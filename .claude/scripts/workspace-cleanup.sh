#!/usr/bin/env bash
# workspace-cleanup.sh - Archive previous cycle artifacts for clean workspace
# Part of Loa Framework - https://github.com/anthropics/loa
#
# Exit codes:
#   0 - Success (archived or skipped)
#   1 - Error (lock, disk, permission)
#   2 - User declined
#   3 - Validation failure (security)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Require bash 4.0+ (associative arrays)
# shellcheck source=bash-version-guard.sh
source "$SCRIPT_DIR/bash-version-guard.sh"

# ==============================================================================
# CONFIGURATION DEFAULTS
# ==============================================================================

GRIMOIRE_DIR="grimoires/loa"
RUN_DIR=".run"
DRY_RUN=false
FORCE=false
YES_FLAG=false
NO_FLAG=false
JSON_OUTPUT=false
PROMPT_TIMEOUT=5
LOCK_TTL=300
SAFETY_MARGIN=2  # Require 2x archive size free space
DEFAULT_ACTION="archive"
FOLLOW_SYMLINKS=false
RETENTION_MAX_AGE_DAYS=90
RETENTION_MAX_COUNT=10

# Runtime state
declare -a FILES_TO_ARCHIVE=()
TOTAL_SIZE=0
ARCHIVE_DIR=""
STAGING_DIR=""
TRANSACTION_LOG=""
LOCK_FD=200

# ==============================================================================
# LOGGING
# ==============================================================================

log() {
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo "[cleanup] $*" >&2
    fi
}

warn() {
    echo "[cleanup] WARNING: $*" >&2
}

error() {
    echo "[cleanup] ERROR: $*" >&2
}

# ==============================================================================
# TASK 1.1: ARGUMENT PARSING
# ==============================================================================

show_help() {
    cat << 'EOF'
workspace-cleanup.sh - Archive previous cycle artifacts for clean workspace

USAGE:
    workspace-cleanup.sh [OPTIONS]

OPTIONS:
    --grimoire <path>    Grimoire directory (default: grimoires/loa)
    --yes                Archive without prompt
    --no                 Skip cleanup without prompt
    --dry-run            Show what would be archived
    --force              Ignore lock conflicts (dangerous)
    --timeout <seconds>  Prompt timeout (default: 5)
    --json               Output results as JSON

EXIT CODES:
    0 - Success (archived or skipped)
    1 - Error (lock, disk, permission)
    2 - User declined
    3 - Validation failure (security)

EXAMPLES:
    # Interactive cleanup with 5s timeout
    workspace-cleanup.sh

    # Autonomous mode (no prompt)
    workspace-cleanup.sh --yes --json

    # Preview what would be archived
    workspace-cleanup.sh --dry-run
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --grimoire)
                GRIMOIRE_DIR="$2"
                shift 2
                ;;
            --yes)
                YES_FLAG=true
                shift
                ;;
            --no)
                NO_FLAG=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --timeout)
                if [[ ! "$2" =~ ^[0-9]+$ ]] || [[ "$2" -lt 1 ]] || [[ "$2" -gt 300 ]]; then
                    error "Invalid timeout: $2 (must be 1-300 seconds)"
                    exit 1
                fi
                PROMPT_TIMEOUT="$2"
                shift 2
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Validate conflicting flags
    if [[ "$YES_FLAG" == "true" && "$NO_FLAG" == "true" ]]; then
        error "Cannot use both --yes and --no"
        exit 1
    fi
}

# ==============================================================================
# TASK 1.5: CONFIGURATION LOADER
# ==============================================================================

load_config() {
    local config_file=".loa.config.yaml"

    if [[ ! -f "$config_file" ]]; then
        # No config file - use defaults
        return 0
    fi

    # Fail-fast: check if yq is available
    if ! command -v yq &>/dev/null; then
        error "Configuration file exists but yq is not installed"
        error "Install yq or remove $config_file to use defaults"
        exit 1
    fi

    # Validate YAML syntax
    if ! yq '.' "$config_file" &>/dev/null; then
        error "Invalid YAML syntax in $config_file"
        exit 1
    fi

    # Load workspace_cleanup configuration
    local enabled
    enabled=$(yq -r '.workspace_cleanup.enabled // true' "$config_file" 2>/dev/null)
    if [[ "$enabled" == "false" ]]; then
        log "Workspace cleanup disabled in config"
        exit 0
    fi

    # Load settings
    local val
    val=$(yq -r '.workspace_cleanup.default_action // "archive"' "$config_file" 2>/dev/null)
    # Strip any surrounding quotes
    val="${val//\"/}"
    if [[ "$val" =~ ^(archive|skip)$ ]]; then
        DEFAULT_ACTION="$val"
    elif [[ -n "$val" && "$val" != "null" ]]; then
        error "Invalid default_action in config: $val (must be 'archive' or 'skip')"
        exit 1
    fi

    val=$(yq -r '.workspace_cleanup.disk_space.safety_margin // 2' "$config_file" 2>/dev/null)
    [[ "$val" != "null" && -n "$val" ]] && SAFETY_MARGIN="$val"

    val=$(yq -r '.workspace_cleanup.lock.ttl_seconds // 300' "$config_file" 2>/dev/null)
    [[ "$val" != "null" && -n "$val" ]] && LOCK_TTL="$val"

    val=$(yq -r '.workspace_cleanup.security.follow_symlinks // false' "$config_file" 2>/dev/null)
    [[ "$val" != "null" && -n "$val" ]] && FOLLOW_SYMLINKS="$val"

    val=$(yq -r '.workspace_cleanup.retention.max_age_days // 90' "$config_file" 2>/dev/null)
    [[ "$val" != "null" && -n "$val" ]] && RETENTION_MAX_AGE_DAYS="$val"

    val=$(yq -r '.workspace_cleanup.retention.max_count // 10' "$config_file" 2>/dev/null)
    [[ "$val" != "null" && -n "$val" ]] && RETENTION_MAX_COUNT="$val"

    val=$(yq -r '.workspace_cleanup.prompt.timeout_seconds // 5' "$config_file" 2>/dev/null)
    [[ "$val" != "null" && -n "$val" ]] && PROMPT_TIMEOUT="$val"
}

# ==============================================================================
# TASK 1.2: LOCK MANAGER
# ==============================================================================

acquire_cleanup_lock() {
    local lock_file="$GRIMOIRE_DIR/.cleanup.lock"
    local max_retries=3
    local retry_delay=1

    # Create lock file if needed
    mkdir -p "$(dirname "$lock_file")"
    touch "$lock_file" 2>/dev/null || {
        error "Cannot create lock file: $lock_file"
        return 1
    }

    # Open file descriptor for locking
    exec 200>"$lock_file"

    # Retry loop with jitter to avoid thundering herd (HIGH-001 fix)
    local attempt=0
    while (( attempt < max_retries )); do
        # Try non-blocking exclusive lock
        if flock -n 200; then
            # Successfully acquired lock
            break
        fi

        attempt=$((attempt + 1))

        if (( attempt >= max_retries )); then
            # Final attempt failed - check staleness for advisory message only
            if is_lock_stale "$lock_file"; then
                if [[ "$FORCE" == "true" ]]; then
                    warn "Stale lock detected, forcing acquisition (--force flag)"
                    # Use blocking lock with timeout - flock handles atomicity
                    if flock -w 10 200; then
                        break
                    fi
                    error "Cannot acquire lock even with --force (timeout)"
                    return 1
                else
                    error "Lock appears stale but --force not specified"
                    error "Use --force to override, or wait for TTL expiry"
                    return 1
                fi
            else
                error "Lock held by another process"
                error "Another cleanup or preflight is in progress"
                return 1
            fi
        fi

        # Add jitter (0.1-0.5s random) to retry delay to avoid races
        local jitter
        jitter=$(awk 'BEGIN{srand(); printf "%.1f", 0.1 + rand()*0.4}')
        log "Lock busy, retrying in ${retry_delay}s (attempt $attempt/$max_retries)..."
        sleep "$retry_delay"
        sleep "$jitter" 2>/dev/null || true
        retry_delay=$((retry_delay * 2))  # Exponential backoff
    done

    # Write lock metadata (for observability, not for locking)
    cat > "$lock_file" << EOF
{
  "pid": $$,
  "hostname": "$(hostname)",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "ttl_seconds": $LOCK_TTL
}
EOF

    return 0
}

is_lock_stale() {
    local lock_file="$1"

    if [[ ! -s "$lock_file" ]]; then
        return 0  # Empty lock file = stale
    fi

    local pid hostname timestamp ttl
    pid=$(jq -r '.pid // 0' "$lock_file" 2>/dev/null || echo 0)
    hostname=$(jq -r '.hostname // ""' "$lock_file" 2>/dev/null || echo "")
    timestamp=$(jq -r '.timestamp // ""' "$lock_file" 2>/dev/null || echo "")
    ttl=$(jq -r '.ttl_seconds // 300' "$lock_file" 2>/dev/null || echo 300)

    # Check if same host and process dead
    if [[ "$hostname" == "$(hostname)" && -n "$pid" && "$pid" != "0" ]]; then
        if ! kill -0 "$pid" 2>/dev/null; then
            return 0  # Process dead = stale
        fi
    fi

    # Check TTL expiry (for cross-host scenarios)
    if [[ -n "$timestamp" && "$timestamp" != "null" ]]; then
        local lock_epoch now_epoch
        lock_epoch=$(date -d "$timestamp" +%s 2>/dev/null || echo 0)
        now_epoch=$(date +%s)

        if (( now_epoch - lock_epoch > ttl )); then
            return 0  # TTL expired = stale
        fi
    fi

    return 1  # Lock appears valid
}

release_cleanup_lock() {
    # Close file descriptor (releases flock)
    exec 200>&- 2>/dev/null || true
}

# ==============================================================================
# TASK 1.3: SCANNER MODULE
# ==============================================================================

scan_archivable_files() {
    FILES_TO_ARCHIVE=()
    TOTAL_SIZE=0

    # Try cycle manifest first
    if [[ -f "$RUN_DIR/cycle-manifest.json" ]]; then
        scan_from_manifest
    fi

    # Pattern-based fallback
    scan_from_patterns

    # Validate all paths
    validate_scanned_paths

    # Recalculate size with du -sb for accuracy
    recalculate_total_size
}

scan_from_manifest() {
    local manifest="$RUN_DIR/cycle-manifest.json"

    while IFS= read -r path; do
        # Skip empty lines
        [[ -z "$path" ]] && continue

        # Remove grimoires/loa/ prefix if present
        path="${path#grimoires/loa/}"

        # Security: validate path
        if ! validate_single_path "$path"; then
            warn "Skipping invalid path from manifest: $path"
            continue
        fi

        local full_path="$GRIMOIRE_DIR/$path"
        if [[ -f "$full_path" || -d "$full_path" ]]; then
            FILES_TO_ARCHIVE+=("$path")
        fi
    done < <(jq -r '.produced_files[]?.path // empty' "$manifest" 2>/dev/null)
}

scan_from_patterns() {
    local patterns=(
        "prd.md"
        "sdd.md"
        "sprint.md"
        "prd-*.md"
        "sdd-*.md"
        "sprint-*.md"
    )

    for pattern in "${patterns[@]}"; do
        # Use find with -P (no symlink following)
        while IFS= read -r -d '' file; do
            local relpath="${file#$GRIMOIRE_DIR/}"

            # Skip if already in list
            local already_exists=false
            for existing in "${FILES_TO_ARCHIVE[@]:-}"; do
                if [[ "$existing" == "$relpath" ]]; then
                    already_exists=true
                    break
                fi
            done
            [[ "$already_exists" == "true" ]] && continue

            FILES_TO_ARCHIVE+=("$relpath")
        done < <(find -P "$GRIMOIRE_DIR" -maxdepth 1 -name "$pattern" -type f -print0 2>/dev/null)
    done

    # Scan sprint directories in a2a
    if [[ -d "$GRIMOIRE_DIR/a2a" ]]; then
        while IFS= read -r -d '' dir; do
            local relpath="${dir#$GRIMOIRE_DIR/}"
            FILES_TO_ARCHIVE+=("$relpath")
        done < <(find -P "$GRIMOIRE_DIR/a2a" -maxdepth 1 -type d -name "sprint-[0-9]*" -print0 2>/dev/null)
    fi
}

validate_scanned_paths() {
    local valid_files=()

    for path in "${FILES_TO_ARCHIVE[@]:-}"; do
        # Skip empty paths
        [[ -z "$path" ]] && continue
        if validate_single_path "$path"; then
            valid_files+=("$path")
        else
            warn "Security: Rejected path: $path"
        fi
    done

    # Reset array - use proper empty array syntax when no valid files
    if [[ ${#valid_files[@]} -eq 0 ]]; then
        FILES_TO_ARCHIVE=()
    else
        FILES_TO_ARCHIVE=("${valid_files[@]}")
    fi
}

validate_single_path() {
    local path="$1"
    local full_path="$GRIMOIRE_DIR/$path"

    # Reject paths with ..
    if [[ "$path" == *".."* ]]; then
        return 1
    fi

    # Reject absolute paths
    if [[ "$path" == /* ]]; then
        return 1
    fi

    # Reject symlinks (unless configured)
    if [[ "$FOLLOW_SYMLINKS" == "false" && -L "$full_path" ]]; then
        warn "Symlink detected, skipping: $path"
        return 1
    fi

    # Verify realpath is under grimoire
    local real_path grimoire_real
    real_path=$(realpath -m "$full_path" 2>/dev/null) || return 1
    grimoire_real=$(realpath -m "$GRIMOIRE_DIR" 2>/dev/null) || return 1

    if [[ "$real_path" != "$grimoire_real"/* && "$real_path" != "$grimoire_real" ]]; then
        return 1
    fi

    return 0
}

recalculate_total_size() {
    TOTAL_SIZE=0

    for path in "${FILES_TO_ARCHIVE[@]:-}"; do
        local full_path="$GRIMOIRE_DIR/$path"
        if [[ -e "$full_path" ]]; then
            local size
            size=$(du -sb "$full_path" 2>/dev/null | cut -f1)
            TOTAL_SIZE=$((TOTAL_SIZE + ${size:-0}))
        fi
    done
}

# ==============================================================================
# TASK 1.7: DISK SPACE CHECK
# ==============================================================================

check_disk_space() {
    local required_space=$((TOTAL_SIZE * SAFETY_MARGIN))
    local archive_dest="$GRIMOIRE_DIR/archive"

    mkdir -p "$archive_dest"

    local available
    available=$(df -B1 "$archive_dest" 2>/dev/null | tail -1 | awk '{print $4}')

    if [[ -z "$available" || "$available" -lt "$required_space" ]]; then
        local required_mb=$((required_space / 1024 / 1024))
        local available_mb=$((available / 1024 / 1024))
        error "Insufficient disk space: need ${required_mb}MB, have ${available_mb}MB"
        return 1
    fi

    return 0
}

# ==============================================================================
# TASK 1.8: USER PROMPT (with IMP-002 stdin handling)
# ==============================================================================

should_prompt() {
    # Explicit flags override
    [[ "$YES_FLAG" == "true" ]] && return 1
    [[ "$NO_FLAG" == "true" ]] && return 1
    [[ "$DRY_RUN" == "true" ]] && return 1

    # Check if stdin is a TTY
    [[ -t 0 ]] && return 0

    # Non-TTY: use default action
    return 1
}

prompt_user() {
    local total_mb=$((TOTAL_SIZE / 1024 / 1024))
    [[ "$total_mb" -eq 0 ]] && total_mb=1

    echo "" >&2
    echo "╔══════════════════════════════════════════════════════════════╗" >&2
    echo "║                    WORKSPACE CLEANUP                         ║" >&2
    echo "╠══════════════════════════════════════════════════════════════╣" >&2
    echo "║  Files to archive:                                           ║" >&2
    for path in "${FILES_TO_ARCHIVE[@]:-}"; do
        printf "║    • %-54s ║\n" "$path" >&2
    done
    echo "║                                                              ║" >&2
    printf "║  Total size: %3d MB                                         ║\n" "$total_mb" >&2
    echo "║                                                              ║" >&2
    echo "║  Archive to: grimoires/loa/archive/$(date +%Y-%m-%d)                   ║" >&2
    echo "╚══════════════════════════════════════════════════════════════╝" >&2
    echo "" >&2

    # IMP-002: Handle stdin closed/pipe failure gracefully
    local response=""
    if [[ -t 0 ]]; then
        echo -n "Archive these files? [Y/n] (${PROMPT_TIMEOUT}s timeout, default: Y) " >&2

        # Use read with timeout
        if ! read -r -t "$PROMPT_TIMEOUT" response 2>/dev/null; then
            # Timeout or error
            echo "" >&2
            log "Timeout reached, defaulting to YES"
            response="y"
        fi
    else
        # Stdin not a TTY - this shouldn't happen if should_prompt() works correctly
        # but handle gracefully per IMP-002
        log "Non-interactive mode: using default action ($DEFAULT_ACTION)"
        if [[ "$DEFAULT_ACTION" == "archive" ]]; then
            response="y"
        else
            response="n"
        fi
    fi

    # Empty response = default YES
    [[ -z "$response" ]] && response="y"

    case "${response,,}" in
        y|yes|"")
            return 0
            ;;
        n|no)
            log "User declined cleanup"
            return 1
            ;;
        *)
            warn "Invalid response '$response', treating as NO"
            return 1
            ;;
    esac
}

# ==============================================================================
# TASK 1.4: ARCHIVER MODULE (4-Stage with Transaction Log)
# ==============================================================================

execute_archive() {
    local archive_date
    archive_date=$(date +%Y-%m-%d)
    local archive_name="$archive_date"

    # Handle duplicate dates (MEDIUM-003 fix: limit counter to prevent runaway)
    local counter=0
    local max_archives_per_day=100
    while [[ -d "$GRIMOIRE_DIR/archive/$archive_name" ]]; do
        counter=$((counter + 1))
        if (( counter > max_archives_per_day )); then
            error "Too many archives for $archive_date (max $max_archives_per_day per day)"
            error "Clean up old archives or check for runaway automation"
            return 1
        fi
        archive_name="${archive_date}-${counter}"
    done

    ARCHIVE_DIR="$GRIMOIRE_DIR/archive/$archive_name"
    STAGING_DIR="$GRIMOIRE_DIR/archive/${archive_name}.staging"
    TRANSACTION_LOG="$GRIMOIRE_DIR/archive/.transaction-${archive_name}.log"

    # Initialize transaction log
    init_transaction_log

    # Stage 1: Copy to staging
    log "Stage 1/4: Copying to staging..."
    if ! stage1_copy_to_staging; then
        cleanup_staging
        return 1
    fi

    # Stage 2: Verify ALL checksums
    log "Stage 2/4: Verifying checksums..."
    if ! stage2_verify_checksums; then
        cleanup_staging
        return 1
    fi

    # Stage 3: Finalize archive
    log "Stage 3/4: Finalizing archive..."
    if ! stage3_finalize_archive; then
        mv "$STAGING_DIR" "${STAGING_DIR%.staging}.failed" 2>/dev/null
        return 1
    fi

    # Stage 4: Remove originals
    log "Stage 4/4: Removing originals..."
    if ! stage4_remove_originals; then
        warn "Partial cleanup - see transaction log: $TRANSACTION_LOG"
        return 1
    fi

    # Success - remove transaction log
    rm -f "$TRANSACTION_LOG"

    log "Archive complete: $ARCHIVE_DIR"
    return 0
}

init_transaction_log() {
    mkdir -p "$(dirname "$TRANSACTION_LOG")"

    # MEDIUM-002 fix: Clean up any orphaned .tmp files from previous crashes
    local orphaned_tmp
    orphaned_tmp=$(find "$(dirname "$TRANSACTION_LOG")" -name ".transaction-*.log.tmp" -mmin +5 2>/dev/null || true)
    if [[ -n "$orphaned_tmp" ]]; then
        warn "Cleaning up orphaned transaction temp files"
        echo "$orphaned_tmp" | xargs rm -f 2>/dev/null || true
    fi

    cat > "$TRANSACTION_LOG" << EOF
{
  "archive_id": "archive-$(date +%Y%m%d)-$$",
  "started": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "staging_dir": "$STAGING_DIR",
  "archive_dir": "$ARCHIVE_DIR",
  "state": "STARTED",
  "files_to_delete": [],
  "files_deleted": []
}
EOF
    # Ensure written to disk
    sync "$TRANSACTION_LOG" 2>/dev/null || true
}

update_transaction_state() {
    local state="$1"
    local tmp="${TRANSACTION_LOG}.tmp"
    jq --arg state "$state" '.state = $state' "$TRANSACTION_LOG" > "$tmp"
    # MEDIUM-002 fix: Sync before rename to ensure data is flushed
    sync "$tmp" 2>/dev/null || true
    mv "$tmp" "$TRANSACTION_LOG"
}

stage1_copy_to_staging() {
    mkdir -p "$STAGING_DIR"

    declare -A checksums

    for path in "${FILES_TO_ARCHIVE[@]:-}"; do
        local src="$GRIMOIRE_DIR/$path"
        local dest="$STAGING_DIR/$path"

        mkdir -p "$(dirname "$dest")"

        if [[ -d "$src" ]]; then
            # Copy directory recursively
            cp -r "$src" "$dest" || {
                error "Failed to copy directory: $path"
                return 1
            }
            # Compute checksums for all files in directory
            while IFS= read -r -d '' file; do
                local relfile="${file#$src/}"
                local checksum
                checksum=$(sha256sum "$file" | cut -d' ' -f1)
                checksums["$path/$relfile"]="$checksum"
            done < <(find "$src" -type f -print0)
        else
            # Copy single file
            cp "$src" "$dest" || {
                error "Failed to copy file: $path"
                return 1
            }
            # Compute checksum
            local checksum
            checksum=$(sha256sum "$src" | cut -d' ' -f1)
            checksums["$path"]="$checksum"
        fi
    done

    # Save checksums to staging
    for path in "${!checksums[@]}"; do
        echo "${checksums[$path]}  $path" >> "$STAGING_DIR/.checksums"
    done

    update_transaction_state "COPIED"
    return 0
}

stage2_verify_checksums() {
    if [[ ! -f "$STAGING_DIR/.checksums" ]]; then
        error "Checksum file missing from staging"
        return 1
    fi

    while IFS= read -r line; do
        local expected_sum="${line%% *}"
        local file_path="${line#*  }"
        local full_path="$STAGING_DIR/$file_path"

        if [[ ! -f "$full_path" ]]; then
            error "File missing from staging: $file_path"
            return 1
        fi

        local actual_sum
        actual_sum=$(sha256sum "$full_path" | cut -d' ' -f1)

        if [[ "$expected_sum" != "$actual_sum" ]]; then
            error "Checksum mismatch for: $file_path"
            error "  Expected: $expected_sum"
            error "  Actual:   $actual_sum"
            return 1
        fi
    done < "$STAGING_DIR/.checksums"

    update_transaction_state "VERIFIED"
    return 0
}

stage3_finalize_archive() {
    # Rename staging to final
    if ! mv "$STAGING_DIR" "$ARCHIVE_DIR" 2>/dev/null; then
        # EXDEV: cross-filesystem - use copy+delete
        if ! cp -r "$STAGING_DIR" "$ARCHIVE_DIR"; then
            error "Failed to finalize archive"
            return 1
        fi
        rm -rf "$STAGING_DIR"
    fi

    # Write manifest
    local manifest="$ARCHIVE_DIR/manifest.json"
    local files_json
    files_json=$(printf '%s\n' "${FILES_TO_ARCHIVE[@]:-}" | jq -R . | jq -s .)

    cat > "$manifest" << EOF
{
  "archived_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source": "$GRIMOIRE_DIR",
  "files": $files_json,
  "total_size_bytes": $TOTAL_SIZE,
  "checksum_file": ".checksums"
}
EOF

    # Write committed marker
    touch "$ARCHIVE_DIR/.committed"

    update_transaction_state "FINALIZED"
    return 0
}

stage4_remove_originals() {
    # Record files to delete in transaction log
    local files_json
    files_json=$(printf '%s\n' "${FILES_TO_ARCHIVE[@]:-}" | jq -R . | jq -s .)
    local tmp="${TRANSACTION_LOG}.tmp"
    jq --argjson files "$files_json" '.files_to_delete = $files' "$TRANSACTION_LOG" > "$tmp"
    mv "$tmp" "$TRANSACTION_LOG"

    update_transaction_state "DELETING"

    for path in "${FILES_TO_ARCHIVE[@]:-}"; do
        local src="$GRIMOIRE_DIR/$path"

        if [[ -d "$src" ]]; then
            rm -rf "$src" || {
                warn "Failed to remove directory: $path"
            }
        else
            rm -f "$src" || {
                warn "Failed to remove file: $path"
            }
        fi

        # Update transaction log
        tmp="${TRANSACTION_LOG}.tmp"
        jq --arg file "$path" '.files_deleted += [$file]' "$TRANSACTION_LOG" > "$tmp"
        mv "$tmp" "$TRANSACTION_LOG"
    done

    update_transaction_state "COMPLETED"
    return 0
}

cleanup_staging() {
    if [[ -d "$STAGING_DIR" ]]; then
        rm -rf "$STAGING_DIR"
    fi
    if [[ -f "$TRANSACTION_LOG" ]]; then
        rm -f "$TRANSACTION_LOG"
    fi
}

# ==============================================================================
# TASK 1.6: ARCHIVE RETENTION MANAGER
# ==============================================================================

cleanup_old_archives() {
    local archive_base="$GRIMOIRE_DIR/archive"
    [[ ! -d "$archive_base" ]] && return 0

    local archives=()
    while IFS= read -r -d '' dir; do
        # Skip staging, failed, and protected archives
        [[ "$dir" == *.staging ]] && continue
        [[ "$dir" == *.failed ]] && continue
        [[ -f "$dir/.keep" ]] && continue

        archives+=("$dir")
    done < <(find "$archive_base" -maxdepth 1 -type d -name "20*" -print0 | sort -z)

    # Remove archives older than max_age_days
    local now_epoch
    now_epoch=$(date +%s)
    local max_age_seconds=$((RETENTION_MAX_AGE_DAYS * 86400))

    for archive in "${archives[@]:-}"; do
        local archive_name
        archive_name=$(basename "$archive")
        local archive_date="${archive_name%%-*}"

        local archive_epoch
        archive_epoch=$(date -d "$archive_date" +%s 2>/dev/null || echo 0)

        if (( now_epoch - archive_epoch > max_age_seconds )); then
            log "Removing old archive (age): $archive_name"
            rm -rf "$archive"
        fi
    done

    # Refresh archives list
    archives=()
    while IFS= read -r -d '' dir; do
        [[ "$dir" == *.staging ]] && continue
        [[ "$dir" == *.failed ]] && continue
        [[ -f "$dir/.keep" ]] && continue
        archives+=("$dir")
    done < <(find "$archive_base" -maxdepth 1 -type d -name "20*" -print0 | sort -zr)

    # Keep only max_count newest archives
    local count=0
    for archive in "${archives[@]:-}"; do
        count=$((count + 1))
        if (( count > RETENTION_MAX_COUNT )); then
            log "Removing old archive (count): $(basename "$archive")"
            rm -rf "$archive"
        fi
    done
}

# ==============================================================================
# IMP-001: PARTIAL STATE DETECTION
# ==============================================================================

detect_partial_state() {
    local archive_base="$GRIMOIRE_DIR/archive"
    local staging_dirs=()
    local failed_dirs=()

    if [[ -d "$archive_base" ]]; then
        while IFS= read -r -d '' dir; do
            staging_dirs+=("$dir")
        done < <(find "$archive_base" -maxdepth 1 -type d -name "*.staging" -print0 2>/dev/null)

        while IFS= read -r -d '' dir; do
            failed_dirs+=("$dir")
        done < <(find "$archive_base" -maxdepth 1 -type d -name "*.failed" -print0 2>/dev/null)
    fi

    if [[ ${#staging_dirs[@]} -gt 0 || ${#failed_dirs[@]} -gt 0 ]]; then
        echo "staging:${staging_dirs[*]:-}"
        echo "failed:${failed_dirs[*]:-}"
        return 0
    fi

    return 1
}

# ==============================================================================
# TASK 1.9: JSON OUTPUT
# ==============================================================================

output_results() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        local files_json
        files_json=$(printf '%s\n' "${FILES_TO_ARCHIVE[@]:-}" | jq -R . | jq -s .)

        local partial_state=""
        if detect_partial_state > /dev/null 2>&1; then
            partial_state=$(detect_partial_state 2>/dev/null | jq -R . | jq -s .)
        fi

        cat << EOF
{
  "success": true,
  "archived": true,
  "archived_count": ${#FILES_TO_ARCHIVE[@]},
  "archive_path": "$ARCHIVE_DIR",
  "total_size_bytes": $TOTAL_SIZE,
  "files": $files_json,
  "partial_state": ${partial_state:-null},
  "skipped_locked": false
}
EOF
    fi
}

output_skip_results() {
    local reason="$1"

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        cat << EOF
{
  "success": true,
  "archived": false,
  "reason": "$reason",
  "archived_count": 0,
  "archive_path": null,
  "total_size_bytes": 0,
  "files": [],
  "partial_state": null,
  "skipped_locked": false
}
EOF
    fi
}

output_dry_run_results() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        local files_json
        files_json=$(printf '%s\n' "${FILES_TO_ARCHIVE[@]:-}" | jq -R . | jq -s .)

        cat << EOF
{
  "dry_run": true,
  "would_archive_count": ${#FILES_TO_ARCHIVE[@]},
  "would_archive_size_bytes": $TOTAL_SIZE,
  "files": $files_json
}
EOF
    else
        echo ""
        echo "DRY RUN - Would archive:"
        for path in "${FILES_TO_ARCHIVE[@]:-}"; do
            echo "  • $path"
        done
        echo ""
        echo "Total size: $((TOTAL_SIZE / 1024 / 1024))MB"
        echo "Archive destination: $GRIMOIRE_DIR/archive/$(date +%Y-%m-%d)"
    fi
}

# ==============================================================================
# GRIMOIRE PATH VALIDATION
# ==============================================================================

validate_grimoire_path() {
    local path="$1"

    # Check directory exists
    if [[ ! -d "$path" ]]; then
        error "Grimoire directory does not exist: $path"
        return 1
    fi

    # Check not a symlink
    if [[ -L "$path" ]]; then
        error "Grimoire path is a symlink: $path"
        return 1
    fi

    # MEDIUM-004 fix: Check writability
    if [[ ! -w "$path" ]]; then
        error "Grimoire directory not writable: $path"
        return 1
    fi

    # MEDIUM-004 fix: Check archive subdirectory writability (or can create)
    local archive_dir="$path/archive"
    if [[ -d "$archive_dir" && ! -w "$archive_dir" ]]; then
        error "Archive directory not writable: $archive_dir"
        return 1
    fi

    # Check realpath doesn't escape expected location
    local real_path
    real_path=$(realpath -m "$path")

    if [[ "$real_path" != *"grimoires"* ]]; then
        error "Grimoire path outside expected location: $path"
        return 1
    fi

    # MEDIUM-004 fix: Advisory ownership check
    local owner
    owner=$(stat -c '%U' "$path" 2>/dev/null || stat -f '%Su' "$path" 2>/dev/null || echo "unknown")
    local current_user
    current_user=$(whoami)
    if [[ "$owner" != "$current_user" && "$EUID" != 0 ]]; then
        warn "Grimoire directory owned by '$owner', not current user '$current_user'"
    fi

    return 0
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    parse_arguments "$@"

    # Load configuration
    load_config

    # Security: validate grimoire path
    validate_grimoire_path "$GRIMOIRE_DIR" || exit 3

    # Acquire lock BEFORE scanning
    acquire_cleanup_lock || exit 1
    trap release_cleanup_lock EXIT

    # Scan for archivable files
    scan_archivable_files

    if [[ ${#FILES_TO_ARCHIVE[@]} -eq 0 ]]; then
        log "No archivable files found"
        output_skip_results "no_files"
        exit 0
    fi

    log "Found ${#FILES_TO_ARCHIVE[@]} items to archive ($(( TOTAL_SIZE / 1024 ))KB)"

    # Dry run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        output_dry_run_results
        exit 0
    fi

    # Check disk space
    check_disk_space || exit 1

    # Handle --no flag
    if [[ "$NO_FLAG" == "true" ]]; then
        log "Skipping cleanup (--no flag)"
        output_skip_results "user_declined"
        exit 2
    fi

    # Prompt user (if TTY and not --yes)
    if should_prompt; then
        if ! prompt_user; then
            output_skip_results "user_declined"
            exit 2
        fi
    elif [[ "$YES_FLAG" != "true" && "$DEFAULT_ACTION" != "archive" ]]; then
        log "Skipping cleanup (default action: skip)"
        output_skip_results "default_skip"
        exit 0
    fi

    # Execute archive
    if ! execute_archive; then
        exit 1
    fi

    # Run retention cleanup
    cleanup_old_archives

    # Output results
    output_results

    exit 0
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
