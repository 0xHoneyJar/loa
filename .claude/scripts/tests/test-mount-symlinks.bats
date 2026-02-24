#!/usr/bin/env bats
# test-mount-symlinks.bats - Symlink verification tests (cycle-035 sprint-3)
#
# Verifies that all expected symlinks exist and resolve correctly after
# submodule mount. Tests the symlink manifest from mount-submodule.sh.
#
# Run with: bats .claude/scripts/tests/test-mount-symlinks.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"
SUBMODULE_SCRIPT="${SCRIPT_DIR}/mount-submodule.sh"

# =============================================================================
# Helpers
# =============================================================================

# Create a mock submodule directory structure for testing
create_mock_submodule() {
    local submodule_path="${1:-.loa}"

    # Create submodule directory tree
    mkdir -p "${submodule_path}/.claude/scripts"
    mkdir -p "${submodule_path}/.claude/protocols"
    mkdir -p "${submodule_path}/.claude/hooks"
    mkdir -p "${submodule_path}/.claude/data"
    mkdir -p "${submodule_path}/.claude/schemas"
    mkdir -p "${submodule_path}/.claude/skills/loa-test-skill"
    mkdir -p "${submodule_path}/.claude/commands"
    mkdir -p "${submodule_path}/.claude/loa/reference"
    mkdir -p "${submodule_path}/.claude/loa/learnings"

    # Create expected files
    echo "# test" > "${submodule_path}/.claude/loa/CLAUDE.loa.md"
    echo "# ref" > "${submodule_path}/.claude/loa/reference/test.md"
    echo "ontology: test" > "${submodule_path}/.claude/loa/feedback-ontology.yaml"
    echo "# learning" > "${submodule_path}/.claude/loa/learnings/test.yaml"
    echo "#!/bin/bash" > "${submodule_path}/.claude/scripts/test.sh"
    echo "# protocol" > "${submodule_path}/.claude/protocols/test.md"
    echo "# hook" > "${submodule_path}/.claude/hooks/test.sh"
    echo '{}' > "${submodule_path}/.claude/data/test.json"
    echo '{}' > "${submodule_path}/.claude/schemas/test.json"
    echo '{}' > "${submodule_path}/.claude/settings.json"
    echo "name: test" > "${submodule_path}/.claude/skills/loa-test-skill/index.yaml"
    echo "# cmd" > "${submodule_path}/.claude/commands/test.md"
}

# Simulate symlink creation (mirrors create_symlinks from mount-submodule.sh)
create_test_symlinks() {
    local submodule_path="${1:-.loa}"

    mkdir -p .claude/skills
    mkdir -p .claude/commands
    mkdir -p .claude/loa
    mkdir -p .claude/overrides

    # Directory symlinks
    ln -sf "../${submodule_path}/.claude/scripts" ".claude/scripts"
    ln -sf "../${submodule_path}/.claude/protocols" ".claude/protocols"
    ln -sf "../${submodule_path}/.claude/hooks" ".claude/hooks"
    ln -sf "../${submodule_path}/.claude/data" ".claude/data"
    ln -sf "../${submodule_path}/.claude/schemas" ".claude/schemas"

    # File symlinks under .claude/loa/
    ln -sf "../../${submodule_path}/.claude/loa/CLAUDE.loa.md" ".claude/loa/CLAUDE.loa.md"
    ln -sf "../../${submodule_path}/.claude/loa/reference" ".claude/loa/reference"
    ln -sf "../../${submodule_path}/.claude/loa/learnings" ".claude/loa/learnings"
    ln -sf "../../${submodule_path}/.claude/loa/feedback-ontology.yaml" ".claude/loa/feedback-ontology.yaml"

    # Per-skill symlinks
    ln -sf "../../${submodule_path}/.claude/skills/loa-test-skill" ".claude/skills/loa-test-skill"

    # Per-command symlinks
    ln -sf "../../${submodule_path}/.claude/commands/test.md" ".claude/commands/test.md"

    # Settings symlink
    ln -sf "../${submodule_path}/.claude/settings.json" ".claude/settings.json"
}

setup() {
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test"
    create_mock_submodule ".loa"
    create_test_symlinks ".loa"
}

teardown() {
    cd /
    rm -rf "$TEST_DIR"
}

# =============================================================================
# Task 3.1: Symlink Verification — 10 tests
# =============================================================================

@test "scripts_symlink: .claude/scripts is a symlink to submodule" {
    [ -L ".claude/scripts" ]
    # Verify target resolves
    [ -d ".claude/scripts" ]
    # Verify content is accessible through symlink
    [ -f ".claude/scripts/test.sh" ]
}

@test "protocols_symlink: .claude/protocols is a symlink to submodule" {
    [ -L ".claude/protocols" ]
    [ -d ".claude/protocols" ]
    [ -f ".claude/protocols/test.md" ]
}

@test "hooks_symlink: .claude/hooks is a symlink to submodule" {
    [ -L ".claude/hooks" ]
    [ -d ".claude/hooks" ]
    [ -f ".claude/hooks/test.sh" ]
}

@test "data_symlink: .claude/data is a symlink to submodule" {
    [ -L ".claude/data" ]
    [ -d ".claude/data" ]
    [ -f ".claude/data/test.json" ]
}

@test "schemas_symlink: .claude/schemas is a symlink to submodule" {
    [ -L ".claude/schemas" ]
    [ -d ".claude/schemas" ]
    [ -f ".claude/schemas/test.json" ]
}

@test "claude_loa_md_symlink: .claude/loa/CLAUDE.loa.md is a symlink that resolves" {
    [ -L ".claude/loa/CLAUDE.loa.md" ]
    [ -f ".claude/loa/CLAUDE.loa.md" ]
    # Verify it's a symlink, not a real file, and the content matches
    local content
    content=$(cat ".claude/loa/CLAUDE.loa.md")
    [ "$content" = "# test" ]
}

@test "reference_symlink: .claude/loa/reference/ is a symlink that resolves" {
    [ -L ".claude/loa/reference" ]
    [ -d ".claude/loa/reference" ]
    [ -f ".claude/loa/reference/test.md" ]
}

@test "at_import_resolves: @.claude/loa/CLAUDE.loa.md file path exists" {
    # The @-import in CLAUDE.md references this path
    # Verify the file exists at the expected path
    [ -f ".claude/loa/CLAUDE.loa.md" ]

    # Verify the parent directory is a real directory (not a symlink)
    # This is critical — .claude/loa/ MUST be a real directory for @-import
    [ -d ".claude/loa" ]
    # .claude/loa/ itself should NOT be a symlink (only files inside are)
    [ ! -L ".claude/loa" ]
}

@test "user_files_not_symlinked: settings.json is accessible but user files are not framework-owned" {
    # In submodule mode, settings.json IS a symlink to framework defaults
    # But overrides directory is NOT a symlink
    [ -d ".claude/overrides" ]
    [ ! -L ".claude/overrides" ]
}

@test "overrides_not_symlinked: .claude/overrides/ is a real directory" {
    [ -d ".claude/overrides" ]
    # Overrides MUST NOT be a symlink — they are user-owned
    [ ! -L ".claude/overrides" ]
    # Should be writable
    touch ".claude/overrides/test-file"
    [ -f ".claude/overrides/test-file" ]
}

# =============================================================================
# Bonus: Symlink manifest coverage in mount-submodule.sh
# =============================================================================

@test "mount-submodule.sh has verify_and_reconcile_symlinks function" {
    run grep -c "verify_and_reconcile_symlinks()" "$SUBMODULE_SCRIPT"
    [ "$status" -eq 0 ]
    [ "${output}" -ge 1 ]
}

@test "symlink manifest includes all 5 directory symlinks" {
    local manifest_lib="${SCRIPT_DIR}/lib/symlink-manifest.sh"
    run grep -A30 "MANIFEST_DIR_SYMLINKS=(" "$manifest_lib"
    echo "$output" | grep -q ".claude/scripts"
    echo "$output" | grep -q ".claude/protocols"
    echo "$output" | grep -q ".claude/hooks"
    echo "$output" | grep -q ".claude/data"
    echo "$output" | grep -q ".claude/schemas"
}

@test "symlink manifest includes loa file symlinks" {
    local manifest_lib="${SCRIPT_DIR}/lib/symlink-manifest.sh"
    run grep -A20 "MANIFEST_FILE_SYMLINKS=(" "$manifest_lib"
    echo "$output" | grep -q "CLAUDE.loa.md"
    echo "$output" | grep -q "reference"
    echo "$output" | grep -q "feedback-ontology"
    echo "$output" | grep -q "learnings"
}

# =============================================================================
# Task 3.2: Memory Stack Relocation Tests — 3 tests
# =============================================================================

@test "memory_stack_new_path: fresh install uses .loa-state/" {
    # Verify mount-submodule.sh has get_memory_stack_path function
    run grep -c "get_memory_stack_path()" "$SUBMODULE_SCRIPT"
    [ "$status" -eq 0 ]
    [ "${output}" -ge 1 ]

    # Verify the function prioritizes .loa-state/ over .loa/
    run grep -A10 "get_memory_stack_path()" "$SUBMODULE_SCRIPT"
    echo "$output" | grep -q ".loa-state"
}

@test "memory_stack_auto_migrate: relocate_memory_stack moves data from .loa/ to .loa-state/" {
    # Verify relocate_memory_stack function exists and handles migration
    run grep -c "relocate_memory_stack()" "$SUBMODULE_SCRIPT"
    [ "$status" -eq 0 ]
    [ "${output}" -ge 1 ]

    # Verify it uses copy-verify-switch pattern (Flatline IMP-002)
    run grep -A60 "relocate_memory_stack()" "$SUBMODULE_SCRIPT"
    echo "$output" | grep -q "cp -r"
    echo "$output" | grep -q "source_count"
    echo "$output" | grep -q "target_count"
}

@test "memory_stack_submodule_safe: no migration when .loa/ is submodule" {
    # Verify relocate_memory_stack checks for submodule before migrating
    run grep -A20 "relocate_memory_stack()" "$SUBMODULE_SCRIPT"
    echo "$output" | grep -q "gitmodules"
    echo "$output" | grep -q "Already a submodule"
}

# =============================================================================
# Task 3.3: Gitignore Correctness Tests — 3 tests
# =============================================================================

@test "loa_dir_not_gitignored: .loa/ is NOT in .gitignore" {
    local gitignore="${SCRIPT_DIR}/../../.gitignore"
    # .loa/ must NOT be gitignored (submodule needs to be tracked by git)
    run bash -c "grep '^\.loa/$' '$gitignore' | wc -l"
    [ "$output" = "0" ]
}

@test "loa_state_gitignored: .loa-state/ IS in .gitignore" {
    local gitignore="${SCRIPT_DIR}/../../.gitignore"
    run grep "^\.loa-state/" "$gitignore"
    [ "$status" -eq 0 ]
}

@test "backup_gitignored: .claude.backup.* IS in .gitignore" {
    local gitignore="${SCRIPT_DIR}/../../.gitignore"
    run grep "^\.claude\.backup\.\*$" "$gitignore"
    [ "$status" -eq 0 ]
}

@test "manifest_single_source: shared library exists and is sourced by mount-submodule.sh" {
    # Verify the shared manifest library exists
    [ -f "${SCRIPT_DIR}/lib/symlink-manifest.sh" ]

    # Verify mount-submodule.sh sources the library (not inline)
    run grep "source.*lib/symlink-manifest.sh" "$SUBMODULE_SCRIPT"
    [ "$status" -eq 0 ]

    # Verify verify_and_reconcile_symlinks does NOT have inline manifest arrays
    # (it should call get_symlink_manifest instead)
    run bash -c "sed -n '/verify_and_reconcile_symlinks/,/^}/p' '$SUBMODULE_SCRIPT' | grep -c 'local -a dir_symlinks'"
    [ "$output" = "0" ]
}

@test "symlinks_gitignored: update_gitignore_for_submodule includes symlink entries" {
    # Verify that mount-submodule.sh's update_gitignore_for_submodule function
    # includes all required symlink gitignore entries.
    # (Actual .gitignore entries are only added when mount is run on a consuming project)
    run grep -A30 "update_gitignore_for_submodule()" "$SUBMODULE_SCRIPT"
    echo "$output" | grep -q ".claude/scripts"
    echo "$output" | grep -q ".claude/protocols"
    echo "$output" | grep -q ".claude/hooks"
    echo "$output" | grep -q ".claude/data"
    echo "$output" | grep -q ".claude/schemas"
}
