#!/usr/bin/env bash
# Context size assessment for parallel execution decisions
# Used by agents to determine if work should be split

set -euo pipefail

# Get total line count for context files
get_context_size() {
    local total=0

    # Core planning documents
    for file in grimoires/loa/prd.md grimoires/loa/sdd.md grimoires/loa/sprint.md; do
        if [ -f "$file" ]; then
            total=$((total + $(wc -l < "$file")))
        fi
    done

    # A2A communication files
    for file in grimoires/loa/a2a/*.md; do
        if [ -f "$file" ]; then
            total=$((total + $(wc -l < "$file")))
        fi
    done

    echo "$total"
}

# Get context size for a specific sprint
get_sprint_context_size() {
    local sprint_id="$1"
    local total=0
    local sprint_dir="grimoires/loa/a2a/${sprint_id}"

    if [ -d "$sprint_dir" ]; then
        for file in "$sprint_dir"/*.md; do
            if [ -f "$file" ]; then
                total=$((total + $(wc -l < "$file")))
            fi
        done
    fi

    echo "$total"
}

# Determine context category based on thresholds
# Args: $1=total_lines, $2=small_threshold, $3=large_threshold
categorize_context() {
    local total="$1"
    local small="${2:-3000}"
    local large="${3:-6000}"

    if [ "$total" -lt "$small" ]; then
        echo "SMALL"
    elif [ "$total" -lt "$large" ]; then
        echo "MEDIUM"
    else
        echo "LARGE"
    fi
}

# Agent-specific thresholds
# Returns: small_threshold large_threshold
get_agent_thresholds() {
    local agent="$1"

    case "$agent" in
        "reviewing-code")
            echo "3000 6000"
            ;;
        "auditing-security")
            echo "2000 5000"
            ;;
        "implementing-tasks")
            echo "3000 8000"
            ;;
        "deploying-infrastructure")
            echo "2000 5000"
            ;;
        *)
            echo "3000 6000"
            ;;
    esac
}

# Full context assessment for an agent
assess_context() {
    local agent="$1"
    local thresholds=$(get_agent_thresholds "$agent")
    local small=$(echo "$thresholds" | cut -d' ' -f1)
    local large=$(echo "$thresholds" | cut -d' ' -f2)
    local total=$(get_context_size)
    local category=$(categorize_context "$total" "$small" "$large")

    echo "total=$total category=$category"
}

# Quick check if parallel execution is needed
needs_parallel() {
    local agent="$1"
    local thresholds=$(get_agent_thresholds "$agent")
    local large=$(echo "$thresholds" | cut -d' ' -f2)
    local total=$(get_context_size)

    [ "$total" -ge "$large" ]
}
