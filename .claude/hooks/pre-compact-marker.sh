#!/usr/bin/env bash
# pre-compact-marker.sh - Write marker with context for post-compact recovery
#
# This hook runs before context compaction and creates a marker file
# that the post-compact-reminder hook will detect to inject recovery
# instructions into Claude's context.
#
# Usage: Called automatically via Claude Code hooks
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

# Detect active run mode
run_mode_active="false"
run_mode_state=""
if [[ -f "${PROJECT_ROOT}/.run/sprint-plan-state.json" ]]; then
    run_mode_active="true"
    run_mode_state=$(jq -r '.state // "unknown"' "${PROJECT_ROOT}/.run/sprint-plan-state.json" 2>/dev/null) || run_mode_state="unknown"
fi

# Detect active simstim
simstim_active="false"
simstim_phase=""
if [[ -f "${PROJECT_ROOT}/.run/simstim-state.json" ]]; then
    simstim_active="true"
    simstim_phase=$(jq -r '.phase // "unknown"' "${PROJECT_ROOT}/.run/simstim-state.json" 2>/dev/null) || simstim_phase="unknown"
fi

# Capture current context
CONTEXT=$(cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project_root": "$PROJECT_ROOT",
  "run_mode": {
    "active": $run_mode_active,
    "state": "$run_mode_state"
  },
  "simstim": {
    "active": $simstim_active,
    "phase": "$simstim_phase"
  },
  "current_skill": "${LOA_CURRENT_SKILL:-unknown}",
  "current_phase": "${LOA_CURRENT_PHASE:-unknown}",
  "current_task": "${LOA_CURRENT_TASK:-unknown}"
}
EOF
)

# Write markers (both locations for reliability)
echo "$CONTEXT" > "$GLOBAL_MARKER" 2>/dev/null || true
echo "$CONTEXT" > "$PROJECT_MARKER" 2>/dev/null || true

# Always exit 0 - never block compaction
exit 0
