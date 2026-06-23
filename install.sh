#!/usr/bin/env bash
set -euo pipefail

# pst merge-mode shim installer.
#
# Durable + idempotent:
#   1. Copies hook scripts into ~/.claude/pst/bin/ (survives this repo moving
#      or being deleted — settings.json points at the copy, not the repo).
#   2. Symlinks the SKILL.md for the /pst manual re-invoke path.
#   3. Patches ~/.claude/settings.json to wire the SessionStart hook, without
#      disturbing any other hooks already configured there.

REPO="$(cd "$(dirname "$0")" && pwd)"
CLAUDE="$HOME/.claude"
BIN="$CLAUDE/pst/bin"
SKILLS="$CLAUDE/skills/pst"
SETTINGS="$CLAUDE/settings.json"

RUBY="$(command -v ruby)"

mkdir -p "$BIN" "$SKILLS"

# 1. Copy hook scripts (durable — not symlinked).
cp "$REPO/scripts/pst-session-start.rb" "$BIN/pst-session-start.rb"
chmod +x "$BIN/pst-session-start.rb"

# 2. Symlink the skill for /pst.
ln -sf "$REPO/skills/pst/SKILL.md" "$SKILLS/SKILL.md"

# 3. Idempotently wire the SessionStart hook into settings.json.
"$RUBY" -rjson -e '
  settings_path = ARGV[0]
  ruby_bin      = ARGV[1]
  script        = ARGV[2]
  command       = "#{ruby_bin} #{script}"

  settings = File.exist?(settings_path) ? JSON.parse(File.read(settings_path)) : {}
  settings["hooks"] ||= {}
  settings["hooks"]["SessionStart"] ||= []

  # Drop any existing pst-session-start entries, then add ours back once.
  settings["hooks"]["SessionStart"].each do |group|
    next unless group.is_a?(Hash) && group["hooks"].is_a?(Array)
    group["hooks"].reject! { |h| h["command"].to_s.include?("pst-session-start.rb") }
  end
  settings["hooks"]["SessionStart"].reject! { |g| g.is_a?(Hash) && (g["hooks"] || []).empty? }

  settings["hooks"]["SessionStart"] << {
    "hooks" => [{ "type" => "command", "command" => command }]
  }

  File.write(settings_path, JSON.pretty_generate(settings) + "\n")
' "$SETTINGS" "$RUBY" "$BIN/pst-session-start.rb"

echo "pst merge-mode shim installed:"
echo "  hook script -> $BIN/pst-session-start.rb"
echo "  skill       -> $SKILLS/SKILL.md"
echo "  settings    -> $SETTINGS (SessionStart wired)"
