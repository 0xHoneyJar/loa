#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-117-push-gate.bats
#
# cycle-117 item C — run-mode-stop-guard.sh push-at-gate side channel
# (bd-c117-c-push-gate-eld2, issue #1177 C).
#
# When a Stop lands while a run/bridge/simstim state file holds a TERMINAL
# state, the guard fires an operator-configurable, best-effort external push
# command exactly once per distinct terminal transition — without ever
# changing its own exit code or its (empty-on-allow) stdout contract.
#
# Terminal vocabularies differ per file:
#   sprint-plan: JACKED_OUT | READY_FOR_HITL | HALTED
#   bridge:      JACKED_OUT | HALTED            (no READY_FOR_HITL for bridge)
#   simstim:     COMPLETED | AWAITING_HITL | HALTED
#
# Each test runs the hook from a CLEAN temp CWD so the repo's own
# .run/*-state.json does not pre-empt the checks, seeding its own
# .loa.config.yaml and .run/*-state.json fixtures there. The configured push
# command appends $LOA_PUSH_MESSAGE to ./push.out inside that CWD.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    HOOK="$PROJECT_ROOT/.claude/hooks/safety/run-mode-stop-guard.sh"
    export HOOK
    CLEAN_CWD="$BATS_TEST_TMPDIR/clean"
    mkdir -p "$CLEAN_CWD/.run"
    PUSH_OUT="$CLEAN_CWD/push.out"
    MARKER="$CLEAN_CWD/.run/push-last-state.json"
}

# Write a push-enabled config into the clean CWD. $1 optional command override.
_seed_config() {
    local cmd="${1:-printf \"%s\\n\" \"\$LOA_PUSH_MESSAGE\" >> push.out}"
    cat > "$CLEAN_CWD/.loa.config.yaml" <<YAML
notifications:
  push_command:
    enabled: true
    command: '$cmd'
    timeout_sec: 5
YAML
}

_seed_sprint()  { printf '%s' "$1" > "$CLEAN_CWD/.run/sprint-plan-state.json"; }
_seed_bridge()  { printf '%s' "$1" > "$CLEAN_CWD/.run/bridge-state.json"; }
_seed_simstim() { printf '%s' "$1" > "$CLEAN_CWD/.run/simstim-state.json"; }

# Feed $1 as stdin to the hook, run from the clean CWD; capture output+status.
_run_stop() {
    ( cd "$CLEAN_CWD" && printf '%s' "$1" | "$HOOK" 2>&1 )
}

# --- AC row 1: terminal states push exactly once, naming source + gate -------

@test "AC1 sprint JACKED_OUT → exactly one push naming sprint+gate, <200 chars" {
    _seed_config
    _seed_sprint '{"state":"JACKED_OUT","sprints":{"current":"sprint-7"},"timestamps":{"last_activity":"2026-07-06T00:00:00Z"}}'
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'"decision"'* ]]
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    [ -f "$PUSH_OUT" ]
    [ "$(wc -l < "$PUSH_OUT")" -eq 1 ]
    local line; line="$(cat "$PUSH_OUT")"
    [[ "$line" == *"sprint-7"* ]]
    [[ "$line" == *"JACKED_OUT"* ]]
    [ "${#line}" -lt 200 ]
}

@test "AC1 sprint READY_FOR_HITL → one push" {
    _seed_config
    _seed_sprint '{"state":"READY_FOR_HITL","sprints":{"current":"sprint-3"},"timestamps":{"last_activity":"t1"}}'
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$PUSH_OUT")" -eq 1 ]
    [[ "$(cat "$PUSH_OUT")" == *"READY_FOR_HITL"* ]]
}

@test "AC1 sprint HALTED → one push" {
    _seed_config
    _seed_sprint '{"state":"HALTED","sprints":{"current":"sprint-9"},"timestamps":{"last_activity":"t1"}}'
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$PUSH_OUT")" -eq 1 ]
    [[ "$(cat "$PUSH_OUT")" == *"HALTED"* ]]
}

@test "AC1 bridge JACKED_OUT → one push" {
    _seed_config
    _seed_bridge '{"state":"JACKED_OUT","current_iteration":4,"timestamps":{"last_activity":"t1"}}'
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$PUSH_OUT")" -eq 1 ]
    [[ "$(cat "$PUSH_OUT")" == *"bridge"* ]]
    [[ "$(cat "$PUSH_OUT")" == *"JACKED_OUT"* ]]
}

@test "AC1 bridge HALTED → one push" {
    _seed_config
    _seed_bridge '{"state":"HALTED","current_iteration":2,"timestamps":{"last_activity":"t1"}}'
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$PUSH_OUT")" -eq 1 ]
    [[ "$(cat "$PUSH_OUT")" == *"bridge"* ]]
}

@test "AC1 simstim COMPLETED → one push" {
    _seed_config
    _seed_simstim '{"state":"COMPLETED","phase":"review","timestamps":{"last_activity":"t1"}}'
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$PUSH_OUT")" -eq 1 ]
    [[ "$(cat "$PUSH_OUT")" == *"simstim"* ]]
    [[ "$(cat "$PUSH_OUT")" == *"COMPLETED"* ]]
}

@test "AC1 simstim AWAITING_HITL → one push" {
    _seed_config
    _seed_simstim '{"state":"AWAITING_HITL","phase":"audit","timestamps":{"last_activity":"t1"}}'
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$PUSH_OUT")" -eq 1 ]
    [[ "$(cat "$PUSH_OUT")" == *"AWAITING_HITL"* ]]
}

@test "AC1 simstim HALTED → one push" {
    _seed_config
    _seed_simstim '{"state":"HALTED","phase":"implementation","timestamps":{"last_activity":"t1"}}'
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$PUSH_OUT")" -eq 1 ]
    [[ "$(cat "$PUSH_OUT")" == *"HALTED"* ]]
}

# --- AC row 2: soft-block states never push ----------------------------------

@test "AC2 sprint RUNNING → soft-block, no push" {
    _seed_config
    _seed_sprint '{"state":"RUNNING","sprints":{"current":"sprint-1"},"timestamps":{"last_activity":"t1"}}'
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "block"'* ]]
    [ ! -f "$PUSH_OUT" ]
}

@test "AC2 bridge ITERATING → soft-block, no push" {
    _seed_config
    _seed_bridge '{"state":"ITERATING","current_iteration":1,"timestamps":{"last_activity":"t1"}}'
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "block"'* ]]
    [ ! -f "$PUSH_OUT" ]
}

@test "AC2 simstim RUNNING/implementation → soft-block, no push" {
    _seed_config
    _seed_simstim '{"state":"RUNNING","phase":"implementation","timestamps":{"last_activity":"t1"}}'
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "block"'* ]]
    [ ! -f "$PUSH_OUT" ]
}

# --- AC row 3: unset/disabled/empty command → silent no-op, no slot burned ----

@test "AC3a no config file → silent no-op, no marker, stdout empty" {
    _seed_sprint '{"state":"JACKED_OUT","sprints":{"current":"sprint-7"},"timestamps":{"last_activity":"t1"}}'
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -f "$PUSH_OUT" ]
    [ ! -f "$MARKER" ]
}

@test "AC3b enabled:false → silent no-op, no marker" {
    cat > "$CLEAN_CWD/.loa.config.yaml" <<'YAML'
notifications:
  push_command:
    enabled: false
    command: 'printf x >> push.out'
    timeout_sec: 5
YAML
    _seed_sprint '{"state":"JACKED_OUT","sprints":{"current":"sprint-7"},"timestamps":{"last_activity":"t1"}}'
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -f "$PUSH_OUT" ]
    [ ! -f "$MARKER" ]
}

@test "AC3c enabled:true but empty command → silent no-op, no marker" {
    cat > "$CLEAN_CWD/.loa.config.yaml" <<'YAML'
notifications:
  push_command:
    enabled: true
    command: ""
    timeout_sec: 5
YAML
    _seed_sprint '{"state":"JACKED_OUT","sprints":{"current":"sprint-7"},"timestamps":{"last_activity":"t1"}}'
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -f "$PUSH_OUT" ]
    [ ! -f "$MARKER" ]
}

# --- AC row 4: failed command never changes exit/stdout contract -------------

@test "AC4 failing push command → hook still exit 0, stdout empty, marker written" {
    _seed_config 'exit 1'
    _seed_sprint '{"state":"JACKED_OUT","sprints":{"current":"sprint-7"},"timestamps":{"last_activity":"t1"}}'
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    # marker IS written (attempt counted once) even though the command failed
    [ -f "$MARKER" ]
}

# --- Cross-source dedup regression: stale marker must not mask a new source --

@test "cross-source: stale sprint marker does not mask a fresh bridge gate" {
    _seed_config
    _seed_sprint '{"state":"JACKED_OUT","sprints":{"current":"sprint-7"},"timestamps":{"last_activity":"t1"}}'
    # First Stop pushes the sprint gate and records its marker.
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$PUSH_OUT")" -eq 1 ]
    # A fresh bridge terminal state now appears alongside the (unchanged) sprint.
    _seed_bridge '{"state":"HALTED","current_iteration":3,"timestamps":{"last_activity":"t2"}}'
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    # Bridge push fired despite the stale sprint marker → 2 lines total.
    [ "$(wc -l < "$PUSH_OUT")" -eq 2 ]
    [[ "$(tail -1 "$PUSH_OUT")" == *"bridge"* ]]
}

# --- Precedence: sprint outranks bridge outranks simstim on the same Stop -----

@test "precedence: sprint fires before bridge/simstim on one Stop" {
    _seed_config
    _seed_sprint  '{"state":"JACKED_OUT","sprints":{"current":"sprint-7"},"timestamps":{"last_activity":"t1"}}'
    _seed_bridge  '{"state":"HALTED","current_iteration":1,"timestamps":{"last_activity":"t1"}}'
    _seed_simstim '{"state":"COMPLETED","phase":"review","timestamps":{"last_activity":"t1"}}'
    run _run_stop '{}'
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$PUSH_OUT")" -eq 1 ]
    [[ "$(cat "$PUSH_OUT")" == *"sprint-plan"* ]]
}
