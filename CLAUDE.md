# skills

Canonical source of truth for Patrick's system-wide Claude Code skills and
hooks. What lives here is what gets installed; nothing else should be wired
system-wide.

## What's here

- `skills/<name>/SKILL.md` — a skill, registered by its YAML frontmatter
  (`name`, `description`). Currently: `pst`.
- `scripts/*.rb` — Ruby hook scripts and their shared libs. Files run as
  `ruby <path>`, never as bare commands.
- `install.rb` — installs everything: copies `scripts/*.rb` into
  `~/.claude/pst/bin`, symlinks each skill into `~/.claude/skills/`, and wires
  the hooks in `~/.claude/settings.json`.
- `test/*_test.rb` — minitest suites. Run with `ruby test/<name>_test.rb`.
- `.github/workflows/` — release tagging and a version-bump reminder.

## The pst skill

A merge-mode shim. On session start a `SessionStart` hook asks how changes
should be handled (Local only / Merge ready / Admin bypass); the choice is
persisted per session, restated each turn (`UserPromptSubmit`), recorded from
the answer (`PostToolUse`), and enforced as an advisory guard (`PreToolUse`).
See `skills/pst/SKILL.md`.

## Conventions

- **Ruby filenames are snake_case** and match their `require_relative` targets
  and the `MergeModeStore`-style constant they define.
- **Hooks fail silent.** Parse stdin through `HookEvent.read`; a bad payload
  yields an empty event, never a crash, because hooks fire on every event.
- **The installer is the source of truth.** It sweeps managed hooks across all
  events and wipes `~/.claude/pst/bin` before copying, so a reinstall makes the
  live install match this repo exactly. Re-run it after pulling.
- **Add a test with new behavior.** Keep the suites green before opening a PR.

## Versioning

Single `VERSION` file (semver). On merge to `main`, the `tag-on-version`
workflow tags the squash-merge commit when `VERSION` is new. Bump `VERSION` in
the same PR as a release-worthy change: minor for new capability, patch for
fixes. CI plumbing alone needs no bump. A `version-reminder` workflow warns when
shipped code changes without a bump.

## Workflow

This repo uses **squash merge**. Patrick reviews and merges every PR manually;
do not merge unless explicitly told. Commit messages must not contain em-dashes.
