#!/usr/bin/env bash
# golden-path.sh - State resolution for Golden Path commands
# Issue: #211 — DX Golden Path Simplification
#
# Provides shared helpers for the 5 golden commands (/loa, /plan, /build,
# /review, /ship) to auto-detect workflow state and route to truename commands.
#
# Usage:
#   source .claude/scripts/golden-path.sh
#
#   golden_detect_sprint          # → "sprint-2" or ""
#   golden_detect_plan_phase      # → "discovery" | "architecture" | "sprint_planning" | "complete"
#   golden_detect_review_target   # → "sprint-2" or ""
#   golden_check_ship_ready       # → exit 0 (ready) | exit 1 (not ready)
#   golden_format_journey         # → visual journey bar string
#   golden_suggest_command        # → golden command for current state
#
# Design: Porcelain & Plumbing (git model)
#   Golden Path = porcelain (5 commands for 90% of users)
#   Truenames   = plumbing (43 commands for power users)

set -euo pipefail

# Source bootstrap for PROJECT_ROOT and path-lib
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/bootstrap.sh"

# Resolve paths using path-lib getters
_GP_GRIMOIRE_DIR=$(get_grimoire_dir)
_GP_PRD_FILE="${_GP_GRIMOIRE_DIR}/prd.md"
_GP_SDD_FILE="${_GP_GRIMOIRE_DIR}/sdd.md"
_GP_SPRINT_FILE="${_GP_GRIMOIRE_DIR}/sprint.md"
_GP_A2A_DIR="${_GP_GRIMOIRE_DIR}/a2a"

# ─────────────────────────────────────────────────────────────
# Planning Phase Detection
# ─────────────────────────────────────────────────────────────

# Detect which planning phase the user is in.
# Returns: "discovery" | "architecture" | "sprint_planning" | "complete"
golden_detect_plan_phase() {
    if [[ ! -f "${_GP_PRD_FILE}" ]]; then
        echo "discovery"
    elif [[ ! -f "${_GP_SDD_FILE}" ]]; then
        echo "architecture"
    elif [[ ! -f "${_GP_SPRINT_FILE}" ]]; then
        echo "sprint_planning"
    else
        echo "complete"
    fi
}

# ─────────────────────────────────────────────────────────────
# Sprint Detection
# ─────────────────────────────────────────────────────────────

# Count total sprints from sprint.md headers
_gp_count_sprints() {
    if [[ -f "${_GP_SPRINT_FILE}" ]]; then
        grep -c "^## Sprint [0-9]" "${_GP_SPRINT_FILE}" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Check if a specific sprint is complete
_gp_sprint_is_complete() {
    local sprint_id="$1"
    local sprint_dir="${_GP_A2A_DIR}/${sprint_id}"
    [[ -f "${sprint_dir}/COMPLETED" ]]
}

# Check if a sprint has been reviewed (no findings or no required changes).
# Detection: feedback file exists AND contains no "## Changes Required" or "## Findings" sections,
# OR the sprint has already passed audit (which implies review was acceptable).
_gp_sprint_is_reviewed() {
    local sprint_id="$1"
    local sprint_dir="${_GP_A2A_DIR}/${sprint_id}"

    # If already audited, review is implicitly passed
    if _gp_sprint_is_audited "${sprint_id}"; then
        return 0
    fi

    if [[ -f "${sprint_dir}/engineer-feedback.md" ]]; then
        # If feedback file has no actionable findings, review passed
        if ! grep -qE "^## (Changes Required|Findings|Issues)" "${sprint_dir}/engineer-feedback.md" 2>/dev/null; then
            return 0
        fi
        return 1
    fi
    return 1
}

# Check if a sprint has been audited
_gp_sprint_is_audited() {
    local sprint_id="$1"
    local sprint_dir="${_GP_A2A_DIR}/${sprint_id}"

    if [[ -f "${sprint_dir}/auditor-sprint-feedback.md" ]]; then
        grep -q "APPROVED" "${sprint_dir}/auditor-sprint-feedback.md" 2>/dev/null
        return $?
    fi
    return 1
}

# Detect the current sprint to work on.
# Returns: "sprint-N" or "" if none/all complete.
golden_detect_sprint() {
    local total
    total=$(_gp_count_sprints)

    if [[ "${total}" -eq 0 ]]; then
        echo ""
        return
    fi

    local i
    for i in $(seq 1 "${total}"); do
        local sprint_id="sprint-${i}"
        if ! _gp_sprint_is_complete "${sprint_id}"; then
            echo "${sprint_id}"
            return
        fi
    done

    # All complete
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Review Target Detection
# ─────────────────────────────────────────────────────────────

# Find the most recent sprint that needs review.
# A sprint "needs review" if it has been implemented but not yet reviewed+audited.
# Returns: "sprint-N" or "" if nothing to review.
golden_detect_review_target() {
    local total
    total=$(_gp_count_sprints)

    if [[ "${total}" -eq 0 ]]; then
        echo ""
        return
    fi

    local i
    for i in $(seq 1 "${total}"); do
        local sprint_id="sprint-${i}"
        local sprint_dir="${_GP_A2A_DIR}/${sprint_id}"

        # Skip sprints that are fully complete (reviewed + audited + marked)
        if _gp_sprint_is_complete "${sprint_id}"; then
            continue
        fi

        # If sprint dir exists (implementation started), it may need review
        if [[ -d "${sprint_dir}" ]]; then
            echo "${sprint_id}"
            return
        fi
    done

    echo ""
}

# ─────────────────────────────────────────────────────────────
# Ship Readiness Check
# ─────────────────────────────────────────────────────────────

# Check if the project is ready to ship.
# Returns 0 if ready, 1 if not. Prints reason to stdout on failure.
golden_check_ship_ready() {
    local total
    total=$(_gp_count_sprints)

    if [[ "${total}" -eq 0 ]]; then
        echo "No sprint plan found. Run /plan first."
        return 1
    fi

    local i
    for i in $(seq 1 "${total}"); do
        local sprint_id="sprint-${i}"

        if ! _gp_sprint_is_complete "${sprint_id}"; then
            if ! _gp_sprint_is_reviewed "${sprint_id}"; then
                echo "${sprint_id} has not been reviewed. Run /review first."
                return 1
            fi
            if ! _gp_sprint_is_audited "${sprint_id}"; then
                echo "${sprint_id} has not been audited. Run /review first."
                return 1
            fi
        fi
    done

    return 0
}

# ─────────────────────────────────────────────────────────────
# Journey Bar Visualization
# ─────────────────────────────────────────────────────────────

# Map workflow state to a golden path position.
# Returns: "plan" | "build" | "review" | "ship" | "done"
_gp_journey_position() {
    local plan_phase
    plan_phase=$(golden_detect_plan_phase)

    if [[ "${plan_phase}" != "complete" ]]; then
        echo "plan"
        return
    fi

    local sprint
    sprint=$(golden_detect_sprint)

    if [[ -n "${sprint}" ]]; then
        # Check if this sprint needs review vs implementation
        local sprint_dir="${_GP_A2A_DIR}/${sprint}"
        if [[ -d "${sprint_dir}" ]] && _gp_sprint_is_reviewed "${sprint}"; then
            echo "review"
        elif [[ -d "${sprint_dir}" ]]; then
            # Has sprint dir but not reviewed — could be building or reviewing
            local total
            total=$(_gp_count_sprints)
            local completed=0
            local idx
            for idx in $(seq 1 "${total}"); do
                if _gp_sprint_is_complete "sprint-${idx}"; then
                    completed=$((completed + 1))
                fi
            done

            if [[ "${completed}" -eq $((total - 1)) ]]; then
                # Last sprint — check if it's in review
                echo "review"
            else
                echo "build"
            fi
        else
            echo "build"
        fi
        return
    fi

    # All sprints complete
    local ship_check
    if ship_check=$(golden_check_ship_ready) 2>/dev/null; then
        echo "ship"
    else
        echo "review"
    fi
}

# Render the visual journey bar.
# Uses Unicode box drawing and bold markers.
golden_format_journey() {
    local position
    position=$(_gp_journey_position)

    local plan_seg build_seg review_seg ship_seg
    local marker="●"

    case "${position}" in
        plan)
            plan_seg="${marker}"
            build_seg="─"
            review_seg="─"
            ship_seg="─"
            ;;
        build)
            plan_seg="━"
            build_seg="${marker}"
            review_seg="─"
            ship_seg="─"
            ;;
        review)
            plan_seg="━"
            build_seg="━"
            review_seg="${marker}"
            ship_seg="─"
            ;;
        ship|done)
            plan_seg="━"
            build_seg="━"
            review_seg="━"
            ship_seg="${marker}"
            ;;
    esac

    echo "/plan ${plan_seg}━━━━━ /build ${build_seg}━━━━━ /review ${review_seg}━━━━━ /ship ${ship_seg}"
}

# ─────────────────────────────────────────────────────────────
# Golden Command Suggestions
# ─────────────────────────────────────────────────────────────

# Suggest the next golden command based on current state.
# Returns a single golden command string.
golden_suggest_command() {
    local plan_phase
    plan_phase=$(golden_detect_plan_phase)

    if [[ "${plan_phase}" != "complete" ]]; then
        echo "/plan"
        return
    fi

    local sprint
    sprint=$(golden_detect_sprint)

    if [[ -n "${sprint}" ]]; then
        echo "/build"
        return
    fi

    # All sprints complete — check ship readiness (review + audit)
    if ! golden_check_ship_ready >/dev/null 2>&1; then
        echo "/review"
        return
    fi

    echo "/ship"
}

# ─────────────────────────────────────────────────────────────
# Truename Resolution
# ─────────────────────────────────────────────────────────────

# Validate sprint ID format (sprint-N where N is a positive integer).
_gp_validate_sprint_id() {
    local id="$1"
    [[ "${id}" =~ ^sprint-[1-9][0-9]*$ ]]
}

# Resolve a golden command to its truename(s) with arguments.
# Args: golden_command [override_arg]
# Returns: truename command string
golden_resolve_truename() {
    local command="${1:-}"
    local override="${2:-}"

    # Validate override format for sprint-accepting commands
    if [[ -n "${override}" ]] && [[ "${command}" == "build" || "${command}" == "review" ]]; then
        if ! _gp_validate_sprint_id "${override}"; then
            echo "Invalid sprint ID: ${override} (expected: sprint-N)" >&2
            return 1
        fi
    fi

    case "${command}" in
        plan)
            local phase
            phase=$(golden_detect_plan_phase)
            case "${phase}" in
                discovery) echo "/plan-and-analyze" ;;
                architecture) echo "/architect" ;;
                sprint_planning) echo "/sprint-plan" ;;
                complete) echo "" ;;
            esac
            ;;
        build)
            local sprint
            sprint="${override:-$(golden_detect_sprint)}"
            if [[ -n "${sprint}" ]]; then
                echo "/implement ${sprint}"
            fi
            ;;
        review)
            local target
            target="${override:-$(golden_detect_review_target)}"
            if [[ -n "${target}" ]]; then
                echo "/review-sprint ${target}"
            fi
            ;;
        ship)
            echo "/deploy-production"
            ;;
    esac
}
