#!/usr/bin/env bash
# example-decider.sh — phase 1 (decider)
#
# Decide what (if anything) the dispatcher should do. SHOULD be side-effect-free.
# Args: $1 cycle_id  $2 schedule_id  $3 phase_index  $4 prior_phases_json
# stdout: JSON describing the planned action(s) for the dispatcher.

set -euo pipefail

cycle_id="${1:?cycle_id required}"
schedule_id="${2:?schedule_id required}"
prior="${4:-[]}"

# Walk prior phase records (just the reader at this point) to extract state.
reader_hash="$(printf '%s' "$prior" | jq -r '.[] | select(.phase=="reader") | .output_hash // ""')"

jq -nc \
    --arg cid "$cycle_id" \
    --arg sid "$schedule_id" \
    --arg rh "$reader_hash" \
    '{cycle_id:$cid, schedule_id:$sid, action:"noop",
      reader_output_hash:$rh, note:"replace with real decider logic"}'
