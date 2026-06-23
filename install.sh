#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_SKILLS="$HOME/.claude/skills"

mkdir -p "$CLAUDE_SKILLS/pst"
ln -sf "$REPO/skills/pst/SKILL.md" "$CLAUDE_SKILLS/pst/SKILL.md"

echo "pst shim installed -> $CLAUDE_SKILLS/pst/SKILL.md"
