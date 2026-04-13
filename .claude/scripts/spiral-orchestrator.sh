#!/usr/bin/env bash
# =============================================================================
# spiral-orchestrator.sh - /spiral meta-orchestrator (cycle-066)
# =============================================================================
# Version: 0.1.0 (MVP scaffolding)
# Part of: RFC-060 #483 autopoietic spiral
# Depends on: cycle-063 state coalescer, cycle-064 per-cycle workspace
#
# Usage:
#   spiral-orchestrator.sh --start [--max-cycles N] [--budget-cents N] [--dry-run]
#   spiral-orchestrator.sh --status [--json]
#   spiral-orchestrator.sh --halt [--reason TEXT]
#   spiral-orchestrator.sh --resume
#   spiral-orchestrator.sh --check-stop      Evaluate stopping conditions only
#
# State machine:
#   INIT -> RUNNING -> (COMPLETED | HALTED | FAILED)
#
# Phase within a cycle:
#   SEED -> SIMSTIM -> HARVEST -> EVALUATE
#
# Exit codes:
#   0 - Success
#   1 - Validation error
#   2 - Feature disabled in config
#   3 - State conflict (run in progress)
#   4 - Stopping condition triggered
#   5 - HITL halt requested
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

STATE_FILE="$PROJECT_ROOT/.run/spiral-state.json"
HALT_SENTINEL="$PROJECT_ROOT/.run/spiral-halt"
TRAJECTORY_DIR=$(get_trajectory_dir)
_GRIMOIRE_DIR=$(get_grimoire_dir)

# Hardcoded safety floors (RFC-060 AD-4) — cannot be overridden by config.
MAX_CYCLES_FLOOR=50
MAX_COST_CENTS_FLOOR=10000       # $100
MAX_WALL_CLOCK_SECONDS_FLOOR=86400  # 24h

log() {
    echo "[spiral] $*" >&2
}

error() {
    echo "ERROR: $*" >&2
}

# =============================================================================
# Config read helpers
# =============================================================================

read_config() {
    local key="$1"
    local default="$2"
    local config="$PROJECT_ROOT/.loa.config.yaml"
    [[ ! -f "$config" ]] && { echo "$default"; return 0; }
    local value
    value=$(yq eval ".$key // null" "$config" 2>/dev/null || echo "null")
    if [[ "$value" == "null" || -z "$value" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

is_enabled() {
    local enabled
    enabled=$(read_config "spiral.enabled" "false")
    [[ "$enabled" == "true" ]]
}

# =============================================================================
# Safety-floor clamping
# =============================================================================

clamp_to_floor() {
    local value="$1"
    local floor="$2"
    if [[ "$value" -gt "$floor" ]]; then
        log "Value $value exceeds safety floor $floor — clamping"
        echo "$floor"
    else
        echo "$value"
    fi
}

# =============================================================================
# State management
# =============================================================================

generate_spiral_id() {
    local date_part
    date_part=$(date -u +%Y%m%d)
    local rand_part
    rand_part=$(head -c 3 /dev/urandom | od -An -tx1 | tr -d ' \n')
    echo "spiral-${date_part}-${rand_part}"
}

init_state() {
    local max_cycles="$1"
    local budget_cents="$2"
    local wall_clock_seconds="$3"
    local flatline_min="$4"
    local flatline_consec="$5"

    mkdir -p "$(dirname "$STATE_FILE")"

    local spiral_id
    spiral_id=$(generate_spiral_id)
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg id "$spiral_id" \
        --arg ts "$timestamp" \
        --argjson max_cycles "$max_cycles" \
        --argjson budget_cents "$budget_cents" \
        --argjson wall_clock_seconds "$wall_clock_seconds" \
        --argjson flatline_min "$flatline_min" \
        --argjson flatline_consec "$flatline_consec" \
        '{
            schema_version: 1,
            spiral_id: $id,
            state: "RUNNING",
            phase: "SEED",
            cycle_index: 0,
            max_cycles: $max_cycles,
            cycles: [],
            harvest: {
                visions_captured: 0,
                lore_candidates_queued: 0,
                pending_bugs: 0
            },
            flatline_counter: 0,
            flatline: {
                min_new_findings_per_cycle: $flatline_min,
                consecutive_low_cycles_threshold: $flatline_consec
            },
            budget: {
                budget_cents: $budget_cents,
                cost_cents: 0,
                wall_clock_seconds: $wall_clock_seconds
            },
            stopping_condition: null,
            timestamps: {
                started: $ts,
                last_activity: $ts,
                completed_at: null
            }
        }' > "$STATE_FILE"

    chmod 600 "$STATE_FILE"
    echo "$spiral_id"
}

update_phase() {
    local new_phase="$1"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local tmp="${STATE_FILE}.tmp"
    jq --arg phase "$new_phase" --arg ts "$timestamp" \
        '.phase = $phase | .timestamps.last_activity = $ts' \
        "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

coalesce_spiral_terminal_state() {
    local target_state="$1"
    local stopping_condition="$2"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local tmp="${STATE_FILE}.tmp"
    jq --arg state "$target_state" \
        --arg condition "$stopping_condition" \
        --arg ts "$timestamp" \
        '.state = $state |
         .stopping_condition = $condition |
         .timestamps.completed_at = $ts |
         .timestamps.last_activity = $ts' \
        "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

# =============================================================================
# Stopping-condition predicates (RFC-060 AD-4)
# =============================================================================

check_cycle_budget() {
    local current_index max
    current_index=$(jq -r '.cycle_index' "$STATE_FILE")
    max=$(jq -r '.max_cycles' "$STATE_FILE")
    [[ "$current_index" -ge "$max" ]]
}

check_flatline() {
    local counter threshold
    counter=$(jq -r '.flatline_counter' "$STATE_FILE")
    threshold=$(jq -r '.flatline.consecutive_low_cycles_threshold' "$STATE_FILE")
    [[ "$counter" -ge "$threshold" ]]
}

check_cost_budget() {
    local cost_cents budget
    cost_cents=$(jq -r '.budget.cost_cents' "$STATE_FILE")
    budget=$(jq -r '.budget.budget_cents' "$STATE_FILE")
    [[ "$cost_cents" -ge "$budget" ]]
}

check_wall_clock() {
    local started budget now_epoch started_epoch elapsed
    started=$(jq -r '.timestamps.started' "$STATE_FILE")
    budget=$(jq -r '.budget.wall_clock_seconds' "$STATE_FILE")
    now_epoch=$(date -u +%s)
    started_epoch=$(date -u -d "$started" +%s 2>/dev/null \
        || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$started" +%s 2>/dev/null \
        || echo "$now_epoch")
    elapsed=$((now_epoch - started_epoch))
    [[ "$elapsed" -ge "$budget" ]]
}

check_hitl_halt() {
    [[ -f "$HALT_SENTINEL" ]]
}

# Returns the triggered stopping condition name, or empty string if none.
evaluate_stopping_conditions() {
    if check_hitl_halt; then
        echo "hitl_halt"
        return 0
    fi
    if check_cycle_budget; then
        echo "cycle_budget_exhausted"
        return 0
    fi
    if check_flatline; then
        echo "flatline_convergence"
        return 0
    fi
    if check_cost_budget; then
        echo "cost_budget_exhausted"
        return 0
    fi
    if check_wall_clock; then
        echo "wall_clock_exhausted"
        return 0
    fi
    echo ""
}

# =============================================================================
# Trajectory logging
# =============================================================================

log_trajectory() {
    local event="$1"
    local payload="$2"
    local date_stamp
    date_stamp=$(date -u +%Y-%m-%d)
    local log_file="$TRAJECTORY_DIR/spiral-${date_stamp}.jsonl"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    mkdir -p "$TRAJECTORY_DIR"
    jq -c -n \
        --arg ts "$timestamp" \
        --arg event "$event" \
        --argjson payload "$payload" \
        '{timestamp: $ts, event: $event} + $payload' \
        >> "$log_file"
}

# =============================================================================
# Commands
# =============================================================================

cmd_start() {
    # MVP scaffolding: initializes state, validates config, runs preflight,
    # and returns control. Full cycle dispatch lives in cycle-067+.

    if ! is_enabled; then
        error "/spiral is disabled. Set spiral.enabled: true in .loa.config.yaml"
        return 2
    fi

    if [[ -f "$STATE_FILE" ]]; then
        local current_state
        current_state=$(jq -r '.state // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
        if [[ "$current_state" == "RUNNING" ]]; then
            error "Spiral already RUNNING. Use --status, --halt, or --resume."
            return 3
        fi
    fi

    # Read config with defaults from RFC-060 schema
    local max_cycles budget_cents wall_clock_seconds flatline_min flatline_consec
    max_cycles=$(read_config "spiral.default_max_cycles" "3")
    budget_cents=$(read_config "spiral.budget_cents" "2000")
    wall_clock_seconds=$(read_config "spiral.wall_clock_seconds" "28800")
    flatline_min=$(read_config "spiral.flatline.min_new_findings_per_cycle" "3")
    flatline_consec=$(read_config "spiral.flatline.consecutive_low_cycles" "2")

    # Parse CLI overrides
    local dry_run=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-cycles) max_cycles="$2"; shift 2 ;;
            --budget-cents) budget_cents="$2"; shift 2 ;;
            --wall-clock-seconds) wall_clock_seconds="$2"; shift 2 ;;
            --dry-run) dry_run=true; shift ;;
            *) error "Unknown --start option: $1"; return 1 ;;
        esac
    done

    # Apply safety floors (AD-4)
    max_cycles=$(clamp_to_floor "$max_cycles" "$MAX_CYCLES_FLOOR")
    budget_cents=$(clamp_to_floor "$budget_cents" "$MAX_COST_CENTS_FLOOR")
    wall_clock_seconds=$(clamp_to_floor "$wall_clock_seconds" "$MAX_WALL_CLOCK_SECONDS_FLOOR")

    if [[ "$dry_run" == "true" ]]; then
        jq -n \
            --argjson max_cycles "$max_cycles" \
            --argjson budget_cents "$budget_cents" \
            --argjson wall_clock_seconds "$wall_clock_seconds" \
            --argjson flatline_min "$flatline_min" \
            --argjson flatline_consec "$flatline_consec" \
            '{
                dry_run: true,
                computed: {
                    max_cycles: $max_cycles,
                    budget_cents: $budget_cents,
                    wall_clock_seconds: $wall_clock_seconds,
                    flatline_min: $flatline_min,
                    flatline_consecutive: $flatline_consec
                },
                safety_floors: {
                    max_cycles: 50,
                    max_cost_cents: 10000,
                    max_wall_clock_seconds: 86400
                }
            }'
        return 0
    fi

    local spiral_id
    spiral_id=$(init_state \
        "$max_cycles" "$budget_cents" "$wall_clock_seconds" \
        "$flatline_min" "$flatline_consec")

    log_trajectory "spiral_started" "$(jq -n --arg id "$spiral_id" '{spiral_id: $id}')"

    jq -n \
        --arg id "$spiral_id" \
        --argjson max_cycles "$max_cycles" \
        '{started: true, spiral_id: $id, max_cycles: $max_cycles, note: "MVP scaffolding — cycle dispatch lands in cycle-067+"}'
}

cmd_status() {
    local json_mode=false
    [[ "${1:-}" == "--json" ]] && json_mode=true

    if [[ ! -f "$STATE_FILE" ]]; then
        if [[ "$json_mode" == "true" ]]; then
            echo '{"state": "NO_SPIRAL"}'
        else
            echo "No active spiral. Use --start to begin."
        fi
        return 0
    fi

    if [[ "$json_mode" == "true" ]]; then
        cat "$STATE_FILE"
    else
        local state phase cycle_index max_cycles spiral_id
        state=$(jq -r '.state' "$STATE_FILE")
        phase=$(jq -r '.phase' "$STATE_FILE")
        cycle_index=$(jq -r '.cycle_index' "$STATE_FILE")
        max_cycles=$(jq -r '.max_cycles' "$STATE_FILE")
        spiral_id=$(jq -r '.spiral_id' "$STATE_FILE")
        cat <<EOF
Spiral: $spiral_id
State:  $state
Phase:  $phase
Cycle:  $cycle_index / $max_cycles
EOF
    fi
}

cmd_halt() {
    local reason="operator_halt"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reason) reason="$2"; shift 2 ;;
            *) error "Unknown --halt option: $1"; return 1 ;;
        esac
    done

    # Create the halt sentinel — next evaluate cycle will detect and terminate
    mkdir -p "$(dirname "$HALT_SENTINEL")"
    echo "$reason" > "$HALT_SENTINEL"

    # If a state file exists, coalesce to HALTED immediately
    if [[ -f "$STATE_FILE" ]]; then
        coalesce_spiral_terminal_state "HALTED" "$reason"
        log_trajectory "spiral_halted" "$(jq -n --arg reason "$reason" '{reason: $reason}')"
    fi

    jq -n --arg reason "$reason" '{halted: true, reason: $reason}'
}

cmd_resume() {
    if [[ ! -f "$STATE_FILE" ]]; then
        error "No spiral state to resume. Use --start."
        return 1
    fi

    local current_state
    current_state=$(jq -r '.state' "$STATE_FILE")

    if [[ "$current_state" == "RUNNING" ]]; then
        error "Spiral is already RUNNING. No resume needed."
        return 3
    fi

    if [[ "$current_state" != "HALTED" ]]; then
        error "Cannot resume from state: $current_state (only HALTED resumable)"
        return 1
    fi

    # Clear halt sentinel
    rm -f "$HALT_SENTINEL"

    # Transition back to RUNNING
    local tmp="${STATE_FILE}.tmp"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg ts "$timestamp" \
        '.state = "RUNNING" |
         .stopping_condition = null |
         .timestamps.completed_at = null |
         .timestamps.last_activity = $ts' \
        "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"

    log_trajectory "spiral_resumed" "{}"

    jq -n '{resumed: true}'
}

cmd_check_stop() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{"stop": false, "reason": "no_state"}'
        return 0
    fi

    local condition
    condition=$(evaluate_stopping_conditions)

    if [[ -n "$condition" ]]; then
        jq -n --arg c "$condition" '{stop: true, condition: $c}'
        return 0
    fi
    echo '{"stop": false}'
}

# =============================================================================
# CLI
# =============================================================================

usage() {
    sed -n '/^# Usage:/,/^# State machine/p' "${BASH_SOURCE[0]}" \
        | sed -e '/^# State machine/d' -e 's/^# \{0,1\}//'
}

main() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    case "$cmd" in
        --start) cmd_start "$@" ;;
        --status) cmd_status "$@" ;;
        --halt) cmd_halt "$@" ;;
        --resume) cmd_resume ;;
        --check-stop) cmd_check_stop ;;
        -h|--help|help|"")
            usage
            [[ -z "$cmd" ]] && exit 1 || exit 0
            ;;
        *)
            error "Unknown command: $cmd"
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
