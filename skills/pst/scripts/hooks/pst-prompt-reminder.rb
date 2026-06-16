#!/usr/bin/env ruby
# frozen_string_literal: true
# PST UserPromptSubmit hook: re-inject the compressed rule checklist each turn so
# the doctrine cannot drift over a long session. Leads with the delegate-by-default
# test (rule 1, the most easily-decayed rule) unless foreground mode is set. Inert
# unless armed. For UserPromptSubmit, plain stdout is added to the model context.
require_relative 'pst_common'

Pst.allow! unless Pst.armed?

foreground = File.exist?(File.join(Pst::HOME, 'foreground', Pst.session_id))
unless foreground
  puts 'DELEGATE FIRST (rule 1): work that is independent, well-scoped, and not a ' \
       'gating judgment goes to a background Sonnet agent in an isolated worktree, ' \
       'not inline. Foreground is for conversation, planning, choices, agent ' \
       'orchestration, and final validation.'
end

puts <<~PST
  [PST mode active] Standing rules (full doctrine in the /pst skill):
  1 delegate by default. 2 tiers: Opus/high foreground, Sonnet/medium background, Haiku/low trivial; set model explicitly. 3 isolated worktree per file-mutating agent. 4 tidy, prompt before pruning. 5 PR + squash, never merge red CI. 6 fix CI at root cause, no band-aids. 7 adversarial review + implement fixes before merge. 8 local k8s gate before any remote. 9 QA arsenal (E2E, a11y, ZAP, k6) with discernment. 10 no-reply commit identity. 11 no em dashes. 12 de-slop, prose and code. 13 run to completion. 14 prove it works: green + real E2E. 15 refactor: two hats, under green tests, rule of three. 16 brevity (soft): paragraphs <=320 chars, flat bullets <=160 chars, <=5 bullets (requested PR/Jira lists may exceed).
PST
