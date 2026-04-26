#!/usr/bin/env bash
set -e

SKILL_DIR="$HOME/.claude/skills/standup"
REPO_BASE="https://raw.githubusercontent.com/rrjoson/claude-skills/main/skills/standup"

echo "Installing standup skill..."

mkdir -p "$SKILL_DIR"

# Download SKILL.md (always overwrite — safe to re-run for updates)
curl -fsSL "$REPO_BASE/SKILL.md" -o "$SKILL_DIR/skill.md"

# Never overwrite existing config
if [ ! -f "$SKILL_DIR/config.json" ]; then
  curl -fsSL "$REPO_BASE/config.example.json" -o "$SKILL_DIR/config.example.json"
  echo "  config.example.json written for reference."
else
  echo "  Existing config.json preserved."
fi

echo ""
echo "Done. Run /standup in Claude Code to get started."
echo "First run will ask for your work email and set everything up automatically."
