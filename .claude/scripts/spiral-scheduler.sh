#!/usr/bin/env bash
# =============================================================================
# spiral-scheduler.sh — Off-Hours Scheduling Wrapper for /spiral
# =============================================================================
# Version: 1.0.0
# Part of: Spiral Cost Optimization (cycle-072)
#
# Entry point for scheduled (cron/trigger) spiral execution. Checks for
# an existing HALTED spiral to resume, or starts a new one from backlog.
# Designed to be invoked by CronCreate or RemoteTrigger during off-hours
# token allowance windows.
#
# Usage:
#   spiral-scheduler.sh [--profile standard] [--max-cycles 3]
#
# Scheduling (inside Claude Code):
#   CronCreate: schedule "0 2 * * *", task "spiral-scheduler.sh"
#   /schedule:  /schedule create --name spiral-nightly --cron "0 2 * * *"
#
# Exit codes:
#   0   — Completed (spiral finished or halted at window end)
#   1   — Error (config, state, or dispatch failure)
#   2   — Scheduling disabled in config
#   3   — Already running (PID guard)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh" 2>/dev/null || true

STATE_FILE="${PROJECT_ROOT:-.}/.run/spiral-state.json"
CONFIG="${PROJECT_ROOT:-.}/.loa.config.yaml"
LOCK_FILE="${PROJECT_ROOT:-.}/.run/spiral-scheduler.lock"

log() { echo "[scheduler] $(date -u +%H:%M:%SZ) $*" >&2; }
error() { echo "ERROR: $*" >&2; }

# =============================================================================
# Config
# =============================================================================

_read_config() {
    local key="$1" default="$2"
    [[ ! -f "$CONFIG" ]] && { echo "$default"; return 0; }
    local value
    value=$(yq eval ".$key // null" "$CONFIG" 2>/dev/null || echo "null")
    [[ "$value" == "null" || -z "$value" ]] && { echo "$default"; return 0; }
    echo "$value"
}

# =============================================================================
# Arguments
# =============================================================================

PROFILE=$(_read_config "spiral.harness.pipeline_profile" "standard")
MAX_CYCLES=$(_read_config "spiral.scheduling.max_cycles_per_window" "3")

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) PROFILE="$2"; shift 2 ;;
        --max-cycles) MAX_CYCLES="$2"; shift 2 ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
done

# =============================================================================
# Guards
# =============================================================================

# Check scheduling is enabled
scheduling_enabled=$(_read_config "spiral.scheduling.enabled" "false")
if [[ "$scheduling_enabled" != "true" ]]; then
    log "Scheduling disabled (spiral.scheduling.enabled != true)"
    exit 2
fi

# Check spiral is enabled
spiral_enabled=$(_read_config "spiral.enabled" "false")
if [[ "$spiral_enabled" != "true" ]]; then
    log "Spiral disabled (spiral.enabled != true)"
    exit 2
fi

# PID guard — prevent double execution
if [[ -f "$LOCK_FILE" ]]; then
    existing_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
        log "Already running (PID $existing_pid)"
        exit 3
    fi
    log "Stale lock file (PID $existing_pid not running), cleaning up"
    rm -f "$LOCK_FILE"
fi

# Write PID lock
echo "$$" > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# =============================================================================
# Window Check
# =============================================================================

# Verify we're within a configured scheduling window
_in_window() {
    local start_utc end_utc
    start_utc=$(_read_config "spiral.scheduling.windows[0].start_utc" "")
    end_utc=$(_read_config "spiral.scheduling.windows[0].end_utc" "")

    [[ -z "$start_utc" || -z "$end_utc" ]] && return 0  # No window = always OK

    local today now_epoch start_epoch end_epoch
    today=$(date -u +%Y-%m-%d)
    now_epoch=$(date -u +%s)
    start_epoch=$(date -u -d "${today}T${start_utc}:00Z" +%s 2>/dev/null || echo "0")
    end_epoch=$(date -u -d "${today}T${end_utc}:00Z" +%s 2>/dev/null || echo "0")

    [[ "$start_epoch" -eq 0 || "$end_epoch" -eq 0 ]] && return 0  # Parse fail = allow

    [[ "$now_epoch" -ge "$start_epoch" && "$now_epoch" -lt "$end_epoch" ]]
}

if ! _in_window; then
    log "Outside scheduling window, exiting"
    exit 0
fi

log "Scheduling window active. Profile=$PROFILE MaxCycles=$MAX_CYCLES"

# =============================================================================
# Dispatch: Resume or Start
# =============================================================================

if [[ -f "$STATE_FILE" ]]; then
    state=$(jq -r '.state' "$STATE_FILE" 2>/dev/null || echo "unknown")
    case "$state" in
        HALTED)
            log "Found HALTED spiral, resuming"
            "$SCRIPT_DIR/spiral-orchestrator.sh" --resume
            exit $?
            ;;
        RUNNING)
            log "Spiral already RUNNING (stale state?), skipping"
            exit 3
            ;;
        COMPLETED|FAILED)
            log "Previous spiral $state, starting fresh"
            ;;
        *)
            log "Unknown state '$state', starting fresh"
            ;;
    esac
fi

# Start a new spiral
log "Starting new spiral: profile=$PROFILE max-cycles=$MAX_CYCLES"
"$SCRIPT_DIR/spiral-orchestrator.sh" \
    --start \
    --max-cycles "$MAX_CYCLES" \
    --budget-cents "$(_read_config "spiral.max_total_budget_usd" "50")00"

exit $?
