#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# Edit/Write/MultiEdit で SKILL.md / commands/*.md / CLAUDE.md の散文が
# net で threshold 行を超えて増えたら deny する PreToolUse hook。
# fail-open: 判定不能・対象外・スクリプト自体のエラーは exit 0 (=allow)。
# SKILL_PROSE_GUARD=off で無効化、SKILL_PROSE_GUARD_THRESHOLD=N でしきい値上書き。

set -u

[ "${SKILL_PROSE_GUARD:-}" = "off" ] && exit 0

input=$(cat)

tool_name=$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null) || exit 0
case "$tool_name" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

file_path=$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null) || exit 0
[ -n "$file_path" ] || exit 0

case "$file_path" in
  */SKILL.md|*/commands/*.md|*/CLAUDE.md) ;;
  *) exit 0 ;;
esac

# 散文行 = コード fence (``` で囲まれた範囲) の外で、
# blank / heading (#) / list (-/*/+/番号./>) / table (|) / front matter (---) ではない行。
count_prose_lines() {
  printf '%s\n' "$1" | awk '
    BEGIN { in_fence = 0; in_fm = 0; line_no = 0 }
    {
      line_no++
      line = $0
      sub(/[ \t]+$/, "", line)

      if (line_no == 1 && line == "---") { in_fm = 1; next }
      if (in_fm) {
        if (line == "---") in_fm = 0
        next
      }

      if (line ~ /^[ \t]*```/) { in_fence = !in_fence; next }
      if (in_fence) next

      if (line ~ /^[ \t]*$/) next
      if (line ~ /^[ \t]*#/) next
      if (line ~ /^[ \t]*([-*+]|[0-9]+\.|>)([ \t]|$)/) next
      if (line ~ /^[ \t]*\|/) next

      c++
    }
    END { print c+0 }
  ' 2>/dev/null
}

prose_delta() {
  local old=$1 new=$2 oldP newP
  oldP=$(count_prose_lines "$old"); oldP=${oldP:-0}
  newP=$(count_prose_lines "$new"); newP=${newP:-0}
  echo $((newP - oldP))
}

total=0
case "$tool_name" in
  Edit)
    old=$(jq -r '.tool_input.old_string // ""' <<<"$input" 2>/dev/null)
    new=$(jq -r '.tool_input.new_string // ""' <<<"$input" 2>/dev/null)
    d=$(prose_delta "$old" "$new")
    total=$((total + ${d:-0}))
    ;;
  Write)
    if [ -f "$file_path" ]; then
      old=$(cat "$file_path" 2>/dev/null) || exit 0
    else
      old=""
    fi
    new=$(jq -r '.tool_input.content // ""' <<<"$input" 2>/dev/null)
    d=$(prose_delta "$old" "$new")
    total=$((total + ${d:-0}))
    ;;
  MultiEdit)
    n=$(jq '.tool_input.edits | length' <<<"$input" 2>/dev/null)
    [ -n "$n" ] || exit 0
    i=0
    while [ "$i" -lt "$n" ] 2>/dev/null; do
      old=$(jq -r ".tool_input.edits[$i].old_string // \"\"" <<<"$input" 2>/dev/null)
      new=$(jq -r ".tool_input.edits[$i].new_string // \"\"" <<<"$input" 2>/dev/null)
      d=$(prose_delta "$old" "$new")
      total=$((total + ${d:-0}))
      i=$((i + 1))
    done
    ;;
esac

threshold=${SKILL_PROSE_GUARD_THRESHOLD:-3}

[ "${total:-0}" -gt "$threshold" ] 2>/dev/null || exit 0

reason="skill 編集で散文行が net ${total} 行追加されています (しきい値: ${threshold} 行)。次の観点で diff を見直してから再実行してください

1. 判定 / 分岐ロジックはコマンド節 (実行可能 snippet) に集約する
2. description / 目的 / 手順は最小置換に留め新規節を増やさない
3. 手順への補足は 1 行に圧縮し、サブステップを増やさない
4. 差分の経緯解説は commit message と PR description に書き、skill 本文には残さない

意図的な追加であれば SKILL_PROSE_GUARD=off で一時的に無効化、SKILL_PROSE_GUARD_THRESHOLD=N でしきい値を上書きできます。"

jq -nc --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
