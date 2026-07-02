---
name: pst:code-review
description: Review a pull request, branch, file set, or feature description for correctness bugs and refactor opportunities. Verifies each candidate finding in an isolated worktree before posting only the ones that survive, so PR feedback is curated instead of noisy.
---

# PST Code Review

Trigger: `/pst:code-review <scope>`.

Question: does this finding survive an isolated attempt to refute it? A
plausible-sounding comment that was never checked against the real code is the
AI slop this skill exists to filter out. Silence beats a wrong or nitpicky
comment; when in doubt, drop it.

## Scope

Accepted forms, resolved in this order:

1. A PR URL or `owner/repo#123` / bare `#123` (current repo when owner/repo is
   omitted). Resolve via `pull_request_read`.
2. A branch or ref: diff against the default branch.
3. An explicit file list or glob.
4. A semantic description of a feature ("the auth refactor", "the caching
   layer"): locate the files with Explore/Grep, list what was found, and
   confirm the set before reviewing.
5. The whole repository: only on explicit request. State the file count
   before proceeding, given the cost.

If scope is ambiguous, ask which PR or files are meant. Do not guess.

## Workflow

1. **Resolve scope to files and a diff.** PR: `pull_request_read` with
   `get_diff`, `get_files`, and `get_comments`/`get_review_comments` so
   ground already covered by a human or a prior review is not re-flagged.
   Everything else: `git diff`, `git show`, or plain reads. Record the base
   commit so worktrees in step 3 can check out the same state.
2. **Find candidates**, two lenses over the same file set, each dispatched
   as background `Agent` calls run in parallel with each other (do not pass
   `run_in_background: false`). Wait for every call this step dispatched
   before moving to step 3.
   - Rubric lens, `model: "haiku"`: route files through the repo's own
     rubrics with `ruby ~/.claude/pst/bin/skill_route.rb <files...>` (the
     same routing `pst:refactor` uses), one call per matched skill or file
     batch, applying that skill's principles verbatim (`pst:refactoring`
     and `pst:ai-slop` included). This is checklist application against
     text the skill already wrote, not open-ended judgment, so the cheap
     tier is enough.
   - General lens, no `model` override (inherit the session model):
     correctness bugs, edge cases, security (injection, auth, secrets,
     OWASP top 10), API/contract breaks, missing or wrong test coverage,
     performance regressions. There is no checklist to apply here, so it
     needs full reasoning, not the cheap tier.
   Every candidate needs a file, a line, and a concrete failure scenario
   ("input X produces Y", "breaks when Z is absent"), not a vague quality
   complaint.
3. **Verify each candidate in an isolated worktree.** One background
   `Agent` call per finding, or per small batch of related findings, with
   `isolation: "worktree"` and no `model` override, so verification never
   touches the tree the review itself runs from. Verification has to
   write and run an actual repro or apply an actual refactor correctly,
   which the cheap tier is not reliable enough for. Dispatch every
   candidate's call in parallel and wait for all of them; step 4 must not
   curate against a partial set. Task each agent to refute, not confirm:
   reproduce the bug (a failing test, an actual invocation, a traced code
   path), or for a refactor suggestion, apply it and confirm behavior is
   unchanged and the result is actually simpler. A tie goes to discarding
   the finding; a concrete reproduction is what keeps it, not renewed
   confidence.
4. **Curate.** Drop everything that did not survive step 3. Merge
   duplicates surfaced by both lenses. Tier each survivor (see Priority)
   and re-verify every P1 candidate with a second, independent
   `isolation: "worktree"` Agent call, dispatched in the background with
   `model: "opus"`, that gets only the file/line/claim, not the first
   agent's reasoning. Dispatch every P1 recheck in parallel and wait for
   all of them before finalizing tiers; P1 volume is small and a wrong
   verdict here posts a false red finding carrying an auto-apply diff, so
   the expensive tier is the right trade at this one point in the
   pipeline. A P1 that the second pass cannot also reproduce drops to P2
   with no suggested diff, never posts as P1. Cap the set: post what a
   reviewer would actually want interrupted for, not everything that
   happens to be true. Note anything dropped only for volume so it can be
   requested explicitly.
5. **Report before posting.** Show the curated list (`path:line`, tier, one
   line each) and ask whether to post. Skip the ask only when the
   invocation said to post automatically.
6. **Post.**
   - PR scope: `pull_request_review_write` with `create` (no `event`, so it
     stays pending), then `add_comment_to_pending_review` per finding
     anchored to `path`/`line`, then `submit_pending` with
     `event: "COMMENT"`. Never `REQUEST_CHANGES` or `APPROVE` unless asked.
   - Non-PR scope: there is nothing to post to. The curated report to the
     user is the deliverable.

## Dispatch

Every `Agent` call above runs in the background and in parallel with its
siblings from the same step; the next step waits for all of them before it
starts, so nothing curates or posts against a partial result.

| Call | Model | Why |
|---|---|---|
| Rubric lens (step 2) | `haiku` | Applies an already-written skill's rules; no open-ended judgment |
| General lens (step 2) | inherit | No checklist; needs full reasoning to name what a rubric cannot |
| Worktree verification (step 3) | inherit | Must write and run a real repro or refactor correctly |
| P1 second-pass (step 4) | `opus` | Low volume, highest stakes: gates a red, auto-apply-diff finding |

## Priority

Assign a tier from what step 3 actually proved, never from how severe it
sounds:

| Tier | Bar | Requires |
|---|---|---|
| P1 (red) | Confirmed break: crash, wrong output, security hole, data loss | A reproduction, plus the step-4 second-pass agreement |
| P2 (yellow) | Confirmed but bounded: real bug/smell needing specific input, config, or scale; or a refactor with verified payoff | A reproduction from step 3 |
| P3 (green) | Real but low blast radius, and only worth interrupting for because the fix is a one-line, unambiguous diff | A reproduction from step 3, and a suggestion block (see below) |

Drop anything that only clears the P3 bar and has no suggestion block; it is
noise, not feedback. Prefix each posted comment with its tier (`**P1**`,
`**P2**`, `**P3**`).

## Posting style

One finding, one comment: tier prefix, the concrete failure scenario, then
the fix. Hard cap 640 characters per comment body; target roughly 240. No
summary of the summary, no praise, no restating the diff. Apply
`pst:ai-slop`'s punctuation and tone rules to anything written into a
comment body. Before calling `add_comment_to_pending_review`, check the
body's length; if it is over budget, cut prose before cutting the concrete
scenario, and drop the suggestion block if it still does not fit rather
than splitting into a second comment.

Add a GitHub suggestion block only when the fix is mechanical and
unambiguous from the finding alone (a rename, a null check, an off-by-one,
a dead branch, the exact rubric move a matched skill names) and touches
only the lines already in the diff:

    ```suggestion
    <replacement line(s)>
    ```

Never suggest a diff for anything needing a judgment call, multiple files,
or unclear intent; post the finding without one instead.
