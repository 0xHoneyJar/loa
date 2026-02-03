#!/usr/bin/env bash
# =============================================================================
# simstim-state.sh - State file CRUD operations for /simstim workflow
# =============================================================================
# Version: 1.0.0
# Part of: Simstim v1.24.0
#
# Provides atomic state file operations with backup and checksum tracking.
# Used by simstim-orchestrator.sh for workflow state management.
#
# Usage:
#   simstim-state.sh <command> [options]
#
# Commands:
#   init [--from <phase>]        Create initial state file
#   get <field>                  Get field value (dot notation: timestamps.started)
#   update <field> <value>       Update field atomically
#   update-phase <phase> <status> Update phase status
#   add-artifact <name> <path>   Add artifact with SHA256 checksum
#   validate-artifacts           Compare checksums, return drift JSON
#   save-interrupt               Mark state as interrupted
#   cleanup                      Remove state file and backup
#   check-version                Verify schema version, migrate if needed
#
# Exit codes:
#   0 - Success
#   1 - General error
#   2 - State file not found
#   3 - Invalid arguments
#   4 - Version mismatch
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUN_DIR="$PROJECT_ROOT/.run"
STATE_FILE="$RUN_DIR/simstim-state.json"
STATE_BACKUP="$RUN_DIR/simstim-state.json.bak"

# Current schema version
SCHEMA_VERSION=1

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[simstim-state] $*" >&2
}

error() {
    echo "ERROR: $*" >&2
}

# =============================================================================
# State File Operations
# =============================================================================

# Ensure run directory exists with proper permissions
ensure_run_dir() {
    if [[ ! -d "$RUN_DIR" ]]; then
        mkdir -p "$RUN_DIR"
        chmod 700 "$RUN_DIR"
    fi
}

# Create backup before modification
backup_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cp "$STATE_FILE" "$STATE_BACKUP"
    fi
}

# Atomic write: temp file + mv
atomic_write() {
    local content="$1"
    local tmp_file="${STATE_FILE}.tmp"

    echo "$content" > "$tmp_file"
    chmod 600 "$tmp_file"
    mv "$tmp_file" "$STATE_FILE"
}

# Check if state file exists
state_exists() {
    [[ -f "$STATE_FILE" ]]
}

# Calculate SHA256 checksum
calculate_checksum() {
    local file="$1"
    if [[ -f "$file" ]]; then
        sha256sum "$file" | cut -d' ' -f1
    else
        echo ""
    fi
}

# =============================================================================
# Schema Version Management
# =============================================================================

check_version() {
    if ! state_exists; then
        error "State file not found"
        exit 2
    fi

    local version
    version=$(jq -r '.schema_version // 0' "$STATE_FILE")

    if [[ "$version" == "0" ]]; then
        # Legacy state file without version - assume v1, add version
        log "Legacy state file detected, adding schema_version=1"
        backup_state
        local tmp_file="${STATE_FILE}.tmp"
        jq --argjson v "$SCHEMA_VERSION" '.schema_version = $v' "$STATE_FILE" > "$tmp_file"
        mv "$tmp_file" "$STATE_FILE"
        echo '{"version": 1, "migrated": true}'
        return 0
    fi

    if [[ "$version" -lt "$SCHEMA_VERSION" ]]; then
        # Future: migration hooks would go here
        log "State version $version is older than current $SCHEMA_VERSION - migration needed"
        # For now, just update version (no actual migration needed for v1)
        backup_state
        local tmp_file="${STATE_FILE}.tmp"
        jq --argjson v "$SCHEMA_VERSION" '.schema_version = $v' "$STATE_FILE" > "$tmp_file"
        mv "$tmp_file" "$STATE_FILE"
        echo "{\"version\": $SCHEMA_VERSION, \"migrated_from\": $version}"
        return 0
    fi

    if [[ "$version" -gt "$SCHEMA_VERSION" ]]; then
        error "State version $version is newer than supported $SCHEMA_VERSION"
        exit 4
    fi

    echo "{\"version\": $version, \"migrated\": false}"
}

# =============================================================================
# Initialize State
# =============================================================================

init_state() {
    local from_phase=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from) from_phase="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    ensure_run_dir

    if state_exists; then
        error "State file already exists. Use --cleanup first or --resume."
        exit 1
    fi

    local simstim_id
    simstim_id="simstim-$(date +%Y%m%d)-$(openssl rand -hex 4)"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Map --from phase to starting phase
    local starting_phase="preflight"
    case "$from_phase" in
        "plan-and-analyze"|"discovery") starting_phase="discovery" ;;
        "architect"|"architecture") starting_phase="architecture" ;;
        "sprint-plan"|"planning") starting_phase="planning" ;;
        "run"|"implementation") starting_phase="implementation" ;;
        "") starting_phase="preflight" ;;
        *) error "Unknown phase: $from_phase"; exit 3 ;;
    esac

    # Create initial state
    local state
    state=$(jq -n \
        --arg id "$simstim_id" \
        --argjson version "$SCHEMA_VERSION" \
        --arg ts "$timestamp" \
        --arg phase "$starting_phase" \
        --arg from "${from_phase:-full}" \
        '{
            simstim_id: $id,
            schema_version: $version,
            state: "RUNNING",
            phase: $phase,
            timestamps: {
                started: $ts,
                last_activity: $ts
            },
            phases: {
                preflight: (if $phase == "preflight" then "pending" else "skipped" end),
                discovery: (if $phase == "preflight" or $phase == "discovery" then "pending" else "skipped" end),
                flatline_prd: (if $phase == "preflight" or $phase == "discovery" then "pending" else "skipped" end),
                architecture: (if $phase == "preflight" or $phase == "discovery" or $phase == "architecture" then "pending" else "skipped" end),
                flatline_sdd: (if $phase == "preflight" or $phase == "discovery" or $phase == "architecture" then "pending" else "skipped" end),
                planning: (if $phase != "implementation" then "pending" else "skipped" end),
                flatline_sprint: (if $phase != "implementation" then "pending" else "skipped" end),
                implementation: "pending"
            },
            artifacts: {},
            flatline_metrics: {},
            blocker_decisions: [],
            options: {
                from: $from,
                timeout_hours: 24
            }
        }')

    atomic_write "$state"
    log "Initialized state: $simstim_id (starting from $starting_phase)"

    echo "$state"
}

# =============================================================================
# Get Field
# =============================================================================

get_field() {
    local field="$1"

    if ! state_exists; then
        error "State file not found"
        exit 2
    fi

    jq -r ".$field // null" "$STATE_FILE"
}

# =============================================================================
# Update Field
# =============================================================================

update_field() {
    local field="$1"
    local value="$2"

    if ! state_exists; then
        error "State file not found"
        exit 2
    fi

    backup_state

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local tmp_file="${STATE_FILE}.tmp"

    # Handle different value types
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        # Numeric value
        jq --arg ts "$timestamp" --argjson val "$value" \
            ".timestamps.last_activity = \$ts | .$field = \$val" \
            "$STATE_FILE" > "$tmp_file"
    elif [[ "$value" == "true" || "$value" == "false" || "$value" == "null" ]]; then
        # Boolean or null
        jq --arg ts "$timestamp" --argjson val "$value" \
            ".timestamps.last_activity = \$ts | .$field = \$val" \
            "$STATE_FILE" > "$tmp_file"
    else
        # String value
        jq --arg ts "$timestamp" --arg val "$value" \
            ".timestamps.last_activity = \$ts | .$field = \$val" \
            "$STATE_FILE" > "$tmp_file"
    fi

    mv "$tmp_file" "$STATE_FILE"
    log "Updated $field = $value"
    echo '{"updated": true}'
}

# =============================================================================
# Update Phase Status
# =============================================================================

update_phase() {
    local phase="$1"
    local status="$2"

    if ! state_exists; then
        error "State file not found"
        exit 2
    fi

    # Validate status
    case "$status" in
        pending|in_progress|completed|skipped|incomplete) ;;
        *) error "Invalid status: $status (expected: pending|in_progress|completed|skipped|incomplete)"; exit 3 ;;
    esac

    backup_state

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local tmp_file="${STATE_FILE}.tmp"
    jq --arg phase "$phase" --arg status "$status" --arg ts "$timestamp" \
        '.timestamps.last_activity = $ts | .phases[$phase] = $status | .phase = (if $status == "in_progress" then $phase else .phase end)' \
        "$STATE_FILE" > "$tmp_file"
    mv "$tmp_file" "$STATE_FILE"

    log "Phase $phase: $status"
    echo '{"updated": true}'
}

# =============================================================================
# Add Artifact
# =============================================================================

add_artifact() {
    local name="$1"
    local path="$2"

    if ! state_exists; then
        error "State file not found"
        exit 2
    fi

    local full_path="$PROJECT_ROOT/$path"
    if [[ ! -f "$full_path" ]]; then
        error "Artifact not found: $path"
        exit 1
    fi

    backup_state

    local checksum
    checksum=$(calculate_checksum "$full_path")

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local tmp_file="${STATE_FILE}.tmp"
    jq --arg name "$name" --arg path "$path" --arg checksum "$checksum" --arg ts "$timestamp" \
        '.timestamps.last_activity = $ts | .artifacts[$name] = {path: $path, checksum: ("sha256:" + $checksum), added: $ts}' \
        "$STATE_FILE" > "$tmp_file"
    mv "$tmp_file" "$STATE_FILE"

    log "Added artifact $name: $path (sha256:${checksum:0:12}...)"
    echo "{\"name\": \"$name\", \"checksum\": \"sha256:$checksum\"}"
}

# =============================================================================
# Validate Artifacts
# =============================================================================

validate_artifacts() {
    if ! state_exists; then
        error "State file not found"
        exit 2
    fi

    local drift_items=()
    local all_valid=true

    # Read artifacts from state
    local artifacts
    artifacts=$(jq -r '.artifacts | to_entries[] | "\(.key)|\(.value.path)|\(.value.checksum)"' "$STATE_FILE" 2>/dev/null)

    while IFS='|' read -r name path checksum; do
        [[ -z "$name" ]] && continue

        local full_path="$PROJECT_ROOT/$path"

        if [[ ! -f "$full_path" ]]; then
            log "Artifact missing: $name ($path)"
            drift_items+=("{\"name\": \"$name\", \"path\": \"$path\", \"status\": \"missing\"}")
            all_valid=false
            continue
        fi

        local current_checksum
        current_checksum="sha256:$(calculate_checksum "$full_path")"

        if [[ "$current_checksum" != "$checksum" ]]; then
            log "Artifact modified: $name ($path)"
            drift_items+=("{\"name\": \"$name\", \"path\": \"$path\", \"status\": \"modified\", \"expected\": \"$checksum\", \"actual\": \"$current_checksum\"}")
            all_valid=false
        fi
    done <<< "$artifacts"

    # Build result JSON
    local drift_json="[]"
    if [[ ${#drift_items[@]} -gt 0 ]]; then
        drift_json=$(printf '%s\n' "${drift_items[@]}" | jq -s '.')
    fi

    jq -n \
        --argjson valid "$all_valid" \
        --argjson drift "$drift_json" \
        '{valid: $valid, drift: $drift}'
}

# =============================================================================
# Save Interrupt
# =============================================================================

save_interrupt() {
    if ! state_exists; then
        log "No state file to save"
        echo '{"saved": false}'
        return 0
    fi

    backup_state

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local tmp_file="${STATE_FILE}.tmp"
    jq --arg ts "$timestamp" \
        '.state = "INTERRUPTED" | .timestamps.interrupted = $ts | .timestamps.last_activity = $ts' \
        "$STATE_FILE" > "$tmp_file"
    mv "$tmp_file" "$STATE_FILE"

    log "State saved as INTERRUPTED"
    echo '{"saved": true, "state": "INTERRUPTED"}'
}

# =============================================================================
# Cleanup
# =============================================================================

cleanup() {
    rm -f "$STATE_FILE" "$STATE_BACKUP" "${STATE_FILE}.tmp"
    log "State files cleaned up"
    echo '{"cleaned": true}'
}

# =============================================================================
# Main
# =============================================================================

usage() {
    cat <<EOF
Usage: simstim-state.sh <command> [options]

Commands:
  init [--from <phase>]         Create initial state file
  get <field>                   Get field value (dot notation supported)
  update <field> <value>        Update field atomically
  update-phase <phase> <status> Update phase status (pending|in_progress|completed|skipped|incomplete)
  add-artifact <name> <path>    Add artifact with SHA256 checksum
  validate-artifacts            Compare checksums, return drift JSON
  save-interrupt                Mark state as interrupted
  cleanup                       Remove state file and backup
  check-version                 Verify schema version

Exit codes:
  0 - Success
  1 - General error
  2 - State file not found
  3 - Invalid arguments
  4 - Version mismatch
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
        init)
            init_state "$@"
            ;;
        get)
            if [[ $# -lt 1 ]]; then
                error "Usage: get <field>"
                exit 3
            fi
            get_field "$1"
            ;;
        update)
            if [[ $# -lt 2 ]]; then
                error "Usage: update <field> <value>"
                exit 3
            fi
            update_field "$1" "$2"
            ;;
        update-phase)
            if [[ $# -lt 2 ]]; then
                error "Usage: update-phase <phase> <status>"
                exit 3
            fi
            update_phase "$1" "$2"
            ;;
        add-artifact)
            if [[ $# -lt 2 ]]; then
                error "Usage: add-artifact <name> <path>"
                exit 3
            fi
            add_artifact "$1" "$2"
            ;;
        validate-artifacts)
            validate_artifacts
            ;;
        save-interrupt)
            save_interrupt
            ;;
        cleanup)
            cleanup
            ;;
        check-version)
            check_version
            ;;
        -h|--help)
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
