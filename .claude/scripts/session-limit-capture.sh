#!/usr/bin/env bash
# =============================================================================
# session-limit-capture.sh — snapshot a session/usage cap + live run state
# =============================================================================
# Part of: cycle-117 session-economy (bd-c117-a-session-cap-x04j, issue #1177 A).
#
# Usage: session-limit-capture.sh --raw '<full error text>'
#
# Given a Claude session-limit / usage-cap error string, parse its reset time
# and write .run/session-limit-state.json: hit_at (now, UTC), reset_at (ISO +
# offset), reset_at_epoch (plain unix epoch, for jq-side comparison), and an
# EMBEDDED scalar snapshot of the live run/bridge/simstim state (never bare path
# references — the snapshot must survive the referenced files being mutated or
# deleted by a later run before the resume reminder fires).
#
# The post-session-limit-reminder.sh UserPromptSubmit hook later detects this
# marker and, once now >= reset_at_epoch, injects a one-shot resume reminder.
#
# Exit 1 (with a message on stderr) when --raw is not a recognized cap string
# or its reset time cannot be parsed (e.g. GNU-date-only ceiling on macOS).
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/session-limit-lib.sh"

RAW=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --raw) RAW="${2:-}"; shift 2 ;;
        --raw=*) RAW="${1#--raw=}"; shift ;;
        *) shift ;;
    esac
done

if [[ -z "$RAW" ]]; then
    echo "session-limit-capture: --raw '<error text>' is required" >&2
    exit 1
fi

if ! session_limit_matches "$RAW"; then
    echo "session-limit-capture: input is not a recognized session-limit string; nothing captured" >&2
    exit 1
fi

RESET_ISO="$(session_limit_parse_reset "$RAW")" || {
    echo "session-limit-capture: could not parse reset time (GNU-date-only; see session-limit-lib.sh)" >&2
    exit 1
}
RESET_EPOCH="$(session_limit_parse_reset_epoch "$RAW")" || {
    echo "session-limit-capture: could not parse reset epoch" >&2
    exit 1
}
if [[ ! "$RESET_EPOCH" =~ ^[0-9]+$ ]]; then
    echo "session-limit-capture: parsed reset epoch is not numeric" >&2
    exit 1
fi

HIT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"
RUN_DIR="$PROJECT_ROOT/.run"
mkdir -p "$RUN_DIR" 2>/dev/null || true
STATE_FILE="$RUN_DIR/session-limit-state.json"

SPRINT_FILE="$RUN_DIR/sprint-plan-state.json"
BRIDGE_FILE="$RUN_DIR/bridge-state.json"
SIMSTIM_FILE="$RUN_DIR/simstim-state.json"

# Extract a scalar from a state file, falling back to a default when the file
# is absent, jq is missing, or the field is null. Embeds the VALUE, not a path.
_snap() {
    local file="$1" query="$2" default="$3" val
    if [[ -f "$file" ]]; then
        val="$(jq -r "$query // \"$default\"" "$file" 2>/dev/null)" || val="$default"
        [[ -n "$val" ]] || val="$default"
        printf '%s' "$val"
    else
        printf '%s' "$default"
    fi
}

sp_state="$(_snap "$SPRINT_FILE" '.state' 'unknown')"
sp_current="$(_snap "$SPRINT_FILE" '.sprints.current' 'null')"
sp_cycle="$(_snap "$SPRINT_FILE" '.cycle' 'null')"
sp_plan="$(_snap "$SPRINT_FILE" '.plan_id' 'null')"
br_state="$(_snap "$BRIDGE_FILE" '.state' 'unknown')"
br_iter="$(_snap "$BRIDGE_FILE" '.current_iteration' '0')"
ss_state="$(_snap "$SIMSTIM_FILE" '.state' 'unknown')"
ss_phase="$(_snap "$SIMSTIM_FILE" '.phase' 'unknown')"

# Truncate the raw string for provenance (bounded — the error text is short).
RAW_TRUNC="${RAW:0:400}"

SNAP="$(jq -n \
    --arg hit_at "$HIT_AT" \
    --arg reset_at "$RESET_ISO" \
    --argjson reset_at_epoch "$RESET_EPOCH" \
    --arg raw "$RAW_TRUNC" \
    --arg sp_state "$sp_state" \
    --arg sp_current "$sp_current" \
    --arg sp_cycle "$sp_cycle" \
    --arg sp_plan "$sp_plan" \
    --arg br_state "$br_state" \
    --arg br_iter "$br_iter" \
    --arg ss_state "$ss_state" \
    --arg ss_phase "$ss_phase" \
    '{
        hit_at: $hit_at,
        reset_at: $reset_at,
        reset_at_epoch: $reset_at_epoch,
        raw: $raw,
        active_run_state_snapshot: {
            sprint_plan: { state: $sp_state, current: $sp_current, cycle: $sp_cycle, plan_id: $sp_plan },
            bridge: { state: $br_state, current_iteration: $br_iter },
            simstim: { state: $ss_state, phase: $ss_phase }
        }
    }' 2>/dev/null)" || {
    echo "session-limit-capture: failed to build snapshot JSON (jq unavailable?)" >&2
    exit 1
}

# Atomic write: sibling .tmp in the SAME directory (guaranteed same filesystem),
# then mv. Never mktemp-in-/tmp + mv (that is copy+unlink across EXDEV, not
# atomic). Mirrors the state-JSON write idiom used elsewhere in this repo.
TMP="${STATE_FILE}.tmp.$$"
if printf '%s\n' "$SNAP" > "$TMP" 2>/dev/null && mv -f "$TMP" "$STATE_FILE" 2>/dev/null; then
    echo "session-limit-capture: wrote $STATE_FILE (reset_at=$RESET_ISO)" >&2
    exit 0
else
    rm -f "$TMP" 2>/dev/null || true
    echo "session-limit-capture: failed to write $STATE_FILE" >&2
    exit 1
fi
