#!/usr/bin/env bash
# memory-writer.sh - Post-tool hook: Capture observations for persistent memory
#
# This hook captures significant discoveries and learnings from tool outputs
# and stores them in the persistent memory system for cross-session recall.
#
# Usage (via Claude Code hook):
#   PostToolUse hook registered in settings.json
#
# Environment:
#   PROJECT_ROOT - Project root directory (defaults to pwd)
#   LOA_SESSION_ID - Session identifier (defaults to date-pid)
#   LOA_MEMORY_ENABLED - Set to "false" to disable (defaults to "true")
#
# Exit codes:
#   0 - Always (never block tool execution)

set -euo pipefail

# Configuration
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
SESSION_ID="${LOA_SESSION_ID:-$(date +%Y%m%d)-$$}"

# Resolve memory directory via path-lib (with fallback to legacy path)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PATH_LIB_LOADED=false
if [[ -f "$SCRIPT_DIR/../scripts/path-lib.sh" ]]; then
    source "$SCRIPT_DIR/../scripts/path-lib.sh" 2>/dev/null && _PATH_LIB_LOADED=true
fi
if [[ "$_PATH_LIB_LOADED" == "true" ]]; then
    MEMORY_DIR=$(get_state_memory_dir 2>/dev/null) || MEMORY_DIR="$PROJECT_ROOT/grimoires/loa/memory"
else
    MEMORY_DIR="$PROJECT_ROOT/grimoires/loa/memory"
fi
MEMORY_ENABLED="${LOA_MEMORY_ENABLED:-true}"

# Skip if disabled
if [[ "$MEMORY_ENABLED" == "false" ]]; then
    exit 0
fi

# Tool name and output from hook parameters
TOOL_NAME="${1:-unknown}"
# Read tool output from stdin or second argument
if [[ -n "${2:-}" ]]; then
    TOOL_OUTPUT="$2"
else
    TOOL_OUTPUT=$(cat 2>/dev/null || echo "")
fi

# =============================================================================
# Configuration Reading
# =============================================================================

CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"

read_config() {
    local path="$1"
    local default="$2"
    if [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null; then
        local value
        value=$(yq -r "$path // \"\"" "$CONFIG_FILE" 2>/dev/null)
        if [[ -n "$value" && "$value" != "null" ]]; then
            echo "$value"
            return
        fi
    fi
    echo "$default"
}

# Check if memory capture is enabled in config
is_capture_enabled() {
    local enabled
    enabled=$(read_config '.memory.enabled' 'true')
    [[ "$enabled" == "true" ]]
}

# =============================================================================
# Tool Filtering
# =============================================================================

# Skip read-only tools (they don't generate learnings)
should_skip_tool() {
    local tool="$1"
    case "$tool" in
        Read|Glob|Grep|Bash)
            # Skip read-only and general-purpose tools
            return 0
            ;;
        Write|Edit|NotebookEdit)
            # Capture write operations that may contain learnings
            return 1
            ;;
        Task|TaskOutput)
            # Capture task completions
            return 1
            ;;
        *)
            # Default: capture
            return 1
            ;;
    esac
}

# =============================================================================
# Learning Signal Detection
# =============================================================================

# Learning signals that indicate an observation worth capturing
LEARNING_PATTERNS=(
    "discovered"
    "learned"
    "fixed"
    "resolved"
    "pattern"
    "insight"
    "realized"
    "found the issue"
    "root cause"
    "the solution"
    "turns out"
    "TIL"
    "important note"
    "for future reference"
)

has_learning_signal() {
    local output="$1"

    for pattern in "${LEARNING_PATTERNS[@]}"; do
        if echo "$output" | grep -qiE "$pattern"; then
            return 0
        fi
    done
    return 1
}

# Detect observation type from content
detect_observation_type() {
    local output="$1"

    if echo "$output" | grep -qiE "(error|exception|failed|bug|crash)"; then
        echo "error"
    elif echo "$output" | grep -qiE "(decided|chose|selected|will use|architecture)"; then
        echo "decision"
    elif echo "$output" | grep -qiE "(pattern|recurring|always|every time)"; then
        echo "pattern"
    elif echo "$output" | grep -qiE "(learned|TIL|realized|insight)"; then
        echo "learning"
    else
        echo "discovery"
    fi
}

# Check for private/sensitive content markers
is_private_content() {
    local output="$1"

    if echo "$output" | grep -qiE "(<private>|PRIVATE|SECRET|API_KEY|password|credential)"; then
        return 0
    fi
    return 1
}

# =============================================================================
# Observation Creation
# =============================================================================

create_observation() {
    local tool="$1"
    local output="$2"

    # Extract summary (first 200 chars, cleaned)
    local summary
    summary=$(echo "$output" | head -c 200 | tr '\n' ' ' | sed 's/"/\\"/g')

    # Detect type
    local obs_type
    obs_type=$(detect_observation_type "$output")

    # Check privacy
    local is_private=false
    if is_private_content "$output"; then
        is_private=true
        summary="[REDACTED - contains sensitive information]"
    fi

    # Generate unique ID
    local obs_id
    obs_id="obs-$(date +%s)-$(echo "$output" | sha256sum | cut -c1-8)"

    # Create observation JSON (using jq for proper escaping)
    local observation
    observation=$(jq -n \
        --arg id "$obs_id" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg session_id "$SESSION_ID" \
        --arg type "$obs_type" \
        --arg summary "$summary" \
        --arg tool "$tool" \
        --argjson private "$is_private" \
        --arg details "" \
        '{
            id: $id,
            timestamp: $timestamp,
            session_id: $session_id,
            type: $type,
            summary: $summary,
            tool: $tool,
            private: $private,
            details: $details,
            tags: [],
            references: []
        }')

    echo "$observation"
}

# =============================================================================
# Storage
# =============================================================================

# Atomic append with file locking to prevent concurrent write corruption
# Uses flock for exclusive lock during JSONL writes
locked_append() {
    local file="$1"
    local content="$2"
    local lock_file="${file}.lock"

    # Use flock for atomic append (fd 200 for lock)
    (
        flock -x 200 2>/dev/null || true  # Continue even if flock unavailable
        echo "$content" >> "$file"
    ) 200>"$lock_file"
}

store_observation() {
    local observation="$1"

    # Ensure directories exist
    mkdir -p "$MEMORY_DIR/sessions"

    # Append to main observations file (prefer append_jsonl from path-lib if available)
    if [[ "$_PATH_LIB_LOADED" == "true" ]] && type append_jsonl &>/dev/null; then
        append_jsonl "$MEMORY_DIR/observations.jsonl" "$observation" 2>/dev/null || \
            locked_append "$MEMORY_DIR/observations.jsonl" "$observation"
    else
        locked_append "$MEMORY_DIR/observations.jsonl" "$observation"
    fi

    # Append to session-specific file (with locking)
    local session_file="$MEMORY_DIR/sessions/${SESSION_ID}.jsonl"
    locked_append "$session_file" "$observation"

    # Check retention limits
    enforce_retention_limits
}

enforce_retention_limits() {
    local max_observations
    max_observations=$(read_config '.memory.max_observations' '10000')

    # Count current observations
    local current_count
    current_count=$(wc -l < "$MEMORY_DIR/observations.jsonl" 2>/dev/null || echo "0")

    # If over limit, archive oldest (with locking to prevent TOCTOU race)
    if [[ $current_count -gt $max_observations ]]; then
        local archive_dir="$MEMORY_DIR/archive"
        mkdir -p "$archive_dir"

        local excess=$((current_count - max_observations))
        local archive_file="$archive_dir/archived-$(date +%Y%m%d).jsonl"
        local lock_file="$MEMORY_DIR/observations.jsonl.lock"

        # Use flock for atomic archival operation
        (
            flock -x 200 2>/dev/null || true
            # Move oldest entries to archive
            head -n "$excess" "$MEMORY_DIR/observations.jsonl" >> "$archive_file"
            tail -n "+$((excess + 1))" "$MEMORY_DIR/observations.jsonl" > "$MEMORY_DIR/observations.jsonl.tmp"
            mv "$MEMORY_DIR/observations.jsonl.tmp" "$MEMORY_DIR/observations.jsonl"
        ) 200>"$lock_file"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    # Check if capture is enabled
    if ! is_capture_enabled; then
        exit 0
    fi

    # Skip certain tools
    if should_skip_tool "$TOOL_NAME"; then
        exit 0
    fi

    # Skip empty output
    if [[ -z "$TOOL_OUTPUT" ]]; then
        exit 0
    fi

    # Check for learning signals
    if ! has_learning_signal "$TOOL_OUTPUT"; then
        exit 0
    fi

    # Create and store observation
    local observation
    observation=$(create_observation "$TOOL_NAME" "$TOOL_OUTPUT")

    store_observation "$observation"
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# Always exit 0 to never block tool execution
exit 0
