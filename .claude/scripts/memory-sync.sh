#!/usr/bin/env bash
# .claude/scripts/memory-sync.sh
#
# Memory Sync Utilities for Loa Memory Stack
# Syncs learnings from NOTES.md and /retrospective to vector database
#
# Usage:
#   memory-sync.sh notes              Sync learnings from NOTES.md
#   memory-sync.sh retrospective      Extract memories from retrospective output
#   memory-sync.sh auto               Auto-sync on session start (if enabled)
#   memory-sync.sh status             Show sync status

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

MEMORY_ADMIN="${PROJECT_ROOT}/.claude/scripts/memory-admin.sh"
NOTES_FILE=$(get_notes_path)
SYNC_STATE_FILE="${PROJECT_ROOT}/.loa/sync_state.json"
TRAJECTORY_DIR=$(get_trajectory_dir)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Log trajectory event
log_trajectory() {
    local event="$1"
    local data="$2"

    mkdir -p "$TRAJECTORY_DIR"
    local trajectory_file="${TRAJECTORY_DIR}/memory-sync-$(date +%Y-%m-%d).jsonl"

    jq -n \
        --arg ts "$(date -Iseconds)" \
        --arg event "$event" \
        --arg data "$data" \
        '{timestamp: $ts, event: $event, data: $data}' \
        >> "$trajectory_file" 2>/dev/null || true
}

# Load sync state
load_sync_state() {
    if [[ -f "$SYNC_STATE_FILE" ]]; then
        cat "$SYNC_STATE_FILE"
    else
        echo "{}"
    fi
}

# Save sync state
save_sync_state() {
    local key="$1"
    local value="$2"
    local state

    mkdir -p "$(dirname "$SYNC_STATE_FILE")"
    state=$(load_sync_state)
    echo "$state" | jq --arg k "$key" --arg v "$value" '.[$k] = $v' > "$SYNC_STATE_FILE"
}

# Get file hash for change detection
get_file_hash() {
    local file="$1"
    if [[ -f "$file" ]]; then
        sha256sum "$file" 2>/dev/null | cut -c1-16
    else
        echo "missing"
    fi
}

# Check if memory-admin is available
check_memory_admin() {
    if [[ ! -f "$MEMORY_ADMIN" ]]; then
        log_error "memory-admin.sh not found"
        return 1
    fi

    if ! "$MEMORY_ADMIN" stats >/dev/null 2>&1; then
        log_warn "Memory database not initialized. Run: memory-admin.sh init"
        return 1
    fi

    return 0
}

# =============================================================================
# NOTES.md Learnings Sync
# =============================================================================

# Extract learnings section from NOTES.md
extract_learnings() {
    local notes_file="$1"

    if [[ ! -f "$notes_file" ]]; then
        return
    fi

    # Extract content between ## Learnings and the next ## header
    awk '
        /^## Learnings/ { capture = 1; next }
        /^## / { capture = 0 }
        capture && /^- / { print }
    ' "$notes_file"
}

# Parse a learning line into memory content and type
parse_learning() {
    local line="$1"

    # Remove leading "- " or "- [ ] " or "- [x] "
    local content
    content=$(echo "$line" | sed -E 's/^- (\[.\] )?//')

    # Detect type from tags like [GOTCHA], [PATTERN], etc.
    local type="learning"
    if [[ "$content" =~ \[GOTCHA\] ]]; then
        type="gotcha"
        content=$(echo "$content" | sed 's/\[GOTCHA\] *//')
    elif [[ "$content" =~ \[PATTERN\] ]]; then
        type="pattern"
        content=$(echo "$content" | sed 's/\[PATTERN\] *//')
    elif [[ "$content" =~ \[DECISION\] ]]; then
        type="decision"
        content=$(echo "$content" | sed 's/\[DECISION\] *//')
    fi

    # Remove skill references like "→ See skills/..."
    content=$(echo "$content" | sed 's/ *→.*$//')

    echo "$type|$content"
}

# Sync learnings from NOTES.md
sync_notes() {
    log_info "Syncing learnings from NOTES.md..."

    if ! check_memory_admin; then
        return 1
    fi

    if [[ ! -f "$NOTES_FILE" ]]; then
        log_warn "NOTES.md not found: $NOTES_FILE"
        return 0
    fi

    # Check if file changed since last sync
    local current_hash
    current_hash=$(get_file_hash "$NOTES_FILE")
    local last_hash
    last_hash=$(load_sync_state | jq -r '.notes_hash // ""')

    if [[ "$current_hash" == "$last_hash" ]]; then
        log_info "NOTES.md unchanged since last sync"
        return 0
    fi

    # Extract and process learnings
    local synced=0
    local skipped=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local parsed
        parsed=$(parse_learning "$line")
        local type="${parsed%%|*}"
        local content="${parsed#*|}"

        # Skip empty or very short content
        if [[ ${#content} -lt 10 ]]; then
            ((skipped++))
            continue
        fi

        # Check for duplicates by searching
        local exists
        exists=$("$MEMORY_ADMIN" search "$content" --top-k 1 --threshold 0.9 2>/dev/null | jq 'length' || echo "0")

        if [[ "$exists" -gt 0 ]]; then
            log_info "Skipping duplicate: ${content:0:50}..."
            ((skipped++))
            continue
        fi

        # Add memory
        if "$MEMORY_ADMIN" add "$content" --type "$type" --source "NOTES.md" >/dev/null 2>&1; then
            ((synced++))
            log_trajectory "notes_sync" "$content"
        else
            log_warn "Failed to add: ${content:0:50}..."
        fi
    done < <(extract_learnings "$NOTES_FILE")

    # Update sync state
    save_sync_state "notes_hash" "$current_hash"
    save_sync_state "notes_sync_time" "$(date -Iseconds)"

    log_success "Synced $synced learnings from NOTES.md (skipped $skipped)"
}

# =============================================================================
# Retrospective Memory Extraction
# =============================================================================

# Extract memories from retrospective JSON output
extract_from_retrospective() {
    local input="$1"

    # Parse retrospective output format
    # Expected: JSON with skills array or markdown with bullet points
    if echo "$input" | jq -e '.' >/dev/null 2>&1; then
        # JSON format
        echo "$input" | jq -r '
            .skills // [] | .[] |
            "\(.type // "learning")|\(.content)"
        ' 2>/dev/null
    else
        # Markdown format - extract bullet points
        echo "$input" | grep -E '^\s*[-*]' | while read -r line; do
            parse_learning "$line"
        done
    fi
}

# Sync from retrospective output (stdin or file)
sync_retrospective() {
    log_info "Extracting memories from retrospective..."

    if ! check_memory_admin; then
        return 1
    fi

    local input
    if [[ -p /dev/stdin ]]; then
        input=$(cat)
    elif [[ -n "${1:-}" && -f "$1" ]]; then
        input=$(cat "$1")
    else
        log_error "No input provided. Pipe retrospective output or provide file."
        return 1
    fi

    local synced=0
    local skipped=0

    while IFS='|' read -r type content; do
        [[ -z "$content" ]] && continue

        # Skip very short content
        if [[ ${#content} -lt 10 ]]; then
            ((skipped++))
            continue
        fi

        # Check for duplicates
        local exists
        exists=$("$MEMORY_ADMIN" search "$content" --top-k 1 --threshold 0.9 2>/dev/null | jq 'length' || echo "0")

        if [[ "$exists" -gt 0 ]]; then
            log_info "Skipping duplicate: ${content:0:50}..."
            ((skipped++))
            continue
        fi

        # Add memory
        if "$MEMORY_ADMIN" add "$content" --type "$type" --source "retrospective" >/dev/null 2>&1; then
            ((synced++))
            log_trajectory "retrospective_extract" "$content"
        fi
    done < <(extract_from_retrospective "$input")

    log_success "Extracted $synced memories from retrospective (skipped $skipped)"
}

# =============================================================================
# Auto Sync
# =============================================================================

# Auto-sync on session start (if enabled in config)
auto_sync() {
    # Check if auto-sync is enabled
    if [[ -f "$CONFIG_FILE" ]]; then
        local enabled
        enabled=$(yq eval '.memory.auto_sync // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
        if [[ "$enabled" != "true" ]]; then
            log_info "Auto-sync disabled in config"
            return 0
        fi
    fi

    sync_notes
}

# =============================================================================
# Status
# =============================================================================

show_status() {
    echo "Memory Sync Status"
    echo "=================="
    echo ""

    # Check memory-admin
    if check_memory_admin 2>/dev/null; then
        echo "Memory Database: OK"
        local stats
        stats=$("$MEMORY_ADMIN" stats 2>/dev/null || echo "{}")
        echo "  Total memories: $(echo "$stats" | jq -r '.total_memories // "unknown"')"
    else
        echo "Memory Database: NOT INITIALIZED"
    fi

    echo ""

    # Check NOTES.md
    if [[ -f "$NOTES_FILE" ]]; then
        local learnings_count
        learnings_count=$(extract_learnings "$NOTES_FILE" | wc -l)
        echo "NOTES.md: Found ($learnings_count learnings)"

        local last_sync
        last_sync=$(load_sync_state | jq -r '.notes_sync_time // "never"')
        echo "  Last sync: $last_sync"
    else
        echo "NOTES.md: NOT FOUND"
    fi

    echo ""

    # Check trajectory
    if [[ -d "$TRAJECTORY_DIR" ]]; then
        local trajectory_count
        trajectory_count=$(find "$TRAJECTORY_DIR" -name "memory-sync-*.jsonl" 2>/dev/null | wc -l)
        echo "Trajectory logs: $trajectory_count files"
    else
        echo "Trajectory logs: None"
    fi
}

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat <<EOF
Memory Sync Utilities for Loa Memory Stack

Usage:
  memory-sync.sh notes              Sync learnings from NOTES.md
  memory-sync.sh retrospective      Extract memories from retrospective output
  memory-sync.sh auto               Auto-sync on session start (if enabled)
  memory-sync.sh status             Show sync status
  memory-sync.sh help               Show this help

NOTES.md Sync:
  Extracts learnings from the ## Learnings section of NOTES.md.
  Supports type tags: [GOTCHA], [PATTERN], [DECISION]
  Deduplicates against existing memories.

Retrospective Sync:
  Pipe retrospective output to extract memories:
    /retrospective | memory-sync.sh retrospective
  Or provide a file:
    memory-sync.sh retrospective output.json

Configuration (.loa.config.yaml):
  memory:
    auto_sync: true    # Enable auto-sync on session start
EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        notes)
            sync_notes "$@"
            ;;
        retrospective)
            sync_retrospective "$@"
            ;;
        auto)
            auto_sync "$@"
            ;;
        status)
            show_status "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
