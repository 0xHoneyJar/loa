#!/usr/bin/env bash
# check-beads.sh
# Purpose: Check if beads_rust (br CLI) is installed and offer installation options
# Enhanced in Sprint 4 for Ghost/Shadow tracking integration
# Updated in v0.19.0 for beads_rust migration
# Usage: ./check-beads.sh [--quiet|--track-ghost|--track-shadow]
#
# Exit codes:
#   0 - beads_rust is installed (or tracking succeeded)
#   1 - beads_rust is not installed (returns install instructions)
#   2 - Tracking failed (silent - never blocks workflow)
#
# Output (when not installed):
#   NOT_INSTALLED|.claude/scripts/beads/install-br.sh

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

# Check if br CLI is available
if command -v br &> /dev/null; then
    export LOA_BEADS_AVAILABLE=1

    # If tracking Ghost/Shadow, create beads_rust task
    if [[ "${ACTION}" == "--track-ghost" ]] && [[ -n "${FEATURE_NAME}" ]]; then
        # Create Ghost Feature task
        BEADS_ID=$(br create "GHOST: ${FEATURE_NAME}" \
            --type liability \
            --priority 2 \
            --json 2>/dev/null | jq -r '.id' || echo "")

        if [[ -n "${BEADS_ID}" ]]; then
            # Add ghost label
            br label add "${BEADS_ID}" ghost 2>/dev/null || true
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

        BEADS_ID=$(br create "SHADOW (${FEATURE_TYPE}): ${FEATURE_NAME}" \
            --type debt \
            --priority "${PRIORITY}" \
            --json 2>/dev/null | jq -r '.id' || echo "")

        if [[ -n "${BEADS_ID}" ]]; then
            # Add shadow label with type
            br label add "${BEADS_ID}" "shadow:${FEATURE_TYPE}" 2>/dev/null || true
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

    # beads_rust not installed - return installation options
    if [[ "${QUIET}" == true ]]; then
        echo "NOT_INSTALLED"
    else
        echo "NOT_INSTALLED|.claude/scripts/beads/install-br.sh"
    fi
    exit 1
fi
