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
    # Active bug fix overrides normal journey position
    local active_bug
    if active_bug=$(golden_detect_active_bug 2>/dev/null); then
        echo "build"
        return
    fi

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
# Dispatches to bug journey when bug_active state detected.
golden_format_journey() {
    # Bug-active state gets its own journey visualization
    local active_bug_ref bug_id
    if active_bug_ref=$(golden_detect_active_bug 2>/dev/null); then
        bug_id=$(golden_parse_bug_id "${active_bug_ref}")
        golden_format_bug_journey "${bug_id}"
        return
    fi

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

# Map bug state to a bug lifecycle position.
# Returns: "triage" | "fix" | "review" | "close"
_gp_bug_journey_position() {
    local bug_id="${1:-}"
    if [[ -z "${bug_id}" ]]; then
        echo "fix"
        return
    fi

    local state_file="${PROJECT_ROOT}/.run/bugs/${bug_id}/state.json"
    if [[ ! -f "${state_file}" ]]; then
        echo "fix"
        return
    fi

    local bug_state
    bug_state=$(jq -r '.state // "IMPLEMENTING"' "${state_file}" 2>/dev/null)
    case "${bug_state}" in
        TRIAGE)       echo "triage" ;;
        IMPLEMENTING) echo "fix" ;;
        REVIEWING)    echo "review" ;;
        AUDITING)     echo "review" ;;
        COMPLETED)    echo "close" ;;
        HALTED)       echo "fix" ;;
        *)            echo "fix" ;;
    esac
}

# Render a bug-specific journey bar.
# Shows: /triage ━━━ /fix ━━━ /review ━━━ /close
golden_format_bug_journey() {
    local bug_id="${1:-}"
    local position
    position=$(_gp_bug_journey_position "${bug_id}")

    local triage_seg fix_seg review_seg close_seg
    local marker="●"

    case "${position}" in
        triage)
            triage_seg="${marker}"
            fix_seg="─"
            review_seg="─"
            close_seg="─"
            ;;
        fix)
            triage_seg="━"
            fix_seg="${marker}"
            review_seg="─"
            close_seg="─"
            ;;
        review)
            triage_seg="━"
            fix_seg="━"
            review_seg="${marker}"
            close_seg="─"
            ;;
        close)
            triage_seg="━"
            fix_seg="━"
            review_seg="━"
            close_seg="${marker}"
            ;;
    esac

    echo "/triage ${triage_seg}━━━━━ /fix ${fix_seg}━━━━━ /review ${review_seg}━━━━━ /close ${close_seg}"
}

# ─────────────────────────────────────────────────────────────
# Trajectory Narrative (v1.39.0 — Environment Design)
# ─────────────────────────────────────────────────────────────

# Generate trajectory narrative for session startup.
# Returns prose summary of project history, current frontier, and open visions.
# Falls back gracefully if trajectory-gen.sh is unavailable.
golden_trajectory() {
    local mode="${1:---prose}"  # --prose (default) | --condensed | --json
    local script="${SCRIPT_DIR}/trajectory-gen.sh"

    if [[ ! -x "$script" ]]; then
        return 0  # Silent fallback — trajectory is optional
    fi

    local flag=""
    case "$mode" in
        --condensed) flag="--condensed" ;;
        --json) flag="--json" ;;
        *) flag="" ;;
    esac

    # Time-bounded: 2-second timeout
    timeout 2 "$script" $flag 2>/dev/null || return 0
}

# ─────────────────────────────────────────────────────────────
# Workflow State Detection (v1.34.0 — Onboarding UX)
# ─────────────────────────────────────────────────────────────

# Detect unified workflow state as a single string.
# Returns one of 9 states with deterministic priority:
#   1. bug_active      — Active bug fix in .run/bugs/ (overrides all)
#   2. initial         — No PRD exists
#   3. prd_created     — PRD exists, no SDD
#   4. sdd_created     — SDD exists, no sprint plan
#   5. implementing    — Incomplete sprint, not yet reviewed
#   6. reviewing       — Sprint needs review
#   7. auditing        — Sprint reviewed, needs audit
#   8. complete        — All sprints reviewed + audited
#   9. sprint_planned  — Sprint plan exists, no work started (fallback)
golden_detect_workflow_state() {
    # Priority 1: Active bug overrides everything
    if golden_detect_active_bug >/dev/null 2>&1; then
        echo "bug_active"
        return
    fi

    # Priority 2-4: Planning phases
    local plan_phase
    plan_phase=$(golden_detect_plan_phase)
    case "${plan_phase}" in
        discovery) echo "initial"; return ;;
        architecture) echo "prd_created"; return ;;
        sprint_planning) echo "sdd_created"; return ;;
    esac

    # Priority 5-8: Sprint execution states
    local sprint review_target
    sprint=$(golden_detect_sprint)
    review_target=$(golden_detect_review_target)

    if [[ -z "${sprint}" ]]; then
        # All sprints done — check ship readiness
        if golden_check_ship_ready >/dev/null 2>&1; then
            echo "complete"
        else
            # WHY: ship_ready fails when reviews/audits are incomplete, OR
            # on ledger issues, missing markers, etc. "reviewing" is
            # intentionally conservative — it prompts investigation rather
            # than falsely reporting "complete". The /review command will
            # surface the specific blocker.
            echo "reviewing"
        fi
        return
    fi

    local sprint_dir="${_GP_A2A_DIR}/${sprint}"
    if [[ ! -d "${sprint_dir}" ]]; then
        # Sprint plan exists but no work started
        echo "sprint_planned"
        return
    fi

    # Sprint dir exists — check if it needs review or audit
    if [[ -n "${review_target}" ]]; then
        if _gp_sprint_is_reviewed "${review_target}" 2>/dev/null && \
           ! _gp_sprint_is_audited "${review_target}" 2>/dev/null; then
            echo "auditing"
        else
            echo "reviewing"
        fi
    else
        echo "implementing"
    fi
}

# ─────────────────────────────────────────────────────────────
# Context-Aware Menu Options (v1.34.0 — Onboarding UX)
# ─────────────────────────────────────────────────────────────

# Generate menu options for AskUserQuestion integration.
# Each line is pipe-delimited: label|description|action
# With --json flag, outputs a JSON array instead.
# Action values: plan, build, review, ship, loa-setup, loa-doctor,
#   archive-cycle, read:PATH, help-full
golden_menu_options() {
    local json_mode=false
    if [[ "${1:-}" == "--json" ]]; then
        json_mode=true
    fi

    local state
    state=$(golden_detect_workflow_state)

    # Collect pipe-delimited lines in an array
    local -a lines=()

    case "${state}" in
        initial)
            lines+=("Plan a new project|Gather requirements and design your project|plan")
            lines+=("Run setup wizard|Check dependencies and configure Loa|loa-setup")
            lines+=("Check system health|Run full diagnostic check|loa-doctor")
            ;;
        prd_created)
            lines+=("Continue planning (architecture)|Design system architecture from PRD|plan")
            lines+=("View PRD|Read the current requirements document|read:${_GP_PRD_FILE}")
            lines+=("Check system health|Run full diagnostic check|loa-doctor")
            ;;
        sdd_created)
            lines+=("Continue planning (sprints)|Create sprint plan from architecture|plan")
            lines+=("View architecture|Read the current design document|read:${_GP_SDD_FILE}")
            lines+=("Check system health|Run full diagnostic check|loa-doctor")
            ;;
        sprint_planned)
            lines+=("Build sprint-1|Start implementing the first sprint|build")
            lines+=("Review sprint plan|Read the sprint breakdown|read:${_GP_SPRINT_FILE}")
            lines+=("Check system health|Run full diagnostic check|loa-doctor")
            ;;
        implementing)
            local sprint
            sprint=$(golden_detect_sprint)
            local review_target
            review_target=$(golden_detect_review_target)
            lines+=("Build ${sprint}|Continue implementing the current sprint|build")
            if [[ -n "${review_target}" && "${review_target}" != "${sprint}" ]]; then
                lines+=("Review ${review_target}|Code review and security audit|review")
            else
                lines+=("Check progress|View detailed sprint status|loa-doctor")
            fi
            lines+=("Check system health|Run full diagnostic check|loa-doctor")
            ;;
        reviewing|auditing)
            local review_target
            review_target=$(golden_detect_review_target)
            lines+=("Review ${review_target:-current sprint}|Code review and security audit|review")
            lines+=("Continue building|Resume sprint implementation|build")
            lines+=("Check system health|Run full diagnostic check|loa-doctor")
            ;;
        complete)
            lines+=("Ship this release|Deploy to production and archive cycle|ship")
            lines+=("Plan new cycle|Archive current cycle and start fresh|archive-cycle")
            lines+=("Check system health|Run full diagnostic check|loa-doctor")
            ;;
        bug_active)
            local active_bug_ref bug_id bug_title
            if active_bug_ref=$(golden_detect_active_bug 2>/dev/null); then
                bug_id=$(golden_parse_bug_id "${active_bug_ref}")
                local state_file="${PROJECT_ROOT}/.run/bugs/${bug_id}/state.json"
                bug_title=$(jq -r '.bug_title // "Unknown bug"' "${state_file}" 2>/dev/null)
                # Truncate title to 40 chars
                if [[ ${#bug_title} -gt 40 ]]; then
                    bug_title="${bug_title:0:37}..."
                fi
                # Sanitize pipe chars to prevent delimiter collision
                bug_title="${bug_title//|/-}"
            else
                bug_title="Active bug"
            fi
            lines+=("Fix bug: ${bug_title}|Continue bug fix implementation|build")
            lines+=("Return to feature sprint|Switch back to planned work|build")
            lines+=("Check system health|Run full diagnostic check|loa-doctor")
            ;;
    esac

    # Slot 4 is always present
    lines+=("View all commands|See all available Loa commands|help-full")

    if [[ "${json_mode}" == "true" ]]; then
        # Convert pipe-delimited lines to JSON array via jq
        local json_arr="[]"
        local idx=0
        for line in "${lines[@]}"; do
            local label desc action recommended
            label="${line%%|*}"
            local rest="${line#*|}"
            desc="${rest%%|*}"
            action="${rest#*|}"
            recommended=$( (( idx == 0 )) && echo "true" || echo "false" )
            json_arr=$(echo "${json_arr}" | jq \
                --arg l "${label}" \
                --arg d "${desc}" \
                --arg a "${action}" \
                --argjson r "${recommended}" \
                '. + [{"label":$l,"description":$d,"action":$a,"recommended":$r}]')
            idx=$((idx + 1))
        done
        echo "${json_arr}"
    else
        for line in "${lines[@]}"; do
            echo "${line}"
        done
    fi
}

# ─────────────────────────────────────────────────────────────
# Golden Command Suggestions
# ─────────────────────────────────────────────────────────────

# Suggest the next golden command based on current state.
# Returns a single golden command string.
golden_suggest_command() {
    # Active bug fix takes priority over feature sprint workflow
    local active_bug
    if active_bug=$(golden_detect_active_bug 2>/dev/null); then
        echo "/build"
        return
    fi

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
# Bug Detection (v1.32.0 — Issue #278)
# ─────────────────────────────────────────────────────────────

# Detect most recent active bug fix from namespaced state.
# Returns: "bug_id:state_hash" on stdout, exit 0 if found, exit 1 if none.
# The state_hash is an md5 of the state file at detection time, enabling
# callers to verify the state hasn't changed between detection and action
# (TOCTOU safety for future concurrent multi-model execution).
# Use golden_parse_bug_id() to extract just the bug_id.
# Concurrent bugs → returns most recently modified.
golden_detect_active_bug() {
    local bugs_dir="${PROJECT_ROOT}/.run/bugs"
    [[ -d "${bugs_dir}" ]] || return 1

    local latest_bug=""
    local latest_time=0
    local latest_hash=""

    local state_file
    for state_file in "${bugs_dir}"/*/state.json; do
        [[ -f "${state_file}" ]] || continue
        local state
        state=$(jq -r '.state // empty' "${state_file}" 2>/dev/null) || continue
        if [[ "${state}" != "COMPLETED" && "${state}" != "HALTED" ]]; then
            local mtime
            mtime=$(stat -c %Y "${state_file}" 2>/dev/null || stat -f %m "${state_file}" 2>/dev/null) || continue
            if (( mtime > latest_time )); then
                latest_time="${mtime}"
                latest_bug=$(jq -r '.bug_id // empty' "${state_file}" 2>/dev/null)
                latest_hash=$(md5sum "${state_file}" 2>/dev/null | cut -d' ' -f1 || md5 -q "${state_file}" 2>/dev/null) || latest_hash="none"
            fi
        fi
    done

    if [[ -n "${latest_bug}" ]]; then
        echo "${latest_bug}:${latest_hash}"
        return 0
    fi
    return 1
}

# Parse bug_id from golden_detect_active_bug() output.
# Args: $1 = "bug_id:state_hash" string from golden_detect_active_bug
# Returns: bug_id on stdout (strips the :hash suffix).
golden_parse_bug_id() {
    echo "${1%%:*}"
}

# Verify that a bug's state hasn't changed since detection.
# Args: $1 = bug_id, $2 = state_hash from golden_detect_active_bug
# Returns: 0 if state matches (safe to act), 1 if changed (stale).
golden_verify_bug_state() {
    local bug_id="${1:-}"
    local expected_hash="${2:-}"
    [[ -z "${bug_id}" || -z "${expected_hash}" ]] && return 1
    [[ "${expected_hash}" == "none" ]] && return 0  # Hash unavailable, skip check

    local state_file="${PROJECT_ROOT}/.run/bugs/${bug_id}/state.json"
    [[ -f "${state_file}" ]] || return 1

    local current_hash
    current_hash=$(md5sum "${state_file}" 2>/dev/null | cut -d' ' -f1 || md5 -q "${state_file}" 2>/dev/null) || return 0

    [[ "${current_hash}" == "${expected_hash}" ]]
}

# Check if a micro-sprint exists for a given bug.
# Args: $1 = bug_id
# Returns: 0 if sprint file exists, 1 otherwise.
golden_detect_micro_sprint() {
    local bug_id="${1:-}"
    [[ -z "${bug_id}" ]] && return 1
    local sprint_file="${_GP_A2A_DIR}/bug-${bug_id}/sprint.md"
    [[ -f "${sprint_file}" ]]
}

# Get the sprint ID for an active bug from its state file.
# Args: $1 = bug_id
# Returns: sprint_id on stdout, exit 0 if found, exit 1 if none.
golden_get_bug_sprint_id() {
    local bug_id="${1:-}"
    [[ -z "${bug_id}" ]] && return 1
    local state_file="${PROJECT_ROOT}/.run/bugs/${bug_id}/state.json"
    [[ -f "${state_file}" ]] || return 1
    local sprint_id
    sprint_id=$(jq -r '.sprint_id // empty' "${state_file}" 2>/dev/null) || return 1
    if [[ -n "${sprint_id}" ]]; then
        echo "${sprint_id}"
        return 0
    fi
    return 1
}

# Validate a bug state transition against the allowed transition table.
# Args: $1 = current_state, $2 = proposed_state
# Returns: 0 if valid, 1 if invalid.
# Transition table (SDD Appendix E / SKILL.md):
#   TRIAGE → IMPLEMENTING
#   IMPLEMENTING → REVIEWING
#   REVIEWING → IMPLEMENTING | AUDITING
#   AUDITING → IMPLEMENTING | COMPLETED
#   ANY → HALTED
#   COMPLETED/HALTED are terminal (no transitions out except HALTED→HALTED)
golden_validate_bug_transition() {
    local current="${1:-}"
    local proposed="${2:-}"
    [[ -z "${current}" || -z "${proposed}" ]] && return 1

    # HALTED is always a valid target from any state
    [[ "${proposed}" == "HALTED" ]] && return 0

    # Terminal states: no transitions out
    if [[ "${current}" == "COMPLETED" || "${current}" == "HALTED" ]]; then
        return 1
    fi

    case "${current}" in
        TRIAGE)
            [[ "${proposed}" == "IMPLEMENTING" ]] && return 0 ;;
        IMPLEMENTING)
            [[ "${proposed}" == "REVIEWING" ]] && return 0 ;;
        REVIEWING)
            [[ "${proposed}" == "IMPLEMENTING" || "${proposed}" == "AUDITING" ]] && return 0 ;;
        AUDITING)
            [[ "${proposed}" == "IMPLEMENTING" || "${proposed}" == "COMPLETED" ]] && return 0 ;;
    esac

    return 1
}

# Dependency check: verify required tools for /bug workflow.
# Returns: 0 if all required present, 1 if missing.
golden_bug_check_deps() {
    local missing=()
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    command -v git >/dev/null 2>&1 || missing+=("git")

    if (( ${#missing[@]} > 0 )); then
        echo "Missing required tools: ${missing[*]}" >&2
        return 1
    fi
    return 0
}

# ─────────────────────────────────────────────────────────────
# Bridge State Detection (v1.34.0 — Issue #292)
# ─────────────────────────────────────────────────────────────

# Detect bridge loop state from .run/bridge-state.json.
# Returns: state string ("ITERATING", "HALTED", "FINALIZING", etc.) or "none"
golden_detect_bridge_state() {
    local bridge_file="${PROJECT_ROOT}/.run/bridge-state.json"
    if [[ -f "${bridge_file}" ]]; then
        local state
        state=$(jq -r '.state // "none"' "${bridge_file}" 2>/dev/null) || state="none"
        echo "${state}"
    else
        echo "none"
    fi
}

# Get bridge progress details for /loa display.
# Returns: human-readable progress string or empty.
golden_bridge_progress() {
    local bridge_file="${PROJECT_ROOT}/.run/bridge-state.json"
    [[ -f "${bridge_file}" ]] || return 0

    local state bridge_id depth
    state=$(jq -r '.state // "none"' "${bridge_file}" 2>/dev/null) || return 0
    [[ "${state}" == "none" || "${state}" == "JACKED_OUT" ]] && return 0

    bridge_id=$(jq -r '.bridge_id // "unknown"' "${bridge_file}" 2>/dev/null)
    depth=$(jq '.config.depth // 0' "${bridge_file}" 2>/dev/null)

    local iteration
    iteration=$(jq '.iterations | length' "${bridge_file}" 2>/dev/null || echo "0")

    case "${state}" in
        ITERATING)
            local score initial
            score=$(jq '.flatline.last_score // 0' "${bridge_file}" 2>/dev/null)
            initial=$(jq '.flatline.initial_score // 0' "${bridge_file}" 2>/dev/null)
            echo "Bridge Loop: Iteration ${iteration}/${depth} (score: ${score}, initial: ${initial})"
            ;;
        HALTED)
            echo "Bridge HALTED at iteration ${iteration}/${depth}. Resume with /run-bridge --resume"
            ;;
        FINALIZING)
            echo "Bridge finalizing after ${iteration} iterations..."
            ;;
        PREFLIGHT|JACK_IN)
            echo "Bridge starting up (${state})..."
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────
# Installation Boundary Report (Task 2.4 — cycle-035 sprint-2)
# ─────────────────────────────────────────────────────────────

# Detect installation mode from .loa-version.json.
# Returns: "submodule" | "vendored" | "unknown"
golden_detect_install_mode() {
    local version_file="${PROJECT_ROOT}/.loa-version.json"
    if [[ ! -f "${version_file}" ]]; then
        echo "unknown"
        return
    fi

    local mode
    mode=$(jq -r '.installation_mode // "standard"' "${version_file}" 2>/dev/null)
    case "${mode}" in
        submodule) echo "submodule" ;;
        standard)  echo "vendored" ;;
        *)         echo "unknown" ;;
    esac
}

# Generate installation boundary report for /loa status display.
# Returns multi-line report to stdout.
golden_boundary_report() {
    local version_file="${PROJECT_ROOT}/.loa-version.json"
    if [[ ! -f "${version_file}" ]]; then
        echo "  Installation: not detected (.loa-version.json missing)"
        return
    fi

    local mode fw_version commit_hash
    mode=$(golden_detect_install_mode)
    fw_version=$(jq -r '.framework_version // "unknown"' "${version_file}" 2>/dev/null)

    echo "  Mode:      ${mode}"
    echo "  Version:   ${fw_version}"

    if [[ "${mode}" == "submodule" ]]; then
        commit_hash=$(jq -r '.submodule.commit // "unknown"' "${version_file}" 2>/dev/null)
        local submodule_path
        submodule_path=$(jq -r '.submodule.path // ".loa"' "${version_file}" 2>/dev/null)
        echo "  Commit:    ${commit_hash:0:12}"
        echo "  Submodule: ${submodule_path}"

        # Count files in submodule
        if [[ -d "${PROJECT_ROOT}/${submodule_path}" ]]; then
            local sub_file_count
            sub_file_count=$(find "${PROJECT_ROOT}/${submodule_path}" -type f | wc -l | tr -d ' ')
            echo "  Submodule files: ${sub_file_count}"
        fi
    fi

    # Count tracked .claude/ files
    local tracked_count
    tracked_count=$(git ls-files .claude/ 2>/dev/null | wc -l | tr -d ' ')
    echo "  Tracked .claude/ files: ${tracked_count}"

    # Count gitignored files
    local ignored_count
    ignored_count=$(git ls-files --others --ignored --exclude-standard .claude/ 2>/dev/null | wc -l | tr -d ' ')
    echo "  Gitignored .claude/ files: ${ignored_count}"

    # List user-owned tracked files (non-symlink)
    local user_files
    user_files=$(git ls-files .claude/overrides/ .claude/commands/ 2>/dev/null | head -10)
    if [[ -n "${user_files}" ]]; then
        echo "  User-owned tracked files:"
        while IFS= read -r f; do
            echo "    ${f}"
        done <<< "${user_files}"
    fi
}

# ─────────────────────────────────────────────────────────────
# Truename Resolution
# ─────────────────────────────────────────────────────────────

# Validate sprint ID format (sprint-N where N is a positive integer).
# Note: Bug sprint IDs (sprint-bug-N) bypass this validation entirely via
# golden_detect_active_bug() early return in golden_resolve_truename("build").
# User-provided overrides still pass through this check.
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
            if [[ -z "${override}" ]]; then
                # Check for active bug fix first
                local active_bug_ref
                if active_bug_ref=$(golden_detect_active_bug 2>/dev/null); then
                    local active_bug
                    active_bug=$(golden_parse_bug_id "${active_bug_ref}")
                    local bug_sprint
                    if bug_sprint=$(golden_get_bug_sprint_id "${active_bug}" 2>/dev/null); then
                        echo "/implement ${bug_sprint}"
                        return
                    fi
                fi
            fi
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
