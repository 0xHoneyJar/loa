#!/usr/bin/env bash
# detect-codebase.sh - Fast brownfield detection for /plan-and-analyze
#
# Detects whether a codebase is GREENFIELD (no meaningful code) or BROWNFIELD
# (has existing code that should be analyzed by /ride before PRD creation).
#
# Output: JSON to stdout with detection results
# Exit: Always 0 (errors reported in JSON)
#
# Usage:
#   ./detect-codebase.sh
#   ./detect-codebase.sh --json  # explicit JSON output (default)

set -uo pipefail
# Note: Not using -e because grep returns 1 on no match which is normal

# =============================================================================
# Configuration
# =============================================================================

# Source extensions to detect (common programming languages)
SOURCE_EXTENSIONS="ts|tsx|js|jsx|py|go|rs|java|rb|php|cs|cpp|c|h|swift|kt|scala|vue|svelte"

# Directories to exclude from counting
EXCLUDES="node_modules|vendor|\.git|dist|build|__pycache__|target|\.next|\.nuxt|\.venv|venv|\.tox|\.eggs|\.mypy_cache|\.pytest_cache|coverage|\.nyc_output"

# Paths to check for source files (in order of likelihood)
SOURCE_PATHS="src lib app packages cmd pkg internal api server client core components services utils helpers models controllers views routes handlers"

# Thresholds for BROWNFIELD detection
MIN_FILES=10
MIN_LINES=500

# =============================================================================
# Functions
# =============================================================================

count_source_files() {
    local path="$1"
    local count=0

    if [[ -d "$path" ]]; then
        # Use find with regex for extensions, excluding common non-source dirs
        # Note: grep -E may return 1 (no match), which is normal - we handle empty output
        count=$(find "$path" -type f 2>/dev/null | \
            grep -E "\.($SOURCE_EXTENSIONS)$" 2>/dev/null | \
            grep -Ev "/($EXCLUDES)/" 2>/dev/null | \
            wc -l | \
            tr -d ' ') || count=0
    fi

    echo "${count:-0}"
}

count_lines() {
    local path="$1"
    local lines=0

    if [[ -d "$path" ]]; then
        # Find all source files and count lines
        local files
        files=$(find "$path" -type f 2>/dev/null | \
            grep -E "\.($SOURCE_EXTENSIONS)$" 2>/dev/null | \
            grep -Ev "/($EXCLUDES)/" 2>/dev/null) || files=""

        if [[ -n "$files" ]]; then
            lines=$(echo "$files" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
        fi
    fi

    echo "${lines:-0}"
}

detect_language() {
    local path="$1"

    # Count files by extension and return most common
    local files
    files=$(find "$path" -type f 2>/dev/null | \
        grep -E "\.($SOURCE_EXTENSIONS)$" 2>/dev/null | \
        grep -Ev "/($EXCLUDES)/" 2>/dev/null) || files=""

    if [[ -n "$files" ]]; then
        echo "$files" | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}'
    else
        echo ""
    fi
}

check_reality() {
    local reality_exists="false"
    local reality_age_days=999

    # Check for reality directory and key files
    local reality_file="grimoires/loa/reality/extracted-prd.md"

    if [[ -f "$reality_file" ]]; then
        reality_exists="true"

        # Calculate age in days (cross-platform)
        local file_mtime
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            file_mtime=$(stat -f %m "$reality_file" 2>/dev/null)
        else
            # Linux
            file_mtime=$(stat -c %Y "$reality_file" 2>/dev/null)
        fi

        if [[ -n "$file_mtime" ]]; then
            local now
            now=$(date +%s)
            local age_seconds=$((now - file_mtime))
            reality_age_days=$((age_seconds / 86400))
        fi
    fi

    echo "$reality_exists $reality_age_days"
}

# =============================================================================
# Main
# =============================================================================

main() {
    local total_files=0
    local total_lines=0
    local primary_lang=""
    local paths_found=()
    local error_msg=""
    local path

    # Check each source path
    for path in $SOURCE_PATHS; do
        if [[ -d "$path" ]]; then
            local count
            count=$(count_source_files "$path")

            if [[ "$count" -gt 0 ]]; then
                paths_found+=("$path/")
                total_files=$((total_files + count))
            fi
        fi
    done

    # Also check root directory for source files (but not recursively into paths we already checked)
    local root_count
    root_count=$(find . -maxdepth 1 -type f 2>/dev/null | \
        grep -E "\.($SOURCE_EXTENSIONS)$" 2>/dev/null | \
        wc -l | tr -d ' ') || root_count=0
    root_count="${root_count:-0}"

    if [[ "$root_count" -gt 0 ]]; then
        total_files=$((total_files + root_count))
        paths_found+=("./")
    fi

    # Count total lines if we found files
    if [[ $total_files -gt 0 ]]; then
        # Count lines from all found paths
        for path in "${paths_found[@]}"; do
            local lines
            lines=$(count_lines "$path")
            total_lines=$((total_lines + lines))
        done

        # Detect primary language from first found path
        for path in "${paths_found[@]}"; do
            primary_lang=$(detect_language "$path")
            if [[ -n "$primary_lang" ]]; then
                break
            fi
        done
    fi

    # Check reality directory
    local reality_info
    reality_info=$(check_reality)
    local reality_exists
    local reality_age_days
    reality_exists=$(echo "$reality_info" | cut -d' ' -f1)
    reality_age_days=$(echo "$reality_info" | cut -d' ' -f2)

    # Determine type
    local type="GREENFIELD"
    if [[ $total_files -ge $MIN_FILES ]] || [[ $total_lines -ge $MIN_LINES ]]; then
        type="BROWNFIELD"
    fi

    # Map extension to language name
    case "$primary_lang" in
        ts|tsx) primary_lang="typescript" ;;
        js|jsx) primary_lang="javascript" ;;
        py) primary_lang="python" ;;
        go) primary_lang="go" ;;
        rs) primary_lang="rust" ;;
        java) primary_lang="java" ;;
        rb) primary_lang="ruby" ;;
        php) primary_lang="php" ;;
        cs) primary_lang="csharp" ;;
        cpp|c|h) primary_lang="cpp" ;;
        swift) primary_lang="swift" ;;
        kt) primary_lang="kotlin" ;;
        scala) primary_lang="scala" ;;
        vue) primary_lang="vue" ;;
        svelte) primary_lang="svelte" ;;
        *) primary_lang="${primary_lang:-unknown}" ;;
    esac

    # Build paths_found JSON array
    local paths_json="[]"
    if [[ ${#paths_found[@]} -gt 0 ]]; then
        paths_json=$(printf '%s\n' "${paths_found[@]}" | jq -R . | jq -s .)
    fi

    # Output JSON
    cat <<EOF
{
  "type": "$type",
  "files": $total_files,
  "lines": $total_lines,
  "language": "$primary_lang",
  "paths_found": $paths_json,
  "reality_exists": $reality_exists,
  "reality_age_days": $reality_age_days,
  "error": null
}
EOF
}

# Run main
main "$@"
