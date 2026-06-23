#!/bin/bash
set -u
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# Write/Edit/MultiEdit 後の SKILL.md frontmatter description に「呼び出し元」
# 「bg session」「Symphony」「1 turn 内に完結」「人間判断必須」「無人で動かす」
# 等の呼び出し文脈依存表現が含まれていれば exit 2 で block する PostToolUse hook。
# skill は呼び出し元に依存せず動作だけを述べる self-contained 記述にする。
# SKILL_MD_GUARD=off で無効化する。

[ "${SKILL_MD_GUARD:-}" = "off" ] && exit 0

input=$(cat)
file_path=$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null) || exit 0
[ -n "$file_path" ] || exit 0

case "$file_path" in
  */SKILL.md) ;;
  *) exit 0 ;;
esac

[ -r "$file_path" ] || exit 0

description=$(awk '
  BEGIN { in_fm = 0; in_desc = 0; buf = "" }
  NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
  in_fm && /^---[[:space:]]*$/ { exit }
  in_fm && /^description:[[:space:]]*/ {
    sub(/^description:[[:space:]]*/, "")
    buf = $0
    in_desc = 1
    next
  }
  in_fm && in_desc && /^[a-zA-Z_][a-zA-Z0-9_-]*:/ { exit }
  in_fm && in_desc {
    line = $0
    sub(/^[[:space:]]+/, " ", line)
    buf = buf line
  }
  END { print buf }
' "$file_path")

[ -n "$description" ] || exit 0

banned=(
  '呼び出し元'
  'バックグラウンドセッション'
  '1 turn 内に完結'
  '1 turn 内で完結'
  '1 turn で完結'
  '人間判断必須'
  '人間の判断必須'
  '無人で動かす'
  '無人運転'
)
banned_ci=(
  'bg session'
  'background session'
  'Symphony'
)

hits=""
for pat in "${banned[@]}"; do
  if printf '%s' "$description" | grep -qF -- "$pat"; then
    hits="${hits}  - \"${pat}\"\n"
  fi
done
for pat in "${banned_ci[@]}"; do
  if printf '%s' "$description" | grep -qiF -- "$pat"; then
    hits="${hits}  - \"${pat}\" (case-insensitive)\n"
  fi
done

[ -n "$hits" ] || exit 0

{
  echo "[skill-md-guard] $file_path の frontmatter description に呼び出し文脈依存表現が含まれている"
  echo ""
  echo "検出された禁止 phrase:"
  printf '%b' "$hits"
  echo ""
  echo "skill は呼び出し元 / 動作文脈に依存せず、動作だけを述べる self-contained 記述にする"
  echo "SKILL_MD_GUARD=off で個別 off できる (推奨しない)"
} >&2
exit 2
