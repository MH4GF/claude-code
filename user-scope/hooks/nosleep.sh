#!/bin/bash
# claude-nosleep: 生きている Claude Code セッションがある間だけ、蓋を閉じてもスリープしない状態を保つ。
#
#   acquire   SessionStart / Stop から呼ぶ。セッションを登録し、状態を合わせる
#   release   SessionEnd から呼ぶ。登録を外し、状態を合わせる
#   status    登録状況と pmset の現状を表示する
#   off       登録を全部捨てて強制解除する
#
# 蓋閉じ (clamshell) スリープは caffeinate では止まらず、pmset disablesleep でしか止まらない。
# アイドルスリープの抑止は Claude Code 本体が caffeinate で行うので、ここでは扱わない。
#
# disablesleep は電源別に設定できない (pmset -g cap に含まれない) ため、
# バッテリー駆動時に有効化しない判断はこのスクリプト側で行う。
#
# root ヘルパー未設置のマシンでは全操作が no-op になる。設置は nosleep-install.sh を参照。
set -uo pipefail

STATE_DIR="${CLAUDE_NOSLEEP_STATE:-/tmp/claude-nosleep-$(id -u)}"
SESSION_DIR="$STATE_DIR/sessions"
LOCK_DIR="$STATE_DIR/lock"
GUARD="${CLAUDE_NOSLEEP_GUARD:-/usr/local/bin/claude-sleep-guard}"
PMSET="${CLAUDE_NOSLEEP_PMSET:-/usr/bin/pmset}"
# パスワードを聞ける端末が無いので必ず -n。許可が無ければ静かに失敗させる。
SUDO="${CLAUDE_NOSLEEP_SUDO:-/usr/bin/sudo -n}"

# 1 なら AC 電源接続時のみ有効化する。カバンの中でバッテリーを焼かないための既定値。
AC_ONLY="${CLAUDE_NOSLEEP_AC_ONLY:-1}"
# AC_ONLY=0 のとき、バッテリー残量がこの値を下回ったら解除する
MIN_BATTERY="${CLAUDE_NOSLEEP_MIN_BATTERY:-30}"
# transcript がこの秒数だけ更新されないセッションは、SessionEnd を落として死んだものとみなす
STALE_AFTER="${CLAUDE_NOSLEEP_STALE_AFTER:-7200}"

# --- 排他 -------------------------------------------------------------------

lock() {
  local waited=0
  until mkdir "$LOCK_DIR" 2>/dev/null; do
    if [ "$waited" -ge 50 ]; then
      # 5 秒取れないロックは前回の異常終了の残骸とみなして 1 度だけ奪う
      rm -rf "$LOCK_DIR"
      mkdir "$LOCK_DIR" 2>/dev/null || return 1
      break
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  trap 'rm -rf "$LOCK_DIR"' EXIT
}

# --- 電源判定 ---------------------------------------------------------------

# 判定は必ず出力を変数に取ってから行う。`pmset | grep -q` だと grep が
# 先頭マッチで抜けた瞬間に pmset が SIGPIPE で死に、pipefail (上の set) が
# それを拾って終了ステータス 141 になる。真なのに偽を返す。
on_ac() {
  local out
  out="$("$PMSET" -g ps 2>/dev/null)"
  [[ "$out" == *"'AC Power'"* ]]
}

battery_pct() {
  "$PMSET" -g ps 2>/dev/null | grep -oE '[0-9]+%' | head -1 | tr -d '%'
}

power_ok() {
  on_ac && return 0
  [ "$AC_ONLY" = "1" ] && return 1
  local pct
  pct="$(battery_pct)"
  [ -n "$pct" ] && [ "$pct" -ge "$MIN_BATTERY" ]
}

# --- pmset 操作 -------------------------------------------------------------

# フラグファイルではなく pmset を真実の源にする。再起動やクラッシュで
# 状態ファイルが消えても、実際の disablesleep から復帰できる。
#
# 設定するときの名前は disablesleep だが、pmset -g が読み出すときの名前は
# SleepDisabled (System-wide power settings 節)。macOS 26 で確認。
# 読めないと off 側が「既に解除済み」と誤判定して解除を飛ばすので、両方拾う。
# パイプを使わない理由は on_ac のコメントを参照。
engaged() {
  local out re
  out="$("$PMSET" -g 2>/dev/null)"
  re='(^|'$'\n'')[[:space:]]*(disablesleep|SleepDisabled)[[:space:]]+1([[:space:]]|$)'
  [[ "$out" =~ $re ]]
}

apply() {
  case "$1" in
    on)  engaged || $SUDO "$GUARD" on >/dev/null 2>&1 ;;
    off) ! engaged || $SUDO "$GUARD" off >/dev/null 2>&1 ;;
  esac
}

# --- セッション登録 ---------------------------------------------------------

# hook payload から 1 フィールド取り出す。jq が PATH に無い環境でも動くようにする。
payload_field() {
  local key=$1 payload=$2
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null
    return
  fi
  printf '%s' "$payload" \
    | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed 's/.*:[[:space:]]*"\(.*\)"$/\1/'
}

session_file() {
  printf '%s/%s' "$SESSION_DIR" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')"
}

# 死んだセッションを掃除し、残数と電源状態から disablesleep を決める。要 lock。
reconcile() {
  local now file transcript stamp live=0
  now="$(date +%s)"
  shopt -s nullglob
  for file in "$SESSION_DIR"/*; do
    transcript="$(cat "$file" 2>/dev/null)"
    stamp=""
    if [ -n "$transcript" ] && [ -f "$transcript" ]; then
      stamp="$(stat -f %m "$transcript" 2>/dev/null)"
    fi
    # transcript が無い、または読めない場合は登録ファイル自身の mtime を時計にする
    [ -z "$stamp" ] && stamp="$(stat -f %m "$file" 2>/dev/null || echo "$now")"
    if [ $((now - stamp)) -gt "$STALE_AFTER" ]; then
      rm -f "$file"
      continue
    fi
    live=$((live + 1))
  done

  if [ "$live" -gt 0 ] && power_ok; then
    apply on
  else
    apply off
  fi
}

# --- コマンド ---------------------------------------------------------------

# ヘルパー未設置のマシンでは何もしない。状態ディレクトリも作らない。
if [ ! -x "$GUARD" ] && [ "${1:-}" != status ]; then
  exit 0
fi

case "${1:-}" in
  acquire)
    payload="$(cat)"
    session_id="$(payload_field session_id "$payload")"
    transcript="$(payload_field transcript_path "$payload")"
    [ -n "$session_id" ] || session_id="unknown"
    mkdir -p "$SESSION_DIR"
    lock || exit 0
    printf '%s' "$transcript" > "$(session_file "$session_id")"
    reconcile
    ;;

  release)
    payload="$(cat)"
    session_id="$(payload_field session_id "$payload")"
    [ -n "$session_id" ] || session_id="unknown"
    mkdir -p "$SESSION_DIR"
    lock || exit 0
    rm -f "$(session_file "$session_id")"
    reconcile
    ;;

  off)
    mkdir -p "$SESSION_DIR"
    lock || exit 0
    rm -f "$SESSION_DIR"/*
    apply off
    ;;

  status)
    if [ -x "$GUARD" ]; then
      echo "guard:     $GUARD"
    else
      echo "guard:     未設置 ($GUARD) — hook は no-op"
    fi
    if on_ac; then
      echo "power:     AC"
    else
      echo "power:     battery $(battery_pct)% (AC_ONLY=$AC_ONLY MIN_BATTERY=$MIN_BATTERY)"
    fi
    if engaged; then
      echo "clamshell: 蓋閉じスリープ抑止中 (disablesleep 1)"
    else
      echo "clamshell: 通常 (disablesleep 0)"
    fi
    echo "sessions:  $(ls -1 "$SESSION_DIR" 2>/dev/null | wc -l | tr -d ' ')"
    ls -1 "$SESSION_DIR" 2>/dev/null | sed 's/^/  - /'
    ;;

  *)
    echo "usage: nosleep.sh {acquire|release|status|off}" >&2
    exit 64
    ;;
esac

exit 0
