---
name: pst:ready
description: Bring one or many open PRs to merge-ready state -- rebase onto base, await CI and auto-fix failures, loop resolve-threads + code-review until clean, re-verify CI, open in the browser. Multiple PR URLs run in parallel via background agents in isolated worktrees, cross-repo capable. Optional `--auto-merge` (or semantic prompt cues) switches to a sequential ship-the-batch mode that opinionatedly orders the PRs, merges each one, waits for post-merge deploys, and posts a post-merge validation comment per PR.
argument-hint: "<PR-URL> [<PR-URL>...] [--dry-run] [--no-open] [--open-all] [--auto-merge] [--max-parallel N] [--max-ci-attempts N] [--max-review-rounds N] [--max-postmerge-wait-min N]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Agent, AskUserQuestion, Skill
---

# Bring PRs to Merge-Ready

Take one or more open GitHub pull requests from wherever they are today (behind base, failing CI, unresolved threads, outstanding CHANGES_REQUESTED reviews) and drive each to a merge-ready state without further user interaction.

For a **single PR**, run the full pipeline in place (or in a worktree/temp clone for cross-repo). For **multiple PRs without auto-merge**, dispatch each to its own background agent running the same pipeline in an isolated worktree, group PRs by repo to share temp clones where sensible, then aggregate the results at the end. For **multiple PRs with auto-merge active** (see Auto-Merge Mode below), execute sequentially in an opinionated order so each subsequent PR rebases onto the freshly-merged base.

The per-PR pipeline is pure composition over existing `/pst:*` skills plus a few pieces of new logic: a bounded CI wait + auto-fix loop, a post-green PR title/description refresh, an auto-validation pass over the test-plan checkboxes, and -- when auto-merge is on -- a permission-checked merge step followed by post-merge validation that waits for production deploys and other base-branch automations to settle. It chains them in the order a human would:

1. Rebase onto the PR's base branch (`pst:rebase`).
2. Wait for CI; when something fails, diagnose and patch until green (new logic here).
3. Address every unresolved review thread (`pst:resolve-threads`).
4. Run a verified-fix code review to catch new issues (`pst:code-review --sweep`).
5. Repeat (3) + (4) until no unresolved threads and no remaining criticals.
6. Re-verify CI is still green after all review-loop commits.
7. Refresh the PR title and description to describe what actually shipped.
8. Parse the test plan, auto-validate the items that can be validated, post a (pre-merge) validation comment, and tick the boxes that passed.
9. Open the PR in the browser so the human can merge.
10. **Auto-merge (gated)**: if `--auto-merge` is active, the user has merge permission, and the PR is `READY`, merge using the repo's preferred merge method (squash > rebase > merge). Use `--admin` if the user has admin perms; otherwise enable GitHub native auto-merge so the merge fires the moment required checks/approvals clear.
11. **Post-merge validation (auto-merge only)**: wait for workflows triggered by the merge commit on the base branch (deploy pipelines, post-merge tests, smoke tests). Re-run any auto-validatable test-plan items against the merged state, run a health check if the repo advertises one, and post a `Post-merge validation` comment summarising results. This validates the change both before merge (Phase 8) and after merge (Phase 11).

---

## Input

<arguments> #$ARGUMENTS </arguments>

**Parse arguments:**

- `<PR-URL>` (required, one or more) -- full GitHub PR URLs, e.g. `https://github.com/owner/repo/pull/42`. Bare PR numbers are rejected; URLs are always required so cross-repo is unambiguous. Multiple URLs trigger dispatcher mode (see below).
- `--dry-run` -- report what would happen at every phase; no pushes, no thread resolutions, no rebase writes, no browser open. Flows through to every child agent in dispatcher mode.
- `--no-open` -- skip browser pop(s) at the end. In dispatcher mode, suppresses opening any PR.
- `--open-all` -- dispatcher mode only: also open BLOCKED PRs (default opens only READY). Ignored in single-PR mode.
- `--max-parallel N` -- dispatcher mode only: cap concurrent background agents at N. Default `4` to avoid GitHub API throttling. Ignored with 1 URL.
- `--max-ci-attempts N` -- override the default CI auto-fix attempt budget (default `3`). Flows through to every child.
- `--max-review-rounds N` -- override the default review-loop round cap (default `5`). Flows through to every child.
- `--auto-merge` -- after a PR finishes Phase 8 in the `READY` state, run Phase 9 (auto-merge) and Phase 10/Phase 11 (post-merge wait + validation) for it. In multi-PR mode this also forces sequential execution (see Auto-Merge Mode below) so each subsequent PR rebases onto the freshly-merged base. Skipped silently for any PR where the user does not have merge permission -- that PR falls back to the default behaviour (open in browser for human merge).
- `--max-postmerge-wait-min N` -- maximum minutes Phase 11 will wait for post-merge workflows on the base branch to reach a terminal state. Default `20`. After the cap, Phase 11 reports whichever workflows are still in flight as `pending` in the post-merge validation comment and does not block the next PR in the batch.

### Semantic auto-merge detection

`--auto-merge` is a strict opt-in. The flag is the canonical signal. The caller (the parent agent loading this skill) is also expected to set `--auto-merge` when the user's prompt makes batch-merge intent unambiguous. Strong signals to look for in the prompt before invoking the skill:

- "merge them", "merge all of them", "ship them", "ship the batch", "land them", "get them in"
- "auto-merge", "automerge", "no need to wait for approval", "don't wait for approval", "go ahead and merge"
- "process this stack", "drive this batch through", "take these to merged"
- A raw list of PR URLs without any modifier verbs is **not** sufficient -- treat that as the default ready-but-don't-merge mode.

When the prompt is ambiguous (e.g., "wrap these up" -- could mean "ready" or "ready+merge"), the caller should `AskUserQuestion` once before invoking the skill rather than guessing. The skill itself does not infer intent from prompt text -- it only reads the flag.

**Validate:**

| Condition                                         | Action                                                         |
| ------------------------------------------------- | -------------------------------------------------------------- |
| No PR URL provided                                | Stop with usage: `/pst:ready <PR-URL> [<PR-URL>...] [flags]`   |
| Any URL fails `https://github.com/.+/.+/pull/\d+` | Stop with the first offender: "Provide a full GitHub PR URL."  |
| Duplicate URLs in the list                        | De-duplicate silently; log `NOTE: deduped N duplicate URL(s)`. |
| `gh` not available                                | Stop: "GitHub CLI (gh) is required."                           |
| `git` not available                               | Stop: "git is required."                                       |

---

## Dispatch Router

The router runs **before** Phase 0. It chooses between:

- **Single-PR mode** -- exactly 1 URL → execute Phases 0..8 inline (and 9..11 if `--auto-merge`). For one URL, dispatcher and child are the same agent.
- **Dispatcher mode (parallel)** -- 2+ URLs without `--auto-merge` → jump to **Phase D** and skip Phases 0..8 at the top level. Each background child agent runs Phases 0..8 in parallel for its assigned PR. This is the original multi-PR behaviour; nothing changes for batches that only want ready-state, not merge.
- **Dispatcher mode (sequential, auto-merge)** -- 2+ URLs with `--auto-merge` → jump to **Phase D** but execute children **one at a time** in an opinionated merge order. After each child finishes Phases 0..8 with `status == READY`, the dispatcher runs Phase 9 (auto-merge) inline at the dispatcher level for that child, then Phase 11 (post-merge validation) for that PR, before moving on to the next PR in the order. The next PR's child rebases onto a freshly-merged base, so we do not need to pre-stack the worktrees.

---

## Auto-Merge Mode

This is the new shape introduced by `--auto-merge`. Read this once before the dispatcher details below.

### Semantics

- Strict opt-in. Without `--auto-merge`, the skill never merges anything; it ends at Phase 8 (open in browser).
- Permission-checked per repo. For each PR, the dispatcher checks `gh api repos/$OWNER/$REPO --jq '.permissions.admin // .permissions.maintain // .permissions.push'`. PRs in repos where the user has none of those bits skip Phase 9 silently and fall back to the default Phase 8 (open browser, let the human merge). They are reported as `READY (auto-merge skipped: no permission)` in the final matrix, not as `BLOCKED`.
- Sequential by construction (multi-PR). With `--auto-merge` and 2+ URLs, the dispatcher abandons parallelism. Concurrent merges in the same repo would invalidate each others' rebases; concurrent merges across repos are tolerable but not worth the orchestration complexity. Sequential execution is also necessary so the second PR's Phase 2 rebase picks up the first PR's merge commit.
- Single PR with `--auto-merge` is allowed -- runs Phases 0..11 inline.
- Per-PR validation runs **twice**: once pre-merge (Phase 8 -- the existing test-plan validation comment) and once post-merge (Phase 11 -- the new post-merge validation comment).

### Opinionated merge order

When `--auto-merge` is active and 2+ URLs are provided, the dispatcher computes an order **once**, up front. It does not pre-rebase or pre-stack anything; it just decides who goes first.

Inputs gathered per PR:

```bash
gh pr view "$URL" --json number,baseRefName,headRefName,labels,files,additions,deletions,changedFiles
```

Ordering algorithm (stable; deterministic for the same input set):

1. **Hard constraints (topological).** If PR-B's base branch equals PR-A's head branch, A must merge before B. Build the dependency graph from these edges. If a cycle exists (rare, usually means a stale base), report it and stop the auto-merge phase for the affected PRs.
2. **Priority bucket.** Assign each PR to the first bucket that matches:
   1. **Hotfix / security / urgent.** Labels containing any of: `hotfix`, `security`, `urgent`, `incident`, `release-blocker`, `p0`, `p1`.
   2. **Infra / build / CI.** Diff is exclusively under `.github/`, `scripts/ci/`, `terraform/`, `infra/`, `docker*`, `Dockerfile`, `.dockerignore`, `Makefile`, `package.json` (root only), `pnpm-workspace.yaml`, `tsconfig*.json`.
   3. **Schema / migration.** Diff touches `migrations/`, `prisma/schema.prisma`, `drizzle/`, or any `*.sql` file.
   4. **Shared library / utility.** Diff touches files under `packages/*/src/` or `lib/` or `src/lib/` and at least one of those files appears in another PR's diff (file-overlap heuristic -- merging shared changes first reduces conflicts in dependents).
   5. **Feature.** Default bucket: anything else with substantive code changes.
   6. **Docs-only / chore.** All changed files match `*.md`, `docs/`, `README*`, `*.mdx`, `LICENSE*`; or only label `chore`/`docs` is present.
3. **Within bucket: smaller diff first.** Sort by `additions + deletions` ascending, breaking ties by `changedFiles` ascending, then by PR number ascending.
4. **Cross-repo grouping.** Group the resulting order by repo. Process each repo group contiguously; do not interleave repos. The order between repo groups follows the priority of the first PR in each group.
5. **Output.** A flat list of PR URLs in the order they will be processed. Log it before launching anything:

```
Auto-merge order (5 PRs across 3 repos):
  1. owner-a/repo-x  #42  [hotfix]            120 lines changed
  2. owner-a/repo-x  #51  [shared-lib]        340 lines changed
  3. owner-b/repo-y  #7   [feature]            85 lines changed
  4. owner-b/repo-y  #9   [feature]           420 lines changed
  5. owner-c/repo-z  #33  [docs-only]          30 lines changed
```

The order is **advisory and local** -- not pinned to a config file. Patrick can override via `AskUserQuestion` if the dispatcher asks at the start of the run. The dispatcher prompts once if (a) the priority order disagrees with the order in which URLs were passed, or (b) cross-repo dependencies are detected in the diffs (e.g., one PR adds an API consumed by another PR). If the user says "use my order", the URL-arg order wins and topological hard constraints are still respected.

### Sequential execution flow

For each PR in the computed order:

1. Dispatcher launches the child agent for this PR (worktree pre-created as in Phase D.4) and waits for it. No `--max-parallel`; concurrency is 1.
2. Child returns `PST_READY_CHILD_RESULT` with `status`.
3. If `status == READY` and `--auto-merge` and the user has merge permission:
   1. Dispatcher runs **Phase 9** at its level for this PR.
   2. Dispatcher runs **Phase 11** at its level for this PR (waits for post-merge workflows; posts validation comment).
4. If `status != READY` (BLOCKED / SKIPPED / ERROR) and `--auto-merge`: dispatcher decides whether to continue with the next PR or stop the whole batch. Default: **continue**, but mark every subsequent PR's status as `WILL-RETRY-AFTER-FIX` if they share files with the blocked PR. The user can pass `--auto-merge-stop-on-block` (future flag, not in this version) to abort -- for now, continuing is the rule.
5. Move to the next PR in the order. Its Phase 2 (rebase) will pick up any new merges automatically.

### Stop signals specific to auto-merge

The dispatcher halts the whole auto-merge batch only when:

- A merge fails for a reason other than permissions (e.g., branch protection requires a status check that is genuinely failing, or the head SHA moved between Phase 8 and Phase 9). Report the affected PR and continue with siblings -- a single bad merge does not abort the rest, but a pattern of repeated failures (≥ 2 in a row across different PRs) does abort.
- Phase 11's post-merge validation surfaces a deploy failure on a shared base branch and the next PR in the batch targets that same base branch. In this case stop, surface the failure prominently, and require the user to acknowledge before continuing.

---

## Phase D -- Dispatcher (multi-PR mode)

**Runs only when 2+ URLs are provided.** The dispatcher does no pipeline work itself -- it plans, launches, and aggregates.

### D.1 Fetch metadata for every URL

For each URL in parallel (`gh pr view` calls are independent), collect:

```bash
gh pr view "$URL" --json number,url,title,state,isDraft,headRefName,headRefOid,baseRefName,mergeable
```

If any URL returns `state != OPEN`, record it and continue; that PR will be reported as `SKIPPED (closed|merged|draft)` in the final matrix but does not block the other PRs.

### D.2 Group by repository

Extract `owner/repo` from each URL. Bucket PRs into groups:

- **Group A -- cwd-repo group:** PRs whose `owner/repo` matches the current working directory's repo (via `gh repo view --json nameWithOwner --jq .nameWithOwner`). Zero or one group of this kind. These children use worktrees inside the current repo: `$REPO_ROOT/.worktrees/ready-PR-<N>`.
- **Group B..Z -- foreign-repo groups:** One group per distinct `owner/repo` not matching cwd. For each such group, the dispatcher creates **one** temp clone shared across all PRs in that group:

  ```bash
  TMPDIR="${TMPDIR:-${TEMP:-/tmp}}"
  CLONE_DIR=$(mktemp -d "$TMPDIR/pst-ready-<owner>-<repo>-XXXXXX")
  gh repo clone "<owner>/<repo>" "$CLONE_DIR" -- --depth=200
  ```

  Children inside this group use worktrees inside `$CLONE_DIR`: `$CLONE_DIR/.worktrees/ready-PR-<N>`.

  Depth 200 (vs. 50 used by the single-PR cross-repo path) because multiple PRs in the same repo are more likely to collectively reach further back in history; `gh pr checkout` will deepen on demand anyway.

Log the grouping summary:

```
Dispatching 5 PRs across 3 repo(s):
  cwd (owner-a/repo-x):  #42, #51
  temp clone owner-b/repo-y:  #7, #9
  temp clone owner-c/repo-z:  #33
```

### D.3 Write dispatcher progress

At the top of the caller's cwd, write `.pst-ready-dispatcher.json` (excluded from git the same way child progress files are):

```json
{
  "started_at": "<iso8601>",
  "urls": ["https://.../pull/42", "..."],
  "flags": {
    "dry_run": false,
    "open_all": false,
    "max_parallel": 4,
    "max_ci_attempts": 3,
    "max_review_rounds": 5
  },
  "groups": [
    {
      "owner_repo": "owner-a/repo-x",
      "clone_dir": null,
      "cwd_group": true,
      "prs": [42, 51]
    },
    {
      "owner_repo": "owner-b/repo-y",
      "clone_dir": "/tmp/pst-ready-owner-b-repo-y-abc123",
      "cwd_group": false,
      "prs": [7, 9]
    }
  ],
  "children": []
}
```

### D.4 Prepare child worktrees

For each PR assigned to a group, the dispatcher pre-creates its worktree before spawning the child agent, so each child agent receives a ready-to-use path:

```bash
# Inside each group's repo root ($REPO_ROOT for cwd group, $CLONE_DIR for foreign groups)
git fetch origin pull/$N/head:refs/pst-ready/pr-$N 2>/dev/null \
  || gh pr checkout "$N" -b "pst-ready-pr-$N"  # fallback if raw fetch fails

WORKTREE_PATH="<group-root>/.worktrees/ready-PR-$N"
git worktree remove --force "$WORKTREE_PATH" 2>/dev/null
git worktree add "$WORKTREE_PATH" "refs/pst-ready/pr-$N"
```

Rationale: the dispatcher does worktree creation, not the child, so that the child agent's `isolation: "worktree"` budget is preserved for its own scratch work (sub-agents inside the child Phase 3 still get their own isolated worktrees for CI fixes).

### D.4.5 Compute auto-merge order (auto-merge mode only)

If `--auto-merge` is set, run the **Opinionated merge order** algorithm from the Auto-Merge Mode section against the PRs collected in D.1. Persist the resulting order in `.pst-ready-dispatcher.json` under a top-level `auto_merge_order` array of PR URLs. If the algorithm prompts the user to override (URL-arg order disagrees with priority order, or cross-repo dependencies detected), do that prompt here -- once, before any child is launched.

Also probe each PR's repo for merge permission and cache the result in the dispatcher progress under `merge_permissions: { "owner/repo": "admin" | "maintain" | "push" | "none" }`. PRs whose repo resolves to `none` will skip Phase 9; record that in the matrix at end-of-run.

### D.5 Launch background agents

In **parallel mode** (no `--auto-merge`), respect `--max-parallel N` (default 4) and spawn children in batches. In **sequential mode** (`--auto-merge` active), force concurrency to 1 and follow the order computed in D.4.5 -- after each child returns, run Phase 9 + Phase 11 at the dispatcher level (see the Auto-Merge Mode section) before launching the next child.

For each child:

```
Agent({
  description: "pst:ready PR #<N> (<owner>/<repo>)",
  subagent_type: "general-purpose",
  run_in_background: true,
  prompt: "<see child prompt template below>"
})
```

If the number of PRs exceeds `--max-parallel`, queue the overflow and launch replacements as earlier children complete (you will be notified of completion per Agent-tool semantics).

**Child prompt template:**

```
You are a focused sub-agent running the per-PR pipeline of /pst:ready for ONE pull request.

Assigned PR:        {PR_URL}
Working directory:  {WORKTREE_PATH}  (already created, on the PR head, clean tree)
Base branch:        {BASE_BRANCH}
Head SHA:           {HEAD_SHA}
Group root:         {GROUP_ROOT}  (shared with sibling PRs in the same repo -- treat as read-only from other siblings' perspective)
Flags to honor:     --max-ci-attempts={N} --max-review-rounds={M} {--dry-run?}

Your job is to execute Phases 0..8 from the /pst:ready single-PR pipeline entirely inside {WORKTREE_PATH}. DO NOT open the browser -- the dispatcher handles that after it collects all children. DO NOT write to the dispatcher's progress file. **DO NOT run Phase 9 (auto-merge) or Phase 11 (post-merge validation)** -- those are dispatcher-only phases. Stop after Phase 8 regardless of whether the parent invocation passed `--auto-merge`.

Write your own progress file at:
  {WORKTREE_PATH}/.pst-ready-progress.json
so a dispatcher resume can see per-PR state.

When you are done, return a single JSON object on the final line of your output in this exact shape:

  PST_READY_CHILD_RESULT={
    "pr_url": "{PR_URL}",
    "pr_number": <N>,
    "status": "READY" | "BLOCKED" | "SKIPPED",
    "rebase": "success" | "skipped-up-to-date" | "conflict",
    "ci_pass1_attempts": <int>,
    "review_rounds": <int>,
    "ci_pass2_attempts": <int>,
    "pr_refresh": "updated" | "unchanged" | "skipped" | "failed",
    "test_plan": { "validated": <int>, "failed": <int>, "manual": <int> },
    "residual": [ ... phase-scoped residual entries ... ],
    "final_head_sha": "<sha>",
    "notes": "optional short string"
  }

Do not emit long progress narration -- keep the response concise. Follow the
/pst:ready single-PR Phases 0..8 exactly as documented.
```

### D.6 Collect and aggregate

As children complete, parse each child's `PST_READY_CHILD_RESULT={...}` line and append to `children` in the dispatcher progress file.

Once all children have reported, classify:

- `READY`: `status == "READY"` and `residual` is empty. (In auto-merge mode this is the precondition for Phase 9.)
- `MERGED`: auto-merge mode only -- child returned `READY`, the dispatcher then ran Phase 9 successfully and Phase 11 finished without surfacing a hard failure.
- `MERGED-WITH-WARNINGS`: auto-merge mode only -- merged successfully, but Phase 11 surfaced post-merge issues (deploy failure, post-merge test failures, health check failures). The PR is merged; the warnings live in the post-merge validation comment.
- `READY (auto-merge skipped: no permission)`: auto-merge mode only -- the PR reached `READY` but the user lacked merge permission on its repo. Phase 9/11 were skipped; the browser was opened so a human can finish.
- `BLOCKED`: `status == "BLOCKED"` -- child halted with residual findings or unfixable CI.
- `SKIPPED`: `status == "SKIPPED"` -- PR was closed/merged/draft.
- `ERROR`: child agent itself crashed (no parsable `PST_READY_CHILD_RESULT` line) -- record the last 20 lines of its output for the matrix.
- `MERGE-FAILED`: auto-merge mode only -- Phase 9 attempted but failed (e.g., branch protection block, head moved). The PR is still in `READY` state on GitHub; report what blocked the merge.

### D.7 Open browsers (respect flags)

Unless `--no-open`:

- Default (no `--auto-merge`): open only `READY` PRs: `for url in ${ready_urls[@]}; do gh pr view "$url" --web; done`
- `--open-all`: open `READY` and `BLOCKED` PRs (skip `SKIPPED` and `ERROR`).
- With `--auto-merge`: do **not** open `MERGED` or `MERGED-WITH-WARNINGS` PRs (they're done -- nothing for the human to do in the browser). Open `READY (auto-merge skipped: no permission)`, `BLOCKED`, and `MERGE-FAILED` PRs by default; `--open-all` additionally includes `READY` (which in auto-merge mode would be unusual). `--no-open` still suppresses everything.

### D.8 Print final matrix

Without `--auto-merge`:

```
/pst:ready dispatch complete: <N> PRs across <M> repo(s)

  owner-a/repo-x  #42  READY     rebased ✓  CI 1 attempt ✓  reviews clean ✓  CI 1 attempt ✓  opened
  owner-a/repo-x  #51  BLOCKED   rebased ✓  CI 3 attempts → residual typecheck in apps/web/src/auth.ts
  owner-b/repo-y  #7   READY     rebased (up-to-date)  CI 1 attempt ✓  reviews clean ✓  opened
  owner-b/repo-y  #9   SKIPPED   PR is MERGED; nothing to ready.
  owner-c/repo-z  #33  ERROR     child agent crashed -- see /tmp/pst-ready-children/PR-33.log

Temp clones preserved for resume:
  /tmp/pst-ready-owner-b-repo-y-abc123
  /tmp/pst-ready-owner-c-repo-z-def456
```

With `--auto-merge` (sequential):

```
/pst:ready --auto-merge complete: <N> PRs across <M> repo(s) (sequential)

Order:
  1. owner-a/repo-x  #42  [hotfix]      MERGED                  squash · post-merge ✓
  2. owner-a/repo-x  #51  [shared-lib]  MERGED-WITH-WARNINGS    squash · deploy job failed -- see comment
  3. owner-b/repo-y  #7   [feature]     READY (no permission)   browser opened for human merge
  4. owner-b/repo-y  #9   [feature]     BLOCKED                 review-loop residual: 2 unresolved threads
  5. owner-c/repo-z  #33  [docs-only]   MERGED                  squash · no post-merge workflows

Post-merge validation comments posted on:
  #42, #51, #33

Temp clones preserved for resume:
  /tmp/pst-ready-owner-b-repo-y-abc123
```

### D.9 Cleanup vs. resume

- On full success: delete `.pst-ready-dispatcher.json` and the temp clones. "Full success" means every PR finished in one of: `READY`, `SKIPPED`, `MERGED`, or `MERGED-WITH-WARNINGS` (the warning is captured in the PR comment, not lost).
- On any `BLOCKED` / `ERROR` / `MERGE-FAILED` / `READY (no permission)`: preserve both files. A subsequent `/pst:ready` invocation with the same URL set reads `.pst-ready-dispatcher.json`, reuses the group clones and worktrees, and only re-dispatches children whose status is not in the "done" set above. Already-`MERGED` PRs are noted in the resume log and skipped.

### D.10 Dry-run in dispatcher mode

`--dry-run` at the dispatcher level:

- Skip cloning foreign repos; use `gh pr view`-only analysis.
- Skip creating worktrees.
- Report the planned group/assignment matrix and exit. Do not spawn child agents.
- With `--dry-run --auto-merge`: also compute and print the opinionated merge order, the per-repo merge-permission probe, the merge method that would be selected per repo, and the (empty) deploy-workflow detection summary. Do not merge. Do not enable native auto-merge.

---

## Per-PR Pipeline (Phases 0-11)

Phases 0-8 are the per-PR readiness pipeline and run either inline (single-PR mode) or inside each dispatched child agent (multi-PR mode). Their behaviour is identical in both cases.

Phases 9 (auto-merge) and 11 (post-merge validation) only run when `--auto-merge` is set. In single-PR mode they run inline after Phase 8. In multi-PR mode they run at the **dispatcher level** for each child after that child returns `READY` -- never inside the child agent itself. Phase 10 is currently reserved (see its section).

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

(Recovery-from-progress-file logic is deferred to the end of Phase 1, once `$WORK_DIR` is resolved -- see Phase 1 step 7.)

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

7. **Recovery from a prior run:** Now that `$WORK_DIR` is known, look for an existing progress file at `$WORK_DIR/.pst-ready-progress.json` from a previous invocation. If one exists AND its `pr_url` matches AND its `updated_at` is within the last 24 hours, read its `completed` list and resume from the first phase **not** in that list. Do not re-run Phase 2 if `"rebase"` is already completed, etc. If the file is missing, stale, or for a different PR, overwrite with the fresh progress from step 6.

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
        5. Do NOT push. Return a machine-readable report on the last line in this
           exact shape (single JSON object, no prose after it):

             CI_FIX_RESULT={
               "status": "fixed" | "no-fix",
               "worktree_path": "/abs/path/to/this/worktree",
               "commit_sha": "<sha of the fix commit, or null if status != fixed>",
               "files_changed": ["path/a.ts", "path/b.ts"],
               "verification_cmd": "pnpm run typecheck",
               "verification_exit": 0,
               "notes": "optional short string -- caveats, env-only hypothesis, etc."
             }

      If you cannot reproduce locally (e.g., environment-only), set status to "no-fix"
      and put the best-effort hypothesis in notes. Always return the JSON object.
    """
  })
  ```

  The orchestrator parses the `CI_FIX_RESULT={...}` line from the sub-agent's final
  message. It uses `worktree_path` and `commit_sha` as the source of truth -- no
  implicit variables.

  When `status == "fixed"`, pull the commit onto the real branch in `$WORK_DIR`:

  ```bash
  # worktree_path and commit_sha come from the parsed CI_FIX_RESULT JSON above
  git fetch "$worktree_path" "$commit_sha"
  git cherry-pick "$commit_sha"
  ```

  If `git fetch` from the worktree path fails (e.g., the worktree was cleaned up
  before we could reach it), fall back to requesting the sub-agent's diff inline
  and applying with `git apply`. Either way, follow with:

  ```bash
  git push --force-with-lease origin "$HEAD_BRANCH"
  HEAD_SHA=$(git rev-parse "origin/$HEAD_BRANCH")
  ```

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

In `--dry-run` mode: do **not** invoke sub-agents or push. Report each failing check with its classification and continue to Phase 4 in read-only mode.

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

## Phase 6 -- Refresh PR Title and Description

This phase runs **only after CI pass 2 is green** (i.e., after Phase 5 has cleared). The branch is now the finished product; the PR body should describe what actually shipped, not what the branch looked like at opening.

### 6.1 Gather the source material

```bash
PR_BODY=$(gh pr view "$PR_NUMBER" --json body --jq .body)
PR_TITLE=$(gh pr view "$PR_NUMBER" --json title --jq .title)
COMMITS=$(git log --oneline "origin/$BASE_BRANCH..HEAD")
DIFF_STAT=$(git diff --stat "origin/$BASE_BRANCH..HEAD")
FILE_LIST=$(git diff --name-only "origin/$BASE_BRANCH..HEAD")
```

Read any top-of-file context that informs how this PR should be described:

- Project `CLAUDE.md` / `AGENTS.md` for house style (e.g., "keep PR titles under 70 chars", "always include a Test Plan section").
- `.context/` ADRs, architecture notes, patterns files -- surface relevant constraints.
- For each non-trivial changed file, read the diff hunks to understand intent.

### 6.2 Regenerate title and body

**Title:** under 70 characters, imperative mood, matches the narrative of the final commits (not just the initial intent). If the existing title already accurately reflects what shipped, keep it verbatim.

**Body sections (in this order):**

1. **Summary** -- 3-6 bullets covering what actually changed by end of branch, written from the current HEAD's perspective.
2. **Implementation Notes** -- key design decisions, invariants, or tradeoffs worth flagging to reviewers. Skip if nothing notable.
3. **Test plan** -- verifiable claims. Mix of auto-checkable items (code-level assertions, CI green, command outputs) and manual items (end-to-end scenarios, UI validation). Use `- [ ]` checkboxes; Phase 7 will tick the auto-validatable ones.

Preserve any existing `- [x]` items: text-match each checked item in the old body to the new body. If the new body contains the same item (same text, minus leading checkbox), keep it ticked. Never un-check a box the user or a prior validation run already ticked.

### 6.3 Update the PR

```bash
gh api "repos/$PR_OWNER/$PR_REPO/pulls/$PR_NUMBER" \
  --method PATCH \
  --field title="$NEW_TITLE" \
  --field body="$NEW_BODY"
```

If `gh pr edit` fails with a `read:org` scope error (common with restricted PATs), use the `gh api` REST path above as the primary -- it only needs `repo` scope.

Mark `refresh-pr` completed.

### 6.4 Dry-run behavior

In `--dry-run`: print the proposed title and body diff vs. the current PR, but do not `PATCH`.

---

## Phase 7 -- Test Plan Validation

This phase runs **only after Phase 6 has refreshed the PR body**, so it always validates against the latest test plan.

### 7.1 Parse the test plan

```bash
PR_BODY=$(gh pr view "$PR_NUMBER" --json body --jq .body)
```

Locate a heading that matches `^#+\s*Test\s*plan\s*$` (case-insensitive; also matches "Test Plan", "TEST PLAN"). Collect every `- [ ]` checkbox **under that heading** (until the next heading or end of body). Preserve each checkbox's position index so we can patch them in order later.

If no Test-plan heading is found OR no unchecked items exist, log `Test plan: nothing to validate` and skip to Phase 8.

### 7.2 Classify each item

For each unchecked checkbox, decide one of:

- **auto-validatable** -- the item describes something testable via code analysis, shell command, or PR state query. Signals: mentions of "build", "lint", "typecheck", "test", "format", "CI is green", specific file/symbol names, behaviour claims about the diff (e.g., "no regressions in auth", "handles null case in foo()").
- **manual-only** -- the item requires runtime/environment/stakeholder action. Signals: mentions of "browser", "staging", "UI looks", "stakeholder approval", "end-to-end scenario requiring a real second PR", "test in production".
- **ambiguous** -- can't confidently decide from the text alone. Treat as manual-only to be safe; do not validate, do not check.

### 7.3 Validate the auto-validatable ones

For each auto-validatable item, run the smallest sufficient check:

| Item kind                                                          | How to validate                                                                                                                      |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| "build passes" / "lint passes" / "typecheck passes" / "tests pass" | Run the repo's corresponding script; require exit 0. If script is missing, mark as manual-only with reason.                          |
| "CI is green" / "all checks passing"                               | `gh pr checks $PR_NUMBER --json bucket --jq 'all(.[]; .bucket == "pass" or .bucket == "skipping")'`. Require `true`.                 |
| "format is clean"                                                  | `pnpm run format:check` (or detected equivalent); exit 0.                                                                            |
| "no regressions in $subsystem"                                     | Confirm no files under relevant paths are newly failing existing tests. Inspect diff to show touched files + existing test coverage. |
| "$file contains $symbol / handles $case"                           | `grep` for the claim in the diff or current file contents; require match.                                                            |
| "no em dashes" / "no AI slop"                                      | Run `bash scripts/lint-no-emdash.sh` or the equivalent repo tooling; exit 0.                                                         |
| "rebased onto $base"                                               | `git merge-base --is-ancestor origin/$BASE_BRANCH HEAD`; exit 0.                                                                     |
| Anything else                                                      | Attempt to derive a minimal verification command from the text; if none obvious, demote to manual-only.                              |

Record each result as: `validated-pass` (check ran, exit 0), `validated-fail` (check ran, non-zero), or `demoted-manual` (couldn't derive a check).

### 7.4 Post the validation comment

Post **one** comment to the PR (not one per item) using `gh pr comment`. Shape:

```markdown
## Test plan validation

Ran against commit `{HEAD_SHA[:12]}` on `{HEAD_BRANCH}`.

**Auto-validated (checked off):** {N}

- `<checkbox text>` -- {one-line evidence, e.g., "pnpm run lint exited 0"}
- ...

**Failed validation (left unchecked):** {N}

- `<checkbox text>` -- {one-line failure summary + log excerpt if short}
- ...

**Manual verification required (left unchecked):** {N}

- `<checkbox text>` -- {why it can't be auto-checked, e.g., "requires a real second PR in another repo"}
- ...
```

If all three counts are 0, skip posting; just log `Test plan validation: no items to report`.

### 7.5 Tick the validated-pass boxes

Refetch the PR body (it may have changed since Phase 6 if an automation raced us), find each `validated-pass` checkbox by text, and replace its `- [ ]` with `- [x]`. Process from highest index to lowest to keep earlier positions stable.

```bash
gh api "repos/$PR_OWNER/$PR_REPO/pulls/$PR_NUMBER" \
  --method PATCH \
  --field body="$UPDATED_BODY"
```

Do not touch `validated-fail` or `manual-only` items -- the reviewer needs to see what's pending.

Mark `test-plan` completed. Record `test_plan: { validated, failed, manual }` counts in the progress file.

### 7.6 Dry-run behavior

In `--dry-run`: parse and classify as above, print the would-be comment and the would-be checkbox diff, but do not post or `PATCH`.

---

## Phase 8 -- Open & Summarize

Browser open is conditional. Skip if `--no-open` or `--dry-run`. Also skip if `--auto-merge` is active **and** the user has merge permission **and** the PR is `READY` -- there is nothing for a human to do; Phase 9 will merge it. In all other cases (including auto-merge-but-no-permission, BLOCKED, etc.), open:

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
  PR refresh:      title + description updated  ✓
  Test plan:       {V} validated / {F} failed / {M} manual
  URL:             {PR_URL}

Residual: none
```

On success without `--auto-merge`, delete `.pst-ready-progress.json`. On partial completion (halt in Phase 3, 4, 5, 6, or 7), keep it so a plain `/pst:ready $PR_URL` picks up where we left off.

With `--auto-merge`, do **not** delete the progress file here -- Phase 9 and Phase 11 still need it. The progress file is deleted at the end of Phase 11 instead.

---

## Phase 9 -- Auto-Merge (gated)

Runs **only when** `--auto-merge` is set, the prior phases reached `READY`, and the user has merge permission on the PR's repo. Skipped silently otherwise; the PR ends at Phase 8 in those cases.

In multi-PR mode this phase runs at the dispatcher level (after the child returns), not inside the child agent. In single-PR mode it runs inline. Either way the steps are identical.

### 9.1 Permission probe

```bash
PERM=$(gh api "repos/$PR_OWNER/$PR_REPO" --jq '.permissions.admin // .permissions.maintain // .permissions.push' 2>/dev/null)
case "$PERM" in
  true|admin)    HAS_PERM=true; IS_ADMIN=true ;;
  maintain|push) HAS_PERM=true; IS_ADMIN=false ;;
  *)             HAS_PERM=false; IS_ADMIN=false ;;
esac
```

If `HAS_PERM=false`, log `Phase 9 skipped for #$PR_NUMBER: no merge permission on $PR_OWNER_REPO`, mark the PR's dispatcher status as `READY (auto-merge skipped: no permission)`, and (per Phase 8) make sure the browser was opened. Return.

### 9.2 Detect allowed merge methods

```bash
MERGE_METHODS=$(gh api "repos/$PR_OWNER/$PR_REPO" --jq '{squash: .allow_squash_merge, merge: .allow_merge_commit, rebase: .allow_rebase_merge}')
SQUASH=$(echo "$MERGE_METHODS" | jq -r '.squash')
MERGE=$(echo  "$MERGE_METHODS" | jq -r '.merge')
REBASE=$(echo "$MERGE_METHODS" | jq -r '.rebase')
```

Pick a method in this preference order:

1. `--squash` if `SQUASH == true` (default for our repos -- single commit on base).
2. `--rebase` if `REBASE == true` (preserves multi-commit history without a merge commit).
3. `--merge` otherwise (last resort -- creates a merge commit).

### 9.3 Merge

```bash
# Re-verify HEAD didn't move while we were collecting state
LATEST_HEAD=$(gh pr view "$PR_NUMBER" --json headRefOid --jq .headRefOid)
if [ "$LATEST_HEAD" != "$HEAD_SHA" ]; then
  echo "HEAD moved between Phase 8 and Phase 9 ($HEAD_SHA -> $LATEST_HEAD); aborting merge."
  # Mark dispatcher status MERGE-FAILED and continue with next PR.
  return
fi

if [ "$IS_ADMIN" = "true" ]; then
  # Admin path: merge immediately, bypassing required reviews/checks the user explicitly waived.
  gh pr merge "$PR_URL" $METHOD --admin --delete-branch
else
  # Non-admin path: enable native auto-merge so GitHub merges as soon as protections clear.
  # Required checks should already be green from Phase 5; this mostly handles "1 approval required" cases.
  gh pr merge "$PR_URL" $METHOD --auto --delete-branch || gh pr merge "$PR_URL" $METHOD --delete-branch
fi
```

Notes:

- `--admin` is the explicit "I have permission and don't want to wait for approval" path the user asked for. Only used when the API confirms the user has admin perms on the repo.
- `--delete-branch` cleans up the head branch automatically. Safe because the branch is now merged; if a teammate also has it checked out they will get a normal "branch deleted on remote" notice.
- Branch protection that requires status checks the bot cannot satisfy (e.g., a manual gate) results in `gh pr merge` returning a non-zero exit status. Capture that, classify the PR as `MERGE-FAILED`, and surface the gh error verbatim.

### 9.4 Capture merge metadata

```bash
sleep 2  # let GitHub propagate
MERGE_INFO=$(gh pr view "$PR_NUMBER" --json mergedAt,mergeCommit,state)
MERGE_COMMIT=$(echo "$MERGE_INFO" | jq -r '.mergeCommit.oid // empty')
PR_STATE=$(echo "$MERGE_INFO" | jq -r .state)
if [ "$PR_STATE" != "MERGED" ] || [ -z "$MERGE_COMMIT" ]; then
  # Native auto-merge may still be pending. Poll for up to 5 minutes.
  for i in $(seq 1 30); do
    sleep 10
    MERGE_INFO=$(gh pr view "$PR_NUMBER" --json mergedAt,mergeCommit,state)
    PR_STATE=$(echo "$MERGE_INFO" | jq -r .state)
    [ "$PR_STATE" = "MERGED" ] && break
  done
fi
```

Record `merge_commit_sha`, `merge_method`, `merged_at`, and `merged_via` (`admin` or `auto`) in the progress file. Mark `auto-merge` completed.

### 9.5 Dry-run

`--dry-run` short-circuits this phase: print the would-be merge command, the chosen method, the permission probe result, and exit Phase 9 without merging.

---

## Phase 10 -- Reserved

Reserved -- placeholder for future "post-merge cleanup" logic (e.g., closing related issues, posting changelog entries). Currently a no-op so that Phase 11 stays a stable, prominent number for the post-merge validation comment.

---

## Phase 11 -- Post-Merge Validation

Runs **only after Phase 9 completed with status `MERGED`**. Validates the change against the freshly-merged base branch and posts a second validation comment on the (now-merged) PR. This is the post-merge counterpart to Phase 7's pre-merge validation comment.

The phase has a hard wall-clock budget of `--max-postmerge-wait-min` (default 20 minutes) so a slow deploy never holds up the next PR in a sequential auto-merge batch.

### 11.1 Detect post-merge workflows

After the merge commit lands on `$BASE_BRANCH`, GitHub may trigger workflows whose `event` is `push` (the merge commit pushed) or `workflow_dispatch` (downstream automation):

```bash
# Wait briefly for runs to register
sleep 10
POST_RUNS=$(gh run list --branch "$BASE_BRANCH" --limit 30 \
  --json databaseId,name,status,conclusion,headSha,event,workflowName,url \
  --jq "[.[] | select(.headSha == \"$MERGE_COMMIT\")]")
```

If `POST_RUNS` is empty after 60 seconds of polling, treat the merge as having no post-merge workflows. Record `post_merge_workflows: []` and proceed to 11.3.

### 11.2 Wait for terminal states (bounded)

```bash
DEADLINE=$(($(date +%s) + 60 * MAX_POSTMERGE_WAIT_MIN))
while [ $(date +%s) -lt $DEADLINE ]; do
  POST_RUNS=$(gh run list --branch "$BASE_BRANCH" --limit 30 \
    --json databaseId,name,status,conclusion,headSha,event,workflowName,url \
    --jq "[.[] | select(.headSha == \"$MERGE_COMMIT\")]")
  PENDING=$(echo "$POST_RUNS" | jq '[.[] | select(.status != "completed")] | length')
  [ "$PENDING" = "0" ] && break
  sleep 30
done
```

Categorize each run by `conclusion`:

- `success` / `skipped` / `neutral` -- pass.
- `failure` / `cancelled` / `timed_out` / `action_required` -- fail.
- still `pending` after deadline -- record as `pending`; do not block.

Detect deploy-style workflows by name match (`deploy`, `release`, `production`, `staging`) and label them in the comment so reviewers see them prominently.

### 11.3 Run the post-merge auto-validatable checks

For each Phase 7 `validated-pass` item that was a "still applies after merge" assertion (e.g., "CI is green", "lint passes", "rebased onto main"), re-run it against the merged state inside `$WORK_DIR` (which has already been updated to track the new base via Phase 2 of the next sibling, OR locally fetched if this is the only PR). Items that are intrinsically pre-merge (e.g., "this branch is rebased onto main") are skipped here -- they do not apply post-merge.

Optional repo-advertised health check: if the repo's `package.json` has a `scripts.healthcheck`, or the repo's CLAUDE.md / AGENTS.md documents a health URL, hit it and record the response code:

```bash
HEALTH_URL=$(grep -hE 'HEALTHCHECK_URL|healthcheck.url' AGENTS.md CLAUDE.md README.md 2>/dev/null \
  | grep -oE 'https?://[^ "]+' | head -1)
if [ -n "$HEALTH_URL" ]; then
  HEALTH_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$HEALTH_URL" || echo "000")
fi
```

### 11.4 Post the post-merge validation comment

One comment per PR (not one per workflow):

```markdown
## Post-merge validation

Merged at `{MERGE_COMMIT[:12]}` via `{MERGE_METHOD}` (`{merged_via}`). Base branch: `{BASE_BRANCH}`.

**Post-merge workflows:** {Pass} passed / {Fail} failed / {Pending} pending (deadline: {N}m)

- ✅ `{workflow name}` -- {duration} -- {url}
- ❌ `{workflow name}` -- failed -- {url}
- ⏳ `{workflow name}` -- still pending after {N}m -- {url}

**Deployment:** {detected deploy workflow name} -- {success | failure | n/a | pending}

**Health check:** `{HEALTH_URL}` returned {HEALTH_CODE} -- {ok | fail | not configured}

**Re-validated test plan items:**

- ✅ `<checkbox text>` -- {evidence}
- ❌ `<checkbox text>` -- {failure summary}

**Summary:** {🎉 fully validated post-merge | ⚠️ post-merge issues -- review above | ⏳ some workflows still running, re-check later}
```

```bash
gh pr comment "$PR_URL" --body "$COMMENT_BODY"
```

### 11.5 Classify the dispatcher status

- All post-merge workflows passed (or none existed) AND all re-validated items passed AND health check is `ok` or `not configured` → `MERGED`.
- Anything failed → `MERGED-WITH-WARNINGS` (the PR remains merged; the warnings are loud in the comment so the human can react).
- Some workflows still pending at deadline → `MERGED` if everything else is clean; `MERGED-WITH-WARNINGS` if anything has already failed.

Mark `post-merge-validation` completed in the progress file. On `MERGED` (no warnings), delete `.pst-ready-progress.json`. On `MERGED-WITH-WARNINGS`, keep it so a follow-up `/pst:ready --post-merge-only $PR_URL` (future flag, not in this version) could re-validate later.

### 11.6 Dry-run

`--dry-run` skips Phase 11 entirely (Phase 9 wouldn't have merged anything). Print "would post post-merge validation comment with {detected workflows count} workflows tracked" and exit.

---

## Dry-Run Summary

`--dry-run` flows through the whole pipeline in read-only mode:

- Phase 2: `pst:rebase --dry-run` -- analysis only.
- Phase 3: skip sub-agent fix attempts; print failing checks and their classifications.
- Phase 4: `pst:resolve-threads --dry-run` + `pst:code-review --sweep --dry-run`; report counts only.
- Phase 5: identical to Phase 3 under dry-run.
- Phase 6: print the proposed title and body diff; do not `PATCH` the PR.
- Phase 7: parse and classify the test plan; print the would-be comment and checkbox diff; do not post or `PATCH`.
- Phase 8: skip browser; print what the final summary would look like.
- Phase 9 (auto-merge): print the permission probe, the chosen merge method, and the would-be `gh pr merge` invocation; do not merge.
- Phase 11 (post-merge validation): not exercised under dry-run because nothing was actually merged; print "would post post-merge validation comment".

No pushes, no resolutions, no PR edits, no comments, no merges, no browser pops. Safe to run at any time to see the state of a PR.

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
  "state": "test-plan",
  "completed": [
    "intake",
    "workspace",
    "rebase",
    "ci-wait-1",
    "review-loop",
    "ci-wait-2",
    "refresh-pr"
  ],
  "skipped": [],
  "ci_attempts_pass1": 2,
  "ci_attempts_pass2": 0,
  "review_rounds": 1,
  "test_plan": { "validated": 3, "failed": 0, "manual": 4 },
  "auto_merge": {
    "requested": true,
    "permission": "admin",
    "method": "squash",
    "merged_via": "admin",
    "merge_commit_sha": "abc1234567890def",
    "merged_at": "2026-04-24T18:12:30Z"
  },
  "post_merge_validation": {
    "workflows": { "passed": 4, "failed": 0, "pending": 0, "deadline_min": 20 },
    "deploy_status": "success",
    "health_check": { "url": "https://api.example.com/health", "code": 200 },
    "revalidated_items": { "passed": 2, "failed": 0 },
    "comment_url": "https://github.com/owner/repo/pull/42#issuecomment-123456789",
    "summary": "MERGED"
  },
  "residual": [],
  "updated_at": "2026-04-24T18:05:00Z"
}
```

When `--auto-merge` is not requested, omit `auto_merge` and `post_merge_validation` from the file rather than writing nulls.

---

## Stop Signals

**Per-PR (inside a child or single-PR run):** halt and preserve that PR's progress file when any of:

- Rebase produces conflicts that `pst:rebase` could not auto-resolve.
- `MAX_CI_ATTEMPTS` consumed in Phase 3 or Phase 5 with failures remaining.
- `MAX_REVIEW_ROUNDS` consumed in Phase 4 with unresolved threads or remaining criticals/warnings.
- Sub-agent fix attempts return no viable patch for every failing check in a round.
- `gh` auth fails, `git push --force-with-lease` is rejected, or the PR is closed/merged mid-run.

In dispatcher mode, a per-PR halt reports that PR as `BLOCKED` in the final matrix but does not stop sibling PRs. The dispatcher never aborts healthy children because one hit a residual.

**Auto-merge specific:** in addition to the per-PR signals above, in `--auto-merge` mode:

- Phase 9 fails because the head SHA moved between Phase 8 and Phase 9 → mark `MERGE-FAILED`, continue with siblings.
- Phase 9 fails because branch protection requires a status the orchestrator cannot satisfy (manual gate, required reviewer not engaged, missing required check that is not failing but not present) → mark `MERGE-FAILED`, continue with siblings.
- Two consecutive PRs return `MERGE-FAILED` → halt the auto-merge batch (probable systemic problem -- bad token scopes, branch protection misconfig). Already-merged PRs stay merged; remaining PRs report as `READY` and the browser opens for them.
- Phase 11 surfaces a deploy failure on a base branch shared by the next PR in the batch → halt and surface the failure. The next PR's Phase 2 rebase would otherwise pick up a known-broken base.

**Dispatcher-level:** halt the whole run only when:

- `gh` or `git` is missing.
- All provided URLs are invalid or all return non-`OPEN` state.
- Temp-clone creation fails for every foreign-repo group (disk full, auth revoked, etc.).
- (Auto-merge only) The opinionated merge order detects a cycle in stacked-PR dependencies that has no resolution.

Every halt prints a clear next-action line; resuming is always `/pst:ready <same URL(s)>` (or `/pst:ready --auto-merge <same URL(s)>` to retry the merge phase).

---

## Notes

- **Composition, not reimplementation.** Rebase, thread resolution, and code review live in their own skills. If their behavior changes, this skill inherits the change.
- **Force-push safety.** All pushes use `--force-with-lease`. The skill never uses `--force`.
- **Cross-repo friendly.** Runs from anywhere. For a single foreign-repo URL, clones to a temp dir and operates there. For multiple URLs spanning several repos, groups URLs by repo and shares one temp clone per foreign repo with per-PR worktrees inside. The user's cwd is never mutated.
- **Parallel by default for 2+ URLs (no auto-merge).** Each PR is driven by its own background agent in its own worktree. Respects `--max-parallel` (default 4) to avoid GitHub API throttling. One crashed or blocked child does not affect its siblings.
- **Sequential when `--auto-merge` is set.** With auto-merge active and 2+ URLs, parallelism is forced to 1 so each PR's rebase picks up the previous PR's merge commit. Order is computed once via the opinionated-merge-order algorithm; do not pre-stack worktrees.
- **Auto-merge is strictly opt-in.** No flag → no merge, no matter what the prompt says. The flag means "I have permission and I want this batch shipped."
- **Two validation comments per merged PR.** Phase 7 posts the pre-merge `Test plan validation` comment; Phase 11 posts the `Post-merge validation` comment after deploys settle. They live alongside each other on the (merged) PR for the audit trail.
- **Idempotent resume at both levels.** Per-PR progress files let an interrupted child pick up where it stopped. The dispatcher progress file lets a re-invocation skip already-`READY`/`MERGED` children and re-dispatch only the `BLOCKED`/`ERROR`/`MERGE-FAILED` ones, reusing existing temp clones and worktrees.
