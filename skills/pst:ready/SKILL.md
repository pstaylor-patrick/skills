---
name: pst:ready
description: Bring an open PR to merge-ready state — rebase onto the PR base, await CI and auto-fix failures, loop resolve-threads + code-review until clean, re-verify CI, then open in the browser.
argument-hint: "<PR-URL> [--dry-run] [--no-open] [--max-ci-attempts N] [--max-review-rounds N]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Agent, AskUserQuestion, Skill
---

# Bring a PR to Merge-Ready

Take an open GitHub pull request from wherever it is today (behind base, failing CI, unresolved threads, outstanding CHANGES_REQUESTED reviews) and drive it to a merge-ready state without further user interaction.

This skill is pure composition over existing `/pst:*` skills plus one piece of new logic: a bounded CI wait + auto-fix loop. It chains them in the order a human would:

1. Rebase onto the PR's base branch (`pst:rebase`).
2. Wait for CI; when something fails, diagnose and patch until green (new logic here).
3. Address every unresolved review thread (`pst:resolve-threads`).
4. Run a verified-fix code review to catch new issues (`pst:code-review --sweep`).
5. Repeat (3) + (4) until no unresolved threads and no remaining criticals.
6. Re-verify CI is still green after all review-loop commits.
7. Open the PR in the browser so the human can merge.

---

## Input

<arguments> #$ARGUMENTS </arguments>

**Parse arguments:**

- `<PR-URL>` (required) -- full GitHub PR URL, e.g. `https://github.com/owner/repo/pull/42`. Bare PR numbers are rejected; this skill always takes a URL so cross-repo is unambiguous.
- `--dry-run` -- report what would happen at every phase; no pushes, no thread resolutions, no rebase writes, no browser open.
- `--no-open` -- run to completion but skip the browser pop at the end (useful for CI/headless use).
- `--max-ci-attempts N` -- override the default CI auto-fix attempt budget (default `3`).
- `--max-review-rounds N` -- override the default review-loop round cap (default `5`).

**Validate:**

| Condition                                              | Action                                         |
| ------------------------------------------------------ | ---------------------------------------------- |
| No PR URL provided                                     | Stop with usage: `/pst:ready <PR-URL> [flags]` |
| URL does not match `https://github.com/.+/.+/pull/\d+` | Stop: "Provide a full GitHub PR URL."          |
| `gh` not available                                     | Stop: "GitHub CLI (gh) is required."           |
| `git` not available                                    | Stop: "git is required."                       |

---

## Phase 0 -- Intake & Guards

Extract metadata and confirm the PR is actionable.

```bash
PR_URL="$1"
PR_JSON=$(gh pr view "$PR_URL" --json number,url,title,state,isDraft,headRefName,headRefOid,baseRefName,headRepository,repository,mergeable)
PR_NUMBER=$(echo "$PR_JSON" | jq -r .number)
PR_STATE=$(echo "$PR_JSON"  | jq -r .state)
IS_DRAFT=$(echo "$PR_JSON"  | jq -r .isDraft)
HEAD_BRANCH=$(echo "$PR_JSON" | jq -r .headRefName)
HEAD_SHA=$(echo "$PR_JSON"    | jq -r .headRefOid)
BASE_BRANCH=$(echo "$PR_JSON" | jq -r .baseRefName)
PR_OWNER_REPO=$(echo "$PR_URL" | sed -E 's|https://github.com/([^/]+/[^/]+)/pull/.*|\1|')
PR_OWNER=$(echo "$PR_OWNER_REPO" | cut -d/ -f1)
PR_REPO=$(echo  "$PR_OWNER_REPO" | cut -d/ -f2)
```

**Stop conditions:**

| Condition                                            | Action                                                          |
| ---------------------------------------------------- | --------------------------------------------------------------- |
| `PR_STATE` is not `OPEN`                             | Stop: "PR #$PR_NUMBER is $PR_STATE; nothing to ready."          |
| `IS_DRAFT` is `true`                                 | Ask the user (AskUserQuestion) whether to proceed; if no, stop. |
| `mergeable` is `CONFLICTING` and `--dry-run` not set | Proceed -- the rebase phase will surface the conflict.          |

**Recovery check:** If a `.pst-ready-progress.json` exists at the repo root of the working directory chosen in Phase 1, read it. If its `pr_url` matches and no more than 24 hours have passed since its last update, resume from the first phase not in `completed`. Otherwise ignore and start fresh.

---

## Phase 1 -- Workspace Setup (cross-repo capable)

Pattern mirrors `pst:code-review` workspace setup. The objective is to have a clean working tree on the PR's head commit before we do anything else.

1. **Resolve cwd repo identity:**

   ```bash
   CWD_OWNER_REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "")
   ```

2. **Cross-repo branch:** If `CWD_OWNER_REPO != PR_OWNER_REPO`:

   ```bash
   TMPDIR="${TMPDIR:-${TEMP:-/tmp}}"
   WORK_DIR=$(mktemp -d "$TMPDIR/pst-ready-XXXXXX")
   gh repo clone "$PR_OWNER_REPO" "$WORK_DIR" -- --depth=50
   cd "$WORK_DIR"
   gh pr checkout "$PR_NUMBER"
   ```

   Record `WORK_DIR` and `cross_repo=true` in the progress file so resume lands in the same place.

3. **Same-repo branch, clean cwd on PR head:** If current branch matches `$HEAD_BRANCH`, `HEAD` matches `$HEAD_SHA`, and `git status --porcelain` is empty -- work in place. Set `WORK_DIR=$(pwd)`.

4. **Same-repo, different branch or dirty tree:** Create a detached worktree:

   ```bash
   REPO_ROOT=$(git rev-parse --path-format=absolute --git-common-dir | sed 's|/.git$||')
   git fetch origin "$HEAD_BRANCH"
   WORK_DIR="$REPO_ROOT/.worktrees/ready-PR-$PR_NUMBER"
   git worktree remove --force "$WORK_DIR" 2>/dev/null
   git worktree add "$WORK_DIR" "$HEAD_BRANCH"
   cd "$WORK_DIR"
   ```

   (Non-detached here because `pst:rebase` needs a branch to push back to.)

5. **Exclude progress file from git:**

   ```bash
   grep -qxF '.pst-ready-progress.json' .git/info/exclude 2>/dev/null \
     || echo '.pst-ready-progress.json' >> .git/info/exclude
   ```

6. **Write initial progress:**
   ```json
   {
     "pr_url": "...",
     "pr_number": 42,
     "head_branch": "feature/x",
     "base_branch": "main",
     "work_dir": "/abs/path",
     "cross_repo": false,
     "state": "rebase",
     "completed": ["intake", "workspace"],
     "ci_attempts_pass1": 0,
     "ci_attempts_pass2": 0,
     "review_rounds": 0,
     "residual": []
   }
   ```

From this phase forward, **all commands run in `$WORK_DIR`**.

---

## Phase 2 -- Rebase

Delegate entirely to `pst:rebase`, passing the PR base branch explicitly so it does not re-infer:

```
Skill("pst:rebase", "$BASE_BRANCH${DRY_RUN:+ --dry-run}")
```

After the skill returns:

- **Success path:** `pst:rebase` force-pushed with `--force-with-lease`. Capture the new `HEAD_SHA`:
  ```bash
  git fetch origin "$HEAD_BRANCH"
  HEAD_SHA=$(git rev-parse "origin/$HEAD_BRANCH")
  ```
- **Conflict path:** `pst:rebase` will have stopped with conflict output. Surface its output verbatim and halt `pst:ready`. Record `residual: [{phase: "rebase", reason: "unresolved-conflicts"}]` in progress so the user can resume after manual resolution.
- **`--dry-run`:** `pst:rebase` prints the analysis. Continue to Phase 3 in read-only mode.

Mark `rebase` completed.

---

## Phase 3 -- CI Wait + Auto-Fix (Pass 1)

This is the only piece of genuinely new logic. It runs up to `MAX_CI_ATTEMPTS` times.

### 3.1 Wait for CI to settle

```bash
gh pr checks "$PR_NUMBER" --watch --interval 20
```

`--watch` blocks until every required check reaches a terminal state (success/failure/cancelled/skipped). `--interval 20` keeps the poll rate friendly.

### 3.2 Read results

```bash
CHECKS_JSON=$(gh pr checks "$PR_NUMBER" --json name,state,link,bucket,workflow)
```

Categorize by `bucket`:

- `pass` / `skipping` -- ignore.
- `fail` / `cancel` -- collect for fix attempts.
- `pending` -- shouldn't exist after `--watch`; if seen, re-enter 3.1.

**If zero `fail`/`cancel` checks -> Phase 4.**

### 3.3 Diagnose failures

For each failing check:

```bash
RUN_ID=$(gh run list --branch "$HEAD_BRANCH" --limit 20 \
  --json databaseId,name,conclusion,headSha,workflowName \
  --jq ".[] | select(.headSha == \"$HEAD_SHA\" and .workflowName == \"$WORKFLOW\") | .databaseId" \
  | head -1)
LOGS=$(gh run view "$RUN_ID" --log-failed 2>/dev/null | tail -500)
```

Classify from `$LOGS`:

| Signal                                                       | Classification |
| ------------------------------------------------------------ | -------------- |
| `error TS\d+:`, `tsc`, `type`                                | `typecheck`    |
| `ESLint`, `eslint`, `Lint`                                   | `lint`         |
| `FAIL `, `Test Failed`, `vitest`, `jest`                     | `test`         |
| `webpack`, `next build`, `Build failed`, `ENOENT`            | `build`        |
| `429`, `504`, `ECONNRESET`, `Network`, `timeout waiting for` | `infra-flake`  |
| Nothing recognizable                                         | `unknown`      |

### 3.4 Handle each failure

- **`infra-flake` on attempt 1:** `gh run rerun $RUN_ID --failed`. Restart from 3.1 without incrementing the attempt counter. Log a note in progress. Second flake on the same workflow -> treat as real failure.

- **`typecheck` / `lint` / `test` / `build` / `unknown`:** Delegate to a sub-agent in an isolated worktree so the fix is reproduced locally before we push.

  ```
  Agent({
    description: "Auto-fix CI failure: {check name}",
    subagent_type: "general-purpose",
    isolation: "worktree",
    prompt: """
      A CI check named "{check name}" is failing on PR #{PR_NUMBER} at commit {HEAD_SHA}.
      Classification: {typecheck|lint|test|build|unknown}.

      Failed-job log excerpt (last 500 lines):
      <<<
      {LOGS}
      >>>

      Task:
        1. Reproduce the failure locally in this worktree. Use the package manager and
           scripts detected in package.json / pyproject.toml / etc.
        2. Fix it minimally -- no drive-by refactors, no unrelated changes.
        3. Re-run the local equivalent of the failing check to verify the fix.
        4. Commit with message: "fix(ci): {one-line summary}"
        5. Do NOT push. Return a short report: files changed, commit SHA, verification
           command + output.

      If you cannot reproduce locally (e.g., environment-only), say so and return a
      best-effort hypothesis patch with clear caveats.
    """
  })
  ```

  When the sub-agent returns:
  - Cherry-pick its commit onto the real branch in `$WORK_DIR`:
    ```bash
    git fetch "$SUBAGENT_WORKTREE_PATH" HEAD
    git cherry-pick FETCH_HEAD
    ```
    (Fall back to applying the returned diff with `git apply` if the cherry-pick source isn't reachable.)
  - `git push --force-with-lease origin "$HEAD_BRANCH"`
  - Update `HEAD_SHA`.

- **If the sub-agent returns no viable fix for a given failure:** record it in `residual` and continue with the other failures. If every failure in this iteration failed to produce a fix, halt.

### 3.5 Loop

Increment `ci_attempts_pass1`. If < `MAX_CI_ATTEMPTS` and any fixes were applied, return to 3.1. If `MAX_CI_ATTEMPTS` is reached with failures still present, halt with a residual report:

```
Phase 3 stopped after {N} attempts.
Remaining failures:
  - {check name}: {classification}
    Last run: {url}
    Last attempt outcome: {no-repro | patch-applied-but-still-failing | sub-agent-gave-up}

Resume with: /pst:ready $PR_URL  (progress file preserved)
```

In `--dry-run` mode: do **not** invoke sub-agents or push. Print the classifications and the patch each sub-agent _would_ attempt (by running them with `dangerouslyDisableSandbox: false` read-only mode? No -- just skip and report) and continue to Phase 4 in read-only mode.

Mark `ci-wait-1` completed. Record `ci_attempts_pass1` used.

---

## Phase 4 -- Virtuous Review Loop

Up to `MAX_REVIEW_ROUNDS` iterations. Each round has three steps; the loop exits when the PR has stabilized (no unresolved threads, no remaining criticals/warnings, no new commits in the round).

```
Round N:
  A. Skill("pst:resolve-threads", "$PR_URL")
  B. Count unresolved threads afterward (GraphQL query below)
  C. Skill("pst:code-review", "--sweep")
  D. Evaluate exit condition
```

### 4.A Resolve threads

```
Skill("pst:resolve-threads", "$PR_URL${DRY_RUN:+ --dry-run}")
```

This skill already handles parallel worktree verification of reviewer suggestions, applying verified fixes, replying, resolving threads, dismissing CHANGES_REQUESTED reviews, and re-requesting review from humans. It may push one or more commits.

After it returns, re-resolve `HEAD_SHA`:

```bash
git fetch origin "$HEAD_BRANCH"
NEW_HEAD_SHA=$(git rev-parse "origin/$HEAD_BRANCH")
PUSHED_IN_A=$([ "$NEW_HEAD_SHA" != "$HEAD_SHA" ] && echo true || echo false)
HEAD_SHA="$NEW_HEAD_SHA"
```

### 4.B Count unresolved threads

```bash
UNRESOLVED=$(gh api graphql -f query='
{
  repository(owner: "'$PR_OWNER'", name: "'$PR_REPO'") {
    pullRequest(number: '$PR_NUMBER') {
      reviewThreads(first: 100) {
        nodes { isResolved isOutdated }
      }
    }
  }
}' --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false and .isOutdated == false)] | length')
```

### 4.C Code review sweep

```
Skill("pst:code-review", "--sweep${DRY_RUN:+ --dry-run}")
```

`--sweep` is already a bounded multi-round autonomous review-and-fix loop. It prints a final status and may push additional commits. Capture its exit summary -- specifically whether any verified criticals or warnings remain.

After it returns, re-resolve `HEAD_SHA` again:

```bash
git fetch origin "$HEAD_BRANCH"
NEW_HEAD_SHA=$(git rev-parse "origin/$HEAD_BRANCH")
PUSHED_IN_C=$([ "$NEW_HEAD_SHA" != "$HEAD_SHA" ] && echo true || echo false)
HEAD_SHA="$NEW_HEAD_SHA"
```

### 4.D Exit condition

Exit the loop when **all** of:

- `UNRESOLVED == 0`
- `pst:code-review --sweep` reported `0 criticals` and `0 warnings`
- `PUSHED_IN_A == false` and `PUSHED_IN_C == false` (the round settled without touching code)

Otherwise increment `review_rounds` and continue. If `review_rounds == MAX_REVIEW_ROUNDS` without meeting the exit condition, halt and record residual:

```
Phase 4 stopped after {N} rounds.
Residual:
  - {U} unresolved threads
  - {C} code-review criticals / {W} warnings (see last --sweep output)

Resume with: /pst:ready $PR_URL
```

In `--dry-run` mode: pass `--dry-run` through to both sub-skills (both support it). Do not evaluate the "no pushes" exit condition (nothing can push); exit after one round with a preview.

Mark `review-loop` completed. Record `review_rounds` used.

---

## Phase 5 -- CI Wait + Auto-Fix (Pass 2)

Repeat Phase 3 verbatim against the (potentially new) `HEAD_SHA`. Phase 4 may have pushed commits that re-break CI -- this is the final green gate before handing the PR back to the human.

Use the same `MAX_CI_ATTEMPTS` budget, tracked separately as `ci_attempts_pass2` so the progress file stays informative.

If this phase halts with residual failures, emit the same report format as Phase 3, plus a note: "Review-loop commits changed the branch; a fresh CI run failed and could not be auto-fixed."

Mark `ci-wait-2` completed.

---

## Phase 6 -- Open & Summarize

Unless `--no-open` or `--dry-run`:

```bash
gh pr view "$PR_URL" --web
```

Print a final summary to the terminal:

```
/pst:ready complete for PR #{PR_NUMBER}
  Rebase:          onto {BASE_BRANCH}           ✓
  CI (pass 1):     green after {X} attempt(s)   ✓
  Review rounds:   {Y} of {MAX_REVIEW_ROUNDS}   ✓
  CI (pass 2):     green after {Z} attempt(s)   ✓
  URL:             {PR_URL}

Residual: none
```

On success, delete `.pst-ready-progress.json`. On partial completion (halt in Phase 3, 4, or 5), keep it so a plain `/pst:ready $PR_URL` picks up where we left off.

---

## Dry-Run Summary

`--dry-run` flows through the whole pipeline in read-only mode:

- Phase 2: `pst:rebase --dry-run` -- analysis only.
- Phase 3: skip sub-agent fix attempts; print failing checks and their classifications.
- Phase 4: `pst:resolve-threads --dry-run` + `pst:code-review --sweep --dry-run`; report counts only.
- Phase 5: identical to Phase 3 under dry-run.
- Phase 6: skip browser; print what the final summary would look like.

No pushes, no resolutions, no browser pops. Safe to run at any time to see the state of a PR.

---

## Progress File Shape

Written after every phase completes, at `$WORK_DIR/.pst-ready-progress.json`:

```json
{
  "pr_url": "https://github.com/owner/repo/pull/42",
  "pr_number": 42,
  "head_branch": "feature/x",
  "base_branch": "main",
  "head_sha": "{latest}",
  "work_dir": "/abs/path",
  "cross_repo": false,
  "state": "review-loop",
  "completed": ["intake", "workspace", "rebase", "ci-wait-1"],
  "skipped": [],
  "ci_attempts_pass1": 2,
  "ci_attempts_pass2": 0,
  "review_rounds": 1,
  "residual": [],
  "updated_at": "2026-04-24T18:05:00Z"
}
```

---

## Stop Signals

Halt and preserve the progress file when any of:

- Rebase produces conflicts that `pst:rebase` could not auto-resolve.
- `MAX_CI_ATTEMPTS` consumed in Phase 3 or Phase 5 with failures remaining.
- `MAX_REVIEW_ROUNDS` consumed in Phase 4 with unresolved threads or remaining criticals/warnings.
- Sub-agent fix attempts return no viable patch for every failing check in a round.
- `gh` auth fails, `git push --force-with-lease` is rejected, or the PR is closed/merged mid-run.

Every halt prints a clear next-action line; resuming is always `/pst:ready $PR_URL`.

---

## Notes

- **Composition, not reimplementation.** Rebase, thread resolution, and code review live in their own skills. If their behavior changes, this skill inherits the change.
- **Force-push safety.** All pushes use `--force-with-lease`. The skill never uses `--force`.
- **Cross-repo friendly.** Runs from anywhere; if the PR is in a different repo, the skill clones to a temp dir and operates there. The user's cwd is not mutated.
- **Idempotent resume.** The progress file makes a second invocation after a halt skip already-completed phases. This is why every phase writes to it atomically.
