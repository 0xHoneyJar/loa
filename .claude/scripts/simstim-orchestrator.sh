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
#   simstim-orchestrator.sh --set-expected-plan-id      # Store plan_id before /run sprint-plan
#   simstim-orchestrator.sh --sync-run-mode             # Sync run-mode completion state
#   simstim-orchestrator.sh --force-phase <phase> --yes # Force phase transition (escape hatch)
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
source "$SCRIPT_DIR/bootstrap.sh"

STATE_FILE="$PROJECT_ROOT/.run/simstim-state.json"
STATE_BACKUP="$PROJECT_ROOT/.run/simstim-state.json.bak"
LOCK_FILE="$PROJECT_ROOT/.run/simstim.lock"
TRAJECTORY_DIR=$(get_trajectory_dir)
_GRIMOIRE_DIR=$(get_grimoire_dir)

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
# Workspace Cleanup Integration (SDD Section 4.1)
# =============================================================================

run_workspace_cleanup() {
    local dry_run="${1:-false}"
    local yes_flag="${2:-false}"

    local cleanup_script="$SCRIPT_DIR/workspace-cleanup.sh"

    # Check if cleanup is enabled
    if ! is_enabled ".workspace_cleanup.enabled"; then
        log "Workspace cleanup disabled in config"
        return 0
    fi

    # Check if script exists
    if [[ ! -x "$cleanup_script" ]]; then
        warn "workspace-cleanup.sh not found or not executable"
        return 0
    fi

    # Build cleanup arguments
    local cleanup_args=()
    cleanup_args+=("--grimoire" "$_GRIMOIRE_DIR")

    if [[ "$dry_run" == "true" ]]; then
        cleanup_args+=("--dry-run")
    elif [[ "$yes_flag" == "true" ]]; then
        cleanup_args+=("--yes")
    fi

    log "Running workspace cleanup..."

    # Execute cleanup
    local cleanup_result
    if cleanup_result=$("$cleanup_script" "${cleanup_args[@]}" 2>&1); then
        log "Workspace cleanup completed"
        log_trajectory "workspace_cleanup" '{"status": "success"}'
        return 0
    else
        local exit_code=$?
        case $exit_code in
            2)
                # User declined - non-fatal
                log "User declined workspace cleanup"
                log_trajectory "workspace_cleanup" '{"status": "declined"}'
                return 0
                ;;
            3)
                # Security validation failure - fatal
                error "Workspace cleanup security validation failed"
                log_trajectory "workspace_cleanup" '{"status": "security_error"}'
                return 1
                ;;
            *)
                # Other error - fatal
                error "Workspace cleanup failed (exit $exit_code)"
                error "$cleanup_result"
                log_trajectory "workspace_cleanup" '{"status": "error", "exit_code": '"$exit_code"'}'
                return 1
                ;;
        esac
    fi
}

# =============================================================================
# Lock Management (Concurrent Execution Prevention)
# =============================================================================
# SIMSTIM-M-3 FIX: Use atomic mkdir for lock acquisition to prevent race conditions

LOCK_DIR="${LOCK_FILE}.d"

acquire_lock() {
    mkdir -p "$(dirname "$LOCK_FILE")"

    # Atomic lock acquisition using mkdir (atomic on POSIX systems)
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        # Successfully acquired lock, record PID
        echo $$ > "$LOCK_FILE"
        return 0
    fi

    # mkdir failed - check if it's our own stale lock or another process
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")

        # Check if the process is still running
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            error "Another simstim session is running (PID: $lock_pid)"
            error "If this is incorrect, run: /simstim --abort"
            return 1
        fi

        # Stale lock from dead process - clean up and retry once
        log "Cleaning up stale lock from PID $lock_pid"
        rm -f "$LOCK_FILE"
        rmdir "$LOCK_DIR" 2>/dev/null || true

        # Retry atomic acquisition
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            echo $$ > "$LOCK_FILE"
            return 0
        fi
    fi

    error "Failed to acquire lock (race condition or permission issue)"
    return 1
}

release_lock() {
    rm -f "$LOCK_FILE"
    rmdir "$LOCK_DIR" 2>/dev/null || true
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
    # SIMSTIM-M-1 FIX: Add default case to reject unknown phase values
    local start_index=0
    if [[ -n "$from_phase" ]]; then
        case "$from_phase" in
            plan-and-analyze|discovery) start_index=1 ;;
            architect|architecture) start_index=3 ;;
            sprint-plan|planning) start_index=5 ;;
            run|implementation) start_index=7 ;;
            *)
                error "Unknown phase: $from_phase"
                error "Valid phases: plan-and-analyze, architect, sprint-plan, run"
                exit 3
                ;;
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

# =============================================================================
# Atomic Write Pattern (Issue #169 - State Sync Fix)
# =============================================================================
# Uses existing mkdir-based locking + temp file rename for atomicity.
# Prevents:
# 1. Interrupted writes (atomic rename)
# 2. Concurrent writers (mkdir lock)
# 3. Read-modify-write races (hold lock during entire operation)

# Atomic write: temp file + rename (no content written to target directly)
atomic_write() {
    local target="$1"
    local content="$2"
    local temp="${target}.tmp.$$"

    # Write to temp file
    echo "$content" > "$temp"

    # Sync to disk (best-effort, not critical)
    sync "$temp" 2>/dev/null || true

    # Atomic rename (POSIX guarantees atomicity on local filesystems)
    mv "$temp" "$target"
}

# Wrapper for jq operations with atomic write
# NOTE: Caller should hold session lock (LOCK_DIR) for concurrent session safety
# This function provides atomic file operations, not session-level locking
atomic_jq_update() {
    local state_file="$1"
    shift

    if [[ ! -f "$state_file" ]]; then
        error "State file not found: $state_file"
        return 1
    fi

    local content
    content=$(jq "$@" "$state_file")
    atomic_write "$state_file" "$content"
}

# =============================================================================
# Sync Attempt Tracking (Issue #169 - State Sync Fix)
# =============================================================================

MAX_SYNC_ATTEMPTS=3

increment_sync_attempts() {
    if [[ ! -f "$STATE_FILE" ]]; then
        return
    fi

    local current
    current=$(jq -r '.sync_attempts // 0' "$STATE_FILE")
    local new=$((current + 1))

    atomic_jq_update "$STATE_FILE" --argjson attempts "$new" '.sync_attempts = $attempts'

    if [[ $new -ge $MAX_SYNC_ATTEMPTS ]]; then
        warn "Sync failed $new times. Use --force-phase to bypass."
    fi
}

reset_sync_attempts() {
    if [[ ! -f "$STATE_FILE" ]]; then
        return
    fi

    atomic_jq_update "$STATE_FILE" '.sync_attempts = 0'
}

# =============================================================================
# Run-Mode State Sync (Issue #169 - State Sync Fix)
# =============================================================================

RUN_MODE_STATE="$PROJECT_ROOT/.run/sprint-plan-state.json"

set_expected_plan_id() {
    if [[ ! -f "$STATE_FILE" ]]; then
        error "No state file found"
        exit 1
    fi

    backup_state

    # Generate expected plan_id from simstim_id
    # Format: simstim-YYYYMMDD-hash → plan-YYYYMMDD-hash
    local simstim_id
    simstim_id=$(jq -r '.simstim_id // ""' "$STATE_FILE")

    if [[ -z "$simstim_id" || "$simstim_id" == "null" ]]; then
        error "No simstim_id in state file"
        exit 1
    fi

    # Extract date and hash portions
    local expected_plan_id="plan-${simstim_id#simstim-}"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    atomic_jq_update "$STATE_FILE" \
        --arg plan_id "$expected_plan_id" \
        --arg ts "$timestamp" \
        '.expected_plan_id = $plan_id | .implementation_started_at = $ts | .sync_attempts = 0'

    jq -n --arg plan_id "$expected_plan_id" --arg ts "$timestamp" \
        '{expected_plan_id: $plan_id, implementation_started_at: $ts}'
}

sync_run_mode() {
    # Check simstim state file exists
    if [[ ! -f "$STATE_FILE" ]]; then
        error "No simstim state file found"
        exit 1
    fi

    # Check run-mode state exists
    if [[ ! -f "$RUN_MODE_STATE" ]]; then
        echo '{"synced": false, "reason": "no_run_mode_state"}'
        return 0
    fi

    # Validate JSON
    if ! jq empty "$RUN_MODE_STATE" 2>/dev/null; then
        increment_sync_attempts
        echo '{"synced": false, "reason": "invalid_json"}'
        return 0
    fi

    # Extract run-mode state
    local run_mode_state
    run_mode_state=$(jq -r '.state // "unknown"' "$RUN_MODE_STATE")

    # Don't sync if still running
    if [[ "$run_mode_state" == "RUNNING" ]]; then
        echo '{"synced": false, "reason": "still_running"}'
        return 0
    fi

    # =========================================================================
    # Validation 1: Plan ID correlation
    # =========================================================================
    local run_mode_plan_id
    run_mode_plan_id=$(jq -r '.plan_id // ""' "$RUN_MODE_STATE")

    local expected_plan_id
    expected_plan_id=$(jq -r '.expected_plan_id // ""' "$STATE_FILE")

    if [[ -n "$expected_plan_id" && -n "$run_mode_plan_id" ]]; then
        if [[ "$expected_plan_id" != "$run_mode_plan_id" ]]; then
            increment_sync_attempts
            jq -n \
                --arg expected "$expected_plan_id" \
                --arg found "$run_mode_plan_id" \
                '{synced: false, reason: "plan_id_mismatch", expected: $expected, found: $found}'
            return 0
        fi
    fi

    # =========================================================================
    # Validation 2: Timestamp staleness check
    # =========================================================================
    local impl_started_at
    impl_started_at=$(jq -r '.implementation_started_at // ""' "$STATE_FILE")

    local run_mode_last_activity
    run_mode_last_activity=$(jq -r '.timestamps.last_activity // .timestamps.started // ""' "$RUN_MODE_STATE")

    if [[ -n "$impl_started_at" && -n "$run_mode_last_activity" ]]; then
        # Convert to epoch for comparison (try GNU date first, then BSD date)
        local impl_epoch run_epoch
        impl_epoch=$(date -d "$impl_started_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$impl_started_at" +%s 2>/dev/null || echo "0")
        run_epoch=$(date -d "$run_mode_last_activity" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$run_mode_last_activity" +%s 2>/dev/null || echo "0")

        if [[ "$run_epoch" -lt "$impl_epoch" ]]; then
            increment_sync_attempts
            jq -n \
                --arg impl_ts "$impl_started_at" \
                --arg run_ts "$run_mode_last_activity" \
                '{synced: false, reason: "stale_run_mode_state", implementation_started: $impl_ts, run_mode_activity: $run_ts}'
            return 0
        fi
    fi

    # =========================================================================
    # Validation passed - proceed with sync
    # =========================================================================
    local pr_url
    pr_url=$(jq -r '.pr_url // ""' "$RUN_MODE_STATE")

    # Map run-mode state to simstim state
    local impl_status simstim_state
    case "$run_mode_state" in
        JACKED_OUT)
            impl_status="completed"
            simstim_state="COMPLETED"
            ;;
        READY_FOR_HITL)
            impl_status="completed"
            simstim_state="AWAITING_HITL"
            ;;
        HALTED)
            impl_status="incomplete"
            simstim_state="HALTED"
            ;;
        *)
            increment_sync_attempts
            jq -n --arg state "$run_mode_state" \
                '{synced: false, reason: "unknown_state", state: $state}'
            return 0
            ;;
    esac

    backup_state

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    atomic_jq_update "$STATE_FILE" \
        --arg state "$simstim_state" \
        --arg impl_status "$impl_status" \
        --arg pr_url "$pr_url" \
        --arg ts "$timestamp" \
        '.state = $state |
         .phases.implementation.status = $impl_status |
         .phases.implementation.synced_at = $ts |
         .pr_url = (if $pr_url == "" then null else $pr_url end) |
         .sync_attempts = 0'

    log_trajectory "run_mode_synced" "$(jq -n \
        --arg run_mode_state "$run_mode_state" \
        --arg simstim_state "$simstim_state" \
        --arg impl_status "$impl_status" \
        '{run_mode_state: $run_mode_state, simstim_state: $simstim_state, implementation_status: $impl_status}')"

    jq -n \
        --arg run_mode_state "$run_mode_state" \
        --arg impl_status "$impl_status" \
        --arg pr_url "$pr_url" \
        '{synced: true, run_mode_state: $run_mode_state, implementation_status: $impl_status, pr_url: (if $pr_url == "" then null else $pr_url end), plan_id_match: true}'
}

force_phase() {
    local target_phase="$1"
    local yes_flag="${2:-false}"

    # Validate phase name
    local valid_phases="preflight discovery flatline_prd architecture flatline_sdd planning flatline_sprint implementation complete"
    local phase_valid=false
    for p in $valid_phases; do
        if [[ "$target_phase" == "$p" ]]; then
            phase_valid=true
            break
        fi
    done

    if [[ "$phase_valid" != "true" ]]; then
        error "Invalid phase: $target_phase"
        error "Valid phases: $valid_phases"
        exit 3
    fi

    if [[ ! -f "$STATE_FILE" ]]; then
        error "No state file found"
        exit 1
    fi

    # Display warning
    warn "════════════════════════════════════════════════════════════"
    warn "  WARNING: Force-phase bypasses validation safeguards"
    warn "  Use only as a last resort when normal recovery fails"
    warn "════════════════════════════════════════════════════════════"

    # Require confirmation if not --yes
    if [[ "$yes_flag" != "true" ]]; then
        error "Add --yes flag to confirm: --force-phase $target_phase --yes"
        exit 5
    fi

    backup_state

    local from_phase
    from_phase=$(jq -r '.phase // "unknown"' "$STATE_FILE")

    atomic_jq_update "$STATE_FILE" \
        --arg phase "$target_phase" \
        '.phase = $phase | .sync_attempts = 0 | .force_phase_used = true'

    log_trajectory "force_phase" "$(jq -n \
        --arg from "$from_phase" \
        --arg to "$target_phase" \
        '{from_phase: $from, to_phase: $to, reason: "user_override"}')"

    warn "Phase forced: $from_phase → $target_phase"
    echo '{"forced": true, "from": "'"$from_phase"'", "to": "'"$target_phase"'"}'
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
    local no_clean=false
    local yes_flag=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from) from_phase="$2"; shift 2 ;;
            --resume) resume=true; shift ;;
            --abort) abort=true; shift ;;
            --dry-run) dry_run=true; shift ;;
            --no-clean) no_clean=true; shift ;;
            --yes) yes_flag=true; shift ;;
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

    # Run workspace cleanup (before lock, skip on resume)
    if [[ "$resume" != "true" && "$no_clean" != "true" ]]; then
        run_workspace_cleanup "$dry_run" "$yes_flag"
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

            # =========================================================================
            # Issue #169 Fix: Detect completed-but-not-recorded implementation
            # =========================================================================
            local simstim_impl_status
            simstim_impl_status=$(jq -r '.phases.implementation.status // "pending"' "$STATE_FILE")
            local sync_attempts
            sync_attempts=$(jq -r '.sync_attempts // 0' "$STATE_FILE")

            # Check for sync attempt limit
            if [[ $sync_attempts -ge $MAX_SYNC_ATTEMPTS ]]; then
                error "Sync failed $sync_attempts times."
                error "Use --force-phase <phase> --yes to bypass, or --abort to start fresh."
                release_lock
                exit 6
            fi

            # Detect completed-but-not-recorded scenario
            if [[ "$phase" == "implementation" && "$simstim_impl_status" == "in_progress" ]]; then
                if [[ -f "$RUN_MODE_STATE" ]]; then
                    local run_mode_state
                    run_mode_state=$(jq -r '.state // "unknown"' "$RUN_MODE_STATE" 2>/dev/null || echo "unknown")

                    case "$run_mode_state" in
                        JACKED_OUT|READY_FOR_HITL)
                            log "Detected completed implementation - syncing state..."

                            # Validate plan_id
                            local expected_plan_id
                            expected_plan_id=$(jq -r '.expected_plan_id // ""' "$STATE_FILE")
                            local run_mode_plan_id
                            run_mode_plan_id=$(jq -r '.plan_id // ""' "$RUN_MODE_STATE" 2>/dev/null || echo "")

                            local plan_id_match=true
                            if [[ -n "$expected_plan_id" && -n "$run_mode_plan_id" ]]; then
                                if [[ "$expected_plan_id" != "$run_mode_plan_id" ]]; then
                                    warn "Plan ID mismatch - stale run-mode state detected"
                                    increment_sync_attempts
                                    plan_id_match=false
                                fi
                            fi

                            if [[ "$plan_id_match" == "true" ]]; then
                                # Sync and proceed to complete phase
                                sync_run_mode >/dev/null
                                log "Implementation completed - proceeding to Phase 8"

                                log_trajectory "workflow_resumed" '{"from_phase": "implementation", "note": "auto-synced from run-mode"}'

                                jq -n \
                                    --arg action "resume" \
                                    --arg phase "complete" \
                                    --argjson drift '{"drift": false, "artifacts": []}' \
                                    --arg note "Implementation completed, synced from run-mode" \
                                    '{action: $action, phase: $phase, drift: $drift, note: $note}'
                                exit 0
                            fi
                            ;;
                        HALTED)
                            log "Detected halted implementation"
                            sync_run_mode >/dev/null
                            # Continue with normal resume - will show HALTED state
                            ;;
                    esac
                fi
            fi
            # =========================================================================
            # End Issue #169 Fix
            # =========================================================================

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
                if [[ ! -f "$_GRIMOIRE_DIR/prd.md" ]]; then
                    error "Cannot start from architect: PRD not found"
                    error "Create $_GRIMOIRE_DIR/prd.md first or run without --from"
                    exit 3
                fi
                ;;
            sprint-plan|planning)
                if [[ ! -f "$_GRIMOIRE_DIR/prd.md" ]]; then
                    error "Cannot start from sprint-plan: PRD not found"
                    exit 3
                fi
                if [[ ! -f "$_GRIMOIRE_DIR/sdd.md" ]]; then
                    error "Cannot start from sprint-plan: SDD not found"
                    exit 3
                fi
                ;;
            run|implementation)
                if [[ ! -f "$_GRIMOIRE_DIR/prd.md" ]]; then
                    error "Cannot start from run: PRD not found"
                    exit 3
                fi
                if [[ ! -f "$_GRIMOIRE_DIR/sdd.md" ]]; then
                    error "Cannot start from run: SDD not found"
                    exit 3
                fi
                if [[ ! -f "$_GRIMOIRE_DIR/sprint.md" ]]; then
                    error "Cannot start from run: Sprint plan not found"
                    exit 3
                fi
                ;;
            plan-and-analyze|discovery)
                # No prerequisites
                ;;
            # SIMSTIM-M-1 FIX: Reject unknown phases in prerequisite check
            *)
                error "Unknown phase: $from_phase"
                error "Valid phases: plan-and-analyze, architect, sprint-plan, run"
                exit 3
                ;;
        esac
    fi

    # Dry run - show planned phases
    if [[ "$dry_run" == "true" ]]; then
        local start_index=0
        if [[ -n "$from_phase" ]]; then
            # SIMSTIM-M-1 FIX: Validate phase values
            case "$from_phase" in
                plan-and-analyze|discovery) start_index=1 ;;
                architect|architecture) start_index=3 ;;
                sprint-plan|planning) start_index=5 ;;
                run|implementation) start_index=7 ;;
                *)
                    error "Unknown phase: $from_phase"
                    exit 3
                    ;;
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
# Blocker Override Logging
# =============================================================================

# Log a blocker override decision with rationale
# Called when user chooses to override a BLOCKER in HITL mode
log_blocker_override() {
    local blocker_id=""
    local decision=""
    local rationale=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --blocker-id) blocker_id="$2"; shift 2 ;;
            --decision) decision="$2"; shift 2 ;;
            --rationale) rationale="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$blocker_id" || -z "$decision" ]]; then
        error "--blocker-id and --decision required"
        exit 3
    fi

    if [[ "$decision" == "override" && -z "$rationale" ]]; then
        error "--rationale required for override decision"
        exit 3
    fi

    if [[ ! -f "$STATE_FILE" ]]; then
        error "No state file found"
        exit 1
    fi

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # SIMSTIM-M-2 FIX: Sanitize rationale with length limit
    # Remove control characters and limit to 1000 chars to prevent DoS/log bloat
    rationale=$(echo "$rationale" | tr -d '\000-\037' | head -c 1000)

    # Add to state file
    local tmp_file="${STATE_FILE}.tmp"
    jq --arg id "$blocker_id" --arg decision "$decision" --arg rationale "$rationale" --arg ts "$timestamp" \
        '.blocker_decisions += [{id: $id, decision: $decision, rationale: $rationale, timestamp: $ts}]' \
        "$STATE_FILE" > "$tmp_file"
    mv "$tmp_file" "$STATE_FILE"

    # Log to trajectory
    log_trajectory "blocker_override" "$(jq -n \
        --arg id "$blocker_id" \
        --arg decision "$decision" \
        --arg rationale "$rationale" \
        --arg timestamp "$timestamp" \
        '{blocker_id: $id, decision: $decision, rationale: $rationale, timestamp: $timestamp}')"

    log "Blocker $blocker_id: $decision (rationale: ${rationale:0:50}...)"
    echo '{"logged": true}'
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

        local timestamp
        timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

        local tmp_file="${STATE_FILE}.tmp"
        jq --arg ts "$timestamp" \
            '.state = "INTERRUPTED" | .timestamps.interrupted = $ts | .timestamps.last_activity = $ts' \
            "$STATE_FILE" > "$tmp_file"
        mv "$tmp_file" "$STATE_FILE"

        log_trajectory "workflow_interrupted" '{"reason": "signal"}'

        # Also use simstim-state.sh for consistency
        local state_script="$SCRIPT_DIR/simstim-state.sh"
        if [[ -x "$state_script" ]]; then
            "$state_script" save-interrupt >/dev/null 2>&1 || true
        fi

        echo "" >&2
        echo "════════════════════════════════════════════════════════════" >&2
        echo "     Workflow Interrupted" >&2
        echo "════════════════════════════════════════════════════════════" >&2
        echo "" >&2
        echo "State saved to: .run/simstim-state.json" >&2
        echo "" >&2
        echo "To continue: /simstim --resume" >&2
        echo "To abort:    /simstim --abort" >&2
        echo "" >&2
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
        --log-blocker-override)
            log_blocker_override "$@"
            ;;
        --cleanup)
            rm -f "$STATE_FILE" "$STATE_BACKUP" "$LOCK_FILE"
            echo '{"cleaned": true}'
            ;;
        --set-expected-plan-id)
            set_expected_plan_id
            ;;
        --sync-run-mode)
            sync_run_mode
            ;;
        --force-phase)
            if [[ $# -lt 1 ]]; then
                error "Usage: --force-phase <phase> [--yes]"
                exit 1
            fi
            local target_phase="$1"
            local yes_flag="false"
            shift
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --yes) yes_flag="true"; shift ;;
                    *) shift ;;
                esac
            done
            force_phase "$target_phase" "$yes_flag"
            ;;
        *)
            error "Unknown command: $command"
            exit 1
            ;;
    esac
}

main "$@"
