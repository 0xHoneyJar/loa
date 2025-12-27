#!/usr/bin/env bats
# Integration tests for v0.9.0 Session Lifecycle
# Part of Loa Framework v0.9.0 Lossless Ledger Protocol

# Test setup
setup() {
    # Create temp directory for test environment
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_DIR=$(mktemp -d "${BATS_TMPDIR}/session-lifecycle-test.XXXXXX")
    export PROJECT_ROOT="$TEST_DIR"

    # Initialize git repo
    cd "$TEST_DIR"
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test"

    # Create full project structure
    mkdir -p loa-grimoire/a2a/trajectory
    mkdir -p .beads
    mkdir -p .claude/scripts

    # Create NOTES.md with required sections
    cat > loa-grimoire/NOTES.md << 'EOF'
# Agent Working Memory (NOTES.md)

## Active Sub-Goals
- [ ] Complete integration tests

## Discovered Technical Debt
None identified.

## Blockers & Dependencies
None.

## Session Continuity
| Timestamp | Agent | Summary |
|-----------|-------|---------|
| 2024-01-15T10:00:00Z | implementing-tasks | Initial session |

## Decision Log
| Decision | Rationale | Grounding |
|----------|-----------|-----------|
EOF

    # Create .loa.config.yaml
    cat > .loa.config.yaml << 'EOF'
version: "0.9.0"

grounding:
  enforcement: warn
  threshold: 0.95

attention_budget:
  advisory_only: true
  yellow_threshold: 5000
  red_threshold: 2000
EOF

    # Copy scripts
    cp "${BATS_TEST_DIRNAME}/../../.claude/scripts/grounding-check.sh" .claude/scripts/ 2>/dev/null || true
    cp "${BATS_TEST_DIRNAME}/../../.claude/scripts/synthesis-checkpoint.sh" .claude/scripts/ 2>/dev/null || true
    cp "${BATS_TEST_DIRNAME}/../../.claude/scripts/self-heal-state.sh" .claude/scripts/ 2>/dev/null || true
    chmod +x .claude/scripts/*.sh 2>/dev/null || true

    # Initial commit
    git add .
    git commit -m "Initial project setup" --quiet

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

# Helper to create trajectory entries
add_trajectory_entry() {
    local agent="${1:-implementing-tasks}"
    local grounding="${2:-citation}"
    local claim="${3:-Test claim}"
    local date="${4:-$(date +%Y-%m-%d)}"
    local file="loa-grimoire/a2a/trajectory/${agent}-${date}.jsonl"

    echo "{\"ts\":\"$(date -Iseconds)\",\"agent\":\"${agent}\",\"phase\":\"cite\",\"grounding\":\"${grounding}\",\"claim\":\"${claim}\"}" >> "$file"
}

# Helper to simulate session work
simulate_session_work() {
    local agent="${1:-implementing-tasks}"
    local grounded="${2:-5}"
    local ungrounded="${3:-0}"

    for i in $(seq 1 "$grounded"); do
        add_trajectory_entry "$agent" "citation" "Grounded claim $i"
    done

    for i in $(seq 1 "$ungrounded"); do
        add_trajectory_entry "$agent" "assumption" "Ungrounded claim $i"
    done
}

# =============================================================================
# Session Start with Recovery Tests
# =============================================================================

@test "session start detects healthy State Zone" {
    cd "$TEST_DIR"

    # All components present - should report healthy
    if [[ -f "$SELF_HEAL_SCRIPT" ]]; then
        run bash "$SELF_HEAL_SCRIPT" --check-only
        [[ "$status" -eq 0 ]]
        [[ "$output" == *"healthy"* ]] || [[ "$output" == *"PASSED"* ]]
    else
        skip "self-heal-state.sh not available"
    fi
}

@test "session start recovers missing NOTES.md" {
    cd "$TEST_DIR"

    # Remove NOTES.md
    rm loa-grimoire/NOTES.md

    if [[ -f "$SELF_HEAL_SCRIPT" ]]; then
        run bash "$SELF_HEAL_SCRIPT"

        [[ "$status" -eq 0 ]]
        [[ -f "loa-grimoire/NOTES.md" ]]
    else
        skip "self-heal-state.sh not available"
    fi
}

@test "session start recovers from git history" {
    cd "$TEST_DIR"

    # Add some unique content and commit
    echo "## Unique Session Content" >> loa-grimoire/NOTES.md
    git add loa-grimoire/NOTES.md
    git commit -m "Add unique content" --quiet

    # Remove the file
    rm loa-grimoire/NOTES.md

    if [[ -f "$SELF_HEAL_SCRIPT" ]]; then
        run bash "$SELF_HEAL_SCRIPT"

        [[ "$status" -eq 0 ]]
        [[ -f "loa-grimoire/NOTES.md" ]]
        # Should recover from git with unique content
        grep -q "Unique Session Content" loa-grimoire/NOTES.md || \
            grep -q "Session Continuity" loa-grimoire/NOTES.md
    else
        skip "self-heal-state.sh not available"
    fi
}

@test "session start creates full State Zone from scratch" {
    cd "$TEST_DIR"

    # Remove entire State Zone
    rm -rf loa-grimoire .beads

    if [[ -f "$SELF_HEAL_SCRIPT" ]]; then
        run bash "$SELF_HEAL_SCRIPT"

        [[ "$status" -eq 0 ]]
        [[ -d "loa-grimoire" ]]
        [[ -d ".beads" ]]
        [[ -d "loa-grimoire/a2a/trajectory" ]]
    else
        skip "self-heal-state.sh not available"
    fi
}

# =============================================================================
# Delta-Synthesis Trigger Tests
# =============================================================================

@test "grounding check passes with 100% grounded claims" {
    cd "$TEST_DIR"

    # Simulate session with all grounded claims
    simulate_session_work "implementing-tasks" 10 0

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"grounding_ratio=1.00"* ]]
        [[ "$output" == *"status=pass"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "grounding check fails with low grounding ratio" {
    cd "$TEST_DIR"

    # Simulate session with 50% grounded claims
    simulate_session_work "implementing-tasks" 5 5

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        [[ "$status" -eq 1 ]]
        [[ "$output" == *"status=fail"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "grounding check passes zero-claim session" {
    cd "$TEST_DIR"

    # No trajectory file - zero claims
    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"grounding_ratio=1.00"* ]]
        [[ "$output" == *"zero-claim"* ]] || [[ "$output" == *"Zero-claim"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "grounding ratio exactly at threshold passes" {
    cd "$TEST_DIR"

    # 95% grounded (19/20)
    simulate_session_work "implementing-tasks" 19 1

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"status=pass"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

# =============================================================================
# Synthesis Checkpoint Flow Tests
# =============================================================================

@test "synthesis checkpoint passes with healthy session" {
    cd "$TEST_DIR"

    # Simulate good session work
    simulate_session_work "implementing-tasks" 10 0

    if [[ -f "$SYNTHESIS_SCRIPT" ]]; then
        run bash "$SYNTHESIS_SCRIPT" implementing-tasks

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"SYNTHESIS CHECKPOINT: PASSED"* ]]
        [[ "$output" == *"/clear is permitted"* ]]
    else
        skip "synthesis-checkpoint.sh not available"
    fi
}

@test "synthesis checkpoint warns on low grounding" {
    cd "$TEST_DIR"

    # Simulate session with assumptions
    simulate_session_work "implementing-tasks" 5 5

    if [[ -f "$SYNTHESIS_SCRIPT" ]]; then
        run bash "$SYNTHESIS_SCRIPT" implementing-tasks

        # Default enforcement is warn, so should still pass
        [[ "$status" -eq 0 ]]
        [[ "$output" == *"WARNING"* ]] || [[ "$output" == *"warn"* ]]
    else
        skip "synthesis-checkpoint.sh not available"
    fi
}

@test "synthesis checkpoint creates handoff entry" {
    cd "$TEST_DIR"

    if [[ -f "$SYNTHESIS_SCRIPT" ]]; then
        run bash "$SYNTHESIS_SCRIPT" implementing-tasks

        [[ "$status" -eq 0 ]]

        # Check trajectory has handoff entry
        local today=$(date +%Y-%m-%d)
        local trajectory="loa-grimoire/a2a/trajectory/implementing-tasks-${today}.jsonl"

        [[ -f "$trajectory" ]]
        grep -q "session_handoff" "$trajectory"
    else
        skip "synthesis-checkpoint.sh not available"
    fi
}

@test "synthesis checkpoint runs all 7 steps" {
    cd "$TEST_DIR"

    if [[ -f "$SYNTHESIS_SCRIPT" ]]; then
        run bash "$SYNTHESIS_SCRIPT" implementing-tasks

        [[ "$output" == *"Step 1"* ]]
        [[ "$output" == *"Step 2"* ]]
        [[ "$output" == *"Step 3"* ]]
        [[ "$output" == *"Step 4"* ]]
        [[ "$output" == *"Step 5"* ]]
        [[ "$output" == *"Step 6"* ]]
        [[ "$output" == *"Step 7"* ]]
    else
        skip "synthesis-checkpoint.sh not available"
    fi
}

# =============================================================================
# Self-Healing Recovery Tests
# =============================================================================

@test "self-healing recovers trajectory directory" {
    cd "$TEST_DIR"

    # Remove trajectory directory
    rm -rf loa-grimoire/a2a/trajectory

    if [[ -f "$SELF_HEAL_SCRIPT" ]]; then
        run bash "$SELF_HEAL_SCRIPT"

        [[ "$status" -eq 0 ]]
        [[ -d "loa-grimoire/a2a/trajectory" ]]
    else
        skip "self-heal-state.sh not available"
    fi
}

@test "self-healing recovers .beads directory" {
    cd "$TEST_DIR"

    rm -rf .beads

    if [[ -f "$SELF_HEAL_SCRIPT" ]]; then
        run bash "$SELF_HEAL_SCRIPT"

        [[ "$status" -eq 0 ]]
        [[ -d ".beads" ]]
    else
        skip "self-heal-state.sh not available"
    fi
}

@test "self-healing logs recovery to trajectory" {
    cd "$TEST_DIR"

    # Remove NOTES.md to trigger healing
    rm loa-grimoire/NOTES.md

    if [[ -f "$SELF_HEAL_SCRIPT" ]]; then
        run bash "$SELF_HEAL_SCRIPT"

        [[ "$status" -eq 0 ]]

        # Check trajectory has recovery log
        local today=$(date +%Y-%m-%d)
        local log_file="loa-grimoire/a2a/trajectory/system-${today}.jsonl"

        [[ -f "$log_file" ]]
        grep -q "self_heal" "$log_file"
    else
        skip "self-heal-state.sh not available"
    fi
}

# =============================================================================
# Full Session Lifecycle Tests
# =============================================================================

@test "full session lifecycle: start -> work -> checkpoint -> clear" {
    cd "$TEST_DIR"

    # Step 1: Session start (self-healing check)
    if [[ -f "$SELF_HEAL_SCRIPT" ]]; then
        run bash "$SELF_HEAL_SCRIPT" --check-only
        [[ "$status" -eq 0 ]]
    fi

    # Step 2: Simulate session work with grounded claims
    simulate_session_work "implementing-tasks" 10 0

    # Step 3: Run synthesis checkpoint
    if [[ -f "$SYNTHESIS_SCRIPT" ]]; then
        run bash "$SYNTHESIS_SCRIPT" implementing-tasks

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"SYNTHESIS CHECKPOINT: PASSED"* ]]
        [[ "$output" == *"/clear is permitted"* ]]
    fi

    # Lifecycle complete - clear is permitted
    [[ -f "loa-grimoire/NOTES.md" ]]
}

@test "recovery after simulated crash" {
    cd "$TEST_DIR"

    # Simulate work
    simulate_session_work "implementing-tasks" 5 0

    # Simulate crash by removing State Zone components
    rm loa-grimoire/NOTES.md
    rm -rf loa-grimoire/a2a/trajectory

    if [[ -f "$SELF_HEAL_SCRIPT" ]]; then
        # Recovery should restore everything
        run bash "$SELF_HEAL_SCRIPT"

        [[ "$status" -eq 0 ]]
        [[ -f "loa-grimoire/NOTES.md" ]]
        [[ -d "loa-grimoire/a2a/trajectory" ]]
    else
        skip "self-heal-state.sh not available"
    fi
}

@test "enforcement blocks clear when grounding fails with strict mode" {
    cd "$TEST_DIR"

    # Set strict enforcement
    cat > .loa.config.yaml << 'EOF'
version: "0.9.0"
grounding:
  enforcement: strict
  threshold: 0.95
EOF

    # Simulate session with poor grounding
    simulate_session_work "implementing-tasks" 5 5

    if [[ -f "$SYNTHESIS_SCRIPT" ]]; then
        run bash "$SYNTHESIS_SCRIPT" implementing-tasks

        # Strict enforcement should fail
        [[ "$status" -eq 1 ]] || [[ "$output" == *"FAILED"* ]]
    else
        skip "synthesis-checkpoint.sh not available"
    fi
}

# =============================================================================
# Configuration Integration Tests
# =============================================================================

@test "disabled enforcement skips grounding check entirely" {
    cd "$TEST_DIR"

    # Set disabled enforcement
    cat > .loa.config.yaml << 'EOF'
version: "0.9.0"
grounding:
  enforcement: disabled
  threshold: 0.95
EOF

    # Even with poor grounding, should pass
    simulate_session_work "implementing-tasks" 1 9

    if [[ -f "$SYNTHESIS_SCRIPT" ]]; then
        run bash "$SYNTHESIS_SCRIPT" implementing-tasks

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"SKIPPED"* ]] || [[ "$output" == *"disabled"* ]]
    else
        skip "synthesis-checkpoint.sh not available"
    fi
}

@test "custom threshold is respected" {
    cd "$TEST_DIR"

    # Set low threshold
    cat > .loa.config.yaml << 'EOF'
version: "0.9.0"
grounding:
  enforcement: strict
  threshold: 0.50
EOF

    # 60% grounded should pass with 0.50 threshold
    simulate_session_work "implementing-tasks" 6 4

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.50

        [[ "$status" -eq 0 ]]
        [[ "$output" == *"status=pass"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "missing config uses safe defaults" {
    cd "$TEST_DIR"

    # Remove config
    rm -f .loa.config.yaml

    if [[ -f "$SYNTHESIS_SCRIPT" ]]; then
        run bash "$SYNTHESIS_SCRIPT" implementing-tasks

        [[ "$status" -eq 0 ]]
        # Default enforcement is warn
        [[ "$output" == *"warn"* ]] || [[ "$output" == *"Enforcement: warn"* ]]
    else
        skip "synthesis-checkpoint.sh not available"
    fi
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "handles corrupted trajectory line gracefully" {
    cd "$TEST_DIR"

    local trajectory="loa-grimoire/a2a/trajectory/implementing-tasks-$(date +%Y-%m-%d).jsonl"

    # Create trajectory with corrupted line
    cat > "$trajectory" << 'EOF'
{"ts":"2024-01-15T10:00:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Valid claim"}
this is not valid json at all
{"ts":"2024-01-15T10:02:00Z","agent":"implementing-tasks","phase":"cite","grounding":"citation","claim":"Another valid"}
EOF

    if [[ -f "$GROUNDING_SCRIPT" ]]; then
        run bash "$GROUNDING_SCRIPT" implementing-tasks 0.95

        # Should not crash, should count valid lines
        [[ "$status" -eq 0 ]]
        [[ "$output" == *"total_claims=2"* ]]
    else
        skip "grounding-check.sh not available"
    fi
}

@test "handles empty trajectory file" {
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
