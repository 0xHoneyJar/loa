#!/usr/bin/env bash
set -euo pipefail

# check-permissions.sh - Pre-flight validation for Run Mode
# Verifies Claude Code has required permissions to execute autonomous operations
#
# Usage:
#   check-permissions.sh           Check all permissions
#   check-permissions.sh --json    Output as JSON
#   check-permissions.sh --quiet   Suppress output, exit code only
#
# Exit codes:
#   0 - All required permissions configured
#   1 - Missing required permissions
#   2 - Settings file not found

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETTINGS_FILE="$REPO_ROOT/.claude/settings.json"

# ============================================================================
# REQUIRED PERMISSIONS FOR RUN MODE
# ============================================================================

# Git operations required for autonomous execution
REQUIRED_GIT_PERMISSIONS=(
  "Bash(git checkout:*)"
  "Bash(git commit:*)"
  "Bash(git push:*)"
  "Bash(git branch:*)"
  "Bash(git add:*)"
  "Bash(git status:*)"
  "Bash(git diff:*)"
  "Bash(git rev-parse:*)"
  "Bash(git show-ref:*)"
)

# GitHub CLI operations for PR creation
REQUIRED_GH_PERMISSIONS=(
  "Bash(gh:*)"
  "Bash(gh pr:*)"
)

# File operations required for implementation
REQUIRED_FILE_PERMISSIONS=(
  "Bash(mkdir:*)"
  "Bash(rm:*)"
  "Bash(cp:*)"
  "Bash(mv:*)"
)

# Shell execution required for scripts
REQUIRED_SHELL_PERMISSIONS=(
  "Bash(bash:*)"
)

# ============================================================================
# PARSING
# ============================================================================

OUTPUT_MODE="text"
QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      OUTPUT_MODE="json"
      shift
      ;;
    --quiet|-q)
      QUIET=true
      shift
      ;;
    --help|-h)
      echo "check-permissions.sh - Pre-flight validation for Run Mode"
      echo ""
      echo "Usage:"
      echo "  check-permissions.sh           Check all permissions"
      echo "  check-permissions.sh --json    Output as JSON"
      echo "  check-permissions.sh --quiet   Suppress output, exit code only"
      echo ""
      echo "Exit codes:"
      echo "  0 - All required permissions configured"
      echo "  1 - Missing required permissions"
      echo "  2 - Settings file not found"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log() {
  if [[ "$QUIET" != "true" && "$OUTPUT_MODE" == "text" ]]; then
    echo "$@"
  fi
}

log_error() {
  if [[ "$OUTPUT_MODE" == "text" ]]; then
    echo "ERROR: $*" >&2
  fi
}

# Check if a permission pattern is in the allow list
# Handles wildcard matching (e.g., "Bash(git:*)" matches "Bash(git checkout:*)")
check_permission() {
  local required="$1"
  local allow_list="$2"

  # Direct match
  if echo "$allow_list" | grep -qF "\"$required\""; then
    return 0
  fi

  # Extract command base (e.g., "git checkout" from "Bash(git checkout:*)")
  local cmd_base
  cmd_base=$(echo "$required" | sed -E 's/Bash\(([^:]+):.*\)/\1/')

  # Check for broader wildcard (e.g., "Bash(git:*)" covers "git checkout")
  local base_pattern="Bash(${cmd_base%% *}:*)"
  if echo "$allow_list" | grep -qF "\"$base_pattern\""; then
    return 0
  fi

  return 1
}

# ============================================================================
# MAIN LOGIC
# ============================================================================

main() {
  # Check settings file exists
  if [[ ! -f "$SETTINGS_FILE" ]]; then
    if [[ "$OUTPUT_MODE" == "json" ]]; then
      echo '{"success": false, "error": "Settings file not found", "path": "'"$SETTINGS_FILE"'"}'
    else
      log_error "Settings file not found: $SETTINGS_FILE"
      log_error "Run Mode requires .claude/settings.json with permission configuration"
    fi
    exit 2
  fi

  # Read allow list
  local allow_list
  allow_list=$(cat "$SETTINGS_FILE")

  # Track results
  local missing_permissions=()
  local found_permissions=()
  local all_required=(
    "${REQUIRED_GIT_PERMISSIONS[@]}"
    "${REQUIRED_GH_PERMISSIONS[@]}"
    "${REQUIRED_FILE_PERMISSIONS[@]}"
    "${REQUIRED_SHELL_PERMISSIONS[@]}"
  )

  # Check each required permission
  for perm in "${all_required[@]}"; do
    if check_permission "$perm" "$allow_list"; then
      found_permissions+=("$perm")
    else
      missing_permissions+=("$perm")
    fi
  done

  # Output results
  local total_required=${#all_required[@]}
  local total_found=${#found_permissions[@]}
  local total_missing=${#missing_permissions[@]}

  if [[ "$OUTPUT_MODE" == "json" ]]; then
    # Build JSON output
    local missing_json="[]"
    local found_json="[]"

    if [[ ${#missing_permissions[@]} -gt 0 ]]; then
      missing_json=$(printf '%s\n' "${missing_permissions[@]}" | jq -R . | jq -s .)
    fi
    if [[ ${#found_permissions[@]} -gt 0 ]]; then
      found_json=$(printf '%s\n' "${found_permissions[@]}" | jq -R . | jq -s .)
    fi

    local success="true"
    if [[ $total_missing -gt 0 ]]; then
      success="false"
    fi

    cat << EOF
{
  "success": $success,
  "total_required": $total_required,
  "total_found": $total_found,
  "total_missing": $total_missing,
  "found": $found_json,
  "missing": $missing_json,
  "settings_path": "$SETTINGS_FILE"
}
EOF
  else
    # Text output
    log "Run Mode Permission Check"
    log "========================="
    log ""
    log "Settings file: $SETTINGS_FILE"
    log ""

    if [[ $total_missing -eq 0 ]]; then
      log "✓ All $total_required required permissions are configured"
      log ""
      log "Categories verified:"
      log "  - Git operations: ${#REQUIRED_GIT_PERMISSIONS[@]} permissions"
      log "  - GitHub CLI: ${#REQUIRED_GH_PERMISSIONS[@]} permissions"
      log "  - File operations: ${#REQUIRED_FILE_PERMISSIONS[@]} permissions"
      log "  - Shell execution: ${#REQUIRED_SHELL_PERMISSIONS[@]} permissions"
      log ""
      log "Run Mode pre-flight check: PASSED"
    else
      log "✗ Missing $total_missing of $total_required required permissions"
      log ""
      log "Missing permissions:"
      for perm in "${missing_permissions[@]}"; do
        log "  - $perm"
      done
      log ""
      log "To fix, add the missing permissions to .claude/settings.json under"
      log "\"permissions\".\"allow\""
      log ""
      log "Run Mode pre-flight check: FAILED"
    fi
  fi

  # Exit with appropriate code
  if [[ $total_missing -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

# Only run main if script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
