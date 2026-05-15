#!/usr/bin/env bats
# =============================================================================
# tests/unit/verdict-quality-bash-twin.bats
#
# cycle-109 Sprint 2 T2.2 — bash twin parity for the verdict-quality
# classifier. The bash twin at `.claude/scripts/lib/verdict-quality.sh`
# shells out to the Python canonical (no logic duplication); these tests
# pin the byte-equality contract per SDD §5.2.1.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    TWIN="$PROJECT_ROOT/.claude/scripts/lib/verdict-quality.sh"

    [[ -x "$TWIN" ]] || {
        printf 'FATAL: bash twin not executable at %s\n' "$TWIN" >&2
        return 1
    }
}

# Send a JSON envelope on stdin to `verdict-quality.sh compute`; echoes
# the status enum value.
_compute() {
    bash "$TWIN" compute
}

# Send a JSON envelope on stdin to `verdict-quality.sh emit`; echoes the
# validated + status-stamped envelope JSON.
_emit() {
    bash "$TWIN" emit
}

# =============================================================================
# Bash twin parity — each row of SDD §3.2.2 echoes the same status the
# Python canonical does.
# =============================================================================

@test "BT1: bash twin returns APPROVED for full-success envelope" {
    local env='{"status":"X","consensus_outcome":"consensus","truncation_waiver_applied":false,"voices_planned":3,"voices_succeeded":3,"voices_succeeded_ids":["opus","gpt-5.5-pro","gemini-3.1-pro"],"voices_dropped":[],"chain_health":"ok","confidence_floor":"high","rationale":"ok"}'
    run bash -c "echo '$env' | bash '$TWIN' compute"
    [ "$status" -eq 0 ]
    [[ "$output" == *"APPROVED"* ]]
}

@test "BT2: bash twin returns DEGRADED for partial-success envelope" {
    local env='{"status":"X","consensus_outcome":"consensus","truncation_waiver_applied":false,"voices_planned":3,"voices_succeeded":2,"voices_succeeded_ids":["opus","gpt-5.5-pro"],"voices_dropped":[{"voice":"gemini-3.1-pro","reason":"EmptyContent","exit_code":1,"blocker_risk":"med"}],"chain_health":"degraded","confidence_floor":"med","rationale":"gemini dropped"}'
    run bash -c "echo '$env' | bash '$TWIN' compute"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEGRADED"* ]]
}

@test "BT3: bash twin returns FAILED for chain-exhausted envelope" {
    local env='{"status":"X","consensus_outcome":"consensus","truncation_waiver_applied":false,"voices_planned":3,"voices_succeeded":0,"voices_succeeded_ids":[],"voices_dropped":[{"voice":"opus","reason":"ChainExhausted","exit_code":12,"blocker_risk":"med"},{"voice":"gpt-5.5-pro","reason":"ChainExhausted","exit_code":12,"blocker_risk":"med"},{"voice":"gemini-3.1-pro","reason":"ChainExhausted","exit_code":12,"blocker_risk":"med"}],"chain_health":"exhausted","confidence_floor":"low","rationale":"all chains exhausted"}'
    run bash -c "echo '$env' | bash '$TWIN' compute"
    [ "$status" -eq 0 ]
    [[ "$output" == *"FAILED"* ]]
}

@test "BT4: bash twin returns FAILED for any high-risk dropped voice" {
    local env='{"status":"X","consensus_outcome":"consensus","truncation_waiver_applied":false,"voices_planned":3,"voices_succeeded":2,"voices_succeeded_ids":["opus","gpt-5.5-pro"],"voices_dropped":[{"voice":"gemini-3.1-pro","reason":"EmptyContent","exit_code":1,"blocker_risk":"high"}],"chain_health":"degraded","confidence_floor":"med","rationale":"high-risk drop"}'
    run bash -c "echo '$env' | bash '$TWIN' compute"
    [ "$status" -eq 0 ]
    [[ "$output" == *"FAILED"* ]]
}

@test "BT5: bash twin exits 2 on invariant violation (voices_planned=0)" {
    local env='{"status":"X","consensus_outcome":"consensus","truncation_waiver_applied":false,"voices_planned":0,"voices_succeeded":0,"voices_succeeded_ids":[],"voices_dropped":[],"chain_health":"ok","confidence_floor":"high","rationale":"bad"}'
    run bash -c "echo '$env' | bash '$TWIN' emit"
    [ "$status" -eq 2 ]
    [[ "$output" == *"INV-1"* ]] || [[ "$output" == *"invariant"* ]]
}

@test "BT6: bash twin exits 3 on malformed JSON" {
    run bash -c "echo 'not-json-at-all' | bash '$TWIN' compute"
    [ "$status" -eq 3 ]
}

@test "BT7: bash twin exits 64 on missing subcommand" {
    run bash "$TWIN"
    [ "$status" -eq 64 ]
    [[ "$output" == *"usage"* ]]
}

@test "BT8: bash twin emit stamps status field on validated envelope" {
    local env='{"status":"PLACEHOLDER","consensus_outcome":"consensus","truncation_waiver_applied":false,"voices_planned":3,"voices_succeeded":3,"voices_succeeded_ids":["opus","gpt-5.5-pro","gemini-3.1-pro"],"voices_dropped":[],"chain_health":"ok","confidence_floor":"high","rationale":"ok"}'
    run bash -c "echo '$env' | bash '$TWIN' emit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"status\":\"APPROVED\""* ]]
}
