#!/usr/bin/env bash
# =============================================================================
# implement-gate.sh — Dual-mode compliance hook for App Zone writes (FR-7)
# =============================================================================
# Checks whether Write/Edit to App Zone files occurs within an active
# /implement or /bug skill invocation.
#
# Two detection modes:
#   1. HEURISTIC (ADVISORY, the default): reads .run/ state files for RUNNING state
#   2. AUTHORITATIVE: reads tool_input.active_skill from hook stdin, only when
#      .loa.config.yaml sets implement_gate.mode: authoritative. The PreToolUse
#      payload carries no harness-set skill field (cycle-126 D-4.4) and tool_input
#      is model-authored, so nothing in .run/ selects this mode.
#
# Evidence recorder (cycle-126 D-4.4): a lead-session payload carrying
# tool_input.active_skill records active_skill_seen_at once in
# .run/platform-features.json. It is evidence only and never changes the mode.
#
# Failure mode: FAIL-ASK for App Zone writes (not fail-open).
# Non-App-Zone writes always allowed.
#
# IMPORTANT: No set -euo pipefail — hook must never crash-block.
# Parse/read errors on App Zone writes → ask (not allow).
#
# Part of cycle-049/050: Upstream Platform Alignment (FR-7)
# Red Team findings addressed: ATK-005 (state tampering), ATK-006 (fail-open),
#   ATK-007 (prompt injection via file path)
# Sprint-108 T4.4: Dual-mode (authoritative + heuristic)
# Sprint-108 T4.5: Path normalization
# =============================================================================

# Read tool input from stdin
input=$(cat 2>/dev/null) || input=""

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
RUN_DIR="${RUN_DIR:-$PROJECT_ROOT/.run}"
FEATURES_FILE="$RUN_DIR/platform-features.json"

# Evidence recorder: lead session only (no teammate role, no subagent agent_id), once, atomic.
if [[ -z "${LOA_TEAM_MEMBER:-}" && -d "$RUN_DIR" ]] \
    && jq -e '(.tool_input.active_skill // "") != "" and (.agent_id // "") == ""' <<<"$input" >/dev/null 2>&1 \
    && ! jq -e '.active_skill_seen_at' "$FEATURES_FILE" >/dev/null 2>&1; then
    _ig_base=$(jq -c 'select(type == "object")' "$FEATURES_FILE" 2>/dev/null | tail -n 1)
    _ig_tmp=$(mktemp "$RUN_DIR/.platform-features.XXXXXX" 2>/dev/null) && {
        jq -nc --argjson b "${_ig_base:-{\}}" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '$b + {active_skill_available: false, active_skill_seen_at: $ts, active_skill_source: "tool_input"}' > "$_ig_tmp" 2>/dev/null \
            && mv -f "$_ig_tmp" "$FEATURES_FILE" 2>/dev/null
        rm -f "$_ig_tmp" 2>/dev/null
    }
fi

# Extract file path from tool input (Write or Edit)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || file_path=""

# If we can't determine the file path, allow (can't evaluate)
if [[ -z "$file_path" ]]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Source compat-lib.sh for _date_to_epoch()
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)" || SCRIPT_DIR=""
COMPAT_LIB="${SCRIPT_DIR}/../../scripts/compat-lib.sh"
# shellcheck source=../../scripts/compat-lib.sh
source "$COMPAT_LIB" 2>/dev/null || true

# ---------------------------------------------------------------------------
# T4.5: Path normalization — resolve file_path relative to PROJECT_ROOT
# Prevents false positives from parent directory names
# (e.g., /home/user/src-projects/loa/grimoires/file.md should NOT match src/*)
# ---------------------------------------------------------------------------
normalized_path="$file_path"

# If file_path starts with PROJECT_ROOT, strip the prefix to get relative path
if [[ "$file_path" == "$PROJECT_ROOT/"* ]]; then
    normalized_path="${file_path#"$PROJECT_ROOT"/}"
elif [[ "$file_path" == /* ]]; then
    # Absolute path that doesn't start with PROJECT_ROOT — use as-is
    # but don't match against App Zone patterns (could be false positive)
    normalized_path="$file_path"
fi

# ---------------------------------------------------------------------------
# Zone check: Is this an App Zone write?
# App Zone: src/, lib/, app/ (relative paths only after normalization)
# ---------------------------------------------------------------------------
is_app_zone=false
case "$normalized_path" in
    src/*|lib/*|app/*)
        is_app_zone=true
        ;;
esac

# Only match */src/* etc. if path is relative (no leading /)
# This prevents /home/user/src-projects/loa/grimoires from matching
if [[ "$is_app_zone" == "false" && "$normalized_path" != /* ]]; then
    case "$normalized_path" in
        */src/*|*/lib/*|*/app/*)
            is_app_zone=true
            ;;
    esac
fi

# Non-App-Zone writes always allowed
if [[ "$is_app_zone" == "false" ]]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Mode: heuristic unless the operator opts in through .loa.config.yaml (cycle-126 D-4.4)
# ---------------------------------------------------------------------------
compliance_mode="heuristic"
if command -v yq &>/dev/null && [[ -f "$PROJECT_ROOT/.loa.config.yaml" ]]; then
    configured_mode=$(yq '.implement_gate.mode // ""' "$PROJECT_ROOT/.loa.config.yaml" 2>/dev/null) || configured_mode=""
    [[ "${configured_mode//\"/}" == "authoritative" ]] && compliance_mode="authoritative"
fi

# ---------------------------------------------------------------------------
# Authoritative mode: read active_skill from hook input
# ---------------------------------------------------------------------------
if [[ "$compliance_mode" == "authoritative" ]]; then
    active_skill=$(echo "$input" | jq -r '.tool_input.active_skill // empty' 2>/dev/null) || active_skill=""

    if [[ -n "$active_skill" ]]; then
        # Allow implementation skills
        case "$active_skill" in
            implement|/implement|bug|/bug|run|/run|simstim|/simstim)
                exit 0
                ;;
        esac

        # Non-implementation skill — ask
        echo "[AUTHORITATIVE] App Zone write to '$file_path' detected during /$active_skill (not an implementation skill)." >&2
        echo '{"decision":"ask","reason":"[AUTHORITATIVE] App Zone write outside implementation skill. Verify this is intentional."}'
        exit 0
    fi

    # active_skill field absent despite authoritative mode — fall back to heuristic
    # Log the downgrade
    log_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || log_ts="unknown"
    if command -v jq &>/dev/null; then
        jq -nc \
            --arg ts "$log_ts" \
            --arg from "authoritative" \
            --arg to "heuristic" \
            --arg reason "active_skill field absent in hook input" \
            '{timestamp: $ts, event: "compliance.mode.fallback", from_mode: $from, to_mode: $to, reason: $reason}' \
            >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
    else
        echo "{\"timestamp\":\"$log_ts\",\"event\":\"compliance.mode.fallback\",\"from_mode\":\"authoritative\",\"to_mode\":\"heuristic\",\"reason\":\"active_skill field absent in hook input\"}" \
            >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
    fi
    # Fall through to heuristic check below
fi

# ---------------------------------------------------------------------------
# Heuristic mode: Is an /implement or /bug skill currently active?
# Check .run/sprint-plan-state.json, .run/simstim-state.json, .run/state.json
# ---------------------------------------------------------------------------
check_implementation_active() {
    # Check sprint-plan state
    if [[ -f "$RUN_DIR/sprint-plan-state.json" ]]; then
        local state plan_id last_activity
        state=$(jq -r '.state // empty' "$RUN_DIR/sprint-plan-state.json" 2>/dev/null) || return 1
        plan_id=$(jq -r '.plan_id // empty' "$RUN_DIR/sprint-plan-state.json" 2>/dev/null) || true

        # Integrity: must have plan_id
        if [[ -z "$plan_id" ]]; then
            return 1
        fi

        # Integrity: check staleness (24h = 86400s)
        # Use _date_to_epoch from compat-lib.sh for portable conversion
        last_activity=$(jq -r '.timestamps.last_activity // empty' "$RUN_DIR/sprint-plan-state.json" 2>/dev/null) || true
        if [[ -n "$last_activity" ]]; then
            local now last_epoch
            now=$(date +%s 2>/dev/null) || now=0
            if type _date_to_epoch &>/dev/null; then
                last_epoch=$(_date_to_epoch "$last_activity" 2>/dev/null) || last_epoch=0
            else
                # Fallback if compat-lib not loaded: try GNU then macOS
                last_epoch=$(date -d "$last_activity" +%s 2>/dev/null ||
                             date -jf '%Y-%m-%dT%H:%M:%SZ' "$last_activity" +%s 2>/dev/null) || last_epoch=0
            fi
            if [[ $now -gt 0 && $last_epoch -gt 0 ]]; then
                local age=$((now - last_epoch))
                if [[ $age -gt 86400 ]]; then
                    return 1  # Stale state (>24h)
                fi
            fi
        fi

        if [[ "$state" == "RUNNING" ]]; then
            return 0
        fi
    fi

    # Check simstim state
    if [[ -f "$RUN_DIR/simstim-state.json" ]]; then
        local phase
        phase=$(jq -r '.phase // empty' "$RUN_DIR/simstim-state.json" 2>/dev/null) || return 1
        if [[ "$phase" == "implementation" ]]; then
            return 0
        fi
    fi

    # Check run state
    if [[ -f "$RUN_DIR/state.json" ]]; then
        local run_state
        run_state=$(jq -r '.state // empty' "$RUN_DIR/state.json" 2>/dev/null) || return 1
        if [[ "$run_state" == "RUNNING" ]]; then
            return 0
        fi
    fi

    return 1
}

# ---------------------------------------------------------------------------
# Decision: allow or ask
# ---------------------------------------------------------------------------
if check_implementation_active; then
    # Implementation is active — allow the write
    exit 0
else
    # No active implementation detected — ADVISORY ask
    echo "[ADVISORY] App Zone write to '$file_path' detected outside active /implement or /bug." >&2
    echo "No RUNNING state found in .run/ state files. This may bypass review gates." >&2
    echo '{"decision":"ask","reason":"[ADVISORY] App Zone write outside active implementation. Verify this is intentional."}'
    exit 0
fi
