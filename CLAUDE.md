# skills

Canonical source for Patrick's system-wide Claude Code skills and hooks:
`skills/<name>/SKILL.md`, Ruby hooks in `scripts/`, `install.rb`, `test/`.
What's installed is what's here.

## Rules

- Ruby filenames are snake_case, matching their `require_relative` and class name.
- Hooks fail silent: parse stdin via `HookEvent.read`, never crash.
- `install.rb` is the source of truth; it makes the live install match this repo. Re-run after pulling.
- New behavior ships with a test. Run `ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| require "./#{f}" }'`; keep it green before a PR.
- Bump `VERSION` (semver) with release-worthy changes: minor for capability, patch for fixes, none for CI.
- Squash merge. Patrick merges every PR manually, do not merge unless told. No em-dashes in commits.
