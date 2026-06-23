#!/usr/bin/env ruby
# frozen_string_literal: true

# Merge-mode shim installer.
#
# Durable + idempotent:
#   1. Copies hook scripts into ~/.claude/pst/bin/ (survives this repo moving
#      or being deleted — settings.json points at the copy, not the repo).
#   2. Symlinks SKILL.md for the /pst manual re-invoke path.
#   3. Patches ~/.claude/settings.json to wire the SessionStart hook, leaving
#      every other configured hook untouched.

require "json"
require "fileutils"

REPO     = __dir__
HOME     = Dir.home
BIN      = File.join(HOME, ".claude", "pst", "bin")
SKILLS   = File.join(HOME, ".claude", "skills", "pst")
SETTINGS = File.join(HOME, ".claude", "settings.json")

# Resolve a ruby interpreter for the hook command. Prefer the one running this
# installer (RbConfig), so the hook uses the same ruby the user installed with.
require "rbconfig"
RUBY = File.join(RbConfig::CONFIG["bindir"], RbConfig::CONFIG["ruby_install_name"])
abort "could not resolve a ruby interpreter" unless File.executable?(RUBY)

FileUtils.mkdir_p(BIN)
FileUtils.mkdir_p(SKILLS)

# 1. Copy hook scripts (durable — not symlinked).
hook_src = File.join(REPO, "scripts", "session-start.rb")
hook_dst = File.join(BIN, "session-start.rb")
FileUtils.cp(hook_src, hook_dst)
FileUtils.chmod(0o755, hook_dst)

# 2. Symlink the skill for /pst.
FileUtils.ln_sf(File.join(REPO, "skills", "pst", "SKILL.md"),
                File.join(SKILLS, "SKILL.md"))

# 3. Idempotently wire the SessionStart hook into settings.json.
settings = File.exist?(SETTINGS) ? JSON.parse(File.read(SETTINGS)) : {}
settings["hooks"] ||= {}
settings["hooks"]["SessionStart"] ||= []

command = "#{RUBY} #{hook_dst}"

# Remove any SessionStart hook whose command points into our managed bin dir,
# then add ours back once. This cleans up entries from prior installs (any
# script name) without touching hooks owned by other tools.
settings["hooks"]["SessionStart"].each do |group|
  next unless group.is_a?(Hash) && group["hooks"].is_a?(Array)
  group["hooks"].reject! { |h| h["command"].to_s.include?(BIN) }
end
settings["hooks"]["SessionStart"].reject! do |group|
  group.is_a?(Hash) && (group["hooks"] || []).empty?
end
settings["hooks"]["SessionStart"] << {
  "hooks" => [{ "type" => "command", "command" => command }]
}

# Back up, then write atomically (temp file on the same dir + rename).
if File.exist?(SETTINGS)
  FileUtils.cp(SETTINGS, "#{SETTINGS}.bak")
end
tmp = "#{SETTINGS}.tmp"
File.write(tmp, JSON.pretty_generate(settings) + "\n")
File.rename(tmp, SETTINGS)

puts "merge-mode shim installed:"
puts "  hook script -> #{hook_dst}"
puts "  skill       -> #{File.join(SKILLS, 'SKILL.md')}"
puts "  settings    -> #{SETTINGS} (SessionStart wired; backup at #{SETTINGS}.bak)"
