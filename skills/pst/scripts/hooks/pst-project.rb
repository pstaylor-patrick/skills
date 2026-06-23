#!/usr/bin/env ruby
# frozen_string_literal: true
# PST project registration CLI.
# Usage:
#   pst-project.rb register <name> --stacks <csv> [--global]
#   pst-project.rb list
#   pst-project.rb which
#   pst-project.rb unregister <name>
#   pst-project.rb onboard-skip
require_relative 'pst_common'
require 'json'
require 'fileutils'

verb = ARGV.shift.to_s

case verb
when 'register'
  name = ARGV.shift.to_s
  abort "Usage: pst-project.rb register <name> --stacks <csv> [--global]" if name.empty?
  global = ARGV.delete('--global')
  stacks_idx = ARGV.index('--stacks')
  abort "Missing --stacks argument" unless stacks_idx
  raw_stacks = ARGV[stacks_idx + 1].to_s.split(',').map(&:strip).reject(&:empty?)
  invalid = raw_stacks - Pst::VALID_STACKS
  abort "Unknown stacks: #{invalid.join(', ')}. Valid: #{Pst::VALID_STACKS.join(', ')}" if invalid.any?
  stacks = Pst.topo_sort_stacks(raw_stacks)
  if global
    path = File.join(Pst::HOME, 'projects.json')
    data = File.exist?(path) ? JSON.parse(File.read(path)) : { 'version' => 1, 'projects' => [] }
    root = Pst.git_root(Dir.pwd)
    existing = data['projects'].find { |p| p['name'] == name }
    if existing
      existing['stacks'] = stacks
      existing['repos'] = (Array(existing['repos']) + [root]).uniq
    else
      data['projects'] << { 'name' => name, 'stacks' => stacks, 'repos' => [root] }
    end
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(data))
    puts "Registered '#{name}' globally with stacks: #{stacks.join(', ')}"
  else
    root = Pst.git_root(Dir.pwd)
    pst_dir = File.join(root, '.pst')
    FileUtils.mkdir_p(pst_dir)
    File.write(File.join(pst_dir, 'project.json'), JSON.pretty_generate({ 'version' => 1, 'name' => name, 'stacks' => stacks }))
    puts "Registered '#{name}' locally with stacks: #{stacks.join(', ')}"
  end
  # Arm immediately for this session
  sid = ENV['CLAUDE_SESSION_ID'].to_s
  unless sid.empty?
    stack_dir = File.join(Pst::HOME, 'stack')
    FileUtils.mkdir_p(stack_dir)
    File.write(File.join(stack_dir, sid), stacks.join("\n"))
  end

when 'list'
  projects = Pst.load_global_projects
  if projects.empty?
    puts "(no global projects registered)"
  else
    projects.each { |p| puts "#{p['name']}: #{Array(p['stacks']).join(', ')} (repos: #{Array(p['repos']).join(', ')})" }
  end

when 'which'
  proj = Pst.resolve_project(Dir.pwd)
  if proj
    puts "#{proj[:name]} (#{proj[:source]}): #{proj[:stacks].join(', ')}"
  else
    puts "(no project registered for #{Dir.pwd})"
  end

when 'unregister'
  name = ARGV.shift.to_s
  abort "Usage: pst-project.rb unregister <name>" if name.empty?
  path = File.join(Pst::HOME, 'projects.json')
  if File.exist?(path)
    data = JSON.parse(File.read(path))
    before = data['projects'].size
    data['projects'].reject! { |p| p['name'] == name }
    File.write(path, JSON.pretty_generate(data))
    puts before == data['projects'].size ? "Not found: #{name}" : "Unregistered: #{name}"
  else
    puts "(no global projects file)"
  end

when 'onboard-skip'
  sid = ENV['CLAUDE_SESSION_ID'].to_s
  abort "CLAUDE_SESSION_ID not set" if sid.empty?
  skip_dir = File.join(Pst::HOME, 'onboard-skip')
  FileUtils.mkdir_p(skip_dir)
  FileUtils.touch(File.join(skip_dir, sid))
  FileUtils.rm_f(File.join(Pst::HOME, 'onboard', sid))
  puts "Onboarding skipped for this session."

else
  abort "Unknown verb: #{verb}. Use: register, list, which, unregister, onboard-skip"
end
