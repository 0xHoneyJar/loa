#!/usr/bin/env bash
# session-cap-bb awaiter.sh — phase 3 (awaiter) for the post-reset bridgebuilder
# fan-out (bd-fanout-real-dispatch-9jv6 Tranche 1).
#
# Pass-through: the dispatcher ran bridgebuilder-review synchronously to
# completion under its own L3 phase timeout, so there is no async job to poll.
# Reports the dispatcher's terminal result.
#
# Args: $1 cycle_id  $2 schedule_id  $3 phase_index  $4 prior_phases_json
set -euo pipefail

cycle_id="${1:?cycle_id required}"
schedule_id="${2:?schedule_id required}"

_sanitize() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }
HANDOFF_DIR="${TMPDIR:-/tmp}/loa-session-cap-bb.$(_sanitize "$cycle_id")"
DISPATCHER_FILE="${HANDOFF_DIR}/dispatcher.json"

dispatched="false"
bb_ec="null"
if [[ -f "$DISPATCHER_FILE" ]] && jq empty "$DISPATCHER_FILE" 2>/dev/null; then
    dispatched="$(jq -r '.dispatched // false' "$DISPATCHER_FILE")"
    bb_ec="$(jq -r '.bb_exit_code // "null"' "$DISPATCHER_FILE")"
fi

jq -nc --arg cid "$cycle_id" --arg sid "$schedule_id" \
    --arg d "$dispatched" --arg ec "$bb_ec" \
    '{cycle_id:$cid, schedule_id:$sid,
      terminal_state:(if $d=="true" then "completed" else "skipped" end),
      dispatched:($d=="true"), bb_exit_code:$ec,
      note:"synchronous dispatch; no async job to await"}'
