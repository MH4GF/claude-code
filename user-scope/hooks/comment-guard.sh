#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# Edit/Write/MultiEdit で新規コードコメントが追加されたら deny する PreToolUse hook。
# fail-open: 判定不能・対象外・スクリプト自体のエラーはすべて exit 0 (=allow)。
# COMMENT_GUARD=off で無効化。コメント記述は /write-code-comments スキル経由で許可する。

REPO="${UNSLOP_GUARD_REPO:-/Users/mh4gf/ghq/github.com/MH4GF/claude-code}"
UNSLOP="${UNSLOP_BIN:-/Users/mh4gf/ghq/github.com/MH4GF/unslop/target/release/unslop}"
CONFIG="$REPO/.textlintrc.json"

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
  sql)                      family=sql ;;
  *) exit 0 ;;
esac

case "$family" in
  hash) awk_fam=hash ;;
  sql)  awk_fam=sql ;;
  *)    awk_fam=c ;;
esac

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
    } else if (fam == "sql") {
      if (line ~ /^#!/) next
      gsub(/"[^"]*"/, "", line)
      gsub(/\047[^\047]*\047/, "", line)
      gsub(/`[^`]*`/, "", line)
      if (line ~ /--/ || line ~ /\/\*/) c++
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

# 単一行コメントの本文 (記号除去後) を 1 行 1 コメントで標準出力へ。
# count_comments と同じ無視ルール (shebang・lint directive) を踏襲する。
# multi-line ブロックコメント (/* ... */・""" ... """) はスコープ外。
extract_comment_bodies() {
  printf '%s\n' "$1" | awk -v fam="$awk_fam" '
  {
    line = $0
    sub(/^[ \t]+/, "", line)
    if (fam == "hash") {
      if (line ~ /^#!/) next
      if (line ~ /#[ \t]*(noqa|type:|pylint:|pragma:|yamllint|nosec|fmt:|mypy:)/) next
      gsub(/"[^"]*"/, "", line)
      gsub(/\047[^\047]*\047/, "", line)
      idx = match(line, /(^|[ \t])#/)
      if (idx > 0) {
        body = substr(line, idx + RLENGTH)
        sub(/^[ \t]+/, "", body)
        sub(/[ \t]+$/, "", body)
        if (body != "") print body
      }
    } else if (fam == "sql") {
      if (line ~ /^#!/) next
      gsub(/"[^"]*"/, "", line)
      gsub(/\047[^\047]*\047/, "", line)
      gsub(/`[^`]*`/, "", line)
      idx = match(line, /--/)
      if (idx > 0) {
        body = substr(line, idx + 2)
        sub(/^[ \t]+/, "", body)
        sub(/[ \t]+$/, "", body)
        if (body != "") print body
      }
    } else {
      if (line ~ /^#!/) next
      if (line ~ /\/\/go:/) next
      if (line ~ /(\/\/|\/\*)[ \t]*(eslint-|@ts-|@flow|biome-ignore|prettier-ignore|oxlint-|deno-lint-|c8 ignore|v8 ignore|istanbul ignore|nolint)/) next
      gsub(/"[^"]*"/, "", line)
      gsub(/\047[^\047]*\047/, "", line)
      gsub(/`[^`]*`/, "", line)
      idx = match(line, /\/\//)
      if (idx > 0) {
        body = substr(line, idx + 2)
        sub(/^[ \t]+/, "", body)
        sub(/[ \t]+$/, "", body)
        if (body != "") print body
      }
    }
  }' 2>/dev/null
}

# new から old を multiset 差し引きし、追加されたコメント本文だけを順序維持で出力。
diff_comment_bodies() {
  local old=$1 new=$2 old_bodies new_bodies
  old_bodies=$(extract_comment_bodies "$old")
  new_bodies=$(extract_comment_bodies "$new")
  awk -v old="$old_bodies" '
    BEGIN {
      n = split(old, arr, "\n")
      for (i = 1; i <= n; i++) {
        if (arr[i] != "") seen[arr[i]]++
      }
    }
    {
      if ($0 == "") next
      if ($0 in seen && seen[$0] > 0) { seen[$0]--; next }
      print
    }
  ' <<<"$new_bodies"
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
added_bodies=""

append_added() {
  local bodies
  bodies=$(diff_comment_bodies "$1" "$2")
  [ -n "$bodies" ] || return 0
  if [ -n "$added_bodies" ]; then
    added_bodies="$added_bodies
$bodies"
  else
    added_bodies=$bodies
  fi
}

case "$tool_name" in
  Edit)
    old=$(jq -r '.tool_input.old_string // ""' <<<"$input" 2>/dev/null)
    new=$(jq -r '.tool_input.new_string // ""' <<<"$input" 2>/dev/null)
    c=$(contribution "$old" "$new"); total=$((total + ${c:-0}))
    [ "${c:-0}" -gt 0 ] 2>/dev/null && append_added "$old" "$new"
    ;;
  Write)
    [ -f "$file_path" ] || exit 0
    old=$(cat "$file_path" 2>/dev/null) || exit 0
    new=$(jq -r '.tool_input.content // ""' <<<"$input" 2>/dev/null)
    c=$(contribution "$old" "$new"); total=$((total + ${c:-0}))
    [ "${c:-0}" -gt 0 ] 2>/dev/null && append_added "$old" "$new"
    ;;
  MultiEdit)
    n=$(jq '.tool_input.edits | length' <<<"$input" 2>/dev/null)
    [ -n "$n" ] || exit 0
    i=0
    while [ "$i" -lt "$n" ] 2>/dev/null; do
      old=$(jq -r ".tool_input.edits[$i].old_string // \"\"" <<<"$input" 2>/dev/null)
      new=$(jq -r ".tool_input.edits[$i].new_string // \"\"" <<<"$input" 2>/dev/null)
      c=$(contribution "$old" "$new"); total=$((total + ${c:-0}))
      [ "${c:-0}" -gt 0 ] 2>/dev/null && append_added "$old" "$new"
      i=$((i + 1))
    done
    ;;
esac

[ "${total:-0}" -gt 0 ] 2>/dev/null || exit 0

# deny 候補。/write-code-comments フォークのマーカーが鮮度内なら、追加コメント本文を
# unslop で lint する。違反があれば AI 文章クセを根拠に deny、無ければ通常通り通す。
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
if [ -n "$cwd" ]; then
  marker="$cwd/.claude/tmp/.comment-guard-allow"
  if [ -f "$marker" ] && [ -n "$(find "$marker" -mmin -30 2>/dev/null)" ]; then
    if [ -z "$added_bodies" ] || [ ! -x "$UNSLOP" ] || [ ! -f "$CONFIG" ]; then
      exit 0
    fi
    tmp=$(mktemp 2>/dev/null) || exit 0
    tmp_md="${tmp}.md"
    if ! mv "$tmp" "$tmp_md" 2>/dev/null; then
      rm -f "$tmp"
      exit 0
    fi
    # 各コメント本文を独立段落として書き出す。連続行扱いだと no-mid-sentence-break が
    # 隣接コメントの境目で誤発火する。
    printf '%s\n' "$added_bodies" | awk 'NF { print; print "" }' > "$tmp_md" 2>/dev/null || { rm -f "$tmp_md"; exit 0; }
    pushd "$REPO" >/dev/null 2>&1 || { rm -f "$tmp_md"; exit 0; }
    out=$("$UNSLOP" -c "$CONFIG" --no-color "$tmp_md" 2>&1)
    rc=$?
    popd >/dev/null 2>&1
    rm -f "$tmp_md"
    [ "$rc" -eq 0 ] && exit 0
    reason_body=$(printf '%s\n' "$out" | sed "s|$tmp_md|added-comments.md|g" | awk 'NF' | head -8)
    reason="コードコメントに AI 文章クセが検出されました。次の unslop 指摘を踏まえてコメント本文を見直してから再実行してください。

$reason_body"
    jq -nc --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
  fi
fi

printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"新規コードコメントの追加はブロックされています。コメントを削除して再実行してください。経緯や背景を残したい場合は、コードコメントではなく git のコミットメッセージに記載してください。コメントが本質的に必要な場合はユーザーに依頼してください。"}}'
exit 0
