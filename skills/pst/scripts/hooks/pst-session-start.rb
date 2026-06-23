#!/usr/bin/env ruby
# frozen_string_literal: true
# PST SessionStart hook: expose the current session id to later Bash tool calls
# by appending CLAUDE_SESSION_ID to the harness env file, so /pst can arm itself.
require_relative 'pst_common'

sid = Pst.session_id
env = ENV['CLAUDE_ENV_FILE']
File.open(env, 'a') { |f| f.puts "CLAUDE_SESSION_ID=#{sid}" } if env && !env.empty? && !sid.empty?

require 'fileutils'

cwd = Dir.pwd
proj = Pst.resolve_project(cwd)

if proj && !proj[:stacks].empty?
  stack_dir = File.join(Pst::HOME, 'stack')
  FileUtils.mkdir_p(stack_dir)
  File.write(File.join(stack_dir, sid), proj[:stacks].join("\n"))
  mods = proj[:stacks].map { |s| "stack:#{s}" }.join(', ')
  puts JSON.generate(
    'hookSpecificOutput' => {
      'hookEventName' => 'SessionStart',
      'additionalContext' =>
        "PST project '#{proj[:name]}' (#{proj[:source]}) active. " \
        "Auto-armed stack modules: #{mods}. Invoke them as needed."
    }
  )
else
  # Check if onboarding is appropriate
  skip_file = File.join(Pst::HOME, 'onboard-skip', sid)
  unless File.exist?(skip_file)
    root = Pst.git_root(cwd)
    detected = Pst.detect_stacks(root)
    sentinel = {
      'cwd' => cwd,
      'root' => root,
      'name_suggestion' => File.basename(root),
      'detected_stacks' => detected,
      'ts' => Time.now.utc.iso8601
    }
    onboard_dir = File.join(Pst::HOME, 'onboard')
    FileUtils.mkdir_p(onboard_dir)
    File.write(File.join(onboard_dir, sid), JSON.generate(sentinel))
    puts JSON.generate(
      'hookSpecificOutput' => {
        'hookEventName' => 'SessionStart',
        'additionalContext' =>
          'PST onboarding: this repo is not registered to any project (no .pst/project.json, ' \
          'no ~/.claude/pst/projects.json entry). On your FIRST reply to the user, before other work, ' \
          "read the sentinel at ~/.claude/pst/onboard/#{sid} (detected_stacks, name_suggestion, root), " \
          'then run the AskUserQuestion onboarding flow (PST onboarding spec section 3). ' \
          'Pre-select detected_stacks. After answers, write the config via the register command and ' \
          'remove the sentinel. If the user declines, run pst-project.rb onboard-skip and do not ask again ' \
          'this session. Do not block the user request on this; fold it into your first response.'
      }
    )
  end
end
