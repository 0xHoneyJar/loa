#!/usr/bin/env bats
# Unit tests for .claude/scripts/constructs-install.sh
# Tests pack and skill installation, symlinking, and uninstallation
#
# GitHub Issues:
#   #20 - Add CLI install command for Loa Constructs packs
#   #21 - Pack commands not automatically available after installation

# Test setup
setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures"
    INSTALL_SCRIPT="$PROJECT_ROOT/.claude/scripts/constructs-install.sh"
    LOADER_SCRIPT="$PROJECT_ROOT/.claude/scripts/constructs-loader.sh"

    # Create temp directory for test artifacts
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/constructs-install-test-$$"
    mkdir -p "$TEST_TMPDIR"

    # Override directories for testing
    export LOA_CONSTRUCTS_DIR="$TEST_TMPDIR/.claude/constructs"
    mkdir -p "$LOA_CONSTRUCTS_DIR/skills"
    mkdir -p "$LOA_CONSTRUCTS_DIR/packs"
    mkdir -p "$TEST_TMPDIR/.claude/commands"

    # Override cache directory
    export LOA_CACHE_DIR="$TEST_TMPDIR/.loa/cache"
    mkdir -p "$LOA_CACHE_DIR/public-keys"

    # Copy mock public key
    if [[ -f "$FIXTURES_DIR/mock_public_key.pem" ]]; then
        cp "$FIXTURES_DIR/mock_public_key.pem" "$LOA_CACHE_DIR/public-keys/test-key-01.pem"
        cat > "$LOA_CACHE_DIR/public-keys/test-key-01.meta.json" << EOF
{
    "key_id": "test-key-01",
    "algorithm": "RS256",
    "fetched_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "expires_at": "2030-01-01T00:00:00Z"
}
EOF
    fi

    # Set offline mode to prevent actual API calls during tests
    export LOA_OFFLINE=0

    # Change to temp directory for tests
    cd "$TEST_TMPDIR"

    # Create .gitignore and .git directory to simulate git repo
    mkdir -p .git
    touch .gitignore

    # Source the library for helper functions
    if [[ -f "$PROJECT_ROOT/.claude/scripts/constructs-lib.sh" ]]; then
        source "$PROJECT_ROOT/.claude/scripts/constructs-lib.sh"
    fi
}

teardown() {
    # Return to original directory
    cd /

    # Clean up temp directory
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# Helper to skip if script not implemented
skip_if_not_implemented() {
    if [[ ! -f "$INSTALL_SCRIPT" ]]; then
        skip "constructs-install.sh not yet implemented"
    fi
    if [[ ! -x "$INSTALL_SCRIPT" ]]; then
        skip "constructs-install.sh not executable"
    fi
}

# Helper to create a mock installed pack
create_mock_pack() {
    local pack_slug="$1"
    local pack_dir="$LOA_CONSTRUCTS_DIR/packs/$pack_slug"

    mkdir -p "$pack_dir/skills/test-skill"
    mkdir -p "$pack_dir/commands"

    # Create manifest
    cat > "$pack_dir/manifest.json" << EOF
{
    "name": "$pack_slug",
    "version": "1.0.0",
    "description": "Test pack",
    "skills": [
        {"slug": "test-skill", "name": "Test Skill"}
    ]
}
EOF

    # Create license
    cat > "$pack_dir/.license.json" << EOF
{
    "token": "test-jwt-token",
    "expires_at": "2030-01-01T00:00:00Z",
    "user_id": "test-user",
    "plan": "pro"
}
EOF

    # Create a test command
    cat > "$pack_dir/commands/test-command.md" << EOF
# Test Command
This is a test command for the pack.
EOF

    # Create a test skill
    cat > "$pack_dir/skills/test-skill/index.yaml" << EOF
name: test-skill
version: "1.0.0"
description: Test skill
EOF

    cat > "$pack_dir/skills/test-skill/SKILL.md" << EOF
# Test Skill
This is a test skill.
EOF

    echo "$pack_dir"
}

# =============================================================================
# Script Structure Tests
# =============================================================================

@test "constructs-install.sh exists and is executable" {
    skip_if_not_implemented
    [ -f "$INSTALL_SCRIPT" ]
    [ -x "$INSTALL_SCRIPT" ]
}

@test "constructs-install.sh shows usage with --help" {
    skip_if_not_implemented
    run "$INSTALL_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"pack"* ]]
    [[ "$output" == *"skill"* ]]
    [[ "$output" == *"uninstall"* ]]
}

@test "constructs-install.sh shows error without arguments" {
    skip_if_not_implemented
    run "$INSTALL_SCRIPT"
    [ "$status" -ne 0 ]
}

@test "constructs-install.sh pack requires slug argument" {
    skip_if_not_implemented
    run "$INSTALL_SCRIPT" pack
    [ "$status" -ne 0 ]
    [[ "$output" == *"Missing pack slug"* ]] || [[ "$output" == *"ERROR"* ]]
}

@test "constructs-install.sh skill requires slug argument" {
    skip_if_not_implemented
    run "$INSTALL_SCRIPT" skill
    [ "$status" -ne 0 ]
    [[ "$output" == *"Missing skill slug"* ]] || [[ "$output" == *"ERROR"* ]]
}

# =============================================================================
# Authentication Tests
# =============================================================================

@test "pack install fails without API key" {
    skip_if_not_implemented
    # Ensure no API key is set
    unset LOA_CONSTRUCTS_API_KEY

    run "$INSTALL_SCRIPT" pack test-pack
    [ "$status" -eq 1 ]  # AUTH_ERROR
    [[ "$output" == *"No API key"* ]] || [[ "$output" == *"authenticate"* ]]
}

@test "skill install fails without API key" {
    skip_if_not_implemented
    unset LOA_CONSTRUCTS_API_KEY

    run "$INSTALL_SCRIPT" skill test/skill
    [ "$status" -eq 1 ]  # AUTH_ERROR
    [[ "$output" == *"No API key"* ]] || [[ "$output" == *"authenticate"* ]]
}

# =============================================================================
# Command Symlinking Tests (Issue #21)
# =============================================================================

@test "symlink_pack_commands creates symlinks in .claude/commands/" {
    skip_if_not_implemented

    # Create a mock pack with commands
    local pack_dir
    pack_dir=$(create_mock_pack "test-pack")

    # Source the script to get access to functions
    source "$INSTALL_SCRIPT"

    # Run symlink function
    cd "$TEST_TMPDIR"
    local linked
    linked=$(symlink_pack_commands "test-pack")

    # Check symlink was created
    [ -L "$TEST_TMPDIR/.claude/commands/test-command.md" ]

    # Check it points to the right place
    local target
    target=$(readlink "$TEST_TMPDIR/.claude/commands/test-command.md")
    [[ "$target" == *"constructs/packs/test-pack/commands/test-command.md"* ]]
}

@test "symlink_pack_commands returns count of linked commands" {
    skip_if_not_implemented

    # Create mock pack with multiple commands
    local pack_dir="$LOA_CONSTRUCTS_DIR/packs/multi-cmd-pack"
    mkdir -p "$pack_dir/commands"
    echo "# Cmd 1" > "$pack_dir/commands/cmd1.md"
    echo "# Cmd 2" > "$pack_dir/commands/cmd2.md"
    echo "# Cmd 3" > "$pack_dir/commands/cmd3.md"

    source "$INSTALL_SCRIPT"
    cd "$TEST_TMPDIR"

    local linked
    linked=$(symlink_pack_commands "multi-cmd-pack")

    [ "$linked" -eq 3 ]
}

@test "symlink_pack_commands skips existing user files" {
    skip_if_not_implemented

    # Create a user file that shouldn't be overwritten
    echo "# User's custom command" > "$TEST_TMPDIR/.claude/commands/user-cmd.md"

    # Create mock pack with same command name
    local pack_dir="$LOA_CONSTRUCTS_DIR/packs/conflict-pack"
    mkdir -p "$pack_dir/commands"
    echo "# Pack command" > "$pack_dir/commands/user-cmd.md"

    source "$INSTALL_SCRIPT"
    cd "$TEST_TMPDIR"

    run symlink_pack_commands "conflict-pack"

    # Should NOT be a symlink (user file preserved)
    [ ! -L "$TEST_TMPDIR/.claude/commands/user-cmd.md" ]

    # Content should still be user's
    run cat "$TEST_TMPDIR/.claude/commands/user-cmd.md"
    [[ "$output" == *"User's custom command"* ]]
}

@test "unlink_pack_commands removes symlinks" {
    skip_if_not_implemented

    # Create and link a pack
    create_mock_pack "unlink-test-pack"

    source "$INSTALL_SCRIPT"
    cd "$TEST_TMPDIR"

    # Ensure commands directory exists
    mkdir -p "$TEST_TMPDIR/.claude/commands"

    # Create symlinks manually for this test
    ln -sf "../constructs/packs/unlink-test-pack/commands/test-command.md" "$TEST_TMPDIR/.claude/commands/test-command.md"
    [ -L "$TEST_TMPDIR/.claude/commands/test-command.md" ]

    # Remove symlinks
    local unlinked
    unlinked=$(unlink_pack_commands "unlink-test-pack")

    [ ! -L "$TEST_TMPDIR/.claude/commands/test-command.md" ]
    [ "$unlinked" -eq 1 ]
}

# =============================================================================
# Skill Symlinking Tests
# =============================================================================

@test "symlink_pack_skills creates symlinks in constructs/skills/" {
    skip_if_not_implemented

    create_mock_pack "skill-link-pack"

    source "$INSTALL_SCRIPT"
    cd "$TEST_TMPDIR"

    local linked
    linked=$(symlink_pack_skills "skill-link-pack")

    # Check symlink was created
    [ -L "$LOA_CONSTRUCTS_DIR/skills/skill-link-pack/test-skill" ]
    [ "$linked" -eq 1 ]
}

@test "unlink_pack_skills removes skill symlinks" {
    skip_if_not_implemented

    create_mock_pack "skill-unlink-pack"

    source "$INSTALL_SCRIPT"
    cd "$TEST_TMPDIR"

    # Create skill symlinks directory manually for this test
    mkdir -p "$LOA_CONSTRUCTS_DIR/skills/skill-unlink-pack"
    ln -sf "../../packs/skill-unlink-pack/skills/test-skill" "$LOA_CONSTRUCTS_DIR/skills/skill-unlink-pack/test-skill"
    [ -d "$LOA_CONSTRUCTS_DIR/skills/skill-unlink-pack" ]

    # Remove symlinks
    unlink_pack_skills "skill-unlink-pack"
    [ ! -d "$LOA_CONSTRUCTS_DIR/skills/skill-unlink-pack" ]
}

# =============================================================================
# Uninstall Tests
# =============================================================================

@test "uninstall pack removes pack directory" {
    skip_if_not_implemented

    # Create a mock pack
    create_mock_pack "remove-pack"

    source "$INSTALL_SCRIPT"
    cd "$TEST_TMPDIR"

    # Create symlinks manually
    mkdir -p "$TEST_TMPDIR/.claude/commands"
    ln -sf "../constructs/packs/remove-pack/commands/test-command.md" "$TEST_TMPDIR/.claude/commands/test-command.md"
    mkdir -p "$LOA_CONSTRUCTS_DIR/skills/remove-pack"
    ln -sf "../../packs/remove-pack/skills/test-skill" "$LOA_CONSTRUCTS_DIR/skills/remove-pack/test-skill"

    # Verify pack exists
    [ -d "$LOA_CONSTRUCTS_DIR/packs/remove-pack" ]
    [ -L "$TEST_TMPDIR/.claude/commands/test-command.md" ]

    # Uninstall
    run do_uninstall_pack "remove-pack"
    [ "$status" -eq 0 ]

    # Verify removal
    [ ! -d "$LOA_CONSTRUCTS_DIR/packs/remove-pack" ]
    [ ! -L "$TEST_TMPDIR/.claude/commands/test-command.md" ]
}

@test "uninstall pack fails for non-existent pack" {
    skip_if_not_implemented

    source "$INSTALL_SCRIPT"
    cd "$TEST_TMPDIR"

    run do_uninstall_pack "nonexistent-pack"
    [ "$status" -eq 3 ]  # NOT_FOUND
}

# =============================================================================
# link-commands Tests
# =============================================================================

@test "link-commands all links commands for all packs" {
    skip_if_not_implemented

    # Create multiple packs
    local pack1_dir="$LOA_CONSTRUCTS_DIR/packs/pack1"
    local pack2_dir="$LOA_CONSTRUCTS_DIR/packs/pack2"
    mkdir -p "$pack1_dir/commands" "$pack2_dir/commands"
    echo "# Pack1 Cmd" > "$pack1_dir/commands/pack1-cmd.md"
    echo "# Pack2 Cmd" > "$pack2_dir/commands/pack2-cmd.md"

    cd "$TEST_TMPDIR"
    run "$INSTALL_SCRIPT" link-commands all

    [ "$status" -eq 0 ]
    [ -L "$TEST_TMPDIR/.claude/commands/pack1-cmd.md" ]
    [ -L "$TEST_TMPDIR/.claude/commands/pack2-cmd.md" ]
}

@test "link-commands specific pack only links that pack" {
    skip_if_not_implemented

    # Create multiple packs
    local pack1_dir="$LOA_CONSTRUCTS_DIR/packs/specific-pack"
    local pack2_dir="$LOA_CONSTRUCTS_DIR/packs/other-pack"
    mkdir -p "$pack1_dir/commands" "$pack2_dir/commands"
    echo "# Specific Cmd" > "$pack1_dir/commands/specific-cmd.md"
    echo "# Other Cmd" > "$pack2_dir/commands/other-cmd.md"

    cd "$TEST_TMPDIR"
    run "$INSTALL_SCRIPT" link-commands specific-pack

    [ "$status" -eq 0 ]
    [ -L "$TEST_TMPDIR/.claude/commands/specific-cmd.md" ]
    [ ! -L "$TEST_TMPDIR/.claude/commands/other-cmd.md" ]
}

# =============================================================================
# Registry Meta Tests
# =============================================================================

@test "pack installation updates .constructs-meta.json" {
    skip_if_not_implemented

    # Create mock pack
    create_mock_pack "meta-test-pack"

    source "$INSTALL_SCRIPT"
    cd "$TEST_TMPDIR"

    # Initialize meta file
    init_registry_meta

    # Update meta as if pack was installed
    update_pack_meta "meta-test-pack" "$LOA_CONSTRUCTS_DIR/packs/meta-test-pack"

    # Check meta was updated
    local meta_path="$LOA_CONSTRUCTS_DIR/.constructs-meta.json"
    [ -f "$meta_path" ]

    # Check pack is in meta
    run jq -r '.installed_packs["meta-test-pack"].version' "$meta_path"
    [ "$output" == "1.0.0" ]
}

# =============================================================================
# Offline Mode Tests
# =============================================================================

@test "pack install fails in offline mode" {
    skip_if_not_implemented

    export LOA_OFFLINE=1
    export LOA_CONSTRUCTS_API_KEY="test-key"

    cd "$TEST_TMPDIR"
    run "$INSTALL_SCRIPT" pack some-pack

    [ "$status" -eq 2 ]  # NETWORK_ERROR
    [[ "$output" == *"offline"* ]]
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "handles pack without commands directory" {
    skip_if_not_implemented

    # Create pack without commands
    local pack_dir="$LOA_CONSTRUCTS_DIR/packs/no-commands-pack"
    mkdir -p "$pack_dir"
    echo '{"name": "no-commands-pack", "version": "1.0.0"}' > "$pack_dir/manifest.json"

    source "$INSTALL_SCRIPT"
    cd "$TEST_TMPDIR"

    # Should not error
    local linked
    linked=$(symlink_pack_commands "no-commands-pack")
    [ "$linked" -eq 0 ]
}

@test "handles pack without skills directory" {
    skip_if_not_implemented

    # Create pack without skills
    local pack_dir="$LOA_CONSTRUCTS_DIR/packs/no-skills-pack"
    mkdir -p "$pack_dir"
    echo '{"name": "no-skills-pack", "version": "1.0.0"}' > "$pack_dir/manifest.json"

    source "$INSTALL_SCRIPT"
    cd "$TEST_TMPDIR"

    # Should not error
    local linked
    linked=$(symlink_pack_skills "no-skills-pack")
    [ "$linked" -eq 0 ]
}
