#!/bin/bash
set -u
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

REPO="${UNSLOP_GUARD_REPO:-/Users/mh4gf/ghq/github.com/MH4GF/claude-code}"
UNSLOP="${UNSLOP_BIN:-/Users/mh4gf/ghq/github.com/MH4GF/unslop/target/release/unslop}"
CONFIG="$REPO/.textlintrc.json"

[ "${UNSLOP_GUARD:-}" = "off" ] && exit 0

input=$(cat)
file_path=$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null) || exit 0
[ -n "$file_path" ] || exit 0

case "$file_path" in
  *.md|*.mdx|*.txt) ;;
  *) exit 0 ;;
esac

case "$file_path" in
  */node_modules/*|*/.git/*|*/.claude/tmp/*) exit 0 ;;
esac

if [ -r "$file_path" ]; then
  perl -CSD -0777 -ne 'exit(/\p{Hiragana}|\p{Katakana}|\p{Han}/ ? 0 : 1)' "$file_path" 2>/dev/null
  case $? in
    1) exit 0 ;;
  esac
fi

if [ ! -x "$UNSLOP" ]; then
  echo "[unslop-guard] $UNSLOP がない。'cd ~/ghq/github.com/MH4GF/unslop && cargo build --release' を実行してください" >&2
  exit 2
fi

if [ ! -f "$CONFIG" ]; then
  echo "[unslop-guard] $CONFIG が見つかりません" >&2
  exit 2
fi

cd "$REPO" || { echo "[unslop-guard] cd $REPO に失敗" >&2; exit 2; }
out=$("$UNSLOP" -c "$CONFIG" --no-color "$file_path" 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
  printf '%s\n' "$out" >&2
  echo "" >&2
  echo "[unslop-guard] AI 文章 lint で指摘あり。上記を踏まえて編集を見直してください" >&2
  exit 2
fi
exit 0
