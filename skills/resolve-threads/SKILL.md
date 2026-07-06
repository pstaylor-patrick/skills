---
name: pst:resolve-threads
description: Resolves every unresolved review thread on a pull request. Each thread is evaluated by its own background agent inside an isolated git worktree, weighing the comment against the full pull request and repository context, then either implementing the fix directly, dismissing it with a recorded rationale, or deferring it to a human when the call is ambiguous. Verdicts are reported before any code, reply, or resolution reaches GitHub.
---

# PST Resolve Threads

Trigger: `/pst:resolve-threads <PR>`.

Question: given everything this thread's author could see plus everything the
repository as a whole can add, is the recommendation worth acting on? A
reviewer's comment and a bot's comment get the same weight; what decides the
verdict is whether the concern holds up once a real agent reads the full
change and the surrounding code, not who raised it.

## Scope

A PR URL, `owner/repo#123`, a bare `#123` (current repo when owner/repo is
omitted), or the PR associated with the current branch. This skill only
operates on pull requests; it has nothing to resolve without one. If no PR
can be resolved unambiguously, ask which one is meant.

## Workflow

1. **Resolve the PR and its threads.** `pull_request_read` with `get`, `get_
   diff`, `get_files`, and `get_review_comments` (paginate with `after` until
   exhausted). Keep only threads where `isResolved` is false. For each,
   collect `threadId` (the GraphQL node id, for resolving), the anchor
   `path`/`line`, every comment in the thread in order (author, body), and
   whether the thread is outdated (its anchor line may no longer exist in the
   current diff, so the evaluating agent reads the live file, not the stale
   hunk). If none are unresolved, report that and stop.
2. **Get a real local checkout.** Fetch and check out the PR's head branch
   (not a detached `pull/<N>/head`, since fixes need to be committed and
   pushed on it) so `repoPath` is this checkout's absolute path and `headSha`
   is its current tip.
3. **Run the resolution workflow.** Call `Workflow` with the script under
   Resolution workflow script and `args: { threads, repoPath, headSha,
   prNumber, prTitle, prBody }`. Invoking this skill is what authorizes the
   `Workflow` call. The script evaluates every thread concurrently, each in
   its own throwaway `git worktree` of `repoPath` at `headSha` so one
   thread's exploration cannot see or collide with another's, then applies
   every accepted fix sequentially against the live `repoPath` so drift
   between fixes is caught as it happens rather than silently overwritten.
   It returns `{ fixed, wontFix, needsHuman, conflicts }`. On a repeat run
   against the same PR, pass back the `scriptPath` the first call returned
   instead of resending `script`.
4. **Report before touching GitHub.** For every thread: verdict, one-line
   rationale, and (for `fixed`) which commit. Ask before replying, resolving,
   or pushing, unless the invocation said to proceed automatically.
5. **Commit.** One commit per `fixed` thread, message referencing the
   thread's file and the concern it addressed. `conflicts` (a fix whose diff
   no longer applied cleanly once earlier fixes landed) get no commit and
   fold into `needsHuman` for reporting and replies.
6. **Reply and resolve.** For `fixed` and `wontFix`: `add_reply_to_pull_
   request_comment` on the thread's last comment stating what happened (the
   commit, or the dismissal rationale), then `resolve_review_thread` with the
   `threadId`. For `needsHuman` and `conflicts`: reply with the open question
   or the drift that needs a human look, and leave the thread unresolved.
7. **Push.** Push the branch carrying the new commits. The session's active
   pst merge mode (see `pst`) governs whether that push, and any PR update,
   actually happens versus staying local.

## Resolution workflow script

Pass this verbatim as `Workflow`'s `script`.

```js
export const meta = {
  name: "pst-resolve-threads-scope",
  description: "Evaluate every unresolved PR thread in its own worktree, then apply accepted fixes sequentially",
  phases: [
    { title: "Evaluate", model: "opus" },
    { title: "Apply" }
  ]
}

const VERDICT_SCHEMA = {
  type: "object",
  properties: {
    action: { type: "string", enum: [ "fix", "wont_fix", "needs_human" ] },
    rationale: { type: "string" },
    diff: { type: "string" },
    reply: { type: "string" }
  },
  required: [ "action", "rationale" ]
}

const APPLY_SCHEMA = {
  type: "object",
  properties: {
    applied: { type: "boolean" },
    commitSha: { type: "string" },
    note: { type: "string" }
  },
  required: [ "applied", "note" ]
}

const threads = args.threads
const repoPath = args.repoPath
const headSha = args.headSha
const prTitle = args.prTitle
const prBody = args.prBody

function threadContext(t) {
  const convo = t.comments.map((c) => c.author + ": " + c.body).join("\n")
  const staleness = t.isOutdated
    ? "This thread's anchor line is outdated; read the file's current content, not the stored hunk."
    : "This thread's anchor line still matches the current diff."
  return "Pull request: " + prTitle + "\n\n" + prBody + "\n\nThread at " + t.path + ":" +
    t.line + " (" + staleness + ")\n\n" + convo
}

function worktreeSetup() {
  return "Before doing anything else, create your own throwaway checkout: run " +
    "`git -C " + repoPath + " worktree add $(mktemp -d) " + headSha + "` and note the " +
    "path it prints, then do every read and every trial edit inside that path only, " +
    "never in " + repoPath + " itself. Remove it when finished with `git -C " + repoPath +
    " worktree remove <path> --force`, whether or not the change was applied there. "
}

phase("Evaluate")
const verdicts = await parallel(threads.map((t) => () =>
  agent(
    worktreeSetup() +
    "Decide how to handle this review thread, reading as much of the repository as the " +
    "decision needs, not just the diff hunk: does the concern hold up against the real code, " +
    "and is it worth acting on regardless of whether a human or a bot raised it?\n\n" +
    threadContext(t) +
    "\n\nIf the concern is real and worth fixing, make the change in your worktree, confirm " +
    "it behaves (a quick test or a manual check), then capture `git diff` there as the `diff` " +
    "field and set action to fix. If it is not worth fixing (already covered elsewhere, " +
    "based on a misreading, or the cost outweighs the benefit), set action to wont_fix and say " +
    "why in rationale. If the right call depends on a judgment this agent cannot make (product " +
    "intent, a tradeoff only a maintainer can weigh, conflicting guidance elsewhere in the PR), " +
    "set action to needs_human. Always include a short reply meant for the thread itself.",
    { phase: "Evaluate", label: t.path + ":" + t.line, schema: VERDICT_SCHEMA }
  ).then((v) => (v ? { ...t, ...v } : { ...t, action: "needs_human", rationale: "evaluation agent did not return a result" }))
))

phase("Apply")
const toApply = verdicts.filter((v) => v.action === "fix" && v.diff)
const applied = []
for (const v of toApply) {
  const result = await agent(
    "In the repository at " + repoPath + " (already checked out on the branch under review), " +
    "apply this fix for the review thread at " + v.path + ":" + v.line + ".\n\nDiff captured " +
    "from an isolated trial:\n\n" + v.diff + "\n\nTry to apply it as-is first; if it no longer " +
    "applies cleanly because an earlier fix in this same run touched overlapping code, re-read " +
    "the current file and re-implement the equivalent change by hand instead of forcing the " +
    "patch. Once the working tree has the change, create exactly one commit for it referencing " +
    v.path + " and the concern it addresses, and report the commit sha. If the change cannot be " +
    "reconciled with what is already on disk, make no commit and report why.",
    { phase: "Apply", label: v.path + ":" + v.line, schema: APPLY_SCHEMA }
  )
  applied.push({ ...v, ...(result || { applied: false, note: "apply agent did not return a result" }) })
}

const fixed = applied.filter((a) => a.applied)
const conflicts = applied.filter((a) => !a.applied)
const wontFix = verdicts.filter((v) => v.action === "wont_fix")
const needsHuman = verdicts.filter((v) => v.action === "needs_human")

return { fixed, wontFix, needsHuman, conflicts }
```

## Model tiers

| Call | Model | Why |
|---|---|---|
| Evaluate | `opus` | One call per thread, low volume, high stakes: it is both the read on whether the concern is real and the decision to write code in response |
| Apply | inherit | Mechanical reconciliation of an already-decided diff against a moving working tree |

## Verdicts

| Verdict | Bar | GitHub outcome |
|---|---|---|
| `fix` | The concern reproduces against the real code and the isolated trial fix holds | Applied on `repoPath`, committed, thread replied to and resolved |
| `wont_fix` | The concern does not hold up, is already covered, or costs more than it is worth | No code change; thread replied to with the rationale and resolved |
| `needs_human` | The right call depends on judgment this skill cannot make, or a `fix` diff conflicted once applied | No code change; thread replied to with the open question, left unresolved |

## Reply style

One reply per thread, plain prose, no restating the original comment. State
the outcome first (fixed in commit X, not fixing because Y, or the open
question), then stop. Apply `pst:ai-slop`'s punctuation and tone rules to
every reply body before posting.
