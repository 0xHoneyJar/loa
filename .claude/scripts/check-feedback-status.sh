#!/usr/bin/env bash
# Check feedback status for a sprint
# Usage: ./check-feedback-status.sh sprint-N
# Returns: AUDIT_REQUIRED | REVIEW_REQUIRED | CLEAR
# Exit codes: 0=success, 1=error, 2=invalid input

set -euo pipefail

main() {
    local sprint_id="${1:-}"

    # Validate input
    if [ -z "$sprint_id" ]; then
        echo "ERROR|Missing sprint ID" >&2
        exit 2
    fi

    if ! echo "$sprint_id" | grep -qE "^sprint-[0-9]+$"; then
        echo "ERROR|Invalid sprint ID format: $sprint_id" >&2
        exit 2
    fi

    local sprint_dir="grimoires/loa/a2a/${sprint_id}"
    local audit_file="${sprint_dir}/auditor-sprint-feedback.md"
    local engineer_file="${sprint_dir}/engineer-feedback.md"

    # Check audit feedback first (highest priority)
    if [ -f "$audit_file" ]; then
        if grep -q "CHANGES_REQUIRED" "$audit_file"; then
            echo "AUDIT_REQUIRED"
            exit 0
        fi
        if grep -q "APPROVED" "$audit_file"; then
            # Audit passed, check engineer feedback
            :
        fi
    fi

    # Check engineer feedback
    if [ -f "$engineer_file" ]; then
        if grep -q "All good" "$engineer_file"; then
            echo "CLEAR"
            exit 0
        else
            echo "REVIEW_REQUIRED"
            exit 0
        fi
    fi

    # No feedback files - clear to proceed
    echo "CLEAR"
    exit 0
}

main "$@"
