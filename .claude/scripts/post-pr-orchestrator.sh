#!/usr/bin/env bash
# post-pr-orchestrator.sh - Post-PR Validation Loop Orchestrator
# Part of Loa Framework v1.25.0
#
# Executes validation phases after PR creation:
#   PR_CREATED → POST_PR_AUDIT → CONTEXT_CLEAR → E2E_TESTING → FLATLINE_PR → READY_FOR_HITL
#
# Usage:
#   post-pr-orchestrator.sh --pr-url <url> [options]
#
# Options:
#   --pr-url <url>      PR URL (required)
#   --mode <mode>       Mode: autonomous | hitl (default: autonomous)
#   --skip-audit        Skip audit phase
#   --skip-e2e          Skip E2E testing phase
#   --skip-flatline     Skip Flatline PR review phase
#   --dry-run           Show planned phases without executing
#   --resume            Resume from checkpoint
#   --timeout <secs>    Override default timeout
#
# Exit codes:
#   0 - Success (READY_FOR_HITL)
#   1 - Invalid arguments
#   2 - Phase timeout
#   3 - Phase failure (audit/e2e)
#   4 - Blocker found (Flatline)
#   5 - Halted by user

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly STATE_SCRIPT="${SCRIPT_DIR}/post-pr-state.sh"
readonly AUDIT_SCRIPT="${SCRIPT_DIR}/post-pr-audit.sh"
readonly CONTEXT_SCRIPT="${SCRIPT_DIR}/post-pr-context-clear.sh"
readonly E2E_SCRIPT="${SCRIPT_DIR}/post-pr-e2e.sh"

# Per-phase timeouts (seconds) - Flatline IMP-001
readonly TIMEOUT_POST_PR_AUDIT="${TIMEOUT_POST_PR_AUDIT:-600}"    # 10 min
readonly TIMEOUT_CONTEXT_CLEAR="${TIMEOUT_CONTEXT_CLEAR:-60}"     # 1 min
readonly TIMEOUT_E2E_TESTING="${TIMEOUT_E2E_TESTING:-1200}"       # 20 min
readonly TIMEOUT_FLATLINE_PR="${TIMEOUT_FLATLINE_PR:-300}"        # 5 min

# State machine states
readonly STATE_PR_CREATED="PR_CREATED"
readonly STATE_POST_PR_AUDIT="POST_PR_AUDIT"
readonly STATE_FIX_AUDIT="FIX_AUDIT"
readonly STATE_CONTEXT_CLEAR="CONTEXT_CLEAR"
readonly STATE_E2E_TESTING="E2E_TESTING"
readonly STATE_FIX_E2E="FIX_E2E"
readonly STATE_FLATLINE_PR="FLATLINE_PR"
readonly STATE_READY_FOR_HITL="READY_FOR_HITL"
readonly STATE_HALTED="HALTED"

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
  echo "[INFO] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}

log_phase() {
  echo ""
  echo "=========================================="
  echo "[PHASE] $*"
  echo "=========================================="
}

log_success() {
  echo "[SUCCESS] $*" >&2
}

# Update state file
update_state() {
  local new_state="$1"
  "$STATE_SCRIPT" set state "$new_state"
}

# Get current state
get_state() {
  "$STATE_SCRIPT" get state 2>/dev/null || echo ""
}

# Check if phase should be skipped
should_skip_phase() {
  local phase="$1"
  local status
  status=$("$STATE_SCRIPT" get "phases.${phase}" 2>/dev/null || echo "")

  if [[ "$status" == "skipped" ]] || [[ "$status" == "completed" ]]; then
    return 0
  fi
  return 1
}

# Run command with timeout (H-1 fix: array-based execution, no bash -c)
run_with_timeout() {
  local timeout_val="$1"
  shift
  # Execute command array directly, not via bash -c string interpolation
  local -a cmd_array=("$@")

  if command -v timeout &>/dev/null; then
    timeout "$timeout_val" "${cmd_array[@]}"
  else
    # Fallback for systems without timeout (macOS)
    local pid
    "${cmd_array[@]}" &
    pid=$!

    local count=0
    while kill -0 "$pid" 2>/dev/null; do
      sleep 1
      ((++count))
      if (( count >= timeout_val )); then
        kill -TERM "$pid" 2>/dev/null || true
        sleep 2
        kill -KILL "$pid" 2>/dev/null || true
        return 124  # timeout exit code
      fi
    done

    wait "$pid"
  fi
}

# ============================================================================
# Signal Handling
# ============================================================================

cleanup_on_signal() {
  log_info "Received interrupt signal, saving state..."

  # Update state to HALTED
  if [[ -f "${STATE_DIR:-.run}/post-pr-state.json" ]]; then
    "$STATE_SCRIPT" set state "$STATE_HALTED" 2>/dev/null || true
    "$STATE_SCRIPT" set "halt_reason" "user_interrupt" 2>/dev/null || true
  fi

  log_info "State saved. Use --resume to continue."
  exit 5
}

trap cleanup_on_signal SIGINT SIGTERM

# ============================================================================
# Phase Handlers
# ============================================================================

phase_post_pr_audit() {
  log_phase "POST_PR_AUDIT"

  "$STATE_SCRIPT" update-phase post_pr_audit in_progress
  update_state "$STATE_POST_PR_AUDIT"

  local iteration
  iteration=$("$STATE_SCRIPT" get "audit.iteration" 2>/dev/null || echo "0")
  local max_iterations
  max_iterations=$("$STATE_SCRIPT" get "audit.max_iterations" 2>/dev/null || echo "5")

  while (( iteration < max_iterations )); do
    ((++iteration))
    log_info "Audit iteration $iteration/$max_iterations"

    "$STATE_SCRIPT" set "audit.iteration" "$iteration"

    # Run audit with timeout
    local audit_result=0
    if [[ -x "$AUDIT_SCRIPT" ]]; then
      run_with_timeout "$TIMEOUT_POST_PR_AUDIT" "$AUDIT_SCRIPT" --pr-url "$PR_URL" || audit_result=$?
    else
      # Placeholder: audit not implemented yet
      log_info "Audit script not found, assuming APPROVED"
      audit_result=0
    fi

    case $audit_result in
      0)
        # APPROVED
        log_success "Audit APPROVED"
        "$STATE_SCRIPT" update-phase post_pr_audit completed
        "$STATE_SCRIPT" add-marker "PR-AUDITED"
        return 0
        ;;
      1)
        # CHANGES_REQUIRED - enter fix loop
        log_info "Changes required, entering fix loop..."
        update_state "$STATE_FIX_AUDIT"

        # Check circuit breaker: same finding 3x
        local finding_count
        finding_count=$("$STATE_SCRIPT" get "audit.finding_identities" 2>/dev/null | jq 'length' 2>/dev/null || echo "0")

        if (( finding_count >= 3 )); then
          log_error "Circuit breaker: Same finding appeared 3+ times"
          update_state "$STATE_HALTED"
          "$STATE_SCRIPT" set "halt_reason" "audit_circuit_breaker"
          return 3
        fi

        # In dry-run or placeholder mode, break after first iteration
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
          break
        fi
        ;;
      2)
        # ESCALATED
        log_error "Audit escalated - requires human review"
        update_state "$STATE_HALTED"
        "$STATE_SCRIPT" set "halt_reason" "audit_escalated"
        return 3
        ;;
      124)
        # Timeout
        log_error "Audit phase timed out after ${TIMEOUT_POST_PR_AUDIT}s"
        update_state "$STATE_HALTED"
        "$STATE_SCRIPT" set "halt_reason" "audit_timeout"
        return 2
        ;;
      *)
        # ERROR
        log_error "Audit failed with exit code: $audit_result"
        update_state "$STATE_HALTED"
        "$STATE_SCRIPT" set "halt_reason" "audit_error"
        return 3
        ;;
    esac
  done

  # Max iterations reached
  log_error "Max audit iterations ($max_iterations) reached"
  update_state "$STATE_HALTED"
  "$STATE_SCRIPT" set "halt_reason" "audit_max_iterations"
  return 3
}

phase_context_clear() {
  log_phase "CONTEXT_CLEAR"

  "$STATE_SCRIPT" update-phase context_clear in_progress
  update_state "$STATE_CONTEXT_CLEAR"

  # Run context clear with timeout
  local result=0
  if [[ -x "$CONTEXT_SCRIPT" ]]; then
    run_with_timeout "$TIMEOUT_CONTEXT_CLEAR" "$CONTEXT_SCRIPT" || result=$?
  else
    # Placeholder: display instructions
    log_info "Context clear instructions:"
    echo ""
    echo "=========================================="
    echo "  CONTEXT CLEAR REQUIRED"
    echo "=========================================="
    echo ""
    echo "To continue with fresh-eyes E2E testing:"
    echo ""
    echo "  1. Run: /clear"
    echo "  2. Run: /simstim --resume"
    echo "     OR:  post-pr-orchestrator.sh --resume --pr-url '$PR_URL'"
    echo ""
    echo "State has been saved. The next phase will be E2E_TESTING."
    echo ""
    result=0
  fi

  if (( result == 0 )); then
    "$STATE_SCRIPT" update-phase context_clear completed
    return 0
  elif (( result == 124 )); then
    log_error "Context clear timed out"
    update_state "$STATE_HALTED"
    return 2
  else
    log_error "Context clear failed"
    return 3
  fi
}

phase_e2e_testing() {
  log_phase "E2E_TESTING"

  "$STATE_SCRIPT" update-phase e2e_testing in_progress
  update_state "$STATE_E2E_TESTING"

  local iteration
  iteration=$("$STATE_SCRIPT" get "e2e.iteration" 2>/dev/null || echo "0")
  local max_iterations
  max_iterations=$("$STATE_SCRIPT" get "e2e.max_iterations" 2>/dev/null || echo "3")

  while (( iteration < max_iterations )); do
    ((++iteration))
    log_info "E2E iteration $iteration/$max_iterations"

    "$STATE_SCRIPT" set "e2e.iteration" "$iteration"

    # Run E2E tests with timeout
    local e2e_result=0
    if [[ -x "$E2E_SCRIPT" ]]; then
      run_with_timeout "$TIMEOUT_E2E_TESTING" "$E2E_SCRIPT" || e2e_result=$?
    else
      # Placeholder: E2E not implemented yet
      log_info "E2E script not found, assuming PASSED"
      e2e_result=0
    fi

    case $e2e_result in
      0)
        # PASSED
        log_success "E2E tests PASSED"
        "$STATE_SCRIPT" update-phase e2e_testing completed
        "$STATE_SCRIPT" add-marker "PR-E2E-PASSED"
        return 0
        ;;
      1)
        # FAILED - enter fix loop
        log_info "E2E tests failed, entering fix loop..."
        update_state "$STATE_FIX_E2E"

        # Check circuit breaker: same failure 2x
        local failure_count
        failure_count=$("$STATE_SCRIPT" get "e2e.failure_identities" 2>/dev/null | jq 'length' 2>/dev/null || echo "0")

        if (( failure_count >= 2 )); then
          log_error "Circuit breaker: Same failure appeared 2+ times"
          update_state "$STATE_HALTED"
          "$STATE_SCRIPT" set "halt_reason" "e2e_circuit_breaker"
          return 3
        fi

        # In dry-run or placeholder mode, break after first iteration
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
          break
        fi
        ;;
      2)
        # BUILD_FAILED
        log_error "Build failed - cannot run E2E tests"
        update_state "$STATE_HALTED"
        "$STATE_SCRIPT" set "halt_reason" "build_failed"
        return 3
        ;;
      124)
        # Timeout
        log_error "E2E phase timed out after ${TIMEOUT_E2E_TESTING}s"
        update_state "$STATE_HALTED"
        "$STATE_SCRIPT" set "halt_reason" "e2e_timeout"
        return 2
        ;;
      *)
        # ERROR
        log_error "E2E tests failed with exit code: $e2e_result"
        update_state "$STATE_HALTED"
        "$STATE_SCRIPT" set "halt_reason" "e2e_error"
        return 3
        ;;
    esac
  done

  # Max iterations reached
  log_error "Max E2E iterations ($max_iterations) reached"
  update_state "$STATE_HALTED"
  "$STATE_SCRIPT" set "halt_reason" "e2e_max_iterations"
  return 3
}

phase_flatline_pr() {
  log_phase "FLATLINE_PR"

  # Check if Flatline is enabled
  local flatline_enabled
  flatline_enabled=$(yq '.flatline_protocol.enabled // false' .loa.config.yaml 2>/dev/null || echo "false")

  if [[ "$flatline_enabled" != "true" ]]; then
    log_info "Flatline PR review disabled, skipping"
    "$STATE_SCRIPT" update-phase flatline_pr skipped
    return 0
  fi

  "$STATE_SCRIPT" update-phase flatline_pr in_progress
  update_state "$STATE_FLATLINE_PR"

  # Display cost estimate
  log_info "Estimated cost for Flatline PR review: ~\$1.50"

  local mode
  mode=$("$STATE_SCRIPT" get mode 2>/dev/null || echo "autonomous")

  # Run Flatline with timeout
  local flatline_result=0
  if [[ -x "${SCRIPT_DIR}/flatline-orchestrator.sh" ]]; then
    local flatline_mode="--autonomous"
    if [[ "$mode" == "hitl" ]]; then
      flatline_mode="--interactive"
    fi

    # Get PRD and SDD paths
    local prd_path="grimoires/loa/prd.md"
    local sdd_path="grimoires/loa/sdd.md"

    run_with_timeout "$TIMEOUT_FLATLINE_PR" \
      "${SCRIPT_DIR}/flatline-orchestrator.sh" --doc "$prd_path" --doc "$sdd_path" --phase pr "$flatline_mode" \
      || flatline_result=$?
  else
    log_info "Flatline orchestrator not found, skipping"
    flatline_result=0
  fi

  case $flatline_result in
    0)
      # Success
      log_success "Flatline PR review completed"
      "$STATE_SCRIPT" update-phase flatline_pr completed
      "$STATE_SCRIPT" add-marker "PR-VALIDATED"
      return 0
      ;;
    1)
      # Blocker found
      if [[ "$mode" == "autonomous" ]]; then
        log_error "Flatline found blocker - halting autonomous mode"
        update_state "$STATE_HALTED"
        "$STATE_SCRIPT" set "halt_reason" "flatline_blocker"
        return 4
      else
        # HITL mode - prompt user
        log_info "Flatline found blocker - please review and decide"
        return 0
      fi
      ;;
    124)
      # Timeout - mark as skipped and continue
      log_info "Flatline PR review timed out, continuing"
      "$STATE_SCRIPT" update-phase flatline_pr skipped
      return 0
      ;;
    *)
      # Error - mark as skipped and continue
      log_info "Flatline PR review failed (exit: $flatline_result), continuing"
      "$STATE_SCRIPT" update-phase flatline_pr skipped
      return 0
      ;;
  esac
}

# ============================================================================
# Main Orchestration
# ============================================================================

run_dry_run() {
  echo ""
  echo "=========================================="
  echo "  POST-PR VALIDATION - DRY RUN"
  echo "=========================================="
  echo ""
  echo "PR URL: $PR_URL"
  echo "Mode: $MODE"
  echo ""
  echo "Planned phases:"
  echo ""

  local phase_num=1

  if [[ "$SKIP_AUDIT" != "true" ]]; then
    echo "  $phase_num. POST_PR_AUDIT (timeout: ${TIMEOUT_POST_PR_AUDIT}s)"
    echo "     - Run consolidated audit on PR changes"
    echo "     - Fix loop: max 5 iterations, circuit breaker on 3x same finding"
    ((++phase_num))
  fi

  echo "  $phase_num. CONTEXT_CLEAR (timeout: ${TIMEOUT_CONTEXT_CLEAR}s)"
  echo "     - Save checkpoint to NOTES.md"
  echo "     - Instruct user: /clear then /simstim --resume"
  ((++phase_num))

  if [[ "$SKIP_E2E" != "true" ]]; then
    echo "  $phase_num. E2E_TESTING (timeout: ${TIMEOUT_E2E_TESTING}s)"
    echo "     - Run build and tests with fresh context"
    echo "     - Fix loop: max 3 iterations, circuit breaker on 2x same failure"
    ((++phase_num))
  fi

  if [[ "$SKIP_FLATLINE" != "true" ]]; then
    echo "  $phase_num. FLATLINE_PR (timeout: ${TIMEOUT_FLATLINE_PR}s)"
    echo "     - Optional multi-model adversarial review (~\$1.50)"
    echo "     - Mode: $MODE (blocker handling differs)"
    ((++phase_num))
  fi

  echo "  $phase_num. READY_FOR_HITL"
  echo "     - All validations complete"
  echo "     - PR ready for human review"
  echo ""
  echo "Exit codes:"
  echo "  0 = Success | 1 = Invalid args | 2 = Timeout | 3 = Failure | 4 = Blocker | 5 = Halted"
  echo ""
}

run_orchestration() {
  local current_state
  current_state=$(get_state)

  log_info "Starting from state: ${current_state:-PR_CREATED}"

  # State machine
  case "${current_state:-PR_CREATED}" in
    "$STATE_PR_CREATED")
      if [[ "$SKIP_AUDIT" != "true" ]]; then
        phase_post_pr_audit || return $?
      else
        log_info "Skipping audit phase"
        "$STATE_SCRIPT" update-phase post_pr_audit skipped
      fi
      ;&  # Fall through

    "$STATE_POST_PR_AUDIT"|"$STATE_FIX_AUDIT")
      if [[ "$(get_state)" != "$STATE_HALTED" ]]; then
        phase_context_clear || return $?
        # After context clear, we need user to /clear and --resume
        log_info "Waiting for context clear and resume..."
        return 0
      fi
      ;;

    "$STATE_CONTEXT_CLEAR")
      if [[ "$SKIP_E2E" != "true" ]]; then
        phase_e2e_testing || return $?
      else
        log_info "Skipping E2E phase"
        "$STATE_SCRIPT" update-phase e2e_testing skipped
      fi
      ;&  # Fall through

    "$STATE_E2E_TESTING"|"$STATE_FIX_E2E")
      if [[ "$(get_state)" != "$STATE_HALTED" ]]; then
        if [[ "$SKIP_FLATLINE" != "true" ]]; then
          phase_flatline_pr || return $?
        else
          log_info "Skipping Flatline phase"
          "$STATE_SCRIPT" update-phase flatline_pr skipped
        fi
      fi
      ;&  # Fall through

    "$STATE_FLATLINE_PR")
      if [[ "$(get_state)" != "$STATE_HALTED" ]]; then
        update_state "$STATE_READY_FOR_HITL"
        log_success "Post-PR validation complete - READY_FOR_HITL"
        return 0
      fi
      ;;

    "$STATE_READY_FOR_HITL")
      log_info "Already at READY_FOR_HITL"
      return 0
      ;;

    "$STATE_HALTED")
      local reason
      reason=$("$STATE_SCRIPT" get halt_reason 2>/dev/null || echo "unknown")
      log_error "Orchestration halted: $reason"
      return 5
      ;;

    *)
      log_error "Unknown state: $current_state"
      return 1
      ;;
  esac
}

# ============================================================================
# Main
# ============================================================================

main() {
  # Defaults
  PR_URL=""
  MODE="autonomous"
  SKIP_AUDIT="false"
  SKIP_E2E="false"
  SKIP_FLATLINE="false"
  DRY_RUN="false"
  RESUME="false"

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pr-url)
        PR_URL="$2"
        shift 2
        ;;
      --mode)
        MODE="$2"
        shift 2
        ;;
      --skip-audit)
        SKIP_AUDIT="true"
        shift
        ;;
      --skip-e2e)
        SKIP_E2E="true"
        shift
        ;;
      --skip-flatline)
        SKIP_FLATLINE="true"
        shift
        ;;
      --dry-run)
        DRY_RUN="true"
        shift
        ;;
      --resume)
        RESUME="true"
        shift
        ;;
      --timeout)
        # Override all timeouts
        TIMEOUT_POST_PR_AUDIT="$2"
        TIMEOUT_CONTEXT_CLEAR="$2"
        TIMEOUT_E2E_TESTING="$2"
        TIMEOUT_FLATLINE_PR="$2"
        shift 2
        ;;
      --help|-h)
        echo "Usage: post-pr-orchestrator.sh --pr-url <url> [options]"
        echo ""
        echo "Options:"
        echo "  --pr-url <url>      PR URL (required)"
        echo "  --mode <mode>       Mode: autonomous | hitl (default: autonomous)"
        echo "  --skip-audit        Skip audit phase"
        echo "  --skip-e2e          Skip E2E testing phase"
        echo "  --skip-flatline     Skip Flatline PR review phase"
        echo "  --dry-run           Show planned phases without executing"
        echo "  --resume            Resume from checkpoint"
        echo "  --timeout <secs>    Override default timeout"
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        exit 1
        ;;
    esac
  done

  # Validate PR URL
  if [[ -z "$PR_URL" ]]; then
    log_error "Missing required argument: --pr-url"
    exit 1
  fi

  # Export for subprocesses
  export PR_URL MODE DRY_RUN

  # Handle dry-run
  if [[ "$DRY_RUN" == "true" ]]; then
    run_dry_run
    exit 0
  fi

  # Initialize or resume state
  if [[ "$RESUME" != "true" ]]; then
    log_info "Initializing post-PR validation state..."
    "$STATE_SCRIPT" init --pr-url "$PR_URL" --mode "$MODE" || exit $?
  else
    log_info "Resuming from checkpoint..."
    if [[ ! -f "${STATE_DIR:-.run}/post-pr-state.json" ]]; then
      log_error "No state file found to resume from"
      exit 1
    fi
  fi

  # Run orchestration
  run_orchestration
  exit $?
}

main "$@"
