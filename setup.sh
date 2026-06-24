#!/bin/sh
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"

# Execution guard: worktree や symphony workspace から実行されると、
# ~/.claude/{CLAUDE.md,settings.json,commands,hooks,skills} の symlink が
# ephemeral なパスを指して壊れる (MH-44)。
case "$ROOT" in
  */.symphony/workspaces/*|*/.claude/worktrees/*)
    cat >&2 <<EOF
setup.sh は worktree や symphony workspace から実行できません。
  Executed from: $ROOT

このまま実行すると ~/.claude の symlink が一時的なパスを指し、
workspace 片付け後に壊れます。正規 clone から実行してください:

  cd ~/ghq/github.com/MH4GF/claude-code && ./setup.sh
EOF
    exit 1
    ;;
esac

# Strict check: ghq が使える環境では canonical clone path と比較する。
if command -v ghq >/dev/null 2>&1; then
  EXPECTED_ROOT="$(ghq root 2>/dev/null)/github.com/MH4GF/claude-code"
  if [ -d "$EXPECTED_ROOT" ] && [ "$ROOT" != "$EXPECTED_ROOT" ]; then
    cat >&2 <<EOF
setup.sh は canonical clone からのみ実行できます。
  Executed from: $ROOT
  Expected:      $EXPECTED_ROOT

正規 clone から実行してください:

  cd "$EXPECTED_ROOT" && ./setup.sh
EOF
    exit 1
  fi
fi

USER_SCOPE="$ROOT/user-scope"

jq . "$USER_SCOPE/settings.json" > /dev/null

mkdir -p ~/.claude

ln -sf "$USER_SCOPE/CLAUDE.md" ~/.claude/CLAUDE.md
ln -sf "$USER_SCOPE/settings.json" ~/.claude/settings.json
ln -sfn "$USER_SCOPE/commands" ~/.claude/commands
ln -sfn "$USER_SCOPE/hooks" ~/.claude/hooks
ln -sfn "$USER_SCOPE/skills" ~/.claude/skills
ln -sfn "$USER_SCOPE/agents" ~/.claude/agents
