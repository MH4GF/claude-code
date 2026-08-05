#!/bin/bash
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# nosleep hook のオフライン単体テスト。
# pmset と sudo をスタブに差し替え、disablesleep が期待どおり上げ下げされるかを見る。

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../user-scope/hooks/nosleep.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ ! -f "$HOOK" ]; then
  echo "FAIL: $HOOK not found"
  exit 1
fi

mkdir -p "$WORK/bin" "$WORK/state"

# --- スタブ -----------------------------------------------------------------

# pmset スタブ。電源と disablesleep をファイルから読む。
cat > "$WORK/bin/pmset" <<'EOF'
#!/bin/bash
src="$(cat "$WORK/power")"
if [ "${2:-}" = ps ]; then
  case "$src" in
    ac) echo "Now drawing from 'AC Power'" ;;
    *)  echo "Now drawing from 'Battery Power'"
        echo " -InternalBattery-0 (id=1)	${src#battery:}%; discharging; 3:00 remaining present: true" ;;
  esac
  exit 0
fi
# 実機の pmset -g に合わせる。設定名は disablesleep だが読み出し名は SleepDisabled で、
# 0 のときは System-wide power settings 節ごと出てこない (macOS 26 で確認)。
if [ "$(cat "$WORK/disablesleep")" = 1 ]; then
  echo "System-wide power settings:"
  printf ' SleepDisabled\t\t1\n'
fi
echo "Currently in use:"
echo " sleep                15"
exit 0
EOF

# guard スタブ。呼び出しを記録し、pmset スタブが読む状態を書き換える。
cat > "$WORK/bin/guard" <<'EOF'
#!/bin/bash
echo "$1" >> "$WORK/calls"
case "$1" in
  on)  echo 1 > "$WORK/disablesleep" ;;
  off) echo 0 > "$WORK/disablesleep" ;;
esac
EOF

chmod +x "$WORK/bin/pmset" "$WORK/bin/guard"

# --- テストハーネス ---------------------------------------------------------

pass=0
fail=0

reset_env() {
  rm -rf "$WORK/state" "$WORK/calls"
  mkdir -p "$WORK/state"
  : > "$WORK/calls"
  echo ac > "$WORK/power"
  echo 0 > "$WORK/disablesleep"
}

# invoke <verb> <session_id> <transcript_path> [env assignments...]
invoke() {
  local verb=$1 sid=$2 tp=$3
  shift 3
  printf '{"session_id":"%s","transcript_path":"%s"}' "$sid" "$tp" \
    | env \
        WORK="$WORK" \
        CLAUDE_NOSLEEP_STATE="$WORK/state" \
        CLAUDE_NOSLEEP_GUARD="$WORK/bin/guard" \
        CLAUDE_NOSLEEP_PMSET="$WORK/bin/pmset" \
        CLAUDE_NOSLEEP_SUDO=env \
        "$@" \
        bash "$HOOK" "$verb" >/dev/null 2>&1
}

# check <name> <expected 0|1>
check() {
  local name=$1 want=$2 got
  got="$(cat "$WORK/disablesleep")"
  if [ "$got" = "$want" ]; then
    echo "PASS $name"
    pass=$((pass + 1))
  else
    echo "FAIL $name: disablesleep=$got want=$want"
    fail=$((fail + 1))
  fi
}

# check_calls <name> <expected call count>
check_calls() {
  local name=$1 want=$2 got
  got="$(wc -l < "$WORK/calls" | tr -d ' ')"
  if [ "$got" = "$want" ]; then
    echo "PASS $name"
    pass=$((pass + 1))
  else
    echo "FAIL $name: guard calls=$got want=$want"
    fail=$((fail + 1))
  fi
}

# --- ケース -----------------------------------------------------------------

# 1. AC 電源でセッションを 1 つ登録すると抑止が入る
reset_env
: > "$WORK/t1.jsonl"
invoke acquire s1 "$WORK/t1.jsonl"
check "acquire on AC engages" 1

# 2. 同じセッションを release すると解除される
invoke release s1 "$WORK/t1.jsonl"
check "release disengages" 0

# 3. 2 セッションのうち 1 つを release しても抑止は続く
reset_env
: > "$WORK/t1.jsonl"; : > "$WORK/t2.jsonl"
invoke acquire s1 "$WORK/t1.jsonl"
invoke acquire s2 "$WORK/t2.jsonl"
invoke release s1 "$WORK/t1.jsonl"
check "one of two released stays engaged" 1
invoke release s2 "$WORK/t2.jsonl"
check "last release disengages" 0

# 4. すでに目的の状態なら guard を呼ばない (Stop hook が毎ターン叩くため)
reset_env
: > "$WORK/t1.jsonl"
invoke acquire s1 "$WORK/t1.jsonl"
invoke acquire s1 "$WORK/t1.jsonl"
invoke acquire s1 "$WORK/t1.jsonl"
check_calls "idempotent acquire calls guard once" 1

# 5. バッテリー駆動では既定 (AC_ONLY=1) で有効化しない
reset_env
echo battery:90 > "$WORK/power"
: > "$WORK/t1.jsonl"
invoke acquire s1 "$WORK/t1.jsonl"
check "battery with AC_ONLY=1 stays off" 0

# 6. AC_ONLY=0 かつ残量十分なら有効化する
reset_env
echo battery:90 > "$WORK/power"
: > "$WORK/t1.jsonl"
invoke acquire s1 "$WORK/t1.jsonl" CLAUDE_NOSLEEP_AC_ONLY=0
check "battery with AC_ONLY=0 engages" 1

# 7. AC_ONLY=0 でも残量が MIN_BATTERY を下回れば解除する
invoke acquire s1 "$WORK/t1.jsonl" CLAUDE_NOSLEEP_AC_ONLY=0 CLAUDE_NOSLEEP_MIN_BATTERY=95
check "battery below MIN_BATTERY disengages" 0

# 8. AC から抜けたら次の hook で解除される (Stop hook が拾う想定)
reset_env
: > "$WORK/t1.jsonl"
invoke acquire s1 "$WORK/t1.jsonl"
echo battery:90 > "$WORK/power"
invoke acquire s1 "$WORK/t1.jsonl"
check "unplugging disengages on next hook" 0

# 9. transcript が古いセッションは掃除される (SessionEnd を落としたケース)
reset_env
: > "$WORK/t1.jsonl"
invoke acquire s1 "$WORK/t1.jsonl"
touch -t 202001010000 "$WORK/t1.jsonl"
invoke release other "$WORK/t-none.jsonl"
check "stale transcript is pruned" 0

# 10. transcript が存在しない場合は登録ファイルの mtime で判定する
reset_env
invoke acquire s1 "$WORK/missing.jsonl"
check "missing transcript still engages" 1
touch -t 202001010000 "$WORK/state/sessions/s1"
invoke release other "$WORK/t-none.jsonl"
check "stale registration is pruned" 0

# 11. off で全部捨てて解除する
reset_env
: > "$WORK/t1.jsonl"; : > "$WORK/t2.jsonl"
invoke acquire s1 "$WORK/t1.jsonl"
invoke acquire s2 "$WORK/t2.jsonl"
printf '{}' | env WORK="$WORK" \
  CLAUDE_NOSLEEP_STATE="$WORK/state" \
  CLAUDE_NOSLEEP_GUARD="$WORK/bin/guard" \
  CLAUDE_NOSLEEP_PMSET="$WORK/bin/pmset" \
  CLAUDE_NOSLEEP_SUDO=env \
  bash "$HOOK" off >/dev/null 2>&1
check "off disengages" 0
if [ -z "$(ls -A "$WORK/state/sessions" 2>/dev/null)" ]; then
  echo "PASS off clears registry"
  pass=$((pass + 1))
else
  echo "FAIL off clears registry: $(ls -A "$WORK/state/sessions")"
  fail=$((fail + 1))
fi

# 12. guard 未設置のマシンでは何もせず、状態ディレクトリも作らない
reset_env
rm -rf "$WORK/state"
printf '{"session_id":"s1","transcript_path":"%s"}' "$WORK/t1.jsonl" \
  | env WORK="$WORK" \
      CLAUDE_NOSLEEP_STATE="$WORK/state" \
      CLAUDE_NOSLEEP_GUARD="$WORK/bin/absent" \
      CLAUDE_NOSLEEP_PMSET="$WORK/bin/pmset" \
      CLAUDE_NOSLEEP_SUDO=env \
      bash "$HOOK" acquire >/dev/null 2>&1
if [ ! -d "$WORK/state" ] && [ "$(cat "$WORK/disablesleep")" = 0 ]; then
  echo "PASS missing guard is a no-op"
  pass=$((pass + 1))
else
  echo "FAIL missing guard is a no-op: state dir or disablesleep changed"
  fail=$((fail + 1))
fi

# 13. jq が PATH に無くても session_id を取り出せる
reset_env
: > "$WORK/t1.jsonl"
printf '{"session_id":"s1","transcript_path":"%s"}' "$WORK/t1.jsonl" \
  | env -i PATH=/usr/bin:/bin WORK="$WORK" \
      CLAUDE_NOSLEEP_STATE="$WORK/state" \
      CLAUDE_NOSLEEP_GUARD="$WORK/bin/guard" \
      CLAUDE_NOSLEEP_PMSET="$WORK/bin/pmset" \
      CLAUDE_NOSLEEP_SUDO=env \
      bash "$HOOK" acquire >/dev/null 2>&1
if [ -f "$WORK/state/sessions/s1" ] && [ "$(cat "$WORK/disablesleep")" = 1 ]; then
  echo "PASS works without jq"
  pass=$((pass + 1))
else
  echo "FAIL works without jq: registry=$(ls -A "$WORK/state/sessions" 2>/dev/null)"
  fail=$((fail + 1))
fi

# 14. hook は常に exit 0 を返す (失敗させてセッションを止めない)
reset_env
printf 'not json' | env WORK="$WORK" \
  CLAUDE_NOSLEEP_STATE="$WORK/state" \
  CLAUDE_NOSLEEP_GUARD="$WORK/bin/guard" \
  CLAUDE_NOSLEEP_PMSET="$WORK/bin/pmset" \
  CLAUDE_NOSLEEP_SUDO=env \
  bash "$HOOK" acquire >/dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "PASS malformed payload exits 0"
  pass=$((pass + 1))
else
  echo "FAIL malformed payload exits 0"
  fail=$((fail + 1))
fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
