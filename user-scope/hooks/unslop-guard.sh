#!/bin/bash
set -u
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

REPO="${UNSLOP_GUARD_REPO:-$HOME/ghq/github.com/MH4GF/claude-code}"
UNSLOP="${UNSLOP_BIN:-$HOME/ghq/github.com/MH4GF/unslop/target/release/unslop}"
CONFIG="$REPO/.textlintrc.json"

[ "${UNSLOP_GUARD:-}" = "off" ] && exit 0

input=$(cat)
file_path=$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null) || exit 0
[ -n "$file_path" ] || exit 0

case "$file_path" in
  *.md|*.mdx|*.txt) ;;
  *) exit 0 ;;
esac

case "$file_path" in
  */node_modules/*|*/.git/*) exit 0 ;;
esac

if [ -r "$file_path" ]; then
  perl -CSD -0777 -ne 'exit(/\p{Hiragana}|\p{Katakana}|\p{Han}/ ? 0 : 1)' "$file_path" 2>/dev/null
  case $? in
    1) exit 0 ;;
  esac
fi

if [ ! -x "$UNSLOP" ]; then
  echo "[unslop-guard] $UNSLOP がない。'cd ~/ghq/github.com/MH4GF/unslop && cargo build --release' を実行してください" >&2
  exit 2
fi

if [ ! -f "$CONFIG" ]; then
  echo "[unslop-guard] $CONFIG が見つかりません" >&2
  exit 2
fi

# prh rule は MH4GF/shared-config/unslop/prh.yml が正 (single source)。
# raw URL から $REPO/prh.yml (gitignored) へ TTL 24h で cache する。
# fetch 失敗時は stale cache をそのまま使い、cache 自体がなければ block する。
PRH_URL="${UNSLOP_PRH_URL:-https://raw.githubusercontent.com/MH4GF/shared-config/main/unslop/prh.yml}"
PRH_CACHE="$REPO/prh.yml"
if [ ! -f "$PRH_CACHE" ] || [ -n "$(find "$PRH_CACHE" -mmin +1440 2>/dev/null)" ]; then
  if curl -fsSL --retry 2 --max-time 10 "$PRH_URL" -o "$PRH_CACHE.tmp" 2>/dev/null; then
    mv "$PRH_CACHE.tmp" "$PRH_CACHE"
  else
    rm -f "$PRH_CACHE.tmp"
  fi
fi
if [ ! -f "$PRH_CACHE" ]; then
  echo "[unslop-guard] prh.yml cache がない (offline?)。'curl -fsSL $PRH_URL -o $PRH_CACHE' で取得してください" >&2
  exit 2
fi

# binary の鮮度チェック (best-effort)。unslop repo の origin/main 最新コミットより
# binary が古ければ、その事実を通知する。prh ルールは cache で最新に保たれる一方
# binary は手動 build 依存で silent に古くなるため、ここで乖離を検出する。
# git 無し / repo 無し / origin/main 不在 / offline など判定不能なときは黙って続行する。
# 判定失敗が編集を止めてはならない (ネットワークの無い環境でも作業を止めない)。
staleness_note=""
UNSLOP_REPO="${UNSLOP_REPO:-$HOME/ghq/github.com/MH4GF/unslop}"
git_dir=$(git -C "$UNSLOP_REPO" rev-parse --absolute-git-dir 2>/dev/null)
if [ -n "$git_dir" ]; then
  # origin/main を TTL 24h で best-effort fetch する (prh cache と同じ方針)。
  # TTL 内は fetch を skip する。offline で fetch が失敗しても stamp を更新し、
  # 次の 24h は再試行せず待たされないようにする。timeout があれば 10s で打ち切る。
  fetch_stamp="$git_dir/.unslop-guard-fetch"
  if [ ! -f "$fetch_stamp" ] || [ -n "$(find "$fetch_stamp" -mmin +1440 2>/dev/null)" ]; then
    timeout_cmd=$(command -v timeout || command -v gtimeout)
    ${timeout_cmd:+$timeout_cmd 10} git -C "$UNSLOP_REPO" fetch --quiet origin main 2>/dev/null
    touch "$fetch_stamp" 2>/dev/null
  fi
  commit_ts=$(git -C "$UNSLOP_REPO" log -1 --format=%ct origin/main 2>/dev/null)
  bin_ts=$(stat -f %m "$UNSLOP" 2>/dev/null || stat -c %Y "$UNSLOP" 2>/dev/null)
  if [ -n "$commit_ts" ] && [ -n "$bin_ts" ] && [ "$commit_ts" -gt "$bin_ts" ]; then
    fmt() { date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$1" '+%Y-%m-%d %H:%M' 2>/dev/null || printf '%s' "$1"; }
    staleness_note="[unslop-guard] unslop binary が origin/main より古い (build: $(fmt "$bin_ts"), origin/main: $(fmt "$commit_ts"))。lint 結果が古いルールに基づくおそれがある。'cd $UNSLOP_REPO && git pull && cargo build --release' で更新してください"
  fi
fi

cd "$REPO" || { echo "[unslop-guard] cd $REPO に失敗" >&2; exit 2; }

# UNSLOP_GUARD_FIX=off で fix を抑止し、lint-only に戻せる。
fix_flag="--fix"
[ "${UNSLOP_GUARD_FIX:-}" = "off" ] && fix_flag=""

out=$("$UNSLOP" -c "$CONFIG" --no-color $fix_flag "$file_path" 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
  printf '%s\n' "$out" >&2
  [ -n "$staleness_note" ] && printf '%s\n' "$staleness_note" >&2
  echo "" >&2
  echo "[unslop-guard] AI 文章 lint で指摘あり。上記を踏まえて編集を見直してください" >&2
  exit 2
fi
# rc=0 でも fix 適用時は "[unslop] fixed N issue(s) ..." が `out` に残るので agent に通知する。
if [ -n "$out" ]; then
  printf '%s\n' "$out" >&2
fi
# lint が clean でも binary が古ければ exit 2 で通知する。編集は PostToolUse 時点で
# 適用済みのため block にはならず、agent へ鮮度不足を伝える手段として使う。
if [ -n "$staleness_note" ]; then
  printf '%s\n' "$staleness_note" >&2
  exit 2
fi
exit 0
