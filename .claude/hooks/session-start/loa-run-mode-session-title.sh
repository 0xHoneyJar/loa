#!/usr/bin/env bash
# =============================================================================
# loa-run-mode-session-title.sh — SessionStart hook (cycle-114 FR-9).
#
# When a session starts (or resumes) with an active autonomous run, set the
# session title to reflect that state so an operator returning after a
# compaction / new session immediately sees what to resume. Uses the
# Claude Code 2.1.152 `hookSpecificOutput.sessionTitle` return.
#
# Active states surfaced:
#   .run/sprint-plan-state.json — state RUNNING|HALTED
#   .run/bridge-state.json      — state ITERATING|FINALIZING|HALTED
#   .run/simstim-state.json     — state RUNNING
#
# Silent (exit 0, no stdout) when no run is active or state is
# JACKED_OUT/COMPLETED/absent. Fail-open: malformed JSON or missing jq → exit 0.
# =============================================================================

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HOOK_DIR}/../../.." && pwd)"
RUN_DIR="${REPO_ROOT}/.run"

# Fail-open if jq is unavailable — never break session start.
command -v jq >/dev/null 2>&1 || exit 0

_emit() {
    # $1 = sessionTitle string
    jq -cn --arg t "$1" '{hookSpecificOutput: {hookEventName: "SessionStart", sessionTitle: $t}}'
    exit 0
}

# --- sprint-plan ---
sp="${RUN_DIR}/sprint-plan-state.json"
if [[ -f "$sp" ]]; then
    state="$(jq -r '.state // ""' "$sp" 2>/dev/null || echo "")"
    if [[ "$state" == "RUNNING" || "$state" == "HALTED" ]]; then
        cur="$(jq -r '.sprints.current // "?"' "$sp" 2>/dev/null || echo "?")"
        _emit "LOA: [sprint-plan ${state}] resume ${cur}"
    fi
fi

# --- bridge ---
br="${RUN_DIR}/bridge-state.json"
if [[ -f "$br" ]]; then
    state="$(jq -r '.state // ""' "$br" 2>/dev/null || echo "")"
    if [[ "$state" == "ITERATING" || "$state" == "FINALIZING" || "$state" == "HALTED" ]]; then
        it="$(jq -r '.current_iteration // .iterations[-1].iteration // "?"' "$br" 2>/dev/null || echo "?")"
        _emit "LOA: [bridge ${state}] iteration ${it}"
    fi
fi

# --- simstim ---
ss="${RUN_DIR}/simstim-state.json"
if [[ -f "$ss" ]]; then
    state="$(jq -r '.state // ""' "$ss" 2>/dev/null || echo "")"
    if [[ "$state" == "RUNNING" ]]; then
        phase="$(jq -r '.phase // "?"' "$ss" 2>/dev/null || echo "?")"
        _emit "LOA: [simstim RUNNING] phase ${phase}"
    fi
fi

# No active run — silent.
exit 0
