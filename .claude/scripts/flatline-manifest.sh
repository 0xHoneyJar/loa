#!/usr/bin/env bash
# =============================================================================
# flatline-manifest.sh - Run manifest manager for Flatline Protocol
# =============================================================================
# Version: 1.0.0
# Part of: Autonomous Flatline Integration v1.22.0
#
# Tracks run state, integrations, snapshots, and disputed items for
# auditability and rollback support.
#
# Usage:
#   flatline-manifest.sh create --phase <type> --document <path>
#   flatline-manifest.sh update <run-id> <field> <value>
#   flatline-manifest.sh add-integration <run-id> --type <type> --id <integration-id>
#   flatline-manifest.sh get <run-id>
#   flatline-manifest.sh list [--status <status>]
#
# Exit codes:
#   0 - Success
#   1 - Manifest creation failed
#   2 - Manifest not found
#   3 - Invalid arguments
#   4 - Lock acquisition failed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
RUNS_DIR="$PROJECT_ROOT/.flatline/runs"

# Source cross-platform time utilities
# shellcheck source=time-lib.sh
source "$SCRIPT_DIR/time-lib.sh"
INDEX_FILE="$RUNS_DIR/index.json"
TRAJECTORY_DIR="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"

# Lock script
LOCK_SCRIPT="$SCRIPT_DIR/flatline-lock.sh"

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[flatline-manifest] $*" >&2
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
    local log_file="$TRAJECTORY_DIR/flatline-manifest-$date_str.jsonl"

    touch "$log_file"
    chmod 600 "$log_file"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg type "flatline_manifest" \
        --arg event "$event_type" \
        --arg timestamp "$timestamp" \
        --argjson data "$data" \
        '{type: $type, event: $event, timestamp: $timestamp, data: $data}' >> "$log_file"
}

# =============================================================================
# Directory Management
# =============================================================================

ensure_runs_dir() {
    if [[ ! -d "$RUNS_DIR" ]]; then
        (umask 077 && mkdir -p "$RUNS_DIR")
        log "Created runs directory: $RUNS_DIR"
    fi

    # Initialize index if needed
    if [[ ! -f "$INDEX_FILE" ]]; then
        echo '{"runs": [], "updated_at": null}' > "$INDEX_FILE"
        chmod 600 "$INDEX_FILE"
    fi
}

# =============================================================================
# ID Generation
# =============================================================================

# Generate run ID: flatline-run-{UUIDv4}
generate_run_id() {
    local uuid
    # Try uuidgen first
    if command -v uuidgen &> /dev/null; then
        uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
    # Fall back to /proc/sys/kernel/random/uuid (Linux)
    elif [[ -f /proc/sys/kernel/random/uuid ]]; then
        uuid=$(cat /proc/sys/kernel/random/uuid)
    # Fall back to Python
    elif command -v python3 &> /dev/null; then
        uuid=$(python3 -c 'import uuid; print(uuid.uuid4())')
    else
        # Last resort: use timestamp + random (cross-platform via time-lib.sh)
        uuid=$(get_timestamp_ns)$(( RANDOM * RANDOM ))
    fi

    echo "flatline-run-${uuid}"
}

# Generate integration ID: {run_id_short}-{sequence}-{hash_short}
generate_integration_id() {
    local run_id="$1"
    local sequence="$2"
    local hash="${3:-}"

    # Extract short run ID (last 8 chars of UUID)
    local run_id_short
    run_id_short=$(echo "$run_id" | sed 's/flatline-run-//' | rev | cut -c1-8 | rev)

    # Format sequence as 3-digit number
    local seq_formatted
    seq_formatted=$(printf "%03d" "$sequence")

    # Get hash short (first 6 chars) or generate random
    local hash_short
    if [[ -n "$hash" ]]; then
        hash_short=$(echo "$hash" | head -c 6)
    else
        hash_short=$(head -c 3 /dev/urandom | xxd -p)
    fi

    echo "${run_id_short}-${seq_formatted}-${hash_short}"
}

# Check for run ID collision
check_run_collision() {
    local run_id="$1"

    if [[ -f "$INDEX_FILE" ]]; then
        local exists
        exists=$(jq -r --arg id "$run_id" '.runs[] | select(.run_id == $id) | .run_id' "$INDEX_FILE" 2>/dev/null || echo "")
        if [[ -n "$exists" ]]; then
            return 0  # Collision found
        fi
    fi

    local manifest_file="$RUNS_DIR/${run_id}.json"
    if [[ -f "$manifest_file" ]]; then
        return 0  # Collision found
    fi

    return 1  # No collision
}

# =============================================================================
# Locking
# =============================================================================

acquire_manifest_lock() {
    local run_id="$1"
    local timeout="${2:-10}"

    if [[ -x "$LOCK_SCRIPT" ]]; then
        "$LOCK_SCRIPT" acquire "$run_id" --type manifest --timeout "$timeout" --caller "manifest"
        return $?
    fi
    return 0  # No lock script, proceed without lock
}

release_manifest_lock() {
    local run_id="$1"

    if [[ -x "$LOCK_SCRIPT" ]]; then
        "$LOCK_SCRIPT" release "$run_id" --type manifest
        return $?
    fi
    return 0
}

# =============================================================================
# Manifest Operations
# =============================================================================

create_manifest() {
    local phase="$1"
    local document="$2"

    ensure_runs_dir

    # Generate unique run ID with collision check
    local run_id
    local attempts=0
    while true; do
        run_id=$(generate_run_id)
        if ! check_run_collision "$run_id"; then
            break
        fi
        ((attempts++))
        if [[ $attempts -gt 10 ]]; then
            error "Failed to generate unique run ID after 10 attempts"
            return 1
        fi
    done

    local manifest_file="$RUNS_DIR/${run_id}.json"

    # Calculate document hash
    local doc_hash=""
    if [[ -f "$document" ]]; then
        doc_hash=$(sha256sum "$document" | cut -d' ' -f1)
    fi

    # Normalize document path
    local doc_relative
    if [[ "$document" == "$PROJECT_ROOT"* ]]; then
        doc_relative="${document#$PROJECT_ROOT/}"
    else
        doc_relative="$document"
    fi

    # Create manifest
    local manifest
    manifest=$(jq -n \
        --arg run_id "$run_id" \
        --arg phase "$phase" \
        --arg document "$doc_relative" \
        --arg document_hash "$doc_hash" \
        --arg status "in_progress" \
        --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            run_id: $run_id,
            phase: $phase,
            document: $document,
            document_hash: $document_hash,
            status: $status,
            created_at: $created_at,
            updated_at: $created_at,
            snapshots: [],
            integrations: [],
            disputed_items: [],
            blockers: [],
            metrics: {
                high_consensus_count: 0,
                disputed_count: 0,
                blocker_count: 0,
                integration_count: 0
            }
        }')

    echo "$manifest" > "$manifest_file"
    chmod 600 "$manifest_file"

    # Update index
    update_index "$run_id" "in_progress" "$phase"

    log "Created manifest: $run_id"
    log_trajectory "manifest_created" "$manifest"

    echo "$manifest"
}

get_manifest() {
    local run_id="$1"

    local manifest_file="$RUNS_DIR/${run_id}.json"

    if [[ ! -f "$manifest_file" ]]; then
        error "Manifest not found: $run_id"
        return 2
    fi

    cat "$manifest_file"
}

update_manifest() {
    local run_id="$1"
    local field="$2"
    local value="$3"

    local manifest_file="$RUNS_DIR/${run_id}.json"

    if [[ ! -f "$manifest_file" ]]; then
        error "Manifest not found: $run_id"
        return 2
    fi

    # Acquire lock
    if ! acquire_manifest_lock "$run_id"; then
        error "Failed to acquire manifest lock"
        return 4
    fi

    trap 'release_manifest_lock "$run_id"' EXIT

    # Update field
    local updated
    updated=$(jq \
        --arg field "$field" \
        --arg value "$value" \
        --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.[$field] = $value | .updated_at = $updated_at' "$manifest_file")

    echo "$updated" > "$manifest_file"

    release_manifest_lock "$run_id"
    trap - EXIT

    # Update index if status changed
    if [[ "$field" == "status" ]]; then
        local phase
        phase=$(echo "$updated" | jq -r '.phase')
        update_index "$run_id" "$value" "$phase"
    fi

    log "Updated manifest $run_id: $field = $value"
    log_trajectory "manifest_updated" "{\"run_id\": \"$run_id\", \"field\": \"$field\", \"value\": \"$value\"}"

    echo "$updated"
}

add_integration() {
    local run_id="$1"
    local integration_type="$2"
    local item_id="$3"
    local snapshot_id="${4:-}"
    local document_hash="${5:-}"

    local manifest_file="$RUNS_DIR/${run_id}.json"

    if [[ ! -f "$manifest_file" ]]; then
        error "Manifest not found: $run_id"
        return 2
    fi

    # Acquire lock
    if ! acquire_manifest_lock "$run_id"; then
        error "Failed to acquire manifest lock"
        return 4
    fi

    trap 'release_manifest_lock "$run_id"' EXIT

    # Get current integration count for sequence number
    local current_count
    current_count=$(jq '.integrations | length' "$manifest_file")
    local sequence=$((current_count + 1))

    # Generate integration ID
    local integration_id
    integration_id=$(generate_integration_id "$run_id" "$sequence" "$document_hash")

    # Create integration record
    local integration
    integration=$(jq -n \
        --arg integration_id "$integration_id" \
        --arg type "$integration_type" \
        --arg item_id "$item_id" \
        --arg snapshot_id "${snapshot_id:-}" \
        --arg document_hash "${document_hash:-}" \
        --argjson sequence "$sequence" \
        --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            integration_id: $integration_id,
            type: $type,
            item_id: $item_id,
            sequence: $sequence,
            snapshot_id: (if $snapshot_id == "" then null else $snapshot_id end),
            document_hash: (if $document_hash == "" then null else $document_hash end),
            created_at: $created_at,
            status: "applied"
        }')

    # Add to manifest
    local updated
    updated=$(jq \
        --argjson integration "$integration" \
        --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.integrations += [$integration] | .metrics.integration_count += 1 | .updated_at = $updated_at' "$manifest_file")

    echo "$updated" > "$manifest_file"

    release_manifest_lock "$run_id"
    trap - EXIT

    log "Added integration: $integration_id (type: $integration_type)"
    log_trajectory "integration_added" "$integration"

    echo "$integration"
}

add_snapshot() {
    local run_id="$1"
    local snapshot_id="$2"

    local manifest_file="$RUNS_DIR/${run_id}.json"

    if [[ ! -f "$manifest_file" ]]; then
        error "Manifest not found: $run_id"
        return 2
    fi

    # Acquire lock
    if ! acquire_manifest_lock "$run_id"; then
        error "Failed to acquire manifest lock"
        return 4
    fi

    trap 'release_manifest_lock "$run_id"' EXIT

    local updated
    updated=$(jq \
        --arg snapshot_id "$snapshot_id" \
        --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.snapshots += [$snapshot_id] | .updated_at = $updated_at' "$manifest_file")

    echo "$updated" > "$manifest_file"

    release_manifest_lock "$run_id"
    trap - EXIT

    log "Added snapshot to manifest: $snapshot_id"
}

add_disputed() {
    local run_id="$1"
    local item_json="$2"

    local manifest_file="$RUNS_DIR/${run_id}.json"

    if [[ ! -f "$manifest_file" ]]; then
        error "Manifest not found: $run_id"
        return 2
    fi

    # Acquire lock
    if ! acquire_manifest_lock "$run_id"; then
        error "Failed to acquire manifest lock"
        return 4
    fi

    trap 'release_manifest_lock "$run_id"' EXIT

    local updated
    updated=$(jq \
        --argjson item "$item_json" \
        --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.disputed_items += [$item] | .metrics.disputed_count += 1 | .updated_at = $updated_at' "$manifest_file")

    echo "$updated" > "$manifest_file"

    release_manifest_lock "$run_id"
    trap - EXIT

    log "Added disputed item to manifest"
    log_trajectory "disputed_added" "$item_json"
}

add_blocker() {
    local run_id="$1"
    local blocker_json="$2"

    local manifest_file="$RUNS_DIR/${run_id}.json"

    if [[ ! -f "$manifest_file" ]]; then
        error "Manifest not found: $run_id"
        return 2
    fi

    # Acquire lock
    if ! acquire_manifest_lock "$run_id"; then
        error "Failed to acquire manifest lock"
        return 4
    fi

    trap 'release_manifest_lock "$run_id"' EXIT

    local updated
    updated=$(jq \
        --argjson blocker "$blocker_json" \
        --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.blockers += [$blocker] | .metrics.blocker_count += 1 | .updated_at = $updated_at' "$manifest_file")

    echo "$updated" > "$manifest_file"

    release_manifest_lock "$run_id"
    trap - EXIT

    log "Added blocker to manifest"
    log_trajectory "blocker_added" "$blocker_json"
}

mark_integration_rolled_back() {
    local run_id="$1"
    local integration_id="$2"

    local manifest_file="$RUNS_DIR/${run_id}.json"

    if [[ ! -f "$manifest_file" ]]; then
        error "Manifest not found: $run_id"
        return 2
    fi

    # Acquire lock
    if ! acquire_manifest_lock "$run_id"; then
        error "Failed to acquire manifest lock"
        return 4
    fi

    trap 'release_manifest_lock "$run_id"' EXIT

    local updated
    updated=$(jq \
        --arg integration_id "$integration_id" \
        --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '(.integrations[] | select(.integration_id == $integration_id) | .status) = "rolled_back" |
         .updated_at = $updated_at' "$manifest_file")

    echo "$updated" > "$manifest_file"

    release_manifest_lock "$run_id"
    trap - EXIT

    log "Marked integration as rolled back: $integration_id"
    log_trajectory "integration_rolled_back" "{\"run_id\": \"$run_id\", \"integration_id\": \"$integration_id\"}"
}

# =============================================================================
# Index Management
# =============================================================================

update_index() {
    local run_id="$1"
    local status="$2"
    local phase="$3"

    ensure_runs_dir

    # M-6 FIX: Acquire lock on index and fail if cannot acquire
    local lock_acquired=false
    if [[ -x "$LOCK_SCRIPT" ]]; then
        if "$LOCK_SCRIPT" acquire "index" --type manifest --timeout 5 --caller "index" >/dev/null 2>&1; then
            lock_acquired=true
        else
            error "Failed to acquire index lock, aborting update"
            log_trajectory "index_lock_failed" "{\"run_id\": \"$run_id\", \"status\": \"$status\"}"
            return 4
        fi
    fi

    local updated
    updated=$(jq \
        --arg run_id "$run_id" \
        --arg status "$status" \
        --arg phase "$phase" \
        --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '
        # Remove existing entry if present
        .runs = [.runs[] | select(.run_id != $run_id)] |
        # Add new/updated entry
        .runs += [{run_id: $run_id, status: $status, phase: $phase, updated_at: $updated_at}] |
        .updated_at = $updated_at
        ' "$INDEX_FILE")

    echo "$updated" > "$INDEX_FILE"

    if [[ "$lock_acquired" == "true" ]]; then
        "$LOCK_SCRIPT" release "index" --type manifest 2>/dev/null || true
    fi
}

list_manifests() {
    local filter_status="${1:-}"

    ensure_runs_dir

    local manifests=()

    while IFS= read -r -d '' manifest_file; do
        # Skip index file
        if [[ "$(basename "$manifest_file")" == "index.json" ]]; then
            continue
        fi

        local manifest
        manifest=$(cat "$manifest_file" 2>/dev/null || echo "{}")

        # Filter by status if specified
        if [[ -n "$filter_status" ]]; then
            local status
            status=$(echo "$manifest" | jq -r '.status // ""')
            if [[ "$status" != "$filter_status" ]]; then
                continue
            fi
        fi

        # Return summary view
        local summary
        summary=$(echo "$manifest" | jq '{
            run_id: .run_id,
            phase: .phase,
            document: .document,
            status: .status,
            created_at: .created_at,
            updated_at: .updated_at,
            metrics: .metrics
        }')

        manifests+=("$summary")
    done < <(find "$RUNS_DIR" -name "*.json" -type f -print0 2>/dev/null)

    if [[ ${#manifests[@]} -eq 0 ]]; then
        echo "[]"
    else
        printf '%s\n' "${manifests[@]}" | jq -s '.'
    fi
}

# =============================================================================
# Main
# =============================================================================

usage() {
    cat <<EOF
Usage: flatline-manifest.sh <command> [options]

Commands:
  create                   Create new run manifest
    --phase <type>         Phase type: prd, sdd, sprint (required)
    --document <path>      Document being reviewed (required)

  get <run-id>             Get manifest by run ID

  update <run-id>          Update manifest field
    --field <name>         Field name (required)
    --value <value>        New value (required)

  add-integration <run-id> Add integration to manifest
    --type <type>          Integration type: high_consensus, disputed, etc.
    --item-id <id>         Item ID from Flatline result
    --snapshot-id <id>     Associated snapshot ID (optional)
    --document-hash <hash> Document hash at integration time (optional)

  add-snapshot <run-id>    Add snapshot to manifest
    --snapshot-id <id>     Snapshot ID (required)

  add-disputed <run-id>    Add disputed item to manifest
    --item <json>          Disputed item JSON (required)

  add-blocker <run-id>     Add blocker to manifest
    --item <json>          Blocker item JSON (required)

  mark-rolled-back <run-id> Mark integration as rolled back
    --integration-id <id>  Integration ID (required)

  list                     List all manifests
    --status <status>      Filter by status

Examples:
  flatline-manifest.sh create --phase prd --document grimoires/loa/prd.md
  flatline-manifest.sh get flatline-run-abc123
  flatline-manifest.sh add-integration flatline-run-abc123 --type high_consensus --item-id IMP-001
  flatline-manifest.sh list --status in_progress

Exit codes:
  0 - Success
  1 - Operation failed
  2 - Manifest not found
  3 - Invalid arguments
  4 - Lock acquisition failed
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
        create)
            local phase=""
            local document=""

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --phase)
                        phase="$2"
                        shift 2
                        ;;
                    --document)
                        document="$2"
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

            if [[ -z "$phase" ]]; then
                error "--phase required"
                exit 3
            fi

            if [[ -z "$document" ]]; then
                error "--document required"
                exit 3
            fi

            create_manifest "$phase" "$document"
            ;;

        get)
            local run_id=""

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        run_id="$1"
                        shift
                        ;;
                esac
            done

            if [[ -z "$run_id" ]]; then
                error "Run ID required"
                exit 3
            fi

            get_manifest "$run_id"
            ;;

        update)
            local run_id=""
            local field=""
            local value=""

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --field)
                        field="$2"
                        shift 2
                        ;;
                    --value)
                        value="$2"
                        shift 2
                        ;;
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        run_id="$1"
                        shift
                        ;;
                esac
            done

            if [[ -z "$run_id" ]]; then
                error "Run ID required"
                exit 3
            fi
            if [[ -z "$field" ]]; then
                error "--field required"
                exit 3
            fi
            if [[ -z "$value" ]]; then
                error "--value required"
                exit 3
            fi

            update_manifest "$run_id" "$field" "$value"
            ;;

        add-integration)
            local run_id=""
            local type=""
            local item_id=""
            local snapshot_id=""
            local document_hash=""

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --type)
                        type="$2"
                        shift 2
                        ;;
                    --item-id)
                        item_id="$2"
                        shift 2
                        ;;
                    --snapshot-id)
                        snapshot_id="$2"
                        shift 2
                        ;;
                    --document-hash)
                        document_hash="$2"
                        shift 2
                        ;;
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        run_id="$1"
                        shift
                        ;;
                esac
            done

            if [[ -z "$run_id" ]]; then
                error "Run ID required"
                exit 3
            fi
            if [[ -z "$type" ]]; then
                error "--type required"
                exit 3
            fi
            if [[ -z "$item_id" ]]; then
                error "--item-id required"
                exit 3
            fi

            add_integration "$run_id" "$type" "$item_id" "$snapshot_id" "$document_hash"
            ;;

        add-snapshot)
            local run_id=""
            local snapshot_id=""

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --snapshot-id)
                        snapshot_id="$2"
                        shift 2
                        ;;
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        run_id="$1"
                        shift
                        ;;
                esac
            done

            if [[ -z "$run_id" ]]; then
                error "Run ID required"
                exit 3
            fi
            if [[ -z "$snapshot_id" ]]; then
                error "--snapshot-id required"
                exit 3
            fi

            add_snapshot "$run_id" "$snapshot_id"
            ;;

        add-disputed)
            local run_id=""
            local item=""

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --item)
                        item="$2"
                        shift 2
                        ;;
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        run_id="$1"
                        shift
                        ;;
                esac
            done

            if [[ -z "$run_id" ]]; then
                error "Run ID required"
                exit 3
            fi
            if [[ -z "$item" ]]; then
                error "--item required"
                exit 3
            fi

            add_disputed "$run_id" "$item"
            ;;

        add-blocker)
            local run_id=""
            local item=""

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --item)
                        item="$2"
                        shift 2
                        ;;
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        run_id="$1"
                        shift
                        ;;
                esac
            done

            if [[ -z "$run_id" ]]; then
                error "Run ID required"
                exit 3
            fi
            if [[ -z "$item" ]]; then
                error "--item required"
                exit 3
            fi

            add_blocker "$run_id" "$item"
            ;;

        mark-rolled-back)
            local run_id=""
            local integration_id=""

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --integration-id)
                        integration_id="$2"
                        shift 2
                        ;;
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        run_id="$1"
                        shift
                        ;;
                esac
            done

            if [[ -z "$run_id" ]]; then
                error "Run ID required"
                exit 3
            fi
            if [[ -z "$integration_id" ]]; then
                error "--integration-id required"
                exit 3
            fi

            mark_integration_rolled_back "$run_id" "$integration_id"
            ;;

        list)
            local status=""

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --status)
                        status="$2"
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

            list_manifests "$status"
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
