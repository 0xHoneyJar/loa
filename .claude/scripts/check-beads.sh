#!/bin/bash
# check-beads.sh
# Purpose: Check if Beads (bd CLI) is installed and offer installation options
# Enhanced in Sprint 4 for Ghost/Shadow tracking integration
# Usage: ./check-beads.sh [--quiet|--track-ghost|--track-shadow]
#
# Exit codes:
#   0 - Beads is installed (or tracking succeeded)
#   1 - Beads is not installed (returns install instructions)
#   2 - Tracking failed (silent - never blocks workflow)
#
# Output (when not installed):
#   NOT_INSTALLED|brew install steveyegge/beads/bd|npm install -g @beads/bd

set -euo pipefail

ACTION="${1:-}"
QUIET=false

# Parse arguments
case "${ACTION}" in
    --quiet)
        QUIET=true
        ;;
    --track-ghost|--track-shadow)
        # Ghost/Shadow tracking mode
        FEATURE_NAME="${2:-}"
        FEATURE_TYPE="${3:-}"
        ;;
esac

# Check if bd CLI is available
if command -v bd &> /dev/null; then
    export LOA_BEADS_AVAILABLE=1

    # If tracking Ghost/Shadow, create Beads task
    if [[ "${ACTION}" == "--track-ghost" ]] && [[ -n "${FEATURE_NAME}" ]]; then
        # Create Ghost Feature task
        BEADS_ID=$(bd create "GHOST: ${FEATURE_NAME}" \
            --type liability \
            --priority 2 \
            --json 2>/dev/null | jq -r '.id' || echo "")

        if [[ -n "${BEADS_ID}" ]]; then
            echo "${BEADS_ID}"
            exit 0
        else
            # Tracking failed, but don't block
            echo "N/A"
            exit 2
        fi
    elif [[ "${ACTION}" == "--track-shadow" ]] && [[ -n "${FEATURE_NAME}" ]] && [[ -n "${FEATURE_TYPE}" ]]; then
        # Create Shadow System task
        # Feature type should be: orphaned|drifted|partial
        PRIORITY=1  # Orphaned = high priority
        if [[ "${FEATURE_TYPE}" == "drifted" ]]; then
            PRIORITY=2
        elif [[ "${FEATURE_TYPE}" == "partial" ]]; then
            PRIORITY=3
        fi

        BEADS_ID=$(bd create "SHADOW (${FEATURE_TYPE}): ${FEATURE_NAME}" \
            --type debt \
            --priority "${PRIORITY}" \
            --json 2>/dev/null | jq -r '.id' || echo "")

        if [[ -n "${BEADS_ID}" ]]; then
            echo "${BEADS_ID}"
            exit 0
        else
            # Tracking failed, but don't block
            echo "N/A"
            exit 2
        fi
    else
        # Just checking availability
        if [[ "${QUIET}" == false ]]; then
            echo "INSTALLED"
        fi
        exit 0
    fi
else
    export LOA_BEADS_AVAILABLE=0

    # For tracking actions, return N/A (don't block)
    if [[ "${ACTION}" == "--track-ghost" ]] || [[ "${ACTION}" == "--track-shadow" ]]; then
        echo "N/A"
        exit 2
    fi

    # Beads not installed - return installation options
    if [[ "${QUIET}" == true ]]; then
        echo "NOT_INSTALLED"
    else
        echo "NOT_INSTALLED|brew install steveyegge/beads/bd|npm install -g @beads/bd"
    fi
    exit 1
fi
