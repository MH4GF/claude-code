#!/bin/bash
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# setup.sh の per-user overlay 挙動を isolated HOME で検証する。
# CLAUDE_SETUP_USER で user 名を override、CLAUDE_SETUP_SKIP_LOCATION_GUARD で
# canonical clone / symphony workspace guard を bypass する。

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP="$REPO_ROOT/setup.sh"

if [ ! -x "$SETUP" ]; then
  echo "FAIL: $SETUP not found or not executable"
  exit 1
fi

pass=0
fail=0

assert_eq() {
  local name=$1 got=$2 want=$3
  if [ "$got" = "$want" ]; then
    echo "PASS $name"
    pass=$((pass+1))
  else
    echo "FAIL $name: got='$got' want='$want'"
    fail=$((fail+1))
  fi
}

run_setup() {
  local home=$1 user=$2
  HOME="$home" \
    CLAUDE_SETUP_USER="$user" \
    CLAUDE_SETUP_SKIP_LOCATION_GUARD=1 \
    "$SETUP" > /dev/null
}

# 1. mh4gf user: overlay 適用 → settings.json は real file かつ ask 24 件
HOME1=$(mktemp -d)
trap 'rm -rf "$HOME1"' EXIT
run_setup "$HOME1" mh4gf
assert_eq "mh4gf settings.json is regular file (not symlink)" \
  "$([ -L "$HOME1/.claude/settings.json" ] && echo symlink || echo regular)" \
  regular
assert_eq "mh4gf permissions.ask has 25 entries" \
  "$(jq '.permissions.ask | length' "$HOME1/.claude/settings.json")" \
  25
assert_eq "mh4gf ask contains gh pr create" \
  "$(jq -r '.permissions.ask | any(. == "Bash(gh pr create:*)")' "$HOME1/.claude/settings.json")" \
  true
assert_eq "mh4gf base permissions.allow preserved" \
  "$(jq '.permissions.allow | length > 0' "$HOME1/.claude/settings.json")" \
  true
assert_eq "mh4gf base permissions.deny preserved" \
  "$(jq '.permissions.deny | length > 0' "$HOME1/.claude/settings.json")" \
  true
assert_eq "mh4gf model field preserved from base" \
  "$(jq -r '.model' "$HOME1/.claude/settings.json")" \
  claude-opus-4-7

# 2. hermes user: overlay 無し → symlink + ask 空
HOME2=$(mktemp -d)
trap 'rm -rf "$HOME1" "$HOME2"' EXIT
run_setup "$HOME2" hermes
assert_eq "hermes settings.json is symlink" \
  "$([ -L "$HOME2/.claude/settings.json" ] && echo symlink || echo regular)" \
  symlink
assert_eq "hermes permissions.ask is empty" \
  "$(jq '.permissions.ask | length' "$HOME2/.claude/settings.json")" \
  0

# 3. idempotency: mh4gf を 2 回連続実行しても結果が同じ
HOME3=$(mktemp -d)
trap 'rm -rf "$HOME1" "$HOME2" "$HOME3"' EXIT
run_setup "$HOME3" mh4gf
SHA1=$(shasum "$HOME3/.claude/settings.json" | cut -d' ' -f1)
run_setup "$HOME3" mh4gf
SHA2=$(shasum "$HOME3/.claude/settings.json" | cut -d' ' -f1)
assert_eq "mh4gf idempotent (sha unchanged on rerun)" "$SHA1" "$SHA2"

# 4. unknown user: overlay 無し → fallback で symlink になる
HOME4=$(mktemp -d)
trap 'rm -rf "$HOME1" "$HOME2" "$HOME3" "$HOME4"' EXIT
run_setup "$HOME4" nobody-xyz
assert_eq "unknown user falls back to symlink" \
  "$([ -L "$HOME4/.claude/settings.json" ] && echo symlink || echo regular)" \
  symlink

# 5. switch user: hermes → mh4gf で symlink から materialized file へ移行
HOME5=$(mktemp -d)
trap 'rm -rf "$HOME1" "$HOME2" "$HOME3" "$HOME4" "$HOME5"' EXIT
run_setup "$HOME5" hermes
assert_eq "switch step1: starts as symlink" \
  "$([ -L "$HOME5/.claude/settings.json" ] && echo symlink || echo regular)" \
  symlink
run_setup "$HOME5" mh4gf
assert_eq "switch step2: replaced with regular file" \
  "$([ -L "$HOME5/.claude/settings.json" ] && echo symlink || echo regular)" \
  regular
assert_eq "switch step2: ask populated after switch" \
  "$(jq '.permissions.ask | length' "$HOME5/.claude/settings.json")" \
  25

echo
echo "Results: PASS=$pass FAIL=$fail"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
echo "ALL PASS"
