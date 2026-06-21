#!/bin/bash
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# Tests for scripts/unslop-changed-lines.py.
# 各ケースで使い捨て git repo を作り、commit を打って filter の挙動を assert する。

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/unslop-changed-lines.py"
CONFIG="$REPO_ROOT/.textlintrc.json"
UNSLOP="${UNSLOP_BIN:-/Users/mh4gf/ghq/github.com/MH4GF/unslop/target/release/unslop}"

if [ ! -x "$UNSLOP" ]; then
  echo "SKIP: unslop binary not found at $UNSLOP (set UNSLOP_BIN to override)"
  exit 0
fi
if [ ! -x "$SCRIPT" ]; then
  echo "FAIL: $SCRIPT not executable"
  exit 1
fi

pass=0
fail=0

assert_exit() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS $name (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL $name: expected exit=$expected, got exit=$actual"
    fail=$((fail + 1))
  fi
}

assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "PASS $name"
    pass=$((pass + 1))
  else
    echo "FAIL $name: missing needle '$needle' in output:"
    printf '%s\n' "$haystack" | sed 's/^/  | /'
    fail=$((fail + 1))
  fi
}

assert_not_contains() {
  local name="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "FAIL $name: unexpected needle '$needle' in output:"
    printf '%s\n' "$haystack" | sed 's/^/  | /'
    fail=$((fail + 1))
  else
    echo "PASS $name"
    pass=$((pass + 1))
  fi
}

setup_repo() {
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"
  git init -q -b main
  git config user.email test@example.com
  git config user.name test
  git config commit.gpgsign false
  git config core.hooksPath /dev/null
  cp "$CONFIG" .textlintrc.json
  cp "$REPO_ROOT/prh.yml" prh.yml
}

teardown_repo() {
  cd "$SCRIPT_DIR"
  rm -rf "$TMPDIR"
  unset TMPDIR
}

run_filter() {
  local base="$1" head="$2"; shift 2
  python3 "$SCRIPT" --base "$base" --head "$head" --unslop "$UNSLOP" --config .textlintrc.json "$@" 2>&1
  echo "---EXIT:$?---"
}

# Case 1: PR touches non-violation line, file already had violations elsewhere.
# Expected: filter drops pre-existing violations on untouched lines, exit 0.
setup_repo
cat > sample.md <<'EOF'
# タイトル

reviewerに対する違反がここにある。
普通の行。
EOF
git add sample.md && git commit -q -m "baseline with violations"
base=$(git rev-parse HEAD)
# Add a new clean line elsewhere
cat > sample.md <<'EOF'
# タイトル

reviewerに対する違反がここにある。
普通の行。
追記された新しい行。
EOF
git add sample.md && git commit -q -m "add clean line"
out=$(run_filter "$base" HEAD sample.md)
exit_marker=$(printf '%s\n' "$out" | grep -oE 'EXIT:[0-9]+' | tail -1 | cut -d: -f2)
assert_exit "case1: untouched-line violations dropped" "0" "$exit_marker"
assert_not_contains "case1: pre-existing violation absent from output" "reviewer" "$out"
teardown_repo

# Case 2: PR adds a new violation on a touched line.
# Expected: violation reported, exit 1.
setup_repo
cat > sample.md <<'EOF'
# タイトル

普通の行。
EOF
git add sample.md && git commit -q -m "baseline clean"
base=$(git rev-parse HEAD)
cat > sample.md <<'EOF'
# タイトル

普通の行。
新しい行にretryの違反を入れる。
EOF
git add sample.md && git commit -q -m "introduce violation"
out=$(run_filter "$base" HEAD sample.md)
exit_marker=$(printf '%s\n' "$out" | grep -oE 'EXIT:[0-9]+' | tail -1 | cut -d: -f2)
assert_exit "case2: touched-line violation reported" "1" "$exit_marker"
assert_contains "case2: touched line 4 coord present" "4:" "$out"
teardown_repo

# Case 3: bundle output, partial in-range.
# Same rule fires on multiple lines but only one is touched.
setup_repo
cat > sample.md <<'EOF'
# タイトル

reviewerの違反その1。
普通の行その1。
reviewerの違反その2。
普通の行その2。
reviewerの違反その3。
EOF
git add sample.md && git commit -q -m "baseline with bundled violations"
base=$(git rev-parse HEAD)
# Modify only line 5 (the middle violation), keep others untouched.
cat > sample.md <<'EOF'
# タイトル

reviewerの違反その1。
普通の行その1。
reviewerの違反その2を編集した。
普通の行その2。
reviewerの違反その3。
EOF
git add sample.md && git commit -q -m "edit middle violation line"
out=$(run_filter "$base" HEAD sample.md)
exit_marker=$(printf '%s\n' "$out" | grep -oE 'EXIT:[0-9]+' | tail -1 | cut -d: -f2)
assert_exit "case3: bundle pruned to in-range coords" "1" "$exit_marker"
# Coord on line 5 must remain
assert_contains "case3: in-range coord 5: present" "5:" "$out"
# Coords on lines 3 and 7 should not remain
assert_not_contains "case3: out-of-range coord 3: absent" "3:1" "$out"
assert_not_contains "case3: out-of-range coord 7: absent" "7:1" "$out"
teardown_repo

# Case 4: newly added file is fully in-range.
setup_repo
cat > existing.md <<'EOF'
# placeholder

普通の行。
EOF
git add existing.md && git commit -q -m "baseline"
base=$(git rev-parse HEAD)
cat > brand-new.md <<'EOF'
# 新しい

reviewerの違反その1。
別の行にもretryの違反。
EOF
git add brand-new.md && git commit -q -m "add new file with violations"
out=$(run_filter "$base" HEAD brand-new.md)
exit_marker=$(printf '%s\n' "$out" | grep -oE 'EXIT:[0-9]+' | tail -1 | cut -d: -f2)
assert_exit "case4: newly added file all in-range" "1" "$exit_marker"
assert_contains "case4: violation surfaced in new file" "brand-new.md" "$out"
teardown_repo

# Case 5: PR touches a clean line; pre-existing same-line violations stay reported.
# This is the boundary: touched line itself has a pre-existing violation that
# the PR didn't add, but since the line is in-range we still surface it (correct).
setup_repo
cat > sample.md <<'EOF'
# タイトル

reviewerの行に既存違反。
EOF
git add sample.md && git commit -q -m "baseline with existing violation"
base=$(git rev-parse HEAD)
cat > sample.md <<'EOF'
# タイトル

reviewerの行に既存違反を編集した。
EOF
git add sample.md && git commit -q -m "edit the violation line"
out=$(run_filter "$base" HEAD sample.md)
exit_marker=$(printf '%s\n' "$out" | grep -oE 'EXIT:[0-9]+' | tail -1 | cut -d: -f2)
assert_exit "case5: violation on touched line reported" "1" "$exit_marker"
assert_contains "case5: line 3 coord present" "3:" "$out"
teardown_repo

echo
echo "Total: PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
