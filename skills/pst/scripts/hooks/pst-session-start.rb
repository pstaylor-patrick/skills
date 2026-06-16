#!/usr/bin/env ruby
# frozen_string_literal: true
# PST SessionStart hook: expose the current session id to later Bash tool calls
# by appending CLAUDE_SESSION_ID to the harness env file, so /pst can arm itself.
require 'json'

sid =
  begin
    JSON.parse($stdin.read)['session_id'].to_s
  rescue StandardError
    ''
  end

env = ENV['CLAUDE_ENV_FILE']
if env && !env.empty? && !sid.empty?
  File.open(env, 'a') { |f| f.puts "CLAUDE_SESSION_ID=#{sid}" }
end
