#!/usr/bin/env bash
# session-cap-bb decider.sh — phase 1 (decider) for the post-reset bridgebuilder
# fan-out (bd-fanout-real-dispatch-9jv6 Tranche 1).
#
# FAIL-CLOSED: emits action:dispatch ONLY when the captured snapshot shows a
# sprint_plan or bridge state in {RUNNING, HALTED} (i.e. something was
# demonstrably interrupted at cap time); every other case — snapshot absent,
# unreadable, or in a terminal/idle state — is action:noop. Side-effect-free
# apart from writing its own handoff file.
#
# Args: $1 cycle_id  $2 schedule_id  $3 phase_index  $4 prior_phases_json
set -euo pipefail

cycle_id="${1:?cycle_id required}"
schedule_id="${2:?schedule_id required}"

_sanitize() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }
HANDOFF_DIR="${TMPDIR:-/tmp}/loa-session-cap-bb.$(_sanitize "$cycle_id")"
mkdir -p "$HANDOFF_DIR"
READER_FILE="${HANDOFF_DIR}/reader.json"

sp_state=""
br_state=""
if [[ -f "$READER_FILE" ]] && jq empty "$READER_FILE" 2>/dev/null; then
    sp_state="$(jq -r '.sprint_plan_state // ""' "$READER_FILE")"
    br_state="$(jq -r '.bridge_state // ""' "$READER_FILE")"
fi

action="noop"
case "$sp_state" in RUNNING|HALTED) action="dispatch" ;; esac
case "$br_state" in RUNNING|HALTED) action="dispatch" ;; esac

jq -nc --arg cid "$cycle_id" --arg sid "$schedule_id" --arg act "$action" \
    --arg sp "$sp_state" --arg br "$br_state" \
    '{cycle_id:$cid, schedule_id:$sid, action:$act,
      sprint_plan_state:$sp, bridge_state:$br}' \
    | tee "${HANDOFF_DIR}/decider.json"
