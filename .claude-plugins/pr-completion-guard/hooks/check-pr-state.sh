#!/bin/bash
# Stop hook: push back the agent when the session is about to end with PR
# work left half-done (uncommitted, no PR, PR draft / pending / failing / conflict).
#
# Output contract:
#   exit 0 (no stdout): allow stop
#   stdout {"decision":"block","reason":"..."}: push back
#
# Fail open: any tooling error exits 0 to avoid getting the session stuck.
#
# Loop guard: persist (session_id, reason_key) to
# .git/info/pr-completion-guard-last-reason so identical consecutive push-backs
# are suppressed while reason transitions re-fire.
#
# Operator-only safety valve:
#   PR_GUARD_SKIP=1 claude ...

set -uo pipefail

input=$(cat 2>/dev/null || echo '{}')
session_id=$(jq -r '.session_id // ""' <<<"$input" 2>/dev/null || echo "")

git_dir=$(git rev-parse --git-dir 2>/dev/null) || exit 0
marker="$git_dir/info/pr-completion-guard-last-reason"

read_marker() { [ -f "$marker" ] && cat "$marker" 2>/dev/null || printf ''; }
write_marker() {
  mkdir -p "$(dirname "$marker")" 2>/dev/null || return 0
  printf '%s\t%s' "$session_id" "$1" > "$marker" 2>/dev/null || return 0
}
clear_marker() { rm -f "$marker" 2>/dev/null || true; }

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
case "$branch" in
  main|master|HEAD|"")
    clear_marker
    exit 0
    ;;
esac

[ "${PR_GUARD_SKIP:-}" = "1" ] && exit 0

emit_block() {
  local key="$1" reason="$2"
  local current prev
  current=$(printf '%s\t%s' "$session_id" "$key")
  prev=$(read_marker)
  if [ "$prev" = "$current" ]; then
    exit 0
  fi
  write_marker "$key"
  jq -nc --arg reason "$reason" '{decision:"block", reason:$reason}'
  exit 0
}

with_timeout() {
  local sec="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$sec" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$sec" "$@"
  else
    "$@"
  fi
}

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  emit_block "uncommitted" "未コミットの変更があります。変更を確認してファイル単位でコミットし、PR まで進めてください。"
fi

pr_json=$(with_timeout 5 gh pr list --state all --head "$branch" --limit 1 \
  --json number,state,isDraft,statusCheckRollup,mergeable 2>/dev/null) || exit 0
pr_count=$(jq 'length' <<<"$pr_json" 2>/dev/null || echo 0)

if [ "$pr_count" = "0" ]; then
  ahead=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo 0)
  if [ "${ahead:-0}" -gt 0 ]; then
    emit_block "pr-missing" "コミットが origin/main より進んでいますが PR がありません。\`gh pr create --draft\` で draft PR を作成してください。"
  fi
  clear_marker
  exit 0
fi

# Single jq pass to extract every field we need. statusCheckRollup entries
# carry one of three result fields depending on shape:
#   - CheckRun completed: .conclusion (SUCCESS/FAILURE/...)
#   - CheckRun running:   .status (IN_PROGRESS/QUEUED/...) — .conclusion is ""
#   - StatusContext:      .state (SUCCESS/FAILURE/...) — no .conclusion/.status
# `//` treats "" as truthy, so explicitly skip empty strings.
IFS=$'\t' read -r pr_number state is_draft mergeable ci_states < <(
  jq -r '.[0] | [
    .number,
    .state,
    (.isDraft | tostring),
    .mergeable,
    ([.statusCheckRollup[]? |
      if (.conclusion // "") != "" then .conclusion
      elif (.state // "") != ""      then .state
      else                                (.status // "")
      end
    ] | join(" "))
  ] | @tsv' <<<"$pr_json"
)

if [ "$state" != "OPEN" ]; then
  clear_marker
  exit 0
fi

has_failure=false
has_pending=false
for c in $ci_states; do
  case "$c" in
    FAILURE|TIMED_OUT|ACTION_REQUIRED|STARTUP_FAILURE|STALE) has_failure=true ;;
    PENDING|QUEUED|IN_PROGRESS|WAITING|REQUESTED) has_pending=true ;;
  esac
done

if $has_failure; then
  emit_block "ci-fail#${pr_number}" "PR #${pr_number} の CI が失敗しています。\`gh pr checks ${pr_number}\` で失敗内容を確認し、修正してください。"
fi
if $has_pending; then
  emit_block "ci-pending#${pr_number}" "PR #${pr_number} の CI 待ちです。\`gh pr checks ${pr_number} --watch\` で完了を待ってください。"
fi

case "$mergeable" in
  MERGEABLE)
    if [ "$is_draft" = "true" ]; then
      emit_block "mergeable-draft#${pr_number}" "PR #${pr_number} は CI green ですが draft のままです。\`gh pr ready ${pr_number}\` で ready 化してから merge してください。"
    else
      emit_block "mergeable#${pr_number}" "PR #${pr_number} は merge 可能です。\`gh pr merge ${pr_number} --squash --delete-branch\` で merge してください。"
    fi
    ;;
  CONFLICTING)
    emit_block "conflict#${pr_number}" "PR #${pr_number} に conflict があります。origin/main を rebase して解消してください。"
    ;;
  UNKNOWN)
    emit_block "mergeable-unknown#${pr_number}" "PR #${pr_number} の mergeable 判定が pending です。少し待ってから \`gh pr view ${pr_number} --json mergeable\` で再評価してください。"
    ;;
esac

clear_marker
exit 0
