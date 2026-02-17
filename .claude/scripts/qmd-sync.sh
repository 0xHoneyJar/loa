#!/usr/bin/env bash
# .claude/scripts/qmd-sync.sh
#
# QMD Index Synchronization for Loa Memory Stack
# Manages QMD collections for semantic document search
#
# Usage:
#   qmd-sync.sh [command] [options]
#
# Commands:
#   sync [--force]     Sync all collections (incremental or full)
#   status             Show collection status
#   create <name>      Create a new collection
#   delete <name>      Delete a collection
#   query <query>      Query across collections
#
# Configuration:
#   Reads from .loa.config.yaml:
#     memory.qmd.enabled: true/false
#     memory.qmd.binary: qmd (path to binary)
#     memory.qmd.index_dir: .loa/qmd
#     memory.qmd.collections: [{name, path, include}]

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"
LOA_DIR="${PROJECT_ROOT}/.loa"
QMD_DIR="${LOA_DIR}/qmd"
MTIME_CACHE="${QMD_DIR}/.mtime_cache"
FAILURE_COUNT_FILE="${QMD_DIR}/.failure_count"

# Defaults
QMD_BINARY="qmd"
QMD_ENABLED=false
MAX_FAILURES=3

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Load configuration from .loa.config.yaml
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_warn "Config file not found: $CONFIG_FILE"
        return 1
    fi

    # Check if QMD is enabled
    QMD_ENABLED=$(yq eval '.memory.qmd.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
    # SECURITY (MEDIUM-004): Validate boolean value
    case "${QMD_ENABLED,,}" in
        true|yes|1) QMD_ENABLED="true" ;;
        *) QMD_ENABLED="false" ;;
    esac
    if [[ "$QMD_ENABLED" != "true" ]]; then
        return 1
    fi

    # Load binary path
    QMD_BINARY=$(yq eval '.memory.qmd.binary // "qmd"' "$CONFIG_FILE" 2>/dev/null || echo "qmd")
    # SECURITY (MEDIUM-004): Validate binary name (alphanumeric, dash, underscore only)
    if [[ ! "$QMD_BINARY" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
        log_error "Invalid QMD binary name in config: $QMD_BINARY"
        QMD_BINARY="qmd"
    fi

    # Load index directory
    local config_dir
    config_dir=$(yq eval '.memory.qmd.index_dir // ".loa/qmd"' "$CONFIG_FILE" 2>/dev/null || echo ".loa/qmd")

    # SECURITY (MEDIUM-004): Validate config path - no traversal or absolute paths
    if [[ "$config_dir" == *".."* ]]; then
        log_error "SECURITY: Config index_dir contains path traversal, using default"
        config_dir=".loa/qmd"
    fi
    if [[ "$config_dir" == /* ]]; then
        log_error "SECURITY: Config index_dir should be relative, using default"
        config_dir=".loa/qmd"
    fi
    if [[ "$config_dir" =~ [\$\`\|\;\&] ]]; then
        log_error "SECURITY: Config index_dir contains shell metacharacters, using default"
        config_dir=".loa/qmd"
    fi

    QMD_DIR="${PROJECT_ROOT}/${config_dir}"

    return 0
}

# Check if QMD binary is available
check_qmd_available() {
    if ! command -v "$QMD_BINARY" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Track QMD failures for auto-disable
track_failure() {
    mkdir -p "$QMD_DIR"
    local count=0
    if [[ -f "$FAILURE_COUNT_FILE" ]]; then
        count=$(cat "$FAILURE_COUNT_FILE" 2>/dev/null || echo "0")
    fi
    count=$((count + 1))
    echo "$count" > "$FAILURE_COUNT_FILE"

    if [[ $count -ge $MAX_FAILURES ]]; then
        log_warn "QMD has failed $count times. Consider disabling in config."
    fi
}

# Reset failure count on success
reset_failures() {
    if [[ -f "$FAILURE_COUNT_FILE" ]]; then
        rm -f "$FAILURE_COUNT_FILE"
    fi
}

# Get file mtime for incremental sync
get_file_mtime() {
    local file="$1"
    stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo "0"
}

# Check if file needs reindex
needs_reindex() {
    local file="$1"
    local collection="$2"
    local cache_file="${QMD_DIR}/${collection}/.mtime_cache"

    if [[ ! -f "$cache_file" ]]; then
        return 0
    fi

    local current_mtime
    current_mtime=$(get_file_mtime "$file")

    local cached_mtime
    cached_mtime=$(grep -F "$file" "$cache_file" 2>/dev/null | cut -d'|' -f2 || echo "0")

    if [[ "$current_mtime" != "$cached_mtime" ]]; then
        return 0
    fi

    return 1
}

# Update mtime cache
update_mtime_cache() {
    local file="$1"
    local collection="$2"
    local cache_file="${QMD_DIR}/${collection}/.mtime_cache"

    mkdir -p "$(dirname "$cache_file")"

    local mtime
    mtime=$(get_file_mtime "$file")

    # Remove old entry and add new one
    # MED-003 fix: Use mktemp for secure temporary file creation
    if [[ -f "$cache_file" ]]; then
        local tmp_file
        tmp_file=$(mktemp "${cache_file}.XXXXXX") || {
            log_warn "Failed to create temp file for cache update"
            return 1
        }
        grep -v -F "$file" "$cache_file" > "$tmp_file" 2>/dev/null || true
        mv "$tmp_file" "$cache_file"
    fi

    echo "${file}|${mtime}" >> "$cache_file"
}

# =============================================================================
# Collection Management
# =============================================================================

# Get configured collections
get_collections() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "[]"
        return
    fi

    yq eval -o json '.memory.qmd.collections // []' "$CONFIG_FILE" 2>/dev/null || echo "[]"
}

# Create a collection
create_collection() {
    local name="$1"
    local collection_dir="${QMD_DIR}/${name}"

    mkdir -p "$collection_dir"
    log_info "Created collection: $name"
}

# Delete a collection
delete_collection() {
    local name="$1"
    local collection_dir="${QMD_DIR}/${name}"

    if [[ -d "$collection_dir" ]]; then
        rm -rf "$collection_dir"
        log_info "Deleted collection: $name"
    else
        log_warn "Collection not found: $name"
    fi
}

# Index files into a collection
index_collection() {
    local name="$1"
    local path="$2"
    local includes="$3"
    local force="${4:-false}"

    local collection_dir="${QMD_DIR}/${name}"
    mkdir -p "$collection_dir"

    # Resolve and validate path (HIGH-003 fix: prevent path traversal)
    local full_path
    full_path=$(realpath "${PROJECT_ROOT}/${path}" 2>/dev/null) || {
        log_warn "Invalid path: $path"
        return 1
    }

    # Ensure the resolved path is within PROJECT_ROOT
    if [[ ! "$full_path" =~ ^"$PROJECT_ROOT" ]]; then
        log_error "Path traversal attempt blocked: $path resolves outside project"
        return 1
    fi

    if [[ ! -d "$full_path" ]]; then
        log_warn "Path not found: $full_path"
        return 1
    fi

    # Register collection with QMD if available (BUG-359 fix)
    # QMD operates at collection level, not per-file
    local qmd_available=false
    if check_qmd_available; then
        qmd_available=true
        # Register collection (idempotent — QMD ignores if already exists)
        local first_mask
        first_mask=$(echo "$includes" | jq -r '.[0] // "*.md"' 2>/dev/null || echo "*.md")
        "$QMD_BINARY" collection add "$full_path" --name "$name" --mask "**/$first_mask" 2>/dev/null || true
    fi

    # Find files matching includes and track mtime changes
    local indexed=0
    local skipped=0

    while IFS= read -r pattern; do
        [[ -z "$pattern" ]] && continue

        # Sanitize pattern to prevent injection
        if [[ "$pattern" =~ [^a-zA-Z0-9_.*-] ]]; then
            log_warn "Skipping invalid pattern: $pattern"
            continue
        fi

        while IFS= read -r -d '' file; do
            # Validate file is within full_path (HIGH-003 fix)
            local real_file
            real_file=$(realpath "$file" 2>/dev/null) || continue
            if [[ ! "$real_file" =~ ^"$full_path" ]]; then
                log_warn "Skipping file outside collection path: $file"
                continue
            fi

            # Check if needs reindex
            if [[ "$force" == "true" ]] || needs_reindex "$real_file" "$name"; then
                update_mtime_cache "$real_file" "$name"
                indexed=$((indexed + 1))
            else
                skipped=$((skipped + 1))
            fi
        done < <(find "$full_path" -type f -name "$pattern" -print0 2>/dev/null)
    done < <(echo "$includes" | jq -r '.[]' 2>/dev/null || echo "*.md")

    # Re-index via QMD after tracking changes (BUG-359 fix)
    if [[ "$qmd_available" == "true" && $indexed -gt 0 ]]; then
        "$QMD_BINARY" update 2>/dev/null || track_failure
    fi

    log_info "Collection '$name': indexed $indexed files, skipped $skipped unchanged"
    return 0
}

# =============================================================================
# Search
# =============================================================================

# Query a collection
query_collection() {
    local query="$1"
    local collection="$2"
    local top_k="${3:-5}"
    local threshold="${4:-0.3}"

    local collection_dir="${QMD_DIR}/${collection}"

    if [[ ! -d "$collection_dir" ]]; then
        echo "[]"
        return
    fi

    if check_qmd_available; then
        # Use QMD for semantic search (BUG-359 fix: use name, not dir path)
        "$QMD_BINARY" search "$query" \
            --collection "$collection" \
            --limit "$top_k" \
            --min-score "$threshold" \
            --format json 2>/dev/null || echo "[]"
    else
        # Fallback: grep-based search
        local cache_file="${collection_dir}/.mtime_cache"
        if [[ ! -f "$cache_file" ]]; then
            echo "[]"
            return
        fi

        local results=()
        while IFS='|' read -r file _mtime; do
            # HIGH-003 fix: Validate file is within PROJECT_ROOT to prevent path traversal
            local real_file
            real_file=$(realpath "$file" 2>/dev/null) || continue

            # Ensure the resolved path starts with PROJECT_ROOT
            if [[ ! "$real_file" =~ ^"$PROJECT_ROOT" ]]; then
                # Log potential attack attempt and skip
                log_warn "Path traversal attempt blocked: $file"
                continue
            fi

            # Ensure file exists and is a regular file
            if [[ ! -f "$real_file" ]]; then
                continue
            fi

            if grep -l -i "$query" "$real_file" >/dev/null 2>&1; then
                # Extract snippet - use real_file for actual read
                local snippet
                snippet=$(grep -i -m1 "$query" "$real_file" 2>/dev/null | head -c 200 || echo "")
                # Escape JSON special characters in snippet
                snippet=$(echo "$snippet" | jq -Rs '.' | sed 's/^"//;s/"$//')
                results+=("{\"file\":\"$real_file\",\"score\":0.5,\"snippet\":\"$snippet\"}")
            fi
        done < "$cache_file"

        # Return as JSON array
        if [[ ${#results[@]} -eq 0 ]]; then
            echo "[]"
        else
            printf '%s\n' "${results[@]}" | head -n "$top_k" | jq -s '.' 2>/dev/null || echo "[]"
        fi
    fi
}

# Query all collections
query_all() {
    local query="$1"
    local top_k="${2:-5}"
    local threshold="${3:-0.3}"

    local all_results=()

    # Get collection names
    local collections
    collections=$(get_collections)

    while IFS= read -r collection; do
        [[ -z "$collection" ]] && continue
        local name
        name=$(echo "$collection" | jq -r '.name // empty' 2>/dev/null)
        [[ -z "$name" ]] && continue

        local results
        results=$(query_collection "$query" "$name" "$top_k" "$threshold")
        if [[ "$results" != "[]" ]]; then
            all_results+=("$results")
        fi
    done < <(echo "$collections" | jq -c '.[]' 2>/dev/null)

    # Merge and sort by score
    if [[ ${#all_results[@]} -eq 0 ]]; then
        echo "[]"
    else
        printf '%s\n' "${all_results[@]}" | jq -s 'add | sort_by(-.score) | .[0:'"$top_k"']' 2>/dev/null || echo "[]"
    fi
}

# =============================================================================
# Commands
# =============================================================================

cmd_sync() {
    local force=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                force=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if ! load_config; then
        log_warn "QMD is disabled or config missing"
        return 0
    fi

    mkdir -p "$QMD_DIR"

    local collections
    collections=$(get_collections)

    if [[ "$collections" == "[]" || "$collections" == "null" ]]; then
        log_warn "No collections configured"
        return 0
    fi

    local synced=0
    while IFS= read -r collection; do
        [[ -z "$collection" ]] && continue

        local name path includes
        name=$(echo "$collection" | jq -r '.name // empty')
        path=$(echo "$collection" | jq -r '.path // empty')
        includes=$(echo "$collection" | jq -c '.include // ["*.md"]')

        if [[ -z "$name" || -z "$path" ]]; then
            continue
        fi

        log_info "Syncing collection: $name"
        if index_collection "$name" "$path" "$includes" "$force"; then
            ((synced++))
        fi
    done < <(echo "$collections" | jq -c '.[]' 2>/dev/null)

    if [[ $synced -gt 0 ]]; then
        reset_failures
    fi

    log_info "Sync complete: $synced collections processed"
}

cmd_status() {
    if ! load_config; then
        echo "QMD Status: DISABLED"
        return 0
    fi

    echo "QMD Status: ENABLED"
    echo "Binary: $QMD_BINARY ($(check_qmd_available && echo "available" || echo "NOT FOUND"))"
    echo "Index Dir: $QMD_DIR"
    echo ""
    echo "Collections:"

    local collections
    collections=$(get_collections)

    while IFS= read -r collection; do
        [[ -z "$collection" ]] && continue

        local name path
        name=$(echo "$collection" | jq -r '.name // empty')
        path=$(echo "$collection" | jq -r '.path // empty')

        local collection_dir="${QMD_DIR}/${name}"
        local file_count=0
        if [[ -f "${collection_dir}/.mtime_cache" ]]; then
            file_count=$(wc -l < "${collection_dir}/.mtime_cache" 2>/dev/null || echo "0")
        fi

        echo "  - $name: $path ($file_count files indexed)"
    done < <(echo "$collections" | jq -c '.[]' 2>/dev/null)
}

cmd_create() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        log_error "Usage: qmd-sync.sh create <name>"
        exit 1
    fi
    create_collection "$name"
}

cmd_delete() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        log_error "Usage: qmd-sync.sh delete <name>"
        exit 1
    fi
    delete_collection "$name"
}

cmd_query() {
    local query="${1:-}"
    if [[ -z "$query" ]]; then
        log_error "Usage: qmd-sync.sh query <query>"
        exit 1
    fi

    if ! load_config; then
        log_warn "QMD is disabled"
        echo "[]"
        return 0
    fi

    query_all "$query"
}

cmd_help() {
    cat <<EOF
QMD Index Synchronization for Loa Memory Stack

Usage:
  qmd-sync.sh [command] [options]

Commands:
  sync [--force]     Sync all collections (incremental or full)
  status             Show collection status
  create <name>      Create a new collection
  delete <name>      Delete a collection
  query <query>      Query across all collections
  help               Show this help

Configuration (in .loa.config.yaml):
  memory:
    qmd:
      enabled: true
      binary: qmd
      index_dir: .loa/qmd
      collections:
        - name: loa-state
          path: grimoires/loa
          include: ["*.md"]
        - name: loa-reality
          path: grimoires/loa/reality
          include: ["*.md"]

Examples:
  qmd-sync.sh sync              # Incremental sync
  qmd-sync.sh sync --force      # Full reindex
  qmd-sync.sh status            # Check status
  qmd-sync.sh query "auth flow" # Search documents
EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        sync)
            cmd_sync "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        create)
            cmd_create "$@"
            ;;
        delete)
            cmd_delete "$@"
            ;;
        query)
            cmd_query "$@"
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            log_error "Unknown command: $command"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
