#!/bin/bash
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# comment-guard hook のオフライン単体テスト。
# stdin に JSON を流し、deny JSON が出れば "deny"、無出力なら "allow" と判定する。

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../user-scope/hooks/comment-guard.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ ! -f "$HOOK" ]; then
  echo "FAIL: $HOOK not found"
  exit 1
fi

pass=0
fail=0

# run_case <name> <payload-json> <allow|deny> [env-assignment]
run_case() {
  local name=$1 payload=$2 expected=$3 envp=${4:-}
  local out got
  if [ -n "$envp" ]; then
    out=$(printf '%s' "$payload" | env "$envp" bash "$HOOK" 2>/dev/null)
  else
    out=$(printf '%s' "$payload" | bash "$HOOK" 2>/dev/null)
  fi
  got=allow
  printf '%s' "$out" | grep -q '"permissionDecision":"deny"' && got=deny
  if [ "$got" = "$expected" ]; then
    echo "PASS $name"
    pass=$((pass+1))
  else
    echo "FAIL $name: got=$got want=$expected"
    fail=$((fail+1))
  fi
}

# 1. .ts 行頭コメント追加 → deny
run_case "ts line-head comment" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/x.ts",old_string:"const a=1;",new_string:"// added\nconst a=1;"}}')" \
  deny

# 2. .ts 行末コメント追加 → deny
run_case "ts trailing comment" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/x.ts",old_string:"foo();",new_string:"foo(); // explain"}}')" \
  deny

# 3. 文字列リテラル内の // (URL) → allow
run_case "url in string literal" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/x.ts",old_string:"const a=1;",new_string:"const u = \"https://example.com\";"}}')" \
  allow

# 4. コメント文言の書き換え (行数同じ) → allow
run_case "comment reword same count" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/x.ts",old_string:"// old text\nconst a=1;",new_string:"// new text\nconst a=1;"}}')" \
  allow

# 5. コメント削除 (行数減) → allow
run_case "comment removal" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/x.ts",old_string:"// drop me\nconst a=1;",new_string:"const a=1;"}}')" \
  allow

# 6. .md ファイル → 対象外 allow
run_case "markdown out of scope" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/x.md",old_string:"text",new_string:"<!-- note -->\ntext"}}')" \
  allow

# 7. 存在しない .ts への Write (新規ファイル) → allow
run_case "write new file skipped" \
  "$(jq -nc --arg p "$WORK/brand-new.ts" '{tool_name:"Write",tool_input:{file_path:$p,content:"// license header\nconst a=1;"}}')" \
  allow

# 8. C-family テンプレートリテラル (バッククォート不均衡) → allow
run_case "unbalanced backtick guard" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/x.ts",old_string:"const a=1;",new_string:"const q = `\n// inside template\nSELECT 1;"}}')" \
  allow

# 9. YAML run: | block scalar 内の # → allow
run_case "yaml block scalar guard" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/ci.yml",old_string:"steps:",new_string:"steps:\n  - run: |\n      # build step\n      make"}}')" \
  allow

# 9b. 通常の YAML コメント追加 → deny
run_case "yaml real comment" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/c.yml",old_string:"key: 1",new_string:"# config\nkey: 1"}}')" \
  deny

# 10. .go の //go:generate → allowlist で allow
run_case "go directive allowlisted" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/x.go",old_string:"package p",new_string:"package p\n//go:generate mockgen"}}')" \
  allow

# 10b. eslint-disable ディレクティブ → allow
run_case "eslint directive allowlisted" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/x.ts",old_string:"const a=1;",new_string:"// eslint-disable-next-line\nconst a=1;"}}')" \
  allow

# 11. 鮮度内マーカー存在下でコメント追加 → allow
mkdir -p "$WORK/fresh/.claude/tmp"
: > "$WORK/fresh/.claude/tmp/.comment-guard-allow"
run_case "fresh marker allows comment" \
  "$(jq -nc --arg c "$WORK/fresh" '{tool_name:"Edit",cwd:$c,tool_input:{file_path:"/tmp/x.ts",old_string:"const a=1;",new_string:"// added\nconst a=1;"}}')" \
  allow

# 12. 鮮度切れマーカー (mtime 古い) 存在下でコメント追加 → deny
mkdir -p "$WORK/stale/.claude/tmp"
: > "$WORK/stale/.claude/tmp/.comment-guard-allow"
touch -t 202001010000 "$WORK/stale/.claude/tmp/.comment-guard-allow"
run_case "stale marker denies comment" \
  "$(jq -nc --arg c "$WORK/stale" '{tool_name:"Edit",cwd:$c,tool_input:{file_path:"/tmp/x.ts",old_string:"const a=1;",new_string:"// added\nconst a=1;"}}')" \
  deny

# 13. COMMENT_GUARD=off → 常に allow
run_case "COMMENT_GUARD=off disables guard" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/x.ts",old_string:"const a=1;",new_string:"// added\nconst a=1;"}}')" \
  allow "COMMENT_GUARD=off"

# 14. 不正 JSON → fail-open allow
run_case "malformed json fails open" "not json at all" allow

# 15. MultiEdit で 1 edit がコメント増 → deny
run_case "multiedit one edit adds comment" \
  "$(jq -nc '{tool_name:"MultiEdit",tool_input:{file_path:"/tmp/x.ts",edits:[{old_string:"a",new_string:"b"},{old_string:"c",new_string:"// note\nc"}]}}')" \
  deny

# 16. 既存 .ts への Write でコメント増 → deny
printf 'const a=1;\n' > "$WORK/exist.ts"
run_case "write existing file adds comment" \
  "$(jq -nc --arg p "$WORK/exist.ts" '{tool_name:"Write",tool_input:{file_path:$p,content:"// added\nconst a=1;\n"}}')" \
  deny

# 17. 既存 .ts への Write で内容据え置き → allow
printf '// keep\nconst a=1;\n' > "$WORK/keep.ts"
run_case "write existing file unchanged comments" \
  "$(jq -nc --arg p "$WORK/keep.ts" '{tool_name:"Write",tool_input:{file_path:$p,content:"// keep\nconst a=2;\n"}}')" \
  allow

# 18. Bash ツール → 対象外 allow
run_case "bash tool out of scope" \
  "$(jq -nc '{tool_name:"Bash",tool_input:{command:"ls"}}')" \
  allow

# 19. .sql 行コメント追加 → deny
run_case "sql line comment added" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/x.sql",old_string:"SELECT 1;",new_string:"-- comment\nSELECT 1;"}}')" \
  deny

# 20. .sql ブロックコメント追加 → deny
run_case "sql block comment added" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/x.sql",old_string:"SELECT 1;",new_string:"/* comment */\nSELECT 1;"}}')" \
  deny

# 21. .sql 文字列リテラル内の -- → allow
run_case "sql dashes inside string literal" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/x.sql",old_string:"SELECT 1;",new_string:"SELECT * FROM t WHERE col = '\''--not a comment'\'';"}}')" \
  allow

# 22. .sql コメントなし純粋クエリ追加 → allow
run_case "sql pure query added" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/x.sql",old_string:"SELECT 1;",new_string:"SELECT 1;\nSELECT 2 FROM users;"}}')" \
  allow

# 23. .sql 既存コメント削除のみ → allow
run_case "sql comment removal" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/x.sql",old_string:"-- drop me\nSELECT 1;",new_string:"SELECT 1;"}}')" \
  allow

# 24. 鮮度内マーカー + unslop 違反コメント → deny (AI 文章クセ検出)
mkdir -p "$WORK/unslop-deny/.claude/tmp"
: > "$WORK/unslop-deny/.claude/tmp/.comment-guard-allow"
run_case "fresh marker + unslop violation denies" \
  "$(jq -nc --arg c "$WORK/unslop-deny" '{tool_name:"Edit",cwd:$c,tool_input:{file_path:"/tmp/x.ts",old_string:"const a=1;",new_string:"// このコードは非常に重要な機能を提供しており、複雑な処理を効率的に実行するために最適化されています。\nconst a=1;"}}')" \
  deny

# 25. 鮮度内マーカー + unslop バイナリ不在 → fail-open allow
run_case "fresh marker + missing unslop fails open" \
  "$(jq -nc --arg c "$WORK/unslop-deny" '{tool_name:"Edit",cwd:$c,tool_input:{file_path:"/tmp/x.ts",old_string:"const a=1;",new_string:"// このコードは非常に重要な機能を提供しており、複雑な処理を効率的に実行するために最適化されています。\nconst a=1;"}}')" \
  allow "UNSLOP_BIN=/nonexistent"

# 26. 鮮度内マーカー + Py コメント unslop 違反 → deny
mkdir -p "$WORK/unslop-py/.claude/tmp"
: > "$WORK/unslop-py/.claude/tmp/.comment-guard-allow"
run_case "py fresh marker + unslop violation denies" \
  "$(jq -nc --arg c "$WORK/unslop-py" '{tool_name:"Edit",cwd:$c,tool_input:{file_path:"/tmp/x.py",old_string:"x=1",new_string:"# このコードは非常に重要な機能を提供しており、複雑な処理を効率的に実行するために最適化されています。\nx=1"}}')" \
  deny

# 27. 鮮度内マーカー + SQL コメント unslop 違反 → deny
run_case "sql fresh marker + unslop violation denies" \
  "$(jq -nc --arg c "$WORK/unslop-py" '{tool_name:"Edit",cwd:$c,tool_input:{file_path:"/tmp/x.sql",old_string:"SELECT 1;",new_string:"-- このコードは非常に重要な機能を提供しており、複雑な処理を効率的に実行するために最適化されています。\nSELECT 1;"}}')" \
  deny

# 28. 鮮度内マーカー + prh 違反のコメント → deny
run_case "fresh marker + prh violation denies" \
  "$(jq -nc --arg c "$WORK/unslop-py" '{tool_name:"Edit",cwd:$c,tool_input:{file_path:"/tmp/x.ts",old_string:"const a=1;",new_string:"// tx の retry を実装する\nconst a=1;"}}')" \
  deny

echo
echo "Results: PASS=$pass FAIL=$fail"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
echo "ALL PASS"
