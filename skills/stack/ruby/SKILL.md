---
name: stack:ruby
description: Ruby conventions for PST projects -- style, Bundler, RuboCop.
---

# Ruby Stack Module

## Style

- Frozen string literals at top of every file: `# frozen_string_literal: true`
- No `and`/`or` -- use `&&`/`||`.
- `do...end` for multi-line blocks, `{...}` for inline/chained blocks.
- Guard clauses over nested conditionals.
- `module_function` for stateless utility modules (see `pst_common.rb`).

## Bundler

- Pin gem versions in `Gemfile.lock`. Commit the lockfile.
- Use `bundle exec` to run any gem-provided binary.
- `bundle audit` before any release (checks for CVEs in locked gems).

## RuboCop

- Run `bundle exec rubocop` before committing.
- Auto-correct safe offenses: `bundle exec rubocop -A`.
- Shared `.rubocop.yml` at repo root inherits from `rubocop-rails-omakase` or equivalent.
- Never disable a cop project-wide without a comment explaining why.

## Testing

- RSpec. `spec/` mirrors `app/` structure.
- No `let!` when `let` suffices. No `before(:all)`.
- One expectation per example when practical.
