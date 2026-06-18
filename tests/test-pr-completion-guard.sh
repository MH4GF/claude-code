#!/bin/bash
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# pr-completion-guard hook のオフライン単体テスト。
# 各ケースで一時 git repo を作り、`gh` を fake binary に差し替えて hook を実行する。
# stdout が空なら exit 0 で素通し、`{decision:"block","reason":...}` を返したら push back。

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../.claude-plugins/pr-completion-guard/hooks/check-pr-state.sh"

if [ ! -x "$HOOK" ]; then
  echo "FAIL: $HOOK not found or not executable"
  exit 1
fi

pass=0
fail=0

# setup_repo <dir> <branch>
#   初期コミットを main に置き、<branch> を切って HEAD に進める。
#   origin/main を local clone で参照する場合は別途設定する。
setup_repo() {
  local dir="$1" branch="$2"
  (
    cd "$dir"
    git init -q -b main
    git config user.email t@t
    git config user.name t
    git config commit.gpgsign false
    git config tag.gpgsign false
    git config core.hooksPath /dev/null
    echo init > README.md
    git add README.md
    git commit -q --no-verify -m init
    if [ "$branch" != "main" ]; then
      git checkout -q -b "$branch"
    fi
  )
}

# add_remote_main <dir>
#   origin/main を同じ commit に固定する (ahead count 計算用)。
add_remote_main() {
  local dir="$1"
  (
    cd "$dir"
    git update-ref refs/remotes/origin/main HEAD
  )
}

# make_fake_gh <bin_dir> <json_payload>
#   `gh` を呼ぶと固定 JSON を返す stub binary を作る。空白 payload で `[]` を返す。
make_fake_gh() {
  local bin_dir="$1" payload="$2"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/gh" <<EOF
#!/bin/bash
cat <<'JSON'
$payload
JSON
EOF
  chmod +x "$bin_dir/gh"
}

# run_case <name> <branch> <gh_payload> <expected_key|"">
#   <expected_key> が空文字なら exit 0 + stdout 空を期待。
#   設定済み: dirty=0 のクリーン作業ツリー、origin/main が HEAD と同じ commit。
run_case() {
  local name="$1" branch="$2" payload="$3" expected_key="$4"
  local base; base=$(mktemp -d)
  local dir="$base/repo"
  local bin_dir="$base/bin"
  mkdir -p "$dir"
  setup_repo "$dir" "$branch"
  add_remote_main "$dir"
  make_fake_gh "$bin_dir" "$payload"
  local out
  out=$(cd "$dir" && PATH="$bin_dir:$PATH" PR_GUARD_SKIP= bash "$HOOK" <<<'{"session_id":"s1"}' 2>/dev/null)
  rm -rf "$base"
  if [ -z "$expected_key" ]; then
    if [ -z "$out" ]; then
      echo "PASS $name"
      pass=$((pass+1))
    else
      echo "FAIL $name: expected empty stdout, got: $out"
      fail=$((fail+1))
    fi
    return
  fi
  local got_reason; got_reason=$(jq -r '.reason // ""' <<<"$out" 2>/dev/null)
  if [ -z "$got_reason" ]; then
    echo "FAIL $name: no reason in stdout: $out"
    fail=$((fail+1))
    return
  fi
  case "$got_reason" in
    *"$expected_key"*)
      echo "PASS $name"
      pass=$((pass+1))
      ;;
    *)
      echo "FAIL $name: reason did not match '$expected_key': $got_reason"
      fail=$((fail+1))
      ;;
  esac
}

# 1. main branch では exit 0
{
  dir=$(mktemp -d)
  setup_repo "$dir" main
  out=$(cd "$dir" && bash "$HOOK" <<<'{"session_id":"s1"}' 2>/dev/null)
  rm -rf "$dir"
  if [ -z "$out" ]; then
    echo "PASS main branch passes through"; pass=$((pass+1))
  else
    echo "FAIL main branch passes through: $out"; fail=$((fail+1))
  fi
}

# 2. PR_GUARD_SKIP=1 で素通し
{
  dir=$(mktemp -d)
  setup_repo "$dir" feature
  add_remote_main "$dir"
  out=$(cd "$dir" && PR_GUARD_SKIP=1 bash "$HOOK" <<<'{"session_id":"s1"}' 2>/dev/null)
  rm -rf "$dir"
  if [ -z "$out" ]; then
    echo "PASS PR_GUARD_SKIP=1 passes through"; pass=$((pass+1))
  else
    echo "FAIL PR_GUARD_SKIP=1 passes through: $out"; fail=$((fail+1))
  fi
}

# 3. uncommitted changes で block
{
  base=$(mktemp -d); dir="$base/repo"; bin_dir="$base/bin"; mkdir -p "$dir"
  setup_repo "$dir" feature
  add_remote_main "$dir"
  make_fake_gh "$bin_dir" "[]"
  (cd "$dir" && echo dirty > dirty.txt)
  out=$(cd "$dir" && PATH="$bin_dir:$PATH" bash "$HOOK" <<<'{"session_id":"s1"}' 2>/dev/null)
  rm -rf "$base"
  reason=$(jq -r '.reason // ""' <<<"$out" 2>/dev/null)
  case "$reason" in
    *"未コミット"*) echo "PASS uncommitted blocks"; pass=$((pass+1)) ;;
    *) echo "FAIL uncommitted blocks: '$reason'"; fail=$((fail+1)) ;;
  esac
}

# 4. PR 0 件 + ahead > 0 で pr-missing
{
  base=$(mktemp -d); dir="$base/repo"; bin_dir="$base/bin"; mkdir -p "$dir"
  setup_repo "$dir" feature
  add_remote_main "$dir"
  (cd "$dir" && echo more > extra.txt && git add extra.txt && git commit -q --no-verify -m extra)
  make_fake_gh "$bin_dir" "[]"
  out=$(cd "$dir" && PATH="$bin_dir:$PATH" bash "$HOOK" <<<'{"session_id":"s1"}' 2>/dev/null)
  rm -rf "$base"
  reason=$(jq -r '.reason // ""' <<<"$out" 2>/dev/null)
  case "$reason" in
    *"PR がありません"*) echo "PASS pr-missing blocks"; pass=$((pass+1)) ;;
    *) echo "FAIL pr-missing blocks: '$reason'"; fail=$((fail+1)) ;;
  esac
}

# 5. PR 0 件かつ ahead 0 (commit が origin/main と同じ) は素通し
run_case "no PR no ahead passes through" feature "[]" ""

# 6. CI 失敗で ci-fail
ci_fail='[{"number":42,"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[{"conclusion":"FAILURE","name":"test"}]}]'
run_case "ci-fail blocks" feature "$ci_fail" "CI が失敗"

# 7. CI 待ちで ci-pending
ci_pending='[{"number":42,"state":"OPEN","isDraft":false,"mergeable":"UNKNOWN","statusCheckRollup":[{"status":"IN_PROGRESS","name":"test"}]}]'
run_case "ci-pending blocks" feature "$ci_pending" "CI 待ち"

# 8. mergeable + draft で ready 化要求
mergeable_draft='[{"number":42,"state":"OPEN","isDraft":true,"mergeable":"MERGEABLE","statusCheckRollup":[{"conclusion":"SUCCESS","name":"test"}]}]'
run_case "mergeable draft blocks" feature "$mergeable_draft" "ready 化"

# 9. mergeable + Ready で merge 要求
mergeable_ready='[{"number":42,"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[{"conclusion":"SUCCESS","name":"test"}]}]'
run_case "mergeable ready blocks" feature "$mergeable_ready" "merge 可能"

# 10. conflict で block
conflict='[{"number":42,"state":"OPEN","isDraft":false,"mergeable":"CONFLICTING","statusCheckRollup":[{"conclusion":"SUCCESS","name":"test"}]}]'
run_case "conflict blocks" feature "$conflict" "conflict"

# 11. mergeable UNKNOWN で再評価待ち
unknown='[{"number":42,"state":"OPEN","isDraft":false,"mergeable":"UNKNOWN","statusCheckRollup":[{"conclusion":"SUCCESS","name":"test"}]}]'
run_case "mergeable-unknown blocks" feature "$unknown" "pending"

# 12. PR が MERGED 状態は素通し
merged='[{"number":42,"state":"MERGED","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[]}]'
run_case "merged PR passes through" feature "$merged" ""

# 13. PR が CLOSED は素通し
closed='[{"number":42,"state":"CLOSED","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[]}]'
run_case "closed PR passes through" feature "$closed" ""

# 14. loop guard: marker と同じ reason で連続発火 → 2 回目は素通し
{
  base=$(mktemp -d); dir="$base/repo"; bin_dir="$base/bin"; mkdir -p "$dir"
  setup_repo "$dir" feature
  add_remote_main "$dir"
  (cd "$dir" && echo dirty > dirty.txt)
  make_fake_gh "$bin_dir" "[]"
  first=$(cd "$dir" && PATH="$bin_dir:$PATH" bash "$HOOK" <<<'{"session_id":"s1"}' 2>/dev/null)
  second=$(cd "$dir" && PATH="$bin_dir:$PATH" bash "$HOOK" <<<'{"session_id":"s1"}' 2>/dev/null)
  rm -rf "$base"
  if [ -n "$first" ] && [ -z "$second" ]; then
    echo "PASS loop guard suppresses identical reason"; pass=$((pass+1))
  else
    echo "FAIL loop guard: first='$first' second='$second'"; fail=$((fail+1))
  fi
}

# 15. loop guard: reason key 変化で再発火
{
  base=$(mktemp -d); dir="$base/repo"; bin_dir="$base/bin"; mkdir -p "$dir"
  setup_repo "$dir" feature
  add_remote_main "$dir"
  (cd "$dir" && echo dirty > dirty.txt)
  make_fake_gh "$bin_dir" "[]"
  first=$(cd "$dir" && PATH="$bin_dir:$PATH" bash "$HOOK" <<<'{"session_id":"s1"}' 2>/dev/null)
  (cd "$dir" && git add dirty.txt && git commit -q --no-verify -m dirty)
  make_fake_gh "$bin_dir" "$ci_fail"
  second=$(cd "$dir" && PATH="$bin_dir:$PATH" bash "$HOOK" <<<'{"session_id":"s1"}' 2>/dev/null)
  rm -rf "$base"
  reason2=$(jq -r '.reason // ""' <<<"$second" 2>/dev/null)
  if [ -n "$first" ] && [[ "$reason2" == *"CI が失敗"* ]]; then
    echo "PASS reason transition re-fires"; pass=$((pass+1))
  else
    echo "FAIL reason transition re-fires: first='$first' second='$second'"; fail=$((fail+1))
  fi
}

echo
echo "Results: PASS=$pass FAIL=$fail"
if [ $fail -gt 0 ]; then
  exit 1
fi
echo "ALL PASS"
