#!/usr/bin/env bash
# =============================================================================
# flatline-lock.sh - Document and manifest locking for Flatline Protocol
# =============================================================================
# Version: 1.0.0
# Part of: Autonomous Flatline Integration v1.22.0
#
# Provides flock()-based advisory locking to prevent concurrent modification
# of documents and manifests during autonomous Flatline execution.
#
# Usage:
#   flatline-lock.sh acquire <resource> [--timeout <seconds>] [--type <type>]
#   flatline-lock.sh release <resource>
#   flatline-lock.sh with-lock <resource> -- <command>
#   flatline-lock.sh list [--active]
#   flatline-lock.sh status <resource>
#   flatline-lock.sh cleanup [--force]
#
# Lock Types (acquisition order to prevent deadlocks):
#   1. run     - Global run mutex (acquired first)
#   2. manifest - Run manifest locks
#   3. document - Individual document locks
#
# Exit codes:
#   0 - Success
#   1 - Lock acquisition failed (timeout)
#   2 - Lock not found
#   3 - Invalid arguments
#   4 - Resource not found
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
LOCK_DIR="$PROJECT_ROOT/.flatline/locks"
TRAJECTORY_DIR="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"

# Default configuration
DEFAULT_TIMEOUT=10
DEFAULT_STALE_TTL=300  # 5 minutes
DEFAULT_MAX_RETRIES=3
DEFAULT_BACKOFF_BASE=1

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[flatline-lock] $*" >&2
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

    # Security: Create log directory with restrictive permissions
    (umask 077 && mkdir -p "$TRAJECTORY_DIR")
    local date_str
    date_str=$(date +%Y-%m-%d)
    local log_file="$TRAJECTORY_DIR/flatline-lock-$date_str.jsonl"

    # Ensure log file has restrictive permissions
    touch "$log_file"
    chmod 600 "$log_file"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg type "flatline_lock" \
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

get_lock_timeout() {
    read_config '.autonomous_mode.locking.timeout_seconds' "$DEFAULT_TIMEOUT"
}

get_stale_ttl() {
    read_config '.autonomous_mode.locking.stale_ttl_seconds' "$DEFAULT_STALE_TTL"
}

get_max_retries() {
    read_config '.autonomous_mode.locking.max_retries' "$DEFAULT_MAX_RETRIES"
}

is_run_isolation_enabled() {
    local enabled
    enabled=$(read_config '.autonomous_mode.locking.run_isolation' 'true')
    [[ "$enabled" == "true" ]]
}

is_nfs_fallback_enabled() {
    local enabled
    enabled=$(read_config '.autonomous_mode.locking.nfs_fallback' 'true')
    [[ "$enabled" == "true" ]]
}

# =============================================================================
# Lock Directory Management
# =============================================================================

ensure_lock_dir() {
    if [[ ! -d "$LOCK_DIR" ]]; then
        # Security: Create with restrictive permissions (700 = owner only)
        (umask 077 && mkdir -p "$LOCK_DIR")
        log "Created lock directory: $LOCK_DIR"
    fi
}

# Generate lock file path from resource identifier
get_lock_path() {
    local resource="$1"
    local lock_type="${2:-document}"

    # Sanitize resource name (convert path separators and special chars)
    local sanitized
    sanitized=$(echo "$resource" | sed 's|/|__|g' | sed 's|[^a-zA-Z0-9_.-]|_|g')

    echo "$LOCK_DIR/${lock_type}__${sanitized}.lock"
}

# Get lock info file path (companion file with metadata)
get_lock_info_path() {
    local lock_path="$1"
    echo "${lock_path%.lock}.info"
}

# =============================================================================
# Lock Acquisition (flock-based)
# =============================================================================

# Acquire lock using flock()
# Returns: 0 on success, 1 on timeout, 2 on error
acquire_lock() {
    local resource="$1"
    local lock_type="${2:-document}"
    local timeout="${3:-$(get_lock_timeout)}"
    local caller="${4:-unknown}"

    ensure_lock_dir

    local lock_path
    lock_path=$(get_lock_path "$resource" "$lock_type")

    local info_path
    info_path=$(get_lock_info_path "$lock_path")

    # Check for stale locks first
    if [[ -f "$info_path" ]]; then
        local lock_time pid
        lock_time=$(jq -r '.timestamp // 0' "$info_path" 2>/dev/null || echo "0")
        pid=$(jq -r '.pid // 0' "$info_path" 2>/dev/null || echo "0")
        local now
        now=$(date +%s)
        local stale_ttl
        stale_ttl=$(get_stale_ttl)

        # Check if lock is stale (old timestamp or dead process)
        if [[ $((now - lock_time)) -gt $stale_ttl ]]; then
            warn "Stale lock detected (age: $((now - lock_time))s > TTL: ${stale_ttl}s), removing"
            rm -f "$lock_path" "$info_path"
        elif [[ "$pid" != "0" ]] && ! kill -0 "$pid" 2>/dev/null; then
            warn "Lock held by dead process (PID: $pid), removing"
            rm -f "$lock_path" "$info_path"
        fi
    fi

    # Try flock-based locking first
    if command -v flock &> /dev/null; then
        log "Acquiring lock: $resource (type: $lock_type, timeout: ${timeout}s)"

        # Open lock file and try to acquire exclusive lock
        exec 200>"$lock_path"
        if flock -w "$timeout" 200; then
            # Lock acquired, write info file
            jq -n \
                --arg resource "$resource" \
                --arg type "$lock_type" \
                --argjson pid "$$" \
                --argjson timestamp "$(date +%s)" \
                --arg caller "$caller" \
                --arg hostname "$(hostname)" \
                '{resource: $resource, type: $type, pid: $pid, timestamp: $timestamp, caller: $caller, hostname: $hostname}' > "$info_path"
            chmod 600 "$info_path"

            log "Lock acquired: $resource"
            log_trajectory "lock_acquired" "$(cat "$info_path")"
            return 0
        else
            # SIMSTIM-H-1 FIX: Close file descriptor on timeout to prevent FD leak
            # Log close failure for debugging instead of silent suppression
            local fd_close_error
            fd_close_error=$(exec 200>&- 2>&1) || {
                warn "FD close warning: ${fd_close_error:-close returned non-zero}"
            }
            log "Lock acquisition timed out: $resource"
            log_trajectory "lock_timeout" "{\"resource\": \"$resource\", \"type\": \"$lock_type\", \"timeout\": $timeout}"
            return 1
        fi
    elif is_nfs_fallback_enabled; then
        # NFS fallback: Use atomic mkdir-based locking
        log "flock not available, using mkdir-based fallback"
        acquire_lock_mkdir "$resource" "$lock_type" "$timeout" "$caller"
        return $?
    else
        error "flock not available and NFS fallback disabled"
        return 2
    fi
}

# NFS-safe mkdir-based locking (fallback)
acquire_lock_mkdir() {
    local resource="$1"
    local lock_type="$2"
    local timeout="$3"
    local caller="$4"

    local lock_path
    lock_path=$(get_lock_path "$resource" "$lock_type")
    local lock_dir="${lock_path}.d"

    local info_path
    info_path=$(get_lock_info_path "$lock_path")

    local start_time
    start_time=$(date +%s)
    local max_retries
    max_retries=$(get_max_retries)
    local attempt=0
    local backoff=$DEFAULT_BACKOFF_BASE

    while [[ $attempt -lt $max_retries ]]; do
        local now
        now=$(date +%s)
        if [[ $((now - start_time)) -ge $timeout ]]; then
            log "Lock acquisition timed out (mkdir fallback): $resource"
            return 1
        fi

        # mkdir is atomic on POSIX filesystems
        if mkdir "$lock_dir" 2>/dev/null; then
            # Lock acquired
            jq -n \
                --arg resource "$resource" \
                --arg type "$lock_type" \
                --argjson pid "$$" \
                --argjson timestamp "$(date +%s)" \
                --arg caller "$caller" \
                --arg hostname "$(hostname)" \
                --arg method "mkdir" \
                '{resource: $resource, type: $type, pid: $pid, timestamp: $timestamp, caller: $caller, hostname: $hostname, method: $method}' > "$info_path"
            chmod 600 "$info_path"

            log "Lock acquired (mkdir fallback): $resource"
            log_trajectory "lock_acquired" "$(cat "$info_path")"
            return 0
        fi

        # Check for stale mkdir lock
        if [[ -f "$info_path" ]]; then
            local lock_time pid
            lock_time=$(jq -r '.timestamp // 0' "$info_path" 2>/dev/null || echo "0")
            pid=$(jq -r '.pid // 0' "$info_path" 2>/dev/null || echo "0")
            local stale_ttl
            stale_ttl=$(get_stale_ttl)

            if [[ $((now - lock_time)) -gt $stale_ttl ]]; then
                warn "Stale mkdir lock detected, removing"
                rm -rf "$lock_dir" "$info_path"
                continue
            fi
        fi

        # Exponential backoff with jitter
        local jitter=$((RANDOM % 1000))
        local delay_ms=$((backoff * 1000 + jitter))
        sleep "$(echo "scale=3; $delay_ms / 1000" | bc)"
        backoff=$((backoff * 2))
        if [[ $backoff -gt 30 ]]; then
            backoff=30
        fi
        ((attempt++))
    done

    log "Lock acquisition failed after $max_retries attempts: $resource"
    return 1
}

# =============================================================================
# Lock Release
# =============================================================================

release_lock() {
    local resource="$1"
    local lock_type="${2:-document}"

    local lock_path
    lock_path=$(get_lock_path "$resource" "$lock_type")
    local lock_dir="${lock_path}.d"

    local info_path
    info_path=$(get_lock_info_path "$lock_path")

    # Check if we hold the lock
    if [[ -f "$info_path" ]]; then
        local pid
        pid=$(jq -r '.pid // 0' "$info_path" 2>/dev/null || echo "0")
        if [[ "$pid" != "$$" ]]; then
            warn "Cannot release lock not owned by this process (owner: $pid, us: $$)"
            # Still try to release if process is dead
            if kill -0 "$pid" 2>/dev/null; then
                return 2
            fi
            warn "Lock owner is dead, releasing anyway"
        fi
    fi

    log "Releasing lock: $resource (type: $lock_type)"
    log_trajectory "lock_released" "{\"resource\": \"$resource\", \"type\": \"$lock_type\", \"pid\": $$}"

    # Release flock (close file descriptor)
    exec 200>&- 2>/dev/null || true

    # Remove lock files
    rm -f "$lock_path" "$info_path"

    # Remove mkdir-based lock if exists
    rm -rf "$lock_dir" 2>/dev/null || true

    log "Lock released: $resource"
    return 0
}

# =============================================================================
# With Lock (execute command while holding lock)
# =============================================================================

with_lock() {
    local resource="$1"
    local lock_type="${2:-document}"
    local timeout="${3:-$(get_lock_timeout)}"
    shift 3

    # Acquire lock
    if ! acquire_lock "$resource" "$lock_type" "$timeout" "with_lock"; then
        error "Failed to acquire lock for: $resource"
        return 1
    fi

    # Set up trap to release lock on exit
    trap 'release_lock "$resource" "$lock_type"' EXIT

    # Execute command
    local exit_code=0
    "$@" || exit_code=$?

    # Release lock (trap will also try, but explicit is cleaner)
    release_lock "$resource" "$lock_type"
    trap - EXIT

    return $exit_code
}

# =============================================================================
# Run Mutex (Global Lock for Run Isolation)
# =============================================================================

# Lock order: run → manifest → document (prevents deadlocks)
acquire_run_mutex() {
    local run_id="${1:-unknown}"
    local timeout="${2:-$(get_lock_timeout)}"

    if ! is_run_isolation_enabled; then
        log "Run isolation disabled, skipping run mutex"
        return 0
    fi

    log "Acquiring global run mutex for: $run_id"
    acquire_lock "run" "run" "$timeout" "run:$run_id"
    return $?
}

release_run_mutex() {
    if ! is_run_isolation_enabled; then
        return 0
    fi

    log "Releasing global run mutex"
    release_lock "run" "run"
    return $?
}

# =============================================================================
# Lock Status and Listing
# =============================================================================

list_locks() {
    local active_only="${1:-false}"

    ensure_lock_dir

    local locks=()
    local now
    now=$(date +%s)
    local stale_ttl
    stale_ttl=$(get_stale_ttl)

    # Find all lock info files
    while IFS= read -r -d '' info_file; do
        local lock_info
        lock_info=$(cat "$info_file" 2>/dev/null || echo "{}")

        local timestamp pid resource lock_type
        timestamp=$(echo "$lock_info" | jq -r '.timestamp // 0')
        pid=$(echo "$lock_info" | jq -r '.pid // 0')
        resource=$(echo "$lock_info" | jq -r '.resource // "unknown"')
        lock_type=$(echo "$lock_info" | jq -r '.type // "unknown"')

        # Check if lock is stale or process is dead
        local is_active="true"
        local status="active"
        if [[ $((now - timestamp)) -gt $stale_ttl ]]; then
            is_active="false"
            status="stale"
        elif [[ "$pid" != "0" ]] && ! kill -0 "$pid" 2>/dev/null; then
            is_active="false"
            status="orphaned"
        fi

        if [[ "$active_only" == "true" && "$is_active" == "false" ]]; then
            continue
        fi

        local lock_json
        lock_json=$(echo "$lock_info" | jq \
            --arg status "$status" \
            --argjson age "$((now - timestamp))" \
            '. + {status: $status, age_seconds: $age}')

        locks+=("$lock_json")
    done < <(find "$LOCK_DIR" -name "*.info" -print0 2>/dev/null)

    # Output as JSON array
    if [[ ${#locks[@]} -eq 0 ]]; then
        echo "[]"
    else
        printf '%s\n' "${locks[@]}" | jq -s '.'
    fi
}

lock_status() {
    local resource="$1"
    local lock_type="${2:-document}"

    local lock_path
    lock_path=$(get_lock_path "$resource" "$lock_type")

    local info_path
    info_path=$(get_lock_info_path "$lock_path")

    if [[ ! -f "$info_path" ]]; then
        jq -n --arg resource "$resource" --arg type "$lock_type" \
            '{resource: $resource, type: $type, status: "unlocked"}'
        return 0
    fi

    local lock_info
    lock_info=$(cat "$info_path" 2>/dev/null || echo "{}")

    local timestamp pid
    timestamp=$(echo "$lock_info" | jq -r '.timestamp // 0')
    pid=$(echo "$lock_info" | jq -r '.pid // 0')

    local now
    now=$(date +%s)
    local stale_ttl
    stale_ttl=$(get_stale_ttl)

    local status="locked"
    if [[ $((now - timestamp)) -gt $stale_ttl ]]; then
        status="stale"
    elif [[ "$pid" != "0" ]] && ! kill -0 "$pid" 2>/dev/null; then
        status="orphaned"
    fi

    echo "$lock_info" | jq \
        --arg status "$status" \
        --argjson age "$((now - timestamp))" \
        '. + {status: $status, age_seconds: $age}'
}

# =============================================================================
# Cleanup
# =============================================================================

cleanup_locks() {
    local force="${1:-false}"

    ensure_lock_dir

    local cleaned=0
    local now
    now=$(date +%s)
    local stale_ttl
    stale_ttl=$(get_stale_ttl)

    while IFS= read -r -d '' info_file; do
        local lock_info
        lock_info=$(cat "$info_file" 2>/dev/null || echo "{}")

        local timestamp pid
        timestamp=$(echo "$lock_info" | jq -r '.timestamp // 0')
        pid=$(echo "$lock_info" | jq -r '.pid // 0')

        local should_clean="false"

        if [[ "$force" == "true" ]]; then
            should_clean="true"
        elif [[ $((now - timestamp)) -gt $stale_ttl ]]; then
            should_clean="true"
            log "Cleaning stale lock: $info_file"
        elif [[ "$pid" != "0" ]] && ! kill -0 "$pid" 2>/dev/null; then
            should_clean="true"
            log "Cleaning orphaned lock: $info_file (PID $pid is dead)"
        fi

        if [[ "$should_clean" == "true" ]]; then
            local lock_path="${info_file%.info}.lock"
            local lock_dir="${info_file%.info}.lock.d"
            rm -f "$lock_path" "$info_file"
            rm -rf "$lock_dir" 2>/dev/null || true
            ((cleaned++))
        fi
    done < <(find "$LOCK_DIR" -name "*.info" -print0 2>/dev/null)

    log "Cleaned $cleaned locks"
    echo "$cleaned"
}

# =============================================================================
# Main
# =============================================================================

usage() {
    cat <<EOF
Usage: flatline-lock.sh <command> [options]

Commands:
  acquire <resource>       Acquire lock on resource
    --type <type>          Lock type: run, manifest, document (default: document)
    --timeout <seconds>    Acquisition timeout (default: 10)
    --caller <name>        Caller identifier for debugging

  release <resource>       Release lock on resource
    --type <type>          Lock type (default: document)

  with-lock <resource> -- <command>
                           Execute command while holding lock
    --type <type>          Lock type (default: document)
    --timeout <seconds>    Acquisition timeout (default: 10)

  list                     List all locks
    --active               Only show active locks

  status <resource>        Check lock status
    --type <type>          Lock type (default: document)

  cleanup                  Clean up stale/orphaned locks
    --force                Force cleanup of all locks

  run-acquire <run_id>     Acquire global run mutex
  run-release              Release global run mutex

Examples:
  flatline-lock.sh acquire grimoires/loa/prd.md --type document
  flatline-lock.sh with-lock grimoires/loa/prd.md --type document -- cat file.txt
  flatline-lock.sh list --active
  flatline-lock.sh cleanup

Exit codes:
  0 - Success
  1 - Lock acquisition failed (timeout)
  2 - Lock not found or not owned
  3 - Invalid arguments
  4 - Resource not found
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
        acquire)
            local resource=""
            local lock_type="document"
            local timeout=""
            local caller="cli"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --type)
                        lock_type="$2"
                        shift 2
                        ;;
                    --timeout)
                        timeout="$2"
                        shift 2
                        ;;
                    --caller)
                        caller="$2"
                        shift 2
                        ;;
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        resource="$1"
                        shift
                        ;;
                esac
            done

            if [[ -z "$resource" ]]; then
                error "Resource required"
                exit 3
            fi

            timeout="${timeout:-$(get_lock_timeout)}"
            acquire_lock "$resource" "$lock_type" "$timeout" "$caller"
            ;;

        release)
            local resource=""
            local lock_type="document"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --type)
                        lock_type="$2"
                        shift 2
                        ;;
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        resource="$1"
                        shift
                        ;;
                esac
            done

            if [[ -z "$resource" ]]; then
                error "Resource required"
                exit 3
            fi

            release_lock "$resource" "$lock_type"
            ;;

        with-lock)
            local resource=""
            local lock_type="document"
            local timeout=""
            local cmd_args=()
            local in_cmd=false

            while [[ $# -gt 0 ]]; do
                if [[ "$in_cmd" == "true" ]]; then
                    cmd_args+=("$1")
                    shift
                    continue
                fi

                case "$1" in
                    --type)
                        lock_type="$2"
                        shift 2
                        ;;
                    --timeout)
                        timeout="$2"
                        shift 2
                        ;;
                    --)
                        in_cmd=true
                        shift
                        ;;
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        resource="$1"
                        shift
                        ;;
                esac
            done

            if [[ -z "$resource" ]]; then
                error "Resource required"
                exit 3
            fi

            if [[ ${#cmd_args[@]} -eq 0 ]]; then
                error "Command required after --"
                exit 3
            fi

            timeout="${timeout:-$(get_lock_timeout)}"
            with_lock "$resource" "$lock_type" "$timeout" "${cmd_args[@]}"
            ;;

        list)
            local active_only="false"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --active)
                        active_only="true"
                        shift
                        ;;
                    *)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                esac
            done

            list_locks "$active_only"
            ;;

        status)
            local resource=""
            local lock_type="document"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --type)
                        lock_type="$2"
                        shift 2
                        ;;
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        resource="$1"
                        shift
                        ;;
                esac
            done

            if [[ -z "$resource" ]]; then
                error "Resource required"
                exit 3
            fi

            lock_status "$resource" "$lock_type"
            ;;

        cleanup)
            local force="false"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --force)
                        force="true"
                        shift
                        ;;
                    *)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                esac
            done

            cleanup_locks "$force"
            ;;

        run-acquire)
            local run_id="${1:-unknown}"
            local timeout="${2:-$(get_lock_timeout)}"
            acquire_run_mutex "$run_id" "$timeout"
            ;;

        run-release)
            release_run_mutex
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
