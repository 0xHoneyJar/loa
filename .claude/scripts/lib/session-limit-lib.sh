#!/usr/bin/env bash
# =============================================================================
# session-limit-lib.sh — parse the Claude session/usage-cap error strings
# =============================================================================
# Part of: cycle-117 session-economy (bd-c117-a-session-cap-x04j, issue #1177 A).
#
# Sourceable, no side effects. Provides:
#   session_limit_matches <raw>                     -> 0 iff raw is a cap string
#                                                      with a parseable reset clause
#   session_limit_parse_reset <raw> [now_epoch]     -> ISO8601 + numeric offset
#                                                      (e.g. 2026-07-06T21:50:00+10:00)
#   session_limit_parse_reset_epoch <raw> [now_epoch] -> same instant, plain unix epoch
#
# WHY an epoch twin of the ISO parse: jq's fromdateiso8601 REJECTS the
# "+10:00"-offset ISO form (it only parses bare-Z UTC). Any jq-side comparison
# of reset_at against now (e.g. run-mode-stop-guard.sh's single-jq design) needs
# a plain epoch integer, not the offset-ISO string. Both wrappers share one
# internal resolver so the parse logic stays DRY.
#
# WHY no set -e: sourced into hooks/CLIs that own their own exit paths; a parse
# failure must return non-zero to the caller, never abort the caller's process
# (mirrors run-mode-stop-guard.sh's no-set-e rationale and compliance-lib.sh).
#
# loa:shortcut: GNU-date only. The TZ-name reset math uses GNU date's free-text
# `date -d` grammar, which BSD/macOS date does not implement the same way.
# Ceiling: on a Darwin host session_limit_matches still DETECTS the shape, but
# session_limit_parse_reset(_epoch) returns non-zero (PARSE_FAIL) and capture
# silently no-ops. Upgrade trigger: if a fleet member runs the harness on macOS,
# add the BSD `date -j -f` / perl Time::Piece tier mirroring
# .claude/scripts/compat-lib.sh:_date_to_epoch (441-475). Not built now: no
# Darwin host was available to verify BSD-date behavior against, and bats CI
# (bats-tests.yml) runs ubuntu-latest exclusively.
#
# loa:shortcut: never build the reset instant with a "<date> <time> +1 day"
# compound string — GNU date's fuzzy grammar can consume "+1" as a UTC-offset
# modifier on the preceding HH:MM instead of a day count, silently landing 1-2
# days off. The roll-forward below advances the DATE-ONLY string first, then
# reattaches HH:MM — verified correct across the AEST/AEDT October boundary.
# =============================================================================

[[ -n "${_SESSION_LIMIT_LIB_LOADED:-}" ]] && return 0
_SESSION_LIMIT_LIB_LOADED=1

set -uo pipefail

# The two observed lead-in phrases (issue #1177). Either one, plus a parseable
# "resets <time> (<tz>)" clause, marks this as a session/usage cap string.
_SESSION_LIMIT_LEADIN_RE='hit your session limit|out of extra usage'
# resets <H|HH>[:MM] [am|pm] (<TZ name>)  — bare-hour and colon-minute forms,
# with or without an am/pm suffix (bare form = 24h clock).
_SESSION_LIMIT_RESET_RE='resets[[:space:]]+([0-9]{1,2})(:([0-9]{2}))?[[:space:]]*([AaPp][Mm])?[[:space:]]*\(([^)]+)\)'

# session_limit_matches <raw> -> 0 iff raw carries a known lead-in AND a
# parseable reset clause. No date math (safe on any host, including macOS).
session_limit_matches() {
    local raw="${1:-}"
    [[ "$raw" =~ $_SESSION_LIMIT_LEADIN_RE ]] || return 1
    [[ "$raw" =~ $_SESSION_LIMIT_RESET_RE ]] || return 1
    return 0
}

# Internal: resolve the reset instant. Echoes "<epoch> <iso>" on success;
# returns 1 on any parse/date failure. now_epoch is injectable for determinism.
_session_limit_resolve() {
    local raw="${1:-}" now_epoch="${2:-}"
    [[ -n "$now_epoch" ]] || now_epoch="$(date +%s)"
    [[ "$now_epoch" =~ ^[0-9]+$ ]] || return 1
    [[ "$raw" =~ $_SESSION_LIMIT_RESET_RE ]] || return 1

    local hh="${BASH_REMATCH[1]}" mm="${BASH_REMATCH[3]}" ampm="${BASH_REMATCH[4]}" tz="${BASH_REMATCH[5]}"
    mm="${mm:-00}"

    # Normalize to a 24h HH:MM (10# forces base-10 so "09" is not read as octal).
    local h=$((10#$hh)) m=$((10#$mm))
    case "${ampm,,}" in
        pm) [[ "$h" -lt 12 ]] && h=$((h + 12)) ;;
        am) [[ "$h" -eq 12 ]] && h=0 ;;
    esac
    [[ "$h" -ge 0 && "$h" -le 23 && "$m" -ge 0 && "$m" -le 59 ]] || return 1
    local hhmm
    printf -v hhmm '%02d:%02d' "$h" "$m"

    # "Today" in the target zone, derived from the injected now-epoch.
    local day cand_epoch iso
    day="$(TZ="$tz" date -d "@$now_epoch" +%Y-%m-%d 2>/dev/null)" || return 1
    [[ -n "$day" ]] || return 1
    cand_epoch="$(TZ="$tz" date -d "$day $hhmm" +%s 2>/dev/null)" || return 1
    [[ "$cand_epoch" =~ ^[0-9]+$ ]] || return 1

    # Roll forward to tomorrow when the wall-clock time is at or before now
    # (exact-equal boundary rolls forward). Date-only advance — see header note.
    if [[ "$cand_epoch" -le "$now_epoch" ]]; then
        day="$(TZ="$tz" date -d "$day +1 day" +%Y-%m-%d 2>/dev/null)" || return 1
        [[ -n "$day" ]] || return 1
        cand_epoch="$(TZ="$tz" date -d "$day $hhmm" +%s 2>/dev/null)" || return 1
        [[ "$cand_epoch" =~ ^[0-9]+$ ]] || return 1
    fi

    iso="$(TZ="$tz" date -d "$day $hhmm" +%Y-%m-%dT%H:%M:%S%:z 2>/dev/null)" || return 1
    [[ -n "$iso" ]] || return 1
    printf '%s %s' "$cand_epoch" "$iso"
}

# session_limit_parse_reset <raw> [now_epoch] -> ISO8601 + offset on stdout.
session_limit_parse_reset() {
    local out
    out="$(_session_limit_resolve "$@")" || return 1
    printf '%s\n' "${out#* }"
}

# session_limit_parse_reset_epoch <raw> [now_epoch] -> plain unix epoch on stdout.
session_limit_parse_reset_epoch() {
    local out
    out="$(_session_limit_resolve "$@")" || return 1
    printf '%s\n' "${out%% *}"
}
