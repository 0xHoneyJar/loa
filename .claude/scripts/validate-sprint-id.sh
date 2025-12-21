#!/bin/bash
# Validate sprint ID format
# Usage: ./validate-sprint-id.sh sprint-N
# Returns: VALID | INVALID|reason
# Exit codes: 0=valid, 1=invalid

set -euo pipefail

main() {
    local sprint_id="${1:-}"

    # Check if provided
    if [ -z "$sprint_id" ]; then
        echo "INVALID|Missing sprint ID"
        exit 1
    fi

    # Check format: sprint-N where N is positive integer
    if ! echo "$sprint_id" | grep -qE "^sprint-[0-9]+$"; then
        echo "INVALID|Format must be sprint-N where N is a positive integer"
        exit 1
    fi

    # Extract number and check it's positive
    local num="${sprint_id#sprint-}"
    if [ "$num" -eq 0 ]; then
        echo "INVALID|Sprint number must be positive (sprint-1 or higher)"
        exit 1
    fi

    echo "VALID"
    exit 0
}

main "$@"
