#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-114-session-title.bats
#
# Cycle-114 FR-9 — SessionStart sessionTitle run-mode recovery hook.
# The hook emits hookSpecificOutput.sessionTitle when a run is active, and is
# silent (exit 0, no output) when jacked-out/absent. Fail-open on malformed JSON.
#
# Runs the hook against a synthetic REPO_ROOT (BATS_TEST_TMPDIR) so the repo's
# own .run/ state does not influence the result.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    HOOK="$PROJECT_ROOT/.claude/hooks/session-start/loa-run-mode-session-title.sh"
    # Synthetic repo root: copy the hook into a tmp tree so REPO_ROOT resolves
    # to BATS_TEST_TMPDIR (hook derives REPO_ROOT from its own location).
    FAKE_ROOT="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$FAKE_ROOT/.claude/hooks/session-start" "$FAKE_ROOT/.run"
    cp "$HOOK" "$FAKE_ROOT/.claude/hooks/session-start/"
    FAKE_HOOK="$FAKE_ROOT/.claude/hooks/session-start/$(basename "$HOOK")"
}

@test "c114-FR9: RUNNING sprint-plan → sessionTitle emitted" {
    printf '{"state":"RUNNING","sprints":{"current":"sprint-3"}}' > "$FAKE_ROOT/.run/sprint-plan-state.json"
    run "$FAKE_HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sessionTitle"* ]]
    [[ "$output" == *"sprint-plan RUNNING"* ]]
    [[ "$output" == *"sprint-3"* ]]
}

@test "c114-FR9: HALTED sprint-plan → sessionTitle emitted" {
    printf '{"state":"HALTED","sprints":{"current":"sprint-2"}}' > "$FAKE_ROOT/.run/sprint-plan-state.json"
    run "$FAKE_HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sprint-plan HALTED"* ]]
}

@test "c114-FR9: JACKED_OUT sprint-plan → silent (no title)" {
    printf '{"state":"JACKED_OUT","sprints":{"current":"sprint-3"}}' > "$FAKE_ROOT/.run/sprint-plan-state.json"
    run "$FAKE_HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"sessionTitle"* ]]
}

@test "c114-FR9: bridge ITERATING → sessionTitle emitted" {
    printf '{"state":"ITERATING","current_iteration":2}' > "$FAKE_ROOT/.run/bridge-state.json"
    run "$FAKE_HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"bridge ITERATING"* ]]
}

@test "c114-FR9: simstim RUNNING → sessionTitle emitted" {
    printf '{"state":"RUNNING","phase":"implementation"}' > "$FAKE_ROOT/.run/simstim-state.json"
    run "$FAKE_HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"simstim RUNNING"* ]]
    [[ "$output" == *"implementation"* ]]
}

@test "c114-FR9: no state files → silent" {
    run "$FAKE_HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "c114-FR9: malformed JSON → fail-open (silent, exit 0)" {
    printf 'not-json{{{' > "$FAKE_ROOT/.run/sprint-plan-state.json"
    run "$FAKE_HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"sessionTitle"* ]]
}

@test "c114-FR9: emitted sessionTitle is valid JSON" {
    printf '{"state":"RUNNING","sprints":{"current":"sprint-1"}}' > "$FAKE_ROOT/.run/sprint-plan-state.json"
    run "$FAKE_HOOK"
    echo "$output" | jq -e '.hookSpecificOutput.sessionTitle' >/dev/null
}
