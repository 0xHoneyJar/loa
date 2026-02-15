#!/usr/bin/env bash
# bridge-state.sh — Eval fixture stub
# Manages bridge loop state in .run/bridge-state.json.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
BRIDGE_STATE_FILE="${PROJECT_ROOT}/.run/bridge-state.json"

# Initialize bridge state for a new bridge loop
init_bridge_state() {
    local bridge_id="$1"
    local depth="${2:-3}"
    local mode="${3:-full}"

    mkdir -p "$(dirname "$BRIDGE_STATE_FILE")"
    cat > "$BRIDGE_STATE_FILE" << EOF
{
  "schema_version": 1,
  "bridge_id": "$bridge_id",
  "state": "PREFLIGHT",
  "config": {
    "depth": $depth,
    "mode": "$mode"
  },
  "iterations": [],
  "flatline": {
    "initial_score": null,
    "last_score": null,
    "consecutive_below_threshold": 0,
    "flatline_detected": false
  }
}
EOF
}

# Update bridge state
update_bridge_state() {
    local new_state="$1"
    if [[ -f "$BRIDGE_STATE_FILE" ]] && command -v jq &>/dev/null; then
        jq --arg s "$new_state" '.state = $s' "$BRIDGE_STATE_FILE" > "$BRIDGE_STATE_FILE.tmp"
        mv "$BRIDGE_STATE_FILE.tmp" "$BRIDGE_STATE_FILE"
    fi
}
