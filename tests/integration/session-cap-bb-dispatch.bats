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

_copy_contract_repo() {
    local root="$TEST_DIR/contract repo"
    local rel=".claude/skills/scheduled-cycle-template/contracts/session-cap-bb"
    mkdir -p "$root/$rel" "$root/.run" "$TEST_DIR/outside/.run"
    cp "$CDIR/"*.sh "$root/$rel/"
    git -C "$root" init -q
    git -C "$root" remote add origin https://github.com/fixture/owned-repo.git
    CDIR="$root/$rel"
    _write_state RUNNING NONE
    cp "$STATE_FILE" "$root/.run/session-limit-state.json"
    printf 'corrupt caller state' > "$TEST_DIR/outside/.run/session-limit-state.json"
    cd "$TEST_DIR/outside"
}

@test "issue-1213: reader defaults to script repo state from an unrelated cwd" {
    _copy_contract_repo
    unset LOA_SESSION_CAP_STATE_FILE
    run "${CDIR}/reader.sh" cid-root sched 0 '[]'
    [ "$status" -eq 0 ]
    jq -e '.state_present == true and .sprint_plan_state == "RUNNING"' <<< "$output"
}

@test "issue-1213: dispatcher resolves script repo origin from another repository" {
    _copy_contract_repo
    git init -q
    git remote add origin https://github.com/wrong/caller-repo.git
    export LOA_SESSION_CAP_STATE_FILE="$STATE_FILE"
    export LOA_SESSION_CAP_BB_ENTRY="$MOCK_ENTRY"
    unset LOA_SESSION_CAP_BB_REPO
    "${CDIR}/reader.sh" cid-origin sched 0 '[]' >/dev/null
    "${CDIR}/decider.sh" cid-origin sched 1 '[]' >/dev/null
    run "${CDIR}/dispatcher.sh" cid-origin sched 2 '[]'
    [ "$status" -eq 0 ]
    [[ "$(cat "$MOCK_ARGS")" == *"--repo fixture/owned-repo"* ]]
}

@test "issue-1213: explicit state and repo overrides still win outside the root" {
    _copy_contract_repo
    _write_state NONE HALTED
    export LOA_SESSION_CAP_STATE_FILE="$STATE_FILE"
    export LOA_SESSION_CAP_BB_ENTRY="$MOCK_ENTRY"
    export LOA_SESSION_CAP_BB_REPO="explicit/override"
    run "${CDIR}/reader.sh" cid-override sched 0 '[]'
    [ "$status" -eq 0 ]
    jq -e '.bridge_state == "HALTED"' <<< "$output"
    "${CDIR}/decider.sh" cid-override sched 1 '[]' >/dev/null
    run "${CDIR}/dispatcher.sh" cid-override sched 2 '[]'
    [ "$status" -eq 0 ]
    [[ "$(cat "$MOCK_ARGS")" == *"--repo explicit/override"* ]]
}

# A real local Git submodule, with the installer-style skills symlink. Both
# origins are inert strings; the only submodule transport is a local file path.
_copy_mounted_contract_repo() {
    local rel=".claude/skills/scheduled-cycle-template/contracts/session-cap-bb"
    local seed="$TEST_DIR/framework source"
    export CONSUMER_ROOT="$TEST_DIR/consumer repo"
    export FRAMEWORK_ROOT="$CONSUMER_ROOT/.loa"
    mkdir -p "$seed/$rel" "$CONSUMER_ROOT/.claude" "$CONSUMER_ROOT/.run"
    cp "$CDIR/"*.sh "$seed/$rel/"
    git -C "$seed" init -q
    git -C "$seed" add .
    git -C "$seed" -c user.name=Fixture -c user.email=fixture@example.invalid \
        -c commit.gpgSign=false -c core.hooksPath=/dev/null commit -qm fixture
    git -C "$CONSUMER_ROOT" init -q
    git -C "$CONSUMER_ROOT" -c protocol.file.allow=always \
        submodule add -q "$seed" .loa
    git -C "$CONSUMER_ROOT" remote add origin https://github.com/fixture/consumer.git
    git -C "$FRAMEWORK_ROOT" remote set-url origin https://github.com/fixture/framework.git
    ln -s ../.loa/.claude/skills "$CONSUMER_ROOT/.claude/skills"
    CDIR="$CONSUMER_ROOT/$rel"
    _write_state RUNNING NONE
    cp "$STATE_FILE" "$CONSUMER_ROOT/.run/session-limit-state.json"
    mkdir -p "$TEST_DIR/outside/.run"
    printf 'corrupt caller state' > "$TEST_DIR/outside/.run/session-limit-state.json"
    git -C "$TEST_DIR/outside" init -q
    git -C "$TEST_DIR/outside" remote add origin https://github.com/wrong/caller.git
    cd "$TEST_DIR/outside"
    unset LOA_SESSION_CAP_STATE_FILE LOA_SESSION_CAP_BB_REPO
    export LOA_SESSION_CAP_BB_ENTRY="$MOCK_ENTRY"
}

_canonical_mounted_phase() {
    bash -c '
        source "$LIB"
        _L3_REPO_ROOT="$CONSUMER_ROOT"
        _l3_validate_phase_path "$1" fixture
    ' _ "$1"
}

@test "issue-1213 mounted: logical phases bind the consumer from unrelated cwd" {
    _copy_mounted_contract_repo
    run "$CDIR/reader.sh" cid-mounted-logical sched 0 '[]'
    [ "$status" -eq 0 ]
    jq -e '.state_present and .sprint_plan_state == "RUNNING"' <<< "$output"
    "$CDIR/decider.sh" cid-mounted-logical sched 1 '[]' >/dev/null
    run "$CDIR/dispatcher.sh" cid-mounted-logical sched 2 '[]'
    [ "$status" -eq 0 ]
    jq -e '.repo == "fixture/consumer"' <<< "$output"
}

@test "issue-1213 mounted: canonical reader uses consumer with absent or conflicting framework state" {
    _copy_mounted_contract_repo
    local reader
    reader="$(_canonical_mounted_phase "${CDIR}/reader.sh")"
    [[ "$reader" == "$FRAMEWORK_ROOT/"* ]]
    run "$reader" cid-mounted-reader sched 0 '[]'
    [ "$status" -eq 0 ]
    jq -e '.state_present and .sprint_plan_state == "RUNNING" and .bridge_state == "NONE"' <<< "$output"
    mkdir -p "$FRAMEWORK_ROOT/.run"
    _write_state NONE HALTED
    cp "$STATE_FILE" "$FRAMEWORK_ROOT/.run/session-limit-state.json"
    run "$reader" cid-mounted-decoy sched 0 '[]'
    [ "$status" -eq 0 ]
    jq -e '.state_present and .sprint_plan_state == "RUNNING" and .bridge_state == "NONE"' <<< "$output"
}

@test "issue-1213 mounted: canonical dispatcher selects consumer origin independently of reader" {
    _copy_mounted_contract_repo
    local dispatcher
    dispatcher="$(_canonical_mounted_phase "${CDIR}/dispatcher.sh")"
    [[ "$dispatcher" == "$FRAMEWORK_ROOT/"* ]]
    mkdir -p "$TMPDIR/loa-session-cap-bb.cid-mounted-dispatch"
    printf '{"action":"dispatch"}' > "$TMPDIR/loa-session-cap-bb.cid-mounted-dispatch/decider.json"
    run "$dispatcher" cid-mounted-dispatch sched 2 '[]'
    [ "$status" -eq 0 ]
    jq -e '.dispatched and .repo == "fixture/consumer"' <<< "$output"
    [[ "$(cat "$MOCK_ARGS")" == "ARGS: --repo fixture/consumer" ]]
}

@test "issue-1213 mounted: corrupt consumer state fails through canonical reader" {
    _copy_mounted_contract_repo
    printf 'corrupt consumer state' > "$CONSUMER_ROOT/.run/session-limit-state.json"
    local reader
    reader="$(_canonical_mounted_phase "${CDIR}/reader.sh")"
    run "$reader" cid-mounted-corrupt sched 0 '[]'
    [ "$status" -ne 0 ]
    [[ "$output" == *"present but not valid JSON"* ]]
}

@test "issue-1213 mounted: explicit overrides survive canonical invocation" {
    _copy_mounted_contract_repo
    _write_state NONE HALTED
    export LOA_SESSION_CAP_STATE_FILE="$STATE_FILE"
    export LOA_SESSION_CAP_BB_REPO="explicit/override"
    local reader dispatcher
    reader="$(_canonical_mounted_phase "${CDIR}/reader.sh")"
    dispatcher="$(_canonical_mounted_phase "${CDIR}/dispatcher.sh")"
    run "$reader" cid-mounted-override sched 0 '[]'
    [ "$status" -eq 0 ]
    jq -e '.sprint_plan_state == "NONE" and .bridge_state == "HALTED"' <<< "$output"
    "$CDIR/decider.sh" cid-mounted-override sched 1 '[]' >/dev/null
    run "$dispatcher" cid-mounted-override sched 2 '[]'
    [ "$status" -eq 0 ]
    jq -e '.repo == "explicit/override"' <<< "$output"
}

@test "issue-1213 mounted: canonical containment still rejects traversal and escaped symlinks" {
    _copy_mounted_contract_repo
    local outside="$TEST_DIR/outside/escape.sh"
    printf '#!/bin/sh\nexit 0\n' > "$outside"
    ln -s "$outside" "$CONSUMER_ROOT/.claude/skills/escape.sh"
    run _canonical_mounted_phase "$CONSUMER_ROOT/.claude/skills/escape.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"outside allowlist"* ]]
    run _canonical_mounted_phase "../outside/escape.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"outside allowlist"* ]]
}

@test "issue-1213 mounted: a nested framework without the consumer skills mount keeps its own root" {
    _copy_mounted_contract_repo
    rm "$CONSUMER_ROOT/.claude/skills"
    mkdir -p "$FRAMEWORK_ROOT/.run"
    _write_state NONE HALTED
    cp "$STATE_FILE" "$FRAMEWORK_ROOT/.run/session-limit-state.json"
    local physical="$FRAMEWORK_ROOT/.claude/skills/scheduled-cycle-template/contracts/session-cap-bb"
    run "$physical/reader.sh" cid-unmounted sched 0 '[]'
    [ "$status" -eq 0 ]
    jq -e '.sprint_plan_state == "NONE" and .bridge_state == "HALTED"' <<< "$output"
    "$physical/decider.sh" cid-unmounted sched 1 '[]' >/dev/null
    run "$physical/dispatcher.sh" cid-unmounted sched 2 '[]'
    [ "$status" -eq 0 ]
    jq -e '.repo == "fixture/framework"' <<< "$output"
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

@test "issue-1213 mounted: full scheduler canonicalizes phases and dispatches consumer without state or repo overrides" {
    _copy_mounted_contract_repo
    local yaml="$TEST_DIR/mounted.yaml"
    _bb_schedule_yaml "$yaml"
    export LOA_CYCLES_LOG="$TEST_DIR/mounted-cycles.jsonl"
    export LOA_L3_LOCK_DIR="$TEST_DIR/mounted-locks"
    # Only the external BB call is replaced. Default state/origin, canonical
    # allowlisting, env-i, phase sequencing, and audit emission stay real.
    export LOA_L3_PHASE_ENV_PASSTHROUGH="LOA_SESSION_CAP_BB_ENTRY"
    run bash -c '
        source "$LIB"
        _L3_REPO_ROOT="$CONSUMER_ROOT"
        cycle_invoke "$1" --cycle-id mounted-full
    ' _ "$yaml"
    [ "$status" -eq 0 ]
    # The real logger removes the handoff directory. A dispatched entry proves
    # the reader/decider saw the active consumer state before that cleanup.
    [ -f "$MOCK_ARGS" ]
    [[ "$(cat "$MOCK_ARGS")" == "ARGS: --repo fixture/consumer" ]]
    jq -se 'length == 7 and ([.[] | select(.event_type == "cycle.complete")] | length == 1)' \
        "$LOA_CYCLES_LOG"
}
