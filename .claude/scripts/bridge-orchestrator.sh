#!/usr/bin/env bash
# bridge-orchestrator.sh - Run Bridge loop orchestrator
# Version: 1.0.0
#
# Main orchestrator for the bridge loop: iteratively runs sprint-plan,
# invokes Bridgebuilder review, parses findings, detects flatline,
# and generates new sprint plans from findings.
#
# Usage:
#   bridge-orchestrator.sh [OPTIONS]
#
# Options:
#   --depth N          Maximum iterations (default: 3)
#   --per-sprint       Review after each sprint instead of full plan
#   --resume           Resume from interrupted bridge
#   --from PHASE       Start from phase (sprint-plan)
#   --help             Show help
#
# Exit Codes:
#   0 - Complete (JACKED_OUT)
#   1 - Halted (circuit breaker or error)
#   2 - Config error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"
source "$SCRIPT_DIR/bridge-state.sh"

# =============================================================================
# Defaults (overridden by config)
# =============================================================================

DEPTH=3
PER_SPRINT=false
RESUME=false
FROM_PHASE=""
FLATLINE_THRESHOLD=0.05
CONSECUTIVE_FLATLINE=2
PER_ITERATION_TIMEOUT=14400   # 4 hours in seconds
TOTAL_TIMEOUT=86400            # 24 hours in seconds

# =============================================================================
# Usage
# =============================================================================

usage() {
  cat <<'USAGE'
Usage: bridge-orchestrator.sh [OPTIONS]

Options:
  --depth N          Maximum iterations (default: 3)
  --per-sprint       Review after each sprint instead of full plan
  --resume           Resume from interrupted bridge
  --from PHASE       Start from phase (sprint-plan)
  --help             Show help

Exit Codes:
  0  Complete (JACKED_OUT)
  1  Halted (circuit breaker or error)
  2  Config error
USAGE
  exit "${1:-0}"
}

# =============================================================================
# Argument Parsing
# =============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --depth)
      DEPTH="$2"
      shift 2
      ;;
    --per-sprint)
      PER_SPRINT=true
      shift
      ;;
    --resume)
      RESUME=true
      shift
      ;;
    --from)
      FROM_PHASE="$2"
      shift 2
      ;;
    --help)
      usage 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage 2
      ;;
  esac
done

# =============================================================================
# Config Loading
# =============================================================================

load_bridge_config() {
  if command -v yq &>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
    local enabled
    enabled=$(yq '.run_bridge.enabled // false' "$CONFIG_FILE" 2>/dev/null)
    if [[ "$enabled" != "true" ]]; then
      echo "ERROR: run_bridge.enabled is not true in $CONFIG_FILE" >&2
      exit 2
    fi

    DEPTH=$(yq ".run_bridge.defaults.depth // $DEPTH" "$CONFIG_FILE" 2>/dev/null)
    PER_SPRINT=$(yq ".run_bridge.defaults.per_sprint // $PER_SPRINT" "$CONFIG_FILE" 2>/dev/null)
    FLATLINE_THRESHOLD=$(yq ".run_bridge.defaults.flatline_threshold // $FLATLINE_THRESHOLD" "$CONFIG_FILE" 2>/dev/null)
    CONSECUTIVE_FLATLINE=$(yq ".run_bridge.defaults.consecutive_flatline // $CONSECUTIVE_FLATLINE" "$CONFIG_FILE" 2>/dev/null)

    local per_iter_hours total_hours
    per_iter_hours=$(yq '.run_bridge.timeouts.per_iteration_hours // 4' "$CONFIG_FILE" 2>/dev/null)
    total_hours=$(yq '.run_bridge.timeouts.total_hours // 24' "$CONFIG_FILE" 2>/dev/null)
    PER_ITERATION_TIMEOUT=$((per_iter_hours * 3600))
    TOTAL_TIMEOUT=$((total_hours * 3600))
  fi
}

# =============================================================================
# Preflight
# =============================================================================

preflight() {
  echo "═══════════════════════════════════════════════════"
  echo "  BRIDGE ORCHESTRATOR — PREFLIGHT"
  echo "═══════════════════════════════════════════════════"

  # Check config
  load_bridge_config

  # Check beads health (non-blocking — warn if unavailable)
  if [[ -f "$SCRIPT_DIR/beads/beads-health.sh" ]]; then
    local beads_status
    beads_status=$("$SCRIPT_DIR/beads/beads-health.sh" --quick --json 2>/dev/null | jq -r '.status // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
    if [[ "$beads_status" != "HEALTHY" ]]; then
      echo "WARNING: Beads health: $beads_status (bridge continues without beads)"
    fi
  fi

  # Validate branch via ICE
  if [[ -f "$SCRIPT_DIR/run-mode-ice.sh" ]]; then
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    echo "Branch: $current_branch"

    # Check we're not on a protected branch
    if [[ "$current_branch" == "main" ]] || [[ "$current_branch" == "master" ]]; then
      echo "ERROR: Cannot run bridge on protected branch: $current_branch" >&2
      exit 2
    fi
  fi

  # Check required files
  if [[ ! -f "$PROJECT_ROOT/grimoires/loa/sprint.md" ]]; then
    echo "ERROR: Sprint plan not found at grimoires/loa/sprint.md" >&2
    exit 2
  fi

  echo "Depth: $DEPTH"
  echo "Per-sprint: $PER_SPRINT"
  echo "Flatline threshold: $FLATLINE_THRESHOLD"
  echo "Consecutive flatline: $CONSECUTIVE_FLATLINE"
  echo ""
  echo "Preflight PASSED"
}

# =============================================================================
# Resume Logic
# =============================================================================

handle_resume() {
  if [[ ! -f "$BRIDGE_STATE_FILE" ]]; then
    echo "ERROR: No bridge state file found for resume" >&2
    exit 1
  fi

  local state bridge_id
  state=$(jq -r '.state' "$BRIDGE_STATE_FILE")
  bridge_id=$(jq -r '.bridge_id' "$BRIDGE_STATE_FILE")

  echo "Resuming bridge: $bridge_id (state: $state)"

  case "$state" in
    HALTED)
      # Resume from HALTED — transition back to ITERATING
      update_bridge_state "ITERATING"
      local last_iteration
      last_iteration=$(jq '.iterations | length' "$BRIDGE_STATE_FILE")
      echo "Resuming from iteration $((last_iteration + 1))"
      return "$last_iteration"
      ;;
    ITERATING)
      # Already iterating — continue from current
      local last_iteration
      last_iteration=$(jq '.iterations | length' "$BRIDGE_STATE_FILE")
      echo "Continuing from iteration $last_iteration"
      return "$last_iteration"
      ;;
    *)
      echo "ERROR: Cannot resume from state: $state" >&2
      exit 1
      ;;
  esac
}

# =============================================================================
# Core Loop
# =============================================================================

bridge_main() {
  local start_iteration=0

  if [[ "$RESUME" == "true" ]]; then
    handle_resume
    start_iteration=$?
  else
    # Fresh start
    preflight

    local bridge_id
    bridge_id="bridge-$(date +%Y%m%d)-$(head -c 3 /dev/urandom | xxd -p)"
    local branch
    branch=$(git branch --show-current 2>/dev/null || echo "unknown")

    init_bridge_state "$bridge_id" "$DEPTH" "$PER_SPRINT" "$FLATLINE_THRESHOLD" "$branch"
    update_bridge_state "JACK_IN"

    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  JACK IN — Bridge ID: $bridge_id"
    echo "═══════════════════════════════════════════════════"

    update_bridge_state "ITERATING"
    start_iteration=0
  fi

  # Iteration loop
  local iteration=$((start_iteration + 1))
  local total_start_time=$SECONDS

  while [[ $iteration -le $DEPTH ]]; do
    local iter_start_time=$SECONDS

    echo ""
    echo "───────────────────────────────────────────────────"
    echo "  ITERATION $iteration / $DEPTH"
    echo "───────────────────────────────────────────────────"

    # Track iteration
    local source="existing"
    if [[ $iteration -gt 1 ]]; then
      source="findings"
    fi
    update_iteration "$iteration" "in_progress" "$source"

    # 2a: Sprint Plan
    if [[ $iteration -eq 1 ]] && [[ -z "$FROM_PHASE" || "$FROM_PHASE" == "sprint-plan" ]]; then
      echo "[PLAN] Using existing sprint plan"
    elif [[ $iteration -gt 1 ]]; then
      echo "[PLAN] Generating sprint plan from findings (iteration $iteration)"
      # The findings-to-sprint-plan generation is handled by the Claude agent
      # This script signals that it needs to happen
      echo "SIGNAL:GENERATE_SPRINT_FROM_FINDINGS:$iteration"
    fi

    # 2b: Execute Sprint Plan
    echo "[EXECUTE] Running sprint plan..."
    if [[ "$PER_SPRINT" == "true" ]]; then
      echo "SIGNAL:RUN_PER_SPRINT:$iteration"
    else
      echo "SIGNAL:RUN_SPRINT_PLAN:$iteration"
    fi

    # 2c: Bridgebuilder Review
    echo "[REVIEW] Invoking Bridgebuilder review..."
    echo "SIGNAL:BRIDGEBUILDER_REVIEW:$iteration"

    # 2d: Vision Capture
    echo "[VISION] Capturing VISION findings..."
    echo "SIGNAL:VISION_CAPTURE:$iteration"

    # 2e: GitHub Trail
    echo "[TRAIL] Posting to GitHub..."
    echo "SIGNAL:GITHUB_TRAIL:$iteration"

    # 2f: Flatline Detection
    echo "[FLATLINE] Checking flatline condition..."
    echo "SIGNAL:FLATLINE_CHECK:$iteration"

    # Mark iteration as completed
    update_iteration "$iteration" "completed"

    # Check flatline
    local flatlined
    flatlined=$(is_flatlined "$CONSECUTIVE_FLATLINE")
    if [[ "$flatlined" == "true" ]]; then
      echo ""
      echo "═══════════════════════════════════════════════════"
      echo "  FLATLINE DETECTED"
      echo "  Terminating after $iteration iterations"
      echo "═══════════════════════════════════════════════════"
      break
    fi

    # Check per-iteration timeout
    local iter_elapsed=$((SECONDS - iter_start_time))
    if [[ $iter_elapsed -gt $PER_ITERATION_TIMEOUT ]]; then
      echo "WARNING: Per-iteration timeout exceeded ($iter_elapsed s > $PER_ITERATION_TIMEOUT s)"
      update_bridge_state "HALTED"
      exit 1
    fi

    # Check total timeout
    local total_elapsed=$((SECONDS - total_start_time))
    if [[ $total_elapsed -gt $TOTAL_TIMEOUT ]]; then
      echo "WARNING: Total timeout exceeded ($total_elapsed s > $TOTAL_TIMEOUT s)"
      update_bridge_state "HALTED"
      exit 1
    fi

    iteration=$((iteration + 1))
  done

  # Finalization
  echo ""
  echo "═══════════════════════════════════════════════════"
  echo "  FINALIZING"
  echo "═══════════════════════════════════════════════════"

  update_bridge_state "FINALIZING"

  echo "[GT] Updating Grounded Truth..."
  echo "SIGNAL:GROUND_TRUTH_UPDATE"

  echo "[RTFM] Running documentation gate..."
  echo "SIGNAL:RTFM_PASS"

  echo "[PR] Updating final PR..."
  echo "SIGNAL:FINAL_PR_UPDATE"

  update_bridge_state "JACKED_OUT"

  echo ""
  echo "═══════════════════════════════════════════════════"
  echo "  JACKED OUT — Bridge complete"
  echo "═══════════════════════════════════════════════════"

  # Print summary
  local metrics
  metrics=$(jq '.metrics' "$BRIDGE_STATE_FILE")
  echo ""
  echo "Metrics:"
  echo "  Sprints executed: $(echo "$metrics" | jq '.total_sprints_executed')"
  echo "  Files changed: $(echo "$metrics" | jq '.total_files_changed')"
  echo "  Findings addressed: $(echo "$metrics" | jq '.total_findings_addressed')"
  echo "  Visions captured: $(echo "$metrics" | jq '.total_visions_captured')"
}

# =============================================================================
# Entry Point
# =============================================================================

bridge_main
