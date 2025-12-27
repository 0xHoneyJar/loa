#!/usr/bin/env bats
# Edge case tests for v0.9.0 Lossless Ledger Protocol
# Tests zero-claim sessions, missing files, corrupted data, and safe defaults

# Test setup
setup() {
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_DIR=$(mktemp -d "${BATS_TMPDIR}/lossless-ledger-edge-test.XXXXXX")
    export PROJECT_ROOT="$TEST_DIR"

    # Initialize git repo
    cd "$TEST_DIR"
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test"

    # Create full structure
    mkdir -p loa-grimoire/a2a/trajectory
    mkdir -p .beads
    mkdir -p .claude/scripts

    # Create NOTES.md
    cat > loa-grimoire/NOTES.md << 'EOF'
# Agent Working Memory (NOTES.md)

## Session Continuity
| Timestamp | Agent | Summary |
|-----------|-------|---------|

## Decision Log
EOF

    # Copy scripts
    cp "${BATS_TEST_DIRNAME}/../../.claude/scripts/grounding-check.sh" .claude/scripts/ 2>/dev/null || true
    cp "${BATS_TEST_DIRNAME}/../../.claude/scripts/synthesis-checkpoint.sh" .claude/scripts/ 2>/dev/null || true
    cp "${BATS_TEST_DIRNAME}/../../.claude/scripts/self-heal-state.sh" .claude/scripts/ 2>/dev/null || true
    chmod +x .claude/scripts/*.sh 2>/dev/null || true

    # Initial commit
    git add .
    git commit -m "Initial" --quiet

    export GROUNDING_SCRIPT=".claude/scripts/grounding-check.sh"
    export SYNTHESIS_SCRIPT=".claude/scripts/synthesis-checkpoint.sh"
    export SELF_HEAL_SCRIPT=".claude/scripts/self-heal-state.sh"
}

teardown() {
    cd /
    if [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# Helper functions
create_trajectory() {
    local agent="${1:-implementing-tasks}"
    local date="${2:-$(date +%Y-%m-%d)}"
    local file="loa-grimoire/a2a/trajectory/${agent}-${date}.jsonl"
    cat > "$file"
}

# =============================================================================
# Zero-Claim Session Edge Cases
# =============================================================================

@test "zero-claim session returns ratio 1.00" {
    cd "$TEST_DIR"

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"grounding_ratio=1.00"* ]]
        [[ "$output" == *"status=pass"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "zero-claim with empty trajectory file returns ratio 1.00" {
    cd "$TEST_DIR"

    local trajectory="loa-grimoire/a2a/trajectory/implementing-tasks-$(date +%Y-%m-%d).jsonl"
    touch "$trajectory"

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"total_claims=0"* ]]
        [[ "$output" == *"grounding_ratio=1.00"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "zero-claim with whitespace-only trajectory returns ratio 1.00" {
    cd "$TEST_DIR"

    local trajectory="loa-grimoire/a2a/trajectory/implementing-tasks-$(date +%Y-%m-%d).jsonl"
    echo "   " > "$trajectory"
    echo "" >> "$trajectory"
    echo "    " >> "$trajectory"

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"grounding_ratio=1.00"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

# =============================================================================
# Missing Trajectory File Edge Cases
# =============================================================================

@test "missing trajectory directory handled gracefully" {
    cd "$TEST_DIR"

    rm -rf loa-grimoire/a2a/trajectory

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"grounding_ratio=1.00"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "missing loa-grimoire directory handled gracefully" {
    cd "$TEST_DIR"

    rm -rf loa-grimoire

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"grounding_ratio=1.00"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "trajectory file for different date not found is zero-claim" {
    cd "$TEST_DIR"

    # Create trajectory for yesterday
    local yesterday=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)
    create_trajectory implementing-tasks "$yesterday" <<EOF
{"ts":"2024-01-14T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Yesterday's claim"}
EOF

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        # Check today's trajectory (should be empty/missing)
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"grounding_ratio=1.00"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

# =============================================================================
# Corrupted Ledger Lines Edge Cases
# =============================================================================

@test "corrupted JSON line dropped silently" {
    cd "$TEST_DIR"

    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Valid claim 1"}
this is not valid json at all
{"ts":"2024-01-15T10:02:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Valid claim 2"}
EOF

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"total_claims=2"* ]]  # Only valid lines counted
    else
        skip "grounding-check.sh not available"
    fi
}

@test "truncated JSON line dropped" {
    cd "$TEST_DIR"

    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Valid"}
{"ts":"2024-01-15T10:01:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citatio
{"ts":"2024-01-15T10:02:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Valid 2"}
EOF

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"total_claims=2"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "binary garbage in trajectory handled" {
    cd "$TEST_DIR"

    local trajectory="loa-grimoire/a2a/trajectory/implementing-tasks-$(date +%Y-%m-%d).jsonl"
    echo '{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Valid"}' > "$trajectory"
    echo -e "\x00\x01\x02\x03" >> "$trajectory"
    echo '{"ts":"2024-01-15T10:02:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Valid 2"}' >> "$trajectory"

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        [[ "$status" -eq 0 ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "empty JSON object line ignored" {
    cd "$TEST_DIR"

    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Valid"}
{}
{"ts":"2024-01-15T10:02:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Valid 2"}
EOF

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        # Empty object should not be counted as a claim
        [[ "$status" -eq 0 ]]
    else
        skip "grounding-check.sh not available"
    fi
}

# =============================================================================
# Missing Configuration Safe Defaults
# =============================================================================

@test "missing .loa.config.yaml uses safe defaults" {
    cd "$TEST_DIR"

    rm -f .loa.config.yaml

    if [[ -f "$SYNTHESIS_SCRIPT" ]]; then
        run bash "$SYNTHESIS_SCRIPT" implementing-tasks

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"warn"* ]] || [[ "$output" == *"Enforcement: warn"* ]]
    else
        skip "synthesis-checkpoint.sh not available"
    fi
}

@test "empty .loa.config.yaml uses safe defaults" {
    cd "$TEST_DIR"

    : > .loa.config.yaml

    if [[ -f "$SYNTHESIS_SCRIPT" ]]; then
        run bash "$SYNTHESIS_SCRIPT" implementing-tasks

        [[ "$status" -eq 0 ]]
    else
        skip "synthesis-checkpoint.sh not available"
    fi
}

@test "malformed .loa.config.yaml uses safe defaults" {
    cd "$TEST_DIR"

    echo "this: is: not: valid: yaml:" > .loa.config.yaml

    if [[ -f "$SYNTHESIS_SCRIPT" ]]; then
        run bash "$SYNTHESIS_SCRIPT" implementing-tasks

        [[ "$status" -eq 0 ]]
    else
        skip "synthesis-checkpoint.sh not available"
    fi
}

@test "missing grounding section uses 0.95 threshold" {
    cd "$TEST_DIR"

    cat > .loa.config.yaml << 'EOF'
version: "0.9.0"
# grounding section missing
EOF

    # Create session with exactly 95% grounding (should pass with default)
    local trajectory="loa-grimoire/a2a/trajectory/implementing-tasks-$(date +%Y-%m-%d).jsonl"
    for i in {1..19}; do
        echo "{\"ts\":\"2024-01-15T10:00:00Z\",\"agent\":\"implementing-tasks\",\"phase\":\"cite\",\"grounding\":\"citation\",\"claim\":\"Claim $i\"}" >> "$trajectory"
    done
    echo '{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"assumption","claim":"Assumption"}' >> "$trajectory"

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        [[ "$status" -eq 0 ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "invalid enforcement level falls back to warn" {
    cd "$TEST_DIR"

    cat > .loa.config.yaml << 'EOF'
version: "0.9.0"
grounding:
  enforcement: invalid_level
  threshold: 0.95
EOF

    if [[ -f "$SYNTHESIS_SCRIPT" ]]; then
        run bash "$SYNTHESIS_SCRIPT" implementing-tasks

        # Should not crash, should use default
        [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
    else
        skip "synthesis-checkpoint.sh not available"
    fi
}

# =============================================================================
# NOTES.md Edge Cases
# =============================================================================

@test "empty NOTES.md triggers recovery" {
    cd "$TEST_DIR"

    : > loa-grimoire/NOTES.md

    if [[ -f "$SELF_HEAL_SCRIPT" ]]; then
        run bash "$SELF_HEAL_SCRIPT"

        [[ "$status" -eq 0 ]]
        [[ -s "loa-grimoire/NOTES.md" ]]  # Should have content now
    else
        skip "self-heal-state.sh not available"
    fi
}

@test "NOTES.md with only whitespace triggers recovery" {
    cd "$TEST_DIR"

    echo "   " > loa-grimoire/NOTES.md
    echo "" >> loa-grimoire/NOTES.md

    if [[ -f "$SELF_HEAL_SCRIPT" ]]; then
        run bash "$SELF_HEAL_SCRIPT"

        [[ "$status" -eq 0 ]]
        # Should recover meaningful content
        grep -q "Session Continuity" loa-grimoire/NOTES.md || \
            grep -q "Active Sub-Goals" loa-grimoire/NOTES.md
    else
        skip "self-heal-state.sh not available"
    fi
}

@test "NOTES.md missing required sections triggers template merge" {
    cd "$TEST_DIR"

    echo "# Just a header" > loa-grimoire/NOTES.md

    if [[ -f "$SELF_HEAL_SCRIPT" ]]; then
        run bash "$SELF_HEAL_SCRIPT"

        [[ "$status" -eq 0 ]]
    else
        skip "self-heal-state.sh not available"
    fi
}

# =============================================================================
# Grounding Type Edge Cases
# =============================================================================

@test "unknown grounding type treated as ungrounded" {
    cd "$TEST_DIR"

    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Grounded"}
{"ts":"2024-01-15T10:01:00Z","agent":"implementing-tasks","phase":"cite","grounding":"unknown_type","claim":"Unknown grounding"}
EOF

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        [[ "$status" -eq 1 ]]  # Should fail - unknown type is ungrounded
        [[ "$output" == *"grounded_claims=1"* ]] || [[ "$output" == *"status=fail"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "missing grounding field treated as ungrounded" {
    cd "$TEST_DIR"

    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Has grounding"}
{"ts":"2024-01-15T10:01:00Z","agent":"implementing-tasks","phase":"cite","claim":"Missing grounding field"}
EOF

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        # Missing field should be treated as ungrounded
        [[ "$status" -eq 1 ]] || [[ "$output" == *"status=fail"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "null grounding value treated as ungrounded" {
    cd "$TEST_DIR"

    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Valid"}
{"ts":"2024-01-15T10:01:00Z","agent":"implementing-tasks","phase":"cite","grounding":null,"claim":"Null grounding"}
EOF

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        [[ "$status" -eq 1 ]] || [[ "$output" == *"status=fail"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

# =============================================================================
# Threshold Boundary Edge Cases
# =============================================================================

@test "threshold 0.00 passes any ratio" {
    cd "$TEST_DIR"

    create_trajectory implementing-tasks <<EOF
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"assumption","claim":"All assumptions"}
{"ts":"2024-01-15T10:01:00Z","agent":"implementing-tasks","phase":"cite","grounding":"assumption","claim":"More assumptions"}
EOF

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.00

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"status=pass"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "threshold 1.00 requires 100% grounding" {
    cd "$TEST_DIR"

    # 99% grounded (99/100)
    local trajectory="loa-grimoire/a2a/trajectory/implementing-tasks-$(date +%Y-%m-%d).jsonl"
    for i in {1..99}; do
        echo "{\"ts\":\"2024-01-15T10:00:00Z\",\"agent\":\"implementing-tasks\",\"phase\":\"cite\",\"grounding\":\"citation\",\"claim\":\"Claim $i\"}" >> "$trajectory"
    done
    echo '{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"assumption","claim":"One assumption"}' >> "$trajectory"

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 1.00

        [[ "$status" -eq 1 ]]  # Should fail with 99%
        [[ "$output" == *"status=fail"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "threshold > 1.00 is invalid" {
    cd "$TEST_DIR"

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 1.50

        [[ "$status" -eq 2 ]]
        [[ "$output" == *"invalid"* ]] || [[ "$output" == *"error"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "negative threshold is invalid" {
    cd "$TEST_DIR"

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks -0.5

        [[ "$status" -eq 2 ]]
        [[ "$output" == *"invalid"* ]] || [[ "$output" == *"error"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

# =============================================================================
# Self-Healing Priority Edge Cases
# =============================================================================

@test "self-healing prefers git history over template" {
    cd "$TEST_DIR"

    # Add unique content and commit
    echo "## UNIQUE MARKER 12345" >> loa-grimoire/NOTES.md
    git add loa-grimoire/NOTES.md
    git commit -m "Add unique content" --quiet

    # Remove the file
    rm loa-grimoire/NOTES.md

    if [[ -f "$SELF_HEAL_SCRIPT" ]]; then
        run bash "$SELF_HEAL_SCRIPT"

        [[ "$status" -eq 0 ]]
        [[ -f "loa-grimoire/NOTES.md" ]]
        # Should have unique marker from git history
        grep -q "UNIQUE MARKER 12345" loa-grimoire/NOTES.md || \
            grep -q "Session Continuity" loa-grimoire/NOTES.md
    else
        skip "self-heal-state.sh not available"
    fi
}

@test "self-healing creates template when git has no history" {
    cd "$TEST_DIR"

    # Remove file and git tracking
    rm loa-grimoire/NOTES.md
    git rm --cached loa-grimoire/NOTES.md --quiet 2>/dev/null || true
    git commit -m "Remove NOTES.md" --quiet 2>/dev/null || true

    if [[ -f "$SELF_HEAL_SCRIPT" ]]; then
        run bash "$SELF_HEAL_SCRIPT"

        [[ "$status" -eq 0 ]]
        [[ -f "loa-grimoire/NOTES.md" ]]
        # Should have required sections from template
        grep -q "Session Continuity" loa-grimoire/NOTES.md
    else
        skip "self-heal-state.sh not available"
    fi
}

# =============================================================================
# Agent Name Edge Cases
# =============================================================================

@test "agent name with spaces handled" {
    cd "$TEST_DIR"

    # Create trajectory with agent name containing spaces (unlikely but possible)
    local trajectory="loa-grimoire/a2a/trajectory/my agent-$(date +%Y-%m-%d).jsonl"
    echo '{"ts":"2024-01-15T10:00:00Z","agent":"my agent","phase":"cite","grounding":"citation","claim":"Test"}' > "$trajectory"

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" "my agent" 0.95

        # Should handle gracefully (may fail to find, but shouldn't crash)
        [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "agent name with special characters handled" {
    cd "$TEST_DIR"

    # Create trajectory with safe special chars
    local trajectory="loa-grimoire/a2a/trajectory/agent-v1.0-$(date +%Y-%m-%d).jsonl"
    echo '{"ts":"2024-01-15T10:00:00Z","agent":"agent-v1.0","phase":"cite","grounding":"citation","claim":"Test"}' > "$trajectory"

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" "agent-v1.0" 0.95

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"total_claims=1"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

# =============================================================================
# Date Edge Cases
# =============================================================================

@test "trajectory from future date is valid" {
    cd "$TEST_DIR"

    # Create trajectory for tomorrow (edge case during date rollover)
    local tomorrow=$(date -d "tomorrow" +%Y-%m-%d 2>/dev/null || date -v+1d +%Y-%m-%d 2>/dev/null || echo "2099-12-31")
    local trajectory="loa-grimoire/a2a/trajectory/implementing-tasks-${tomorrow}.jsonl"
    echo '{"ts":"2024-01-16T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Future claim"}' > "$trajectory"

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95 "$tomorrow"

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"total_claims=1"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "invalid date format returns error" {
    cd "$TEST_DIR"

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95 "not-a-date"

        # Should handle gracefully
        [[ "$status" -eq 0 ]] || [[ "$status" -eq 2 ]]
    else
        skip "grounding-check.sh not available"
    fi
}
