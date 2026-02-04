#!/usr/bin/env bash
# workflow-state.sh
# Purpose: Detect current Loa workflow state and progress
# Sprint: Goal Traceability v0.21.0 (FR-6, GitHub Issue #45)
# Usage: workflow-state.sh [--json] [--cache] [--no-cache]
#
# Follows RLM patterns:
# - Semantic cache integration for expensive state detection
# - Condensed output for token efficiency
# - mtime-based invalidation
#
# Exit codes:
#   0 - State detected successfully
#   1 - Error (missing files, etc.)

set -euo pipefail

# Establish project root and source path-lib
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

CACHE_MANAGER="${PROJECT_ROOT}/.claude/scripts/cache-manager.sh"

# Arguments
JSON_OUTPUT=false
USE_CACHE=true
for arg in "$@"; do
    case "$arg" in
        --json) JSON_OUTPUT=true ;;
        --cache) USE_CACHE=true ;;
        --no-cache) USE_CACHE=false ;;
    esac
done

# State constants
STATE_INITIAL="initial"
STATE_PRD_CREATED="prd_created"
STATE_SDD_CREATED="sdd_created"
STATE_SPRINT_PLANNED="sprint_planned"
STATE_IMPLEMENTING="implementing"
STATE_REVIEWING="reviewing"
STATE_AUDITING="auditing"
STATE_COMPLETE="complete"

# File paths (use path-lib getters)
_GRIMOIRE_DIR=$(get_grimoire_dir)
PRD_FILE="${_GRIMOIRE_DIR}/prd.md"
SDD_FILE="${_GRIMOIRE_DIR}/sdd.md"
SPRINT_FILE="${_GRIMOIRE_DIR}/sprint.md"
LEDGER_FILE=$(get_ledger_path)

# Function: Get current sprint from ledger
get_current_sprint() {
    if [[ -f "${LEDGER_FILE}" ]] && command -v jq >/dev/null 2>&1; then
        local active_cycle
        active_cycle=$(jq -r '.active_cycle // ""' "${LEDGER_FILE}" 2>/dev/null)
        if [[ -n "${active_cycle}" ]]; then
            # Find the first non-completed sprint in active cycle
            jq -r --arg cycle "${active_cycle}" '
                .cycles[] | select(.id == $cycle) | .sprints[]? |
                select(.status != "completed" and .status != "archived") |
                .global_id
            ' "${LEDGER_FILE}" 2>/dev/null | head -1
        fi
    fi
    echo ""
}

# Function: Get sprint count from sprint.md
get_total_sprints() {
    if [[ -f "${SPRINT_FILE}" ]]; then
        grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Function: Count completed sprints
get_completed_sprints() {
    local count=0
    local sprint_dirs
    local a2a_dir="${_GRIMOIRE_DIR}/a2a"
    sprint_dirs=$(find "${a2a_dir}" -maxdepth 1 -type d -name "sprint-*" 2>/dev/null || true)

    for dir in ${sprint_dirs}; do
        if [[ -f "${dir}/COMPLETED" ]]; then
            count=$((count + 1))
        fi
    done
    echo "${count}"
}

# Function: Get current sprint state
get_sprint_state() {
    local sprint_id="$1"
    local sprint_dir="${_GRIMOIRE_DIR}/a2a/${sprint_id}"

    if [[ -f "${sprint_dir}/COMPLETED" ]]; then
        echo "completed"
    elif [[ -f "${sprint_dir}/auditor-sprint-feedback.md" ]]; then
        if grep -q "APPROVED - LET'S FUCKING GO" "${sprint_dir}/auditor-sprint-feedback.md" 2>/dev/null; then
            echo "audit_approved"
        else
            echo "audit_changes_required"
        fi
    elif [[ -f "${sprint_dir}/engineer-feedback.md" ]]; then
        if grep -q "All good" "${sprint_dir}/engineer-feedback.md" 2>/dev/null; then
            echo "review_approved"
        else
            echo "review_changes_required"
        fi
    elif [[ -f "${sprint_dir}/reviewer.md" ]]; then
        echo "implementation_complete"
    elif [[ -d "${sprint_dir}" ]]; then
        echo "in_progress"
    else
        echo "not_started"
    fi
}

# Function: Determine overall workflow state
determine_state() {
    # Check for PRD
    if [[ ! -f "${PRD_FILE}" ]]; then
        echo "${STATE_INITIAL}"
        return
    fi

    # Check for SDD
    if [[ ! -f "${SDD_FILE}" ]]; then
        echo "${STATE_PRD_CREATED}"
        return
    fi

    # Check for Sprint Plan
    if [[ ! -f "${SPRINT_FILE}" ]]; then
        echo "${STATE_SDD_CREATED}"
        return
    fi

    # Check sprint states
    local total_sprints
    local completed_sprints
    total_sprints=$(get_total_sprints)
    completed_sprints=$(get_completed_sprints)

    # All sprints complete?
    if [[ "${completed_sprints}" -ge "${total_sprints}" ]] && [[ "${total_sprints}" -gt 0 ]]; then
        echo "${STATE_COMPLETE}"
        return
    fi

    # Find current sprint
    local current_sprint=""
    for i in $(seq 1 "${total_sprints}"); do
        local sprint_id="sprint-${i}"
        local sprint_state
        sprint_state=$(get_sprint_state "${sprint_id}")

        case "${sprint_state}" in
            completed|audit_approved)
                continue
                ;;
            review_approved)
                current_sprint="${sprint_id}"
                echo "${STATE_AUDITING}"
                return
                ;;
            implementation_complete|review_changes_required)
                current_sprint="${sprint_id}"
                echo "${STATE_REVIEWING}"
                return
                ;;
            in_progress|not_started|audit_changes_required)
                current_sprint="${sprint_id}"
                echo "${STATE_IMPLEMENTING}"
                return
                ;;
        esac
    done

    echo "${STATE_SPRINT_PLANNED}"
}

# Function: Get suggested next command
get_suggested_command() {
    local state="$1"
    local current_sprint="$2"

    case "${state}" in
        "${STATE_INITIAL}")
            echo "/plan-and-analyze"
            ;;
        "${STATE_PRD_CREATED}")
            echo "/architect"
            ;;
        "${STATE_SDD_CREATED}")
            echo "/sprint-plan"
            ;;
        "${STATE_SPRINT_PLANNED}")
            echo "/implement sprint-1"
            ;;
        "${STATE_IMPLEMENTING}")
            echo "/implement ${current_sprint}"
            ;;
        "${STATE_REVIEWING}")
            echo "/review-sprint ${current_sprint}"
            ;;
        "${STATE_AUDITING}")
            echo "/audit-sprint ${current_sprint}"
            ;;
        "${STATE_COMPLETE}")
            echo "/deploy-production"
            ;;
        *)
            echo "/plan-and-analyze"
            ;;
    esac
}

# Function: Get progress percentage
get_progress_percentage() {
    local state="$1"
    local total_sprints="$2"
    local completed_sprints="$3"

    case "${state}" in
        "${STATE_INITIAL}")
            echo "0"
            ;;
        "${STATE_PRD_CREATED}")
            echo "10"
            ;;
        "${STATE_SDD_CREATED}")
            echo "20"
            ;;
        "${STATE_SPRINT_PLANNED}")
            echo "25"
            ;;
        "${STATE_IMPLEMENTING}"|"${STATE_REVIEWING}"|"${STATE_AUDITING}")
            if [[ "${total_sprints}" -gt 0 ]]; then
                # 25% base + 70% for sprints (save 5% for deploy)
                local sprint_progress=$((completed_sprints * 70 / total_sprints))
                echo $((25 + sprint_progress))
            else
                echo "30"
            fi
            ;;
        "${STATE_COMPLETE}")
            echo "95"
            ;;
        *)
            echo "0"
            ;;
    esac
}

# Function: Get human-readable state description
get_state_description() {
    local state="$1"
    local current_sprint="$2"

    case "${state}" in
        "${STATE_INITIAL}")
            echo "No PRD found. Ready to start discovery."
            ;;
        "${STATE_PRD_CREATED}")
            echo "PRD complete. Ready for architecture design."
            ;;
        "${STATE_SDD_CREATED}")
            echo "SDD complete. Ready for sprint planning."
            ;;
        "${STATE_SPRINT_PLANNED}")
            echo "Sprint plan ready. Ready to start implementation."
            ;;
        "${STATE_IMPLEMENTING}")
            echo "Implementing ${current_sprint}."
            ;;
        "${STATE_REVIEWING}")
            echo "Review pending for ${current_sprint}."
            ;;
        "${STATE_AUDITING}")
            echo "Security audit pending for ${current_sprint}."
            ;;
        "${STATE_COMPLETE}")
            echo "All sprints complete. Ready for deployment."
            ;;
        *)
            echo "Unknown state."
            ;;
    esac
}

# Function: Generate cache key for workflow state
generate_cache_key() {
    if [[ -x "${CACHE_MANAGER}" ]]; then
        local paths=""
        [[ -f "${PRD_FILE}" ]] && paths="${PRD_FILE}"
        [[ -f "${SDD_FILE}" ]] && paths="${paths:+${paths},}${SDD_FILE}"
        [[ -f "${SPRINT_FILE}" ]] && paths="${paths:+${paths},}${SPRINT_FILE}"
        [[ -f "${LEDGER_FILE}" ]] && paths="${paths:+${paths},}${LEDGER_FILE}"

        if [[ -n "${paths}" ]]; then
            "${CACHE_MANAGER}" generate-key \
                --paths "${paths}" \
                --query "workflow-state" \
                --operation "workflow-state" 2>/dev/null || echo ""
        fi
    fi
    echo ""
}

# Function: Check cache for workflow state
check_cache() {
    local cache_key="$1"
    if [[ -n "${cache_key}" ]] && [[ -x "${CACHE_MANAGER}" ]]; then
        "${CACHE_MANAGER}" get --key "${cache_key}" 2>/dev/null
    fi
}

# Function: Store result in cache
store_cache() {
    local cache_key="$1"
    local result="$2"
    if [[ -n "${cache_key}" ]] && [[ -x "${CACHE_MANAGER}" ]]; then
        local paths=""
        [[ -f "${PRD_FILE}" ]] && paths="${PRD_FILE}"
        [[ -f "${SDD_FILE}" ]] && paths="${paths:+${paths},}${SDD_FILE}"
        [[ -f "${SPRINT_FILE}" ]] && paths="${paths:+${paths},}${SPRINT_FILE}"

        "${CACHE_MANAGER}" set \
            --key "${cache_key}" \
            --condensed "${result}" \
            --sources "${paths}" 2>/dev/null || true
    fi
}

# Main logic
main() {
    local state
    local total_sprints
    local completed_sprints
    local current_sprint=""

    # Check semantic cache first (RLM pattern)
    local cache_key=""
    if [[ "${USE_CACHE}" == "true" ]]; then
        cache_key=$(generate_cache_key)
        if [[ -n "${cache_key}" ]]; then
            local cached_result
            if cached_result=$(check_cache "${cache_key}") && [[ -n "${cached_result}" ]]; then
                # Cache hit - return cached result
                if [[ "${JSON_OUTPUT}" == "true" ]]; then
                    echo "${cached_result}"
                else
                    # Parse cached JSON for display
                    echo "${cached_result}" | jq -r '"═══════════════════════════════════════════════════\n Loa Workflow Status (cached)\n═══════════════════════════════════════════════════\n\n State: \(.state)\n \(.description)\n\n Progress: \(.progress_percent)%\n Sprints: \(.completed_sprints)/\(.total_sprints) complete\n\n───────────────────────────────────────────────────\n Suggested: \(.suggested_command)\n═══════════════════════════════════════════════════"' 2>/dev/null || echo "${cached_result}"
                fi
                return 0
            fi
        fi
    fi

    # Cache miss - compute state
    state=$(determine_state)
    total_sprints=$(get_total_sprints)
    completed_sprints=$(get_completed_sprints)

    # Find current sprint for implementing/reviewing/auditing states
    if [[ "${state}" == "${STATE_IMPLEMENTING}" ]] || \
       [[ "${state}" == "${STATE_REVIEWING}" ]] || \
       [[ "${state}" == "${STATE_AUDITING}" ]]; then
        for i in $(seq 1 "${total_sprints}"); do
            local sprint_id="sprint-${i}"
            local sprint_state
            sprint_state=$(get_sprint_state "${sprint_id}")

            if [[ "${sprint_state}" != "completed" ]] && [[ "${sprint_state}" != "audit_approved" ]]; then
                current_sprint="${sprint_id}"
                break
            fi
        done
    fi

    local suggested_command
    local progress
    local description

    suggested_command=$(get_suggested_command "${state}" "${current_sprint}")
    progress=$(get_progress_percentage "${state}" "${total_sprints}" "${completed_sprints}")
    description=$(get_state_description "${state}" "${current_sprint}")

    # Build JSON result (used for both output and caching)
    local json_result
    json_result=$(cat <<EOF
{
  "state": "${state}",
  "description": "${description}",
  "current_sprint": "${current_sprint}",
  "total_sprints": ${total_sprints},
  "completed_sprints": ${completed_sprints},
  "progress_percent": ${progress},
  "suggested_command": "${suggested_command}",
  "files": {
    "prd_exists": $([ -f "${PRD_FILE}" ] && echo "true" || echo "false"),
    "sdd_exists": $([ -f "${SDD_FILE}" ] && echo "true" || echo "false"),
    "sprint_exists": $([ -f "${SPRINT_FILE}" ] && echo "true" || echo "false")
  }
}
EOF
)

    # Store in cache for future use (RLM pattern)
    if [[ -n "${cache_key}" ]]; then
        store_cache "${cache_key}" "${json_result}"
    fi

    if [[ "${JSON_OUTPUT}" == "true" ]]; then
        echo "${json_result}"
    else
        echo "═══════════════════════════════════════════════════"
        echo " Loa Workflow Status"
        echo "═══════════════════════════════════════════════════"
        echo ""
        echo " State: ${state}"
        echo " ${description}"
        echo ""
        echo " Progress: [$(printf '█%.0s' $(seq 1 $((progress / 5))))$(printf '░%.0s' $(seq 1 $((20 - progress / 5))))] ${progress}%"
        echo ""
        if [[ -n "${current_sprint}" ]]; then
            echo " Current Sprint: ${current_sprint}"
        fi
        echo " Sprints: ${completed_sprints}/${total_sprints} complete"
        echo ""
        echo "───────────────────────────────────────────────────"
        echo " Suggested: ${suggested_command}"
        echo "═══════════════════════════════════════════════════"
    fi
}

main "$@"
