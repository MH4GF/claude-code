#!/bin/sh
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"

# Execution guard: worktree や symphony workspace から実行されると、
# ~/.claude/{CLAUDE.md,settings.json,commands,hooks,skills} の symlink が
# ephemeral なパスを指して壊れる (MH-44)。
# CLAUDE_SETUP_SKIP_LOCATION_GUARD=1 で bypass する (tests/test-setup.sh 用)。
if [ -z "${CLAUDE_SETUP_SKIP_LOCATION_GUARD:-}" ]; then
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
fi

USER_SCOPE="$ROOT/user-scope"

jq . "$USER_SCOPE/settings.json" > /dev/null

mkdir -p ~/.claude

ln -sf "$USER_SCOPE/CLAUDE.md" ~/.claude/CLAUDE.md
ln -sfn "$USER_SCOPE/commands" ~/.claude/commands
ln -sfn "$USER_SCOPE/hooks" ~/.claude/hooks
ln -sfn "$USER_SCOPE/skills" ~/.claude/skills

# Per-user ~/.claude/settings.json
# - overlay 有り (`user-scope/settings.<user>.overlay.json`) → base + overlay を jq で deep merge して real file として書き出す
# - overlay 無し → 従来通り symlink する
# 公式 Claude Code は user-level の settings.local.json を持たないため、
# user 単位の差分は user-scope side で吸収する (MH-105)。
# CLAUDE_SETUP_USER で user 名 override 可能 (tests/test-setup.sh 用)。
USER_NAME="${CLAUDE_SETUP_USER:-$(id -un)}"
OVERLAY="$USER_SCOPE/settings.$USER_NAME.overlay.json"
TARGET="$HOME/.claude/settings.json"

if [ -f "$OVERLAY" ]; then
  jq . "$OVERLAY" > /dev/null
  rm -f "$TARGET"
  jq -s '.[0] * .[1]' "$USER_SCOPE/settings.json" "$OVERLAY" > "$TARGET"
  echo "settings.json materialized with overlay for user=$USER_NAME"
else
  ln -sf "$USER_SCOPE/settings.json" "$TARGET"
  echo "settings.json symlinked (no overlay for user=$USER_NAME)"
fi
