#!/bin/bash
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# unslop-guard hook のオフライン単体テスト。
# binary 鮮度チェック (origin/main コミット時刻 vs binary mtime) を中心に検証する。
# 実際の unslop binary は使わず、mock で lint 結果を差し替える。ネットワークにも出ない。

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../user-scope/hooks/unslop-guard.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ ! -f "$HOOK" ]; then
  echo "FAIL: $HOOK not found"
  exit 1
fi

pass=0
fail=0

# lint mock binary を作る。$1=path $2=exit-code。exit!=0 のとき stdout に指摘を出す。
make_bin() {
  local path=$1 code=$2
  cat >"$path" <<EOF
#!/bin/bash
[ "$code" -ne 0 ] && echo "mock lint finding"
exit $code
EOF
  chmod +x "$path"
}

# unslop repo (git) を作る。$1=repo dir $2=origin/main コミット日時。
# origin remote は到達不能な local path にし、offline でも fetch が即座に失敗するようにする。
make_repo() {
  local repo=$1 cdate=$2
  git init -q "$repo"
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name tester
  GIT_AUTHOR_DATE="$cdate" GIT_COMMITTER_DATE="$cdate" \
    git -C "$repo" commit -q --allow-empty -m init
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  git -C "$repo" remote add origin /nonexistent-unslop-remote
  # fetch stamp を fresh にして TTL 内 (fetch skip) にする。
  touch "$(git -C "$repo" rev-parse --absolute-git-dir)/.unslop-guard-fetch"
}

# CONFIG / prh cache を備えた REPO (claude-code 相当) を作る。
make_guard_repo() {
  local repo=$1
  mkdir -p "$repo"
  printf '{}\n' >"$repo/.textlintrc.json"
  printf '' >"$repo/prh.yml"
}

# CJK を含む md ファイルを作る。
make_md() {
  printf 'これは日本語のドキュメントです。\n' >"$1"
}

# run <name> <expected-rc> <expect-stale: yes|no> [extra env...]
# stdin には md への Edit payload を流す。
run() {
  local name=$1 want_rc=$2 want_stale=$3; shift 3
  local out rc got_stale=no
  out=$(printf '%s' "$PAYLOAD" | env "$@" bash "$HOOK" 2>&1 >/dev/null)
  rc=$?
  printf '%s' "$out" | grep -q 'origin/main より古い' && got_stale=yes
  if [ "$rc" = "$want_rc" ] && [ "$got_stale" = "$want_stale" ]; then
    echo "PASS $name"
    pass=$((pass+1))
  else
    echo "FAIL $name: rc=$rc(want $want_rc) stale=$got_stale(want $want_stale)"
    printf '  out: %s\n' "$out"
    fail=$((fail+1))
  fi
}

GUARD_REPO="$WORK/guard"
make_guard_repo "$GUARD_REPO"
MD="$WORK/doc.md"
make_md "$MD"
PAYLOAD="$(jq -nc --arg p "$MD" '{tool_name:"Edit",tool_input:{file_path:$p}}')"

BASE_ENV=(UNSLOP_GUARD_REPO="$GUARD_REPO" UNSLOP_PRH_URL="file:///nonexistent")

# 1. binary が origin/main より古い + lint clean → exit 2, stale 通知あり
REPO1="$WORK/repo1"; make_repo "$REPO1" "2026-08-10T00:00:00+09:00"
BIN1="$WORK/bin1"; make_bin "$BIN1" 0; touch -t 202608010000 "$BIN1"
run "stale binary + clean lint surfaces" 2 yes \
  "${BASE_ENV[@]}" UNSLOP_BIN="$BIN1" UNSLOP_REPO="$REPO1"

# 2. binary が origin/main より新しい + lint clean → exit 0, 通知なし (従来どおり静か)
REPO2="$WORK/repo2"; make_repo "$REPO2" "2026-08-10T00:00:00+09:00"
BIN2="$WORK/bin2"; make_bin "$BIN2" 0; touch -t 202608150000 "$BIN2"
run "fresh binary stays silent" 0 no \
  "${BASE_ENV[@]}" UNSLOP_BIN="$BIN2" UNSLOP_REPO="$REPO2"

# 3. unslop repo が git でない → 鮮度判定を skip, exit 0 (block しない)
NOTREPO="$WORK/notrepo"; mkdir -p "$NOTREPO"
BIN3="$WORK/bin3"; make_bin "$BIN3" 0; touch -t 202601010000 "$BIN3"
run "missing repo degrades to silent" 0 no \
  "${BASE_ENV[@]}" UNSLOP_BIN="$BIN3" UNSLOP_REPO="$NOTREPO"

# 4. origin/main ref が無い → 鮮度判定を skip, exit 0
REPO4="$WORK/repo4"; git init -q "$REPO4"
git -C "$REPO4" config user.email t@example.com; git -C "$REPO4" config user.name t
GIT_AUTHOR_DATE="2026-08-10T00:00:00+09:00" GIT_COMMITTER_DATE="2026-08-10T00:00:00+09:00" \
  git -C "$REPO4" commit -q --allow-empty -m init
touch "$(git -C "$REPO4" rev-parse --absolute-git-dir)/.unslop-guard-fetch"
BIN4="$WORK/bin4"; make_bin "$BIN4" 0; touch -t 202601010000 "$BIN4"
run "no origin/main ref degrades to silent" 0 no \
  "${BASE_ENV[@]}" UNSLOP_BIN="$BIN4" UNSLOP_REPO="$REPO4"

# 5. offline (到達不能な origin) + fetch stamp 期限切れ + stale binary
#    → fetch は失敗するが既存 ref で判定でき、block しない (exit 2, stale 通知)
REPO5="$WORK/repo5"; make_repo "$REPO5" "2026-08-10T00:00:00+09:00"
rm -f "$(git -C "$REPO5" rev-parse --absolute-git-dir)/.unslop-guard-fetch"
BIN5="$WORK/bin5"; make_bin "$BIN5" 0; touch -t 202608010000 "$BIN5"
run "offline fetch failure still detects stale" 2 yes \
  "${BASE_ENV[@]}" UNSLOP_BIN="$BIN5" UNSLOP_REPO="$REPO5"

# 6. UNSLOP_GUARD=off → stale でも常に exit 0
run "guard off disables everything" 0 no \
  "${BASE_ENV[@]}" UNSLOP_BIN="$BIN1" UNSLOP_REPO="$REPO1" UNSLOP_GUARD=off

# 7. lint 指摘あり + stale → exit 2, lint 出力と stale 通知の両方
BINF="$WORK/binf"; make_bin "$BINF" 1; touch -t 202608010000 "$BINF"
run "lint finding + stale both surface" 2 yes \
  "${BASE_ENV[@]}" UNSLOP_BIN="$BINF" UNSLOP_REPO="$REPO1"

# 8. lint 指摘あり + fresh → exit 2, stale 通知なし (既存挙動)
BINF2="$WORK/binf2"; make_bin "$BINF2" 1; touch -t 202608150000 "$BINF2"
run "lint finding + fresh has no stale note" 2 no \
  "${BASE_ENV[@]}" UNSLOP_BIN="$BINF2" UNSLOP_REPO="$REPO2"

# 9. CJK を含まない md → 対象外で exit 0 (鮮度判定も走らない)
ASCII="$WORK/ascii.md"; printf 'plain english only\n' >"$ASCII"
ASCII_PAYLOAD="$(jq -nc --arg p "$ASCII" '{tool_name:"Edit",tool_input:{file_path:$p}}')"
out=$(printf '%s' "$ASCII_PAYLOAD" | env "${BASE_ENV[@]}" UNSLOP_BIN="$BIN1" UNSLOP_REPO="$REPO1" bash "$HOOK" 2>&1 >/dev/null); rc=$?
if [ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q 'origin/main より古い'; then
  echo "PASS ascii md out of scope stays silent"; pass=$((pass+1))
else
  echo "FAIL ascii md out of scope stays silent: rc=$rc out=$out"; fail=$((fail+1))
fi

echo
echo "Results: PASS=$pass FAIL=$fail"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
echo "ALL PASS"
