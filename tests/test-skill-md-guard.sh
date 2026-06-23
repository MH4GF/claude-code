#!/bin/bash
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# skill-md-guard hook のオフライン単体テスト。
# stdin に JSON、ファイルシステムに SKILL.md を用意し、exit code で判定する。
# exit 0 → allow、exit 2 → deny、その他 → fail。

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../user-scope/hooks/skill-md-guard.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ ! -f "$HOOK" ]; then
  echo "FAIL: $HOOK not found"
  exit 1
fi

pass=0
fail=0

# write_skill <relpath> <description> [body]
write_skill() {
  local rel=$1 desc=$2 body=${3:-"# skill"}
  local path="$WORK/$rel"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
---
name: $(basename "$(dirname "$rel")")
description: $desc
---

$body
EOF
  printf '%s' "$path"
}

# run_case <name> <file_path> <expected> [env-assignment]
run_case() {
  local name=$1 file_path=$2 expected=$3 envp=${4:-}
  local payload rc got
  payload=$(jq -nc --arg p "$file_path" '{tool_input:{file_path:$p}}')
  if [ -n "$envp" ]; then
    printf '%s' "$payload" | env "$envp" bash "$HOOK" >/dev/null 2>&1
  else
    printf '%s' "$payload" | bash "$HOOK" >/dev/null 2>&1
  fi
  rc=$?
  case "$rc" in
    0) got=allow ;;
    2) got=deny ;;
    *) got="error($rc)" ;;
  esac
  if [ "$got" = "$expected" ]; then
    echo "PASS $name"
    pass=$((pass+1))
  else
    echo "FAIL $name: got=$got want=$expected"
    fail=$((fail+1))
  fi
}

# 1. clean description → allow
p=$(write_skill skills/clean/SKILL.md "PR の 3 channel feedback を取得して structured markdown で返す")
run_case "clean description allows" "$p" allow

# 2-7. 各 banned phrase が単独で含まれていれば deny
for phrase in '呼び出し元' 'Symphony' '無人で動かす' '1 turn 内に完結' '人間判断必須' 'バックグラウンドセッション'; do
  slug=$(printf '%s' "$phrase" | tr -dc '[:alnum:]')
  [ -n "$slug" ] || slug="phrase$RANDOM"
  p=$(write_skill "skills/ban-$slug/SKILL.md" "$phrase を含む description")
  run_case "deny phrase: $phrase" "$p" deny
done

# 8. bg session は大文字小文字を無視して deny
p=$(write_skill skills/bg-session/SKILL.md "BG Session で動くと書く")
run_case "deny bg session case-insensitive" "$p" deny

# 9. body だけに phrase、description は clean → allow
p=$(write_skill skills/body-only/SKILL.md "clean description" "本文に Symphony や bg session が書かれていても description が clean なら通す")
run_case "body-only phrase allows" "$p" allow

# 10. SKILL.md 以外のパス → allow (frontmatter 似でも対象外)
p=$(write_skill skills/other/README.md "Symphony bg session" "# readme")
mv "$p" "$WORK/skills/other/notes.md"
run_case "non-SKILL.md ignored" "$WORK/skills/other/notes.md" allow

# 11. SKILL_MD_GUARD=off → 違反でも allow
p=$(write_skill skills/disabled/SKILL.md "Symphony で動かす")
run_case "SKILL_MD_GUARD=off disables" "$p" allow "SKILL_MD_GUARD=off"

# 12. file_path 空 → fail-open allow
run_case "empty file_path fails open" "" allow

# 13. 不正 JSON → fail-open allow
printf 'not json' | bash "$HOOK" >/dev/null 2>&1
if [ "$?" -eq 0 ]; then
  echo "PASS malformed json fails open"; pass=$((pass+1))
else
  echo "FAIL malformed json fails open"; fail=$((fail+1))
fi

# 14. SKILL.md だが file が存在しない → allow (fail-open)
run_case "missing file fails open" "$WORK/skills/missing/SKILL.md" allow

# 15. description 無しの frontmatter → allow
mkdir -p "$WORK/skills/no-desc"
cat > "$WORK/skills/no-desc/SKILL.md" <<'EOF'
---
name: no-desc
context: fork
---

# no-desc
EOF
run_case "no description field allows" "$WORK/skills/no-desc/SKILL.md" allow

# 16. frontmatter 無しの SKILL.md → allow (description 不在扱い)
mkdir -p "$WORK/skills/no-fm"
cat > "$WORK/skills/no-fm/SKILL.md" <<'EOF'
# no frontmatter

ここに Symphony と書いても description 不在なので通る
EOF
run_case "no frontmatter allows" "$WORK/skills/no-fm/SKILL.md" allow

# 17. 複数 banned phrase → deny (1 件でも該当すれば block)
p=$(write_skill skills/multi-ban/SKILL.md "Symphony bg session で 1 turn 内に完結する")
run_case "multiple bans deny" "$p" deny

# 18. background session の variant → deny
p=$(write_skill skills/bg-variant/SKILL.md "Background session から呼ばれて動く")
run_case "background session denies" "$p" deny

# 19. 人間の判断必須 variant → deny
p=$(write_skill skills/human-variant/SKILL.md "人間の判断必須な分岐がある")
run_case "人間の判断必須 denies" "$p" deny

# 20. 無人運転 variant → deny
p=$(write_skill skills/unattended/SKILL.md "無人運転を前提とした skill")
run_case "無人運転 denies" "$p" deny

# 21. 1 turn 内で完結 variant → deny
p=$(write_skill skills/oneturn-de/SKILL.md "1 turn 内で完結する処理")
run_case "1 turn 内で完結 denies" "$p" deny

# 22. SymPHONY のような大文字混在 → deny
p=$(write_skill skills/case-mix/SKILL.md "SymPHONY 経由で動かす")
run_case "Symphony case-mix denies" "$p" deny

# 23. 通常 PostToolUse payload (tool_name 等を含む) → deny
p=$(write_skill skills/full-payload/SKILL.md "Symphony で動かす")
payload=$(jq -nc --arg p "$p" '{tool_name:"Write",tool_input:{file_path:$p,content:""},cwd:"/tmp"}')
printf '%s' "$payload" | bash "$HOOK" >/dev/null 2>&1
if [ "$?" -eq 2 ]; then
  echo "PASS full PostToolUse payload denies"; pass=$((pass+1))
else
  echo "FAIL full PostToolUse payload denies"; fail=$((fail+1))
fi

# 24. frontmatter description に `呼び出し側` (許容語) は含まれても allow
p=$(write_skill skills/side-ok/SKILL.md "出力を呼び出し側に返す PR feedback fetcher")
run_case "呼び出し側 (side) allows" "$p" allow

echo
echo "Results: PASS=$pass FAIL=$fail"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
echo "ALL PASS"
