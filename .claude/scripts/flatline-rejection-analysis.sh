#!/usr/bin/env bash
# =============================================================================
# flatline-rejection-analysis.sh - Root Cause Analysis for Rejected Proposals
# =============================================================================
# Part of Flatline-Enhanced Compound Learning v1.23.0 (Sprint 3)
# Addresses: T3.4 - Analyze rejected proposals for root cause patterns
#
# Categorizes rejections and tracks pattern frequency to improve future proposals.
#
# Usage:
#   flatline-rejection-analysis.sh --learning <json> --rejection-reason <text> [options]
#
# Exit codes:
#   0 - Success
#   1 - Invalid arguments
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Require bash 4.0+ (associative arrays)
# shellcheck source=bash-version-guard.sh
source "$SCRIPT_DIR/bash-version-guard.sh"

TRAJECTORY_DIR="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"
COMPOUND_DIR="$PROJECT_ROOT/grimoires/loa/a2a/compound"
PATTERNS_FILE="$COMPOUND_DIR/rejection-patterns.json"

# =============================================================================
# Logging
# =============================================================================

log_error() { echo "[ERROR] $(date -Iseconds) $*" >&2; }
log_info() { echo "[INFO] $(date -Iseconds) $*" >&2; }
log_debug() { [[ "${LOA_DEBUG:-false}" == "true" ]] && echo "[DEBUG] $(date -Iseconds) $*" >&2 || true; }

# Log to trajectory
log_trajectory() {
    local event_type="$1"
    local data="$2"

    (umask 077 && mkdir -p "$TRAJECTORY_DIR")
    local date_str
    date_str=$(date +%Y-%m-%d)
    local log_file="$TRAJECTORY_DIR/rejection-analysis-$date_str.jsonl"

    touch "$log_file"
    chmod 600 "$log_file"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg type "rejection_analysis" \
        --arg event "$event_type" \
        --arg timestamp "$timestamp" \
        --argjson data "$data" \
        '{type: $type, event: $event, timestamp: $timestamp, data: $data}' >> "$log_file"
}

# =============================================================================
# Rejection Pattern Categories
# =============================================================================

# Pattern definitions with keywords and suggestions
declare -A PATTERN_KEYWORDS
PATTERN_KEYWORDS["specificity"]="specific|particular|project|codebase|this|local"
PATTERN_KEYWORDS["clarity"]="unclear|vague|ambiguous|confusing|hard to understand"
PATTERN_KEYWORDS["verification"]="unverified|untested|not confirmed|unproven"
PATTERN_KEYWORDS["triviality"]="obvious|trivial|basic|documented|well-known"
PATTERN_KEYWORDS["accuracy"]="incorrect|wrong|inaccurate|misleading|outdated"
PATTERN_KEYWORDS["generalizability"]="not general|too narrow|limited scope|edge case"
PATTERN_KEYWORDS["actionability"]="not actionable|unclear guidance|missing steps"
PATTERN_KEYWORDS["duplicative"]="duplicate|already exists|similar|redundant"

declare -A PATTERN_SUGGESTIONS
PATTERN_SUGGESTIONS["specificity"]="Remove project-specific details. Focus on the general pattern that could apply to any codebase."
PATTERN_SUGGESTIONS["clarity"]="Rewrite the trigger with specific error messages or conditions. Use concrete examples."
PATTERN_SUGGESTIONS["verification"]="Test the solution in multiple contexts. Document verification steps."
PATTERN_SUGGESTIONS["triviality"]="Focus on non-obvious discoveries. Document why this isn't in standard documentation."
PATTERN_SUGGESTIONS["accuracy"]="Verify technical correctness. Check against current best practices and documentation."
PATTERN_SUGGESTIONS["generalizability"]="Abstract the solution to work across frameworks/languages. Remove implementation details."
PATTERN_SUGGESTIONS["actionability"]="Add step-by-step guidance. Include code examples or configuration snippets."
PATTERN_SUGGESTIONS["duplicative"]="Check existing learnings more thoroughly. Consider merging with existing content."

# =============================================================================
# Pattern Analysis
# =============================================================================

# Initialize patterns file
init_patterns_file() {
    mkdir -p "$COMPOUND_DIR"

    if [[ ! -f "$PATTERNS_FILE" ]]; then
        jq -n '{
            version: 1,
            created_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
            patterns: {
                specificity: {count: 0, last_seen: null},
                clarity: {count: 0, last_seen: null},
                verification: {count: 0, last_seen: null},
                triviality: {count: 0, last_seen: null},
                accuracy: {count: 0, last_seen: null},
                generalizability: {count: 0, last_seen: null},
                actionability: {count: 0, last_seen: null},
                duplicative: {count: 0, last_seen: null},
                other: {count: 0, last_seen: null}
            }
        }' > "$PATTERNS_FILE"
    fi
}

# Classify rejection reason into pattern category
classify_rejection() {
    local reason="$1"
    local reason_lower
    reason_lower=$(echo "$reason" | tr '[:upper:]' '[:lower:]')

    local best_match="other"
    local best_score=0

    for pattern in "${!PATTERN_KEYWORDS[@]}"; do
        local keywords="${PATTERN_KEYWORDS[$pattern]}"
        local score=0

        # Count keyword matches
        for keyword in $(echo "$keywords" | tr '|' ' '); do
            if [[ "$reason_lower" == *"$keyword"* ]]; then
                ((score++))
            fi
        done

        if [[ $score -gt $best_score ]]; then
            best_score=$score
            best_match=$pattern
        fi
    done

    echo "$best_match"
}

# Update pattern frequency
update_pattern_frequency() {
    local pattern="$1"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    init_patterns_file

    local temp_file
    temp_file=$(mktemp)

    jq --arg pattern "$pattern" --arg now "$now" '
        .patterns[$pattern].count += 1 |
        .patterns[$pattern].last_seen = $now |
        .updated_at = $now
    ' "$PATTERNS_FILE" > "$temp_file" && mv "$temp_file" "$PATTERNS_FILE"

    log_debug "Updated frequency for pattern: $pattern"
}

# Get suggestion for pattern
get_suggestion() {
    local pattern="$1"

    if [[ -n "${PATTERN_SUGGESTIONS[$pattern]:-}" ]]; then
        echo "${PATTERN_SUGGESTIONS[$pattern]}"
    else
        echo "Review the rejection reason and address the specific feedback."
    fi
}

# =============================================================================
# Main Analysis
# =============================================================================

analyze_rejection() {
    local learning_json="$1"
    local rejection_reason="$2"

    local learning_id
    learning_id=$(echo "$learning_json" | jq -r '.id // "unknown"')

    log_info "Analyzing rejection for: $learning_id"

    # Classify the rejection
    local pattern
    pattern=$(classify_rejection "$rejection_reason")

    log_debug "Classified as: $pattern"

    # Get suggestion
    local suggestion
    suggestion=$(get_suggestion "$pattern")

    # Update frequency tracking
    update_pattern_frequency "$pattern"

    # Get current pattern stats
    init_patterns_file
    local pattern_stats
    pattern_stats=$(jq --arg pattern "$pattern" '.patterns[$pattern]' "$PATTERNS_FILE")

    # Build result
    local result
    result=$(jq -n \
        --arg learning_id "$learning_id" \
        --arg rejection_reason "$rejection_reason" \
        --arg pattern "$pattern" \
        --arg suggestion "$suggestion" \
        --argjson pattern_stats "$pattern_stats" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            learning_id: $learning_id,
            timestamp: $timestamp,
            rejection_reason: $rejection_reason,
            pattern: $pattern,
            suggestion: $suggestion,
            pattern_frequency: $pattern_stats.count,
            pattern_last_seen: $pattern_stats.last_seen
        }')

    # Log to trajectory
    log_trajectory "rejection_analysis_complete" "$result"

    log_info "Analysis complete: $pattern (frequency: $(echo "$pattern_stats" | jq -r '.count'))"

    echo "$result"
}

# List common rejection patterns
list_patterns() {
    init_patterns_file

    echo "## Rejection Pattern Summary"
    echo ""

    jq -r '.patterns | to_entries | sort_by(-.value.count) | .[] | "- **\(.key)**: \(.value.count) occurrences (last: \(.value.last_seen // "never"))"' "$PATTERNS_FILE"

    echo ""
    echo "## Improvement Suggestions"
    echo ""

    for pattern in "${!PATTERN_SUGGESTIONS[@]}"; do
        echo "### $pattern"
        echo "${PATTERN_SUGGESTIONS[$pattern]}"
        echo ""
    done
}

# =============================================================================
# CLI Interface
# =============================================================================

usage() {
    cat <<EOF
Usage: flatline-rejection-analysis.sh [options]

Analyze rejected proposals to identify root cause patterns.

Options:
  --learning <json|file>       Learning JSON or path (required for analyze)
  --rejection-reason <text>    Rejection reason text (required for analyze)
  --list-patterns              List common rejection patterns and suggestions
  --output <format>            Output format: json (default), markdown
  --help                       Show this help

Pattern Categories:
  specificity      - Too project-specific
  clarity          - Trigger condition unclear
  verification     - Solution not verified
  triviality       - Already documented/obvious
  accuracy         - Technically incorrect
  generalizability - Too narrow scope
  actionability    - Missing actionable guidance
  duplicative      - Similar to existing learning
  other            - Uncategorized

Exit Codes:
  0 - Success
  1 - Invalid arguments
EOF
}

main() {
    local learning_input=""
    local rejection_reason=""
    local list_mode=false
    local output_format="json"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --learning)
                learning_input="$2"
                shift 2
                ;;
            --rejection-reason)
                rejection_reason="$2"
                shift 2
                ;;
            --list-patterns)
                list_mode=true
                shift
                ;;
            --output)
                output_format="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Handle list mode
    if [[ "$list_mode" == "true" ]]; then
        list_patterns
        exit 0
    fi

    # Validate required arguments
    if [[ -z "$learning_input" ]]; then
        log_error "--learning is required"
        usage
        exit 1
    fi

    if [[ -z "$rejection_reason" ]]; then
        log_error "--rejection-reason is required"
        usage
        exit 1
    fi

    # Load learning JSON
    local learning_json
    if [[ "$learning_input" == "-" ]]; then
        learning_json=$(cat)
    elif [[ -f "$learning_input" ]]; then
        learning_json=$(cat "$learning_input")
    else
        learning_json="$learning_input"
    fi

    # Validate JSON
    if ! echo "$learning_json" | jq '.' >/dev/null 2>&1; then
        log_error "Invalid JSON input"
        exit 1
    fi

    # Analyze rejection
    analyze_rejection "$learning_json" "$rejection_reason"
}

main "$@"
