#!/usr/bin/env bats
# =============================================================================
# tests/unit/session-limit-lib.bats
#
# cycle-117 item A — session-limit-lib.sh TZ-aware reset parser
# (bd-c117-a-session-cap-x04j, issue #1177 A).
#
# Every reset-time case injects an explicit now_epoch so the suite is
# deterministic regardless of when CI runs it (whether a reset time rolls to
# tomorrow depends entirely on now relative to the fixed reset string).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LIB="$PROJECT_ROOT/.claude/scripts/lib/session-limit-lib.sh"
    # shellcheck source=/dev/null
    source "$LIB"
    # 2026-07-06T06:00:00Z == 2026-07-06 16:00 AEST (+10:00)
    NOW_JUL="$(date -u -d 2026-07-06T06:00:00Z +%s)"
}

# --- session_limit_matches -------------------------------------------------

@test "matches: 'hit your session limit' + reset clause" {
    run session_limit_matches "You've hit your session limit · resets 9:50pm (Australia/Melbourne)"
    [ "$status" -eq 0 ]
}

@test "matches: 'out of extra usage' + reset clause" {
    run session_limit_matches "You're out of extra usage · resets 3pm (Australia/Melbourne)"
    [ "$status" -eq 0 ]
}

@test "matches: lead-in present but no reset clause → no match" {
    run session_limit_matches "You've hit your session limit, try later"
    [ "$status" -ne 0 ]
}

@test "matches: reset clause present but no known lead-in → no match" {
    run session_limit_matches "server maintenance · resets 3pm (Australia/Melbourne)"
    [ "$status" -ne 0 ]
}

@test "matches: unrelated text → no match" {
    run session_limit_matches "hello world"
    [ "$status" -ne 0 ]
}

# --- session_limit_parse_reset: both observed shapes -----------------------

@test "parse: 9:50pm colon-minute form, future today (no roll)" {
    run session_limit_parse_reset "hit your session limit · resets 9:50pm (Australia/Melbourne)" "$NOW_JUL"
    [ "$status" -eq 0 ]
    [ "$output" = "2026-07-06T21:50:00+10:00" ]
}

@test "parse: 3pm bare-hour am/pm form, already passed → rolls forward" {
    run session_limit_parse_reset "out of extra usage · resets 3pm (Australia/Melbourne)" "$NOW_JUL"
    [ "$status" -eq 0 ]
    [ "$output" = "2026-07-07T15:00:00+10:00" ]
}

@test "parse: bare 24h form (no am/pm) rolls forward" {
    run session_limit_parse_reset "out of extra usage · resets 15:00 (Australia/Melbourne)" "$NOW_JUL"
    [ "$status" -eq 0 ]
    [ "$output" = "2026-07-07T15:00:00+10:00" ]
}

@test "parse: 9am rolls forward to tomorrow" {
    run session_limit_parse_reset "hit your session limit · resets 9am (Australia/Melbourne)" "$NOW_JUL"
    [ "$status" -eq 0 ]
    [ "$output" = "2026-07-07T09:00:00+10:00" ]
}

@test "parse: 12am maps to 00:00" {
    run session_limit_parse_reset "hit your session limit · resets 12am (Australia/Melbourne)" "$NOW_JUL"
    [ "$status" -eq 0 ]
    [ "$output" = "2026-07-07T00:00:00+10:00" ]
}

@test "parse: 12pm maps to noon" {
    run session_limit_parse_reset "hit your session limit · resets 12pm (Australia/Melbourne)" "$NOW_JUL"
    [ "$status" -eq 0 ]
    [ "$output" = "2026-07-07T12:00:00+10:00" ]
}

# --- exact-equal boundary rolls forward ------------------------------------

@test "parse: reset time exactly equal to now rolls forward one day" {
    local nowe
    nowe="$(TZ=Australia/Melbourne date -d '2026-07-06 21:50' +%s)"
    run session_limit_parse_reset "hit your session limit · resets 9:50pm (Australia/Melbourne)" "$nowe"
    [ "$status" -eq 0 ]
    [ "$output" = "2026-07-07T21:50:00+10:00" ]
}

# --- DST boundary (Australia/Melbourne spring-forward 2026-10-04) -----------

@test "parse: DST — reset before Oct-04 transition carries AEST +10:00" {
    # 2026-10-03 06:00 local; 3pm same day is future → no roll, still AEST.
    local nowe
    nowe="$(TZ=Australia/Melbourne date -d '2026-10-03 06:00' +%s)"
    run session_limit_parse_reset "hit your session limit · resets 3pm (Australia/Melbourne)" "$nowe"
    [ "$status" -eq 0 ]
    [ "$output" = "2026-10-03T15:00:00+10:00" ]
}

@test "parse: DST — reset after Oct-04 transition carries AEDT +11:00" {
    # 2026-10-05 06:00 local; 3pm same day is future → no roll, now AEDT.
    local nowe
    nowe="$(TZ=Australia/Melbourne date -d '2026-10-05 06:00' +%s)"
    run session_limit_parse_reset "hit your session limit · resets 3pm (Australia/Melbourne)" "$nowe"
    [ "$status" -eq 0 ]
    [ "$output" = "2026-10-05T15:00:00+11:00" ]
}

@test "parse: DST — roll-forward across the Oct-04 transition day lands AEDT" {
    # now = Oct-03 16:00 local (AEST); 3pm already passed → rolls to Oct-04,
    # which is the transition day and already AEDT (+11:00) at 15:00.
    local nowe
    nowe="$(TZ=Australia/Melbourne date -d '2026-10-03 16:00' +%s)"
    run session_limit_parse_reset "hit your session limit · resets 3pm (Australia/Melbourne)" "$nowe"
    [ "$status" -eq 0 ]
    [ "$output" = "2026-10-04T15:00:00+11:00" ]
}

# --- epoch twin consistency ------------------------------------------------

@test "parse_epoch: matches the ISO instant exactly" {
    local iso epoch
    iso="$(session_limit_parse_reset "hit your session limit · resets 9:50pm (Australia/Melbourne)" "$NOW_JUL")"
    epoch="$(session_limit_parse_reset_epoch "hit your session limit · resets 9:50pm (Australia/Melbourne)" "$NOW_JUL")"
    [ "$epoch" = "$(date -d "$iso" +%s)" ]
}

@test "parse_epoch: emits a bare integer (jq --argjson-safe)" {
    run session_limit_parse_reset_epoch "out of extra usage · resets 3pm (Australia/Melbourne)" "$NOW_JUL"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
}

# --- failure modes ---------------------------------------------------------

@test "parse: non-cap string returns non-zero, no output" {
    run session_limit_parse_reset "totally unrelated text" "$NOW_JUL"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "parse: non-numeric now_epoch returns non-zero" {
    run session_limit_parse_reset "hit your session limit · resets 3pm (Australia/Melbourne)" "not-a-number"
    [ "$status" -ne 0 ]
}
