#!/usr/bin/env bats
# cycle-103 sprint-1 T1.8 — AC-1.3 vestigial-marker pin for the entry.sh
# NODE_OPTIONS Happy Eyeballs fix.
#
# Sprint plan filename ("tests/test_entry_sh_node_options_vestigial.bats") is
# paraphrased — repo convention places bats unit tests under tests/unit/ with
# dashes instead of underscores. This file matches the convention used by
# sibling bats files (flatline-*.bats, lib-curl-fallback-*.bats,
# check-no-direct-llm-fetch.bats).
#
# Contract pinned by this file:
#   1. The VESTIGIAL marker comment block is present in entry.sh — removing it
#      without the companion cycle-104 removal landing fails this test.
#   2. The cycle-104 removal TODO is present alongside the marker — ensures
#      the gate condition is documented inline with the code.
#   3. The NODE_OPTIONS export is STILL present (per AC-1.5 — the flag
#      stays at merge time; removal is gated on cycle-104).
#   4. The LOA_BB_DISABLE_FAMILY_TIMEOUT_FIX opt-out env hatch is still
#      honored (the original safety valve).
#
# These four assertions together form the "vestigial-but-active" contract:
# the operator-facing behavior is unchanged in this PR (AC-1.5 stay-at-merge),
# while the in-code marker telegraphs to future maintainers that removal is
# scheduled for cycle-104.

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    ENTRY="$PROJECT_ROOT/.claude/skills/bridgebuilder-review/resources/entry.sh"
    [[ -f "$ENTRY" ]] || skip "entry.sh not found at $ENTRY"
}

@test "VESTIGIAL marker comment is present" {
    run grep -F 'VESTIGIAL — cycle-103 sprint-1 T1.8 / AC-1.3' "$ENTRY"
    [ "$status" -eq 0 ]
}

@test "cycle-104+ removal TODO is present alongside the marker" {
    # cycle-104 sprint-2 T2.14: TODO suffix relaxed to "cycle-104+" since
    # the env-var rollback signal (LOA_BB_FORCE_LEGACY_FETCH) was retired
    # but the NODE_OPTIONS removal itself is gated on a later cycle. Match
    # both shapes so the test survives the relaxation.
    run grep -E 'TODO\(cycle-104\+?\): remove this entire NODE_OPTIONS block' "$ENTRY"
    [ "$status" -eq 0 ]
}

@test "removal gate conditions are documented inline" {
    # github-cli.ts gate condition must remain so removers know what to
    # verify. The LOA_BB_FORCE_LEGACY_FETCH gate was retired in cycle-104
    # sprint-2 T2.14 (the env var no longer exists); its historical
    # mention in the TODO is acceptable but no longer load-bearing.
    run grep -F 'github-cli.ts' "$ENTRY"
    [ "$status" -eq 0 ]
}

@test "NODE_OPTIONS export is STILL active (AC-1.5 — stays at merge)" {
    # The flag stays at merge time. This bats test FAILS if someone removes
    # the NODE_OPTIONS export without the marker also being removed (i.e.,
    # forgets to gate the cleanup on cycle-104).
    run grep -F -- '--network-family-autoselection-attempt-timeout=5000' "$ENTRY"
    [ "$status" -eq 0 ]
    run grep -F 'export NODE_OPTIONS=' "$ENTRY"
    [ "$status" -eq 0 ]
}

@test "LOA_BB_DISABLE_FAMILY_TIMEOUT_FIX opt-out hatch is still honored" {
    # The original safety valve must stay so operators can opt out if the
    # cycle-103 unification doesn't fully eliminate the failure mode.
    run grep -F 'LOA_BB_DISABLE_FAMILY_TIMEOUT_FIX' "$ENTRY"
    [ "$status" -eq 0 ]
}

@test "entry.sh syntax is valid bash" {
    run bash -n "$ENTRY"
    [ "$status" -eq 0 ]
}
