#!/usr/bin/env bash
# .claude/hooks/memory-utils/search.sh
#
# Memory Search Utility for Loa Memory Stack
# Queries vector database and optionally QMD for similar memories
#
# Usage:
#   search.sh <query> [--top-k N] [--threshold T] [--include-qmd]
#
# Output:
#   JSON array of memory objects with scores

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
MEMORY_ADMIN="${PROJECT_ROOT}/.claude/scripts/memory-admin.sh"
QMD_SYNC="${PROJECT_ROOT}/.claude/scripts/qmd-sync.sh"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"

# Defaults
TOP_K=3
THRESHOLD=0.35
INCLUDE_QMD=false

# Parse arguments
QUERY=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --top-k|-k)
            TOP_K="$2"
            shift 2
            ;;
        --threshold|-t)
            THRESHOLD="$2"
            shift 2
            ;;
        --include-qmd)
            INCLUDE_QMD=true
            shift
            ;;
        *)
            if [[ -z "$QUERY" ]]; then
                QUERY="$1"
            else
                QUERY="$QUERY $1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$QUERY" ]]; then
    echo "[]"
    exit 0
fi

# Check if QMD should be auto-included from config
check_qmd_enabled() {
    if [[ -f "$CONFIG_FILE" ]]; then
        local enabled
        enabled=$(yq eval '.memory.qmd.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
        if [[ "$enabled" == "true" ]]; then
            INCLUDE_QMD=true
        fi
    fi
}

# Search vector database
search_vector_db() {
    if [[ -f "$MEMORY_ADMIN" ]]; then
        "$MEMORY_ADMIN" search "$QUERY" --top-k "$TOP_K" --threshold "$THRESHOLD" 2>/dev/null || echo "[]"
    else
        echo "[]"
    fi
}

# Search QMD collections
search_qmd() {
    if [[ -f "$QMD_SYNC" ]]; then
        "$QMD_SYNC" query "$QUERY" 2>/dev/null || echo "[]"
    else
        echo "[]"
    fi
}

# Merge results from vector DB and QMD
merge_results() {
    local vector_results="$1"
    local qmd_results="$2"

    # Transform QMD results to match memory format
    local transformed_qmd
    transformed_qmd=$(echo "$qmd_results" | jq '[.[] | {
        memory_type: "document",
        content: (.snippet // .file),
        score: .score,
        source: .file
    }]' 2>/dev/null || echo "[]")

    # Merge and sort by score, take top-k
    echo "$vector_results" "$transformed_qmd" | jq -s '
        add |
        sort_by(-.score) |
        .[0:'"$TOP_K"']
    ' 2>/dev/null || echo "$vector_results"
}

# Main search logic
main() {
    # Check if QMD should be enabled from config
    check_qmd_enabled

    # Search vector database
    local vector_results
    vector_results=$(search_vector_db)

    if [[ "$INCLUDE_QMD" == "true" ]]; then
        # Search QMD and merge results
        local qmd_results
        qmd_results=$(search_qmd)

        merge_results "$vector_results" "$qmd_results"
    else
        echo "$vector_results"
    fi
}

main
