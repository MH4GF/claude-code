#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# Edit/Write/MultiEdit で新規コードコメントが追加されたら deny する PreToolUse hook。
# fail-open: 判定不能・対象外・スクリプト自体のエラーはすべて exit 0 (=allow)。
# COMMENT_GUARD=off で無効化。コメント記述は /write-code-comments スキル経由で許可する。

input=$(cat)

[[ "${COMMENT_GUARD:-}" == "off" ]] && exit 0

tool_name=$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null) || exit 0
case "$tool_name" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

file_path=$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null) || exit 0
[ -n "$file_path" ] || exit 0

ext=$(printf '%s' "$file_path" | tr '[:upper:]' '[:lower:]')
ext="${ext##*.}"
case "$ext" in
  ts|tsx|js|jsx|mjs|cjs|go) family=c ;;
  json)                     family=json ;;
  yaml|yml|py)              family=hash ;;
  *) exit 0 ;;
esac

awk_fam=c
[ "$family" = hash ] && awk_fam=hash

count_comments() {
  printf '%s\n' "$1" | awk -v fam="$awk_fam" '
  {
    line = $0
    sub(/^[ \t]+/, "", line)
    if (fam == "hash") {
      if (line ~ /^#!/) next
      if (line ~ /#[ \t]*(noqa|type:|pylint:|pragma:|yamllint|nosec|fmt:|mypy:)/) next
      gsub(/"[^"]*"/, "", line)
      gsub(/\047[^\047]*\047/, "", line)
      if (line ~ /(^|[ \t])#/) c++
    } else {
      if (line ~ /^#!/) next
      if (line ~ /\/\/go:/) next
      if (line ~ /(\/\/|\/\*)[ \t]*(eslint-|@ts-|@flow|biome-ignore|prettier-ignore|oxlint-|deno-lint-|c8 ignore|v8 ignore|istanbul ignore|nolint)/) next
      gsub(/"[^"]*"/, "", line)
      gsub(/\047[^\047]*\047/, "", line)
      gsub(/`[^`]*`/, "", line)
      if (line ~ /\/\// || line ~ /\/\*/) c++
    }
  }
  END { print c+0 }
  ' 2>/dev/null
}

# 1 edit の (old,new) からコメント行数の増分を算出。
# マルチライン文字列ガードに該当したら判定をスキップし 0 を返す。
contribution() {
  local old=$1 new=$2 bt cold cnew
  if [ "$family" = c ]; then
    bt=$(printf '%s' "$new" | tr -cd '`' | wc -c | tr -d ' ')
    [ -n "$bt" ] && [ $((bt % 2)) -ne 0 ] && { echo 0; return; }
  elif [ "$family" = hash ]; then
    printf '%s\n' "$new" | grep -qE ':[[:space:]]*[|>][+-]?[0-9]?[[:space:]]*$' && { echo 0; return; }
  fi
  cold=$(count_comments "$old"); cold=${cold:-0}
  cnew=$(count_comments "$new"); cnew=${cnew:-0}
  echo $((cnew - cold))
}

total=0
case "$tool_name" in
  Edit)
    old=$(jq -r '.tool_input.old_string // ""' <<<"$input" 2>/dev/null)
    new=$(jq -r '.tool_input.new_string // ""' <<<"$input" 2>/dev/null)
    c=$(contribution "$old" "$new"); total=$((total + ${c:-0}))
    ;;
  Write)
    [ -f "$file_path" ] || exit 0
    old=$(cat "$file_path" 2>/dev/null) || exit 0
    new=$(jq -r '.tool_input.content // ""' <<<"$input" 2>/dev/null)
    c=$(contribution "$old" "$new"); total=$((total + ${c:-0}))
    ;;
  MultiEdit)
    n=$(jq '.tool_input.edits | length' <<<"$input" 2>/dev/null)
    [ -n "$n" ] || exit 0
    i=0
    while [ "$i" -lt "$n" ] 2>/dev/null; do
      old=$(jq -r ".tool_input.edits[$i].old_string // \"\"" <<<"$input" 2>/dev/null)
      new=$(jq -r ".tool_input.edits[$i].new_string // \"\"" <<<"$input" 2>/dev/null)
      c=$(contribution "$old" "$new"); total=$((total + ${c:-0}))
      i=$((i + 1))
    done
    ;;
esac

[ "${total:-0}" -gt 0 ] 2>/dev/null || exit 0

# deny 候補。/write-code-comments フォークのマーカーが鮮度内なら許可する。
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
if [ -n "$cwd" ]; then
  marker="$cwd/.claude/tmp/.comment-guard-allow"
  if [ -f "$marker" ] && [ -n "$(find "$marker" -mmin -30 2>/dev/null)" ]; then
    exit 0
  fi
fi

printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"新規コードコメントの追加はブロックされています。コメントを削除して再実行してください。経緯や背景を残したい場合は、コードコメントではなく git のコミットメッセージに記載してください。コメントが本質的に必要な場合はユーザーに依頼してください。"}}'
exit 0
