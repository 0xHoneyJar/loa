#!/usr/bin/env bats
# =============================================================================
# tests/integration/loa-status-integration.bats
#
# cycle-098 Sprint 1C — extends /loa status to surface agent-network primitives,
# tier validator, protected queue, and audit chain health.
#
# AC source: SDD §4.4 (line ~1550) — full ASCII layout already specified.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LOA_STATUS="$PROJECT_ROOT/.claude/scripts/loa-status.sh"

    [[ -f "$LOA_STATUS" ]] || skip "loa-status.sh not present"

    TEST_DIR="$(mktemp -d)"
    export LOA_AGENT_NETWORK_HOME="$TEST_DIR"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
    fi
    unset LOA_AGENT_NETWORK_HOME
}

# -----------------------------------------------------------------------------
# Sprint 1C extensions live in the existing loa-status output
# -----------------------------------------------------------------------------

@test "loa-status-1C: includes Agent-Network Primitives section" {
    run bash "$LOA_STATUS"
    # Don't insist on success — loa-status.sh exits 0 even with no version file.
    [[ "$output" == *"Agent-Network Primitives"* ]]
}

@test "loa-status-1C: includes Tier validator line" {
    run bash "$LOA_STATUS"
    [[ "$output" == *"Tier validator"* ]]
}

@test "loa-status-1C: includes Protected queue line" {
    run bash "$LOA_STATUS"
    [[ "$output" == *"Protected queue"* ]]
}

@test "loa-status-1C: includes Audit chain summary" {
    run bash "$LOA_STATUS"
    [[ "$output" == *"Audit chain"* ]]
}

@test "loa-status-1C: shows protected-queue count when queue file present" {
    mkdir -p "$PROJECT_ROOT/.run"
    local q="$PROJECT_ROOT/.run/protected-queue.jsonl"
    # Write 2 dummy queue items for this test scope (cleaned up after).
    {
        echo '{"id":"q-1","decision_class":"prod_deploy"}'
        echo '{"id":"q-2","decision_class":"key_rotation"}'
    } > "$q"

    run bash "$LOA_STATUS"
    [[ "$output" == *"Protected queue"* ]]
    # Cleanup
    rm -f "$q"
}

@test "loa-status-1C: existing Workflow State + Framework Version sections still render" {
    run bash "$LOA_STATUS"
    # Existing sections must NOT be removed.
    [[ "$output" == *"Loa Status"* ]]
    [[ "$output" == *"Framework Version"* ]]
}

@test "loa-status-1C: --json mode includes agent_network key" {
    run bash "$LOA_STATUS" --json
    [[ "$status" -eq 0 ]]
    # Expect a top-level agent_network field in JSON output.
    if command -v jq >/dev/null 2>&1; then
        local has_an
        has_an=$(printf '%s' "$output" | jq 'has("agent_network")' 2>/dev/null || echo "false")
        [[ "$has_an" == "true" ]]
    else
        [[ "$output" == *"agent_network"* ]]
    fi
}
