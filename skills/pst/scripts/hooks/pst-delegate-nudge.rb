#!/usr/bin/env ruby
# frozen_string_literal: true
# PST PostToolUse nudge: after a few inline implementation edits in an armed
# session, surface a non-blocking reminder to consider delegating to a background
# worktree agent (rule 1). NEVER blocks (PostToolUse). Silent under the foreground
# escape hatch (PST_FOREGROUND_OK=1 or ~/.claude/pst/foreground/<sid>). Counts
# only implementation-looking files; favors under-counting over false positives.
require_relative 'pst_common'
require 'fileutils'

exit 0 unless Pst.armed?

sid = Pst.session_id
exit 0 if ENV['PST_FOREGROUND_OK'] == '1'
exit 0 if File.exist?(File.join(Pst::HOME, 'foreground', sid))

path = (Pst.payload['tool_input'] || {})['file_path'].to_s
exit 0 if path.empty?

# Skip docs, config, lockfiles, data, dotfiles: only count implementation code.
base = File.basename(path).downcase
SKIP_EXT = /\.(md|markdown|mdx|lock|tfvars|json|ya?ml|toml|ini|cfg|conf|env|txt|csv|svg)$/i
exit 0 if path =~ SKIP_EXT || base.include?('lock') || base == 'gemfile' || base.start_with?('.')

THRESHOLD = 3
dir = File.join(Pst::HOME, 'delegate')
FileUtils.mkdir_p(dir)
counter = File.join(dir, sid)
n = begin
  File.read(counter).to_i
rescue StandardError
  0
end + 1

if n >= THRESHOLD
  File.write(counter, '0')
  puts JSON.generate(
    'hookSpecificOutput' => { 'hookEventName' => 'PostToolUse' },
    'additionalContext' =>
      "PST: #{n} inline implementation edits this session. If this is independent, " \
      'well-scoped, non-gating grunt work, delegate it to a background Sonnet agent ' \
      'in an isolated worktree (rule 1) instead of continuing inline. Run ' \
      '`pst-mode.rb foreground on` to silence this when foreground work is intentional.'
  )
else
  File.write(counter, n.to_s)
end
exit 0
