#!/usr/bin/env bash
# =============================================================================
# spiral-scheduler.sh — Off-Hours Scheduling Wrapper for /spiral
# =============================================================================
# Version: 1.0.0
# Part of: Spiral Cost Optimization (cycle-072)
#
# Entry point for scheduled (cron/trigger) spiral execution. Checks for
# an existing HALTED spiral to resume, or starts a new one from backlog.
# Uses flock-based locking with stale lock recovery.
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
#   3   — Already running (lock contention)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh" 2>/dev/null || true

STATE_FILE="${STATE_FILE:-${PROJECT_ROOT:-.}/.run/spiral-state.json}"
CONFIG="${CONFIG:-${PROJECT_ROOT:-.}/.loa.config.yaml}"
LOCK_FILE="${LOCK_FILE:-${PROJECT_ROOT:-.}/.run/spiral-scheduler.lock}"
LOCK_PID_FILE="${LOCK_FILE}.pid"
LOCK_TIMEOUT=60
STALE_LOCK_AGE_SEC=300  # 5 minutes

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

PROFILE=""
MAX_CYCLES=""

_parse_scheduler_args() {
    PROFILE=$(_read_config "spiral.harness.pipeline_profile" "standard")
    MAX_CYCLES=$(_read_config "spiral.scheduling.max_cycles_per_window" "3")

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile) PROFILE="$2"; shift 2 ;;
            --max-cycles) MAX_CYCLES="$2"; shift 2 ;;
            *) error "Unknown option: $1"; return 1 ;;
        esac
    done
}

_check_guards() {
    local scheduling_enabled
    scheduling_enabled=$(_read_config "spiral.scheduling.enabled" "false")
    if [[ "$scheduling_enabled" != "true" ]]; then
        log "Scheduling disabled (spiral.scheduling.enabled != true)"
        return 2
    fi

    local spiral_enabled
    spiral_enabled=$(_read_config "spiral.enabled" "false")
    if [[ "$spiral_enabled" != "true" ]]; then
        log "Spiral disabled (spiral.enabled != true)"
        return 2
    fi
    return 0
}

# =============================================================================
# flock-based Locking (with stale recovery)
# =============================================================================

_acquire_lock() {
    exec 200>"$LOCK_FILE"
    if ! flock -w "$LOCK_TIMEOUT" 200; then
        # Check if lock holder is alive and lock is not stale
        if [[ -f "$LOCK_PID_FILE" ]]; then
            local holder_pid holder_ts now_epoch lock_age
            holder_pid=$(head -1 "$LOCK_PID_FILE" 2>/dev/null || echo "")
            holder_ts=$(tail -1 "$LOCK_PID_FILE" 2>/dev/null || echo "0")
            now_epoch=$(date -u +%s)
            lock_age=$((now_epoch - ${holder_ts:-0}))

            if [[ -n "$holder_pid" ]] && ! kill -0 "$holder_pid" 2>/dev/null && \
               [[ "$lock_age" -ge "$STALE_LOCK_AGE_SEC" ]]; then
                log "Stale lock from dead PID $holder_pid (age: ${lock_age}s), reclaiming"
                rm -f "$LOCK_PID_FILE"
                flock -w 5 200 || { error "Cannot reclaim lock"; exit 3; }
            else
                log "Lock held by PID ${holder_pid:-unknown} (age: ${lock_age}s), exiting"
                exit 3
            fi
        else
            log "Lock contention (no PID file), exiting"
            exit 3
        fi
    fi

    # Write PID + hostname + timestamp fingerprint
    {
        echo "$$"
        echo "$(hostname 2>/dev/null || echo 'unknown')"
        echo "$(date -u +%s)"
    } > "$LOCK_PID_FILE"

    trap '_release_lock' EXIT
}

_release_lock() {
    rm -f "$LOCK_PID_FILE"
    exec 200>&- 2>/dev/null || true
}

# =============================================================================
# Window Check
# =============================================================================

_in_window() {
    local strategy
    strategy=$(_read_config "spiral.scheduling.strategy" "fill")
    [[ "$strategy" == "continuous" ]] && return 0

    local start_utc end_utc
    start_utc=$(_read_config "spiral.scheduling.windows[0].start_utc" "")
    end_utc=$(_read_config "spiral.scheduling.windows[0].end_utc" "")

    [[ -z "$start_utc" || -z "$end_utc" ]] && return 0

    local today now_epoch start_epoch end_epoch
    today=$(date -u +%Y-%m-%d)
    now_epoch=$(date -u +%s)
    start_epoch=$(date -u -d "${today}T${start_utc}:00Z" +%s 2>/dev/null \
        || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "${today}T${start_utc}:00Z" +%s 2>/dev/null \
        || echo "0")
    end_epoch=$(date -u -d "${today}T${end_utc}:00Z" +%s 2>/dev/null \
        || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "${today}T${end_utc}:00Z" +%s 2>/dev/null \
        || echo "0")

    [[ "$start_epoch" -eq 0 || "$end_epoch" -eq 0 ]] && return 0

    [[ "$now_epoch" -ge "$start_epoch" && "$now_epoch" -lt "$end_epoch" ]]
}

# =============================================================================
# Trajectory Logging
# =============================================================================

_log_event() {
    local event="$1" detail="${2:-}"
    local trajectory_dir="${PROJECT_ROOT:-.}/grimoires/loa/a2a/trajectory"
    mkdir -p "$trajectory_dir"
    local date_stamp
    date_stamp=$(date -u +%Y-%m-%d)
    jq -n -c --arg event "$event" --arg detail "$detail" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{event: $event, detail: $detail, ts: $ts, pid: '$$'}' \
        >> "$trajectory_dir/scheduler-${date_stamp}.jsonl"
}

# =============================================================================
# Main
# =============================================================================

_scheduler_main() {

_parse_scheduler_args "$@" || exit $?
_check_guards || exit $?
_acquire_lock

if ! _in_window; then
    log "Outside scheduling window, exiting"
    _log_event "scheduler_outside_window"
    exit 0
fi

log "Scheduling window active. Profile=$PROFILE MaxCycles=$MAX_CYCLES"
_log_event "scheduler_started" "profile=$PROFILE max_cycles=$MAX_CYCLES"

# Dispatch: Resume or Start
if [[ -f "$STATE_FILE" ]]; then
    state=$(jq -r '.state' "$STATE_FILE" 2>/dev/null || echo "unknown")
    case "$state" in
        HALTED)
            log "Found HALTED spiral, resuming"
            _log_event "scheduler_resumed" "from=HALTED"
            "$SCRIPT_DIR/spiral-orchestrator.sh" --resume
            exit $?
            ;;
        RUNNING)
            log "Spiral already RUNNING (stale state?), skipping"
            _log_event "scheduler_skipped" "reason=already_running"
            exit 3
            ;;
        COMPLETED|FAILED)
            log "Previous spiral $state, starting fresh"
            _log_event "scheduler_fresh_start" "previous_state=$state"
            ;;
        *)
            log "Unknown state '$state', starting fresh"
            _log_event "scheduler_fresh_start" "previous_state=$state"
            ;;
    esac
fi

log "Starting new spiral: profile=$PROFILE max-cycles=$MAX_CYCLES"
"$SCRIPT_DIR/spiral-orchestrator.sh" \
    --start \
    --max-cycles "$MAX_CYCLES" \
    --budget-cents "$(_read_config "spiral.max_total_budget_usd" "50")00"

}  # end _scheduler_main

# Main guard: allow sourcing for tests without executing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _scheduler_main "$@"
    exit $?
fi
