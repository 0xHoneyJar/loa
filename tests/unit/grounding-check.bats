#!/usr/bin/env bats
# Unit tests for grounding-check.sh
# Part of Loa Framework v0.9.0 Lossless Ledger Protocol

# Test setup
setup() {
    # Create temp directory for test files
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_DIR=$(mktemp -d "${BATS_TMPDIR}/grounding-check-test.XXXXXX")
    export PROJECT_ROOT="$TEST_DIR"

    # Create trajectory directory
    mkdir -p "${TEST_DIR}/loa-grimoire/a2a/trajectory"

    # Store original PATH
    export ORIGINAL_PATH="$PATH"

    # Create script copy for testing
    export SCRIPT="${BATS_TEST_DIRNAME}/../../.claude/scripts/grounding-check.sh"
}

teardown() {
    # Clean up test directory
    if [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi

    # Restore PATH
    export PATH="$ORIGINAL_PATH"
}

# Helper to create trajectory file
create_trajectory() {
    local agent="${1:-implementing-tasks}"
    local date="${2:-$(date +%Y-%m-%d)}"
    local file="${TEST_DIR}/loa-grimoire/a2a/trajectory/${agent}-${date}.jsonl"
    cat > "$file"
    echo "$file"
}

# =============================================================================
# Basic Functionality Tests
# =============================================================================

@test "grounding-check.sh exists and is executable" {
    [[ -f "$SCRIPT" ]]
    [[ -x "$SCRIPT" ]] || chmod +x "$SCRIPT"
}

@test "zero-claim session returns ratio 1.00 and passes" {
    # No trajectory file = zero claims
    run bash "$SCRIPT" implementing-tasks 0.95

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"grounding_ratio=1.00"* ]]
    [[ "$output" == *"status=pass"* ]]
    [[ "$output" == *"zero-claim"* ]] || [[ "$output" == *"Zero-claim"* ]]
}

@test "100% grounded claims returns ratio 1.00 and passes" {
    # Create trajectory with all grounded claims
    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"API uses REST"}
{"ts":"2024-01-15T10:01:00Z","agent":"implementing-tasks","phase":"cite","grounding":"code_reference","claim":"Auth in jwt.ts"}
{"ts":"2024-01-15T10:02:00Z","agent":"implementing-tasks","phase":"cite","grounding":"user_input","claim":"User wants dark mode"}
EOF

    run bash "$SCRIPT" implementing-tasks 0.95

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"total_claims=3"* ]]
    [[ "$output" == *"grounded_claims=3"* ]]
    [[ "$output" == *"grounding_ratio=1.00"* ]]
    [[ "$output" == *"status=pass"* ]]
}

@test "50% grounded claims returns ratio 0.50 and fails with 0.95 threshold" {
    # Create trajectory with mixed claims
    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"API documented"}
{"ts":"2024-01-15T10:01:00Z","agent":"implementing-tasks","phase":"cite","grounding":"assumption","claim":"Probably uses OAuth"}
EOF

    run bash "$SCRIPT" implementing-tasks 0.95

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"total_claims=2"* ]]
    [[ "$output" == *"grounded_claims=1"* ]]
    [[ "$output" == *"assumptions=1"* ]]
    [[ "$output" == *"grounding_ratio=0.50"* ]]
    [[ "$output" == *"status=fail"* ]]
}

@test "ratio exactly at threshold passes" {
    # Create trajectory with exactly 95% grounded (19/20)
    local file="${TEST_DIR}/loa-grimoire/a2a/trajectory/implementing-tasks-$(date +%Y-%m-%d).jsonl"

    # 19 grounded claims
    for i in {1..19}; do
        echo '{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Claim '$i'"}' >> "$file"
    done
    # 1 assumption
    echo '{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"assumption","claim":"Assumption 1"}' >> "$file"

    run bash "$SCRIPT" implementing-tasks 0.95

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"total_claims=20"* ]]
    [[ "$output" == *"grounded_claims=19"* ]]
    [[ "$output" == *"status=pass"* ]]
}

# =============================================================================
# Argument Handling Tests
# =============================================================================

@test "custom agent name is used correctly" {
    # Create trajectory for custom agent
    create_trajectory "custom-agent" <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"custom-agent","phase":"cite","grounding":"citation","claim":"Test claim"}
EOF

    run bash "$SCRIPT" custom-agent 0.95

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"total_claims=1"* ]]
}

@test "custom threshold is respected" {
    # Create trajectory with 80% grounding
    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Claim 1"}
{"ts":"2024-01-15T10:01:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Claim 2"}
{"ts":"2024-01-15T10:02:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Claim 3"}
{"ts":"2024-01-15T10:03:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Claim 4"}
{"ts":"2024-01-15T10:04:00Z","agent":"implementing-tasks","phase":"cite","grounding":"assumption","claim":"Assumption 1"}
EOF

    # 80% should fail with 0.95 threshold
    run bash "$SCRIPT" implementing-tasks 0.95
    [[ "$status" -eq 1 ]]

    # 80% should pass with 0.80 threshold
    run bash "$SCRIPT" implementing-tasks 0.80
    [[ "$status" -eq 0 ]]
}

@test "invalid threshold returns exit code 2" {
    run bash "$SCRIPT" implementing-tasks "not-a-number"

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"error=invalid_threshold"* ]]
}

# =============================================================================
# Edge Case Tests
# =============================================================================

@test "handles empty trajectory file gracefully" {
    # Create empty trajectory file
    local file="${TEST_DIR}/loa-grimoire/a2a/trajectory/implementing-tasks-$(date +%Y-%m-%d).jsonl"
    touch "$file"

    run bash "$SCRIPT" implementing-tasks 0.95

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"total_claims=0"* ]]
    [[ "$output" == *"grounding_ratio=1.00"* ]]
    [[ "$output" == *"status=pass"* ]]
}

@test "handles trajectory with non-cite phases" {
    # Create trajectory with mixed phases (only cite phases count as claims)
    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"This counts"}
{"ts":"2024-01-15T10:01:00Z","agent":"implementing-tasks","phase":"execute","action":"write_file","file":"test.ts"}
{"ts":"2024-01-15T10:02:00Z","agent":"implementing-tasks","phase":"reason","thought":"Thinking about design"}
EOF

    run bash "$SCRIPT" implementing-tasks 0.95

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"total_claims=1"* ]]  # Only the cite phase counts
    [[ "$output" == *"grounded_claims=1"* ]]
}

@test "handles malformed JSON lines gracefully" {
    # Create trajectory with some malformed lines
    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Valid claim"}
this is not valid json
{"ts":"2024-01-15T10:02:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Another valid"}
EOF

    run bash "$SCRIPT" implementing-tasks 0.95

    # Should still work - grep counts pattern matches, not JSON validity
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"total_claims=2"* ]]
}

@test "custom date argument works correctly" {
    # Create trajectory for specific date
    local custom_date="2024-01-15"
    create_trajectory implementing-tasks "$custom_date" <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Test claim"}
EOF

    run bash "$SCRIPT" implementing-tasks 0.95 "$custom_date"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"total_claims=1"* ]]
}

# =============================================================================
# Grounding Type Tests
# =============================================================================

@test "citation type is counted as grounded" {
    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"From docs"}
EOF

    run bash "$SCRIPT" implementing-tasks 0.95

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"grounded_citations=1"* ]]
    [[ "$output" == *"grounded_claims=1"* ]]
}

@test "code_reference type is counted as grounded" {
    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"code_reference","claim":"From code"}
EOF

    run bash "$SCRIPT" implementing-tasks 0.95

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"grounded_references=1"* ]]
    [[ "$output" == *"grounded_claims=1"* ]]
}

@test "user_input type is counted as grounded" {
    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"user_input","claim":"User said X"}
EOF

    run bash "$SCRIPT" implementing-tasks 0.95

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"grounded_user_input=1"* ]]
    [[ "$output" == *"grounded_claims=1"* ]]
}

@test "assumption type is counted as ungrounded" {
    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"assumption","claim":"I assume X"}
EOF

    run bash "$SCRIPT" implementing-tasks 0.95

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"assumptions=1"* ]]
    [[ "$output" == *"grounded_claims=0"* ]]
    [[ "$output" == *"status=fail"* ]]
}

# =============================================================================
# Output Format Tests
# =============================================================================

@test "output contains all required fields" {
    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Test"}
EOF

    run bash "$SCRIPT" implementing-tasks 0.95

    [[ "$output" == *"total_claims="* ]]
    [[ "$output" == *"grounded_claims="* ]]
    [[ "$output" == *"grounding_ratio="* ]]
    [[ "$output" == *"status="* ]]
    [[ "$output" == *"message="* ]]
}

@test "failing output lists ungrounded claims" {
    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"assumption","claim":"Unknown claim here"}
EOF

    run bash "$SCRIPT" implementing-tasks 0.95

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"ungrounded_claims:"* ]]
}
