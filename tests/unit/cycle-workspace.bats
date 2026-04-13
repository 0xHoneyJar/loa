#!/usr/bin/env bats
# =============================================================================
# cycle-workspace.bats — cycle-064 regression tests
# =============================================================================
# Verifies the per-cycle workspace manager for RFC-060 #483 Friction 9.
# Tests init/switch/list/active/status commands against a temp grimoire dir.
# =============================================================================

setup() {
    # Create a temp dir that looks like a Loa project root so bootstrap.sh's
    # _detect_project_root finds it. Putting a .claude/ subdir there makes
    # the walk-up detection succeed when we cd into it.
    export PROJECT_ROOT
    PROJECT_ROOT=$(mktemp -d)
    mkdir -p "$PROJECT_ROOT/.claude"
    touch "$PROJECT_ROOT/.loa.config.yaml"

    # Point grimoire inside the fake project so path-lib's workspace check
    # passes. Path-lib requires LOA_GRIMOIRE_DIR to start with PROJECT_ROOT.
    export LOA_GRIMOIRE_DIR="$PROJECT_ROOT/grimoires/loa"
    mkdir -p "$LOA_GRIMOIRE_DIR"

    # Work from the fake project root so git rev-parse and the walk-up
    # fallback both resolve PROJECT_ROOT correctly.
    cd "$PROJECT_ROOT"
    # Init git so bootstrap.sh's git-toplevel strategy lands on this dir
    # rather than the real Loa repo where bats was invoked from.
    git init -q -b main
    git config user.email test@test
    git config user.name test

    SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/cycle-workspace.sh"
}

teardown() {
    cd /
    rm -rf "$PROJECT_ROOT"
}

# =============================================================================
# T1: init creates cycle dir + empty artifacts + active symlink
# =============================================================================
@test "init: creates cycle dir with empty artifacts and active symlink" {
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-test-001 >/dev/null

    [ -d "$LOA_GRIMOIRE_DIR/cycles/cycle-test-001" ]
    [ -f "$LOA_GRIMOIRE_DIR/cycles/cycle-test-001/prd.md" ]
    [ -f "$LOA_GRIMOIRE_DIR/cycles/cycle-test-001/sdd.md" ]
    [ -f "$LOA_GRIMOIRE_DIR/cycles/cycle-test-001/sprint.md" ]
    [ -L "$LOA_GRIMOIRE_DIR/cycles/active" ]
    [ "$(readlink "$LOA_GRIMOIRE_DIR/cycles/active")" = "cycle-test-001" ]
}

# =============================================================================
# T2: init wires top-level symlinks to cycles/active
# =============================================================================
@test "init: top-level prd/sdd/sprint become symlinks to cycles/active" {
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-test-001 >/dev/null

    [ -L "$LOA_GRIMOIRE_DIR/prd.md" ]
    [ -L "$LOA_GRIMOIRE_DIR/sdd.md" ]
    [ -L "$LOA_GRIMOIRE_DIR/sprint.md" ]
    [ "$(readlink "$LOA_GRIMOIRE_DIR/prd.md")" = "cycles/active/prd.md" ]
}

# =============================================================================
# T3: init auto-migrates pre-existing top-level regular files (no data loss)
# =============================================================================
@test "init: migrates pre-existing top-level regular files into cycle dir" {
    # Create a pre-existing prd.md with content
    echo "# Legacy PRD content" > "$LOA_GRIMOIRE_DIR/prd.md"
    echo "# Legacy SDD content" > "$LOA_GRIMOIRE_DIR/sdd.md"

    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-test-001 >/dev/null

    # Content must now be inside the cycle dir
    grep -q "Legacy PRD content" "$LOA_GRIMOIRE_DIR/cycles/cycle-test-001/prd.md"
    grep -q "Legacy SDD content" "$LOA_GRIMOIRE_DIR/cycles/cycle-test-001/sdd.md"
    # Top-level must now be a symlink pointing at the cycle
    [ -L "$LOA_GRIMOIRE_DIR/prd.md" ]
    # Reading through the symlink must surface the legacy content
    grep -q "Legacy PRD content" "$LOA_GRIMOIRE_DIR/prd.md"
}

# =============================================================================
# T4: init is idempotent — re-running leaves state unchanged
# =============================================================================
@test "init: idempotent on same cycle-id" {
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-test-001 >/dev/null
    # Write some content into the active cycle's prd
    echo "# Cycle 1 work" > "$LOA_GRIMOIRE_DIR/cycles/cycle-test-001/prd.md"

    # Re-run init — must NOT clobber content
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-test-001 >/dev/null

    grep -q "Cycle 1 work" "$LOA_GRIMOIRE_DIR/cycles/cycle-test-001/prd.md"
}

# =============================================================================
# T5: switch updates active symlink without recreating content
# =============================================================================
@test "switch: updates active symlink to target cycle" {
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-test-001 >/dev/null
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-test-002 >/dev/null
    # After second init, active points at cycle-test-002
    [ "$(readlink "$LOA_GRIMOIRE_DIR/cycles/active")" = "cycle-test-002" ]

    # Switch back to cycle-test-001
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" switch cycle-test-001 >/dev/null
    [ "$(readlink "$LOA_GRIMOIRE_DIR/cycles/active")" = "cycle-test-001" ]
}

# =============================================================================
# T6: switch refuses non-existent cycle
# =============================================================================
@test "switch: refuses non-existent cycle (exit 2)" {
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-test-001 >/dev/null

    set +e
    output=$(env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" switch cycle-nonexistent 2>&1)
    exit_code=$?
    set -e

    [ "$exit_code" -eq 2 ]
    [[ "$output" == *"does not exist"* ]]
}

# =============================================================================
# T7: list returns all cycles as JSON array
# =============================================================================
@test "list: returns JSON array of cycle ids" {
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-a >/dev/null
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-b >/dev/null
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-c >/dev/null

    local output
    output=$(env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" list)

    # Must be a JSON array
    echo "$output" | jq -e 'type == "array"' >/dev/null
    # Must contain our three cycles
    echo "$output" | jq -e 'contains(["cycle-a", "cycle-b", "cycle-c"])' >/dev/null
}

# =============================================================================
# T8: active prints current cycle id
# =============================================================================
@test "active: prints current active cycle id" {
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-test-001 >/dev/null

    local output
    output=$(env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" active)
    [ "$output" = "cycle-test-001" ]
}

# =============================================================================
# T9: active returns empty string when no active symlink
# =============================================================================
@test "active: returns empty when no active cycle" {
    local output
    output=$(env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" active)
    [ -z "$output" ]
}

# =============================================================================
# T10: status returns JSON with active + cycles + artifact state
# =============================================================================
@test "status: returns JSON with active, cycles array, artifact state" {
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-test-001 >/dev/null

    local output
    output=$(env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" status)

    echo "$output" | jq -e '.active == "cycle-test-001"' >/dev/null
    echo "$output" | jq -e '.cycles | type == "array"' >/dev/null
    echo "$output" | jq -e '.top_level_artifacts."prd.md" == "linked"' >/dev/null
    echo "$output" | jq -e '.top_level_artifacts."sdd.md" == "linked"' >/dev/null
    echo "$output" | jq -e '.top_level_artifacts."sprint.md" == "linked"' >/dev/null
}

# =============================================================================
# T11: validate_cycle_id rejects path-traversal attempts
# =============================================================================
@test "init: rejects cycle-id with path-traversal chars" {
    set +e
    output=$(env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init "../../etc" 2>&1)
    exit_code=$?
    set -e

    [ "$exit_code" -eq 1 ]
    [[ "$output" == *"must match"* ]]
    # No cycle dir with traversal chars created
    [ ! -d "$LOA_GRIMOIRE_DIR/cycles/../../etc" ]
}

# =============================================================================
# T12: reserved names are rejected
# =============================================================================
@test "init: rejects reserved cycle-id 'active'" {
    set +e
    output=$(env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init active 2>&1)
    exit_code=$?
    set -e

    [ "$exit_code" -eq 1 ]
    [[ "$output" == *"reserved"* ]]
}

# =============================================================================
# T13: top-level symlink resolves to the active cycle's artifact
# =============================================================================
@test "backward-compat: reading through top-level symlink surfaces active cycle content" {
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-test-001 >/dev/null
    echo "# Active cycle PRD" > "$LOA_GRIMOIRE_DIR/cycles/cycle-test-001/prd.md"

    # Reading from the top-level path must surface active cycle's content
    grep -q "Active cycle PRD" "$LOA_GRIMOIRE_DIR/prd.md"

    # Initialize a second cycle and switch to it with different content
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-test-002 >/dev/null
    echo "# Second cycle PRD" > "$LOA_GRIMOIRE_DIR/cycles/cycle-test-002/prd.md"

    # Top-level must now reflect cycle-002
    grep -q "Second cycle PRD" "$LOA_GRIMOIRE_DIR/prd.md"
    ! grep -q "Active cycle PRD" "$LOA_GRIMOIRE_DIR/prd.md"

    # Switch back — top-level should flip
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" switch cycle-test-001 >/dev/null
    grep -q "Active cycle PRD" "$LOA_GRIMOIRE_DIR/prd.md"
}

# =============================================================================
# T14: init refuses to clobber when both top-level AND active cycle have content
# =============================================================================
@test "init: refuses to migrate when active cycle's slot already has content" {
    # Init cycle-a and write content into its slot
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-a >/dev/null
    echo "# Cycle-a content" > "$LOA_GRIMOIRE_DIR/cycles/cycle-a/prd.md"

    # Now break the invariant by deleting the top-level symlink and making
    # a regular file with conflicting content.
    rm -f "$LOA_GRIMOIRE_DIR/prd.md"
    echo "# Conflicting top-level content" > "$LOA_GRIMOIRE_DIR/prd.md"

    # Re-init cycle-a — should refuse the migration for prd.md (active slot
    # already has content; clobbering it would lose work).
    set +e
    output=$(env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-a 2>&1)
    exit_code=$?
    set -e

    [ "$exit_code" -eq 2 ]
    [[ "$output" == *"already has content"* ]]
    # Top-level file must remain intact (no data loss)
    [ -f "$LOA_GRIMOIRE_DIR/prd.md" ]
    grep -q "Conflicting top-level content" "$LOA_GRIMOIRE_DIR/prd.md"
}

# =============================================================================
# T16 (follow-up): init is atomic — failed migration rolls back cleanly
# =============================================================================
@test "init: migration failure rolls back active symlink (atomicity)" {
    # First init establishes a clean cycle-a workspace
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-a >/dev/null

    # Seed cycle-b's prd slot with content AND plant a conflicting
    # top-level file. The prd migration will collide; sdd/sprint would
    # have been fine. Atomicity requires we abort WITHOUT half-wiring.
    mkdir -p "$LOA_GRIMOIRE_DIR/cycles/cycle-b"
    echo "cycle-b prd content" > "$LOA_GRIMOIRE_DIR/cycles/cycle-b/prd.md"
    touch "$LOA_GRIMOIRE_DIR/cycles/cycle-b/sdd.md"
    touch "$LOA_GRIMOIRE_DIR/cycles/cycle-b/sprint.md"

    # Break the symlink invariant: remove top-level prd.md symlink and
    # replace with a regular file that would collide with cycle-b's slot.
    rm -f "$LOA_GRIMOIRE_DIR/prd.md"
    echo "top-level conflict content" > "$LOA_GRIMOIRE_DIR/prd.md"

    # Attempt init cycle-b — must fail with exit 2
    set +e
    env LOA_GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR" "$SCRIPT" init cycle-b >/dev/null 2>&1
    exit_code=$?
    set -e
    [ "$exit_code" -eq 2 ]

    # Atomicity: active must still point at cycle-a (rolled back)
    [ "$(readlink "$LOA_GRIMOIRE_DIR/cycles/active")" = "cycle-a" ]

    # Top-level file content must be preserved intact (no data loss)
    grep -q "top-level conflict content" "$LOA_GRIMOIRE_DIR/prd.md"
}

# =============================================================================
# T15: validates usage help output
# =============================================================================
@test "cli: help output documents all commands" {
    local output
    output=$("$SCRIPT" --help 2>&1)

    [[ "$output" == *"init"* ]]
    [[ "$output" == *"switch"* ]]
    [[ "$output" == *"list"* ]]
    [[ "$output" == *"active"* ]]
    [[ "$output" == *"status"* ]]
}
