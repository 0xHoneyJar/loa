#!/usr/bin/env bash
# bridge-flatline-check.sh — Standalone flatline detection for bridge iterations
# Version: 1.0.0
#
# Reads .run/bridge-state.json and evaluates convergence.
# Extracted from bridge-state.sh:is_flatlined() for standalone use.
#
# Exit: 0 = flatlined (should stop), 1 = not flatlined (continue)
# Stdout: JSON summary
#
# Usage:
#   bridge-flatline-check.sh [threshold]
#   bridge-flatline-check.sh          # default threshold: 0.05
#   bridge-flatline-check.sh 0.10     # custom: 10% threshold

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

BRIDGE_STATE="${PROJECT_ROOT}/.run/bridge-state.json"
THRESHOLD="${1:-0.05}"

main() {
  if [[ ! -f "$BRIDGE_STATE" ]]; then
    echo '{"flatlined": false, "reason": "no state file"}'
    exit 1
  fi

  local initial_score last_score consecutive flatline_detected reason
  initial_score=$(jq -r '.flatline.initial_score // 0' "$BRIDGE_STATE")
  last_score=$(jq -r '.flatline.last_score // 0' "$BRIDGE_STATE")
  consecutive=$(jq -r '.flatline.consecutive_below_threshold // 0' "$BRIDGE_STATE")
  flatline_detected=$(jq -r '.flatline.flatline_detected // false' "$BRIDGE_STATE")
  reason=$(jq -r '.flatline.reason // "none"' "$BRIDGE_STATE")

  # Build summary JSON
  jq -n \
    --argjson flatlined "$flatline_detected" \
    --argjson initial "$initial_score" \
    --argjson last "$last_score" \
    --argjson consecutive "$consecutive" \
    --arg reason "$reason" \
    --argjson threshold "$THRESHOLD" \
    '{
      flatlined: $flatlined,
      initial_score: $initial,
      last_score: $last,
      consecutive_below_threshold: $consecutive,
      threshold: $threshold,
      reason: $reason
    }'

  if [[ "$flatline_detected" == "true" ]]; then
    exit 0
  else
    exit 1
  fi
}

main "$@"
