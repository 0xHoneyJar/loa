#!/usr/bin/env bash
# =============================================================================
# post-session-limit-reminder.sh — one-shot resume reminder after a cap resets
# =============================================================================
# Part of: cycle-117 session-economy (bd-c117-a-session-cap-x04j, issue #1177 A).
#
# UserPromptSubmit hook, sibling to post-compact-reminder.sh but with a
# DELIBERATELY DIFFERENT firing discipline:
#
#   post-compact-reminder.sh fires UNCONDITIONALLY on the very next prompt and
#   deletes its marker regardless. This hook must stay SILENT across every
#   prompt while the session cap is still in effect (now < reset_at_epoch),
#   leaving .run/session-limit-state.json in place to be re-checked each prompt.
#   ONLY once now >= reset_at_epoch does it emit the resume reminder exactly
#   once (sprint id + state from the embedded snapshot) and delete the marker.
#
# Fail-open + silent on anything unexpected (absent/malformed/empty marker, no
# jq): a resume nudge that misfires is worse than one that is silently skipped.
#
# Security: the embedded sprint state is allowlist-validated (validate_state)
# and the free-text sprint id is run through sanitize_output (control-char strip
# + truncate) BEFORE it reaches stdout — the marker is agent-adjacent state and
# must not become a prompt-injection vector.
# =============================================================================

set -uo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"
MARKER="${PROJECT_ROOT}/.run/session-limit-state.json"

# No marker → no cap recorded, exit silently.
[[ -f "$MARKER" ]] || exit 0

# Allowed run-mode state values (mirrors post-compact-reminder.sh's allowlist).
VALID_RUN_MODE_STATES=("RUNNING" "HALTED" "JACKED_OUT" "unknown" "null" "false")

# Validate a value against an allowlist; return "unknown" for anything else.
validate_state() {
    local value="$1"; shift
    local valid
    for valid in "$@"; do
        [[ "$value" == "$valid" ]] && { printf '%s' "$value"; return 0; }
    done
    printf 'unknown'
}

# Sanitize free-text for safe output: strip control chars, truncate to 50 chars.
sanitize_output() {
    printf '%s' "$1" | tr -d '\n\r' | tr -cd '[:print:]' | head -c 50
}

# Read the marker (builtin, no cat spawn); fail-open to "{}" on a read race.
{ CONTENT=$(<"$MARKER"); } 2>/dev/null || CONTENT="{}"

# ONE jq extracts every field, NUL-delimited (post-compact-reminder.sh pattern).
mapfile -d '' -t _sl < <(
    printf '%s' "$CONTENT" | jq -sj '
        def r: if type == "string" then . else tojson end;
        ([0] | implode) as $z |
        def scap: . / ([0] | implode) | join("") | sub("\n+$"; "");
        def fld(g; $d): (try (map(g | r) | join("\n") | scap) catch $d);
        fld(.reset_at_epoch // 0; "0") + $z +
        fld(.reset_at // "unknown"; "unknown") + $z +
        fld(.active_run_state_snapshot.sprint_plan.state // "unknown"; "unknown") + $z +
        fld(.active_run_state_snapshot.sprint_plan.current // "null"; "null") + $z
    ' 2>/dev/null
)
if [[ "${#_sl[@]}" -ne 4 ]]; then
    # Malformed marker → fail-open silent (leave the marker for manual cleanup).
    exit 0
fi
reset_epoch_raw="${_sl[0]}"
reset_iso="${_sl[1]}"
sp_state_raw="${_sl[2]}"
sp_current_raw="${_sl[3]}"

# A missing/zero/non-numeric epoch is a malformed marker → fail-open silent.
[[ "$reset_epoch_raw" =~ ^[0-9]+$ ]] && [[ "$reset_epoch_raw" -gt 0 ]] || exit 0

# Not yet reached → silent, marker RETAINED for re-check on the next prompt.
now=$(date +%s)
[[ "$now" -ge "$reset_epoch_raw" ]] || exit 0

# Reached: validate the enum state, sanitize the free-text sprint id.
sp_state=$(validate_state "$sp_state_raw" "${VALID_RUN_MODE_STATES[@]}")
sp_current=$(sanitize_output "$sp_current_raw")
[[ -n "$sp_current" ]] || sp_current="null"

# reset_iso is also marker-sourced free text (cycle-117 audit HIGH): allowlist
# it against a strict ISO-8601 shape — the only legitimate producer
# (session-limit-capture.sh) always writes date +%:z output, so anything else
# is a corrupted/hostile marker and renders as 'unknown', never verbatim.
if [[ ! "$reset_iso" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([+-][0-9]{2}:?[0-9]{2}|Z)$ ]]; then
  reset_iso="unknown"
fi

# Emit the one-shot resume reminder (injected into context).
IFS= read -rd '' _blk <<REMINDER || true

════════════════════════════════════════════════════════════════════
 ⏳ SESSION LIMIT RESET — RESUME CHECK
════════════════════════════════════════════════════════════════════

A Claude session/usage cap was recorded and its reset time (${reset_iso})
has now passed. Run state captured at cap time:

  sprint-plan: state=${sp_state}, sprint=${sp_current}

Before responding to the user:
1. Re-read CLAUDE.md for conventions.
2. Check .run/sprint-plan-state.json — if state=RUNNING, resume the sprint
   AUTONOMOUSLY without asking; if HALTED, report the halt and await /run-resume.
3. Check .run/bridge-state.json / .run/simstim-state.json and resume if active.
4. Review grimoires/loa/NOTES.md for in-flight context.

════════════════════════════════════════════════════════════════════

REMINDER
printf '%s' "$_blk"

# Delete AFTER output (prevents a lost reminder on interrupt — post-compact M7).
rm -f "$MARKER" 2>/dev/null || true

exit 0
