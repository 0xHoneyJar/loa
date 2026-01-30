#!/usr/bin/env bats
# Tests for early-exit.sh - Early-exit coordination protocol

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    EARLY_EXIT="$PROJECT_ROOT/.claude/scripts/early-exit.sh"

    # Create temp directory for test early-exit files
    TEST_EXIT_DIR="$(mktemp -d)"
    export EARLY_EXIT_DIR="$TEST_EXIT_DIR"

    # Test session ID
    SESSION_ID="test-session-$$"
}

teardown() {
    rm -rf "$TEST_EXIT_DIR"
}

@test "early-exit.sh exists and is executable" {
    [[ -x "$EARLY_EXIT" ]]
}

@test "early-exit.sh shows help with --help" {
    run "$EARLY_EXIT" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Early Exit"* ]]
}

@test "cleanup creates clean session state" {
    run "$EARLY_EXIT" cleanup "$SESSION_ID"
    [[ "$status" -eq 0 ]]
}

@test "check returns 0 when no exit signaled" {
    "$EARLY_EXIT" cleanup "$SESSION_ID"

    run "$EARLY_EXIT" check "$SESSION_ID"
    [[ "$status" -eq 0 ]]
}

@test "check returns 1 when exit signaled" {
    "$EARLY_EXIT" cleanup "$SESSION_ID"
    "$EARLY_EXIT" signal "$SESSION_ID" "test-agent"

    run "$EARLY_EXIT" check "$SESSION_ID"
    [[ "$status" -eq 1 ]]
}

@test "signal creates winner marker" {
    "$EARLY_EXIT" cleanup "$SESSION_ID"

    run "$EARLY_EXIT" signal "$SESSION_ID" "agent-1"
    [[ "$status" -eq 0 ]]

    # Check WINNER directory was created
    [[ -d "$EARLY_EXIT_DIR/$SESSION_ID/WINNER" ]]

    # Check winner agent recorded
    [[ -f "$EARLY_EXIT_DIR/$SESSION_ID/winner_agent" ]]
    run cat "$EARLY_EXIT_DIR/$SESSION_ID/winner_agent"
    [[ "$output" == "agent-1" ]]
}

@test "signal is atomic - second signal fails" {
    "$EARLY_EXIT" cleanup "$SESSION_ID"

    run "$EARLY_EXIT" signal "$SESSION_ID" "agent-1"
    [[ "$status" -eq 0 ]]

    run "$EARLY_EXIT" signal "$SESSION_ID" "agent-2"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"already signaled"* ]]
}

@test "register adds agent to session" {
    "$EARLY_EXIT" cleanup "$SESSION_ID"

    run "$EARLY_EXIT" register "$SESSION_ID" "agent-1"
    [[ "$status" -eq 0 ]]

    [[ -f "$EARLY_EXIT_DIR/$SESSION_ID/agents/agent-1" ]]
}

@test "write-result stores agent result" {
    "$EARLY_EXIT" cleanup "$SESSION_ID"
    "$EARLY_EXIT" register "$SESSION_ID" "agent-1"

    run bash -c "echo '{\"result\": \"success\"}' | $EARLY_EXIT write-result $SESSION_ID agent-1"
    [[ "$status" -eq 0 ]]

    [[ -f "$EARLY_EXIT_DIR/$SESSION_ID/results/agent-1.json" ]]
}

@test "read-winner returns winner result" {
    "$EARLY_EXIT" cleanup "$SESSION_ID"
    "$EARLY_EXIT" register "$SESSION_ID" "agent-1"
    "$EARLY_EXIT" signal "$SESSION_ID" "agent-1"
    echo '{"result": "found it"}' | "$EARLY_EXIT" write-result "$SESSION_ID" "agent-1"

    run "$EARLY_EXIT" read-winner "$SESSION_ID"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"result": "found it"'* ]]
}

@test "read-winner with --json includes metadata" {
    "$EARLY_EXIT" cleanup "$SESSION_ID"
    "$EARLY_EXIT" register "$SESSION_ID" "agent-1"
    "$EARLY_EXIT" signal "$SESSION_ID" "agent-1"
    echo '{"data": 123}' | "$EARLY_EXIT" write-result "$SESSION_ID" "agent-1"

    run "$EARLY_EXIT" read-winner "$SESSION_ID" --json
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"session_id"'* ]]
    [[ "$output" == *'"winner_agent": "agent-1"'* ]]
    [[ "$output" == *'"result"'* ]]
}

@test "status shows session state" {
    "$EARLY_EXIT" cleanup "$SESSION_ID"
    "$EARLY_EXIT" register "$SESSION_ID" "agent-1"
    "$EARLY_EXIT" register "$SESSION_ID" "agent-2"

    run "$EARLY_EXIT" status "$SESSION_ID" --json
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"signaled": false'* ]]
    [[ "$output" == *'"registered_agents"'* ]]
}

@test "status shows signaled state after signal" {
    "$EARLY_EXIT" cleanup "$SESSION_ID"
    "$EARLY_EXIT" register "$SESSION_ID" "agent-1"
    "$EARLY_EXIT" signal "$SESSION_ID" "agent-1"

    run "$EARLY_EXIT" status "$SESSION_ID" --json
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"signaled": true'* ]]
    [[ "$output" == *'"winner_agent": "agent-1"'* ]]
}

@test "cleanup removes all session files" {
    # Create session with data
    "$EARLY_EXIT" cleanup "$SESSION_ID"
    "$EARLY_EXIT" register "$SESSION_ID" "agent-1"
    "$EARLY_EXIT" signal "$SESSION_ID" "agent-1"
    echo '{"test": true}' | "$EARLY_EXIT" write-result "$SESSION_ID" "agent-1"

    # Verify files exist
    [[ -d "$EARLY_EXIT_DIR/$SESSION_ID" ]]

    # Cleanup
    run "$EARLY_EXIT" cleanup "$SESSION_ID"
    [[ "$status" -eq 0 ]]

    # Verify files removed
    [[ ! -d "$EARLY_EXIT_DIR/$SESSION_ID" ]]
}

@test "check with --json returns structured output" {
    "$EARLY_EXIT" cleanup "$SESSION_ID"

    run "$EARLY_EXIT" check "$SESSION_ID" --json
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"signaled": false'* ]]
    [[ "$output" == *'"session_id"'* ]]
}

@test "multiple agents can register" {
    "$EARLY_EXIT" cleanup "$SESSION_ID"

    "$EARLY_EXIT" register "$SESSION_ID" "agent-1"
    "$EARLY_EXIT" register "$SESSION_ID" "agent-2"
    "$EARLY_EXIT" register "$SESSION_ID" "agent-3"

    run "$EARLY_EXIT" status "$SESSION_ID" --json
    [[ "$status" -eq 0 ]]

    # Check all agents registered
    echo "$output" | jq -e '.registered_agents | length >= 3'
}
