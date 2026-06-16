#!/usr/bin/env ruby
# frozen_string_literal: true
# PST SessionEnd hook: remove this session's armed marker so the guard goes inert.
require 'json'
require 'fileutils'

sid =
  begin
    JSON.parse($stdin.read)['session_id'].to_s
  rescue StandardError
    ''
  end

FileUtils.rm_f(File.expand_path("~/.claude/pst/armed/#{sid}")) unless sid.empty?
