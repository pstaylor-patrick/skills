#!/usr/bin/env ruby
# frozen_string_literal: true
# PST UserPromptSubmit hook: re-inject a compressed rule checklist each turn so
# the doctrine cannot drift over a long session. Inert unless this session is
# armed. For UserPromptSubmit, plain stdout is added to the model's context.
require_relative 'pst_common'

Pst.allow! unless Pst.armed?

puts <<~PST
  [PST mode active] Standing rules (full doctrine in the /pst skill):
  1 swarm: foreground orchestrates, background implements. 2 tiers: Opus/high foreground, Sonnet/medium background, Haiku/low trivial; set model+effort explicitly. 3 isolated worktree per file-mutating agent. 4 tidy, prompt before pruning. 5 PR + squash, never merge red CI. 6 fix CI at root cause, no band-aids. 7 adversarial review + implement fixes before merge. 8 local k8s gate before any remote. 9 QA arsenal (E2E, a11y, ZAP, k6) with discernment. 10 no-reply commit identity. 11 no em dashes. 12 de-slop, prose and code. 13 run to completion. 14 prove it works: green + real E2E. 15 refactor: two hats, under green tests, rule of three.
PST
