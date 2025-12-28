#!/bin/bash
# detect-mode.sh - Determine Loa installation mode
#
# Outputs: "integrated" or "standalone"
#
# Detection Logic:
# 1. Check HIVEMIND_PATH environment variable points to valid installation
# 2. Check if we're inside the HivemindOS repo itself
# 3. Default to standalone mode

set -euo pipefail

# =============================================================================
# Mode Detection
# =============================================================================

detect_mode() {
    # Check for HIVEMIND_PATH environment variable
    if [[ -n "${HIVEMIND_PATH:-}" ]]; then
        # Validate it points to a valid HivemindOS installation
        if [[ -d "$HIVEMIND_PATH/library" ]] && \
           [[ -d "$HIVEMIND_PATH/laboratory" ]] && \
           [[ -f "$HIVEMIND_PATH/.claude/statusline.sh" ]]; then
            echo "integrated"
            return 0
        fi
    fi

    # Check if we're inside the HivemindOS repo itself
    local project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
    if [[ -d "$project_dir/library" ]] && \
       [[ -d "$project_dir/laboratory" ]] && \
       [[ -f "$project_dir/OS_PLAYBOOK.md" ]]; then
        echo "integrated"
        return 0
    fi

    # Default: standalone mode
    echo "standalone"
    return 0
}

# =============================================================================
# Detailed Detection (for debugging)
# =============================================================================

detect_mode_verbose() {
    local project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"

    echo "=== Mode Detection ===" >&2
    echo "HIVEMIND_PATH: ${HIVEMIND_PATH:-<not set>}" >&2
    echo "CLAUDE_PROJECT_DIR: $project_dir" >&2

    # Check HIVEMIND_PATH
    if [[ -n "${HIVEMIND_PATH:-}" ]]; then
        echo "Checking HIVEMIND_PATH..." >&2
        if [[ -d "$HIVEMIND_PATH/library" ]]; then
            echo "  ✓ library/ exists" >&2
        else
            echo "  ✗ library/ missing" >&2
        fi
        if [[ -d "$HIVEMIND_PATH/laboratory" ]]; then
            echo "  ✓ laboratory/ exists" >&2
        else
            echo "  ✗ laboratory/ missing" >&2
        fi
        if [[ -f "$HIVEMIND_PATH/.claude/statusline.sh" ]]; then
            echo "  ✓ .claude/statusline.sh exists" >&2
        else
            echo "  ✗ .claude/statusline.sh missing" >&2
        fi
    fi

    # Check current directory
    echo "Checking project directory..." >&2
    if [[ -d "$project_dir/library" ]]; then
        echo "  ✓ library/ exists" >&2
    else
        echo "  ✗ library/ missing" >&2
    fi
    if [[ -d "$project_dir/laboratory" ]]; then
        echo "  ✓ laboratory/ exists" >&2
    else
        echo "  ✗ laboratory/ missing" >&2
    fi

    # Final determination
    detect_mode
}

# =============================================================================
# Main
# =============================================================================

# Check for verbose flag
if [[ "${1:-}" == "-v" ]] || [[ "${1:-}" == "--verbose" ]]; then
    detect_mode_verbose
else
    detect_mode
fi
