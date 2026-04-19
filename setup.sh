#!/bin/sh
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
USER_SCOPE="$ROOT/user-scope"

jq . "$USER_SCOPE/settings.json" > /dev/null

mkdir -p ~/.claude

ln -sf "$USER_SCOPE/CLAUDE.md" ~/.claude/CLAUDE.md
ln -sf "$USER_SCOPE/settings.json" ~/.claude/settings.json
ln -sfn "$USER_SCOPE/commands" ~/.claude/commands
ln -sfn "$USER_SCOPE/hooks" ~/.claude/hooks
ln -sfn "$USER_SCOPE/skills" ~/.claude/skills
