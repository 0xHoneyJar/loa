#!/usr/bin/env bash
# loa-status.sh - Enhanced status display with version information
# Sprint 3.5 (T3.5.4): Version-Targeted Updates
#
# Combines workflow state with detailed framework version info.
# Supports both human-readable and JSON output.
#
# Usage:
#   loa-status.sh            Show status with version info
#   loa-status.sh --json     JSON output for scripting
#   loa-status.sh --version  Only show version info
#
# Exit codes:
#   0 - Success
#   1 - Error

set -euo pipefail

# Project paths
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="${PROJECT_ROOT}/.loa-version.json"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"
WORKFLOW_STATE_SCRIPT="${SCRIPT_DIR}/workflow-state.sh"
UPSTREAM_REPO="${LOA_UPSTREAM:-https://github.com/0xHoneyJar/loa.git}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Arguments
JSON_OUTPUT=false
VERSION_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --json) JSON_OUTPUT=true ;;
    --version) VERSION_ONLY=true ;;
    --help|-h)
      echo "Usage: loa-status.sh [--json] [--version] [--help]"
      echo ""
      echo "Options:"
      echo "  --json      Output JSON format"
      echo "  --version   Only show version info"
      echo "  --help      Show this help"
      exit 0
      ;;
  esac
done

# === Version Information Functions ===

get_version_field() {
  local field="$1"
  local default="${2:-}"
  if [[ -f "$VERSION_FILE" ]]; then
    jq -r ".${field} // \"${default}\"" "$VERSION_FILE" 2>/dev/null || echo "$default"
  else
    echo "$default"
  fi
}

get_current_field() {
  local field="$1"
  local default="${2:-}"
  if [[ -f "$VERSION_FILE" ]]; then
    jq -r ".current.${field} // \"${default}\"" "$VERSION_FILE" 2>/dev/null || echo "$default"
  else
    echo "$default"
  fi
}

# Get version info as JSON
get_version_info_json() {
  local version ref ref_type commit updated_at

  version=$(get_version_field "framework_version" "unknown")
  ref=$(get_current_field "ref" "")
  ref_type=$(get_current_field "type" "")
  commit=$(get_current_field "commit" "")
  updated_at=$(get_current_field "updated_at" "")

  # Fall back to framework_version if current block doesn't exist
  if [[ -z "$ref" ]]; then
    ref="v${version}"
    ref_type="tag"
  fi

  local short_commit=""
  if [[ -n "$commit" && "$commit" != "unknown" && "$commit" != "null" ]]; then
    short_commit="${commit:0:8}"
  fi

  # Get source repo URL (strip .git suffix for display)
  local source_url="${UPSTREAM_REPO%.git}"

  # Check for history
  local history_count
  history_count=$(jq -r '.history | length // 0' "$VERSION_FILE" 2>/dev/null || echo "0")

  # Check for available updates
  local update_available="false"
  local latest_version=""
  local cache_file="${HOME}/.loa/cache/update-check.json"
  if [[ -f "$cache_file" ]]; then
    update_available=$(jq -r '.update_available // false' "$cache_file" 2>/dev/null || echo "false")
    latest_version=$(jq -r '.remote_version // ""' "$cache_file" 2>/dev/null || echo "")
  fi

  # Determine if on non-stable ref
  local on_feature_branch="false"
  local warning=""
  if [[ "$ref_type" == "branch" && "$ref" != "main" && "$ref" != "master" ]]; then
    on_feature_branch="true"
    warning="You're on branch '${ref}' (not a stable release)"
  elif [[ "$ref_type" == "commit" ]]; then
    warning="You're on a specific commit (not a tracked ref)"
  fi

  cat <<EOF
{
  "version": "${version}",
  "ref": "${ref}",
  "ref_type": "${ref_type}",
  "commit": "${short_commit}",
  "updated_at": "${updated_at}",
  "source_url": "${source_url}",
  "history_count": ${history_count},
  "update_available": ${update_available},
  "latest_version": "${latest_version}",
  "on_feature_branch": ${on_feature_branch},
  "warning": "${warning}"
}
EOF
}

# Display version info (human-readable)
display_version_info() {
  local version ref ref_type commit updated_at

  version=$(get_version_field "framework_version" "unknown")
  ref=$(get_current_field "ref" "")
  ref_type=$(get_current_field "type" "")
  commit=$(get_current_field "commit" "")
  updated_at=$(get_current_field "updated_at" "")

  # Fall back if current block doesn't exist
  if [[ -z "$ref" ]]; then
    ref="v${version}"
    ref_type="tag"
  fi

  local short_commit=""
  if [[ -n "$commit" && "$commit" != "unknown" && "$commit" != "null" ]]; then
    short_commit=" (${commit:0:8})"
  fi

  echo ""
  echo -e "${BOLD}Framework Version${NC}"
  echo "  Version: ${version}"

  # Show ref type with appropriate icon
  case "$ref_type" in
    tag)
      echo -e "  Ref:     ${GREEN}${ref}${NC} (stable release)"
      ;;
    branch)
      if [[ "$ref" == "main" || "$ref" == "master" ]]; then
        echo -e "  Ref:     ${ref}${short_commit} (main branch)"
      else
        echo -e "  Ref:     ${YELLOW}${ref}${NC}${short_commit} (feature branch)"
        echo -e "  ${YELLOW}Warning:${NC} You're on a non-stable branch"
      fi
      ;;
    commit)
      echo -e "  Ref:     ${YELLOW}${ref:0:12}${NC} (commit)"
      echo -e "  ${YELLOW}Warning:${NC} You're on a specific commit"
      ;;
    latest|*)
      echo -e "  Ref:     ${ref}${short_commit}"
      ;;
  esac

  # Show last updated time
  if [[ -n "$updated_at" && "$updated_at" != "null" ]]; then
    # Format timestamp for display (simplified)
    local formatted_date="${updated_at%%T*}"
    echo "  Updated: ${formatted_date}"
  fi

  # Show source URL
  local source_url="${UPSTREAM_REPO%.git}"
  echo "  Source:  ${source_url}"

  # Check for available updates
  local cache_file="${HOME}/.loa/cache/update-check.json"
  if [[ -f "$cache_file" ]]; then
    local update_available latest_version
    update_available=$(jq -r '.update_available // false' "$cache_file" 2>/dev/null)
    latest_version=$(jq -r '.remote_version // ""' "$cache_file" 2>/dev/null)

    if [[ "$update_available" == "true" && -n "$latest_version" ]]; then
      echo ""
      echo -e "  ${GREEN}Update available:${NC} ${latest_version}"
      echo -e "  Run ${CYAN}/update-loa${NC} to upgrade"
    fi
  fi

  # Suggest stable version if on feature branch
  if [[ "$ref_type" == "branch" && "$ref" != "main" && "$ref" != "master" ]]; then
    echo ""
    echo -e "  ${CYAN}Tip:${NC} Run /update-loa @latest to switch to stable"
  fi

  echo ""
}

# === Main Logic ===

main() {
  # Version-only mode
  if [[ "$VERSION_ONLY" == "true" ]]; then
    if [[ "$JSON_OUTPUT" == "true" ]]; then
      get_version_info_json
    else
      display_version_info
    fi
    exit 0
  fi

  # Full status mode
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    # Combine workflow state and version info into single JSON
    local workflow_json version_json

    if [[ -x "$WORKFLOW_STATE_SCRIPT" ]]; then
      workflow_json=$("$WORKFLOW_STATE_SCRIPT" --json 2>/dev/null || echo '{}')
    else
      workflow_json='{}'
    fi

    version_json=$(get_version_info_json)

    # Merge the two JSON objects
    jq -s '.[0] * { "framework": .[1] }' \
      <(echo "$workflow_json") \
      <(echo "$version_json")
  else
    # Human-readable combined output
    echo "═══════════════════════════════════════════════════════════════"
    echo -e " ${BOLD}Loa Status${NC}"
    echo "═══════════════════════════════════════════════════════════════"

    # Version info section
    display_version_info

    echo "───────────────────────────────────────────────────────────────"

    # Workflow state section
    if [[ -x "$WORKFLOW_STATE_SCRIPT" ]]; then
      echo ""
      echo -e "${BOLD}Workflow State${NC}"

      # Run workflow-state and extract info
      local state description progress current_sprint total_sprints completed_sprints suggested

      state_json=$("$WORKFLOW_STATE_SCRIPT" --json 2>/dev/null || echo '{}')

      state=$(echo "$state_json" | jq -r '.state // "unknown"')
      description=$(echo "$state_json" | jq -r '.description // ""')
      progress=$(echo "$state_json" | jq -r '.progress_percent // 0')
      current_sprint=$(echo "$state_json" | jq -r '.current_sprint // ""')
      total_sprints=$(echo "$state_json" | jq -r '.total_sprints // 0')
      completed_sprints=$(echo "$state_json" | jq -r '.completed_sprints // 0')
      suggested=$(echo "$state_json" | jq -r '.suggested_command // ""')

      echo "  State: ${state}"
      [[ -n "$description" ]] && echo "  ${description}"

      # Progress bar
      local filled=$((progress / 5))
      local empty=$((20 - filled))
      printf "  Progress: ["
      printf '%0.s█' $(seq 1 $filled 2>/dev/null) || true
      printf '%0.s░' $(seq 1 $empty 2>/dev/null) || true
      printf "] %d%%\n" "$progress"

      [[ -n "$current_sprint" ]] && echo "  Current Sprint: ${current_sprint}"
      echo "  Sprints: ${completed_sprints}/${total_sprints} complete"

      echo ""
      echo "───────────────────────────────────────────────────────────────"
      [[ -n "$suggested" ]] && echo -e " ${BOLD}Suggested:${NC} ${CYAN}${suggested}${NC}"
    else
      echo ""
      echo "  Workflow state detection unavailable"
      echo "  (workflow-state.sh not found)"
    fi

    echo "═══════════════════════════════════════════════════════════════"
    echo ""
  fi
}

main "$@"
