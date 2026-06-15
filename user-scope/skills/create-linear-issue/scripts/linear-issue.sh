#!/bin/bash
#
# linear-issue.sh — thin Linear GraphQL wrapper for the create-linear-issue skill.
#
# Workspace-specific identifiers (team_id, project_id, state_id) live in a
# local config file, NOT in this repo, because this repo is public.
#
# Default config path: ~/.config/create-linear-issue/config.json
# Override with: CREATE_LINEAR_ISSUE_CONFIG=/path/to/config.json
#
# Config schema:
# {
#   "default_project": "<key>",
#   "projects": {
#     "<key>": {
#       "team_id": "<uuid>",
#       "project_id": "<uuid>",
#       "default_state_id": "<uuid>"
#     }
#   }
# }
#
# Required env: LINEAR_API_KEY (Linear Personal API key). The key is workspace-
# scoped on the Linear side, so the wrapper cannot reach a different workspace
# even if asked. This is the scope guarantee for the skill.

set -eu

CONFIG_FILE="${CREATE_LINEAR_ISSUE_CONFIG:-$HOME/.config/create-linear-issue/config.json}"

usage() {
  cat <<'EOF'
linear-issue.sh — thin Linear GraphQL wrapper

Usage:
  linear-issue.sh list-projects
      Print configured project keys plus the default.

  linear-issue.sh default-project
      Print the default project key (errors if not set).

  linear-issue.sh search --project <key> --query <text> [--limit N]
      Search active issues (Todo/In Progress) in the project for duplicate detection.
      Returns JSON with identifier/title/state per hit.

  linear-issue.sh create --project <key> --title <text> --description-file <path>
      Create an issue. Title is passed as one string; description is read from the
      file path so newlines / markdown headers / backticks survive verbatim.
      Returns the new issue's identifier and URL on success.

Env:
  LINEAR_API_KEY               Required. Linear Personal API key (workspace-scoped).
  CREATE_LINEAR_ISSUE_CONFIG   Optional. Path to config JSON.

Exit codes:
  0  success
  2  usage error / bad input
  3  config missing or malformed
  4  Linear API error
EOF
}

die() { echo "linear-issue: $*" >&2; exit "${2:-2}"; }

require_api_key() {
  [ -n "${LINEAR_API_KEY:-}" ] || die "LINEAR_API_KEY is not set" 3
}

require_config() {
  [ -r "$CONFIG_FILE" ] || die "config not readable at $CONFIG_FILE" 3
  jq -e . "$CONFIG_FILE" >/dev/null 2>&1 || die "config is not valid JSON: $CONFIG_FILE" 3
}

config_get() {
  # $1 = jq path expression. Errors out (exit 3) if the path is missing.
  local path="$1"
  jq -e -r "$path" "$CONFIG_FILE" 2>/dev/null || die "config missing or null at: $path" 3
}

gql() {
  # $1 = query string. $2 = path to a JSON file containing variables (or "").
  local query="$1"
  local vars_file="${2:-}"
  require_api_key
  local payload
  if [ -n "$vars_file" ] && [ -s "$vars_file" ]; then
    payload=$(jq -n --arg q "$query" --slurpfile vars "$vars_file" \
      '{query: $q, variables: ($vars[0] // {})}')
  else
    payload=$(jq -n --arg q "$query" '{query: $q}')
  fi
  local resp
  resp=$(printf '%s' "$payload" | curl -sS \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d @- https://api.linear.app/graphql) || die "curl to Linear failed" 4
  # Surface GraphQL-level errors as exit 4 so callers can react.
  if printf '%s' "$resp" | jq -e '.errors' >/dev/null 2>&1; then
    printf '%s\n' "$resp" >&2
    die "Linear returned GraphQL errors" 4
  fi
  printf '%s' "$resp"
}

cmd_list_projects() {
  require_config
  local default
  default=$(jq -r '.default_project // empty' "$CONFIG_FILE")
  jq -r --arg d "$default" '.projects | to_entries[] |
    "\(.key)\(if .key == $d then " (default)" else "" end)"' "$CONFIG_FILE"
}

cmd_default_project() {
  require_config
  config_get '.default_project'
}

parse_kv() {
  # Read --flag value pairs into named globals. Caller sets _expected.
  # Usage: parse_kv "$@"; then read variables like KV_project, KV_title, etc.
  while [ $# -gt 0 ]; do
    case "$1" in
      --*)
        local key="${1#--}"
        [ $# -ge 2 ] || die "missing value for --$key"
        # Replace dashes with underscores for variable naming.
        local var="KV_${key//-/_}"
        eval "$var=\"\$2\""
        shift 2
        ;;
      *)
        die "unexpected positional arg: $1"
        ;;
    esac
  done
}

cmd_search() {
  require_config
  KV_limit=10
  parse_kv "$@"
  [ -n "${KV_project:-}" ] || die "--project required"
  [ -n "${KV_query:-}" ] || die "--query required"
  local project_id
  project_id=$(config_get ".projects.\"$KV_project\".project_id")
  local vars
  vars=$(mktemp)
  trap 'rm -f "$vars"' RETURN
  jq -n --arg pid "$project_id" --arg q "$KV_query" --argjson n "$KV_limit" \
    '{projectId: $pid, q: $q, n: $n}' > "$vars"
  local resp
  resp=$(gql 'query Search($projectId: ID!, $q: String!, $n: Int!) {
    issues(first: $n, filter: {
      project: { id: { eq: $projectId } },
      title: { contains: $q }
    }) {
      nodes { identifier title state { name } url }
    }
  }' "$vars")
  printf '%s' "$resp" | jq '.data.issues.nodes'
}

cmd_create() {
  require_config
  parse_kv "$@"
  [ -n "${KV_project:-}" ] || die "--project required"
  [ -n "${KV_title:-}" ] || die "--title required"
  [ -n "${KV_description_file:-}" ] || die "--description-file required"
  [ -r "$KV_description_file" ] || die "cannot read $KV_description_file"
  local team_id project_id state_id desc
  team_id=$(config_get ".projects.\"$KV_project\".team_id")
  project_id=$(config_get ".projects.\"$KV_project\".project_id")
  state_id=$(config_get ".projects.\"$KV_project\".default_state_id")
  desc=$(cat "$KV_description_file")
  local vars
  vars=$(mktemp)
  trap 'rm -f "$vars"' RETURN
  jq -n --arg tid "$team_id" --arg pid "$project_id" --arg sid "$state_id" \
    --arg title "$KV_title" --arg desc "$desc" \
    '{teamId: $tid, projectId: $pid, stateId: $sid, title: $title, description: $desc}' > "$vars"
  local resp
  resp=$(gql 'mutation Create(
    $teamId: String!, $projectId: String!, $stateId: String!,
    $title: String!, $description: String!
  ) {
    issueCreate(input: {
      teamId: $teamId,
      projectId: $projectId,
      stateId: $stateId,
      title: $title,
      description: $description
    }) {
      success
      issue { id identifier url state { name } }
    }
  }' "$vars")
  printf '%s' "$resp" | jq '.data.issueCreate'
}

case "${1:-}" in
  list-projects)     shift; cmd_list_projects "$@";;
  default-project)   shift; cmd_default_project "$@";;
  search)            shift; cmd_search "$@";;
  create)            shift; cmd_create "$@";;
  -h|--help|help|"") usage; exit 0;;
  *) usage; exit 2;;
esac
