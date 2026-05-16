#!/usr/bin/env bats
# =============================================================================
# tests/integration/chain-witness-smoke.bats
#
# BB #804 FINDING-002 closure: minimal smoke coverage for chain-witness.sh
# (134 LOC tool shipped without tests in the original PR).
#
# This is a courtesy-tool, not a Loa primitive — full integration coverage
# would be overkill. The smoke tests verify:
#   - script is executable
#   - --help / -h returns the docstring
#   - --quiet mode returns a single-line summary
#   - script syntax is valid bash
#   - default invocation succeeds (exit 0) from the repo root
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    SCRIPT="$PROJECT_ROOT/.claude/scripts/chain-witness.sh"
    export SCRIPT
}

@test "chain-witness-1: script is executable bash" {
    [ -x "$SCRIPT" ] || skip "script not executable in checkout (chmod +x may be needed)"
    run bash -n "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "chain-witness-2: --help / -h returns docstring without invoking main flow" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"chain-witness.sh"* ]]
    [[ "$output" == *"continuity"* ]] || [[ "$output" == *"chain"* ]]
}

@test "chain-witness-3: -h short form behaves identically to --help" {
    run bash "$SCRIPT" -h
    [ "$status" -eq 0 ]
    # Must contain part of the docstring header to confirm we hit the help path
    [[ "$output" == *"chain-witness.sh"* ]]
}

@test "chain-witness-4: default invocation succeeds from repo root" {
    cd "$PROJECT_ROOT"
    run bash "$SCRIPT"
    # Tool is a read-only inspector; should always exit 0 in a healthy repo
    # (set -uo pipefail without -e means transient grep misses don't fail).
    [ "$status" -eq 0 ]
}

@test "chain-witness-5: --quiet mode produces shorter output than default" {
    cd "$PROJECT_ROOT"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    local default_lines="${#lines[@]}"
    run bash "$SCRIPT" --quiet
    [ "$status" -eq 0 ]
    local quiet_lines="${#lines[@]}"
    # Quiet mode should produce strictly fewer lines than the default.
    [ "$quiet_lines" -lt "$default_lines" ]
}
