#!/bin/bash
set -uo pipefail
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# textlint-guard hook のオフライン単体テスト。
# fixtures を tool_input.file_path に注入し、hook の exit code で判定する。
# 0 = allow, 2 = block, それ以外 = unexpected。

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO/user-scope/hooks/textlint-guard.sh"
BAD="$REPO/tests/fixtures/textlint-bad.md"
GOOD="$REPO/tests/fixtures/textlint-good.md"
BIN="$REPO/node_modules/.bin/textlint"

if [ ! -f "$HOOK" ]; then
  echo "FAIL: $HOOK not found"
  exit 1
fi

if [ ! -x "$BIN" ]; then
  echo "SKIP: $BIN not installed. Run 'cd $REPO && npm install' first."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

# run_case <name> <file_path> <expected_exit> [extra_env]
run_case() {
  local name=$1 file=$2 expected=$3 envp=${4:-}
  local payload out got
  payload=$(jq -nc --arg p "$file" '{tool_name:"Edit",tool_input:{file_path:$p}}')
  if [ -n "$envp" ]; then
    out=$(printf '%s' "$payload" | env "$envp" TEXTLINT_GUARD_REPO="$REPO" bash "$HOOK" 2>/dev/null)
    got=$?
  else
    out=$(printf '%s' "$payload" | env TEXTLINT_GUARD_REPO="$REPO" bash "$HOOK" 2>/dev/null)
    got=$?
  fi
  if [ "$got" = "$expected" ]; then
    echo "PASS $name"
    pass=$((pass+1))
  else
    echo "FAIL $name: got=$got want=$expected"
    fail=$((fail+1))
  fi
}

# run_case_with_stderr_check <name> <file_path> <expected_exit> <stderr_grep_pattern>
run_case_with_stderr_check() {
  local name=$1 file=$2 expected=$3 pattern=$4
  local payload err got
  payload=$(jq -nc --arg p "$file" '{tool_name:"Edit",tool_input:{file_path:$p}}')
  err=$(printf '%s' "$payload" | env TEXTLINT_GUARD_REPO="$REPO" bash "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [ "$got" = "$expected" ] && printf '%s' "$err" | grep -q "$pattern"; then
    echo "PASS $name"
    pass=$((pass+1))
  else
    echo "FAIL $name: got=$got want=$expected, stderr=$err"
    fail=$((fail+1))
  fi
}

# 1. .md で AI 文章 → exit 2
run_case "md with AI prose blocks" "$BAD" 2

# 2. .md でクリーンな日本語 → exit 0
run_case "md with clean prose allows" "$GOOD" 0

# 3. .mdx で AI 文章 → exit 2
mdx_bad="$WORK/bad.mdx"
cp "$BAD" "$mdx_bad"
run_case "mdx with AI prose blocks" "$mdx_bad" 2

# 4. .ts ファイル → exit 0 (拡張子スルー)
ts_file="$WORK/sample.ts"
printf 'const a = 1;\n' > "$ts_file"
run_case "ts file out of scope" "$ts_file" 0

# 5. node_modules 配下 .md → exit 0 (除外パス)
nm_dir="$WORK/node_modules/foo"
mkdir -p "$nm_dir"
cp "$BAD" "$nm_dir/README.md"
run_case "node_modules path excluded" "$nm_dir/README.md" 0

# 6. .git/COMMIT_EDITMSG.md → exit 0 (除外パス)
git_dir="$WORK/.git"
mkdir -p "$git_dir"
cp "$BAD" "$git_dir/COMMIT_EDITMSG.md"
run_case "git path excluded" "$git_dir/COMMIT_EDITMSG.md" 0

# 7. node_modules 不在時 → exit 0 + stderr にヒント
empty_repo="$WORK/empty-repo"
mkdir -p "$empty_repo"
cp "$REPO/.textlintrc.json" "$empty_repo/.textlintrc.json"
md_for_empty="$WORK/empty-target.md"
cp "$BAD" "$md_for_empty"
err=$(printf '%s' "$(jq -nc --arg p "$md_for_empty" '{tool_name:"Edit",tool_input:{file_path:$p}}')" \
  | env TEXTLINT_GUARD_REPO="$empty_repo" bash "$HOOK" 2>&1 >/dev/null)
rc=$?
if [ "$rc" = "0" ] && printf '%s' "$err" | grep -q "未インストール"; then
  echo "PASS missing node_modules fails open with hint"
  pass=$((pass+1))
else
  echo "FAIL missing node_modules: rc=$rc stderr=$err"
  fail=$((fail+1))
fi

echo
echo "Results: PASS=$pass FAIL=$fail"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
echo "ALL PASS"
