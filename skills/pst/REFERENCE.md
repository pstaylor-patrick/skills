# /pst reference

Mechanics and details for the `/pst` skill. Not loaded as part of the doctrine;
read it only when you need these specifics.

## Session hooks

`scripts/pst-mode.rb` installs Ruby scripts to `~/.claude/pst/bin/` and registers
them once in `~/.claude/settings.json`:

- `pst-session-start.rb` (`SessionStart`) writes `CLAUDE_SESSION_ID` into
  `$CLAUDE_ENV_FILE` so a skill can learn its own session id.
- `pst-guard.rb` (`PreToolUse`) enforces, but only when this session is armed:
  - no em dash (U+2014) in `Write` / `Edit` / `MultiEdit` / `NotebookEdit`
    content or `git commit` messages;
  - the merge guard (see below).
- `pst-session-end.rb` (`SessionEnd`) removes the per-session marker.

A session is armed only if `~/.claude/pst/armed/<session_id>` exists, which
`/pst` creates (`/pst off` removes it). In every other session the hooks are
present but inert.

Because Claude Code binds hooks at session startup, in the session that first
installs the shim the guards engage from the next session onward. In all later
sessions the shim is already bound at startup, so arming via `/pst` takes effect
immediately.

## Merge modes (asked at every invoke)

`/pst` asks via `AskUserQuestion` how PRs should land this session, and re-asks
on every re-invocation so it can change per repo:

1. **Admin-bypass squash:** `gh pr merge <pr> --squash --admin` as PRs go green.
   For repos you can self-merge.
2. **Auto-merge on approval:** `gh pr merge <pr> --auto --squash`. GitHub merges
   each PR once required approvals and checks pass. For approval-gated repos
   (for example ShirePath, where Conner must approve).
3. **Merge-ready only:** bring PRs to merge-ready, do not enable auto-merge, do
   not admin-bypass; leave the merge to the user.

## Merge guard (rule 4)

`pst-guard.rb` intercepts a direct `gh pr merge` and runs `gh pr checks`. It
blocks unless every check has passed (pending or failing both block). Cases:

- All checks passed: allow.
- Pending or failing checks: deny with the failing summary.
- No CI checks at all: allow (there is no CI to gate; rule 4 is about not merging
  red CI, not forcing CI to exist).
- Cannot determine status (timeout or error): deny, since green cannot be
  confirmed.
- `--auto` present: allow, because GitHub holds the merge until its own approval
  and checks gate is satisfied (this is how mode 2 works).

Override for a single command by prefixing `PST_ALLOW_RED_MERGE=1`, for example
`PST_ALLOW_RED_MERGE=1 gh pr merge 53 --squash --admin`.

## Deterministic helper scripts (Ruby)

- `scripts/pst-mode.rb` bootstrap: install shim, git identity guard, arm session
  (`pst-mode.rb off` disarms).
- `scripts/register-hooks.rb` idempotently registers the shim in settings.json.
- `scripts/pst-emdash.rb check|prune [path ...]` finds or strips em dashes.
- `scripts/pst-worktrees.rb [repo_dir]` lists prunable worktrees (rule 3).
- `scripts/hooks/*.rb` the installed hook bodies.

## Order of operations for a typical change

1. Plan in the foreground (Opus high). Fan implementation out to background
   Sonnet agents in isolated worktrees (rules 1, 1a, 2).
2. Open a PR (rule 4). Separate refactor commits from behavior changes (rule 13).
3. Get CI green with root-cause fixes (rules 4, 5). De-slop the diff (rule 10).
4. Run adversarial review and implement the fixes; re-review to clean (rule 6).
5. For a cluster app, run the local k8s QA arsenal with discernment and prove it
   works end-to-end (rules 7, 7a, 12). If CI auto-deploys to remote on merge, do
   this BEFORE merge via blue-green.
6. Land the PR by the chosen merge mode: admin-bypass squash on green CI,
   auto-merge on approval, or hand off merge-ready (rule 4, merge-guard enforced).
7. If not gated pre-merge, validate locally before any remote promotion (rule 7).
8. Run `pst-worktrees.rb` and offer to prune orphaned worktrees (rule 3).
