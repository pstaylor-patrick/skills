# /pst reference

Mechanics and detail for the `/pst` skill. Not loaded as doctrine; read it only
when you need specifics. Rule numbers match `SKILL.md`.

## Merge modes (asked at every invoke)

`/pst` asks via `AskUserQuestion` how PRs should land this session, re-asking on
every re-invocation so it can change per repo:

1. **Admin-bypass squash:** `gh pr merge <pr> --squash --admin` as PRs go green.
   For repos you can self-merge.
2. **Auto-merge on approval:** `gh pr merge <pr> --auto --squash`. GitHub merges
   each PR once required approvals and checks pass. For approval-gated repos (for
   example ShirePath, where Conner must approve).
3. **Merge-ready only:** bring PRs to merge-ready, do not enable auto-merge, do
   not admin-bypass; leave the merge to the user.

## Merge guard (rule 5)

`pst-guard.rb` intercepts a direct `gh pr merge` and runs `gh pr checks`. It
blocks unless every check has passed (pending or failing both block):

- All checks passed: allow.
- Pending or failing: deny with the failing summary.
- No CI checks at all: allow (no CI to gate).
- Status unverifiable (timeout or error): deny.
- `--auto` present: allow; GitHub holds the merge until its own approval and
  checks gate is satisfied (mode 2).

Override one command with `PST_ALLOW_RED_MERGE=1`, for example
`PST_ALLOW_RED_MERGE=1 gh pr merge 53 --squash --admin`.

## Deterministic helper scripts (Ruby)

- `scripts/pst-mode.rb` bootstrap: install shim, git identity guard, arm session
  (`off` disarms).
- `scripts/register-hooks.rb` idempotently registers the shim in settings.json.
- `scripts/pst-emdash.rb check|prune [path ...]` finds or strips em dashes.
- `scripts/pst-worktrees.rb [repo_dir]` lists prunable worktrees (rule 4).
- `scripts/hooks/*.rb` installed hook bodies (SessionStart, PreToolUse guard,
  SessionEnd).

## Rule detail and examples

- **Rule 2 tiers, Haiku fits:** mechanical rename or import-path rewrite, lint or
  format autofix, single-string copy change, version or changelog bump, deleting
  already-identified dead code, boilerplate from an exact template.
- **Rule 6 band-aids to avoid:** skipping tests, loosening thresholds,
  retry-until-green, swallowing errors.
- **Rule 8 local k8s timing:** inspect `.github/workflows/`. If merge auto-deploys
  to remote, do the local blue-green deploy and E2E validation BEFORE merge so
  remote is never reached unvalidated; otherwise validate post-merge but
  pre-promotion. The local k3s cloud is a safe sandbox (no VPC or
  deploy-permission roadblocks), so heavyweight automated testing is feasible.
- **Rule 13 cue phrases:** "don't stop until you're done", "all the way", "keep
  going till it's green".
- **Rule 15 smell vocabulary:** long method, large class, feature envy, primitive
  obsession, shotgun surgery, divergent change, data clumps, message chains,
  speculative generality.

## Session hooks

`scripts/pst-mode.rb` installs Ruby scripts to `~/.claude/pst/bin/` and registers
them once in `~/.claude/settings.json`:

- `pst-session-start.rb` (`SessionStart`) writes `CLAUDE_SESSION_ID` into
  `$CLAUDE_ENV_FILE` so a skill can learn its own session id.
- `pst-guard.rb` (`PreToolUse`) enforces, only when armed: no em dash in Write or
  Edit content or git commit messages, and the merge guard.
- `pst-session-end.rb` (`SessionEnd`) removes the per-session marker.

A session is armed only if `~/.claude/pst/armed/<session_id>` exists, which
`/pst` creates (`/pst off` removes it). Otherwise the hooks are inert. Because
Claude Code binds hooks at session startup, in the session that first installs
the shim the guards engage from the next session onward; later sessions arm
immediately.

## Order of operations for a typical change

1. Plan in the foreground (Opus high); fan implementation to background Sonnet
   agents in isolated worktrees (rules 1, 2, 3).
2. Open a PR (rule 5). Separate refactor commits from behavior changes (rule 15).
3. Get CI green with root-cause fixes (rules 5, 6). De-slop the diff (rule 12).
4. Run adversarial review; implement findings; re-review to clean (rule 7).
5. For a cluster app, run the local k8s QA arsenal with discernment and prove it
   works end-to-end (rules 8, 9, 14). If CI auto-deploys to remote on merge, do
   this BEFORE merge via blue-green.
6. Land by the chosen merge mode: admin-bypass squash on green CI, auto-merge on
   approval, or hand off merge-ready (rule 5, merge-guard enforced).
7. If not gated pre-merge, validate locally before any remote promotion (rule 8).
8. Run `pst-worktrees.rb` and offer to prune orphaned worktrees (rule 4).
