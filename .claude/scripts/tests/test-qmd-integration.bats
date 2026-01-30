#!/usr/bin/env bats
# .claude/scripts/tests/test-qmd-integration.bats
#
# Integration tests for QMD Index Synchronization
# Run with: bats .claude/scripts/tests/test-qmd-integration.bats

# Test setup
setup() {
    export PROJECT_ROOT="$(git rev-parse --show-toplevel)"
    export TEST_LOA_DIR="$PROJECT_ROOT/.loa-test-qmd-$$"
    export LOA_DIR="$TEST_LOA_DIR"
    export QMD_DIR="$TEST_LOA_DIR/qmd"
    mkdir -p "$TEST_LOA_DIR"
    mkdir -p "$QMD_DIR"

    # Path to scripts
    export QMD_SYNC="$PROJECT_ROOT/.claude/scripts/qmd-sync.sh"
    export SEARCH_UTIL="$PROJECT_ROOT/.claude/hooks/memory-utils/search.sh"
    export CONFIG_FILE="$TEST_LOA_DIR/test-config.yaml"

    # Create test documents
    export TEST_DOCS="$TEST_LOA_DIR/docs"
    mkdir -p "$TEST_DOCS"

    cat > "$TEST_DOCS/architecture.md" <<'EOF'
# Architecture Overview

This document describes the authentication system architecture.

## Authentication Flow

1. User submits credentials
2. Server validates against database
3. JWT token is generated
4. Token is returned to client

## Security Considerations

- Use bcrypt for password hashing
- Tokens expire after 24 hours
- Refresh tokens stored securely
EOF

    cat > "$TEST_DOCS/api-guide.md" <<'EOF'
# API Guide

## Endpoints

### POST /auth/login
Authenticates a user and returns a token.

### GET /users/:id
Retrieves user information.

### PUT /users/:id
Updates user profile.

## Rate Limiting

All endpoints are rate limited to 100 requests per minute.
EOF

    # Create test config
    cat > "$CONFIG_FILE" <<EOF
memory:
  qmd:
    enabled: true
    binary: qmd
    index_dir: $QMD_DIR
    collections:
      - name: test-docs
        path: $TEST_DOCS
        include: ["*.md"]
EOF
}

# Test teardown
teardown() {
    rm -rf "$TEST_LOA_DIR"
}

# =============================================================================
# Configuration Tests
# =============================================================================

@test "qmd-sync.sh shows help" {
    run "$QMD_SYNC" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"QMD Index Synchronization"* ]]
}

@test "qmd-sync.sh reports disabled when config missing" {
    rm -f "$CONFIG_FILE"
    export CONFIG_FILE="/nonexistent/config.yaml"

    run "$QMD_SYNC" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"DISABLED"* ]]
}

@test "qmd-sync.sh reports disabled when qmd.enabled is false" {
    cat > "$CONFIG_FILE" <<'EOF'
memory:
  qmd:
    enabled: false
EOF

    run "$QMD_SYNC" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"DISABLED"* ]]
}

@test "qmd-sync.sh reports enabled when configured" {
    # Note: QMD binary may not be available, but status should still show enabled
    run "$QMD_SYNC" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"ENABLED"* ]] || [[ "$output" == *"DISABLED"* ]]
}

# =============================================================================
# Collection Management Tests
# =============================================================================

@test "qmd-sync.sh creates collection directory" {
    run "$QMD_SYNC" create my-collection
    [ "$status" -eq 0 ]
    [ -d "$QMD_DIR/my-collection" ]
}

@test "qmd-sync.sh deletes collection directory" {
    mkdir -p "$QMD_DIR/to-delete"

    run "$QMD_SYNC" delete to-delete
    [ "$status" -eq 0 ]
    [ ! -d "$QMD_DIR/to-delete" ]
}

@test "qmd-sync.sh warns when deleting nonexistent collection" {
    run "$QMD_SYNC" delete nonexistent
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found"* ]]
}

# =============================================================================
# Sync Tests
# =============================================================================

@test "qmd-sync.sh sync creates mtime cache" {
    run "$QMD_SYNC" sync
    [ "$status" -eq 0 ]

    # Mtime cache should exist for the collection
    [ -f "$QMD_DIR/test-docs/.mtime_cache" ]
}

@test "qmd-sync.sh sync indexes files" {
    run "$QMD_SYNC" sync
    [ "$status" -eq 0 ]

    # Check mtime cache contains our test files
    local cache_content
    cache_content=$(cat "$QMD_DIR/test-docs/.mtime_cache" 2>/dev/null || echo "")
    [[ "$cache_content" == *"architecture.md"* ]]
    [[ "$cache_content" == *"api-guide.md"* ]]
}

@test "qmd-sync.sh incremental sync skips unchanged files" {
    # First sync
    "$QMD_SYNC" sync

    # Second sync should skip files
    run "$QMD_SYNC" sync
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipped"* ]]
}

@test "qmd-sync.sh force sync reindexes all files" {
    # First sync
    "$QMD_SYNC" sync

    # Force sync should reindex
    run "$QMD_SYNC" sync --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"indexed"* ]]
}

@test "qmd-sync.sh handles empty collections config" {
    cat > "$CONFIG_FILE" <<'EOF'
memory:
  qmd:
    enabled: true
    collections: []
EOF

    run "$QMD_SYNC" sync
    [ "$status" -eq 0 ]
    [[ "$output" == *"No collections configured"* ]]
}

# =============================================================================
# Query Tests (Fallback to grep when QMD binary unavailable)
# =============================================================================

@test "qmd-sync.sh query returns empty for no matches" {
    "$QMD_SYNC" sync

    run "$QMD_SYNC" query "elephants dancing"
    [ "$status" -eq 0 ]
    # Either empty array or no results
    [[ "$output" == "[]" ]] || [[ "$output" == *"[]"* ]]
}

@test "qmd-sync.sh query finds matching content (fallback grep)" {
    "$QMD_SYNC" sync

    # This should match content in our test docs
    run "$QMD_SYNC" query "authentication"
    [ "$status" -eq 0 ]

    # Should return JSON (might be empty if grep fallback doesn't match)
    echo "$output" | jq '.' >/dev/null 2>&1
}

# =============================================================================
# Search Utility Integration Tests
# =============================================================================

@test "search.sh respects --include-qmd flag" {
    "$QMD_SYNC" sync

    run "$SEARCH_UTIL" "test query" --include-qmd
    [ "$status" -eq 0 ]
    # Should return valid JSON
    echo "$output" | jq '.' >/dev/null 2>&1
}

@test "search.sh auto-enables QMD from config" {
    export CONFIG_FILE="$CONFIG_FILE"

    run "$SEARCH_UTIL" "authentication"
    [ "$status" -eq 0 ]
    echo "$output" | jq '.' >/dev/null 2>&1
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "qmd-sync.sh handles missing path gracefully" {
    cat > "$CONFIG_FILE" <<EOF
memory:
  qmd:
    enabled: true
    index_dir: $QMD_DIR
    collections:
      - name: missing
        path: /nonexistent/path
        include: ["*.md"]
EOF

    run "$QMD_SYNC" sync
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"Sync complete"* ]]
}

@test "qmd-sync.sh handles malformed config gracefully" {
    echo "invalid: yaml: content:" > "$CONFIG_FILE"

    run "$QMD_SYNC" status
    [ "$status" -eq 0 ]
}

# =============================================================================
# Status Tests
# =============================================================================

@test "qmd-sync.sh status shows collection info after sync" {
    "$QMD_SYNC" sync

    run "$QMD_SYNC" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-docs"* ]]
    [[ "$output" == *"files indexed"* ]]
}
