#!/usr/bin/env bash
# Claude Code statusline.
#   Line 1: model / rel_path / branch / output_style (always rendered, fail-open)
#   Line 2: 5h usage bar + reset (Asia/Tokyo), omitted on API failure
#   Line 3: 7d usage bar + reset (Asia/Tokyo), omitted on API failure
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

input=$(cat)

GREEN="\033[38;2;151;201;195m"
YELLOW="\033[38;2;229;192;123m"
RED="\033[38;2;224;108;117m"
GRAY="\033[38;2;74;88;92m"
RESET="\033[0m"

color_for_pct() {
  local pct=$1
  if (( pct >= 80 )); then
    printf '%s' "$RED"
  elif (( pct >= 50 )); then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$GREEN"
  fi
}

progress_bar() {
  local pct=$1
  (( pct > 100 )) && pct=100
  (( pct < 0 )) && pct=0
  local filled=$(( pct / 10 ))
  local empty=$(( 10 - filled ))
  local color
  color=$(color_for_pct "$pct")
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="▰"; done
  for ((i=0; i<empty; i++)); do bar+="▱"; done
  printf '%b%s%b' "$color" "$bar" "$RESET"
}

# ── Line 1: preserve the historical inline statusline ──
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
style=$(echo "$input" | jq -r '.output_style.name // "default"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // ""')
project=$(echo "$input" | jq -r '.workspace.project_dir // ""')

if [ -n "$project" ] && [ "$cwd" != "$project" ] && [[ "$cwd" == "$project"/* ]]; then
  rel_path="$(basename "$project")/${cwd#"$project"/}"
else
  rel_path="$(basename "${cwd:-.}")"
fi

branch=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "detached")
fi

if [ -n "$branch" ]; then
  line1=$(printf "\033[2m%s\033[0m \033[36m%s\033[0m \033[2m|\033[0m \033[33m%s\033[0m \033[2m|\033[0m \033[35m%s\033[0m" \
    "$model" "$rel_path" "$branch" "$style")
else
  line1=$(printf "\033[2m%s\033[0m \033[36m%s\033[0m \033[2m|\033[0m \033[35m%s\033[0m" \
    "$model" "$rel_path" "$style")
fi

# ── Usage API (fail-open) ──
CACHE_FILE="/tmp/claude-usage-cache.json"
CACHE_TTL=360

fetch_usage() {
  local token_json access_token response now tmp
  token_json=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) || return 1
  [ -z "$token_json" ] && return 1

  access_token=$(printf '%s' "$token_json" \
    | jq -r '.claudeAiOauth.accessToken // .accessToken // .access_token // empty' 2>/dev/null) || return 1
  [ -z "$access_token" ] && return 1

  response=$(curl -sf --max-time 5 \
    -H "Authorization: Bearer ${access_token}" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null) || return 1
  [ -z "$response" ] && return 1

  now=$(date +%s)
  tmp="${CACHE_FILE}.$$"
  if printf '%s' "$response" | jq --arg ts "$now" '. + {cached_at: ($ts | tonumber)}' >"$tmp" 2>/dev/null; then
    mv -f "$tmp" "$CACHE_FILE" 2>/dev/null || rm -f "$tmp"
  else
    rm -f "$tmp"
  fi
  printf '%s' "$response"
}

get_usage() {
  local now cached_at age
  now=$(date +%s)
  if [ -f "$CACHE_FILE" ]; then
    cached_at=$(jq -r '.cached_at // 0' "$CACHE_FILE" 2>/dev/null || echo 0)
    age=$(( now - cached_at ))
    if (( age < CACHE_TTL )); then
      jq 'del(.cached_at)' "$CACHE_FILE" 2>/dev/null && return 0
    fi
  fi
  fetch_usage
}

iso_to_epoch() {
  local iso_time=$1
  local stripped="${iso_time%%.*}"
  stripped="${stripped%Z}"
  TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null || echo ""
}

format_5h_reset() {
  local epoch
  epoch=$(iso_to_epoch "$1")
  [ -z "$epoch" ] && return
  LC_ALL=en_US.UTF-8 TZ="Asia/Tokyo" date -r "$epoch" +"Resets %-l%p (Asia/Tokyo)" 2>/dev/null | sed 's/AM/am/;s/PM/pm/'
}

format_7d_reset() {
  local epoch
  epoch=$(iso_to_epoch "$1")
  [ -z "$epoch" ] && return
  LC_ALL=en_US.UTF-8 TZ="Asia/Tokyo" date -r "$epoch" +"Resets %b %-d at %-l%p (Asia/Tokyo)" 2>/dev/null | sed 's/AM/am/;s/PM/pm/'
}

line2=""
line3=""
usage_json=$(get_usage 2>/dev/null || true)

if [ -n "$usage_json" ]; then
  five_util=$(printf '%s' "$usage_json" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
  five_reset=$(printf '%s' "$usage_json" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
  seven_util=$(printf '%s' "$usage_json" | jq -r '.seven_day.utilization // empty' 2>/dev/null)
  seven_reset=$(printf '%s' "$usage_json" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)

  if [ -n "$five_util" ]; then
    printf -v five_int "%.0f" "$five_util" 2>/dev/null || five_int="${five_util%%.*}"
    five_color=$(color_for_pct "$five_int")
    five_bar=$(progress_bar "$five_int")
    line2="$(printf '%b5h%b  %b  %b%s%%%b' "$five_color" "$RESET" "$five_bar" "$five_color" "$five_int" "$RESET")"
    five_reset_str=""
    [ -n "$five_reset" ] && five_reset_str=$(format_5h_reset "$five_reset")
    [ -n "$five_reset_str" ] && line2+="$(printf '  %b%s%b' "$GRAY" "$five_reset_str" "$RESET")"
  fi

  if [ -n "$seven_util" ]; then
    printf -v seven_int "%.0f" "$seven_util" 2>/dev/null || seven_int="${seven_util%%.*}"
    seven_color=$(color_for_pct "$seven_int")
    seven_bar=$(progress_bar "$seven_int")
    line3="$(printf '%b7d%b  %b  %b%s%%%b' "$seven_color" "$RESET" "$seven_bar" "$seven_color" "$seven_int" "$RESET")"
    seven_reset_str=""
    [ -n "$seven_reset" ] && seven_reset_str=$(format_7d_reset "$seven_reset")
    [ -n "$seven_reset_str" ] && line3+="$(printf '  %b%s%b' "$GRAY" "$seven_reset_str" "$RESET")"
  fi
fi

printf '%b' "$line1"
[ -n "$line2" ] && printf '\n%b' "$line2"
[ -n "$line3" ] && printf '\n%b' "$line3"
