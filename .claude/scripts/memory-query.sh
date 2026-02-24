#!/usr/bin/env bash
# memory-query.sh - Query persistent memory observations
#
# Provides token-efficient access to stored observations with
# progressive disclosure (index → summary → full).
#
# Usage:
#   memory-query.sh --index                    # List recent observations (~50 tokens)
#   memory-query.sh --type learning --limit 5  # Filter by type
#   memory-query.sh --since 2026-02-01         # Filter by date
#   memory-query.sh --full <id>                # Get full details
#   memory-query.sh "search query"             # Free-text search
#
# Exit codes:
#   0 - Success
#   1 - Invalid arguments or no results

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source bootstrap if available
if [[ -f "$SCRIPT_DIR/bootstrap.sh" ]]; then
    source "$SCRIPT_DIR/bootstrap.sh"
fi

# Configuration
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

# Resolve memory directory via path-lib (with fallback to legacy path)
if type get_state_memory_dir &>/dev/null; then
    MEMORY_DIR=$(get_state_memory_dir 2>/dev/null) || MEMORY_DIR="$PROJECT_ROOT/grimoires/loa/memory"
elif [[ -f "$SCRIPT_DIR/path-lib.sh" ]]; then
    source "$SCRIPT_DIR/path-lib.sh" 2>/dev/null && {
        MEMORY_DIR=$(get_state_memory_dir 2>/dev/null) || MEMORY_DIR="$PROJECT_ROOT/grimoires/loa/memory"
    }
else
    MEMORY_DIR="$PROJECT_ROOT/grimoires/loa/memory"
fi
OBSERVATIONS_FILE="$MEMORY_DIR/observations.jsonl"

# =============================================================================
# Usage
# =============================================================================

usage() {
    cat <<'EOF'
Usage: memory-query.sh [OPTIONS] [QUERY]

Query persistent memory observations with progressive disclosure.

Options:
  --index              Show index only (~50 tokens per entry)
  --type TYPE          Filter by observation type (discovery|learning|pattern|error|decision)
  --tags TAGS          Filter by tags (comma-separated)
  --since DATE         Filter by date (YYYY-MM-DD)
  --limit N            Limit results (default: 10)
  --full ID            Get full details for observation ID (~500 tokens)
  --summary            Show summary view (~200 tokens per entry)
  --session ID         Filter by session ID
  --json               Output as JSON (default)
  --table              Output as markdown table
  --stats              Show memory statistics
  -h, --help           Show this help

Disclosure Levels:
  Level 1 (--index):   ~50 tokens  - ID, type, timestamp only
  Level 2 (--summary): ~200 tokens - ID, type, summary
  Level 3 (--full):    ~500 tokens - Complete observation

Examples:
  memory-query.sh --index
  memory-query.sh --type learning --limit 5
  memory-query.sh --since 2026-02-01
  memory-query.sh --full obs-1234567890-abc123
  memory-query.sh "authentication pattern"
  memory-query.sh --stats
EOF
}

# =============================================================================
# Validation
# =============================================================================

check_observations_file() {
    if [[ ! -f "$OBSERVATIONS_FILE" ]]; then
        echo "No observations found at $OBSERVATIONS_FILE" >&2
        echo "Memory system may not be initialized." >&2
        exit 1
    fi

    if [[ ! -s "$OBSERVATIONS_FILE" ]]; then
        echo "No observations recorded yet." >&2
        exit 0
    fi
}

# =============================================================================
# Query Functions
# =============================================================================

# Level 1: Index only (~50 tokens per entry)
show_index() {
    local limit="${1:-10}"

    jq -s "
        [.[] | select(.private != true)] |
        .[-$limit:] |
        reverse |
        .[] |
        {id, type, timestamp: .timestamp[0:10]}
    " "$OBSERVATIONS_FILE" 2>/dev/null || echo "[]"
}

# Level 2: Summary view (~200 tokens per entry)
show_summary() {
    local limit="${1:-10}"

    jq -s "
        [.[] | select(.private != true)] |
        .[-$limit:] |
        reverse |
        .[] |
        {id, type, timestamp: .timestamp[0:10], summary: (.summary[0:100] + \"...\")}
    " "$OBSERVATIONS_FILE" 2>/dev/null || echo "[]"
}

# Level 3: Full details (~500 tokens)
show_full() {
    local obs_id="$1"

    if [[ -z "$obs_id" ]]; then
        echo "Error: Observation ID required" >&2
        exit 1
    fi

    # SECURITY FIX M1: Use jq --arg to prevent injection
    local result
    result=$(jq -s --arg id "$obs_id" '.[] | select(.id == $id)' "$OBSERVATIONS_FILE" 2>/dev/null)

    if [[ -z "$result" || "$result" == "null" ]]; then
        echo "Observation not found: $obs_id" >&2
        exit 1
    fi

    echo "$result"
}

# Filter by type
filter_by_type() {
    local obs_type="$1"
    local limit="${2:-10}"

    # SECURITY FIX M2: Use jq --arg to prevent injection
    jq -s --arg t "$obs_type" --argjson lim "$limit" '
        [.[] | select(.private != true) | select(.type == $t)] |
        .[-$lim:] |
        reverse |
        .[] |
        {id, type, timestamp: .timestamp[0:10], summary: (.summary[0:100] + "...")}
    ' "$OBSERVATIONS_FILE" 2>/dev/null || echo "[]"
}

# Filter by tags
filter_by_tags() {
    local tags="$1"
    local limit="${2:-10}"

    # Convert comma-separated tags to jq array
    local tag_array
    tag_array=$(echo "$tags" | tr ',' '\n' | jq -R . | jq -s .)

    jq -s --argjson tags "$tag_array" "
        [.[] | select(.private != true) | select(any(.tags[]; . as \$t | \$tags | any(. == \$t)))] |
        .[-$limit:] |
        reverse |
        .[] |
        {id, type, timestamp: .timestamp[0:10], summary}
    " "$OBSERVATIONS_FILE" 2>/dev/null || echo "[]"
}

# Filter by date
filter_by_date() {
    local since_date="$1"
    local limit="${2:-10}"

    jq -s --arg since "$since_date" "
        [.[] | select(.private != true) | select(.timestamp >= \$since)] |
        .[-$limit:] |
        reverse |
        .[] |
        {id, type, timestamp: .timestamp[0:10], summary: (.summary[0:100] + \"...\")}
    " "$OBSERVATIONS_FILE" 2>/dev/null || echo "[]"
}

# Filter by session
filter_by_session() {
    local session_id="$1"
    local limit="${2:-10}"

    jq -s --arg session "$session_id" "
        [.[] | select(.private != true) | select(.session_id == \$session)] |
        .[-$limit:] |
        reverse |
        .[] |
        {id, type, timestamp: .timestamp[0:10], summary}
    " "$OBSERVATIONS_FILE" 2>/dev/null || echo "[]"
}

# Free-text search
search_observations() {
    local query="$1"
    local limit="${2:-10}"

    # SECURITY FIX M3: Use grep -F for literal matching (prevents regex injection)
    # This prevents ReDoS attacks and unexpected regex behavior
    grep -iF "$query" "$OBSERVATIONS_FILE" 2>/dev/null | \
        tail -n "$limit" | \
        jq -s '.[] | {id, type, timestamp: .timestamp[0:10], summary: (.summary[0:100] + "...")}' 2>/dev/null || echo "[]"
}

# =============================================================================
# Lore Query Functions (FR-5 — Temporal Lore Depth)
# =============================================================================

LORE_DIR="${LORE_DIR:-$PROJECT_ROOT/.claude/data/lore}"
DISCOVERED_DIR="${DISCOVERED_DIR:-$LORE_DIR/discovered}"

# List all lore entries with lifecycle metadata
show_lore() {
    local sort_by="${1:-id}"
    local filter_significance="${2:-}"
    local filter_repo="${3:-}"
    local limit="${4:-20}"

    local lore_files=("$DISCOVERED_DIR/patterns.yaml" "$DISCOVERED_DIR/visions.yaml")
    local all_entries="[]"

    for lf in "${lore_files[@]}"; do
        [[ -f "$lf" ]] || continue
        local entries
        entries=$(yq -o=json '.entries // []' "$lf" 2>/dev/null) || continue
        all_entries=$(echo "$all_entries" | jq --argjson new "$entries" '. + $new')
    done

    # Apply filters
    if [[ -n "$filter_significance" ]]; then
        all_entries=$(echo "$all_entries" | jq --arg sig "$filter_significance" \
            '[.[] | select((.lifecycle.significance // "one-off") == $sig)]')
    fi

    if [[ -n "$filter_repo" ]]; then
        all_entries=$(echo "$all_entries" | jq --arg repo "$filter_repo" \
            '[.[] | select((.lifecycle.repos // []) | any(. == $repo))]')
    fi

    # Sort
    case "$sort_by" in
        references)
            all_entries=$(echo "$all_entries" | jq 'sort_by(-(.lifecycle.references // 0))')
            ;;
        last_seen)
            all_entries=$(echo "$all_entries" | jq 'sort_by(.lifecycle.last_seen // "0000") | reverse')
            ;;
        *)
            all_entries=$(echo "$all_entries" | jq 'sort_by(.id)')
            ;;
    esac

    # Apply limit
    all_entries=$(echo "$all_entries" | jq --argjson lim "$limit" '.[:$lim]')

    # Format output
    echo "$all_entries" | jq '.[] | {
        id,
        term,
        short,
        references: (.lifecycle.references // 0),
        last_seen: (.lifecycle.last_seen // "never"),
        significance: (.lifecycle.significance // "one-off"),
        repos: (.lifecycle.repos // []),
        tags
    }'
}

# Statistics
show_stats() {
    if [[ ! -f "$OBSERVATIONS_FILE" ]] || [[ ! -s "$OBSERVATIONS_FILE" ]]; then
        echo "No observations recorded."
        return
    fi

    local total
    total=$(wc -l < "$OBSERVATIONS_FILE")

    local by_type
    by_type=$(jq -s 'group_by(.type) | map({type: .[0].type, count: length}) | sort_by(-.count)' "$OBSERVATIONS_FILE" 2>/dev/null)

    local sessions
    sessions=$(jq -s '[.[].session_id] | unique | length' "$OBSERVATIONS_FILE" 2>/dev/null)

    local oldest
    oldest=$(jq -s 'sort_by(.timestamp) | .[0].timestamp[0:10]' "$OBSERVATIONS_FILE" 2>/dev/null)

    local newest
    newest=$(jq -s 'sort_by(.timestamp) | .[-1].timestamp[0:10]' "$OBSERVATIONS_FILE" 2>/dev/null)

    cat <<EOF
{
  "total_observations": $total,
  "sessions": $sessions,
  "date_range": {"oldest": $oldest, "newest": $newest},
  "by_type": $by_type
}
EOF
}

# Output as markdown table
output_as_table() {
    local json_input="$1"

    echo "| ID | Type | Date | Summary |"
    echo "|-------|------|------|---------|"

    echo "$json_input" | jq -r '
        if type == "array" then .[] else . end |
        "| \(.id // "-") | \(.type // "-") | \(.timestamp // "-") | \(.summary // "-")[0:50] |"
    ' 2>/dev/null || true
}

# =============================================================================
# Main
# =============================================================================

main() {
    local mode="index"
    local output_format="json"
    local limit=10
    local filter_type=""
    local filter_tags=""
    local filter_date=""
    local filter_session=""
    local obs_id=""
    local search_query=""
    local lore_sort_by="id"
    local lore_significance=""
    local lore_repo=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --index)
                mode="index"
                shift
                ;;
            --summary)
                mode="summary"
                shift
                ;;
            --full)
                mode="full"
                obs_id="${2:-}"
                shift 2
                ;;
            --type)
                filter_type="${2:-}"
                shift 2
                ;;
            --tags)
                filter_tags="${2:-}"
                shift 2
                ;;
            --since)
                filter_date="${2:-}"
                shift 2
                ;;
            --session)
                filter_session="${2:-}"
                shift 2
                ;;
            --limit)
                limit="${2:-10}"
                shift 2
                ;;
            --json)
                output_format="json"
                shift
                ;;
            --table)
                output_format="table"
                shift
                ;;
            --stats)
                mode="stats"
                shift
                ;;
            --lore)
                mode="lore"
                shift
                ;;
            --sort-by)
                lore_sort_by="${2:-id}"
                shift 2
                ;;
            --significance)
                lore_significance="${2:-}"
                shift 2
                ;;
            --repo)
                lore_repo="${2:-}"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                echo "Unknown option: $1" >&2
                usage
                exit 1
                ;;
            *)
                search_query="$1"
                mode="search"
                shift
                ;;
        esac
    done

    # Lore mode doesn't need observations file
    if [[ "$mode" == "lore" ]]; then
        local result
        result=$(show_lore "$lore_sort_by" "$lore_significance" "$lore_repo" "$limit")
        case "$output_format" in
            table) output_as_table "$result" ;;
            json|*) echo "$result" ;;
        esac
        return
    fi

    # Check observations file exists
    check_observations_file

    # Execute query based on mode
    local result=""
    case "$mode" in
        index)
            if [[ -n "$filter_type" ]]; then
                result=$(filter_by_type "$filter_type" "$limit")
            elif [[ -n "$filter_tags" ]]; then
                result=$(filter_by_tags "$filter_tags" "$limit")
            elif [[ -n "$filter_date" ]]; then
                result=$(filter_by_date "$filter_date" "$limit")
            elif [[ -n "$filter_session" ]]; then
                result=$(filter_by_session "$filter_session" "$limit")
            else
                result=$(show_index "$limit")
            fi
            ;;
        summary)
            result=$(show_summary "$limit")
            ;;
        full)
            result=$(show_full "$obs_id")
            ;;
        search)
            result=$(search_observations "$search_query" "$limit")
            ;;
        stats)
            result=$(show_stats)
            ;;
    esac

    # Output in requested format
    case "$output_format" in
        table)
            output_as_table "$result"
            ;;
        json|*)
            echo "$result"
            ;;
    esac
}

main "$@"
