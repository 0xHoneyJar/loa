#!/usr/bin/env bash
# =============================================================================
# flatline-rollback.sh - Rollback handler for Flatline Protocol
# =============================================================================
# Version: 1.0.0
# Part of: Autonomous Flatline Integration v1.22.0
#
# Provides rollback capability for auto-integrated changes with divergence
# detection and safety features.
#
# Usage:
#   flatline-rollback.sh single --integration-id <id> [--run-id <id>]
#   flatline-rollback.sh run --run-id <id> [--dry-run]
#   flatline-rollback.sh snapshot --snapshot-id <id> [--force]
#   flatline-rollback.sh list --run-id <id>
#
# Exit codes:
#   0 - Success
#   1 - Rollback failed
#   2 - Resource not found
#   3 - Invalid arguments
#   4 - Divergence detected (use --force to override)
#   5 - Lock acquisition failed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNS_DIR="$PROJECT_ROOT/.flatline/runs"
SNAPSHOT_DIR="$PROJECT_ROOT/.flatline/snapshots"
TRAJECTORY_DIR="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"

# Component scripts
LOCK_SCRIPT="$SCRIPT_DIR/flatline-lock.sh"
SNAPSHOT_SCRIPT="$SCRIPT_DIR/flatline-snapshot.sh"
MANIFEST_SCRIPT="$SCRIPT_DIR/flatline-manifest.sh"

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[flatline-rollback] $*" >&2
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
    local log_file="$TRAJECTORY_DIR/flatline-rollback-$date_str.jsonl"

    touch "$log_file"
    chmod 600 "$log_file"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg type "flatline_rollback" \
        --arg event "$event_type" \
        --arg timestamp "$timestamp" \
        --argjson data "$data" \
        '{type: $type, event: $event, timestamp: $timestamp, data: $data}' >> "$log_file"
}

# =============================================================================
# Hash Calculation
# =============================================================================

calculate_hash() {
    local file="$1"
    if [[ -f "$file" ]]; then
        sha256sum "$file" | cut -d' ' -f1
    else
        echo ""
    fi
}

# =============================================================================
# Divergence Detection
# =============================================================================

check_divergence() {
    local document="$1"
    local expected_hash="$2"

    if [[ ! -f "$document" ]]; then
        # Document doesn't exist - divergence (deleted)
        warn "Document does not exist: $document"
        return 0  # Not diverged, can proceed (will create)
    fi

    local current_hash
    current_hash=$(calculate_hash "$document")

    if [[ "$current_hash" != "$expected_hash" ]]; then
        warn "Document has been modified since integration"
        warn "Expected: $expected_hash"
        warn "Current:  $current_hash"
        return 1  # Diverged
    fi

    return 0  # Not diverged
}

# =============================================================================
# Backup Creation
# =============================================================================

create_backup() {
    local document="$1"

    if [[ ! -f "$document" ]]; then
        return 0
    fi

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${document}.pre-rollback-${timestamp}"

    cp "$document" "$backup_path"
    chmod 600 "$backup_path"

    log "Created backup: $backup_path"
    echo "$backup_path"
}

# =============================================================================
# Single Integration Rollback
# =============================================================================

rollback_single() {
    local integration_id="$1"
    local run_id="${2:-}"
    local dry_run="${3:-false}"
    local force="${4:-false}"

    # Find run_id if not provided
    if [[ -z "$run_id" ]]; then
        # Search through manifests
        while IFS= read -r -d '' manifest_file; do
            local found_run_id
            found_run_id=$(jq -r --arg id "$integration_id" \
                'select(.integrations[].integration_id == $id) | .run_id' "$manifest_file" 2>/dev/null || echo "")
            if [[ -n "$found_run_id" ]]; then
                run_id="$found_run_id"
                break
            fi
        done < <(find "$RUNS_DIR" -name "*.json" -type f -print0 2>/dev/null)
    fi

    if [[ -z "$run_id" ]]; then
        error "Could not find run for integration: $integration_id"
        return 2
    fi

    # Get manifest
    local manifest
    manifest=$("$MANIFEST_SCRIPT" get "$run_id" 2>/dev/null) || {
        error "Could not get manifest for run: $run_id"
        return 2
    }

    # Find integration in manifest
    local integration
    integration=$(echo "$manifest" | jq --arg id "$integration_id" '.integrations[] | select(.integration_id == $id)')

    if [[ -z "$integration" || "$integration" == "null" ]]; then
        error "Integration not found: $integration_id"
        return 2
    fi

    local snapshot_id
    snapshot_id=$(echo "$integration" | jq -r '.snapshot_id // ""')

    if [[ -z "$snapshot_id" || "$snapshot_id" == "null" ]]; then
        error "No snapshot associated with integration: $integration_id"
        error "Cannot rollback without a snapshot"
        return 1
    fi

    # Get document from manifest
    local document
    document=$(echo "$manifest" | jq -r '.document')
    local full_path="$PROJECT_ROOT/$document"

    # Get expected hash
    local expected_hash
    expected_hash=$(echo "$integration" | jq -r '.document_hash // ""')

    # Check for divergence
    if [[ -n "$expected_hash" && "$expected_hash" != "null" ]]; then
        if ! check_divergence "$full_path" "$expected_hash"; then
            if [[ "$force" != "true" ]]; then
                error "Divergence detected. Use --force to override."
                return 4
            fi
            warn "Forcing rollback despite divergence"
        fi
    fi

    if [[ "$dry_run" == "true" ]]; then
        log "[DRY RUN] Would rollback integration $integration_id using snapshot $snapshot_id"
        jq -n \
            --arg integration_id "$integration_id" \
            --arg snapshot_id "$snapshot_id" \
            --arg document "$document" \
            '{dry_run: true, integration_id: $integration_id, snapshot_id: $snapshot_id, document: $document}'
        return 0
    fi

    # Acquire locks (order: run → manifest → document)
    log "Acquiring locks for rollback..."

    if [[ -x "$LOCK_SCRIPT" ]]; then
        "$LOCK_SCRIPT" run-acquire "$run_id" || {
            error "Failed to acquire run lock"
            return 5
        }
        trap '"$LOCK_SCRIPT" run-release 2>/dev/null || true' EXIT

        "$LOCK_SCRIPT" acquire "$run_id" --type manifest || {
            error "Failed to acquire manifest lock"
            return 5
        }

        "$LOCK_SCRIPT" acquire "$document" --type document || {
            error "Failed to acquire document lock"
            return 5
        }
    fi

    # Create backup before rollback
    local backup_path
    backup_path=$(create_backup "$full_path")

    # Restore from snapshot
    log "Restoring from snapshot: $snapshot_id"
    "$SNAPSHOT_SCRIPT" restore "$snapshot_id" --force || {
        error "Snapshot restore failed"
        return 1
    }

    # Mark integration as rolled back in manifest
    "$MANIFEST_SCRIPT" mark-rolled-back "$run_id" --integration-id "$integration_id"

    # Release locks
    if [[ -x "$LOCK_SCRIPT" ]]; then
        "$LOCK_SCRIPT" release "$document" --type document || true
        "$LOCK_SCRIPT" release "$run_id" --type manifest || true
        "$LOCK_SCRIPT" run-release || true
        trap - EXIT
    fi

    log "Rollback complete: $integration_id"
    log_trajectory "single_rollback" "{\"integration_id\": \"$integration_id\", \"snapshot_id\": \"$snapshot_id\", \"backup\": \"$backup_path\"}"

    jq -n \
        --arg integration_id "$integration_id" \
        --arg snapshot_id "$snapshot_id" \
        --arg document "$document" \
        --arg backup "$backup_path" \
        '{status: "rolled_back", integration_id: $integration_id, snapshot_id: $snapshot_id, document: $document, backup: $backup}'
}

# =============================================================================
# Full Run Rollback
# =============================================================================

rollback_run() {
    local run_id="$1"
    local dry_run="${2:-false}"
    local force="${3:-false}"

    # Get manifest
    local manifest
    manifest=$("$MANIFEST_SCRIPT" get "$run_id" 2>/dev/null) || {
        error "Could not get manifest for run: $run_id"
        return 2
    }

    # Get all integrations (in reverse order for proper rollback)
    local integrations
    integrations=$(echo "$manifest" | jq -r '[.integrations | reverse[]] | .[]' 2>/dev/null || echo "")

    if [[ -z "$integrations" ]]; then
        warn "No integrations found in run: $run_id"
        return 0
    fi

    local integration_count
    integration_count=$(echo "$manifest" | jq '.integrations | length')

    log "Rolling back $integration_count integrations for run: $run_id"

    local rolled_back=0
    local failed=0

    # Process each integration in reverse order
    echo "$manifest" | jq -c '.integrations | reverse | .[]' | while IFS= read -r integration; do
        local integration_id
        integration_id=$(echo "$integration" | jq -r '.integration_id')

        local status
        status=$(echo "$integration" | jq -r '.status')

        # Skip already rolled back integrations
        if [[ "$status" == "rolled_back" ]]; then
            log "Skipping already rolled back: $integration_id"
            continue
        fi

        log "Rolling back: $integration_id"

        if rollback_single "$integration_id" "$run_id" "$dry_run" "$force"; then
            ((rolled_back++))
        else
            ((failed++))
            if [[ "$force" != "true" ]]; then
                error "Rollback failed for $integration_id, stopping"
                break
            fi
            warn "Rollback failed for $integration_id, continuing due to --force"
        fi
    done

    # Update manifest status
    if [[ "$dry_run" != "true" ]]; then
        "$MANIFEST_SCRIPT" update "$run_id" --field status --value "rolled_back"
    fi

    log "Run rollback complete: $rolled_back succeeded, $failed failed"
    log_trajectory "run_rollback" "{\"run_id\": \"$run_id\", \"rolled_back\": $rolled_back, \"failed\": $failed}"

    jq -n \
        --arg run_id "$run_id" \
        --argjson rolled_back "$rolled_back" \
        --argjson failed "$failed" \
        --arg dry_run "$dry_run" \
        '{status: "completed", run_id: $run_id, rolled_back: $rolled_back, failed: $failed, dry_run: ($dry_run == "true")}'
}

# =============================================================================
# Direct Snapshot Rollback
# =============================================================================

rollback_snapshot() {
    local snapshot_id="$1"
    local force="${2:-false}"

    log "Rolling back directly from snapshot: $snapshot_id"

    # Get snapshot metadata
    local meta_file="$SNAPSHOT_DIR/${snapshot_id}.meta"
    if [[ ! -f "$meta_file" ]]; then
        error "Snapshot metadata not found: $snapshot_id"
        return 2
    fi

    local meta
    meta=$(cat "$meta_file")

    local document
    document=$(echo "$meta" | jq -r '.document')
    local full_path="$PROJECT_ROOT/$document"

    local expected_hash
    expected_hash=$(echo "$meta" | jq -r '.hash // ""')

    # For direct snapshot restore, we don't check divergence against expected
    # (the snapshot is the source of truth)
    # But we do create a backup

    # Acquire document lock
    if [[ -x "$LOCK_SCRIPT" ]]; then
        "$LOCK_SCRIPT" acquire "$document" --type document || {
            error "Failed to acquire document lock"
            return 5
        }
        trap '"$LOCK_SCRIPT" release "$document" --type document 2>/dev/null || true' EXIT
    fi

    # Create backup
    local backup_path
    backup_path=$(create_backup "$full_path")

    # Restore snapshot
    "$SNAPSHOT_SCRIPT" restore "$snapshot_id" --force || {
        error "Snapshot restore failed"
        return 1
    }

    # Release lock
    if [[ -x "$LOCK_SCRIPT" ]]; then
        "$LOCK_SCRIPT" release "$document" --type document || true
        trap - EXIT
    fi

    log "Snapshot rollback complete: $snapshot_id"
    log_trajectory "snapshot_rollback" "{\"snapshot_id\": \"$snapshot_id\", \"document\": \"$document\", \"backup\": \"$backup_path\"}"

    jq -n \
        --arg snapshot_id "$snapshot_id" \
        --arg document "$document" \
        --arg backup "$backup_path" \
        '{status: "restored", snapshot_id: $snapshot_id, document: $document, backup: $backup}'
}

# =============================================================================
# List Integrations for Rollback
# =============================================================================

list_integrations() {
    local run_id="$1"

    # Get manifest
    local manifest
    manifest=$("$MANIFEST_SCRIPT" get "$run_id" 2>/dev/null) || {
        error "Could not get manifest for run: $run_id"
        return 2
    }

    # Return integrations with rollback info
    echo "$manifest" | jq '.integrations | map({
        integration_id: .integration_id,
        type: .type,
        item_id: .item_id,
        status: .status,
        snapshot_id: .snapshot_id,
        created_at: .created_at,
        can_rollback: (.snapshot_id != null and .status != "rolled_back")
    })'
}

# =============================================================================
# Main
# =============================================================================

usage() {
    cat <<EOF
Usage: flatline-rollback.sh <command> [options]

Commands:
  single                   Rollback single integration
    --integration-id <id>  Integration ID (required)
    --run-id <id>          Run ID (auto-discovered if not provided)
    --dry-run              Preview without executing
    --force                Force rollback despite divergence

  run                      Rollback entire run
    --run-id <id>          Run ID (required)
    --dry-run              Preview without executing
    --force                Continue on failures

  snapshot                 Restore directly from snapshot
    --snapshot-id <id>     Snapshot ID (required)
    --force                Skip confirmation

  list                     List integrations available for rollback
    --run-id <id>          Run ID (required)

Examples:
  flatline-rollback.sh single --integration-id abc123-001-f7e8d9
  flatline-rollback.sh run --run-id flatline-run-abc123 --dry-run
  flatline-rollback.sh snapshot --snapshot-id 20260203_143000_a1b2c3d4
  flatline-rollback.sh list --run-id flatline-run-abc123

Exit codes:
  0 - Success
  1 - Rollback failed
  2 - Resource not found
  3 - Invalid arguments
  4 - Divergence detected
  5 - Lock acquisition failed
EOF
}

main() {
    if [[ $# -lt 1 ]]; then
        usage
        exit 3
    fi

    local command="$1"
    shift

    case "$command" in
        single)
            local integration_id=""
            local run_id=""
            local dry_run="false"
            local force="false"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --integration-id)
                        integration_id="$2"
                        shift 2
                        ;;
                    --run-id)
                        run_id="$2"
                        shift 2
                        ;;
                    --dry-run)
                        dry_run="true"
                        shift
                        ;;
                    --force)
                        force="true"
                        shift
                        ;;
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        error "Unexpected argument: $1"
                        exit 3
                        ;;
                esac
            done

            if [[ -z "$integration_id" ]]; then
                error "--integration-id required"
                exit 3
            fi

            rollback_single "$integration_id" "$run_id" "$dry_run" "$force"
            ;;

        run)
            local run_id=""
            local dry_run="false"
            local force="false"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --run-id)
                        run_id="$2"
                        shift 2
                        ;;
                    --dry-run)
                        dry_run="true"
                        shift
                        ;;
                    --force)
                        force="true"
                        shift
                        ;;
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        error "Unexpected argument: $1"
                        exit 3
                        ;;
                esac
            done

            if [[ -z "$run_id" ]]; then
                error "--run-id required"
                exit 3
            fi

            rollback_run "$run_id" "$dry_run" "$force"
            ;;

        snapshot)
            local snapshot_id=""
            local force="false"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --snapshot-id)
                        snapshot_id="$2"
                        shift 2
                        ;;
                    --force)
                        force="true"
                        shift
                        ;;
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        error "Unexpected argument: $1"
                        exit 3
                        ;;
                esac
            done

            if [[ -z "$snapshot_id" ]]; then
                error "--snapshot-id required"
                exit 3
            fi

            rollback_snapshot "$snapshot_id" "$force"
            ;;

        list)
            local run_id=""

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --run-id)
                        run_id="$2"
                        shift 2
                        ;;
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        error "Unexpected argument: $1"
                        exit 3
                        ;;
                esac
            done

            if [[ -z "$run_id" ]]; then
                error "--run-id required"
                exit 3
            fi

            list_integrations "$run_id"
            ;;

        -h|--help|help)
            usage
            exit 0
            ;;

        *)
            error "Unknown command: $command"
            usage
            exit 3
            ;;
    esac
}

main "$@"
