#!/bin/bash
set -u
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# Write/Edit/MultiEdit 後の Markdown を textlint で検査する PostToolUse hook。
# 指摘・前提崩れ（未インストール / config 欠落）は exit 2 で stderr に流す。
# 対象外（.md/.mdx 以外、node_modules/.git 配下、file_path 無し）は exit 0 でスキップ。
# TEXTLINT_GUARD=off で無効化。

REPO="${TEXTLINT_GUARD_REPO:-/Users/mh4gf/ghq/github.com/MH4GF/claude-code}"
BIN="$REPO/node_modules/.bin/textlint"
CONFIG="$REPO/.textlintrc.json"

[ "${TEXTLINT_GUARD:-}" = "off" ] && exit 0

input=$(cat)
file_path=$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null) || exit 0
[ -n "$file_path" ] || exit 0

case "$file_path" in
  *.md|*.mdx) ;;
  *) exit 0 ;;
esac

case "$file_path" in
  */node_modules/*|*/.git/*) exit 0 ;;
esac

if [ ! -x "$BIN" ]; then
  echo "[textlint-guard] $REPO に textlint が未インストール。'cd $REPO && npm install' を実行してください" >&2
  exit 2
fi

if [ ! -f "$CONFIG" ]; then
  echo "[textlint-guard] $CONFIG が見つかりません" >&2
  exit 2
fi

cd "$REPO" || { echo "[textlint-guard] cd $REPO に失敗" >&2; exit 2; }
out=$("$BIN" -c "$CONFIG" --no-color "$file_path" 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
  printf '%s\n' "$out" >&2
  echo "" >&2
  echo "[textlint-guard] AI 文章 lint で指摘あり。上記を踏まえて編集を見直してください" >&2
  exit 2
fi
exit 0
