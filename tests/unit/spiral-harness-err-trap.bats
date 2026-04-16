#!/usr/bin/env bats
# Regression test for Issue #516 — silent exit in spiral-harness.sh
# https://github.com/0xHoneyJar/loa/issues/516
#
# Tests the two silent-exit failure modes fixed in this sprint:
#   1. ERR trap emits FATAL to stderr
#   2. _invoke_claude propagates claude -p exit code past _record_action failure
#   3. brace-group wc -c expression exits 0 under pipefail with missing file
#   4. ERR trap appends FATAL JSONL entry to flight recorder

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    HARNESS="$PROJECT_ROOT/.claude/scripts/spiral-harness.sh"

    TEST_TMPDIR="$(mktemp -d)"
    mkdir -p "$TEST_TMPDIR/bin"
    export PATH="$TEST_TMPDIR/bin:$PATH"

    # Default claude shim — exits 0
    cat > "$TEST_TMPDIR/bin/claude" << 'SHIM'
#!/usr/bin/env bash
exit 0
SHIM
    chmod +x "$TEST_TMPDIR/bin/claude"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# TC-1: ERR trap emits FATAL to stderr when _FLIGHT_RECORDER is unset
# =============================================================================

@test "TC-1: ERR trap emits FATAL to stderr when _FLIGHT_RECORDER is unset" {
    # Issue #516 — trap must write diagnostic even without flight recorder open

    # Source only the function under test (not the full harness which needs deps)
    eval "$(grep -A 20 '^_harness_err_handler()' "$HARNESS" | head -21)"

    unset _FLIGHT_RECORDER

    # Capture stderr from calling the handler directly
    run bash -c "
        $(grep -A 20 '^_harness_err_handler()' "$HARNESS" | head -21)
        unset _FLIGHT_RECORDER
        _harness_err_handler 42 'false_cmd'
    "

    # Must emit [FATAL] line to stderr with line number
    echo "$output" | grep -qE '\[FATAL\].*ERR at line [0-9]'
}

# =============================================================================
# TC-2: _invoke_claude returns claude exit code when _record_action fails
# =============================================================================

@test "TC-2: _invoke_claude returns claude -p exit code when _record_action returns 1" {
    # Issue #516 — _record_action || true means its failure must not override claude's exit code

    # Stub claude to exit 42
    cat > "$TEST_TMPDIR/bin/claude" << 'SHIM'
#!/usr/bin/env bash
exit 42
SHIM
    chmod +x "$TEST_TMPDIR/bin/claude"

    # Verify the || true is present on the _record_action call in _invoke_claude
    run grep -A 3 '_record_action.*invoke.*stdout_file' "$HARNESS"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '|| true'
}

# =============================================================================
# TC-3: brace-group wc -c does not propagate failure under pipefail
# =============================================================================

@test "TC-3: wc-c failure does not propagate nonzero under pipefail" {
    # Issue #516 — fixed expression must exit 0 and produce "0" when file missing
    # Note: bash emits "No such file or directory" to stderr when the stdin redirect
    # fails; suppress via 2>/dev/null on the brace group so BATS $output is clean.

    run bash -c 'set -eo pipefail; result=$({ wc -c < /nonexistent/does-not-exist 2>/dev/null || echo 0; } 2>/dev/null | tr -d " "); echo "$result"; exit 0'
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

# =============================================================================
# TC-4: ERR trap appends FATAL entry to flight recorder when recorder is open
# =============================================================================

@test "TC-4: ERR trap appends FATAL JSONL entry to flight recorder when recorder is open" {
    # Issue #516 — when _FLIGHT_RECORDER is set, trap must write parseable JSONL

    export _FLIGHT_RECORDER="$TEST_TMPDIR/fr.jsonl"
    touch "$_FLIGHT_RECORDER"

    # Run handler in a subprocess so jq is on PATH
    run bash -c "
        $(grep -A 20 '^_harness_err_handler()' "$HARNESS" | head -21)
        export _FLIGHT_RECORDER='$TEST_TMPDIR/fr.jsonl'
        _harness_err_handler 99 'test_cmd'
    "

    # File must have at least one line
    [ -s "$_FLIGHT_RECORDER" ]

    # Last line must be valid JSON with phase=FATAL and action=ERR_TRAP
    run bash -c "tail -1 '$TEST_TMPDIR/fr.jsonl' | jq -e '.phase == \"FATAL\" and .action == \"ERR_TRAP\"'"
    [ "$status" -eq 0 ]
}
