#!/usr/bin/env bash
# suggest-next-step.sh
# Purpose: Suggest next workflow step based on workflow chain definition
# Sprint: 4 (Agent Chaining - FR-8.1, GitHub Issue #9)
# Usage: suggest-next-step.sh <current_phase> [sprint_id]
#
# Exit codes:
#   0 - Suggestion generated successfully
#   1 - Error (missing workflow chain, invalid phase, etc.)
#   2 - No next step (end of workflow)

set -euo pipefail

# Establish project root
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
WORKFLOW_CHAIN="${PROJECT_ROOT}/.claude/workflow-chain.yaml"

# Arguments
CURRENT_PHASE="${1:-}"
SPRINT_ID="${2:-}"

# Check if yq is available (required for YAML parsing)
if ! command -v yq >/dev/null 2>&1; then
    echo "ERROR: yq is required for workflow chain parsing" >&2
    echo "Install: brew install yq (macOS) or apt install yq (Linux)" >&2
    exit 1
fi

# Check if workflow chain exists
if [[ ! -f "${WORKFLOW_CHAIN}" ]]; then
    echo "ERROR: Workflow chain not found: ${WORKFLOW_CHAIN}" >&2
    exit 1
fi

# Validate current phase argument
if [[ -z "${CURRENT_PHASE}" ]]; then
    echo "ERROR: Current phase required" >&2
    echo "Usage: suggest-next-step.sh <current_phase> [sprint_id]" >&2
    exit 1
fi

# Function: Check if file exists with variable substitution
check_file_exists() {
    local path="$1"
    # Substitute {sprint} variable
    path="${path//\{sprint\}/${SPRINT_ID}}"
    [[ -f "${PROJECT_ROOT}/${path}" ]]
}

# Function: Check if file content matches pattern
check_content_match() {
    local path="$1"
    local pattern="$2"
    # Substitute {sprint} variable
    path="${path//\{sprint\}/${SPRINT_ID}}"
    [[ -f "${PROJECT_ROOT}/${path}" ]] && grep -q "${pattern}" "${PROJECT_ROOT}/${path}"
}

# Function: Substitute variables in string
substitute_vars() {
    local text="$1"

    # Substitute {sprint}
    text="${text//\{sprint\}/${SPRINT_ID}}"

    # Substitute {N+1} (next sprint number)
    if [[ -n "${SPRINT_ID}" ]] && [[ "${SPRINT_ID}" =~ sprint-([0-9]+) ]]; then
        CURRENT_SPRINT_NUM="${BASH_REMATCH[1]}"
        NEXT_SPRINT_NUM=$((CURRENT_SPRINT_NUM + 1))
        text="${text//\{N+1\}/sprint-${NEXT_SPRINT_NUM}}"
    fi

    echo "${text}"
}

# Function: Get next step for phase
get_next_step() {
    local phase="$1"

    # Check if phase exists in workflow or auxiliary commands
    if yq eval ".workflow.\"${phase}\"" "${WORKFLOW_CHAIN}" | grep -q "null"; then
        if yq eval ".auxiliary_commands.\"${phase}\"" "${WORKFLOW_CHAIN}" | grep -q "null"; then
            echo "ERROR: Unknown phase: ${phase}" >&2
            exit 1
        else
            # Auxiliary command
            NEXT_STEP=$(yq eval ".auxiliary_commands.\"${phase}\".next" "${WORKFLOW_CHAIN}")
            MESSAGE=$(yq eval ".auxiliary_commands.\"${phase}\".message" "${WORKFLOW_CHAIN}")
        fi
    else
        # Main workflow phase
        NEXT_STEP=$(yq eval ".workflow.\"${phase}\".next" "${WORKFLOW_CHAIN}")
        MESSAGE=$(yq eval ".workflow.\"${phase}\".message" "${WORKFLOW_CHAIN}")
    fi

    # Handle null next step (end of workflow)
    if [[ "${NEXT_STEP}" == "null" ]]; then
        if [[ "${MESSAGE}" != "null" ]]; then
            echo "${MESSAGE}"
        fi
        exit 2
    fi

    # Apply variable substitution
    NEXT_STEP=$(substitute_vars "${NEXT_STEP}")
    MESSAGE=$(substitute_vars "${MESSAGE}")

    echo "${MESSAGE}"
}

# Function: Handle conditional routing (review/audit phases)
get_conditional_next() {
    local phase="$1"

    # Get validation info
    local validation_type=$(yq eval ".workflow.\"${phase}\".validation.type" "${WORKFLOW_CHAIN}")
    local validation_path=$(yq eval ".workflow.\"${phase}\".validation.path" "${WORKFLOW_CHAIN}")
    local validation_pattern=$(yq eval ".workflow.\"${phase}\".validation.pattern" "${WORKFLOW_CHAIN}")

    # Get conditional next steps
    local next_on_approval=$(yq eval ".workflow.\"${phase}\".next_on_approval" "${WORKFLOW_CHAIN}")
    local next_on_feedback=$(yq eval ".workflow.\"${phase}\".next_on_feedback" "${WORKFLOW_CHAIN}")
    local next_on_changes=$(yq eval ".workflow.\"${phase}\".next_on_changes" "${WORKFLOW_CHAIN}")

    local message_on_approval=$(yq eval ".workflow.\"${phase}\".message_on_approval" "${WORKFLOW_CHAIN}")
    local message_on_feedback=$(yq eval ".workflow.\"${phase}\".message_on_feedback" "${WORKFLOW_CHAIN}")
    local message_on_changes=$(yq eval ".workflow.\"${phase}\".message_on_changes" "${WORKFLOW_CHAIN}")

    # Check if validation passes (approval)
    if [[ "${validation_type}" == "file_content_match" ]]; then
        if check_content_match "${validation_path}" "${validation_pattern}"; then
            # Approval path
            if [[ "${next_on_approval}" != "null" ]]; then
                NEXT_STEP=$(substitute_vars "${next_on_approval}")
                MESSAGE=$(substitute_vars "${message_on_approval}")
                echo "${MESSAGE}"
                return 0
            fi
        else
            # Feedback/changes required path
            if [[ "${next_on_feedback}" != "null" ]]; then
                NEXT_STEP=$(substitute_vars "${next_on_feedback}")
                MESSAGE=$(substitute_vars "${message_on_feedback}")
                echo "${MESSAGE}"
                return 0
            elif [[ "${next_on_changes}" != "null" ]]; then
                NEXT_STEP=$(substitute_vars "${next_on_changes}")
                MESSAGE=$(substitute_vars "${message_on_changes}")
                echo "${MESSAGE}"
                return 0
            fi
        fi
    fi

    # Fall back to simple next step
    get_next_step "${phase}"
}

# Main logic
case "${CURRENT_PHASE}" in
    # Phases with simple next step
    plan-and-analyze|architect|sprint-plan|implement|mount|ride)
        # Validate output file exists
        if [[ "${CURRENT_PHASE}" == "implement" ]] || [[ "${CURRENT_PHASE}" == "review-sprint" ]] || [[ "${CURRENT_PHASE}" == "audit-sprint" ]]; then
            if [[ -z "${SPRINT_ID}" ]]; then
                echo "ERROR: Sprint ID required for ${CURRENT_PHASE} phase" >&2
                exit 1
            fi
        fi

        OUTPUT_FILE=$(yq eval ".workflow.\"${CURRENT_PHASE}\".output_file" "${WORKFLOW_CHAIN}")
        if [[ "${OUTPUT_FILE}" != "null" ]]; then
            OUTPUT_FILE=$(substitute_vars "${OUTPUT_FILE}")
            if ! check_file_exists "${OUTPUT_FILE}"; then
                echo "ERROR: Output file not found: ${OUTPUT_FILE}" >&2
                echo "Phase may not be complete." >&2
                exit 1
            fi
        fi

        get_next_step "${CURRENT_PHASE}"
        ;;

    # Phases with conditional routing
    review-sprint|audit-sprint)
        if [[ -z "${SPRINT_ID}" ]]; then
            echo "ERROR: Sprint ID required for ${CURRENT_PHASE} phase" >&2
            exit 1
        fi

        # Check if output file exists
        OUTPUT_FILE=$(yq eval ".workflow.\"${CURRENT_PHASE}\".output_file" "${WORKFLOW_CHAIN}")
        if [[ "${OUTPUT_FILE}" != "null" ]]; then
            OUTPUT_FILE=$(substitute_vars "${OUTPUT_FILE}")
            if ! check_file_exists "${OUTPUT_FILE}"; then
                echo "ERROR: Output file not found: ${OUTPUT_FILE}" >&2
                echo "Phase may not be complete." >&2
                exit 1
            fi
        fi

        get_conditional_next "${CURRENT_PHASE}"
        ;;

    # One-off commands (no next step)
    deploy-production|audit|translate|contribute|update)
        get_next_step "${CURRENT_PHASE}"
        ;;

    # Unknown phase
    *)
        echo "ERROR: Unknown phase: ${CURRENT_PHASE}" >&2
        exit 1
        ;;
esac
