# PST — Merge Mode Shim

## Session start

On the **first user message** of every session, call `AskUserQuestion` before addressing any other content:

**Question:** "How should I handle changes from this session?"
**Header:** Merge mode
**Options:**

1. **Local only** — No push, no PR. Changes stay on disk.
2. **Merge ready** — Push branch, open PR, ensure CI is green. You merge manually.
3. **Admin bypass** — Push branch, open PR, squash-merge immediately via admin bypass once CI is green.

Acknowledge the choice in one line, then proceed with the session normally.

## /pst

Re-ask the merge mode question above. Acknowledge the updated choice in one line.

## Applying the mode

- **Local only:** Never `git push`, never open PRs.
- **Merge ready:** After completing work, push and open a PR. Stop — do not merge.
- **Admin bypass:** After completing work, push, open a PR, then run `gh pr merge --squash --admin`.
