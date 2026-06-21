---
name: pst:code-review
description: Code review with worktree-isolated fix verification - every finding must survive a quality gate before being reported
argument-hint: "[PR-number | PR-URL | --local | --preflight | --autofix | --sweep]"
allowed-tools: Bash, Read, Edit, Grep, Glob, Agent, AskUserQuestion
---

# Code Review with Fix Verification

Context-aware code review. Every finding is validated by applying the fix in an isolated
worktree and running quality gates. Findings that break the build, fail tests, or cannot
be applied cleanly are dropped before reporting.

---

## Input Parsing

<arguments> #$ARGUMENTS </arguments>

Modes:

- PR number or URL: GitHub PR mode (post review to PR). Cross-repo: clone to a temp dir.
- `--local`: terminal output only, single pass, no GitHub interaction.
- `--preflight`: multi-round review with auto-fix (min 3, max 5 rounds). Commits verified fixes.
- `--autofix`: fully autonomous -- apply verified fixes + post review per event policy.
- `--sweep`: multi-round autonomous review-and-fix loop (min 2, max 5 rounds).

**Re-review detection:** Check `gh api /repos/{owner}/{repo}/pulls/{N}/reviews` for a prior
review. If one exists, scope diff to changes since that commit; report only critical and
warning findings. Zero criticals + zero warnings: APPROVE; else REQUEST_CHANGES.

---

## Workspace Setup

Skip if `--sweep` or `--preflight` (operate on working directory). Skip if cross-repo
(already cloned to temp dir).

```bash
HEAD_BRANCH=$(gh pr view $N --json headRefName --jq .headRefName)
HEAD_SHA=$(gh pr view $N --json headRefOid --jq .headRefOid)
```

Skip worktree if: current branch matches HEAD_BRANCH, HEAD matches HEAD_SHA, working tree
is clean. Otherwise:

```bash
REPO_ROOT=$(git rev-parse --path-format=absolute --git-common-dir | sed 's|/.git$||')
git fetch origin "$HEAD_BRANCH"
REVIEW_DIR="$REPO_ROOT/.worktrees/review-PR-$N"
git worktree remove --force "$REVIEW_DIR" 2>/dev/null
git worktree add --detach "$REVIEW_DIR" "$HEAD_SHA"
```

Set `REVIEW_WORKTREE=true`. Branch freshness: if stale and migrations present, emit critical
finding; if stale with no migrations, emit warning finding.

---

## Context Gathering

1. Read `CLAUDE.md`, `.context/architecture.md`, `.context/patterns.md`, recent ADRs (cap 10).
2. PR metadata: `gh pr view {N} --json number,title,body,baseRefName,headRefName,url,labels`
   plus `gh pr diff {N}`. Parse unchecked checkboxes (`- [ ] ...`) as verification targets.
3. Commit messages: `git log --oneline {base}...HEAD`.
4. No context available: use AskUserQuestion for minimum context.
5. Pattern inference: sample 2-3 similar files per changed file. Flag deviations only when
   75%+ of sampled files agree on a pattern (tag as "inferred pattern" findings).

---

## Analysis -- Tournament

### Diff-size gate

```bash
LINES_CHANGED=$(gh pr diff $N | grep -cE '^[+-]' || echo 0)
```

- **Small** (fewer than 200 lines): N=1, use Strategy B only. Skip tournament and Opus judge.
- **Medium** (200-500 lines): N=3 tournament.
- **Large** (500+ lines): N=3 tournament.

### Parallel Sonnet agents (N=3)

Spawn 3 **foreground** Sonnet agents in a **single response turn** (do not set
`run_in_background`). Pass the full diff text in each agent prompt. No worktree isolation --
these agents are read-only and must not mutate files.

**Strategy A -- Security-first:** Prioritize OWASP A01-A10 and injection/auth/crypto
findings. Weight critical/high findings 3x. Surface every possible security finding even
if uncertain.

**Strategy B -- Correctness-first:** Lead with logic errors, null-safety violations, race
conditions, off-by-one errors, and type mismatches. De-prioritize style and maintainability.

**Strategy C -- Blast-radius-first:** Trace call chains to score each finding by how many
callers are affected. Rank by blast radius, not severity category. Surface cross-cutting
concerns that touch many files.

Each agent returns findings in exactly this block:

```
---review-result---
STRATEGY: <A|B|C>
FINDING_COUNT: <integer>
FINDINGS:
<JSON array: [{"file":"...","line":"...","severity":"critical|high|medium|low","category":"...","description":"...","fix":"..."}]>
---end-review-result---
```

### Opus judge (foreground, N=3 only)

After all three agents return, spawn one **foreground Opus agent** (`model: opus`). Await
its result before proceeding. Provide all three finding sets and these rules:

**Deduplication:** Two findings are duplicates when they reference the same file and their
line numbers overlap within a 5-line window.

**Keep a finding if:** it appears in 2 or more strategy finding sets, OR its severity is
`critical` in any strategy.

**Confidence scoring:** 1 strategy = confidence 1, 2 strategies = confidence 3,
3 strategies = confidence 5.

**Output:** a merged, ranked JSON finding list with confidence scores, highest first.

### Pre-filter

After the judge (or after Strategy B for N=1), drop findings that are: style nitpicks
mis-classified as warnings, already caught by CI tooling (eslint, tsc, prettier), or
missing a concrete actionable fix. Downgrade mis-classified warnings to nit or drop.

Assign IDs `R{N}` (sequential). Severity: `critical | warning | nit | observation`.
Include file + line range, category, title, problem (1-2 sentences), fix (omit for
`observation`). `observation` is for architectural notes with no concrete fix. Max 2 per
review. Observations do not enter Verification.

---

## Verification

### Invariant (non-negotiable)

Every candidate finding that survives pre-filter **MUST** be verified by its own
isolated-worktree sub-agent that (i) applies the proposed fix and (ii) runs the full
quality-gate suite. The only exception is `observation` severity (no fix to apply).

Spawn per finding:

```
Agent:
  subagent_type: general-purpose
  isolation: worktree
  run_in_background: true
  description: "Verify finding R{N}: {title}"
  prompt: "<self-contained verification instructions>"
```

All agents spawn simultaneously. Each gets its own isolated worktree copy.

### Sub-agent workflow

1. Bootstrap: run `worktree:init` (or `install --frozen-lockfile`) with `|| true`. Carry on.
2. Read target file, trace call graph to system boundaries.
3. Validate against ADRs and inferred patterns.
4. **DISCARD (`DROPPED`) if:** style preference disguised as warning; phantom bug from
   incomplete context; CI would already catch it; over-engineering; fix breaks existing
   tests or API contracts; does not materially affect reliability, correctness, or
   maintainability.
5. Apply the suggested fix. Minimum edit.
6. Run quality gates: `build`, `lint`, `typecheck`, `test`. PASS = exits 0. FAIL = exits
   non-zero when base passed. N/A = exits non-zero on both (record identical-failure
   evidence). At least one gate must reach PASS or proven-N/A; zero runnable gates = DROPPED.
7. Verdict: `VERIFIED` (fix applied + all runnable gates passed or proven-N/A) or `DROPPED`.

After all sub-agents complete: collect results, clean up worktrees. Assert
`VERIFIED + DROPPED == total non-observation candidates`. If the count does not balance,
re-dispatch missing sub-agents before reporting.

---

## Reporting

### Required sections (in order)

1. **Summary** -- max 8 bullets.
2. **Findings** -- table of VERIFIED findings (critical / warning / nit).
3. **Observations** -- body-only prose; omit section if empty.
4. **Dropped during verification** -- one line per DROPPED finding with reason.
5. **Verification integrity** -- `VERIFIED (${V}) + DROPPED (${D}) = ${V+D} non-observation candidates.`

### Review event policy

Never post a bare COMMENT as the terminal event except: (1) self-authored PR (GitHub rejects
APPROVE and REQUEST_CHANGES with 422 on your own PR) or (2) explicit user instruction.

- Any VERIFIED critical or warning: `REQUEST_CHANGES`.
- Otherwise: `APPROVE`.

Detect self-authored: compare `gh api /user --jq .login` with
`gh pr view $N --json author --jq '.author.login'`. Flag self-authored only when both are
non-empty and equal.

### GitHub PR mode

Post via `gh api POST /repos/{owner}/{repo}/pulls/{N}/reviews`. Idempotency guard: skip
POST if most recent review from this user is already at HEAD_SHA. Never POST more than once
per run. Open review URL in browser after posting (open / xdg-open / start fallback chain).

Inline comment format:

````markdown
**R{N}** `{severity}` - {title}

{problem in 1-2 sentences}

**Fix:** {specific change}

<details><summary>Verification Details</summary>

**Blast radius:** {summary} | **Quality gates:** PASSED (build, lint, typecheck, test)

</details>

```suggestion
{code suggestion if applicable}
```
````

### Local mode (`--local`)

Full Analysis + Verification. Terminal output only. No GitHub interaction, no code edits.

### Preflight mode (`--preflight`)

Min 3, max 5 rounds. No AskUserQuestion. Each round: diff, analyze, verify, apply VERIFIED
fixes. Exit after min rounds when 0 criticals + 0 warnings remain. One squashed commit after
all rounds. Terminal: `PREFLIGHT ROUND {N}/{MAX} | Criticals: {n} | Warnings: {n} | Fixed: {list}`.

### Autofix mode (`--autofix`)

Fully autonomous. Apply all VERIFIED fixes in one squashed commit. Post per event policy.
Open browser after posting.

### Sweep mode (`--sweep`)

Min 2, max 5 rounds. Skip nits. Each round commits fixes
(`git commit -m "fix: sweep round {N} findings"`). Exit when 0 criticals after min rounds.

### Conversation resolution

Skip if `--sweep`, `--local`, or `--preflight`. After posting, resolve unresolved threads
via AskUserQuestion (Reply Fixed / Won't Fix / Acknowledged / Skip). Resolve via GraphQL
mutation after replying. Always resolve after replying.

### PR checkbox updates

Skip if `--sweep`, `--local`, `--preflight`, or no checkboxes found. Check off checkboxes
verifiable through static analysis that were not contradicted by a critical or warning
finding. Update via `gh api repos/{owner}/{repo}/pulls/$PR_NUMBER --method PATCH`.

### Worktree cleanup

If `REVIEW_WORKTREE=true`: `git worktree remove --force "$REVIEW_DIR"`. Warn with manual
command on failure.

### Error handling

| Condition                  | Action                                                    |
| -------------------------- | --------------------------------------------------------- |
| 401/403 from GitHub        | Instruct `gh auth login`                                  |
| 422 (invalid line comment) | Remove invalid comments, retry                            |
| 429 (rate limit)           | Wait, retry, fallback to body-only with policy event flag |
| Empty diff                 | Exit with message                                         |
| Sub-agent worktree failure | Verdict DROPPED for that finding. No unverified bypass.   |
| All sub-agents fail        | Abort. Do not post unverified findings.                   |
| Worktree creation fails    | Retry once; abort on second failure with clear error.     |

---

## Output Contract

Every run must emit as its final line:

```
Per-finding verification: ${VERIFIED}/${TOTAL} candidates ran isolated quality gates.
```

TOTAL is non-observation candidates that survived pre-filter. If `VERIFIED + DROPPED < TOTAL`,
abort, re-dispatch missing sub-agents, and re-emit only after every candidate has a verdict.
