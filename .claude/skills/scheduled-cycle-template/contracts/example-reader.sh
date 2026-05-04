#!/usr/bin/env bash
# example-reader.sh — phase 0 (reader)
#
# Read state to inform downstream decisions. SHOULD be side-effect-free.
# Args: $1 cycle_id  $2 schedule_id  $3 phase_index  $4 prior_phases_json
# stdout: arbitrary JSON describing observed state.

set -euo pipefail

cycle_id="${1:?cycle_id required}"
schedule_id="${2:?schedule_id required}"

# Example: report what would be cleaned up. Replace with your own read logic.
jq -nc \
    --arg cid "$cycle_id" \
    --arg sid "$schedule_id" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{cycle_id:$cid, schedule_id:$sid, observed_at:$ts,
      candidates:[], note:"replace with real reader logic"}'
