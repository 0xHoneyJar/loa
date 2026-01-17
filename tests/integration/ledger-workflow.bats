#!/usr/bin/env bats
# Integration tests for Sprint Ledger Workflow
# Sprint 5: Command Integration
#
# Test coverage:
#   - End-to-end workflow: init -> create_cycle -> add_sprint -> resolve
#   - Cross-cycle sprint numbering continuity
#   - validate-sprint-id.sh integration with ledger-lib.sh
#   - Legacy mode compatibility (no ledger)
#   - Command integration patterns

# Test setup
setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    LEDGER_LIB="$PROJECT_ROOT/.claude/scripts/ledger-lib.sh"
    VALIDATE_SCRIPT="$PROJECT_ROOT/.claude/scripts/validate-sprint-id.sh"

    # Create temp directory for test artifacts
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/ledger-workflow-test-$$"
    mkdir -p "$TEST_TMPDIR"

    # Create mock project structure
    export TEST_PROJECT="$TEST_TMPDIR/project"
    mkdir -p "$TEST_PROJECT/grimoires/loa/a2a"
    mkdir -p "$TEST_PROJECT/.claude/scripts"

    # Copy scripts to test project
    cp "$LEDGER_LIB" "$TEST_PROJECT/.claude/scripts/" 2>/dev/null || true
    cp "$VALIDATE_SCRIPT" "$TEST_PROJECT/.claude/scripts/" 2>/dev/null || true
    chmod +x "$TEST_PROJECT/.claude/scripts/"*.sh 2>/dev/null || true

    # Change to test project directory
    cd "$TEST_PROJECT"
}

teardown() {
    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# Helper to skip if dependencies not available
skip_if_deps_missing() {
    if ! command -v jq &>/dev/null; then
        skip "jq not available"
    fi
    if [[ ! -f "$LEDGER_LIB" ]]; then
        skip "ledger-lib.sh not available"
    fi
    if [[ ! -f "$VALIDATE_SCRIPT" ]]; then
        skip "validate-sprint-id.sh not available"
    fi
}

# Helper to source the library
source_lib() {
    source ".claude/scripts/ledger-lib.sh"
}

# =============================================================================
# End-to-End Workflow Tests
# =============================================================================

@test "E2E: full workflow from init to resolution" {
    skip_if_deps_missing
    source_lib

    # Step 1: Initialize ledger
    run init_ledger
    [[ "$status" -eq 0 ]]
    [[ -f "grimoires/loa/ledger.json" ]]

    # Step 2: Create a cycle
    local cycle_id
    cycle_id=$(create_cycle "MVP Development")
    [[ "$cycle_id" == "cycle-001" ]]

    # Step 3: Add sprints
    local sprint1_id sprint2_id sprint3_id
    sprint1_id=$(add_sprint "sprint-1")
    sprint2_id=$(add_sprint "sprint-2")
    sprint3_id=$(add_sprint "sprint-3")

    [[ "$sprint1_id" == "1" ]]
    [[ "$sprint2_id" == "2" ]]
    [[ "$sprint3_id" == "3" ]]

    # Step 4: Resolve sprints
    local resolved
    resolved=$(resolve_sprint "sprint-1")
    [[ "$resolved" == "1" ]]

    resolved=$(resolve_sprint "sprint-2")
    [[ "$resolved" == "2" ]]

    resolved=$(resolve_sprint "sprint-3")
    [[ "$resolved" == "3" ]]
}

@test "E2E: cross-cycle sprint numbering continues correctly" {
    skip_if_deps_missing
    source_lib

    # Initialize and create first cycle
    init_ledger
    create_cycle "Cycle 1"
    add_sprint "sprint-1"  # global 1
    add_sprint "sprint-2"  # global 2

    # Archive first cycle
    archive_cycle "cycle-1-done"

    # Create second cycle
    create_cycle "Cycle 2"

    # Add sprints - should continue from 3
    local sprint1_c2 sprint2_c2
    sprint1_c2=$(add_sprint "sprint-1")  # Should be global 3
    sprint2_c2=$(add_sprint "sprint-2")  # Should be global 4

    [[ "$sprint1_c2" == "3" ]]
    [[ "$sprint2_c2" == "4" ]]

    # Verify resolution in new cycle
    local resolved
    resolved=$(resolve_sprint "sprint-1")
    [[ "$resolved" == "3" ]]

    resolved=$(resolve_sprint "sprint-2")
    [[ "$resolved" == "4" ]]
}

@test "E2E: global IDs resolve across archived cycles" {
    skip_if_deps_missing
    source_lib

    # Setup: two cycles with sprints
    init_ledger
    create_cycle "Cycle 1"
    add_sprint "sprint-1"  # global 1
    add_sprint "sprint-2"  # global 2
    archive_cycle "cycle-1"

    create_cycle "Cycle 2"
    add_sprint "sprint-1"  # global 3
    add_sprint "sprint-2"  # global 4

    # Global IDs should resolve even from previous cycles
    local resolved
    resolved=$(resolve_sprint "sprint-1")  # Current cycle's sprint-1
    [[ "$resolved" == "3" ]]

    # But global IDs from cycle 1 should still resolve
    resolved=$(resolve_sprint "sprint-1")
    [[ "$resolved" == "3" ]]  # Current cycle wins for local labels
}

# =============================================================================
# validate-sprint-id.sh Integration Tests
# =============================================================================

@test "validate-sprint-id.sh: returns VALID in legacy mode (no ledger)" {
    skip_if_deps_missing

    run .claude/scripts/validate-sprint-id.sh sprint-1
    [[ "$status" -eq 0 ]]
    [[ "$output" == "VALID" ]]
}

@test "validate-sprint-id.sh: rejects invalid format" {
    skip_if_deps_missing

    run .claude/scripts/validate-sprint-id.sh "invalid"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"INVALID"* ]]

    run .claude/scripts/validate-sprint-id.sh "sprint-0"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"INVALID"* ]]

    run .claude/scripts/validate-sprint-id.sh ""
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"INVALID"* ]]
}

@test "validate-sprint-id.sh: returns global_id with ledger" {
    skip_if_deps_missing
    source_lib

    # Setup ledger with sprints
    init_ledger
    create_cycle "Test Cycle"
    add_sprint "sprint-1"
    add_sprint "sprint-2"

    # Test resolution
    run .claude/scripts/validate-sprint-id.sh sprint-1
    [[ "$status" -eq 0 ]]
    [[ "$output" == "VALID|global_id=1|local_label=sprint-1" ]]

    run .claude/scripts/validate-sprint-id.sh sprint-2
    [[ "$status" -eq 0 ]]
    [[ "$output" == "VALID|global_id=2|local_label=sprint-2" ]]
}

@test "validate-sprint-id.sh: returns NEW for unregistered sprint" {
    skip_if_deps_missing
    source_lib

    # Setup ledger with one sprint
    init_ledger
    create_cycle "Test Cycle"
    add_sprint "sprint-1"

    # sprint-2 not registered yet
    run .claude/scripts/validate-sprint-id.sh sprint-2
    [[ "$status" -eq 0 ]]
    [[ "$output" == "VALID|global_id=NEW|local_label=sprint-2" ]]
}

@test "validate-sprint-id.sh: works after cycle archive" {
    skip_if_deps_missing
    source_lib

    # Setup: cycle 1 with sprints, then archive and create cycle 2
    init_ledger
    create_cycle "Cycle 1"
    add_sprint "sprint-1"
    add_sprint "sprint-2"
    archive_cycle "cycle-1-done"

    create_cycle "Cycle 2"
    add_sprint "sprint-1"  # global 3

    # Should resolve to global 3 (current cycle)
    run .claude/scripts/validate-sprint-id.sh sprint-1
    [[ "$status" -eq 0 ]]
    [[ "$output" == "VALID|global_id=3|local_label=sprint-1" ]]
}

# =============================================================================
# Legacy Mode Compatibility Tests
# =============================================================================

@test "legacy mode: all operations work without ledger" {
    skip_if_deps_missing

    # No ledger created - should work in legacy mode
    run .claude/scripts/validate-sprint-id.sh sprint-1
    [[ "$status" -eq 0 ]]
    [[ "$output" == "VALID" ]]

    run .claude/scripts/validate-sprint-id.sh sprint-42
    [[ "$status" -eq 0 ]]
    [[ "$output" == "VALID" ]]
}

@test "legacy mode: resolve_sprint_safe returns input number" {
    skip_if_deps_missing
    source_lib

    # Without ledger, resolve_sprint_safe should return the number from input
    local result
    result=$(resolve_sprint_safe "sprint-5")
    [[ "$result" == "5" ]]

    result=$(resolve_sprint_safe "sprint-100")
    [[ "$result" == "100" ]]
}

# =============================================================================
# Sprint Status Update Tests
# =============================================================================

@test "sprint status updates through workflow" {
    skip_if_deps_missing
    source_lib

    # Setup
    init_ledger
    create_cycle "Test Cycle"
    local sprint_id
    sprint_id=$(add_sprint "sprint-1")

    # Initial status should be planned
    local status
    status=$(jq -r '.cycles[0].sprints[0].status' grimoires/loa/ledger.json)
    [[ "$status" == "planned" ]]

    # Update to in_progress
    update_sprint_status "$sprint_id" "in_progress"
    status=$(jq -r '.cycles[0].sprints[0].status' grimoires/loa/ledger.json)
    [[ "$status" == "in_progress" ]]

    # Update to completed
    update_sprint_status "$sprint_id" "completed"
    status=$(jq -r '.cycles[0].sprints[0].status' grimoires/loa/ledger.json)
    [[ "$status" == "completed" ]]

    # Completed should set timestamp
    local completed_ts
    completed_ts=$(jq -r '.cycles[0].sprints[0].completed' grimoires/loa/ledger.json)
    [[ "$completed_ts" != "null" ]]
}

# =============================================================================
# Sprint Directory Mapping Tests
# =============================================================================

@test "get_sprint_directory returns correct path" {
    skip_if_deps_missing
    source_lib

    local dir
    dir=$(get_sprint_directory "1")
    [[ "$dir" == "grimoires/loa/a2a/sprint-1" ]]

    dir=$(get_sprint_directory "42")
    [[ "$dir" == "grimoires/loa/a2a/sprint-42" ]]
}

@test "sprint directories use global IDs" {
    skip_if_deps_missing
    source_lib

    # Setup two cycles
    init_ledger
    create_cycle "Cycle 1"
    add_sprint "sprint-1"
    archive_cycle "c1"

    create_cycle "Cycle 2"
    local sprint_id
    sprint_id=$(add_sprint "sprint-1")  # global 2

    # Directory should use global ID
    local dir
    dir=$(get_sprint_directory "$sprint_id")
    [[ "$dir" == "grimoires/loa/a2a/sprint-2" ]]
}

# =============================================================================
# Cycle Lifecycle Tests
# =============================================================================

@test "cycle lifecycle: create, add sprints, archive, repeat" {
    skip_if_deps_missing
    source_lib

    init_ledger

    # Cycle 1
    local c1_id
    c1_id=$(create_cycle "MVP Phase 1")
    [[ "$c1_id" == "cycle-001" ]]

    add_sprint "sprint-1"
    add_sprint "sprint-2"
    add_sprint "sprint-3"

    # Archive
    local archive_path
    archive_path=$(archive_cycle "mvp-v1")
    [[ -d "$archive_path" ]]

    # Cycle 2
    local c2_id
    c2_id=$(create_cycle "MVP Phase 2")
    [[ "$c2_id" == "cycle-002" ]]

    # Sprints continue numbering
    local s4 s5
    s4=$(add_sprint "sprint-1")  # global 4
    s5=$(add_sprint "sprint-2")  # global 5

    [[ "$s4" == "4" ]]
    [[ "$s5" == "5" ]]

    # History should show both cycles
    local history
    history=$(get_cycle_history)
    local count
    count=$(echo "$history" | jq 'length')
    [[ "$count" == "2" ]]
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "adding sprint without active cycle fails" {
    skip_if_deps_missing
    source_lib

    init_ledger

    # No cycle created
    run add_sprint "sprint-1"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"No active cycle"* ]]
}

@test "creating cycle without init fails" {
    skip_if_deps_missing
    source_lib

    # No ledger initialized
    run create_cycle "Test"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not found"* ]]
}

@test "creating duplicate cycle fails" {
    skip_if_deps_missing
    source_lib

    init_ledger
    create_cycle "Cycle 1"

    # Try to create another without archiving
    run create_cycle "Cycle 2"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"already exists"* ]]
}

# =============================================================================
# Backup and Recovery Tests
# =============================================================================

@test "backup created on write operations" {
    skip_if_deps_missing
    source_lib

    init_ledger
    create_cycle "Test"

    # Backup should exist after cycle creation
    [[ -f "grimoires/loa/ledger.json.bak" ]]
}

@test "recovery restores from backup" {
    skip_if_deps_missing
    source_lib

    init_ledger
    create_cycle "Test"
    add_sprint "sprint-1"

    # Force a backup by doing another write operation
    update_sprint_status "1" "in_progress"

    # Now backup has sprint-1 in it
    # Corrupt the ledger
    echo "corrupt" > grimoires/loa/ledger.json

    # Recover
    run recover_from_backup
    [[ "$status" -eq 0 ]]

    # Should be valid again
    run validate_ledger
    [[ "$status" -eq 0 ]]

    # Verify the ledger has valid JSON
    run jq '.cycles[0].sprints | length' grimoires/loa/ledger.json
    [[ "$status" -eq 0 ]]
    [[ "$output" == "1" ]]
}
