#!/usr/bin/env bash
# Validate sprint ID format with optional ledger resolution
# Usage: ./validate-sprint-id.sh sprint-N [--resolve]
# Returns:
#   VALID                           (legacy mode, no ledger)
#   VALID|global_id=N               (ledger mode, existing sprint)
#   VALID|global_id=NEW             (ledger mode, new sprint)
#   INVALID|reason                  (validation failed)
# Exit codes: 0=valid, 1=invalid

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source ledger-lib if available
source_ledger_lib() {
    local lib_path="$SCRIPT_DIR/ledger-lib.sh"
    if [[ -f "$lib_path" ]]; then
        # shellcheck source=./ledger-lib.sh
        source "$lib_path"
        return 0
    fi
    return 1
}

main() {
    local sprint_id="${1:-}"
    local resolve_mode="${2:-}"

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

    # Extract number and validate it's numeric (LOW-004)
    local num="${sprint_id#sprint-}"

    # SECURITY (LOW-004): Explicitly validate numeric before arithmetic
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        echo "INVALID|Sprint number must be numeric"
        exit 1
    fi

    if [ "$num" -eq 0 ]; then
        echo "INVALID|Sprint number must be positive (sprint-1 or higher)"
        exit 1
    fi

    # Try ledger resolution if available
    if source_ledger_lib 2>/dev/null && ledger_exists; then
        local resolved
        resolved=$(resolve_sprint "$sprint_id" 2>/dev/null) || resolved="UNRESOLVED"

        if [[ "$resolved" == "UNRESOLVED" ]]; then
            # Sprint not in ledger - it's a new sprint
            echo "VALID|global_id=NEW|local_label=$sprint_id"
        else
            # Sprint exists in ledger
            echo "VALID|global_id=$resolved|local_label=$sprint_id"
        fi
        exit 0
    fi

    # Legacy mode - no ledger
    echo "VALID"
    exit 0
}

main "$@"
