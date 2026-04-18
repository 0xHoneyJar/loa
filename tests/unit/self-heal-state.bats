#!/usr/bin/env bats
# Unit tests for self-heal-state.sh
# Part of Loa Framework v0.9.0 Lossless Ledger Protocol

# Test setup
setup() {
    # Create temp directory for test files
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_DIR=$(mktemp -d "${BATS_TMPDIR}/self-heal-test.XXXXXX")
    export PROJECT_ROOT="$TEST_DIR"

    # Initialize git repo
    cd "$TEST_DIR"
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test"

    # Create initial structure
    mkdir -p grimoires/loa/a2a/trajectory
    mkdir -p .beads
    mkdir -p .claude/scripts

    # Create initial NOTES.md
    cat > grimoires/loa/NOTES.md << 'EOF'
# Agent Working Memory (NOTES.md)

## Session Continuity
| Timestamp | Agent | Summary |
|-----------|-------|---------|

## Decision Log
EOF

    # Initial commit
    git add .
    git commit -m "Initial commit" --quiet

    # Copy the script + its sourced dependencies so the test harness can
    # source bootstrap.sh and path-lib.sh from the relative path the script
    # expects. Mirrors the pattern in release-notes-gen.bats setup.
    # Fail loudly if any required file is missing — obscuring missing deps
    # would mask real breakage under a future refactor.
    cp "${BATS_TEST_DIRNAME}/../../.claude/scripts/self-heal-state.sh" .claude/scripts/
    cp "${BATS_TEST_DIRNAME}/../../.claude/scripts/bootstrap.sh" .claude/scripts/
    cp "${BATS_TEST_DIRNAME}/../../.claude/scripts/path-lib.sh" .claude/scripts/
    chmod +x .claude/scripts/self-heal-state.sh

    export SCRIPT=".claude/scripts/self-heal-state.sh"
}

teardown() {
    cd /
    if [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# =============================================================================
# Basic Functionality Tests
# =============================================================================

@test "self-heal-state.sh exists and is executable" {
    [[ -f "${TEST_DIR}/${SCRIPT}" ]]
    [[ -x "${TEST_DIR}/${SCRIPT}" ]]
}

@test "reports healthy when all components exist" {
    cd "$TEST_DIR"
    run bash "$SCRIPT"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"State Zone is healthy"* ]]
}

@test "check-only mode reports issues without fixing" {
    cd "$TEST_DIR"

    # Remove NOTES.md
    rm grimoires/loa/NOTES.md

    run bash "$SCRIPT" --check-only

    [[ "$status" -eq 1 ]]  # Issues found
    [[ "$output" == *"Check only"* ]]
    [[ "$output" == *"NOTES.md is missing"* ]]

    # File should still be missing
    [[ ! -f "grimoires/loa/NOTES.md" ]]
}

@test "verbose mode shows more details" {
    cd "$TEST_DIR"
    run bash "$SCRIPT" --verbose

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[SELF-HEAL]"* ]]
}

# =============================================================================
# Recovery Priority Tests
# =============================================================================

@test "recovers NOTES.md from git history" {
    cd "$TEST_DIR"

    # Remove NOTES.md
    rm grimoires/loa/NOTES.md

    run bash "$SCRIPT"

    [[ "$status" -eq 0 ]]
    [[ -f "grimoires/loa/NOTES.md" ]]
    [[ "$output" == *"Recovered from git"* ]] || [[ "$output" == *"Created from template"* ]]
}

@test "creates NOTES.md from template when not in git" {
    cd "$TEST_DIR"

    # Remove NOTES.md and clear git tracking
    rm grimoires/loa/NOTES.md
    git rm --cached grimoires/loa/NOTES.md --quiet 2>/dev/null || true
    git commit -m "Remove NOTES.md" --quiet 2>/dev/null || true

    run bash "$SCRIPT"

    [[ "$status" -eq 0 ]]
    [[ -f "grimoires/loa/NOTES.md" ]]
    [[ "$output" == *"Created from template"* ]]
}

@test "template NOTES.md has required sections" {
    cd "$TEST_DIR"

    # Remove NOTES.md and prevent git recovery
    rm grimoires/loa/NOTES.md
    git rm --cached grimoires/loa/NOTES.md --quiet 2>/dev/null || true

    run bash "$SCRIPT"

    [[ "$status" -eq 0 ]]
    [[ -f "grimoires/loa/NOTES.md" ]]

    # Check required sections
    grep -q "Active Sub-Goals" grimoires/loa/NOTES.md
    grep -q "Session Continuity" grimoires/loa/NOTES.md
    grep -q "Decision Log" grimoires/loa/NOTES.md
}

# =============================================================================
# Directory Healing Tests
# =============================================================================

@test "creates grimoires/loa/ when missing" {
    cd "$TEST_DIR"

    # Remove entire grimoires/loa
    rm -rf grimoires/loa
    git rm -rf grimoires/loa --quiet 2>/dev/null || true
    git commit -m "Remove grimoires/loa" --quiet 2>/dev/null || true

    run bash "$SCRIPT"

    [[ "$status" -eq 0 ]]
    [[ -d "grimoires/loa" ]]
    [[ -d "grimoires/loa/a2a" ]]
    [[ -d "grimoires/loa/a2a/trajectory" ]]
}

@test "creates .beads/ when missing" {
    cd "$TEST_DIR"

    # Remove .beads
    rm -rf .beads
    git rm -rf .beads --quiet 2>/dev/null || true

    run bash "$SCRIPT"

    [[ "$status" -eq 0 ]]
    [[ -d ".beads" ]]
}

@test "creates trajectory/ when missing" {
    cd "$TEST_DIR"

    # Remove trajectory
    rm -rf grimoires/loa/a2a/trajectory

    run bash "$SCRIPT"

    [[ "$status" -eq 0 ]]
    [[ -d "grimoires/loa/a2a/trajectory" ]]
}

# =============================================================================
# Edge Case Tests
# =============================================================================

@test "handles empty NOTES.md file" {
    cd "$TEST_DIR"

    # Create empty file
    : > grimoires/loa/NOTES.md

    run bash "$SCRIPT"

    [[ "$status" -eq 0 ]]
    # Should recover from git or template
    [[ -s "grimoires/loa/NOTES.md" ]]  # File should have content now
}

@test "handles multiple missing components" {
    cd "$TEST_DIR"

    # Remove multiple things
    rm grimoires/loa/NOTES.md
    rm -rf grimoires/loa/a2a/trajectory
    rm -rf .beads

    run bash "$SCRIPT"

    [[ "$status" -eq 0 ]]
    [[ -f "grimoires/loa/NOTES.md" ]]
    [[ -d "grimoires/loa/a2a/trajectory" ]]
    [[ -d ".beads" ]]
}

@test "handles unknown arguments" {
    cd "$TEST_DIR"
    run bash "$SCRIPT" --unknown-arg

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"Unknown argument"* ]]
}

@test "can combine --check-only and --verbose" {
    cd "$TEST_DIR"
    run bash "$SCRIPT" --check-only --verbose

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Check only"* ]]
}

# =============================================================================
# Git Integration Tests
# =============================================================================

@test "recovers .beads/ from git when tracked" {
    cd "$TEST_DIR"

    # Create a bead file and commit
    echo "id: test-bead" > .beads/test.yaml
    git add .beads/
    git commit -m "Add bead" --quiet

    # Remove directory
    rm -rf .beads

    run bash "$SCRIPT"

    [[ "$status" -eq 0 ]]
    [[ -d ".beads" ]]
}

@test "logs recovery to trajectory" {
    cd "$TEST_DIR"

    # Remove NOTES.md to trigger healing
    rm grimoires/loa/NOTES.md

    run bash "$SCRIPT"

    [[ "$status" -eq 0 ]]

    # Check trajectory log
    local today=$(date +%Y-%m-%d)
    local log_file="grimoires/loa/a2a/trajectory/system-${today}.jsonl"

    [[ -f "$log_file" ]]
    grep -q "self_heal" "$log_file"
}

# =============================================================================
# ck Index Tests
# =============================================================================

@test "skips ck healing when ck not available" {
    cd "$TEST_DIR"
    run bash "$SCRIPT" --verbose

    [[ "$status" -eq 0 ]]
    # Should skip ck-related healing
    [[ "$output" == *"Checking: .ck/"* ]]
}

@test "handles missing .ck/ gracefully" {
    cd "$TEST_DIR"

    # Remove .ck if it exists
    rm -rf .ck

    run bash "$SCRIPT"

    [[ "$status" -eq 0 ]]
    # Should not fail, .ck is optional
}

# =============================================================================
# Output Format Tests
# =============================================================================

@test "summary shows mode correctly" {
    cd "$TEST_DIR"
    run bash "$SCRIPT"

    [[ "$output" == *"SELF-HEALING SUMMARY"* ]]
    [[ "$output" == *"Mode: Heal"* ]]
}

@test "check-only summary shows correct mode" {
    cd "$TEST_DIR"
    run bash "$SCRIPT" --check-only

    [[ "$output" == *"SELF-HEALING SUMMARY"* ]]
    [[ "$output" == *"Mode: Check only"* ]]
}

@test "summary includes timestamp" {
    cd "$TEST_DIR"
    run bash "$SCRIPT"

    [[ "$output" == *"Timestamp:"* ]]
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "fails gracefully outside git repo" {
    cd "$TEST_DIR"

    # Remove .git
    rm -rf .git

    run bash "$SCRIPT"

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"Git is required"* ]] || [[ "$output" == *"Not in a git repository"* ]]
}

@test "heals entire missing State Zone" {
    cd "$TEST_DIR"

    # Remove everything but keep git
    rm -rf grimoires/loa .beads .ck

    run bash "$SCRIPT"

    [[ "$status" -eq 0 ]]
    [[ -d "grimoires/loa" ]]
    [[ -d ".beads" ]]
}
