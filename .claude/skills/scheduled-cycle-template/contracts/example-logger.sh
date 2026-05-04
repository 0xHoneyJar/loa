#!/usr/bin/env bash
# example-logger.sh — phase 4 (logger)
#
# Record the cycle outcome to a domain-specific destination. The L3 lib also
# writes a cycle.complete event to .run/cycles.jsonl when this phase exits 0;
# this script is for downstream / ops-facing logs (e.g., NOTES.md, dashboards).
# Args: $1 cycle_id  $2 schedule_id  $3 phase_index  $4 prior_phases_json
# stdout: JSON with the operator-facing summary.

set -euo pipefail

cycle_id="${1:?cycle_id required}"
schedule_id="${2:?schedule_id required}"
prior="${4:-[]}"

# Walk prior phase records to summarize.
total_phases="$(printf '%s' "$prior" | jq -r 'length')"

jq -nc \
    --arg cid "$cycle_id" \
    --arg sid "$schedule_id" \
    --argjson total "$total_phases" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{cycle_id:$cid, schedule_id:$sid, summary:"cycle complete",
      phases_observed:$total, logged_at:$ts,
      note:"replace with NOTES.md append, dashboard push, alert, etc."}'
