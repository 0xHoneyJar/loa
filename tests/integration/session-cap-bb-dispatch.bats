#!/usr/bin/env bats
# =============================================================================
# session-cap-bb-dispatch.bats — real bridgebuilder dispatch contract
# (bd-fanout-real-dispatch-9jv6 Tranche 1).
#
# Covers the session-cap-bb reader/decider/dispatcher/awaiter/logger scripts:
#   - reader sanity gate (absent = noop-normal, corrupt = abort)
#   - decider FAIL-CLOSED (dispatch only on RUNNING/HALTED, else noop)
#   - dispatcher invokes the BB entrypoint with --repo <repo> and NO --pr on
#     dispatch, and short-circuits (no invocation) on noop
#   - dry-run invoke emits cycle.start only
#   - full invoke against a MOCK entrypoint produces the 7-record cycle
#
# Never invokes the real bridgebuilder-review entrypoint — a mock entry script
# on LOA_SESSION_CAP_BB_ENTRY records its argv to a fixed file.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    CDIR="${REPO_ROOT}/.claude/skills/scheduled-cycle-template/contracts/session-cap-bb"
    LIB="${REPO_ROOT}/.claude/scripts/lib/scheduled-cycle-lib.sh"

    TEST_DIR="$(mktemp -d)"
    # Isolate the per-cycle handoff dir under our own TMPDIR (cleaned in teardown).
    export TMPDIR="${TEST_DIR}/tmp"
    mkdir -p "$TMPDIR"

    STATE_FILE="${TEST_DIR}/session-limit-state.json"
    MOCK_ARGS="${TEST_DIR}/mock-entry-args.txt"
    MOCK_ENTRY="${TEST_DIR}/bin/mock-entry.sh"
    mkdir -p "${TEST_DIR}/bin"
    # Mock BB entrypoint: records argv to a fixed absolute path, exits 0.
    cat > "$MOCK_ENTRY" <<EOF
#!/usr/bin/env bash
echo "ARGS: \$*" >> "${MOCK_ARGS}"
exit 0
EOF
    chmod +x "$MOCK_ENTRY"

    unset LOA_AUDIT_SIGNING_KEY_ID
    export LOA_AUDIT_VERIFY_SIGS=0
    export REPO_ROOT CDIR LIB TEST_DIR STATE_FILE MOCK_ARGS MOCK_ENTRY
}

teardown() {
    rm -rf "$TEST_DIR"
}

_write_state() {  # $1 sprint_plan.state  $2 bridge.state
    jq -nc --arg sp "$1" --arg br "$2" \
        '{active_run_state_snapshot:{sprint_plan:{state:$sp}, bridge:{state:$br}}}' \
        > "$STATE_FILE"
}

# -----------------------------------------------------------------------------
# reader — sanity gate
# -----------------------------------------------------------------------------

@test "reader: absent state file is normal (state_present:false, exit 0)" {
    export LOA_SESSION_CAP_STATE_FILE="${TEST_DIR}/does-not-exist.json"
    run "${CDIR}/reader.sh" cid-absent sched 0 '[]'
    [ "$status" -eq 0 ]
    run jq -r '.state_present' <<<"$output"
    [ "$output" = "false" ]
}

@test "reader: present-but-corrupt state file trips the sanity gate (exit != 0)" {
    printf 'not json{' > "$STATE_FILE"
    export LOA_SESSION_CAP_STATE_FILE="$STATE_FILE"
    run "${CDIR}/reader.sh" cid-corrupt sched 0 '[]'
    [ "$status" -ne 0 ]
}

# -----------------------------------------------------------------------------
# decider — FAIL-CLOSED
# -----------------------------------------------------------------------------

@test "decider: sprint_plan RUNNING => action:dispatch" {
    _write_state RUNNING NONE
    export LOA_SESSION_CAP_STATE_FILE="$STATE_FILE"
    run "${CDIR}/reader.sh" cid-run sched 0 '[]'
    [ "$status" -eq 0 ]
    run "${CDIR}/decider.sh" cid-run sched 1 '[]'
    [ "$status" -eq 0 ]
    run jq -r '.action' <<<"$output"
    [ "$output" = "dispatch" ]
}

@test "decider: bridge HALTED => action:dispatch" {
    _write_state NONE HALTED
    export LOA_SESSION_CAP_STATE_FILE="$STATE_FILE"
    run "${CDIR}/reader.sh" cid-halt sched 0 '[]'
    [ "$status" -eq 0 ]
    run "${CDIR}/decider.sh" cid-halt sched 1 '[]'
    [ "$status" -eq 0 ]
    run jq -r '.action' <<<"$output"
    [ "$output" = "dispatch" ]
}

@test "decider: terminal/idle snapshot => action:noop" {
    _write_state JACKED_OUT NONE
    export LOA_SESSION_CAP_STATE_FILE="$STATE_FILE"
    run "${CDIR}/reader.sh" cid-idle sched 0 '[]'
    [ "$status" -eq 0 ]
    run "${CDIR}/decider.sh" cid-idle sched 1 '[]'
    [ "$status" -eq 0 ]
    run jq -r '.action' <<<"$output"
    [ "$output" = "noop" ]
}

@test "decider: absent snapshot (reader saw no state) => action:noop (fail-closed)" {
    export LOA_SESSION_CAP_STATE_FILE="${TEST_DIR}/does-not-exist.json"
    run "${CDIR}/reader.sh" cid-none sched 0 '[]'
    [ "$status" -eq 0 ]
    run "${CDIR}/decider.sh" cid-none sched 1 '[]'
    [ "$status" -eq 0 ]
    run jq -r '.action' <<<"$output"
    [ "$output" = "noop" ]
}

# -----------------------------------------------------------------------------
# dispatcher — invocation shape (--repo, no --pr) vs noop short-circuit
# -----------------------------------------------------------------------------

@test "dispatcher: on dispatch, invokes entrypoint with --repo <repo> and NO --pr" {
    _write_state RUNNING NONE
    export LOA_SESSION_CAP_STATE_FILE="$STATE_FILE"
    export LOA_SESSION_CAP_BB_ENTRY="$MOCK_ENTRY"
    export LOA_SESSION_CAP_BB_REPO="0xHoneyJar/loa"
    run "${CDIR}/reader.sh"   cid-disp sched 0 '[]'
    [ "$status" -eq 0 ]
    run "${CDIR}/decider.sh"  cid-disp sched 1 '[]'
    [ "$status" -eq 0 ]
    run "${CDIR}/dispatcher.sh" cid-disp sched 2 '[]'
    [ "$status" -eq 0 ]

    [ -f "$MOCK_ARGS" ]
    run cat "$MOCK_ARGS"
    [[ "$output" == *"--repo 0xHoneyJar/loa"* ]]
    [[ "$output" != *"--pr"* ]]
    run jq -r '.dispatched' <<<"$(cat "${TMPDIR}/loa-session-cap-bb.cid-disp/dispatcher.json")"
    [ "$output" = "true" ]
}

@test "dispatcher: on noop, does NOT invoke the entrypoint (short-circuit exit 0)" {
    _write_state JACKED_OUT NONE
    export LOA_SESSION_CAP_STATE_FILE="$STATE_FILE"
    export LOA_SESSION_CAP_BB_ENTRY="$MOCK_ENTRY"
    export LOA_SESSION_CAP_BB_REPO="0xHoneyJar/loa"
    run "${CDIR}/reader.sh"   cid-noop sched 0 '[]'
    [ "$status" -eq 0 ]
    run "${CDIR}/decider.sh"  cid-noop sched 1 '[]'
    [ "$status" -eq 0 ]
    run "${CDIR}/dispatcher.sh" cid-noop sched 2 '[]'
    [ "$status" -eq 0 ]

    [ ! -f "$MOCK_ARGS" ]
    run jq -r '.dispatched' <<<"$output"
    [ "$output" = "false" ]
}

# -----------------------------------------------------------------------------
# lib invoke — dry-run (cycle.start only) + full (7 records) with mock entry
# -----------------------------------------------------------------------------

_bb_schedule_yaml() {  # $1 dest path
    local rel=".claude/skills/scheduled-cycle-template/contracts/session-cap-bb"
    cat > "$1" <<YAML
schedule_id: session-cap-bb-test
schedule: "5 2 * * *"
dispatch_contract:
  reader:     "${rel}/reader.sh"
  decider:    "${rel}/decider.sh"
  dispatcher: "${rel}/dispatcher.sh"
  awaiter:    "${rel}/awaiter.sh"
  logger:     "${rel}/logger.sh"
  budget_estimate_usd: 0
  timeout_seconds: 1800
YAML
}

@test "invoke --dry-run against the BB schedule emits cycle.start only" {
    local yaml="${TEST_DIR}/bb.yaml"
    _bb_schedule_yaml "$yaml"
    local cyclog="${TEST_DIR}/cycles-dry.jsonl"
    local lockdir="${TEST_DIR}/lock-dry"
    mkdir -p "$lockdir"
    export LOA_CYCLES_LOG="$cyclog" LOA_L3_LOCK_DIR="$lockdir"

    run "$LIB" invoke "$yaml" --cycle-id bb-dry --dry-run
    [ "$status" -eq 0 ]
    run jq -sr '. | length' "$cyclog"
    [ "$output" = "1" ]
    run jq -sr '.[0].event_type' "$cyclog"
    [ "$output" = "cycle.start" ]
}

@test "invoke (full) with state RUNNING + mock entry produces the 7-record cycle and dispatches" {
    _write_state RUNNING NONE
    local yaml="${TEST_DIR}/bb.yaml"
    _bb_schedule_yaml "$yaml"
    local cyclog="${TEST_DIR}/cycles-full.jsonl"
    local lockdir="${TEST_DIR}/lock-full"
    mkdir -p "$lockdir"
    export LOA_CYCLES_LOG="$cyclog" LOA_L3_LOCK_DIR="$lockdir"
    # Expose the contract's test overrides through the L3 env -i sandbox.
    export LOA_SESSION_CAP_STATE_FILE="$STATE_FILE"
    export LOA_SESSION_CAP_BB_ENTRY="$MOCK_ENTRY"
    export LOA_SESSION_CAP_BB_REPO="0xHoneyJar/loa"
    export LOA_L3_PHASE_ENV_PASSTHROUGH="LOA_SESSION_CAP_STATE_FILE LOA_SESSION_CAP_BB_ENTRY LOA_SESSION_CAP_BB_REPO"

    run "$LIB" invoke "$yaml" --cycle-id bb-full
    [ "$status" -eq 0 ]

    run jq -sr '. | length' "$cyclog"
    [ "$output" = "7" ]
    run jq -sr '[.[] | select(.event_type == "cycle.complete")] | length' "$cyclog"
    [ "$output" = "1" ]
    run jq -sr '[.[] | select(.event_type == "cycle.phase")] | length' "$cyclog"
    [ "$output" = "5" ]

    # The mock entrypoint was fired with --repo and no --pr.
    [ -f "$MOCK_ARGS" ]
    run cat "$MOCK_ARGS"
    [[ "$output" == *"--repo 0xHoneyJar/loa"* ]]
    [[ "$output" != *"--pr"* ]]
}
