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
2. **Find candidates**, two lenses over the same file set:
   - Route files through the repo's own rubrics with
     `ruby ~/.claude/pst/bin/skill_route.rb <files...>` (the same routing
     `pst:refactor` uses) and apply each matched skill's principles,
     `pst:refactoring` and `pst:ai-slop` included.
   - A general reviewer pass, unscoped to any skill: correctness bugs, edge
     cases, security (injection, auth, secrets, OWASP top 10), API/contract
     breaks, missing or wrong test coverage, performance regressions.
   Every candidate needs a file, a line, and a concrete failure scenario
   ("input X produces Y", "breaks when Z is absent"), not a vague quality
   complaint.
3. **Verify each candidate in an isolated worktree.** One `Agent` call per
   finding, or per small batch of related findings, with
   `isolation: "worktree"`, so verification never touches the tree the
   review itself runs from. Task the agent to refute, not confirm:
   reproduce the bug (a failing test, an actual invocation, a traced code
   path), or for a refactor suggestion, apply it and confirm behavior is
   unchanged and the result is actually simpler. A tie goes to discarding
   the finding; a concrete reproduction is what keeps it, not renewed
   confidence.
4. **Curate.** Drop everything that did not survive step 3. Merge
   duplicates surfaced by both lenses. Rank by what would make a reviewer's
   day worse if shipped: correctness and security first, then real refactor
   debt, then everything else. Cap it: post the handful that matter, not
   everything that happens to be true. Note anything dropped only for
   volume so it can be requested explicitly.
5. **Report before posting.** Show the curated list (`path:line`, one line
   each) and ask whether to post. Skip the ask only when the invocation
   said to post automatically.
6. **Post.**
   - PR scope: `pull_request_review_write` with `create` (no `event`, so it
     stays pending), then `add_comment_to_pending_review` per finding
     anchored to `path`/`line`, then `submit_pending` with
     `event: "COMMENT"`. Never `REQUEST_CHANGES` or `APPROVE` unless asked.
   - Non-PR scope: there is nothing to post to. The curated report to the
     user is the deliverable.

## Posting style

One finding, one comment: the concrete failure scenario, then the smallest
fix. No summary of the summary, no praise, no restating the diff. Apply
`pst:ai-slop`'s punctuation and tone rules to anything written into a
comment body.
