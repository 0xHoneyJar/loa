#!/usr/bin/env bash
# =============================================================================
# flatline-exit-classifier.sh — distinguish flatline-orchestrator exit regimes
# =============================================================================
# Issue #663. Previously, post-pr-orchestrator collapsed any non-zero exit
# from flatline-orchestrator into "blocker found", halting autonomous mode
# with halt_reason=flatline_blocker. That misattribution masked validation/
# configuration errors (e.g., "Invalid phase: pr") as if they were real
# Flatline-detected blockers.
#
# This helper inspects captured stderr and exit code, returning one of:
#   ok                          — exit 0, no error
#   timeout                     — exit 124 (run_with_timeout convention)
#   flatline_orchestrator_error — exit non-zero with stderr matching arg/config validation patterns
#   flatline_blocker            — exit 1 without validation patterns (preserves legacy semantics)
#   flatline_error              — any other non-zero exit (model failures, knowledge errors, etc.)
#
# Usage:
#   source flatline-exit-classifier.sh
#   classify_flatline_exit <exit_code> <stderr_file>
# =============================================================================

# Patterns that indicate a CLI/config validation error in flatline-orchestrator,
# NOT a real blocker finding. Intentionally narrow to avoid false-classifying
# real errors as orchestrator errors.
_FLATLINE_VALIDATION_PATTERNS=(
    "Invalid phase:"
    "Invalid mode:"
    "Invalid execution mode:"
    "Unknown option:"
    "Phase required"
    "Mode required"
    "Document must be within"
    "Document not found:"
    "Configuration error"
)

classify_flatline_exit() {
    local exit_code="${1:-0}"
    local stderr_file="${2:-/dev/null}"

    if [[ "$exit_code" -eq 0 ]]; then
        echo "ok"
        return 0
    fi

    if [[ "$exit_code" -eq 124 ]]; then
        echo "timeout"
        return 0
    fi

    # Non-zero exit. Inspect stderr for validation-error signatures.
    if [[ -f "$stderr_file" && -s "$stderr_file" ]]; then
        local pattern
        for pattern in "${_FLATLINE_VALIDATION_PATTERNS[@]}"; do
            if grep -qF "$pattern" "$stderr_file"; then
                echo "flatline_orchestrator_error"
                return 0
            fi
        done
    fi

    # Exit 1 without validation pattern → preserve legacy "blocker" semantics
    if [[ "$exit_code" -eq 1 ]]; then
        echo "flatline_blocker"
        return 0
    fi

    # Any other non-zero exit → orchestrator-level error (model failures, etc.)
    echo "flatline_error"
    return 0
}

# Allow direct invocation for shell-script integration (e.g., from awk/jq)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    classify_flatline_exit "$@"
fi
