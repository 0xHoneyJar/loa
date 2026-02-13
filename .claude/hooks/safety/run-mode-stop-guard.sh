#!/usr/bin/env bash
# =============================================================================
# Stop Hook — Run Mode Guard
# =============================================================================
# Detects active autonomous runs and injects context reminder before stopping.
# Uses stdout JSON decision field (soft block, not hard block).
#
# Checks:
#   1. .run/sprint-plan-state.json — state=RUNNING
#   2. .run/bridge-state.json — state=ITERATING or FINALIZING
#
# Registered in settings.hooks.json as Stop matcher: ""
# Part of Loa Harness Engineering (cycle-011, issue #297)
# Source: Trail of Bits Stop hook pattern
# =============================================================================

# Note: No set -euo pipefail — this hook must never cause a hard failure.
# Missing files and parse errors should result in exit 0 (allow stop).

# ---------------------------------------------------------------------------
# Check sprint-plan state
# ---------------------------------------------------------------------------
SPRINT_STATE_FILE=".run/sprint-plan-state.json"

if [[ -f "$SPRINT_STATE_FILE" ]]; then
  state=$(jq -r '.state // "UNKNOWN"' "$SPRINT_STATE_FILE" 2>/dev/null || echo "UNKNOWN")
  current=$(jq -r '.sprints.current // "null"' "$SPRINT_STATE_FILE" 2>/dev/null || echo "null")

  if [[ "$state" == "RUNNING" && "$current" != "null" ]]; then
    cat <<EOF
{"decision": "block", "reason": "Run mode is active (state=RUNNING, sprint=${current}). Verify all acceptance criteria are met before stopping. Check .run/sprint-plan-state.json for sprint status."}
EOF
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Check bridge state
# ---------------------------------------------------------------------------
BRIDGE_STATE_FILE=".run/bridge-state.json"

if [[ -f "$BRIDGE_STATE_FILE" ]]; then
  bridge_state=$(jq -r '.state // "UNKNOWN"' "$BRIDGE_STATE_FILE" 2>/dev/null || echo "UNKNOWN")
  iteration=$(jq -r '.current_iteration // 0' "$BRIDGE_STATE_FILE" 2>/dev/null || echo "0")

  if [[ "$bridge_state" == "ITERATING" || "$bridge_state" == "FINALIZING" ]]; then
    cat <<EOF
{"decision": "block", "reason": "Bridge mode is active (state=${bridge_state}, iteration=${iteration}). Complete the current bridge iteration before stopping. Check .run/bridge-state.json for bridge status."}
EOF
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Check simstim state
# ---------------------------------------------------------------------------
SIMSTIM_STATE_FILE=".run/simstim-state.json"

if [[ -f "$SIMSTIM_STATE_FILE" ]]; then
  simstim_state=$(jq -r '.state // "UNKNOWN"' "$SIMSTIM_STATE_FILE" 2>/dev/null || echo "UNKNOWN")
  phase=$(jq -r '.phase // "unknown"' "$SIMSTIM_STATE_FILE" 2>/dev/null || echo "unknown")

  if [[ "$simstim_state" == "RUNNING" && "$phase" == "implementation" ]]; then
    cat <<EOF
{"decision": "block", "reason": "Simstim implementation phase is active (state=RUNNING, phase=${phase}). Complete or halt the current simstim workflow before stopping."}
EOF
    exit 0
  fi
fi

# No active runs — allow stop
exit 0
