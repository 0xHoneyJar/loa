#!/usr/bin/env bash
# example-dispatcher.sh — phase 2 (dispatcher)
#
# Apply the decided action(s). THIS is where state mutation happens. SHOULD be
# idempotent so a re-run of the same cycle_id is safe.
# Args: $1 cycle_id  $2 schedule_id  $3 phase_index  $4 prior_phases_json
# stdout: JSON describing the dispatch result (job ids, ack tokens, etc.).

set -euo pipefail

cycle_id="${1:?cycle_id required}"
schedule_id="${2:?schedule_id required}"

# Example: pretend we kicked off a job. Replace with real dispatch logic
# (write to a queue, invoke an API, fork a worker, …).
jq -nc \
    --arg cid "$cycle_id" \
    --arg sid "$schedule_id" \
    --arg job "stub-job-${cycle_id:0:8}" \
    '{cycle_id:$cid, schedule_id:$sid, dispatched:true, job_id:$job,
      note:"replace with real dispatch (queue / API / worker spawn)"}'
