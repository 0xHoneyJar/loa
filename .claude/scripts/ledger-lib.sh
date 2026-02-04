#!/usr/bin/env bash
# =============================================================================
# Loa Sprint Ledger - Library Functions
# =============================================================================
# Provides append-only sprint ledger management for global sprint numbering
# and cycle lifecycle management across multiple /plan-and-analyze cycles.
#
# Usage:
#   source "$(dirname "$0")/ledger-lib.sh"
#
# Sources: sdd.md:§5.1 (ledger-lib.sh), prd.md (Sprint Ledger requirements)
# =============================================================================

set -euo pipefail

# =============================================================================
# Path Resolution
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

# =============================================================================
# Exit Codes (per SDD §6.2)
# =============================================================================
readonly LEDGER_OK=0
readonly LEDGER_ERROR=1
readonly LEDGER_NOT_FOUND=2
readonly LEDGER_NO_ACTIVE_CYCLE=3
readonly LEDGER_SPRINT_NOT_FOUND=4
readonly LEDGER_VALIDATION_ERROR=5

# =============================================================================
# Color Support
# =============================================================================
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# =============================================================================
# Path Functions (delegate to path-lib.sh)
# =============================================================================

# Note: get_ledger_path() is now provided by path-lib.sh via bootstrap.sh
# The function returns the full path based on configuration

# Check if ledger exists
# Returns: 0 if exists, 1 if not
ledger_exists() {
    local ledger_path
    ledger_path=$(get_ledger_path)
    [[ -f "$ledger_path" ]]
}

# =============================================================================
# Date Handling (GNU/BSD compatible)
# =============================================================================

# Get current ISO 8601 timestamp
# Returns: ISO 8601 timestamp (e.g., "2026-01-17T10:00:00Z")
now_iso() {
    if date --version &>/dev/null 2>&1; then
        # GNU date
        date -u +"%Y-%m-%dT%H:%M:%SZ"
    else
        # BSD date (macOS)
        date -u +"%Y-%m-%dT%H:%M:%SZ"
    fi
}

# Get current date for archive slug
# Returns: Date string (e.g., "2026-01-17")
now_date() {
    date +"%Y-%m-%d"
}

# =============================================================================
# Backup and Recovery Functions
# =============================================================================

# Create backup before write operations
# Location: grimoires/loa/ledger.json.bak
ensure_ledger_backup() {
    local ledger_path
    ledger_path=$(get_ledger_path)

    if [[ -f "$ledger_path" ]]; then
        cp "$ledger_path" "${ledger_path}.bak"
    fi
}

# Recover from backup
# Returns: 0 on success, 1 if no backup, 2 if backup is invalid
recover_from_backup() {
    local ledger_path
    ledger_path=$(get_ledger_path)
    local backup_path="${ledger_path}.bak"

    if [[ ! -f "$backup_path" ]]; then
        echo "No backup found" >&2
        return 1
    fi

    # SECURITY (MED-008): Validate backup is valid JSON before restore
    if ! jq empty "$backup_path" 2>/dev/null; then
        echo "ERROR: Backup file is not valid JSON, refusing to restore" >&2
        return 2
    fi

    # Validate backup has required fields
    local version
    version=$(jq -r '.version // "missing"' "$backup_path" 2>/dev/null)
    if [[ "$version" == "missing" ]]; then
        echo "ERROR: Backup missing required 'version' field, refusing to restore" >&2
        return 2
    fi

    # Use atomic write pattern for recovery too
    local tmp_file="${ledger_path}.recover.$$"
    cp "$backup_path" "$tmp_file"
    mv "$tmp_file" "$ledger_path"

    echo "Recovered ledger from backup"
    return 0
}

# =============================================================================
# Internal Write Function (HIGH-001: Atomic writes with flock)
# =============================================================================

# Lock file timeout in seconds
readonly LEDGER_LOCK_TIMEOUT=5

# Write ledger JSON with exclusive locking (internal use)
# Args: $1 - JSON content
# Returns: 0 on success, 1 on lock failure
_write_ledger() {
    local content="$1"
    local ledger_path
    ledger_path=$(get_ledger_path)
    local lock_file="${ledger_path}.lock"

    # Ensure parent directory exists
    mkdir -p "$(dirname "$ledger_path")"

    # SECURITY (HIGH-001): Acquire exclusive lock with timeout
    # This prevents race conditions in concurrent operations
    exec 9>"$lock_file"
    if ! flock -w "$LEDGER_LOCK_TIMEOUT" 9; then
        echo "ERROR: Could not acquire ledger lock within ${LEDGER_LOCK_TIMEOUT}s" >&2
        exec 9>&-
        return 1
    fi

    # Backup before write
    ensure_ledger_backup

    # Update last_updated timestamp
    local updated_content
    updated_content=$(echo "$content" | jq --arg ts "$(now_iso)" '.last_updated = $ts')

    # SECURITY (HIGH-001): Atomic write via temp file + mv
    local tmp_file="${ledger_path}.tmp.$$"
    if ! echo "$updated_content" > "$tmp_file"; then
        echo "ERROR: Failed to write temp file" >&2
        rm -f "$tmp_file"
        flock -u 9
        exec 9>&-
        return 1
    fi

    # Atomic move (same filesystem guarantees atomicity)
    if ! mv "$tmp_file" "$ledger_path"; then
        echo "ERROR: Failed to move temp file to ledger" >&2
        rm -f "$tmp_file"
        flock -u 9
        exec 9>&-
        return 1
    fi

    # Release lock
    flock -u 9
    exec 9>&-
    return 0
}

# =============================================================================
# Initialization Functions
# =============================================================================

# Initialize new ledger
# Creates new ledger.json if not exists
# Returns: 0 on success, 1 if already exists
init_ledger() {
    local ledger_path
    ledger_path=$(get_ledger_path)

    if [[ -f "$ledger_path" ]]; then
        echo "Ledger already exists at $ledger_path" >&2
        return $LEDGER_ERROR
    fi

    # Ensure directory exists
    mkdir -p "$(dirname "$ledger_path")"

    local now
    now=$(now_iso)

    # Create initial ledger
    local ledger_json
    ledger_json=$(cat <<EOF
{
  "version": 1,
  "created": "$now",
  "last_updated": "$now",
  "next_sprint_number": 1,
  "active_cycle": null,
  "cycles": []
}
EOF
)

    echo "$ledger_json" > "$ledger_path"
    echo "Initialized ledger at $ledger_path"
    return $LEDGER_OK
}

# Initialize ledger from existing project
# Scans a2a/sprint-* directories to set next_sprint_number
# Returns: 0 on success, 1 on error
init_ledger_from_existing() {
    local ledger_path
    ledger_path=$(get_ledger_path)

    if [[ -f "$ledger_path" ]]; then
        echo "Ledger already exists at $ledger_path" >&2
        return $LEDGER_ERROR
    fi

    # Find highest existing sprint number
    local max_sprint=0
    local grimoire_dir
    grimoire_dir=$(get_grimoire_dir)
    local a2a_dir="${grimoire_dir}/a2a"

    if [[ -d "$a2a_dir" ]]; then
        for dir in "$a2a_dir"/sprint-*; do
            if [[ -d "$dir" ]]; then
                local sprint_num
                sprint_num=$(basename "$dir" | sed 's/sprint-//')
                if [[ "$sprint_num" =~ ^[0-9]+$ ]] && [[ "$sprint_num" -gt "$max_sprint" ]]; then
                    max_sprint=$sprint_num
                fi
            fi
        done
    fi

    local next_sprint=$((max_sprint + 1))

    # Ensure directory exists
    mkdir -p "$(dirname "$ledger_path")"

    local now
    now=$(now_iso)

    # Create ledger with detected sprint number
    local ledger_json
    ledger_json=$(cat <<EOF
{
  "version": 1,
  "created": "$now",
  "last_updated": "$now",
  "next_sprint_number": $next_sprint,
  "active_cycle": null,
  "cycles": []
}
EOF
)

    echo "$ledger_json" > "$ledger_path"
    echo "Initialized ledger from existing project"
    echo "Detected $max_sprint existing sprints, next sprint number: $next_sprint"
    return $LEDGER_OK
}

# =============================================================================
# Cycle Management Functions
# =============================================================================

# Get active cycle ID
# Returns: Cycle ID (e.g., "cycle-002") or "null" if none active
get_active_cycle() {
    local ledger_path
    ledger_path=$(get_ledger_path)

    if ! ledger_exists; then
        echo "null"
        return $LEDGER_NOT_FOUND
    fi

    jq -r '.active_cycle // "null"' "$ledger_path"
}

# Generate next cycle ID
# Returns: Next cycle ID (e.g., "cycle-001", "cycle-002")
_next_cycle_id() {
    local ledger_path
    ledger_path=$(get_ledger_path)

    local count
    count=$(jq '.cycles | length' "$ledger_path")

    printf "cycle-%03d" $((count + 1))
}

# Create new cycle
# Args: $1 - Human-readable label for the cycle
# Returns: New cycle ID
create_cycle() {
    local label="$1"
    local ledger_path
    ledger_path=$(get_ledger_path)

    if ! ledger_exists; then
        echo "Ledger not found. Run init_ledger first." >&2
        return $LEDGER_NOT_FOUND
    fi

    # Check if active cycle exists
    local active
    active=$(get_active_cycle)
    if [[ "$active" != "null" ]]; then
        echo "Active cycle already exists: $active. Archive it first." >&2
        return $LEDGER_ERROR
    fi

    local cycle_id
    cycle_id=$(_next_cycle_id)

    local now
    now=$(now_iso)

    # Get grimoire directory for PRD path
    local grimoire_dir
    grimoire_dir=$(get_grimoire_dir)
    local prd_path="${grimoire_dir}/prd.md"

    # Create cycle object
    local cycle_json
    cycle_json=$(cat <<EOF
{
  "id": "$cycle_id",
  "label": "$label",
  "status": "active",
  "created": "$now",
  "archived": null,
  "archive_path": null,
  "prd": "$prd_path",
  "sdd": null,
  "sprints": []
}
EOF
)

    # Add cycle and set as active
    local ledger_content
    ledger_content=$(jq --argjson cycle "$cycle_json" --arg id "$cycle_id" \
        '.cycles += [$cycle] | .active_cycle = $id' "$ledger_path")

    _write_ledger "$ledger_content"

    echo "$cycle_id"
    return $LEDGER_OK
}

# Get cycle by ID
# Args: $1 - Cycle ID
# Returns: JSON object of cycle or "null"
get_cycle_by_id() {
    local cycle_id="$1"
    local ledger_path
    ledger_path=$(get_ledger_path)

    if ! ledger_exists; then
        echo "null"
        return $LEDGER_NOT_FOUND
    fi

    jq -r --arg id "$cycle_id" '.cycles[] | select(.id == $id) // "null"' "$ledger_path"
}

# Update cycle field
# Args: $1 - Cycle ID, $2 - Field name, $3 - New value
update_cycle_field() {
    local cycle_id="$1"
    local field="$2"
    local value="$3"
    local ledger_path
    ledger_path=$(get_ledger_path)

    if ! ledger_exists; then
        return $LEDGER_NOT_FOUND
    fi

    local ledger_content
    ledger_content=$(jq --arg id "$cycle_id" --arg field "$field" --arg value "$value" \
        '(.cycles[] | select(.id == $id))[$field] = $value' "$ledger_path")

    _write_ledger "$ledger_content"
    return $LEDGER_OK
}

# =============================================================================
# Sprint Management Functions
# =============================================================================

# Get next sprint number (does NOT increment)
# Returns: Next global sprint number (integer)
get_next_sprint_number() {
    local ledger_path
    ledger_path=$(get_ledger_path)

    if ! ledger_exists; then
        echo "1"
        return $LEDGER_NOT_FOUND
    fi

    jq -r '.next_sprint_number' "$ledger_path"
}

# Allocate sprint number (increments and returns)
# This is atomic: read + increment + write
# Returns: Allocated sprint number (integer)
allocate_sprint_number() {
    local ledger_path
    ledger_path=$(get_ledger_path)

    if ! ledger_exists; then
        echo "1"
        return $LEDGER_NOT_FOUND
    fi

    local current
    current=$(jq -r '.next_sprint_number' "$ledger_path")

    # Increment in ledger
    local ledger_content
    ledger_content=$(jq '.next_sprint_number += 1' "$ledger_path")

    _write_ledger "$ledger_content"

    echo "$current"
    return $LEDGER_OK
}

# Add sprint to active cycle
# Args: $1 - Local label (e.g., "sprint-1")
# Returns: Global sprint ID (integer)
add_sprint() {
    local local_label="$1"
    local ledger_path
    ledger_path=$(get_ledger_path)

    if ! ledger_exists; then
        echo "Ledger not found" >&2
        return $LEDGER_NOT_FOUND
    fi

    local active_cycle
    active_cycle=$(get_active_cycle)

    if [[ "$active_cycle" == "null" ]]; then
        echo "No active cycle" >&2
        return $LEDGER_NO_ACTIVE_CYCLE
    fi

    # Allocate global ID
    local global_id
    global_id=$(allocate_sprint_number)

    local now
    now=$(now_iso)

    # Create sprint object
    local sprint_json
    sprint_json=$(cat <<EOF
{
  "global_id": $global_id,
  "local_label": "$local_label",
  "status": "planned",
  "created": "$now",
  "completed": null
}
EOF
)

    # Add sprint to active cycle
    local ledger_content
    ledger_content=$(jq --arg cycle_id "$active_cycle" --argjson sprint "$sprint_json" \
        '(.cycles[] | select(.id == $cycle_id)).sprints += [$sprint]' "$ledger_path")

    _write_ledger "$ledger_content"

    echo "$global_id"
    return $LEDGER_OK
}

# Resolve sprint (local label to global ID)
# Args: $1 - Local label (e.g., "sprint-1") or global (e.g., "sprint-47")
# Returns: Global sprint ID or "UNRESOLVED" if not found
resolve_sprint() {
    local input="$1"
    local ledger_path
    ledger_path=$(get_ledger_path)

    if ! ledger_exists; then
        # Legacy mode: return input as-is (strip prefix)
        echo "${input#sprint-}"
        return $LEDGER_OK
    fi

    local active_cycle
    active_cycle=$(get_active_cycle)

    if [[ "$active_cycle" == "null" ]]; then
        # No active cycle, return input as-is
        echo "${input#sprint-}"
        return $LEDGER_OK
    fi

    # Extract the number/label part
    local label="$input"

    # Check if it's already a global ID (high number or matches global)
    local sprint_num="${input#sprint-}"

    # First try to find by local_label in active cycle
    local global_id
    global_id=$(jq -r --arg cycle_id "$active_cycle" --arg label "$input" \
        '(.cycles[] | select(.id == $cycle_id)).sprints[] | select(.local_label == $label) | .global_id // "UNRESOLVED"' \
        "$ledger_path" 2>/dev/null || echo "UNRESOLVED")

    if [[ "$global_id" != "UNRESOLVED" ]] && [[ -n "$global_id" ]]; then
        echo "$global_id"
        return $LEDGER_OK
    fi

    # Check if input is a global ID (exists anywhere in ledger)
    if [[ "$sprint_num" =~ ^[0-9]+$ ]]; then
        local exists
        exists=$(jq -r --argjson num "$sprint_num" \
            '[.cycles[].sprints[] | select(.global_id == $num)] | length' \
            "$ledger_path" 2>/dev/null || echo "0")

        if [[ "$exists" -gt 0 ]]; then
            echo "$sprint_num"
            return $LEDGER_OK
        fi
    fi

    echo "UNRESOLVED"
    return $LEDGER_SPRINT_NOT_FOUND
}

# Update sprint status
# Args: $1 - Global sprint ID, $2 - New status (planned, in_progress, completed)
update_sprint_status() {
    local global_id="$1"
    local status="$2"
    local ledger_path
    ledger_path=$(get_ledger_path)

    if ! ledger_exists; then
        return $LEDGER_NOT_FOUND
    fi

    local now
    now=$(now_iso)

    local ledger_content
    if [[ "$status" == "completed" ]]; then
        # Set completed timestamp
        ledger_content=$(jq --argjson id "$global_id" --arg status "$status" --arg completed "$now" \
            '(.cycles[].sprints[] | select(.global_id == $id)) |= (.status = $status | .completed = $completed)' \
            "$ledger_path")
    else
        ledger_content=$(jq --argjson id "$global_id" --arg status "$status" \
            '(.cycles[].sprints[] | select(.global_id == $id)).status = $status' \
            "$ledger_path")
    fi

    _write_ledger "$ledger_content"
    return $LEDGER_OK
}

# Get sprint directory path
# Args: $1 - Global sprint ID
# Returns: Path to a2a directory (e.g., "grimoires/loa/a2a/sprint-3")
get_sprint_directory() {
    local global_id="$1"
    local grimoire_dir
    grimoire_dir=$(get_grimoire_dir)
    echo "${grimoire_dir}/a2a/sprint-${global_id}"
}

# =============================================================================
# Query Functions
# =============================================================================

# Get ledger status summary
# Returns: JSON object with summary
get_ledger_status() {
    local ledger_path
    ledger_path=$(get_ledger_path)

    if ! ledger_exists; then
        echo '{"error": "Ledger not found"}'
        return $LEDGER_NOT_FOUND
    fi

    local active_cycle
    active_cycle=$(jq -r '.active_cycle // "null"' "$ledger_path")

    local active_label="null"
    local current_sprint="null"
    local current_sprint_local="null"

    if [[ "$active_cycle" != "null" ]]; then
        active_label=$(jq -r --arg id "$active_cycle" \
            '(.cycles[] | select(.id == $id)).label // "null"' "$ledger_path")

        # Get latest sprint in active cycle
        current_sprint=$(jq -r --arg id "$active_cycle" \
            '(.cycles[] | select(.id == $id)).sprints | last | .global_id // "null"' "$ledger_path")
        current_sprint_local=$(jq -r --arg id "$active_cycle" \
            '(.cycles[] | select(.id == $id)).sprints | last | .local_label // "null"' "$ledger_path")
    fi

    local next_sprint
    next_sprint=$(jq -r '.next_sprint_number' "$ledger_path")

    local total_cycles
    total_cycles=$(jq '.cycles | length' "$ledger_path")

    local archived_cycles
    archived_cycles=$(jq '[.cycles[] | select(.status == "archived")] | length' "$ledger_path")

    cat <<EOF
{
  "active_cycle": $(echo "$active_cycle" | jq -R .),
  "active_cycle_label": $(echo "$active_label" | jq -R .),
  "current_sprint": $current_sprint,
  "current_sprint_local": $(echo "$current_sprint_local" | jq -R .),
  "next_sprint_number": $next_sprint,
  "total_cycles": $total_cycles,
  "archived_cycles": $archived_cycles
}
EOF
    return $LEDGER_OK
}

# Get cycle history
# Returns: JSON array of all cycles with summary info
get_cycle_history() {
    local ledger_path
    ledger_path=$(get_ledger_path)

    if ! ledger_exists; then
        echo '[]'
        return $LEDGER_NOT_FOUND
    fi

    jq '.cycles | map({
        id: .id,
        label: .label,
        status: .status,
        created: .created,
        archived: .archived,
        sprint_count: (.sprints | length)
    })' "$ledger_path"
}

# =============================================================================
# Validation Functions
# =============================================================================

# Validate ledger against schema
# Returns: 0 if valid, LEDGER_VALIDATION_ERROR if invalid
validate_ledger() {
    local ledger_path
    ledger_path=$(get_ledger_path)

    if ! ledger_exists; then
        echo "Ledger not found" >&2
        return $LEDGER_NOT_FOUND
    fi

    # Check if valid JSON
    if ! jq empty "$ledger_path" 2>/dev/null; then
        echo "Invalid JSON" >&2
        return $LEDGER_VALIDATION_ERROR
    fi

    # Check required fields
    local version
    version=$(jq -r '.version // "missing"' "$ledger_path")
    if [[ "$version" == "missing" ]]; then
        echo "Missing required field: version" >&2
        return $LEDGER_VALIDATION_ERROR
    fi

    local next_sprint
    next_sprint=$(jq -r '.next_sprint_number // "missing"' "$ledger_path")
    if [[ "$next_sprint" == "missing" ]]; then
        echo "Missing required field: next_sprint_number" >&2
        return $LEDGER_VALIDATION_ERROR
    fi

    # Check next_sprint_number is positive integer
    if ! [[ "$next_sprint" =~ ^[1-9][0-9]*$ ]] && [[ "$next_sprint" != "1" ]]; then
        echo "next_sprint_number must be positive integer, got: $next_sprint" >&2
        return $LEDGER_VALIDATION_ERROR
    fi

    # Check cycles is array
    local cycles_type
    cycles_type=$(jq -r '.cycles | type' "$ledger_path")
    if [[ "$cycles_type" != "array" ]]; then
        echo "cycles must be array, got: $cycles_type" >&2
        return $LEDGER_VALIDATION_ERROR
    fi

    echo "Ledger is valid"
    return $LEDGER_OK
}

# =============================================================================
# Archive Functions (Sprint 6)
# =============================================================================

# Archive active cycle
# Args: $1 - Slug for archive directory (e.g., "mvp-complete")
# Returns: Archive path
archive_cycle() {
    local slug="$1"
    local ledger_path
    ledger_path=$(get_ledger_path)

    if ! ledger_exists; then
        echo "Ledger not found" >&2
        return $LEDGER_NOT_FOUND
    fi

    local active_cycle
    active_cycle=$(get_active_cycle)

    if [[ "$active_cycle" == "null" ]]; then
        echo "No active cycle to archive" >&2
        return $LEDGER_NO_ACTIVE_CYCLE
    fi

    local now_date_str
    now_date_str=$(now_date)
    local grimoire_dir
    grimoire_dir=$(get_grimoire_dir)
    local archive_dir
    archive_dir=$(get_archive_dir)
    local archive_path="${archive_dir}/${now_date_str}-${slug}"

    # Create archive directory
    mkdir -p "$archive_path/a2a"

    # Copy current artifacts
    [[ -f "${grimoire_dir}/prd.md" ]] && cp "${grimoire_dir}/prd.md" "$archive_path/"
    [[ -f "${grimoire_dir}/sdd.md" ]] && cp "${grimoire_dir}/sdd.md" "$archive_path/"
    [[ -f "${grimoire_dir}/sprint.md" ]] && cp "${grimoire_dir}/sprint.md" "$archive_path/"

    # Copy sprint directories for this cycle
    local sprints
    sprints=$(jq -r --arg id "$active_cycle" \
        '(.cycles[] | select(.id == $id)).sprints[].global_id' "$ledger_path")

    for sprint_id in $sprints; do
        local sprint_dir="${grimoire_dir}/a2a/sprint-${sprint_id}"
        if [[ -d "$sprint_dir" ]]; then
            cp -r "$sprint_dir" "$archive_path/a2a/"
        fi
    done

    local now
    now=$(now_iso)

    # Update ledger
    local ledger_content
    ledger_content=$(jq --arg id "$active_cycle" --arg archived "$now" --arg path "$archive_path" \
        '(.cycles[] | select(.id == $id)) |= (.status = "archived" | .archived = $archived | .archive_path = $path) | .active_cycle = null' \
        "$ledger_path")

    _write_ledger "$ledger_content"

    echo "$archive_path"
    return $LEDGER_OK
}

# =============================================================================
# Safe Resolution Function (with fallback)
# =============================================================================

# Resolve sprint with fallback to legacy behavior
# Args: $1 - Sprint input (e.g., "sprint-1")
# Returns: Global sprint ID (always succeeds)
resolve_sprint_safe() {
    local input="$1"

    if ! ledger_exists; then
        # Legacy: return input as-is
        echo "${input#sprint-}"
        return 0
    fi

    local result
    result=$(resolve_sprint "$input" 2>/dev/null) || {
        # Fallback on error
        echo "${input#sprint-}"
        return 0
    }

    if [[ "$result" == "UNRESOLVED" ]]; then
        # Fallback for unresolved
        echo "${input#sprint-}"
        return 0
    fi

    echo "$result"
}
