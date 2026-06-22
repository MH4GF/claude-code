#!/bin/bash
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# skill-prose-guard hook のオフライン単体テスト。
# stdin に JSON を流し、deny JSON が出れば "deny"、無出力なら "allow" と判定する。

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../user-scope/hooks/skill-prose-guard.sh"
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

# 1. SKILL.md に散文 4 行追加 → deny (delta=4 > threshold=3)
run_case "SKILL.md prose +4 lines" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/foo/SKILL.md",old_string:"# Title",new_string:"# Title\n\n散文 1\n散文 2\n散文 3\n散文 4"}}')" \
  deny

# 2. SKILL.md に散文 3 行追加 → allow (delta=3, > 3 not satisfied)
run_case "SKILL.md prose +3 lines at threshold" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/foo/SKILL.md",old_string:"# Title",new_string:"# Title\n\n散文 1\n散文 2\n散文 3"}}')" \
  allow

# 3. 対象外パス (README.md) → allow
run_case "non-target README.md" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/foo/README.md",old_string:"x",new_string:"x\n散文 1\n散文 2\n散文 3\n散文 4"}}')" \
  allow

# 4. SKILL.md にコード fence 内テキストを追加 → allow (fence 内は散文扱いしない)
run_case "SKILL.md code fence addition" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/foo/SKILL.md",old_string:"x",new_string:"x\n\n```bash\necho 1\necho 2\necho 3\necho 4\n```"}}')" \
  allow

# 5. SKILL.md にリスト項目を追加 → allow
run_case "SKILL.md list addition" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/foo/SKILL.md",old_string:"x",new_string:"x\n- a\n- b\n- c\n- d\n- e"}}')" \
  allow

# 6. SKILL.md に見出しを追加 → allow
run_case "SKILL.md headings addition" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/foo/SKILL.md",old_string:"x",new_string:"x\n# H1\n## H2\n### H3\n#### H4"}}')" \
  allow

# 7. SKILL.md に表を追加 → allow
run_case "SKILL.md table addition" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/foo/SKILL.md",old_string:"x",new_string:"x\n|a|b|\n|-|-|\n|1|2|\n|3|4|"}}')" \
  allow

# 8. SKILL.md で散文を削減 → allow (delta < 0)
run_case "SKILL.md prose reduction" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/foo/SKILL.md",old_string:"# Title\n\n散文 1\n散文 2\n散文 3\n散文 4\n散文 5",new_string:"# Title"}}')" \
  allow

# 9. SKILL.md で散文を同数置換 → allow (delta=0)
run_case "SKILL.md prose same-count replace" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/foo/SKILL.md",old_string:"古い 1\n古い 2\n古い 3\n古い 4",new_string:"新しい 1\n新しい 2\n新しい 3\n新しい 4"}}')" \
  allow

# 10. commands/*.md に散文 4 行追加 → deny
run_case "commands md prose +4" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/foo/commands/bar.md",old_string:"x",new_string:"x\n散文 1\n散文 2\n散文 3\n散文 4"}}')" \
  deny

# 11. CLAUDE.md に散文 4 行追加 → deny
run_case "CLAUDE.md prose +4" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/foo/CLAUDE.md",old_string:"x",new_string:"x\n散文 1\n散文 2\n散文 3\n散文 4"}}')" \
  deny

# 12. SKILL_PROSE_GUARD=off で escape → allow
run_case "env-off escape" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/foo/SKILL.md",old_string:"x",new_string:"x\n散文 1\n散文 2\n散文 3\n散文 4"}}')" \
  allow \
  "SKILL_PROSE_GUARD=off"

# 13. SKILL_PROSE_GUARD_THRESHOLD=10 で底上げ → allow
run_case "threshold override allow" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/foo/SKILL.md",old_string:"x",new_string:"x\n散文 1\n散文 2\n散文 3\n散文 4"}}')" \
  allow \
  "SKILL_PROSE_GUARD_THRESHOLD=10"

# 14. SKILL_PROSE_GUARD_THRESHOLD=2 で締める → deny
run_case "threshold override deny" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/foo/SKILL.md",old_string:"x",new_string:"x\n散文 1\n散文 2\n散文 3"}}')" \
  deny \
  "SKILL_PROSE_GUARD_THRESHOLD=2"

# 15. Write 新規 SKILL.md (old なし) で散文 4 行 → deny
run_case "Write new SKILL.md prose +4" \
  "$(jq -nc --arg p "$WORK/SKILL.md" '{tool_name:"Write",tool_input:{file_path:$p,content:"# Title\n\n散文 1\n散文 2\n散文 3\n散文 4"}}')" \
  deny

# 16. Write 既存 SKILL.md (同内容) → allow (delta=0)
echo "# Title" > "$WORK/existing-skill.md"
run_case "Write existing SKILL.md unchanged" \
  "$(jq -nc --arg p "$WORK/existing-skill.md" '{tool_name:"Write",tool_input:{file_path:$p,content:"# Title\n"}}')" \
  allow

# 17. MultiEdit 合計 4 行追加 → deny
run_case "MultiEdit sum prose +4" \
  "$(jq -nc '{tool_name:"MultiEdit",tool_input:{file_path:"/tmp/foo/SKILL.md",edits:[{old_string:"a",new_string:"a\n散文 1\n散文 2"},{old_string:"b",new_string:"b\n散文 3\n散文 4"}]}}')" \
  deny

# 18. MultiEdit 各 2 行で合計 4 = 散文 4 はちょうど threshold 超 → deny
run_case "MultiEdit cumulative threshold" \
  "$(jq -nc '{tool_name:"MultiEdit",tool_input:{file_path:"/tmp/foo/SKILL.md",edits:[{old_string:"a",new_string:"a\n散文 1\n散文 2"},{old_string:"b",new_string:"b\n散文 3"}]}}')" \
  allow

# 19. tool_name=Bash → 対象外 allow
run_case "non-edit tool ignored" \
  "$(jq -nc '{tool_name:"Bash",tool_input:{command:"ls"}}')" \
  allow

# 20. front matter (---) を含み、本体が見出しのみ → allow
run_case "front matter only with heading" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/foo/SKILL.md",old_string:"x",new_string:"---\nname: foo\ndescription: bar\n---\n# Title"}}')" \
  allow

# 21. front matter + 散文 4 行 → deny (front matter は散文扱いせず、散文 4 行で delta=4 を超えると deny)
run_case "front matter + prose +4" \
  "$(jq -nc '{tool_name:"Edit",tool_input:{file_path:"/tmp/foo/SKILL.md",old_string:"",new_string:"---\nname: foo\n---\n散文 1\n散文 2\n散文 3\n散文 4"}}')" \
  deny

# 22. 空 payload → exit 0 (fail-open)
run_case "empty payload" "" allow

# 23. 不正 JSON → exit 0 (fail-open)
run_case "malformed payload" "{not json" allow

echo ""
echo "Results: PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && echo "ALL PASS" || exit 1
