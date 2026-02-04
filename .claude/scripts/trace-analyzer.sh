#!/usr/bin/env bash
# trace-analyzer.sh - Shell wrapper for trace_analyzer Python module
# Version: 1.0.0
#
# This wrapper provides:
# - Python availability checking with fallback JSON
# - Strict mode for security (no injection vulnerabilities)
# - Path validation to prevent traversal
# - Proper argument quoting
#
# Usage:
#   trace-analyzer.sh --feedback "User feedback text"
#   trace-analyzer.sh --feedback "Bug report" --session-id abc123
#   trace-analyzer.sh --feedback "Error" --trajectory path/to/trajectory.jsonl

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="${SCRIPT_DIR}/trace_analyzer"

# Version
VERSION="1.0.0"

# Fallback JSON for when Python is unavailable or fails
fallback_json() {
    local error="${1:-Python unavailable}"
    cat << EOF
{
    "category": "unknown",
    "confidence": 0,
    "error": "${error}",
    "timeout": false,
    "timeout_at_stage": null,
    "partial_results": {},
    "version": "${VERSION}",
    "fallback": true
}
EOF
}

# Validate that a path doesn't contain path traversal
validate_path() {
    local path="$1"
    local name="$2"

    # Reject path traversal attempts (pre-canonicalization check)
    if [[ "$path" == *".."* ]]; then
        echo "ERROR: Path traversal detected in $name" >&2
        exit 1
    fi

    # Canonicalize with realpath to resolve symlinks and relative paths
    # Use -m to handle non-existent files (trajectory may not exist yet)
    local canonical_path
    if ! canonical_path=$(realpath -m -- "$path" 2>/dev/null); then
        echo "ERROR: Invalid path in $name" >&2
        exit 1
    fi

    # Post-canonicalization check: ensure no escape via symlink resolution
    if [[ "$canonical_path" == *".."* ]]; then
        echo "ERROR: Path traversal detected after canonicalization in $name" >&2
        exit 1
    fi

    # Get workspace root (parent of .claude directory)
    local workspace_root
    workspace_root=$(realpath -m -- "${SCRIPT_DIR}/../.." 2>/dev/null)

    # Reject absolute paths outside known safe locations
    case "$canonical_path" in
        "${workspace_root}"/*|/home/*|/tmp/*|/var/tmp/*)
            ;;
        *)
            echo "ERROR: Path escapes workspace boundary in $name: $canonical_path" >&2
            exit 1
            ;;
    esac
}

# Check for unexpected flags that might be injection attempts
validate_args() {
    for arg in "$@"; do
        # Skip flag names (--option)
        if [[ "$arg" == "--"* ]]; then
            continue
        fi

        # Reject shell metacharacters that could enable injection
        # Covers: command separators, pipes, backgrounding, subshells,
        # command substitution, redirectors, glob expansion
        if [[ "$arg" == *";"* ]] || \
           [[ "$arg" == *"|"* ]] || \
           [[ "$arg" == *"&"* ]] || \
           [[ "$arg" == *"\`"* ]] || \
           [[ "$arg" == *'$('* ]] || \
           [[ "$arg" == *'${'* ]] || \
           [[ "$arg" == *"<"* ]] || \
           [[ "$arg" == *">"* ]] || \
           [[ "$arg" == *$'\n'* ]] || \
           [[ "$arg" == *$'\r'* ]]; then
            echo "ERROR: Shell metacharacter detected in argument" >&2
            exit 1
        fi
    done
}

# Find Python interpreter
find_python() {
    # Check for virtual environment first
    if [[ -f "${SCRIPT_DIR}/../../.venv/bin/python" ]]; then
        echo "${SCRIPT_DIR}/../../.venv/bin/python"
        return 0
    fi
    if [[ -f "${SCRIPT_DIR}/../../../.venv/bin/python" ]]; then
        echo "${SCRIPT_DIR}/../../../.venv/bin/python"
        return 0
    fi

    # Fall back to system Python
    for py in python3 python; do
        if command -v "$py" &>/dev/null; then
            # Check if pydantic is available
            if "$py" -c "import pydantic" 2>/dev/null; then
                echo "$py"
                return 0
            fi
        fi
    done

    return 1
}

# Main execution
main() {
    # Validate arguments for suspicious patterns
    validate_args "$@"

    # Check for help/version
    for arg in "$@"; do
        case "$arg" in
            -h|--help)
                echo "trace-analyzer.sh v${VERSION}"
                echo ""
                echo "Usage: trace-analyzer.sh --feedback \"text\" [options]"
                echo ""
                echo "Options:"
                echo "  --feedback, -f TEXT      Feedback text to analyze (required)"
                echo "  --trajectory, -t PATH    Trajectory file path"
                echo "  --session-id, -s ID      Session ID filter"
                echo "  --time-window, -w HOURS  Hours of history (default: 24)"
                echo "  --timeout SECONDS        Max processing time (default: 5.0)"
                echo "  --pretty                 Pretty-print JSON output"
                echo "  --dry-run                Validate without analyzing"
                echo ""
                echo "Examples:"
                echo "  trace-analyzer.sh --feedback \"The commit failed\""
                echo "  trace-analyzer.sh -f \"Bug\" -s session123 --pretty"
                exit 0
                ;;
            --version)
                echo "${VERSION}"
                exit 0
                ;;
        esac
    done

    # Validate trajectory path if provided
    local trajectory_path=""
    local args=()
    local i=0
    while [[ $i -lt $# ]]; do
        arg="${@:$((i+1)):1}"
        case "$arg" in
            --trajectory|-t)
                i=$((i + 1))
                trajectory_path="${@:$((i+1)):1}"
                validate_path "$trajectory_path" "trajectory"
                args+=("--trajectory" "$trajectory_path")
                ;;
            *)
                args+=("$arg")
                ;;
        esac
        i=$((i + 1))
    done

    # Find Python
    local python_cmd
    if ! python_cmd=$(find_python); then
        fallback_json "Python with pydantic not available"
        exit 0
    fi

    # Check that package exists
    if [[ ! -d "$PACKAGE_DIR" ]]; then
        fallback_json "trace_analyzer package not found"
        exit 0
    fi

    # Run the analyzer
    # Set PYTHONPATH to include the scripts directory so the module can be found
    # while preserving the current working directory for relative paths
    PYTHONPATH="${SCRIPT_DIR}:${PYTHONPATH:-}" exec "$python_cmd" -m trace_analyzer "${args[@]}"
}

main "$@"
