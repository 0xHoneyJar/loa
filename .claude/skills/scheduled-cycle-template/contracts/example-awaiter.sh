#!/usr/bin/env bash
# example-awaiter.sh — phase 3 (awaiter)
#
# Wait for the dispatched work to complete. Block until terminal, with phase
# timeout providing the upper bound. SHOULD be idempotent if the cycle reruns.
# Args: $1 cycle_id  $2 schedule_id  $3 phase_index  $4 prior_phases_json
# stdout: JSON describing terminal state (succeeded, failed, partial).

set -euo pipefail

cycle_id="${1:?cycle_id required}"
schedule_id="${2:?schedule_id required}"
prior="${4:-[]}"

# Walk prior phase records to extract the dispatched job_id.
job_id="$(printf '%s' "$prior" | jq -r '.[] | select(.phase=="dispatcher") | .output_hash // "unknown"' | head -1)"

# Example: pretend we waited and the job succeeded. Replace with a real
# poll loop or blocking wait.
jq -nc \
    --arg cid "$cycle_id" \
    --arg sid "$schedule_id" \
    --arg jid "$job_id" \
    '{cycle_id:$cid, schedule_id:$sid, terminal_state:"succeeded",
      dispatcher_output_hash:$jid,
      note:"replace with poll/wait loop bounded by timeout_seconds"}'
