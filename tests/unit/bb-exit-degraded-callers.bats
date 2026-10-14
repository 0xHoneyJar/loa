#!/usr/bin/env bats
# cycle-129 Sprint 3 Task 3.4 (SDD D-7.7, DEC-0150): Bridgebuilder exits 3 when a multi-model review COMPLETED with a
# DEGRADED consensus. Every shell caller that tests the exit code treats 3 as "completed, degraded": one WARN line naming
# the incomplete voices, never a failure. A stub Bridgebuilder entry.sh stands in for the real one.

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/bb-exit-degraded.XXXXXX")"
    STUB="$WORK/stub-entry.sh"
}

teardown() {
    [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
}

# make_stub <exit_code>: a stub entry.sh that prints a run JSON naming one incomplete voice, then exits <exit_code>
make_stub() {
    cat > "$STUB" <<'STUB_EOF'
#!/usr/bin/env bash
echo '{"mode":"multi-model","degraded":true,"verdicts":[{"pr":7,"voices":{"planned":2,"completed":1,"incomplete":["openai/gpt-5.5"]}}]}'
STUB_EOF
    echo "exit $1" >> "$STUB"
    chmod +x "$STUB"
}

# --- session-cap-bb dispatcher.sh ------------------------------------------------------------------------------------

run_dispatcher() {
    local cid="cyc-$1"
    local handoff="$WORK/tmp/loa-session-cap-bb.$cid"
    mkdir -p "$handoff"
    printf '{"action":"dispatch"}' > "$handoff/decider.json"
    DISPATCHER_JSON="$handoff/dispatcher.json"
    run env TMPDIR="$WORK/tmp" LOA_SESSION_CAP_BB_ENTRY="$STUB" LOA_SESSION_CAP_BB_REPO="fixture/repo" \
        bash "$PROJECT_ROOT/.claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh" "$cid" sched-1 0 '[]'
}

@test "dispatcher: Bridgebuilder exit 3 is completed-degraded — WARN names the voice, handoff degraded, exit 0" {
    make_stub 3
    run_dispatcher a
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: bridgebuilder completed DEGRADED (exit 3): incomplete voices: openai/gpt-5.5"* ]]
    [ "$(jq -r '.bb_exit_code' "$DISPATCHER_JSON")" = "3" ]
    [ "$(jq -r '.degraded' "$DISPATCHER_JSON")" = "true" ]
    [ "$(jq -r '.incomplete_voices' "$DISPATCHER_JSON")" = "openai/gpt-5.5" ]
}

@test "dispatcher: Bridgebuilder's run JSON still reaches stdout" {
    make_stub 3
    run_dispatcher b
    [ "$status" -eq 0 ]
    [[ "$output" == *'"mode":"multi-model"'* ]]
}

@test "dispatcher: exit 0 stays 0 with degraded false and no WARN" {
    make_stub 0
    run_dispatcher c
    [ "$status" -eq 0 ]
    [[ "$output" != *"DEGRADED"* ]]
    [ "$(jq -r '.degraded' "$DISPATCHER_JSON")" = "false" ]
    [ "$(jq -r 'has("incomplete_voices")' "$DISPATCHER_JSON")" = "false" ]
}

@test "dispatcher: any other non-zero exit is still a failure" {
    make_stub 1
    run_dispatcher d
    [ "$status" -eq 1 ]
    [ "$(jq -r '.bb_exit_code' "$DISPATCHER_JSON")" = "1" ]
    [ "$(jq -r '.degraded' "$DISPATCHER_JSON")" = "false" ]
}

# --- spiral-harness.sh _gate_bridgebuilder ---------------------------------------------------------------------------

# run_gate <exit_code>: source the harness, point it at a fake skills tree holding the stub, run the gate
run_gate() {
    make_stub "$1"
    mkdir -p "$WORK/fake/scripts" "$WORK/fake/skills/bridgebuilder-review/resources" "$WORK/evidence"
    cp "$STUB" "$WORK/fake/skills/bridgebuilder-review/resources/entry.sh"
    run bash -c '
        cd "$1" || exit 99
        source "$2/.claude/scripts/spiral-harness.sh"
        set +e
        SCRIPT_DIR="$1/fake/scripts"
        EVIDENCE_DIR="$1/evidence"
        _record_action() { echo "RECORDED:$1:${10}"; }
        _gate_bridgebuilder "https://github.com/fixture/repo/pull/7"
        echo "GATE_RC=$?"
    ' _ "$WORK" "$PROJECT_ROOT"
}

@test "spiral-harness gate: Bridgebuilder exit 3 logs one WARN naming the voice and the gate passes" {
    run_gate 3
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: Bridgebuilder review iter 1 completed DEGRADED (exit 3): incomplete voices: openai/gpt-5.5"* ]]
    [[ "$output" == *"RECORDED:GATE_BRIDGEBUILDER:posted"* ]]
    [[ "$output" == *"GATE_RC=0"* ]]
    [ "$(grep -c 'DEGRADED' <<<"$output")" -eq 1 ]
}

@test "spiral-harness gate: exit 0 logs no WARN" {
    run_gate 0
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN: Bridgebuilder"* ]]
    [[ "$output" == *"GATE_RC=0"* ]]
}

@test "spiral-harness gate: another non-zero exit is logged as not completed (non-blocking, as before)" {
    run_gate 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: Bridgebuilder review iter 1 exited 1 (the review did not complete)"* ]]
    [[ "$output" == *"GATE_RC=0"* ]]
}

@test "spiral-harness: every entry.sh invocation goes through _bb_surface_exit (no bare || true)" {
    local script="$PROJECT_ROOT/.claude/scripts/spiral-harness.sh"
    local invocations surfaced
    invocations=$(grep -c '"\$entry_script" --pr' "$script")
    surfaced=$(grep -c '_bb_surface_exit "\$bb_rc"' "$script")
    [ "$invocations" -ge 2 ]
    [ "$invocations" -eq "$surfaced" ]
}

@test "entry.sh: the missing-dependency preflight exits 4, never the DEGRADED code 3" {
    local entry="$PROJECT_ROOT/.claude/skills/bridgebuilder-review/resources/entry.sh"
    run grep -n '^  exit 3$' "$entry"
    [ "$status" -ne 0 ]
    run grep -c '^  exit 4$' "$entry"
    [ "$output" = "1" ]
}
