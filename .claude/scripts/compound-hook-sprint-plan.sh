#!/bin/bash
# =============================================================================
# compound-hook-sprint-plan.sh - Compound Learning Hook for /run sprint-plan
# =============================================================================
# Sprint 8, Task 8.8-8.9: Hook triggered after sprint-plan completes
# Goal Contribution: G-3 (Automate knowledge consolidation)
#
# This hook is called by /run sprint-plan after all sprints complete,
# before cleanup_context_directory(). It runs batch retrospective on the
# sprint-plan trajectory and extracts skills.
#
# Usage:
#   ./compound-hook-sprint-plan.sh [options]
#
# Options:
#   --sprint-plan-id ID  Sprint plan identifier
#   --state-file FILE    Path to sprint-plan-state.json
#   --auto-approve       Auto-approve extracted skills
#   --no-compound        Skip compound review (just exit)
#   --dry-run            Preview without changes
#   --help               Show this help
#
# Configuration (.loa.config.yaml):
#   run_mode:
#     sprint_plan:
#       compound_on_complete: true     # Enable hook
#       compound_auto_approve: false   # Auto-approve skills
#       compound_fail_action: warn     # warn | fail
# =============================================================================

set -uo pipefail
# Note: -e disabled to allow proper error handling

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"
TRAJECTORY_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"

# Parameters
SPRINT_PLAN_ID=""
STATE_FILE=""
AUTO_APPROVE=false
NO_COMPOUND=false
DRY_RUN=false

# Config values
CFG_ENABLED=true
CFG_AUTO_APPROVE=false
CFG_FAIL_ACTION="warn"

# Usage
usage() {
  sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
  exit 0
}

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sprint-plan-id)
        SPRINT_PLAN_ID="$2"
        shift 2
        ;;
      --state-file)
        STATE_FILE="$2"
        shift 2
        ;;
      --auto-approve)
        AUTO_APPROVE=true
        shift
        ;;
      --no-compound)
        NO_COMPOUND=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --help|-h)
        usage
        ;;
      *)
        echo "[ERROR] Unknown option: $1" >&2
        exit 1
        ;;
    esac
  done
}

# Load configuration
load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    CFG_ENABLED=$(yq -e '.run_mode.sprint_plan.compound_on_complete // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
    CFG_AUTO_APPROVE=$(yq -e '.run_mode.sprint_plan.compound_auto_approve // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
    CFG_FAIL_ACTION=$(yq -e '.run_mode.sprint_plan.compound_fail_action // "warn"' "$CONFIG_FILE" 2>/dev/null || echo "warn")
  fi
  
  # Command line overrides
  [[ "$AUTO_APPROVE" == "true" ]] && CFG_AUTO_APPROVE=true
}

# Log message
log() {
  echo "[COMPOUND-HOOK] $*"
}

# Handle failure based on config
handle_failure() {
  local message="$1"
  
  log "ERROR: $message"
  
  if [[ "$CFG_FAIL_ACTION" == "fail" ]]; then
    exit 1
  else
    log "WARNING: Continuing despite failure (compound_fail_action=warn)"
    return 0
  fi
}

# Update sprint-plan state file
update_state() {
  local learnings_count="$1"
  
  if [[ -z "$STATE_FILE" || ! -f "$STATE_FILE" ]]; then
    log "No state file to update"
    return
  fi
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would update state file with learnings_extracted=$learnings_count"
    return
  fi
  
  # Update the state file
  jq --argjson count "$learnings_count" '
    .metrics.learnings_extracted = $count |
    .compound_review_completed = true
  ' "$STATE_FILE" > "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
  
  log "Updated state file: learnings_extracted=$learnings_count"
}

# Run compound review
run_compound_review() {
  log "Starting compound review for sprint-plan..."
  
  local orchestrator="${SCRIPT_DIR}/compound-orchestrator.sh"
  
  if [[ ! -x "$orchestrator" ]]; then
    handle_failure "compound-orchestrator.sh not found or not executable"
    return $?
  fi
  
  # Build args
  local args=""
  args+=" --sprint-plan"  # Signal we're in sprint-plan mode
  [[ "$DRY_RUN" == "true" ]] && args+=" --dry-run"
  [[ "$CFG_AUTO_APPROVE" == "true" ]] && args+=" --force"
  
  # Run compound review
  local output
  local exit_code=0
  # shellcheck disable=SC2086
  output=$("$orchestrator" --review-only $args 2>&1) || exit_code=$?
  
  if [[ "$exit_code" -ne 0 ]]; then
    log "Compound review output:"
    echo "$output"
    handle_failure "Compound review failed with exit code $exit_code"
    return $?
  fi
  
  # Extract learnings count from output
  local learnings_count
  learnings_count=$(echo "$output" | grep -oE 'Skills Extracted:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' || echo "0")
  
  log "Extracted $learnings_count skills"
  
  # Update state file
  update_state "$learnings_count"
  
  log "Compound review completed successfully"
  return 0
}

# Main
main() {
  parse_args "$@"
  load_config
  
  # Check if compound learning is enabled
  if [[ "$CFG_ENABLED" != "true" || "$NO_COMPOUND" == "true" ]]; then
    log "Compound learning disabled, skipping review"
    exit 0
  fi
  
  log "Configuration:"
  log "  compound_on_complete: $CFG_ENABLED"
  log "  compound_auto_approve: $CFG_AUTO_APPROVE"
  log "  compound_fail_action: $CFG_FAIL_ACTION"
  
  if [[ -n "$SPRINT_PLAN_ID" ]]; then
    log "  sprint_plan_id: $SPRINT_PLAN_ID"
  fi
  
  if [[ -n "$STATE_FILE" ]]; then
    log "  state_file: $STATE_FILE"
  fi
  
  # Run the review
  run_compound_review
}

main "$@"
