#!/usr/bin/env bash
# =============================================================================
# flatline-snapshot.sh - Snapshot manager for Flatline Protocol
# =============================================================================
# Version: 1.0.0
# Part of: Autonomous Flatline Integration v1.22.0
#
# Creates and manages pre-integration snapshots for rollback capability.
# Supports git transactional semantics, reference counting, and storage quota.
#
# Usage:
#   flatline-snapshot.sh create <document> --run-id <id> [options]
#   flatline-snapshot.sh restore <snapshot-id> [--force]
#   flatline-snapshot.sh list [--run-id <id>]
#   flatline-snapshot.sh cleanup [--max-age <days>] [--dry-run]
#   flatline-snapshot.sh status
#
# Exit codes:
#   0 - Success
#   1 - Snapshot creation failed
#   2 - Snapshot not found
#   3 - Invalid arguments
#   4 - Divergence detected (hash mismatch)
#   5 - Quota exceeded
#   6 - Secret detected (when git_commit enabled)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
SNAPSHOT_DIR="$PROJECT_ROOT/.flatline/snapshots"
REFS_DIR="$SNAPSHOT_DIR/.refs"
TRAJECTORY_DIR="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"

# Component scripts
LOCK_SCRIPT="$SCRIPT_DIR/flatline-lock.sh"

# Default configuration
DEFAULT_MAX_AGE_DAYS=7
DEFAULT_MAX_COUNT=100
DEFAULT_MAX_BYTES=$((100 * 1024 * 1024))  # 100MB
DEFAULT_ON_QUOTA="fail"

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[flatline-snapshot] $*" >&2
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
    local log_file="$TRAJECTORY_DIR/flatline-snapshot-$date_str.jsonl"

    touch "$log_file"
    chmod 600 "$log_file"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg type "flatline_snapshot" \
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

is_snapshots_enabled() {
    local enabled
    enabled=$(read_config '.autonomous_mode.snapshots.enabled' 'true')
    [[ "$enabled" == "true" ]]
}

get_max_age_days() {
    read_config '.autonomous_mode.snapshots.max_age_days' "$DEFAULT_MAX_AGE_DAYS"
}

is_git_commit_enabled() {
    local enabled
    enabled=$(read_config '.autonomous_mode.snapshots.git_commit' 'false')
    [[ "$enabled" == "true" ]]
}

is_git_hooks_enabled() {
    local enabled
    enabled=$(read_config '.autonomous_mode.snapshots.git_commit_with_hooks' 'true')
    [[ "$enabled" == "true" ]]
}

is_secret_scanning_enabled() {
    local enabled
    enabled=$(read_config '.autonomous_mode.snapshots.secret_scanning' 'true')
    [[ "$enabled" == "true" ]]
}

get_max_count() {
    read_config '.autonomous_mode.snapshots.max_count' "$DEFAULT_MAX_COUNT"
}

get_max_bytes() {
    read_config '.autonomous_mode.snapshots.max_bytes' "$DEFAULT_MAX_BYTES"
}

get_on_quota() {
    read_config '.autonomous_mode.snapshots.on_quota' "$DEFAULT_ON_QUOTA"
}

# =============================================================================
# Directory Management
# =============================================================================

ensure_snapshot_dir() {
    if [[ ! -d "$SNAPSHOT_DIR" ]]; then
        (umask 077 && mkdir -p "$SNAPSHOT_DIR")
        log "Created snapshot directory: $SNAPSHOT_DIR"
    fi
    if [[ ! -d "$REFS_DIR" ]]; then
        (umask 077 && mkdir -p "$REFS_DIR")
    fi
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
# Storage Quota Management
# =============================================================================

get_storage_stats() {
    ensure_snapshot_dir

    local count=0
    local total_bytes=0

    while IFS= read -r -d '' file; do
        ((count++))
        local size
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
        total_bytes=$((total_bytes + size))
    done < <(find "$SNAPSHOT_DIR" -name "*.snapshot" -type f -print0 2>/dev/null)

    local max_count max_bytes
    max_count=$(get_max_count)
    max_bytes=$(get_max_bytes)

    jq -n \
        --argjson count "$count" \
        --argjson total_bytes "$total_bytes" \
        --argjson max_count "$max_count" \
        --argjson max_bytes "$max_bytes" \
        '{
            count: $count,
            total_bytes: $total_bytes,
            max_count: $max_count,
            max_bytes: $max_bytes,
            count_percent: (if $max_count > 0 then ($count * 100 / $max_count) else 0 end),
            bytes_percent: (if $max_bytes > 0 then ($total_bytes * 100 / $max_bytes) else 0 end)
        }'
}

check_quota() {
    local stats
    stats=$(get_storage_stats)

    local count_percent bytes_percent
    count_percent=$(echo "$stats" | jq -r '.count_percent')
    bytes_percent=$(echo "$stats" | jq -r '.bytes_percent')

    # Warn at thresholds
    if [[ $count_percent -ge 80 ]] || [[ $bytes_percent -ge 80 ]]; then
        warn "Storage quota at ${count_percent}% count, ${bytes_percent}% bytes"
        log_trajectory "quota_warning" "$stats"
    fi

    if [[ $count_percent -ge 90 ]] || [[ $bytes_percent -ge 90 ]]; then
        warn "Storage quota critical: ${count_percent}% count, ${bytes_percent}% bytes"
        log_trajectory "quota_critical" "$stats"
    fi

    # Check if over quota
    if [[ $count_percent -ge 100 ]] || [[ $bytes_percent -ge 100 ]]; then
        local on_quota
        on_quota=$(get_on_quota)

        if [[ "$on_quota" == "purge_oldest" ]]; then
            warn "Quota exceeded, purging oldest snapshots"
            purge_oldest_snapshots 10  # Purge 10 oldest
            return 0
        else
            error "Storage quota exceeded (${count_percent}% count, ${bytes_percent}% bytes)"
            log_trajectory "quota_exceeded" "$stats"
            return 5
        fi
    fi

    return 0
}

purge_oldest_snapshots() {
    local count="${1:-10}"

    local purged=0
    while IFS= read -r -d '' snapshot; do
        if [[ $purged -ge $count ]]; then
            break
        fi

        local meta_file="${snapshot%.snapshot}.meta"
        local refs_file
        refs_file=$(get_snapshot_refs_file "$snapshot")

        # Check if snapshot has active references
        if [[ -f "$refs_file" ]]; then
            local ref_count
            ref_count=$(wc -l < "$refs_file" 2>/dev/null || echo "0")
            if [[ $ref_count -gt 0 ]]; then
                log "Skipping referenced snapshot: $snapshot ($ref_count refs)"
                continue
            fi
        fi

        rm -f "$snapshot" "$meta_file" "$refs_file"
        ((purged++))
        log "Purged old snapshot: $snapshot"
    done < <(find "$SNAPSHOT_DIR" -name "*.snapshot" -type f -print0 2>/dev/null | \
             xargs -0 -I{} bash -c 'echo "$(stat -c %Y "{}" 2>/dev/null || stat -f %m "{}" 2>/dev/null) {}"' | \
             sort -n | cut -d' ' -f2- | tr '\n' '\0')

    log "Purged $purged snapshots"
}

get_snapshot_refs_file() {
    local snapshot="$1"
    local basename
    basename=$(basename "$snapshot" .snapshot)
    echo "$REFS_DIR/${basename}.refs"
}

# =============================================================================
# Secret Scanning
# =============================================================================

scan_for_secrets() {
    local file="$1"

    if ! is_secret_scanning_enabled; then
        return 0
    fi

    log "Scanning for secrets: $file"

    # Try gitleaks first
    if command -v gitleaks &> /dev/null; then
        if ! gitleaks detect --source "$file" --no-git 2>/dev/null; then
            error "Secret detected by gitleaks in: $file"
            return 6
        fi
        return 0
    fi

    # Try trufflehog
    if command -v trufflehog &> /dev/null; then
        if trufflehog filesystem "$file" --no-update 2>/dev/null | grep -q "Found"; then
            error "Secret detected by trufflehog in: $file"
            return 6
        fi
        return 0
    fi

    # Fallback: basic pattern matching
    log "Using basic secret scanning (gitleaks/trufflehog not available)"
    local patterns=(
        'sk-[a-zA-Z0-9]{20,}'                    # OpenAI API key
        'ghp_[a-zA-Z0-9]{36}'                    # GitHub PAT
        'gho_[a-zA-Z0-9]{36}'                    # GitHub OAuth
        'AKIA[0-9A-Z]{16}'                       # AWS Access Key
        'AIza[0-9A-Za-z_-]{35}'                  # Google API Key
        '-----BEGIN (RSA |EC |DSA )?PRIVATE KEY' # Private keys
        'xox[baprs]-[0-9a-zA-Z]{10,}'            # Slack tokens
    )

    for pattern in "${patterns[@]}"; do
        if grep -qE "$pattern" "$file" 2>/dev/null; then
            error "Potential secret pattern detected in: $file"
            error "Pattern: $pattern"
            return 6
        fi
    done

    return 0
}

# =============================================================================
# Snapshot Operations
# =============================================================================

create_snapshot() {
    local document="$1"
    local run_id="$2"
    local integration_id="${3:-}"

    if ! is_snapshots_enabled; then
        log "Snapshots disabled, skipping"
        echo "{\"status\": \"disabled\"}"
        return 0
    fi

    ensure_snapshot_dir

    # Check quota
    if ! check_quota; then
        return 5
    fi

    # Validate document exists
    if [[ ! -f "$document" ]]; then
        error "Document not found: $document"
        return 3
    fi

    # Security: Validate path is within project
    local realpath_doc
    realpath_doc=$(realpath "$document" 2>/dev/null) || {
        error "Cannot resolve document path: $document"
        return 3
    }
    if [[ ! "$realpath_doc" == "$PROJECT_ROOT"* ]]; then
        error "Document must be within project directory"
        return 3
    fi

    # Generate snapshot ID
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local hash_short
    hash_short=$(calculate_hash "$document" | head -c 8)
    local snapshot_id="${timestamp}_${hash_short}"

    # Create paths
    local snapshot_file="$SNAPSHOT_DIR/${snapshot_id}.snapshot"
    local meta_file="$SNAPSHOT_DIR/${snapshot_id}.meta"
    local temp_file
    temp_file=$(mktemp)

    # Create snapshot (atomic copy via temp file)
    cp "$document" "$temp_file"
    chmod 600 "$temp_file"
    mv "$temp_file" "$snapshot_file"

    # Calculate full hash
    local full_hash
    full_hash=$(calculate_hash "$snapshot_file")

    # Create metadata
    local doc_relative
    doc_relative="${document#$PROJECT_ROOT/}"

    jq -n \
        --arg snapshot_id "$snapshot_id" \
        --arg document "$doc_relative" \
        --arg run_id "$run_id" \
        --arg integration_id "${integration_id:-}" \
        --arg hash "$full_hash" \
        --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson size "$(stat -f%z "$snapshot_file" 2>/dev/null || stat -c%s "$snapshot_file" 2>/dev/null || echo 0)" \
        '{
            snapshot_id: $snapshot_id,
            document: $document,
            run_id: $run_id,
            integration_id: (if $integration_id == "" then null else $integration_id end),
            hash: $hash,
            size_bytes: $size,
            created_at: $created_at
        }' > "$meta_file"
    chmod 600 "$meta_file"

    # Add reference for this run
    add_snapshot_ref "$snapshot_id" "$run_id"

    log "Created snapshot: $snapshot_id for $doc_relative"
    log_trajectory "snapshot_created" "$(cat "$meta_file")"

    # Git commit if enabled
    if is_git_commit_enabled; then
        # Scan for secrets first
        if ! scan_for_secrets "$snapshot_file"; then
            error "Secret scanning failed, aborting git commit"
            # Keep snapshot locally but don't commit
            jq '.git_committed = false | .secret_scan_failed = true' "$meta_file" > "${meta_file}.tmp"
            mv "${meta_file}.tmp" "$meta_file"
            cat "$meta_file"
            return 6
        fi

        commit_snapshot "$snapshot_file" "$meta_file" "$snapshot_id"
    fi

    cat "$meta_file"
}

commit_snapshot() {
    local snapshot_file="$1"
    local meta_file="$2"
    local snapshot_id="$3"

    log "Committing snapshot to git: $snapshot_id"

    local commit_args=()
    if ! is_git_hooks_enabled; then
        # --no-verify: Flatline snapshot commits are framework-internal state (a2a/ artifacts).
        # Only applied when user has explicitly disabled git hooks via config.
        commit_args+=("--no-verify")
        warn "Git hooks disabled for snapshot commit"
    fi

    cd "$PROJECT_ROOT"

    if git add "$snapshot_file" "$meta_file" 2>/dev/null; then
        local msg="chore(flatline): snapshot $snapshot_id"
        if git commit "${commit_args[@]}" -m "$msg" 2>/dev/null; then
            log "Snapshot committed to git"
            jq '.git_committed = true' "$meta_file" > "${meta_file}.tmp"
            mv "${meta_file}.tmp" "$meta_file"
        else
            warn "Git commit failed (snapshot retained locally)"
        fi
    else
        warn "Git add failed (snapshot retained locally)"
    fi
}

add_snapshot_ref() {
    local snapshot_id="$1"
    local run_id="$2"

    local refs_file="$REFS_DIR/${snapshot_id}.refs"
    echo "$run_id" >> "$refs_file"
    chmod 600 "$refs_file"
}

remove_snapshot_ref() {
    local snapshot_id="$1"
    local run_id="$2"

    local refs_file="$REFS_DIR/${snapshot_id}.refs"
    if [[ -f "$refs_file" ]]; then
        grep -v "^${run_id}$" "$refs_file" > "${refs_file}.tmp" || true
        mv "${refs_file}.tmp" "$refs_file"
    fi
}

# =============================================================================
# Restore Operations
# =============================================================================

restore_snapshot() {
    local snapshot_id="$1"
    local force="${2:-false}"

    ensure_snapshot_dir

    local snapshot_file="$SNAPSHOT_DIR/${snapshot_id}.snapshot"
    local meta_file="$SNAPSHOT_DIR/${snapshot_id}.meta"

    if [[ ! -f "$snapshot_file" ]]; then
        error "Snapshot not found: $snapshot_id"
        return 2
    fi

    if [[ ! -f "$meta_file" ]]; then
        error "Snapshot metadata not found: $snapshot_id"
        return 2
    fi

    local document
    document=$(jq -r '.document' "$meta_file")
    local full_path="$PROJECT_ROOT/$document"

    local expected_hash
    expected_hash=$(jq -r '.hash' "$meta_file")

    # H-2 FIX: Acquire document lock BEFORE any file operations to prevent TOCTOU race
    local lock_acquired=false
    if [[ -x "$LOCK_SCRIPT" ]]; then
        if "$LOCK_SCRIPT" acquire --type document --resource "$document" --timeout 10 --caller "snapshot_restore" >/dev/null 2>&1; then
            lock_acquired=true
            log "Acquired document lock for restore"
        else
            error "Failed to acquire document lock for restore"
            return 5
        fi
    fi

    # Set up trap to release lock on any exit
    if [[ "$lock_acquired" == "true" ]]; then
        trap '"$LOCK_SCRIPT" release --type document --resource "$document" 2>/dev/null || true' EXIT
    fi

    local backup_path=""
    local pre_backup_hash=""

    # Check for divergence (current file differs from what we expect)
    if [[ -f "$full_path" ]]; then
        local current_hash
        current_hash=$(calculate_hash "$full_path")
        pre_backup_hash="$current_hash"

        # If document has been modified since snapshot, warn
        if [[ "$force" != "true" ]]; then
            # Create backup before restore
            backup_path="${full_path}.pre-rollback-$(date +%Y%m%d_%H%M%S)"
            cp "$full_path" "$backup_path"
            chmod 600 "$backup_path"
            log "Created backup: $backup_path"
        fi
    fi

    # Prepare atomic copy
    local temp_file
    temp_file=$(mktemp)
    cp "$snapshot_file" "$temp_file"

    # H-2 FIX: Re-verify hash immediately before mv to detect concurrent modification
    if [[ -n "$pre_backup_hash" && -f "$full_path" ]]; then
        local final_hash
        final_hash=$(calculate_hash "$full_path")
        if [[ "$final_hash" != "$pre_backup_hash" ]]; then
            rm -f "$temp_file"
            error "Document modified during restore operation (race detected)"
            log_trajectory "restore_race_detected" "{\"snapshot_id\": \"$snapshot_id\", \"document\": \"$document\", \"expected\": \"$pre_backup_hash\", \"actual\": \"$final_hash\"}"
            return 4
        fi
    fi

    # Restore via atomic move
    mv "$temp_file" "$full_path"

    # Release lock before logging (trap will also attempt release on exit)
    if [[ "$lock_acquired" == "true" ]]; then
        "$LOCK_SCRIPT" release --type document --resource "$document" 2>/dev/null || true
        trap - EXIT
    fi

    log "Restored document from snapshot: $snapshot_id -> $document"
    log_trajectory "snapshot_restored" "{\"snapshot_id\": \"$snapshot_id\", \"document\": \"$document\"}"

    jq -n \
        --arg snapshot_id "$snapshot_id" \
        --arg document "$document" \
        --arg restored_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson restored true \
        '{status: "restored", snapshot_id: $snapshot_id, document: $document, restored_at: $restored_at, restored: $restored}'
}

# =============================================================================
# List and Status
# =============================================================================

list_snapshots() {
    local run_id="${1:-}"

    ensure_snapshot_dir

    local snapshots=()

    while IFS= read -r -d '' meta_file; do
        local meta
        meta=$(cat "$meta_file" 2>/dev/null || echo "{}")

        # Filter by run_id if specified
        if [[ -n "$run_id" ]]; then
            local snapshot_run_id
            snapshot_run_id=$(echo "$meta" | jq -r '.run_id // ""')
            if [[ "$snapshot_run_id" != "$run_id" ]]; then
                continue
            fi
        fi

        # Add ref count
        local snapshot_id
        snapshot_id=$(echo "$meta" | jq -r '.snapshot_id')
        local refs_file="$REFS_DIR/${snapshot_id}.refs"
        local ref_count=0
        if [[ -f "$refs_file" ]]; then
            ref_count=$(wc -l < "$refs_file" 2>/dev/null || echo "0")
        fi

        meta=$(echo "$meta" | jq --argjson refs "$ref_count" '. + {ref_count: $refs}')
        snapshots+=("$meta")
    done < <(find "$SNAPSHOT_DIR" -name "*.meta" -type f -print0 2>/dev/null | sort -z)

    if [[ ${#snapshots[@]} -eq 0 ]]; then
        echo "[]"
    else
        printf '%s\n' "${snapshots[@]}" | jq -s '.'
    fi
}

show_status() {
    local stats
    stats=$(get_storage_stats)

    local oldest_timestamp=""
    local oldest_file
    oldest_file=$(find "$SNAPSHOT_DIR" -name "*.meta" -type f -print0 2>/dev/null | \
                  xargs -0 ls -t 2>/dev/null | tail -1)

    if [[ -n "$oldest_file" && -f "$oldest_file" ]]; then
        oldest_timestamp=$(jq -r '.created_at // ""' "$oldest_file" 2>/dev/null)
    fi

    echo "$stats" | jq \
        --arg oldest "$oldest_timestamp" \
        '. + {oldest_snapshot: (if $oldest == "" then null else $oldest end)}'
}

# =============================================================================
# Cleanup
# =============================================================================

cleanup_snapshots() {
    local max_age_days="${1:-$(get_max_age_days)}"
    local dry_run="${2:-false}"

    ensure_snapshot_dir

    local cutoff_epoch
    cutoff_epoch=$(date -d "-${max_age_days} days" +%s 2>/dev/null || \
                   date -v-${max_age_days}d +%s 2>/dev/null)

    local cleaned=0
    local skipped=0

    while IFS= read -r -d '' meta_file; do
        local created_at
        created_at=$(jq -r '.created_at // ""' "$meta_file" 2>/dev/null)

        if [[ -z "$created_at" ]]; then
            continue
        fi

        local created_epoch
        created_epoch=$(date -d "$created_at" +%s 2>/dev/null || \
                        date -j -f "%Y-%m-%dT%H:%M:%SZ" "$created_at" +%s 2>/dev/null || echo "0")

        if [[ $created_epoch -lt $cutoff_epoch ]]; then
            local snapshot_id
            snapshot_id=$(jq -r '.snapshot_id' "$meta_file")

            # Check for active references
            local refs_file="$REFS_DIR/${snapshot_id}.refs"
            if [[ -f "$refs_file" ]]; then
                local ref_count
                ref_count=$(wc -l < "$refs_file" 2>/dev/null || echo "0")
                if [[ $ref_count -gt 0 ]]; then
                    log "Skipping referenced snapshot: $snapshot_id ($ref_count refs)"
                    ((skipped++))
                    continue
                fi
            fi

            local snapshot_file="$SNAPSHOT_DIR/${snapshot_id}.snapshot"

            if [[ "$dry_run" == "true" ]]; then
                log "[DRY RUN] Would delete: $snapshot_id (age: $(($(date +%s) - created_epoch))s)"
            else
                rm -f "$snapshot_file" "$meta_file" "$refs_file"
                log "Deleted expired snapshot: $snapshot_id"
            fi
            ((cleaned++))
        fi
    done < <(find "$SNAPSHOT_DIR" -name "*.meta" -type f -print0 2>/dev/null)

    log "Cleanup complete: $cleaned deleted, $skipped skipped (referenced)"

    jq -n \
        --argjson cleaned "$cleaned" \
        --argjson skipped "$skipped" \
        --argjson max_age_days "$max_age_days" \
        --arg dry_run "$dry_run" \
        '{cleaned: $cleaned, skipped: $skipped, max_age_days: $max_age_days, dry_run: ($dry_run == "true")}'
}

# =============================================================================
# Main
# =============================================================================

usage() {
    cat <<EOF
Usage: flatline-snapshot.sh <command> [options]

Commands:
  create <document>        Create snapshot of document
    --run-id <id>          Run ID (required)
    --integration-id <id>  Integration ID (optional)

  restore <snapshot-id>    Restore document from snapshot
    --force                Skip divergence check

  list                     List all snapshots
    --run-id <id>          Filter by run ID

  cleanup                  Clean up old snapshots
    --max-age <days>       Maximum age in days (default: 7)
    --dry-run              Preview without deleting

  status                   Show storage stats

Examples:
  flatline-snapshot.sh create grimoires/loa/prd.md --run-id flatline-run-abc123
  flatline-snapshot.sh restore 20260203_143000_a1b2c3d4
  flatline-snapshot.sh list --run-id flatline-run-abc123
  flatline-snapshot.sh cleanup --max-age 14 --dry-run
  flatline-snapshot.sh status

Exit codes:
  0 - Success
  1 - Snapshot creation failed
  2 - Snapshot not found
  3 - Invalid arguments
  4 - Divergence detected
  5 - Quota exceeded
  6 - Secret detected
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
            local document=""
            local run_id=""
            local integration_id=""

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --run-id)
                        run_id="$2"
                        shift 2
                        ;;
                    --integration-id)
                        integration_id="$2"
                        shift 2
                        ;;
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        document="$1"
                        shift
                        ;;
                esac
            done

            if [[ -z "$document" ]]; then
                error "Document required"
                exit 3
            fi

            if [[ -z "$run_id" ]]; then
                error "--run-id required"
                exit 3
            fi

            create_snapshot "$document" "$run_id" "$integration_id"
            ;;

        restore)
            local snapshot_id=""
            local force="false"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --force)
                        force="true"
                        shift
                        ;;
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        snapshot_id="$1"
                        shift
                        ;;
                esac
            done

            if [[ -z "$snapshot_id" ]]; then
                error "Snapshot ID required"
                exit 3
            fi

            restore_snapshot "$snapshot_id" "$force"
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

            list_snapshots "$run_id"
            ;;

        cleanup)
            local max_age=""
            local dry_run="false"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --max-age)
                        max_age="$2"
                        shift 2
                        ;;
                    --dry-run)
                        dry_run="true"
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

            cleanup_snapshots "${max_age:-$(get_max_age_days)}" "$dry_run"
            ;;

        status)
            show_status
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
