#!/usr/bin/env bash
# pre-compact-marker.sh - Write marker with context for post-compact recovery
#
# This hook runs before context compaction and creates a marker file
# that the post-compact-reminder hook will detect to inject recovery
# instructions into Claude's context.
#
# Usage: Called automatically via Claude Code hooks
#
# Liveness (cycle-133 C-4(c)): a run-mode or simstim state file counts only by
# its `.state` and `timestamps.last_activity`: RUNNING → active; HALTED,
# INTERRUPTED (simstim also AWAITING_HITL) → awaiting_resume; COMPLETED,
# JACKED_OUT, any other state, an absent or unreadable file, or a
# last_activity older than LOA_HOOK_LIVE_WINDOW_DAYS (default 7; an
# unparseable timestamp counts as old) → silent. A file without
# timestamps.last_activity is not age-gated. A legacy simstim file without
# `.state` falls back to its `.phase` (live unless terminal). The marker
# carries `liveness` per workflow; `active` is true unless silent.
#
# Exit code is always 0 to never block compaction

set -uo pipefail

# Global marker location (fallback)
MARKER_DIR="${HOME}/.local/state/loa-compact"
GLOBAL_MARKER="${MARKER_DIR}/compact-pending"

# Project-local marker (preferred)
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
PROJECT_MARKER="${PROJECT_ROOT}/.run/compact-pending"

# Ensure directories exist
mkdir -p "$MARKER_DIR" 2>/dev/null || true
mkdir -p "$(dirname "$PROJECT_MARKER")" 2>/dev/null || true

LIVE_WINDOW_DAYS="${LOA_HOOK_LIVE_WINDOW_DAYS:-7}"
[[ "$LIVE_WINDOW_DAYS" =~ ^[0-9]+$ ]] || LIVE_WINDOW_DAYS=7

# 0 when the ISO-8601 UTC timestamp $1 is within the window (or absent).
_pcm_recent() {
    [[ -n "$1" ]] || return 0
    local t now
    t=$(date -u -d "$1" +%s 2>/dev/null) \
        || t=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null) \
        || return 1
    now=$(date -u +%s)
    (( now - t <= LIVE_WINDOW_DAYS * 86400 ))
}

# Read a state file: sets _pcm_state, _pcm_phase, _pcm_last; 1 if unreadable.
_pcm_read() {
    _pcm_state="" _pcm_phase="" _pcm_last=""
    [[ -f "$1" ]] || return 1
    local fields
    if ! fields=$(jq -r 'if type == "object" then [(.state // "" | tostring), (.phase // "" | tostring), (.timestamps.last_activity // "" | tostring)] | map(gsub("[\u0000-\u001f]"; " ")) | join("\u001f") else error("not an object") end' "$1" 2>/dev/null); then
        return 1
    fi
    # US (0x1f) is not IFS whitespace: an empty field stays empty
    IFS=$'\x1f' read -r _pcm_state _pcm_phase _pcm_last <<<"$fields"
    return 0
}

# $1 = workflow (run|simstim); uses _pcm_* → prints active|awaiting_resume|silent
_pcm_liveness() {
    local s="${_pcm_state^^}" l="silent"
    case "$s" in
        RUNNING) l="active" ;;
        HALTED|INTERRUPTED) l="awaiting_resume" ;;
        AWAITING_HITL) [[ "$1" == "simstim" ]] && l="awaiting_resume" ;;
    esac
    if [[ "$l" != "silent" ]] && ! _pcm_recent "$_pcm_last"; then l="silent"; fi
    printf '%s' "$l"
}

# Detect active run mode
run_mode_active="false"
run_mode_state=""
run_mode_liveness="silent"
if _pcm_read "${PROJECT_ROOT}/.run/sprint-plan-state.json"; then
    run_mode_state="${_pcm_state:-unknown}"
    run_mode_liveness=$(_pcm_liveness run)
elif [[ -f "${PROJECT_ROOT}/.run/sprint-plan-state.json" ]]; then
    run_mode_state="unknown"
fi
[[ "$run_mode_liveness" == "silent" ]] || run_mode_active="true"

# Detect active simstim
simstim_active="false"
simstim_phase=""
simstim_state=""
simstim_liveness="silent"
if _pcm_read "${PROJECT_ROOT}/.run/simstim-state.json"; then
    simstim_phase="${_pcm_phase:-unknown}"
    simstim_state="${_pcm_state}"
    if [[ -n "$_pcm_state" ]]; then
        simstim_liveness=$(_pcm_liveness simstim)
    else
        # legacy file without .state: live unless its phase is terminal (cycle-122 rule)
        case "${_pcm_phase,,}" in
            ""|unknown|completed|complete|awaiting_hitl|halted|jacked_out) : ;;
            *) _pcm_recent "$_pcm_last" && simstim_liveness="active" ;;
        esac
    fi
elif [[ -f "${PROJECT_ROOT}/.run/simstim-state.json" ]]; then
    simstim_phase="unknown"
fi
[[ "$simstim_liveness" == "silent" ]] || simstim_active="true"

# Detect active bridge
bridge_active="false"
bridge_state=""
if [[ -f "${PROJECT_ROOT}/.run/bridge-state.json" ]]; then
    bridge_active="true"
    bridge_state=$(jq -r '.state // "unknown"' "${PROJECT_ROOT}/.run/bridge-state.json" 2>/dev/null) || bridge_state="unknown"
fi

# cycle-122: derive the ACTIVE skill doc so post-compact recovery re-reads the
# skill contract that was mid-flight (point-of-use constraints survive
# compaction; CLAUDE.md alone was the only re-read before).
# Terminal sets mirror run-mode-stop-guard's gates (case-folded): a state is
# ACTIVE iff it is non-empty and not terminal. Bridge/simstim intermediate
# phases (PREFLIGHT, JACK_IN, iterating, etc.) all count as active.
_pcm_is_active() {  # $1=value  $2=space-separated terminal set (lowercase)
    local v="${1,,}" t
    [[ -n "$v" && "$v" != "unknown" ]] || return 1
    for t in $2; do [[ "$v" == "$t" ]] && return 1; done
    return 0
}
active_skill_doc=""
# cycle-133: simstim and run mode count only when their liveness is "active".
if [[ "$simstim_liveness" == "active" ]]; then
    active_skill_doc=".claude/skills/simstim-workflow/SKILL.md"
elif [[ "$bridge_active" == "true" ]] && _pcm_is_active "$bridge_state" "jacked_out halted complete completed"; then
    active_skill_doc=".claude/skills/run-bridge/SKILL.md"
elif [[ "$run_mode_liveness" == "active" ]]; then
    active_skill_doc=".claude/skills/run-mode/SKILL.md"
fi

# CI-013: Use jq for safe JSON construction instead of unquoted heredoc
CONTEXT=$(jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg project_root "$PROJECT_ROOT" \
  --argjson run_active "$run_mode_active" \
  --arg run_state "$run_mode_state" \
  --arg run_liveness "$run_mode_liveness" \
  --argjson sim_active "$simstim_active" \
  --arg sim_phase "$simstim_phase" \
  --arg sim_state "$simstim_state" \
  --arg sim_liveness "$simstim_liveness" \
  --argjson bridge_active "$bridge_active" \
  --arg bridge_state "$bridge_state" \
  --arg active_skill_doc "$active_skill_doc" \
  --arg skill "${LOA_CURRENT_SKILL:-unknown}" \
  --arg phase "${LOA_CURRENT_PHASE:-unknown}" \
  --arg task "${LOA_CURRENT_TASK:-unknown}" \
  '{
    timestamp: $ts,
    project_root: $project_root,
    run_mode: { active: $run_active, state: $run_state, liveness: $run_liveness },
    simstim: { active: $sim_active, phase: $sim_phase, state: $sim_state, liveness: $sim_liveness },
    bridge: { active: $bridge_active, state: $bridge_state },
    active_skill_doc: $active_skill_doc,
    current_skill: $skill,
    current_phase: $phase,
    current_task: $task
  }' 2>/dev/null) || CONTEXT="{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"error\":\"jq_unavailable\"}"

# Write markers (both locations for reliability)
echo "$CONTEXT" > "$GLOBAL_MARKER" 2>/dev/null || true
echo "$CONTEXT" > "$PROJECT_MARKER" 2>/dev/null || true

# Always exit 0 - never block compaction
exit 0
