#!/usr/bin/env ruby
# frozen_string_literal: true
# PST PreToolUse guard. Deterministic enforcement, inert unless this session is
# armed (~/.claude/pst/armed/<session_id>). Reads the hook JSON payload on stdin
# and signals a deny via the permissionDecision field per the PreToolUse
# contract. Two policies:
#   1. No em dash (U+2014) in Write/Edit content or git commit messages.
#   2. Merge guard: block `gh pr merge` unless every CI check has passed
#      (rule 4). Override with PST_ALLOW_RED_MERGE=1.
require 'json'

EM = [0x2014].pack('U') # em dash (long dash); built so no literal glyph appears

def allow
  exit 0
end

def deny(reason)
  puts JSON.generate(
    'hookSpecificOutput' => {
      'hookEventName' => 'PreToolUse',
      'permissionDecision' => 'deny',
      'permissionDecisionReason' => reason
    }
  )
  exit 0
end

# Block `gh pr merge` unless CI is fully green. Returns normally to allow.
def merge_guard(cmd, cwd)
  return unless cmd =~ /\bgh\s+pr\s+merge\b/
  return if ENV['PST_ALLOW_RED_MERGE'] == '1'

  require 'open3'
  require 'timeout'
  pr = cmd[%r{\bgh\s+pr\s+merge\b.*?\s(\d+|https?://\S+)}, 1]
  argv = ['gh', 'pr', 'checks']
  argv << pr if pr
  dir = cwd && File.directory?(cwd) ? cwd : Dir.pwd

  out = ''
  status = nil
  begin
    Timeout.timeout(25) { out, status = Open3.capture2e(*argv, chdir: dir) }
  rescue Timeout::Error
    deny('PST merge guard: timed out verifying CI status. Rule 4 requires fully ' \
         'green CI before merge. Re-run after CI reports, or set ' \
         'PST_ALLOW_RED_MERGE=1 to override.')
  rescue StandardError => e
    deny("PST merge guard: could not verify CI status (#{e.class}). Set " \
         'PST_ALLOW_RED_MERGE=1 to override if you are certain CI is green.')
  end

  code = status&.exitstatus
  return if code.zero? # all checks passed
  return if out =~ /no check|no checks reported/i # no CI to gate; allow

  summary = out.to_s.lines.first(12).map(&:rstrip).join("\n")
  deny("PST merge guard: CI is not fully green, so rule 4 blocks this merge " \
       "(gh pr checks exit #{code}: pending or failing checks). Wait for all " \
       "checks to pass, or set PST_ALLOW_RED_MERGE=1 to override.\n#{summary}")
end

data =
  begin
    JSON.parse($stdin.read)
  rescue StandardError
    allow
  end

sid = data['session_id'].to_s
allow if sid.empty?
allow unless File.exist?(File.expand_path("~/.claude/pst/armed/#{sid}"))

tool = data['tool_name'].to_s
ti = data['tool_input'] || {}

case tool
when 'Write', 'Edit', 'MultiEdit', 'NotebookEdit'
  texts = %w[content new_string new_source].map { |k| ti[k] }.select { |v| v.is_a?(String) }
  (ti['edits'] || []).each { |e| texts << e['new_string'] if e.is_a?(Hash) && e['new_string'].is_a?(String) }
  if texts.any? { |t| t.include?(EM) }
    deny('PST mode: the em dash (U+2014) is not allowed. Rewrite with commas, ' \
         'colons, parentheses, or two sentences before writing this file.')
  end
when 'Bash'
  cmd = ti['command'].to_s
  if cmd.include?('git commit') && cmd.include?(EM)
    deny('PST mode: em dash (U+2014) detected in a git commit message. ' \
         'Rephrase the message without em dashes.')
  end
  merge_guard(cmd, data['cwd'])
end

allow
