#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

class MergeModeHook
  EVENT = "SessionStart"

  DIRECTIVE = <<~TEXT.strip
    [pst] Before responding to anything else, call the AskUserQuestion tool to set the session's MERGE MODE.

    Question: "How should I handle changes from this session?"
    Header: "Merge mode"
    Options:
      1. "Local only" — No push, no PR. Changes stay on disk.
      2. "Merge ready" — Push branch, open PR, ensure CI is green. The user merges manually.
      3. "Admin bypass" — Push branch, open PR, then squash-merge via `gh pr merge --squash --admin` once CI is green. No other quality passes.

    After the user answers, acknowledge the choice in one line, then proceed. Apply the chosen mode for the rest of the session unless /pst changes it.
  TEXT

  def payload
    { hookSpecificOutput: { hookEventName: EVENT, additionalContext: DIRECTIVE } }
  end

  def emit(io = $stdout)
    io.puts(JSON.generate(payload))
  end
end

MergeModeHook.new.emit if __FILE__ == $PROGRAM_NAME
