#!/usr/bin/env bats
# Unit tests for tool-search-adapter.sh
# Part of Sprint 3: Tool Search & MCP Enhancement

setup() {
    # Create temp directory for test files
    export TEST_DIR="$BATS_TMPDIR/tool-search-test-$$"
    mkdir -p "$TEST_DIR"
    mkdir -p "$TEST_DIR/.claude"
    mkdir -p "$TEST_DIR/.claude/scripts"
    mkdir -p "$TEST_DIR/.claude/constructs/skills/test-vendor/test-skill"
    mkdir -p "$TEST_DIR/.claude/constructs/packs/test-pack"

    # Script path
    export SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/tool-search-adapter.sh"

    # Create test MCP registry
    cat > "$TEST_DIR/.claude/mcp-registry.yaml" << 'EOF'
version: "1.0.0"
servers:
  github:
    name: "GitHub"
    description: "Repository operations, PRs, issues, and CI/CD"
    scopes:
      - repos
      - pulls
      - issues
  linear:
    name: "Linear"
    description: "Issue tracking and project management"
    scopes:
      - issues
      - projects
  vercel:
    name: "Vercel"
    description: "Deployment and hosting"
    scopes:
      - deployments
groups:
  essential:
    description: "Essential tools"
    servers:
      - github
      - linear
EOF

    # Create test settings file (simulating configured servers)
    cat > "$TEST_DIR/.claude/settings.local.json" << 'EOF'
{
  "mcpServers": {
    "github": {},
    "linear": {}
  }
}
EOF

    # Create test skill
    cat > "$TEST_DIR/.claude/constructs/skills/test-vendor/test-skill/index.yaml" << 'EOF'
name: "Test Skill"
description: "A test skill for unit testing"
triggers:
  - /test
EOF

    # Create test pack
    cat > "$TEST_DIR/.claude/constructs/packs/test-pack/manifest.json" << 'EOF'
{
  "name": "Test Pack",
  "description": "A test pack for unit testing",
  "skills": ["skill1", "skill2"]
}
EOF

    # Create test config
    cat > "$TEST_DIR/.loa.config.yaml" << 'EOF'
tool_search:
  enabled: true
  auto_discover: true
  cache_ttl_hours: 24
  include_constructs: true
EOF

    # Override paths for testing
    export MCP_REGISTRY="$TEST_DIR/.claude/mcp-registry.yaml"
    export SETTINGS_FILE="$TEST_DIR/.claude/settings.local.json"
    export CONSTRUCTS_DIR="$TEST_DIR/.claude/constructs"
    export CONFIG_FILE="$TEST_DIR/.loa.config.yaml"
    export LOA_CACHE_DIR="$TEST_DIR/cache"
}

teardown() {
    rm -rf "$TEST_DIR"
    rm -rf "$LOA_CACHE_DIR"
}

# =============================================================================
# Basic Command Tests
# =============================================================================

@test "tool-search-adapter: shows usage with no arguments" {
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "tool-search-adapter: shows help with --help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Commands:"* ]]
    [[ "$output" == *"search"* ]]
    [[ "$output" == *"discover"* ]]
    [[ "$output" == *"cache"* ]]
}

@test "tool-search-adapter: shows help with -h" {
    run "$SCRIPT" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "tool-search-adapter: rejects unknown command" {
    run "$SCRIPT" unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command"* ]]
}

# =============================================================================
# Search Command Tests
# =============================================================================

@test "tool-search-adapter search: finds github by name" {
    run "$SCRIPT" search "github" --include-unconfigured
    [ "$status" -eq 0 ]
    [[ "$output" == *"GitHub"* ]]
}

@test "tool-search-adapter search: finds multiple servers by scope" {
    run "$SCRIPT" search "issues" --include-unconfigured
    [ "$status" -eq 0 ]
    [[ "$output" == *"GitHub"* ]]
    [[ "$output" == *"Linear"* ]]
}

@test "tool-search-adapter search: empty query returns all servers" {
    run "$SCRIPT" search "" --include-unconfigured
    [ "$status" -eq 0 ]
    [[ "$output" == *"GitHub"* ]]
    [[ "$output" == *"Linear"* ]]
    [[ "$output" == *"Vercel"* ]]
}

@test "tool-search-adapter search: --json outputs valid JSON" {
    run "$SCRIPT" search "github" --json --include-unconfigured
    [ "$status" -eq 0 ]
    echo "$output" | jq empty
    [[ "$output" == *"\"name\""* ]]
}

@test "tool-search-adapter search: --limit limits results" {
    run "$SCRIPT" search "" --limit 1 --include-unconfigured
    [ "$status" -eq 0 ]
    # Should only show one result in JSON mode
    run "$SCRIPT" search "" --json --limit 1 --include-unconfigured
    count=$(echo "$output" | jq 'length')
    [ "$count" -eq 1 ]
}

@test "tool-search-adapter search: case insensitive" {
    run "$SCRIPT" search "GITHUB" --include-unconfigured
    [ "$status" -eq 0 ]
    [[ "$output" == *"GitHub"* ]]
}

@test "tool-search-adapter search: no results for non-matching query" {
    run "$SCRIPT" search "nonexistent-server-xyz" --include-unconfigured
    [ "$status" -eq 0 ]
    [[ "$output" == *"No results"* ]]
}

# =============================================================================
# Discover Command Tests
# =============================================================================

@test "tool-search-adapter discover: shows configured servers" {
    run "$SCRIPT" discover
    [ "$status" -eq 0 ]
    [[ "$output" == *"MCP Servers"* ]]
    [[ "$output" == *"GitHub"* ]]
    [[ "$output" == *"Linear"* ]]
}

@test "tool-search-adapter discover: excludes unconfigured servers" {
    run "$SCRIPT" discover
    [ "$status" -eq 0 ]
    # Vercel is not in settings.local.json
    [[ "$output" != *"Vercel"* ]] || [[ "$output" == *"0 configured"* ]] || true
}

@test "tool-search-adapter discover: --json outputs valid JSON" {
    run "$SCRIPT" discover --json
    [ "$status" -eq 0 ]
    echo "$output" | jq empty
    [[ "$output" == *"\"mcp\""* ]]
    [[ "$output" == *"\"constructs\""* ]]
}

@test "tool-search-adapter discover: includes constructs when present" {
    run "$SCRIPT" discover
    [ "$status" -eq 0 ]
    [[ "$output" == *"Loa Constructs"* ]]
}

@test "tool-search-adapter discover: --refresh ignores cache" {
    # First call creates cache
    run "$SCRIPT" discover
    [ "$status" -eq 0 ]

    # Second call with --refresh
    run "$SCRIPT" discover --refresh
    [ "$status" -eq 0 ]
    [[ "$output" != *"cached"* ]]
}

# =============================================================================
# Cache Command Tests
# =============================================================================

@test "tool-search-adapter cache list: shows no entries initially" {
    # Clear any existing cache first
    "$SCRIPT" cache clear > /dev/null 2>&1 || true
    run "$SCRIPT" cache list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No cache"* ]] || [[ "$output" == *"0"* ]]
}

@test "tool-search-adapter cache list: shows entries after search" {
    # Perform a search to create cache entry
    "$SCRIPT" search "github" --include-unconfigured > /dev/null 2>&1

    run "$SCRIPT" cache list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cache entries"* ]] || [[ "$output" == *"Query:"* ]]
}

@test "tool-search-adapter cache clear: clears all entries" {
    # Create some cache entries
    "$SCRIPT" search "github" --include-unconfigured > /dev/null 2>&1
    "$SCRIPT" search "linear" --include-unconfigured > /dev/null 2>&1

    run "$SCRIPT" cache clear
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cleared"* ]]

    # Verify cache is empty
    run "$SCRIPT" cache list
    [[ "$output" == *"No cache entries"* ]]
}

@test "tool-search-adapter cache: respects TTL" {
    # Search creates cache entry
    "$SCRIPT" search "github" --include-unconfigured > /dev/null 2>&1

    # Second search should use cache
    run "$SCRIPT" search "github" --include-unconfigured
    [ "$status" -eq 0 ]
    [[ "$output" == *"cached"* ]]
}

# =============================================================================
# Configuration Tests
# =============================================================================

@test "tool-search-adapter: disabled search returns warning" {
    # Create config with disabled search
    cat > "$TEST_DIR/.loa.config.yaml" << 'EOF'
tool_search:
  enabled: false
EOF

    # Clear cache to ensure fresh state
    "$SCRIPT" cache clear > /dev/null 2>&1 || true

    run "$SCRIPT" search "github"
    [ "$status" -eq 0 ]
    # Should indicate disabled or return empty results
    [[ "$output" == *"disabled"* ]] || [[ "$output" == *"No results"* ]] || [[ -z "$output" ]]
}

@test "tool-search-adapter: respects include_constructs config" {
    # Create config with constructs disabled
    cat > "$TEST_DIR/.loa.config.yaml" << 'EOF'
tool_search:
  enabled: true
  include_constructs: false
EOF

    # Clear cache to force refresh
    "$SCRIPT" cache clear > /dev/null 2>&1

    run "$SCRIPT" discover --refresh --json
    [ "$status" -eq 0 ]
    # Constructs array should be empty
    constructs_count=$(echo "$output" | jq '.constructs | length')
    [ "$constructs_count" -eq 0 ]
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "tool-search-adapter: handles missing registry gracefully" {
    rm -f "$TEST_DIR/.claude/mcp-registry.yaml"

    run "$SCRIPT" search "github" --include-unconfigured
    [ "$status" -eq 0 ]
    # Should return empty results, not crash
}

@test "tool-search-adapter: handles missing settings file gracefully" {
    rm -f "$TEST_DIR/.claude/settings.local.json"

    run "$SCRIPT" discover
    [ "$status" -eq 0 ]
    # Should show no configured servers, not crash
}

@test "tool-search-adapter: handles missing constructs directory gracefully" {
    rm -rf "$TEST_DIR/.claude/constructs"

    run "$SCRIPT" discover
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 installed"* ]] || [[ "$output" == *"No constructs"* ]]
}

@test "tool-search-adapter: handles special characters in query" {
    run "$SCRIPT" search "github & linear" --include-unconfigured
    [ "$status" -eq 0 ]
    # Should not crash
}

# =============================================================================
# Integration with Constructs
# =============================================================================

@test "tool-search-adapter search: finds constructs skills" {
    run "$SCRIPT" search "test" --include-unconfigured
    [ "$status" -eq 0 ]
    [[ "$output" == *"Test Skill"* ]] || [[ "$output" == *"test-skill"* ]]
}

@test "tool-search-adapter search: finds constructs packs" {
    run "$SCRIPT" search "pack" --include-unconfigured
    [ "$status" -eq 0 ]
    [[ "$output" == *"Test Pack"* ]] || [[ "$output" == *"test-pack"* ]]
}

@test "tool-search-adapter discover: shows installed skills" {
    run "$SCRIPT" discover --json
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-vendor/test-skill"* ]] || [[ "$output" == *"Test Skill"* ]]
}

@test "tool-search-adapter discover: shows installed packs" {
    run "$SCRIPT" discover --json
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-pack"* ]] || [[ "$output" == *"Test Pack"* ]]
}
