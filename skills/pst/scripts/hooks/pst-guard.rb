#!/usr/bin/env ruby
# frozen_string_literal: true
# PST PreToolUse guard: deterministically block em dashes in writes and git
# commit messages. Inert unless this session is armed
# (~/.claude/pst/armed/<session_id>). Reads the hook JSON payload on stdin and
# signals a deny via the permissionDecision field per the PreToolUse contract.
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
end

allow
