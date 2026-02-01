#!/usr/bin/env bash
# .claude/scripts/search-api.sh
#
# Search API Functions - Bash function library for agent skills
# Provides high-level search interface with consistent JSONL output
#
# Usage:
#   source .claude/scripts/search-api.sh
#   results=$(semantic_search "authentication" "src/" 20 0.4)
#   echo "${results}" | jq -r '.file + ":" + (.line | tostring)'

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Check for bc dependency (used in filter_by_score)
if command -v bc >/dev/null 2>&1; then
    export BC_AVAILABLE=true
else
    echo "Warning: bc not found, score filtering will be disabled" >&2
    export BC_AVAILABLE=false
fi

# ============================================================================
# PUBLIC API FUNCTIONS
# ============================================================================

semantic_search() {
    # Find code by meaning using embeddings
    #
    # Args:
    #   $1: query (required) - semantic search query
    #   $2: path (optional) - search path (default: src/)
    #   $3: top_k (optional) - max results (default: 20)
    #   $4: threshold (optional) - similarity threshold (default: 0.4)
    #
    # Returns:
    #   JSONL output: {"file": "path", "line": N, "snippet": "...", "score": 0.89}

    local query="${1}"
    local path="${2:-src/}"
    local top_k="${3:-20}"
    local threshold="${4:-0.4}"

    "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" \
        "semantic" "${query}" "${path}" "${top_k}" "${threshold}"
}

hybrid_search() {
    # Combined semantic + keyword search (Reciprocal Rank Fusion)
    #
    # Args:
    #   $1: query (required) - hybrid search query
    #   $2: path (optional) - search path (default: src/)
    #   $3: top_k (optional) - max results (default: 20)
    #   $4: threshold (optional) - similarity threshold (default: 0.4)
    #
    # Returns:
    #   JSONL output: {"file": "path", "line": N, "snippet": "...", "score": 0.89}

    local query="${1}"
    local path="${2:-src/}"
    local top_k="${3:-20}"
    local threshold="${4:-0.4}"

    "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" \
        "hybrid" "${query}" "${path}" "${top_k}" "${threshold}"
}

regex_search() {
    # Traditional grep-style pattern matching
    #
    # Args:
    #   $1: pattern (required) - regex pattern
    #   $2: path (optional) - search path (default: src/)
    #
    # Returns:
    #   JSONL output or grep-style output (converted to JSONL if grep mode)

    local pattern="${1}"
    local path="${2:-src/}"

    "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" \
        "regex" "${pattern}" "${path}"
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

grep_to_jsonl() {
    # Convert grep output to JSONL format
    #
    # Stdin: grep output (file:line:snippet format)
    # Stdout: JSONL (one result per line)
    #
    # Example:
    #   grep -rn "TODO" src/ | grep_to_jsonl

    while IFS=: read -r file line snippet; do
        # Skip empty lines
        [[ -z "${file}" ]] && continue
        [[ -z "${line}" ]] && line=0

        # Normalize to absolute path
        if [[ ! "${file}" =~ ^/ ]]; then
            file="${PROJECT_ROOT}/${file}"
        fi

        # Output JSONL - use --arg for strings (jq handles escaping internally)
        jq -n \
            --arg file "${file}" \
            --argjson line "${line}" \
            --arg snippet "${snippet}" \
            '{file: $file, line: $line, snippet: $snippet, score: 0.0}'
    done
}

extract_snippet() {
    # Extract code snippet from file with context lines
    #
    # Args:
    #   $1: file (required) - absolute file path
    #   $2: line (required) - target line number
    #   $3: context (optional) - context lines before/after (default: 2)
    #
    # Returns:
    #   Code snippet as string

    local file="${1}"
    local line="${2}"
    local context="${3:-2}"

    if [[ ! -f "${file}" ]]; then
        echo "Error: File not found: ${file}" >&2
        return 1
    fi

    local start=$((line - context))
    [[ ${start} -lt 1 ]] && start=1

    local end=$((line + context))

    sed -n "${start},${end}p" "${file}" 2>/dev/null || echo ""
}

estimate_tokens() {
    # Rough token count estimation (4 chars ≈ 1 token)
    #
    # Args:
    #   $1: text (required) - text to estimate
    #
    # Returns:
    #   Estimated token count (integer)

    local text="${1}"
    local char_count=${#text}
    local token_count=$((char_count / 4))

    echo "${token_count}"
}

parse_jsonl_search_results() {
    # Parse JSONL search results with failure-aware handling
    #
    # Stdin: JSONL search results
    # Stdout: Human-readable format
    #
    # Example:
    #   semantic_search "auth" | parse_jsonl_search_results
    #
    # Failure Handling:
    #   - Drops malformed JSON lines (no crash)
    #   - Logs dropped lines to trajectory
    #   - Calculates data loss ratio

    local count=0
    local line_num=0
    local parse_errors=0
    local dropped_lines=()
    local trajectory_log="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory/${LOA_AGENT_NAME:-unknown}-$(date +%Y-%m-%d).jsonl"

    while IFS= read -r line; do
        ((line_num++))

        # Skip empty lines
        [[ -z "${line}" ]] && continue

        # Try to parse JSON (failure-aware)
        if ! echo "${line}" | jq empty 2>/dev/null; then
            # Malformed JSON - DROP and CONTINUE (no crash)
            ((parse_errors++))
            dropped_lines+=("Line ${line_num}: Parse error")
            # Log to trajectory (if agent context available)
            if [[ -n "${LOA_AGENT_NAME:-}" ]]; then
                echo "{\"ts\":\"$(date -Iseconds)\",\"agent\":\"${LOA_AGENT_NAME}\",\"phase\":\"jsonl_parse_error\",\"line\":${line_num},\"error\":\"Malformed JSON\",\"data\":\"${line:0:50}...\"}" >> "${trajectory_log}" 2>/dev/null || true
            fi
            continue
        fi

        # Parse JSON fields
        file=$(echo "${line}" | jq -r '.file // empty' 2>/dev/null)
        line_num_val=$(echo "${line}" | jq -r '.line // empty' 2>/dev/null)
        snippet=$(echo "${line}" | jq -r '.snippet // empty' 2>/dev/null | head -c 80)
        score=$(echo "${line}" | jq -r '.score // 0.0' 2>/dev/null)

        if [[ -n "${file}" ]] && [[ -n "${line_num_val}" ]]; then
            echo "[$((++count))] ${file}:${line_num_val} (score: ${score})"
            echo "    ${snippet}..."
            echo ""
        fi
    done

    # Log data loss summary if errors occurred
    if [[ ${parse_errors} -gt 0 ]]; then
        local data_loss_ratio=$(echo "scale=4; ${parse_errors} / ${line_num}" | bc 2>/dev/null || echo "0.0")
        echo "Warning: ${parse_errors} malformed JSONL lines dropped (${data_loss_ratio} data loss ratio)" >&2

        # Log to trajectory
        if [[ -n "${LOA_AGENT_NAME:-}" ]] && [[ ${parse_errors} -gt 0 ]]; then
            echo "{\"ts\":\"$(date -Iseconds)\",\"agent\":\"${LOA_AGENT_NAME}\",\"phase\":\"jsonl_parse_summary\",\"parse_errors\":${parse_errors},\"total_lines\":${line_num},\"data_loss_ratio\":${data_loss_ratio}}" >> "${trajectory_log}" 2>/dev/null || true
        fi
    fi
}

count_search_results() {
    # Count JSONL search results
    #
    # Stdin: JSONL search results
    # Stdout: Result count (integer)

    local count=0
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        ((count++))
    done

    echo "${count}"
}

filter_by_score() {
    # Filter JSONL results by minimum score
    #
    # Args:
    #   $1: min_score (required) - minimum score threshold
    #
    # Stdin: JSONL search results
    # Stdout: Filtered JSONL

    local min_score="${1}"

    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue

        if [[ "${BC_AVAILABLE}" == "true" ]]; then
            score=$(echo "${line}" | jq -r '.score // 0.0')

            # Use bc for float comparison
            if (( $(echo "${score} >= ${min_score}" | bc -l) )); then
                echo "${line}"
            fi
        else
            # Fallback: no filtering (return all results)
            echo "${line}"
        fi
    done
}

get_top_results() {
    # Get top N results from JSONL
    #
    # Args:
    #   $1: n (required) - number of results to return
    #
    # Stdin: JSONL search results
    # Stdout: Top N results as JSONL

    local n="${1}"
    head -n "${n}"
}

# Export functions for use in agent skills
export -f semantic_search
export -f hybrid_search
export -f regex_search
export -f grep_to_jsonl
export -f extract_snippet
export -f estimate_tokens
export -f parse_jsonl_search_results
export -f count_search_results
export -f filter_by_score
export -f get_top_results

# Log API initialization
if [[ -n "${LOA_AGENT_NAME:-}" ]]; then
    echo "Search API loaded for agent: ${LOA_AGENT_NAME}" >&2
fi
