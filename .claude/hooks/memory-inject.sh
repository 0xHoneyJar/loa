#!/usr/bin/env bash
# .claude/hooks/memory-inject.sh
#
# PreToolUse Hook for Loa Memory Stack
# Injects relevant memories into Claude's context before tool execution
#
# Environment Variables (provided by Claude Code hook system):
#   CLAUDE_TOOL_NAME        - Name of tool being invoked
#   CLAUDE_TOOL_INPUT       - JSON input to tool
#   CLAUDE_THINKING_CONTENT - Latest thinking block content (or assistant message)
#   CLAUDE_SESSION_ID       - Current session identifier
#
# Output:
#   JSON with additionalContext field for memory injection
#   Empty JSON {} for no-op
#
# Security Notice (MED-005):
#   This hook logs to trajectory/ which may contain sensitive data including
#   thinking content and memory queries. Trajectory files are in .gitignore.
#   See grimoires/loa/a2a/trajectory/README.md for security recommendations.

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
LOA_DIR="${PROJECT_ROOT}/.loa"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"
HASH_FILE="${LOA_DIR}/last_query_hash"
TRAJECTORY_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"

# Defaults (overridden by config)
THINKING_CHARS=1500
SIMILARITY_THRESHOLD=0.35
MAX_MEMORIES=3
TIMEOUT_MS=500
ENABLED_TOOLS=("Read" "Glob" "Grep" "WebFetch" "WebSearch")

# =============================================================================
# Helper Functions
# =============================================================================

log_trajectory() {
    local event="$1"
    local message="$2"

    mkdir -p "$TRAJECTORY_DIR"
    local trajectory_file="${TRAJECTORY_DIR}/memory-hook-$(date +%Y-%m-%d).jsonl"

    jq -n \
        --arg ts "$(date -Iseconds)" \
        --arg event "$event" \
        --arg msg "$message" \
        --arg tool "${CLAUDE_TOOL_NAME:-unknown}" \
        --arg session "${CLAUDE_SESSION_ID:-unknown}" \
        '{timestamp: $ts, event: $event, message: $msg, tool: $tool, session: $session}' \
        >> "$trajectory_file" 2>/dev/null || true
}

no_op() {
    echo '{}'
    exit 0
}

error_no_op() {
    local message="$1"
    log_trajectory "error" "$message"
    echo '{}'
    exit 0
}

# =============================================================================
# Configuration Loading
# =============================================================================

load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return
    fi

    # Check if hook is enabled
    local enabled
    enabled=$(yq eval '.memory.pretooluse_hook.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
    if [[ "$enabled" != "true" ]]; then
        no_op
    fi

    # Load settings
    THINKING_CHARS=$(yq eval '.memory.pretooluse_hook.thinking_chars // 1500' "$CONFIG_FILE" 2>/dev/null || echo "1500")
    SIMILARITY_THRESHOLD=$(yq eval '.memory.pretooluse_hook.similarity_threshold // 0.35' "$CONFIG_FILE" 2>/dev/null || echo "0.35")
    MAX_MEMORIES=$(yq eval '.memory.pretooluse_hook.max_memories // 3' "$CONFIG_FILE" 2>/dev/null || echo "3")
    TIMEOUT_MS=$(yq eval '.memory.pretooluse_hook.timeout_ms // 500' "$CONFIG_FILE" 2>/dev/null || echo "500")

    # Load enabled tools
    local tools_yaml
    tools_yaml=$(yq eval '.memory.pretooluse_hook.tools // []' "$CONFIG_FILE" 2>/dev/null || echo "[]")
    if [[ "$tools_yaml" != "[]" && "$tools_yaml" != "null" ]]; then
        readarray -t ENABLED_TOOLS < <(yq eval '.memory.pretooluse_hook.tools[]' "$CONFIG_FILE" 2>/dev/null || echo "")
    fi
}

# =============================================================================
# Tool Filter
# =============================================================================

check_tool_enabled() {
    local tool_name="${CLAUDE_TOOL_NAME:-}"

    if [[ -z "$tool_name" ]]; then
        no_op
    fi

    for enabled_tool in "${ENABLED_TOOLS[@]}"; do
        if [[ "$tool_name" == "$enabled_tool" ]]; then
            return 0
        fi
    done

    # Tool not in enabled list
    no_op
}

# =============================================================================
# Context Extraction
# =============================================================================

extract_thinking() {
    local thinking="${CLAUDE_THINKING_CONTENT:-}"

    # Fallback to assistant message if no thinking block
    if [[ -z "$thinking" ]]; then
        thinking="${CLAUDE_ASSISTANT_MESSAGE:-}"
    fi

    if [[ -z "$thinking" ]]; then
        return 1
    fi

    # Extract last N characters
    local len=${#thinking}
    if [[ $len -gt $THINKING_CHARS ]]; then
        local start=$((len - THINKING_CHARS))
        thinking="${thinking:$start}"
    fi

    echo "$thinking"
}

# =============================================================================
# Deduplication
# =============================================================================

check_deduplication() {
    local content="$1"

    # Generate hash
    local hash
    hash=$(echo -n "$content" | sha256sum | cut -c1-16)

    # Check against cached hash
    if [[ -f "$HASH_FILE" ]]; then
        local cached_hash
        cached_hash=$(cat "$HASH_FILE" 2>/dev/null || echo "")

        if [[ "$hash" == "$cached_hash" ]]; then
            log_trajectory "dedup_skip" "Hash match, skipping query"
            no_op
        fi
    fi

    # Update hash cache
    mkdir -p "$LOA_DIR"
    echo "$hash" > "$HASH_FILE"
}

# =============================================================================
# Memory Search
# =============================================================================

search_memories() {
    local query="$1"

    local memory_search="${PROJECT_ROOT}/.claude/hooks/memory-utils/search.sh"
    local memory_admin="${PROJECT_ROOT}/.claude/scripts/memory-admin.sh"

    # Use memory-admin search if search.sh doesn't exist
    if [[ -f "$memory_search" ]]; then
        "$memory_search" "$query" --top-k "$MAX_MEMORIES" --threshold "$SIMILARITY_THRESHOLD"
    elif [[ -f "$memory_admin" ]]; then
        "$memory_admin" search "$query" --top-k "$MAX_MEMORIES" --threshold "$SIMILARITY_THRESHOLD" 2>/dev/null
    else
        echo "[]"
    fi
}

# =============================================================================
# Memory Formatting
# =============================================================================

format_memories() {
    local memories_json="$1"

    # Check if we have results
    local count
    count=$(echo "$memories_json" | jq 'length' 2>/dev/null || echo "0")

    if [[ "$count" -eq 0 || "$count" == "null" ]]; then
        return 1
    fi

    # Format as markdown
    local formatted
    formatted=$(echo "$memories_json" | jq -r '
        "## Recalled Memories (mid-stream)\n\n" +
        (map("- [\(.memory_type | ascii_upcase)] (\(.score)): \(.content | gsub("\n"; " ") | .[0:200])") | join("\n"))
    ' 2>/dev/null)

    if [[ -z "$formatted" || "$formatted" == "null" ]]; then
        return 1
    fi

    echo "$formatted"
}

# =============================================================================
# Main
# =============================================================================

main() {
    # Ensure .loa directory exists
    if [[ ! -d "$LOA_DIR" ]]; then
        no_op
    fi

    # Load configuration
    load_config

    # Check if this tool triggers the hook
    check_tool_enabled

    # Extract thinking context
    local thinking
    thinking=$(extract_thinking) || no_op

    # Check deduplication
    check_deduplication "$thinking"

    # Search for memories (with timeout)
    # HIGH-002 fix: Pass query via environment variable to prevent command injection
    local memories
    export MEMORY_QUERY="$thinking"
    if command -v timeout >/dev/null 2>&1; then
        # Use timeout command (convert ms to seconds for BSD/GNU compatibility)
        local timeout_sec
        timeout_sec=$(echo "scale=2; $TIMEOUT_MS / 1000" | bc 2>/dev/null || echo "0.5")
        memories=$(timeout "${timeout_sec}s" bash -c 'search_memories "$MEMORY_QUERY"' 2>/dev/null) || {
            log_trajectory "timeout" "Memory search exceeded ${TIMEOUT_MS}ms"
            unset MEMORY_QUERY
            no_op
        }
    else
        memories=$(search_memories "$MEMORY_QUERY" 2>/dev/null) || no_op
    fi
    unset MEMORY_QUERY

    # Format memories
    local formatted
    formatted=$(format_memories "$memories") || no_op

    # Log successful injection
    local memory_count
    memory_count=$(echo "$memories" | jq 'length' 2>/dev/null || echo "0")
    log_trajectory "inject" "Injected $memory_count memories"

    # Return additionalContext
    jq -n --arg ctx "$formatted" '{"additionalContext": $ctx}'
}

# Export functions for subshell use
export -f search_memories

# Run main
main "$@"
