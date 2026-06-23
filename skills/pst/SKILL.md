# PST — Merge Mode Shim

The merge-mode question is injected automatically by the `SessionStart` hook
(`session-start.rb`) on session start, resume, and `/clear`. This file is
the manual `/pst` re-invoke path plus the rules for applying the chosen mode.

## /pst

Call `AskUserQuestion` to re-set the session's merge mode:

**Question:** "How should I handle changes from this session?"
**Header:** Merge mode
**Options:**

1. **Local only** — No push, no PR. Changes stay on disk.
2. **Merge ready** — Push branch, open PR, ensure CI is green. You merge manually.
3. **Admin bypass** — Push branch, open PR, squash-merge immediately via admin bypass once CI is green.

Acknowledge the choice in one line, then proceed.

## Applying the mode

- **Local only:** Never `git push`, never open PRs.
- **Merge ready:** After completing work, push and open a PR. Stop — do not merge.
- **Admin bypass:** After completing work, push, open a PR, then run `gh pr merge --squash --admin`.
