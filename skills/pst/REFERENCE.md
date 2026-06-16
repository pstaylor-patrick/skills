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

## Deterministic gates in pst-guard.rb (PreToolUse, armed only)

- **No em dash (rule 11):** denies Write/Edit content or git commit messages
  containing U+2014.
- **Model tier (rule 2):** denies an `Agent`/`Task` spawn whose `tool_input.model`
  is unset. Only model is enforceable (effort is not a spawn parameter). Denies
  only when model is absent, so it never blocks a spawn that sets one. Override
  `PST_ALLOW_DEFAULT_MODEL=1`.
- **Merge gate (rules 5 and 7):** intercepts a direct `gh pr merge`:
  - CI (rule 5): runs `gh pr checks`; blocks unless all pass (pending or failing
    block). No checks: allow. Unverifiable (timeout/error): deny. Override
    `PST_ALLOW_RED_MERGE=1`.
  - Review (rule 7): blocks unless a review marker exists for the head commit
    (`pst-reviewed.rb mark`). Override `PST_ALLOW_UNREVIEWED_MERGE=1`.
  - `--auto`: allowed; GitHub holds the merge until its own approval and checks
    gate is satisfied (merge mode 2).

Example override: `PST_ALLOW_RED_MERGE=1 PST_ALLOW_UNREVIEWED_MERGE=1 gh pr merge 53 --squash --admin`.

## Deterministic helper scripts (Ruby)

- `scripts/pst-mode.rb` bootstrap: install shim, git identity guard, arm session
  (`off` disarms; `foreground on|off` toggles the delegate-nudge escape hatch).
- `scripts/register-hooks.rb` idempotently registers the shim in settings.json.
- `scripts/pst-emdash.rb check|prune [path ...]` finds or strips em dashes.
- `scripts/pst-worktrees.rb [repo_dir]` lists prunable worktrees (rule 4).
- `scripts/pst-reviewed.rb mark|check [sha]` records or checks the review marker
  the merge guard requires (rule 7).
- `scripts/hooks/*.rb` installed hook bodies plus `pst_common.rb` (shared lib).

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
- **Rule 17 open-on-post triggers:** `gh pr create`, `gh pr|issue comment`,
  `gh pr|issue edit --body`, and the Jira `createJiraIssue` / `editJiraIssue` /
  `addCommentToJiraIssue` MCP tools. It opens the GitHub URL scraped from command
  output, or a Jira browse URL built from the response host plus the issue key
  (from the input for edit/comment, from the response for create). Scans only the
  tool response, so a URL inside a comment body is not opened by mistake. Uses
  macOS `open` (else `xdg-open`); set `PST_NO_BROWSER=1` to skip a run.

## Session hooks

`scripts/pst-mode.rb` installs Ruby scripts (and `pst_common.rb`, the shared lib)
to `~/.claude/pst/bin/` and registers them once in `~/.claude/settings.json`:

- `pst-session-start.rb` (`SessionStart`) writes `CLAUDE_SESSION_ID` into
  `$CLAUDE_ENV_FILE` so a skill can learn its own session id.
- `pst-guard.rb` (`PreToolUse`) runs the em-dash, model-tier, and merge gates
  above, only when armed.
- `pst-prompt-reminder.rb` (`UserPromptSubmit`) re-injects the compressed rule
  checklist each turn, leading with the delegate-by-default test (rule 1), only
  when armed. Drops the delegation lead under foreground mode.
- `pst-delegate-nudge.rb` (`PostToolUse`, `Write|Edit|MultiEdit`) counts inline
  implementation edits and, after the 3rd, surfaces a non-blocking reminder to
  delegate (rule 1). Never blocks. See "Delegation and foreground mode".
- `pst-open-on-post.rb` (`PostToolUse`, `Bash` and the Jira create/edit/comment
  MCP tools) opens the resulting page in the browser after an action under
  Patrick's name: a PR created, a PR/issue or Jira comment posted, a Jira issue
  created, or a description updated (rule 17). Side effect only, never blocks.
  Skip a run with `PST_NO_BROWSER=1`.
- `pst-session-end.rb` (`SessionEnd`) removes the per-session marker.

### Delegation and foreground mode

The delegate nudge counts only foreground grunt work: an edit counts only when
the file is in the **primary** git worktree. Delegated work runs in linked
worktrees (rules 2, 3), so those edits are never counted, which makes the nudge
correct whether or not sub-agents share the parent session id. It also skips
`*.md`, docs, lockfiles, `*.tfvars`, JSON/YAML/TOML config, and dotfiles, and
edits outside a repo (favoring under-counting). It is non-blocking and resets its
per-session counter after each reminder. Set `PST_DEBUG_DELEGATE=1` to log each
edit's session id, primary-worktree verdict, cwd, and path to
`~/.claude/pst/delegate/debug.log` for verification. Silence it when foreground
work is intentional (a planning or conversation-heavy session) via either:

- `pst-mode.rb foreground on` (creates `~/.claude/pst/foreground/<sid>`; `off`
  removes it). This also drops the per-turn reminder's delegation lead.
- env `PST_FOREGROUND_OK=1` for a single command.

A session is armed only if `~/.claude/pst/armed/<session_id>` exists, which
`/pst` creates (`/pst off` removes it). Otherwise the hooks are inert. Because
Claude Code binds hooks at session startup, in the session that first installs
the shim the guards engage from the next session onward; later sessions arm
immediately.

## Order of operations for a typical change

1. Plan in the foreground (Opus high). Implementation does not run inline: fan it
   out to background Sonnet agents in isolated worktrees (rules 1, 2, 3). The
   foreground keeps only planning, choices, orchestration, and validation.
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
