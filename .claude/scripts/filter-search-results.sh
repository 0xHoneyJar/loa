#!/usr/bin/env bash
# filter-search-results.sh
# Purpose: Build exclude arguments for ck/grep based on context filtering configuration
# Sprint: 4 (Context Filtering - FR-9.2, GitHub Issue #10)
# Usage: Source this file, then call build_ck_excludes() or build_grep_excludes()
#
# Functions:
#   - is_filtering_enabled: Check if filtering is enabled
#   - build_ck_excludes: Build --exclude arguments for ck
#   - build_grep_excludes: Build --exclude arguments for grep
#   - check_signal_marker: Check frontmatter signal in file
#   - filter_by_signal: Post-process results by signal threshold

set -euo pipefail

# Establish project root
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
LOA_CONFIG="${PROJECT_ROOT}/.loa.config.yaml"

# Check if yq is available
if ! command -v yq >/dev/null 2>&1; then
    # yq not available - filtering disabled
    LOA_FILTERING_ENABLED=false
else
    LOA_FILTERING_ENABLED=true
fi

# Function: Check if filtering is enabled
is_filtering_enabled() {
    if [[ "${LOA_FILTERING_ENABLED}" == false ]]; then
        return 1
    fi

    if [[ ! -f "${LOA_CONFIG}" ]]; then
        return 1
    fi

    local enabled=$(yq eval '.context_filtering.enable_filtering' "${LOA_CONFIG}" 2>/dev/null || echo "false")
    [[ "${enabled}" == "true" ]]
}

# Function: Build ck --exclude arguments
build_ck_excludes() {
    if ! is_filtering_enabled; then
        return 0
    fi

    local -a excludes=()

    # Add archive zone
    local archive_zone=$(yq eval '.context_filtering.archive_zone' "${LOA_CONFIG}" 2>/dev/null || echo "")
    if [[ -n "${archive_zone}" ]] && [[ "${archive_zone}" != "null" ]]; then
        excludes+=("--exclude" "${archive_zone}")
    fi

    # Add default exclude patterns
    local default_excludes=$(yq eval '.context_filtering.default_excludes[]' "${LOA_CONFIG}" 2>/dev/null || echo "")
    if [[ -n "${default_excludes}" ]]; then
        while IFS= read -r pattern; do
            if [[ -n "${pattern}" ]] && [[ "${pattern}" != "null" ]]; then
                excludes+=("--exclude" "${pattern}")
            fi
        done <<< "${default_excludes}"
    fi

    # Output exclude arguments (one per line for array consumption)
    for arg in "${excludes[@]}"; do
        echo "${arg}"
    done
}

# Function: Build grep --exclude arguments
build_grep_excludes() {
    if ! is_filtering_enabled; then
        return 0
    fi

    local -a excludes=()

    # Add archive zone as --exclude-dir
    local archive_zone=$(yq eval '.context_filtering.archive_zone' "${LOA_CONFIG}" 2>/dev/null || echo "")
    if [[ -n "${archive_zone}" ]] && [[ "${archive_zone}" != "null" ]]; then
        # Extract directory name from path
        local dir_name=$(basename "${archive_zone}")
        excludes+=("--exclude-dir=${dir_name}")
    fi

    # Add default exclude patterns
    local default_excludes=$(yq eval '.context_filtering.default_excludes[]' "${LOA_CONFIG}" 2>/dev/null || echo "")
    if [[ -n "${default_excludes}" ]]; then
        while IFS= read -r pattern; do
            if [[ -n "${pattern}" ]] && [[ "${pattern}" != "null" ]]; then
                # Convert glob pattern to grep --exclude format
                # e.g., "**/brainstorm-*.md" -> "brainstorm-*.md"
                pattern=$(echo "${pattern}" | sed 's|^\*\*/||')
                excludes+=("--exclude=${pattern}")
            fi
        done <<< "${default_excludes}"
    fi

    # Add exclude-dir for common build/temp directories
    local exclude_patterns=$(yq eval '.drift_detection.exclude_patterns[]' "${LOA_CONFIG}" 2>/dev/null || echo "")
    if [[ -n "${exclude_patterns}" ]]; then
        while IFS= read -r pattern; do
            if [[ -n "${pattern}" ]] && [[ "${pattern}" != "null" ]]; then
                # Extract directory names from patterns like "**/node_modules/**"
                if [[ "${pattern}" == *"/**"* ]]; then
                    local dir_name=$(echo "${pattern}" | sed 's|^\*\*/||' | sed 's|/\*\*$||')
                    excludes+=("--exclude-dir=${dir_name}")
                fi
            fi
        done <<< "${exclude_patterns}"
    fi

    # Output exclude arguments (one per line for array consumption)
    for arg in "${excludes[@]}"; do
        echo "${arg}"
    done
}

# Function: Check signal marker in file frontmatter
# Returns: high|medium|low|none
check_signal_marker() {
    local file_path="$1"

    if [[ ! -f "${file_path}" ]]; then
        echo "none"
        return 0
    fi

    # Check if file has YAML frontmatter
    if ! head -1 "${file_path}" | grep -q "^---$"; then
        echo "none"
        return 0
    fi

    # Extract frontmatter (between first two ---)
    local frontmatter=$(awk '/^---$/{i++}i==1' "${file_path}" | head -n -1)

    # Look for signal: field
    local signal=$(echo "${frontmatter}" | grep "^signal:" | awk '{print $2}' | tr -d ' ')

    if [[ -z "${signal}" ]]; then
        echo "none"
    else
        echo "${signal}"
    fi
}

# Function: Filter results by signal threshold
# Input: Line-by-line search results (path:line format)
# Output: Filtered results
filter_by_signal() {
    if ! is_filtering_enabled; then
        cat  # Pass through
        return 0
    fi

    local respect_frontmatter=$(yq eval '.context_filtering.respect_frontmatter_signals' "${LOA_CONFIG}" 2>/dev/null || echo "false")
    if [[ "${respect_frontmatter}" != "true" ]]; then
        cat  # Pass through
        return 0
    fi

    local signal_threshold=$(yq eval '.context_filtering.signal_threshold' "${LOA_CONFIG}" 2>/dev/null || echo "medium")

    # Read results line by line
    while IFS= read -r line; do
        # Extract file path (before first colon)
        local file_path=$(echo "${line}" | cut -d':' -f1)

        # Check signal marker
        local signal=$(check_signal_marker "${file_path}")

        # Apply threshold filter
        case "${signal_threshold}" in
            high)
                # Only include high-signal files
                if [[ "${signal}" == "high" ]] || [[ "${signal}" == "none" ]]; then
                    echo "${line}"
                fi
                ;;
            medium)
                # Include medium and high
                if [[ "${signal}" == "high" ]] || [[ "${signal}" == "medium" ]] || [[ "${signal}" == "none" ]]; then
                    echo "${line}"
                fi
                ;;
            low)
                # Include all (no filtering)
                echo "${line}"
                ;;
        esac
    done
}

# Function: Get filtered search command for ck
# Returns: Full ck command with excludes
get_ck_search_command() {
    local search_type="$1"  # semantic|hybrid|regex
    local query="$2"
    local path="$3"
    local top_k="${4:-10}"
    local threshold="${5:-0.5}"

    local -a excludes=()
    if is_filtering_enabled; then
        readarray -t excludes < <(build_ck_excludes)
    fi

    # Build command - ck v0.7.0+ syntax:
    # ck --sem|--hybrid|--regex "query" --limit N --threshold T --jsonl [excludes] "path"
    # Note: --sem (not --semantic), --limit (not --top-k), path is positional (not --path)
    local cmd="ck"

    # Search type flag (ck uses --sem not --semantic)
    if [[ "${search_type}" == "semantic" ]]; then
        cmd="${cmd} --sem"
    else
        cmd="${cmd} --${search_type}"
    fi

    # Query
    cmd="${cmd} \"${query}\""

    # Options (before path)
    cmd="${cmd} --limit ${top_k} --jsonl"

    # Add threshold for semantic/hybrid (not regex)
    if [[ "${search_type}" != "regex" ]]; then
        cmd="${cmd} --threshold ${threshold}"
    fi

    # Add excludes
    for arg in "${excludes[@]}"; do
        cmd="${cmd} ${arg}"
    done

    # Path is final positional argument
    cmd="${cmd} \"${path}\""

    echo "${cmd}"
}

# Function: Get filtered search command for grep
# Returns: Full grep command with excludes
get_grep_search_command() {
    local pattern="$1"
    local path="$2"
    local include_pattern="${3:-*.{ts,js,py,md}}"

    local -a excludes=()
    if is_filtering_enabled; then
        readarray -t excludes < <(build_grep_excludes)
    fi

    # Build command
    local cmd="grep -rn -E \"${pattern}\" ${excludes[@]} --include=\"${include_pattern}\" \"${path}\""

    echo "${cmd}"
}

# Export functions for sourcing
export -f is_filtering_enabled
export -f build_ck_excludes
export -f build_grep_excludes
export -f check_signal_marker
export -f filter_by_signal
export -f get_ck_search_command
export -f get_grep_search_command
