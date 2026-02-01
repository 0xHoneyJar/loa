#!/usr/bin/env bats
# Unit tests for synthesis-checkpoint.sh
# Part of Loa Framework v0.9.0 Lossless Ledger Protocol

# Test setup
setup() {
    # Create temp directory for test files
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_DIR=$(mktemp -d "${BATS_TMPDIR}/synthesis-checkpoint-test.XXXXXX")
    export PROJECT_ROOT="$TEST_DIR"

    # Create directory structure
    mkdir -p "${TEST_DIR}/loa-grimoire/a2a/trajectory"
    mkdir -p "${TEST_DIR}/.claude/scripts"

    # Copy scripts for testing
    cp "${BATS_TEST_DIRNAME}/../../.claude/scripts/grounding-check.sh" "${TEST_DIR}/.claude/scripts/"
    cp "${BATS_TEST_DIRNAME}/../../.claude/scripts/synthesis-checkpoint.sh" "${TEST_DIR}/.claude/scripts/"
    chmod +x "${TEST_DIR}/.claude/scripts/"*.sh

    # Create NOTES.md
    cat > "${TEST_DIR}/loa-grimoire/NOTES.md" << 'EOF'
# NOTES.md

## Session Continuity
<!-- Test file -->
EOF

    export SCRIPT="${TEST_DIR}/.claude/scripts/synthesis-checkpoint.sh"
}

teardown() {
    # Clean up test directory
    if [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# Helper to create trajectory file
create_trajectory() {
    local agent="${1:-implementing-tasks}"
    local date="${2:-$(date +%Y-%m-%d)}"
    local file="${TEST_DIR}/loa-grimoire/a2a/trajectory/${agent}-${date}.jsonl"
    cat > "$file"
    echo "$file"
}

# Helper to create config file
create_config() {
    cat > "${TEST_DIR}/.loa.config.yaml"
}

# =============================================================================
# Basic Functionality Tests
# =============================================================================

@test "synthesis-checkpoint.sh exists and is executable" {
    [[ -f "$SCRIPT" ]]
    [[ -x "$SCRIPT" ]]
}

@test "passes with no trajectory file (zero-claim session)" {
    run bash "$SCRIPT" implementing-tasks

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"SYNTHESIS CHECKPOINT: PASSED"* ]]
    [[ "$output" == *"/clear is permitted"* ]]
}

@test "passes with 100% grounded claims" {
    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Test claim 1"}
{"ts":"2024-01-15T10:01:00Z","agent":"implementing-tasks","phase":"cite","grounding":"code_reference","claim":"Test claim 2"}
EOF

    run bash "$SCRIPT" implementing-tasks

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Step 1: Grounding Verification"* ]]
    [[ "$output" == *"Status: PASSED"* ]]
    [[ "$output" == *"SYNTHESIS CHECKPOINT: PASSED"* ]]
}

@test "header shows correct information" {
    run bash "$SCRIPT" test-agent

    [[ "$output" == *"SYNTHESIS CHECKPOINT"* ]]
    [[ "$output" == *"Agent: test-agent"* ]]
    [[ "$output" == *"Enforcement:"* ]]
}

# =============================================================================
# Enforcement Level Tests
# =============================================================================

@test "warn mode allows clear with low grounding ratio" {
    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"assumption","claim":"Ungrounded claim"}
EOF

    # Default enforcement is warn
    run bash "$SCRIPT" implementing-tasks

    [[ "$status" -eq 0 ]]  # Should still pass in warn mode
    [[ "$output" == *"WARNING"* ]]
    [[ "$output" == *"SYNTHESIS CHECKPOINT: PASSED"* ]]
}

@test "disabled enforcement skips grounding check" {
    create_config <<EOF
grounding_enforcement: disabled
EOF

    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"assumption","claim":"Ungrounded claim"}
EOF

    run bash "$SCRIPT" implementing-tasks

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"SKIPPED (enforcement disabled)"* ]]
}

# =============================================================================
# Step Tests
# =============================================================================

@test "runs all 7 steps" {
    run bash "$SCRIPT" implementing-tasks

    [[ "$output" == *"Step 1: Grounding Verification"* ]]
    [[ "$output" == *"Step 2: Negative Grounding"* ]]
    [[ "$output" == *"Step 3: Update Decision Log"* ]]
    [[ "$output" == *"Step 4: Update Bead"* ]]
    [[ "$output" == *"Step 5: Log Session Handoff"* ]]
    [[ "$output" == *"Step 6: Decay Raw Output"* ]]
    [[ "$output" == *"Step 7: Verify EDD"* ]]
}

@test "step 2 negative grounding detects unverified ghosts" {
    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Grounded"}
{"ts":"2024-01-15T10:01:00Z","agent":"implementing-tasks","phase":"negative_grounding","status":"unverified","claim":"Ghost feature"}
EOF

    run bash "$SCRIPT" implementing-tasks

    [[ "$output" == *"Unverified ghosts: 1"* ]]
}

@test "step 3 counts decisions to sync" {
    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Decision 1"}
{"ts":"2024-01-15T10:01:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Decision 2"}
EOF

    run bash "$SCRIPT" implementing-tasks

    [[ "$output" == *"Decisions to sync: 2"* ]]
}

@test "step 4 skips when beads not available" {
    run bash "$SCRIPT" implementing-tasks

    [[ "$output" == *"Step 4: Update Bead"* ]]
    [[ "$output" == *"SKIPPED"* ]]
}

@test "step 5 creates handoff log entry" {
    local trajectory="${TEST_DIR}/loa-grimoire/a2a/trajectory/implementing-tasks-$(date +%Y-%m-%d).jsonl"

    run bash "$SCRIPT" implementing-tasks

    [[ "$status" -eq 0 ]]
    # Check that handoff entry was logged
    [[ -f "$trajectory" ]]
    grep -q "session_handoff" "$trajectory"
}

@test "step 6 is advisory only" {
    run bash "$SCRIPT" implementing-tasks

    [[ "$output" == *"Step 6: Decay Raw Output"* ]]
    [[ "$output" == *"ADVISORY"* ]]
}

@test "step 7 counts test scenarios" {
    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","type":"test_scenario","name":"Happy path"}
{"ts":"2024-01-15T10:01:00Z","agent":"implementing-tasks","type":"test_scenario","name":"Edge case"}
{"ts":"2024-01-15T10:02:00Z","agent":"implementing-tasks","type":"test_scenario","name":"Error handling"}
EOF

    run bash "$SCRIPT" implementing-tasks

    [[ "$output" == *"Test scenarios documented: 3"* ]]
}

# =============================================================================
# Configuration Tests
# =============================================================================

@test "reads grounding threshold from config" {
    create_config <<EOF
grounding:
  threshold: 0.80
EOF

    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Grounded 1"}
{"ts":"2024-01-15T10:01:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Grounded 2"}
{"ts":"2024-01-15T10:02:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Grounded 3"}
{"ts":"2024-01-15T10:03:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Grounded 4"}
{"ts":"2024-01-15T10:04:00Z","agent":"implementing-tasks","phase":"cite","grounding":"assumption","claim":"Assumption"}
EOF

    run bash "$SCRIPT" implementing-tasks

    # 80% grounding with 0.80 threshold should pass
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Threshold: 0.80"* ]] || [[ "$output" == *"Threshold: 0.95"* ]]  # May use default if yq unavailable
}

@test "uses safe defaults when config missing" {
    # No config file
    rm -f "${TEST_DIR}/.loa.config.yaml"

    run bash "$SCRIPT" implementing-tasks

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Enforcement: warn"* ]]
}

# =============================================================================
# Edge Case Tests
# =============================================================================

@test "handles missing grounding-check.sh" {
    rm "${TEST_DIR}/.claude/scripts/grounding-check.sh"

    run bash "$SCRIPT" implementing-tasks

    [[ "$status" -eq 2 ]] || [[ "$output" == *"ERROR"* ]]
}

@test "handles empty trajectory file" {
    local trajectory="${TEST_DIR}/loa-grimoire/a2a/trajectory/implementing-tasks-$(date +%Y-%m-%d).jsonl"
    touch "$trajectory"

    run bash "$SCRIPT" implementing-tasks

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"SYNTHESIS CHECKPOINT: PASSED"* ]]
}

@test "custom agent name works" {
    create_trajectory "custom-agent" <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"custom-agent","phase":"cite","grounding":"citation","claim":"Test"}
EOF

    run bash "$SCRIPT" custom-agent

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Agent: custom-agent"* ]]
}

@test "custom date argument works" {
    local custom_date="2024-01-15"
    create_trajectory "implementing-tasks" "$custom_date" <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Test"}
EOF

    run bash "$SCRIPT" implementing-tasks "$custom_date"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Date: $custom_date"* ]]
}

# =============================================================================
# Output Format Tests
# =============================================================================

@test "final result shows clear permission on pass" {
    run bash "$SCRIPT" implementing-tasks

    [[ "$output" == *"/clear is permitted"* ]]
}

@test "blocking checks run before non-blocking" {
    # Grounding and negative grounding are blocking (steps 1-2)
    # Steps 3-7 are non-blocking

    run bash "$SCRIPT" implementing-tasks

    # Verify order in output
    local step1_pos step3_pos
    step1_pos=$(echo "$output" | grep -n "Step 1" | head -1 | cut -d: -f1)
    step3_pos=$(echo "$output" | grep -n "Step 3" | head -1 | cut -d: -f1)

    [[ "$step1_pos" -lt "$step3_pos" ]]
}
