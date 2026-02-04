#!/usr/bin/env bash
# dcg-matcher.sh - Pattern matching for DCG
#
# Matches parsed commands against loaded security pack patterns.
# Handles safe context detection and safe path checking.
#
# Usage:
#   source dcg-matcher.sh
#   match=$(dcg_match '{"segments":["rm -rf /"]}' "implement")
#   echo "$match" | jq '.action'

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source bootstrap for PROJECT_ROOT
if [[ -f "$SCRIPT_DIR/bootstrap.sh" ]]; then
    source "$SCRIPT_DIR/bootstrap.sh"
fi

# =============================================================================
# Configuration
# =============================================================================

_DCG_MATCHER_VERSION="1.0.0"

# =============================================================================
# Main Match Function
# =============================================================================

dcg_match() {
    local parsed="$1"
    local context="$2"

    # Extract segments from parsed output
    local segments
    segments=$(echo "$parsed" | jq -r '.segments[]' 2>/dev/null) || return

    local matches=()

    # Check each segment against loaded patterns
    while IFS= read -r segment; do
        [[ -z "$segment" ]] && continue

        # Check safe patterns first (data references)
        if _dcg_matcher_is_safe_context "$segment"; then
            continue
        fi

        # Match against all loaded patterns
        local match
        match=$(_dcg_match_patterns "$segment" "$context")
        if [[ -n "$match" && "$match" != "null" ]]; then
            matches+=("$match")
        fi
    done <<< "$segments"

    # Also check heredocs if present
    local heredocs
    heredocs=$(echo "$parsed" | jq -r '.heredocs[]?' 2>/dev/null) || true

    while IFS= read -r heredoc; do
        [[ -z "$heredoc" ]] && continue

        local match
        match=$(_dcg_match_patterns "$heredoc" "$context")
        if [[ -n "$match" && "$match" != "null" ]]; then
            matches+=("$match")
        fi
    done <<< "$heredocs"

    # Return highest severity match
    if [[ ${#matches[@]} -gt 0 ]]; then
        _dcg_highest_severity "${matches[@]}"
    fi
}

# =============================================================================
# Safe Context Detection
# =============================================================================

_dcg_matcher_is_safe_context() {
    local segment="$1"

    # Commands that reference dangerous patterns but don't execute them
    # grep "rm -rf" - searching for pattern
    # echo "DROP TABLE" - printing text
    # cat file.sql - reading file (content checked separately)

    [[ "$segment" =~ ^grep[[:space:]] ]] && return 0
    [[ "$segment" =~ ^egrep[[:space:]] ]] && return 0
    [[ "$segment" =~ ^fgrep[[:space:]] ]] && return 0
    [[ "$segment" =~ ^rg[[:space:]] ]] && return 0
    [[ "$segment" =~ ^echo[[:space:]] ]] && return 0
    [[ "$segment" =~ ^printf[[:space:]] ]] && return 0
    [[ "$segment" =~ ^cat[[:space:]] ]] && return 0
    [[ "$segment" =~ ^head[[:space:]] ]] && return 0
    [[ "$segment" =~ ^tail[[:space:]] ]] && return 0
    [[ "$segment" =~ ^less[[:space:]] ]] && return 0
    [[ "$segment" =~ ^more[[:space:]] ]] && return 0

    # Flags that indicate safe/preview mode
    [[ "$segment" =~ --help ]] && return 0
    [[ "$segment" =~ --dry-run ]] && return 0
    [[ "$segment" =~ --version ]] && return 0
    [[ "$segment" =~ -n[[:space:]] ]] && [[ "$segment" =~ ^git ]] && return 0  # git -n (dry-run)
    [[ "$segment" =~ --what-if ]] && return 0  # terraform what-if

    return 1
}

# =============================================================================
# Pattern Matching
# =============================================================================

_dcg_match_patterns() {
    local segment="$1"
    local context="$2"

    # Get patterns to check (from dcg-packs-loader.sh or core patterns)
    local patterns=()

    if [[ -n "${_DCG_PATTERNS:-}" ]] && [[ ${#_DCG_PATTERNS[@]} -gt 0 ]]; then
        patterns=("${_DCG_PATTERNS[@]}")
    elif [[ -n "${_DCG_CORE_PATTERNS:-}" ]] && [[ ${#_DCG_CORE_PATTERNS[@]} -gt 0 ]]; then
        patterns=("${_DCG_CORE_PATTERNS[@]}")
    else
        # No patterns loaded
        return
    fi

    # Match against patterns
    for pattern_json in "${patterns[@]}"; do
        local id pattern action severity
        id=$(echo "$pattern_json" | jq -r '.id // "unknown"' 2>/dev/null) || continue
        pattern=$(echo "$pattern_json" | jq -r '.pattern // ""' 2>/dev/null) || continue

        [[ -z "$pattern" ]] && continue

        # Check if pattern matches
        if echo "$segment" | grep -qE "$pattern" 2>/dev/null; then
            # Check safe paths for filesystem patterns
            if [[ "$id" =~ ^fs_ ]] && _dcg_matcher_in_safe_path "$segment"; then
                continue
            fi

            # Check context-specific exceptions
            if _dcg_has_context_exception "$id" "$context"; then
                continue
            fi

            echo "$pattern_json"
            return 0
        fi
    done
}

# =============================================================================
# Safe Path Checking
# =============================================================================

_dcg_matcher_in_safe_path() {
    local segment="$1"

    # Extract path from command
    # Handles: rm -rf /path, rm -r -f /path, rm /path
    local path
    path=$(echo "$segment" | grep -oP '(?:rm\s+(?:-[rf]+\s+)*)\K[^\s]+' | head -1) || return 1
    [[ -z "$path" ]] && return 1

    # Expand environment variables
    local expanded
    expanded=$(eval echo "$path" 2>/dev/null) || expanded="$path"

    # Skip relative paths (can't verify safety)
    if [[ ! "$expanded" =~ ^/ ]] && [[ ! "$expanded" =~ ^~ ]]; then
        # Relative path within project - check against PROJECT_ROOT
        expanded="${PROJECT_ROOT:-.}/$expanded"
    fi

    # Expand ~ to home
    expanded="${expanded/#\~/$HOME}"

    # Canonicalize path
    local canonical
    canonical=$(realpath -m "$expanded" 2>/dev/null) || return 1

    # Check against safe paths
    if [[ -n "${_DCG_SAFE_PATHS:-}" ]]; then
        for safe_path in "${_DCG_SAFE_PATHS[@]}"; do
            if [[ "$canonical" == "$safe_path"* ]]; then
                return 0
            fi
        done
    fi

    return 1
}

# =============================================================================
# Context Exceptions
# =============================================================================

_dcg_has_context_exception() {
    local pattern_id="$1"
    local context="$2"

    # Context-specific exceptions
    # e.g., git reset --hard might be OK in certain maintenance contexts

    # Currently no context exceptions defined
    # Future: Load from config or pack

    return 1
}

# =============================================================================
# Severity Comparison
# =============================================================================

_dcg_highest_severity() {
    local matches=("$@")
    local highest=""
    local highest_score=0

    # Severity scores
    local -A severity_scores=(
        ["critical"]=100
        ["high"]=75
        ["medium"]=50
        ["low"]=25
    )

    for match in "${matches[@]}"; do
        local severity
        severity=$(echo "$match" | jq -r '.severity // "medium"' 2>/dev/null)
        local score=${severity_scores[$severity]:-50}

        if [[ $score -gt $highest_score ]]; then
            highest_score=$score
            highest="$match"
        fi
    done

    echo "$highest"
}

# =============================================================================
# Utility
# =============================================================================

dcg_matcher_version() {
    echo "$_DCG_MATCHER_VERSION"
}
