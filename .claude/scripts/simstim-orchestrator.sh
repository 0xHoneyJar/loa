#!/usr/bin/env bash
# =============================================================================
# simstim-orchestrator.sh - Orchestration support for Simstim workflow
# =============================================================================
# Version: 1.0.0
# Part of: Simstim HITL Accelerated Development Workflow
#
# Provides state management, preflight validation, and phase tracking
# for the /simstim command.
#
# Usage:
#   simstim-orchestrator.sh --preflight [--from <phase>] [--resume] [--abort] [--dry-run]
#   simstim-orchestrator.sh --update-phase <phase> <status>
#   simstim-orchestrator.sh --update-flatline-metrics <phase> <integrated> <disputed> <blockers>
#   simstim-orchestrator.sh --complete [--pr-url <url>]
#
# Exit codes:
#   0 - Success
#   1 - Validation error
#   2 - State conflict (existing state, need --resume or --abort)
#   3 - Missing prerequisite
#   4 - Flatline failure
#   5 - User abort
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
STATE_FILE="$PROJECT_ROOT/.run/simstim-state.json"
STATE_BACKUP="$PROJECT_ROOT/.run/simstim-state.json.bak"
LOCK_FILE="$PROJECT_ROOT/.run/simstim.lock"
TRAJECTORY_DIR="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"

# Phase definitions
PHASES=(preflight discovery flatline_prd architecture flatline_sdd planning flatline_sprint implementation)
PHASE_NAMES=(PREFLIGHT DISCOVERY "FLATLINE PRD" ARCHITECTURE "FLATLINE SDD" PLANNING "FLATLINE SPRINT" IMPLEMENTATION)

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[simstim] $*" >&2
}

error() {
    echo "ERROR: $*" >&2
}

warn() {
    echo "WARNING: $*" >&2
}

# Log to trajectory
log_trajectory() {
    local event_type="$1"
    local data="$2"

    (umask 077 && mkdir -p "$TRAJECTORY_DIR")
    local date_str
    date_str=$(date +%Y-%m-%d)
    local log_file="$TRAJECTORY_DIR/simstim-$date_str.jsonl"

    touch "$log_file"
    chmod 600 "$log_file"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg type "simstim" \
        --arg event "$event_type" \
        --arg timestamp "$timestamp" \
        --argjson data "$data" \
        '{type: $type, event: $event, timestamp: $timestamp, data: $data}' >> "$log_file"
}

# =============================================================================
# Configuration
# =============================================================================

read_config() {
    local path="$1"
    local default="$2"
    if [[ -f "$CONFIG_FILE" ]] && command -v yq &> /dev/null; then
        local value
        value=$(yq -r "$path // \"\"" "$CONFIG_FILE" 2>/dev/null)
        if [[ -n "$value" && "$value" != "null" ]]; then
            echo "$value"
            return
        fi
    fi
    echo "$default"
}

is_enabled() {
    local path="$1"
    local value
    value=$(read_config "$path" "false")
    [[ "$value" == "true" ]]
}

# =============================================================================
# Lock Management (Concurrent Execution Prevention)
# =============================================================================

acquire_lock() {
    mkdir -p "$(dirname "$LOCK_FILE")"

    # Check for stale lock
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            error "Another simstim session is running (PID: $lock_pid)"
            error "If this is incorrect, remove $LOCK_FILE manually"
            return 1
        fi
        # Stale lock, remove it
        rm -f "$LOCK_FILE"
    fi

    echo $$ > "$LOCK_FILE"
}

release_lock() {
    rm -f "$LOCK_FILE"
}

# =============================================================================
# State Management
# =============================================================================

generate_simstim_id() {
    local date_part
    date_part=$(date +%Y%m%d)
    local random_part
    random_part=$(head -c 4 /dev/urandom | xxd -p)
    echo "simstim-${date_part}-${random_part}"
}

create_initial_state() {
    local from_phase="${1:-}"

    mkdir -p "$(dirname "$STATE_FILE")"

    local simstim_id
    simstim_id=$(generate_simstim_id)

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Determine starting phase and skip prior phases
    local start_index=0
    if [[ -n "$from_phase" ]]; then
        case "$from_phase" in
            plan-and-analyze|discovery) start_index=1 ;;
            architect|architecture) start_index=3 ;;
            sprint-plan|planning) start_index=5 ;;
            run|implementation) start_index=7 ;;
        esac
    fi

    # Build phases object
    local phases_json='{'
    for i in "${!PHASES[@]}"; do
        local status="pending"
        if [[ $i -lt $start_index ]]; then
            status="skipped"
        fi
        [[ $i -gt 0 ]] && phases_json+=','
        phases_json+="\"${PHASES[$i]}\":{\"status\":\"$status\"}"
    done
    phases_json+='}'

    # Create state file
    jq -n \
        --arg schema_version "1" \
        --arg simstim_id "$simstim_id" \
        --arg state "RUNNING" \
        --arg phase "${PHASES[$start_index]}" \
        --arg started "$timestamp" \
        --arg last_activity "$timestamp" \
        --argjson phases "$phases_json" \
        --arg from "$from_phase" \
        '{
            schema_version: ($schema_version | tonumber),
            simstim_id: $simstim_id,
            state: $state,
            phase: $phase,
            timestamps: {
                started: $started,
                last_activity: $last_activity
            },
            phases: $phases,
            artifacts: {},
            flatline_metrics: {},
            blocker_overrides: [],
            options: {
                from: (if $from == "" then null else $from end),
                timeout_hours: 24
            }
        }' > "$STATE_FILE"

    chmod 600 "$STATE_FILE"

    # Log workflow started event
    log_trajectory "workflow_started" "$(jq -c '{simstim_id: .simstim_id, from_phase: .options.from}' "$STATE_FILE")"

    echo "$simstim_id"
}

backup_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cp "$STATE_FILE" "$STATE_BACKUP"
    fi
}

update_last_activity() {
    if [[ ! -f "$STATE_FILE" ]]; then
        return 1
    fi

    backup_state

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local tmp_file="${STATE_FILE}.tmp"
    jq --arg ts "$timestamp" '.timestamps.last_activity = $ts' "$STATE_FILE" > "$tmp_file"
    mv "$tmp_file" "$STATE_FILE"
}

# =============================================================================
# Artifact Drift Detection
# =============================================================================

check_artifact_drift() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{"drift": false, "artifacts": []}'
        return 0
    fi

    local drift_found=false
    local drifted_artifacts='[]'

    # Check each artifact
    for artifact in prd sdd sprint; do
        local stored
        stored=$(jq -r ".artifacts.${artifact}.checksum // \"\"" "$STATE_FILE")

        if [[ -n "$stored" && "$stored" != "null" ]]; then
            local path
            path=$(jq -r ".artifacts.${artifact}.path // \"\"" "$STATE_FILE")

            if [[ -f "$PROJECT_ROOT/$path" ]]; then
                local current
                current=$(sha256sum "$PROJECT_ROOT/$path" | cut -d' ' -f1)
                local stored_hash
                stored_hash=$(echo "$stored" | sed 's/sha256://')

                if [[ "$current" != "$stored_hash" ]]; then
                    drift_found=true
                    drifted_artifacts=$(echo "$drifted_artifacts" | jq --arg a "$artifact" --arg p "$path" '. + [{artifact: $a, path: $p}]')
                fi
            fi
        fi
    done

    jq -n --argjson drift "$drift_found" --argjson artifacts "$drifted_artifacts" \
        '{drift: $drift, artifacts: $artifacts}'
}

# =============================================================================
# Preflight Validation
# =============================================================================

preflight() {
    local from_phase=""
    local resume=false
    local abort=false
    local dry_run=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from) from_phase="$2"; shift 2 ;;
            --resume) resume=true; shift ;;
            --abort) abort=true; shift ;;
            --dry-run) dry_run=true; shift ;;
            *) shift ;;
        esac
    done

    # Handle abort first
    if [[ "$abort" == "true" ]]; then
        if [[ -f "$STATE_FILE" ]]; then
            log_trajectory "workflow_aborted" '{"reason": "user_request"}'
            rm -f "$STATE_FILE" "$STATE_BACKUP"
            release_lock
        fi
        echo '{"action": "aborted", "message": "State cleaned up"}'
        exit 0
    fi

    # Check configuration
    if ! is_enabled ".simstim.enabled"; then
        error "simstim.enabled is false in .loa.config.yaml"
        exit 1
    fi

    # Check for concurrent execution
    if ! acquire_lock; then
        exit 1
    fi

    # Check for existing state
    if [[ -f "$STATE_FILE" ]]; then
        local current_state
        current_state=$(jq -r '.state' "$STATE_FILE")

        if [[ "$resume" == "true" ]]; then
            # Validate resume
            local phase
            phase=$(jq -r '.phase' "$STATE_FILE")
            local drift
            drift=$(check_artifact_drift)

            log_trajectory "workflow_resumed" "$(jq -c --arg phase "$phase" '{from_phase: $phase}' <<< '{}')"

            jq -n \
                --arg action "resume" \
                --arg phase "$phase" \
                --argjson drift "$drift" \
                '{action: $action, phase: $phase, drift: $drift}'
            exit 0
        fi

        if [[ "$current_state" == "RUNNING" || "$current_state" == "INTERRUPTED" ]]; then
            # State conflict
            error "Existing state found (state: $current_state)"
            error "Use --resume to continue, or --abort to start fresh"
            exit 2
        fi
    fi

    # Validate --from prerequisites
    if [[ -n "$from_phase" ]]; then
        case "$from_phase" in
            architect|architecture)
                if [[ ! -f "$PROJECT_ROOT/grimoires/loa/prd.md" ]]; then
                    error "Cannot start from architect: PRD not found"
                    error "Create grimoires/loa/prd.md first or run without --from"
                    exit 3
                fi
                ;;
            sprint-plan|planning)
                if [[ ! -f "$PROJECT_ROOT/grimoires/loa/prd.md" ]]; then
                    error "Cannot start from sprint-plan: PRD not found"
                    exit 3
                fi
                if [[ ! -f "$PROJECT_ROOT/grimoires/loa/sdd.md" ]]; then
                    error "Cannot start from sprint-plan: SDD not found"
                    exit 3
                fi
                ;;
            run|implementation)
                if [[ ! -f "$PROJECT_ROOT/grimoires/loa/prd.md" ]]; then
                    error "Cannot start from run: PRD not found"
                    exit 3
                fi
                if [[ ! -f "$PROJECT_ROOT/grimoires/loa/sdd.md" ]]; then
                    error "Cannot start from run: SDD not found"
                    exit 3
                fi
                if [[ ! -f "$PROJECT_ROOT/grimoires/loa/sprint.md" ]]; then
                    error "Cannot start from run: Sprint plan not found"
                    exit 3
                fi
                ;;
        esac
    fi

    # Dry run - show planned phases
    if [[ "$dry_run" == "true" ]]; then
        local start_index=0
        if [[ -n "$from_phase" ]]; then
            case "$from_phase" in
                plan-and-analyze|discovery) start_index=1 ;;
                architect|architecture) start_index=3 ;;
                sprint-plan|planning) start_index=5 ;;
                run|implementation) start_index=7 ;;
            esac
        fi

        local phases_to_run='[]'
        for i in "${!PHASES[@]}"; do
            if [[ $i -ge $start_index ]]; then
                phases_to_run=$(echo "$phases_to_run" | jq --arg p "${PHASES[$i]}" --arg n "${PHASE_NAMES[$i]}" '. + [{id: $p, name: $n}]')
            fi
        done

        release_lock
        jq -n --argjson phases "$phases_to_run" '{action: "dry_run", phases: $phases}'
        exit 0
    fi

    # Create initial state
    local simstim_id
    simstim_id=$(create_initial_state "$from_phase")

    jq -n --arg id "$simstim_id" --arg phase "${PHASES[0]}" \
        '{action: "start", simstim_id: $id, starting_phase: $phase}'
}

# =============================================================================
# Phase Updates
# =============================================================================

update_phase() {
    local phase="$1"
    local status="$2"

    if [[ ! -f "$STATE_FILE" ]]; then
        error "No state file found"
        exit 1
    fi

    backup_state
    update_last_activity

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local tmp_file="${STATE_FILE}.tmp"

    if [[ "$status" == "in_progress" ]]; then
        jq --arg phase "$phase" --arg ts "$timestamp" \
            '.phase = $phase | .phases[$phase].status = "in_progress" | .phases[$phase].started_at = $ts' \
            "$STATE_FILE" > "$tmp_file"

        log_trajectory "phase_started" "$(jq -n --arg phase "$phase" '{phase: $phase}')"
    else
        jq --arg phase "$phase" --arg status "$status" --arg ts "$timestamp" \
            '.phases[$phase].status = $status | .phases[$phase].completed_at = $ts' \
            "$STATE_FILE" > "$tmp_file"

        if [[ "$status" == "completed" ]]; then
            log_trajectory "phase_completed" "$(jq -n --arg phase "$phase" '{phase: $phase}')"
        fi
    fi

    mv "$tmp_file" "$STATE_FILE"

    echo '{"updated": true}'
}

# =============================================================================
# Flatline Metrics
# =============================================================================

update_flatline_metrics() {
    local phase="$1"
    local integrated="$2"
    local disputed="$3"
    local blockers="$4"

    if [[ ! -f "$STATE_FILE" ]]; then
        error "No state file found"
        exit 1
    fi

    backup_state

    local tmp_file="${STATE_FILE}.tmp"
    jq --arg phase "$phase" \
        --argjson integrated "$integrated" \
        --argjson disputed "$disputed" \
        --argjson blockers "$blockers" \
        '.flatline_metrics[$phase] = {integrated: $integrated, disputed: $disputed, blockers: $blockers}' \
        "$STATE_FILE" > "$tmp_file"
    mv "$tmp_file" "$STATE_FILE"

    log_trajectory "flatline_completed" "$(jq -n \
        --arg phase "$phase" \
        --argjson integrated "$integrated" \
        --argjson disputed "$disputed" \
        --argjson blockers "$blockers" \
        '{phase: $phase, metrics: {integrated: $integrated, disputed: $disputed, blockers: $blockers}}')"

    echo '{"updated": true}'
}

# =============================================================================
# Completion
# =============================================================================

complete_workflow() {
    local pr_url=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pr-url) pr_url="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ ! -f "$STATE_FILE" ]]; then
        error "No state file found"
        exit 1
    fi

    backup_state

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Calculate totals
    local total_integrated
    total_integrated=$(jq '[.flatline_metrics[].integrated // 0] | add // 0' "$STATE_FILE")
    local total_disputed
    total_disputed=$(jq '[.flatline_metrics[].disputed // 0] | add // 0' "$STATE_FILE")
    local total_blockers
    total_blockers=$(jq '[.flatline_metrics[].blockers // 0] | add // 0' "$STATE_FILE")

    local tmp_file="${STATE_FILE}.tmp"
    jq --arg state "COMPLETED" --arg ts "$timestamp" --arg pr "$pr_url" \
        '.state = $state | .timestamps.completed = $ts | .pr_url = (if $pr == "" then null else $pr end)' \
        "$STATE_FILE" > "$tmp_file"
    mv "$tmp_file" "$STATE_FILE"

    log_trajectory "workflow_completed" "$(jq -c \
        --argjson integrated "$total_integrated" \
        --argjson disputed "$total_disputed" \
        --argjson blockers "$total_blockers" \
        '{total_integrated: $integrated, total_disputed: $disputed, total_blockers: $blockers}' <<< '{}')"

    release_lock

    jq -n \
        --argjson integrated "$total_integrated" \
        --argjson disputed "$total_disputed" \
        --argjson blockers "$total_blockers" \
        --arg pr "$pr_url" \
        '{
            status: "completed",
            flatline_summary: {
                total_integrated: $integrated,
                total_disputed: $disputed,
                total_blockers: $blockers
            },
            pr_url: (if $pr == "" then null else $pr end)
        }'
}

# =============================================================================
# Interrupt Handler
# =============================================================================

save_interrupt() {
    if [[ -f "$STATE_FILE" ]]; then
        backup_state

        local tmp_file="${STATE_FILE}.tmp"
        jq '.state = "INTERRUPTED"' "$STATE_FILE" > "$tmp_file"
        mv "$tmp_file" "$STATE_FILE"

        log_trajectory "workflow_interrupted" '{"reason": "signal"}'
    fi

    release_lock
    echo '{"interrupted": true}'
}

# Trap signals
trap save_interrupt SIGINT SIGTERM

# =============================================================================
# Main
# =============================================================================

main() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: simstim-orchestrator.sh --preflight|--update-phase|--update-flatline-metrics|--complete"
        exit 1
    fi

    local command="$1"
    shift

    case "$command" in
        --preflight)
            preflight "$@"
            ;;
        --update-phase)
            if [[ $# -lt 2 ]]; then
                error "Usage: --update-phase <phase> <status>"
                exit 1
            fi
            update_phase "$1" "$2"
            ;;
        --update-flatline-metrics)
            if [[ $# -lt 4 ]]; then
                error "Usage: --update-flatline-metrics <phase> <integrated> <disputed> <blockers>"
                exit 1
            fi
            update_flatline_metrics "$1" "$2" "$3" "$4"
            ;;
        --complete)
            complete_workflow "$@"
            ;;
        --save-interrupt)
            save_interrupt
            ;;
        --check-drift)
            check_artifact_drift
            ;;
        --cleanup)
            rm -f "$STATE_FILE" "$STATE_BACKUP" "$LOCK_FILE"
            echo '{"cleaned": true}'
            ;;
        *)
            error "Unknown command: $command"
            exit 1
            ;;
    esac
}

main "$@"
