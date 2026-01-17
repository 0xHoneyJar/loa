#!/usr/bin/env bats
# Unit tests for ledger-lib.sh - Sprint Ledger Library
# Sprint 4: Core Ledger Library
#
# Test coverage:
#   - Initialization functions (init_ledger, init_ledger_from_existing)
#   - Cycle management (create_cycle, get_active_cycle, get_cycle_by_id)
#   - Sprint management (add_sprint, resolve_sprint, update_sprint_status)
#   - Query functions (get_ledger_status, get_cycle_history, validate_ledger)
#   - Error handling (ensure_ledger_backup, recover_from_backup)

# Test setup
setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/ledger-lib.sh"

    # Create temp directory for test artifacts
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/ledger-lib-test-$$"
    mkdir -p "$TEST_TMPDIR"

    # Create mock project structure
    export TEST_PROJECT="$TEST_TMPDIR/project"
    mkdir -p "$TEST_PROJECT/grimoires/loa/a2a"

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
    if [[ ! -f "$SCRIPT" ]]; then
        skip "ledger-lib.sh not available"
    fi
}

# Helper to source the library
source_lib() {
    source "$SCRIPT"
}

# =============================================================================
# Path Function Tests
# =============================================================================

@test "get_ledger_path returns correct path" {
    skip_if_deps_missing
    source_lib

    local result
    result=$(get_ledger_path)

    [[ "$result" == "grimoires/loa/ledger.json" ]]
}

@test "ledger_exists returns false when no ledger" {
    skip_if_deps_missing
    source_lib

    run ledger_exists
    [[ "$status" -eq 1 ]]
}

@test "ledger_exists returns true when ledger exists" {
    skip_if_deps_missing
    source_lib

    # Create a ledger file
    mkdir -p grimoires/loa
    echo '{"version": 1}' > grimoires/loa/ledger.json

    run ledger_exists
    [[ "$status" -eq 0 ]]
}

# =============================================================================
# Initialization Tests
# =============================================================================

@test "init_ledger creates valid ledger" {
    skip_if_deps_missing
    source_lib

    run init_ledger
    [[ "$status" -eq 0 ]]

    # Verify file exists
    [[ -f "grimoires/loa/ledger.json" ]]

    # Verify structure
    local version
    version=$(jq -r '.version' grimoires/loa/ledger.json)
    [[ "$version" == "1" ]]

    local next_sprint
    next_sprint=$(jq -r '.next_sprint_number' grimoires/loa/ledger.json)
    [[ "$next_sprint" == "1" ]]

    local cycles_count
    cycles_count=$(jq '.cycles | length' grimoires/loa/ledger.json)
    [[ "$cycles_count" == "0" ]]
}

@test "init_ledger fails if ledger already exists" {
    skip_if_deps_missing
    source_lib

    # Create existing ledger
    mkdir -p grimoires/loa
    echo '{"version": 1}' > grimoires/loa/ledger.json

    run init_ledger
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"already exists"* ]]
}

@test "init_ledger_from_existing detects existing sprints" {
    skip_if_deps_missing
    source_lib

    # Create existing sprint directories
    mkdir -p grimoires/loa/a2a/sprint-1
    mkdir -p grimoires/loa/a2a/sprint-2
    mkdir -p grimoires/loa/a2a/sprint-3

    run init_ledger_from_existing
    [[ "$status" -eq 0 ]]

    # Verify next_sprint_number is 4
    local next_sprint
    next_sprint=$(jq -r '.next_sprint_number' grimoires/loa/ledger.json)
    [[ "$next_sprint" == "4" ]]
}

@test "init_ledger_from_existing handles empty project" {
    skip_if_deps_missing
    source_lib

    run init_ledger_from_existing
    [[ "$status" -eq 0 ]]

    # Verify next_sprint_number is 1
    local next_sprint
    next_sprint=$(jq -r '.next_sprint_number' grimoires/loa/ledger.json)
    [[ "$next_sprint" == "1" ]]
}

# =============================================================================
# Cycle Management Tests
# =============================================================================

@test "create_cycle generates sequential IDs" {
    skip_if_deps_missing
    source_lib

    init_ledger

    local cycle1
    cycle1=$(create_cycle "First Cycle")
    [[ "$cycle1" == "cycle-001" ]]

    # Archive first cycle to allow second
    local ledger_content
    ledger_content=$(jq '.active_cycle = null | .cycles[0].status = "archived"' grimoires/loa/ledger.json)
    echo "$ledger_content" > grimoires/loa/ledger.json

    local cycle2
    cycle2=$(create_cycle "Second Cycle")
    [[ "$cycle2" == "cycle-002" ]]
}

@test "create_cycle sets active_cycle" {
    skip_if_deps_missing
    source_lib

    init_ledger
    create_cycle "Test Cycle"

    local active
    active=$(jq -r '.active_cycle' grimoires/loa/ledger.json)
    [[ "$active" == "cycle-001" ]]
}

@test "create_cycle fails if active cycle exists" {
    skip_if_deps_missing
    source_lib

    init_ledger
    create_cycle "First Cycle"

    run create_cycle "Second Cycle"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"already exists"* ]]
}

@test "get_active_cycle returns cycle ID" {
    skip_if_deps_missing
    source_lib

    init_ledger
    create_cycle "Test Cycle"

    local result
    result=$(get_active_cycle)
    [[ "$result" == "cycle-001" ]]
}

@test "get_active_cycle returns null when no active" {
    skip_if_deps_missing
    source_lib

    init_ledger

    local result
    result=$(get_active_cycle)
    [[ "$result" == "null" ]]
}

@test "get_cycle_by_id returns cycle object" {
    skip_if_deps_missing
    source_lib

    init_ledger
    create_cycle "Test Cycle"

    local cycle_json
    cycle_json=$(get_cycle_by_id "cycle-001")

    local label
    label=$(echo "$cycle_json" | jq -r '.label')
    [[ "$label" == "Test Cycle" ]]
}

# =============================================================================
# Sprint Management Tests
# =============================================================================

@test "allocate_sprint_number increments counter" {
    skip_if_deps_missing
    source_lib

    init_ledger

    local num1
    num1=$(allocate_sprint_number)
    [[ "$num1" == "1" ]]

    local num2
    num2=$(allocate_sprint_number)
    [[ "$num2" == "2" ]]

    local num3
    num3=$(allocate_sprint_number)
    [[ "$num3" == "3" ]]
}

@test "add_sprint adds sprint to active cycle" {
    skip_if_deps_missing
    source_lib

    init_ledger
    create_cycle "Test Cycle"

    local global_id
    global_id=$(add_sprint "sprint-1")
    [[ "$global_id" == "1" ]]

    # Verify sprint in cycle
    local sprint_count
    sprint_count=$(jq '.cycles[0].sprints | length' grimoires/loa/ledger.json)
    [[ "$sprint_count" == "1" ]]

    local sprint_label
    sprint_label=$(jq -r '.cycles[0].sprints[0].local_label' grimoires/loa/ledger.json)
    [[ "$sprint_label" == "sprint-1" ]]
}

@test "add_sprint fails without active cycle" {
    skip_if_deps_missing
    source_lib

    init_ledger

    run add_sprint "sprint-1"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"No active cycle"* ]]
}

@test "resolve_sprint maps local to global ID" {
    skip_if_deps_missing
    source_lib

    init_ledger
    create_cycle "Test Cycle"
    add_sprint "sprint-1"

    local result
    result=$(resolve_sprint "sprint-1")
    [[ "$result" == "1" ]]
}

@test "resolve_sprint passes through global IDs" {
    skip_if_deps_missing
    source_lib

    init_ledger
    create_cycle "Test Cycle"
    add_sprint "sprint-1"

    # Resolve by global ID should pass through
    local result
    result=$(resolve_sprint "sprint-1")
    [[ "$result" == "1" ]]

    # Now try with a number that exists globally
    # It should find it
    result=$(resolve_sprint "1")
    [[ "$result" != "UNRESOLVED" ]]
}

@test "resolve_sprint returns UNRESOLVED for unknown sprint" {
    skip_if_deps_missing
    source_lib

    init_ledger
    create_cycle "Test Cycle"

    # Use run to capture exit code and output properly
    run resolve_sprint "sprint-99"
    [[ "$status" -eq 4 ]]  # LEDGER_SPRINT_NOT_FOUND
    [[ "$output" == "UNRESOLVED" ]]
}

@test "resolve_sprint works without ledger (legacy mode)" {
    skip_if_deps_missing
    source_lib

    # No ledger exists
    local result
    result=$(resolve_sprint "sprint-5")
    [[ "$result" == "5" ]]
}

@test "update_sprint_status changes status" {
    skip_if_deps_missing
    source_lib

    init_ledger
    create_cycle "Test Cycle"
    add_sprint "sprint-1"

    update_sprint_status 1 "in_progress"

    local status
    status=$(jq -r '.cycles[0].sprints[0].status' grimoires/loa/ledger.json)
    [[ "$status" == "in_progress" ]]
}

@test "update_sprint_status sets completed timestamp" {
    skip_if_deps_missing
    source_lib

    init_ledger
    create_cycle "Test Cycle"
    add_sprint "sprint-1"

    update_sprint_status 1 "completed"

    local completed
    completed=$(jq -r '.cycles[0].sprints[0].completed' grimoires/loa/ledger.json)
    [[ "$completed" != "null" ]]
}

@test "get_sprint_directory returns correct path" {
    skip_if_deps_missing
    source_lib

    local result
    result=$(get_sprint_directory 5)
    [[ "$result" == "grimoires/loa/a2a/sprint-5" ]]
}

# =============================================================================
# Query Function Tests
# =============================================================================

@test "get_ledger_status returns summary JSON" {
    skip_if_deps_missing
    source_lib

    init_ledger
    create_cycle "Test Cycle"
    add_sprint "sprint-1"
    add_sprint "sprint-2"

    local status_json
    status_json=$(get_ledger_status)

    local active_cycle
    active_cycle=$(echo "$status_json" | jq -r '.active_cycle')
    [[ "$active_cycle" == "cycle-001" ]]

    local next_sprint
    next_sprint=$(echo "$status_json" | jq -r '.next_sprint_number')
    [[ "$next_sprint" == "3" ]]
}

@test "get_cycle_history returns all cycles" {
    skip_if_deps_missing
    source_lib

    init_ledger
    create_cycle "First Cycle"
    add_sprint "sprint-1"

    local history
    history=$(get_cycle_history)

    local count
    count=$(echo "$history" | jq 'length')
    [[ "$count" == "1" ]]

    local label
    label=$(echo "$history" | jq -r '.[0].label')
    [[ "$label" == "First Cycle" ]]
}

@test "validate_ledger accepts valid ledger" {
    skip_if_deps_missing
    source_lib

    init_ledger

    run validate_ledger
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"valid"* ]]
}

@test "validate_ledger rejects invalid JSON" {
    skip_if_deps_missing
    source_lib

    mkdir -p grimoires/loa
    echo "not valid json" > grimoires/loa/ledger.json

    run validate_ledger
    [[ "$status" -eq 5 ]]
    [[ "$output" == *"Invalid JSON"* ]]
}

@test "validate_ledger rejects missing fields" {
    skip_if_deps_missing
    source_lib

    mkdir -p grimoires/loa
    echo '{"cycles": []}' > grimoires/loa/ledger.json

    run validate_ledger
    [[ "$status" -eq 5 ]]
    [[ "$output" == *"Missing"* ]]
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "ensure_ledger_backup creates backup file" {
    skip_if_deps_missing
    source_lib

    init_ledger
    ensure_ledger_backup

    [[ -f "grimoires/loa/ledger.json.bak" ]]
}

@test "recover_from_backup restores ledger" {
    skip_if_deps_missing
    source_lib

    init_ledger
    ensure_ledger_backup

    # Corrupt the ledger
    echo "corrupted" > grimoires/loa/ledger.json

    run recover_from_backup
    [[ "$status" -eq 0 ]]

    # Verify restored
    local version
    version=$(jq -r '.version' grimoires/loa/ledger.json)
    [[ "$version" == "1" ]]
}

@test "recover_from_backup fails without backup" {
    skip_if_deps_missing
    source_lib

    init_ledger
    # No backup created

    run recover_from_backup
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# Safe Resolution Tests
# =============================================================================

@test "resolve_sprint_safe always returns valid ID" {
    skip_if_deps_missing
    source_lib

    # Without ledger - should fallback
    local result
    result=$(resolve_sprint_safe "sprint-5")
    [[ "$result" == "5" ]]

    # With ledger and existing sprint
    init_ledger
    create_cycle "Test Cycle"
    add_sprint "sprint-1"

    result=$(resolve_sprint_safe "sprint-1")
    [[ "$result" == "1" ]]

    # With ledger but unknown sprint - should fallback
    result=$(resolve_sprint_safe "sprint-99")
    [[ "$result" == "99" ]]
}

# =============================================================================
# Archive Function Tests
# =============================================================================

@test "archive_cycle creates archive directory" {
    skip_if_deps_missing
    source_lib

    init_ledger
    create_cycle "Test Cycle"
    add_sprint "sprint-1"

    # Create some files to archive
    echo "# PRD" > grimoires/loa/prd.md
    echo "# SDD" > grimoires/loa/sdd.md
    mkdir -p grimoires/loa/a2a/sprint-1
    echo "review" > grimoires/loa/a2a/sprint-1/reviewer.md

    local archive_path
    archive_path=$(archive_cycle "test-archive")

    # Verify archive exists
    [[ -d "$archive_path" ]]
    [[ -f "$archive_path/prd.md" ]]
    [[ -f "$archive_path/sdd.md" ]]
    [[ -d "$archive_path/a2a/sprint-1" ]]
}

@test "archive_cycle updates ledger status" {
    skip_if_deps_missing
    source_lib

    init_ledger
    create_cycle "Test Cycle"

    archive_cycle "test-archive"

    # Verify cycle is archived
    local status
    status=$(jq -r '.cycles[0].status' grimoires/loa/ledger.json)
    [[ "$status" == "archived" ]]

    # Verify active_cycle is null
    local active
    active=$(jq -r '.active_cycle' grimoires/loa/ledger.json)
    [[ "$active" == "null" ]]
}

@test "archive_cycle fails without active cycle" {
    skip_if_deps_missing
    source_lib

    init_ledger

    run archive_cycle "test-archive"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"No active cycle"* ]]
}

# =============================================================================
# Multi-Cycle Workflow Test
# =============================================================================

@test "full multi-cycle workflow works correctly" {
    skip_if_deps_missing
    source_lib

    # Initialize
    init_ledger

    # Cycle 1
    create_cycle "MVP Development"
    local s1
    s1=$(add_sprint "sprint-1")
    [[ "$s1" == "1" ]]

    local s2
    s2=$(add_sprint "sprint-2")
    [[ "$s2" == "2" ]]

    # Archive cycle 1
    archive_cycle "mvp-complete"

    # Cycle 2
    create_cycle "Feature Development"
    local s3
    s3=$(add_sprint "sprint-1")  # Note: local label is sprint-1
    [[ "$s3" == "3" ]]  # But global ID is 3

    # Resolve sprint-1 in cycle 2
    local resolved
    resolved=$(resolve_sprint "sprint-1")
    [[ "$resolved" == "3" ]]  # Should be 3, not 1

    # Check status
    local status_json
    status_json=$(get_ledger_status)

    local archived_count
    archived_count=$(echo "$status_json" | jq -r '.archived_cycles')
    [[ "$archived_count" == "1" ]]

    local next_sprint
    next_sprint=$(echo "$status_json" | jq -r '.next_sprint_number')
    [[ "$next_sprint" == "4" ]]
}
