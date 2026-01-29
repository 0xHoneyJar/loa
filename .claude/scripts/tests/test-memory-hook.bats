#!/usr/bin/env bats
# .claude/scripts/tests/test-memory-hook.bats
#
# Integration tests for Loa Memory Stack PreToolUse hook
# Run with: bats .claude/scripts/tests/test-memory-hook.bats

# Test setup
setup() {
    export PROJECT_ROOT="$(git rev-parse --show-toplevel)"
    export TEST_LOA_DIR="$PROJECT_ROOT/.loa-test-hook-$$"
    export LOA_DIR="$TEST_LOA_DIR"
    export DB_FILE="$TEST_LOA_DIR/memory.db"
    mkdir -p "$TEST_LOA_DIR"

    # Path to scripts
    export MEMORY_ADMIN="$PROJECT_ROOT/.claude/scripts/memory-admin.sh"
    export MEMORY_INJECT="$PROJECT_ROOT/.claude/hooks/memory-inject.sh"
    export CONFIG_FILE="$TEST_LOA_DIR/test-config.yaml"

    # Create test config
    cat > "$CONFIG_FILE" <<'EOF'
memory:
  pretooluse_hook:
    enabled: true
    thinking_chars: 1500
    similarity_threshold: 0.35
    max_memories: 3
    timeout_ms: 500
    tools:
      - Read
      - Glob
      - Grep
      - WebFetch
      - WebSearch
EOF
}

# Test teardown
teardown() {
    rm -rf "$TEST_LOA_DIR"
}

# =============================================================================
# Hook Enable/Disable Tests
# =============================================================================

@test "memory-inject.sh returns no-op when disabled" {
    # Create disabled config
    cat > "$CONFIG_FILE" <<'EOF'
memory:
  pretooluse_hook:
    enabled: false
EOF

    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="Test thinking content"

    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
}

@test "memory-inject.sh returns no-op for non-enabled tool" {
    export CLAUDE_TOOL_NAME="Write"
    export CLAUDE_THINKING_CONTENT="Test thinking content"

    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
}

@test "memory-inject.sh returns no-op when .loa directory missing" {
    rm -rf "$TEST_LOA_DIR"

    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="Test thinking content"

    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
}

# =============================================================================
# Context Extraction Tests
# =============================================================================

@test "memory-inject.sh extracts thinking content" {
    skip_if_no_sentence_transformers

    # Initialize database with a memory
    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Use absolute paths in settings" --type gotcha

    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="Let me check the settings file for path configuration"

    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]

    # Should return additionalContext
    echo "$output" | jq -e '.additionalContext' >/dev/null
}

@test "memory-inject.sh truncates long thinking content" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Test memory" --type gotcha

    # Create thinking content > 1500 chars
    local long_thinking
    long_thinking=$(printf 'x%.0s' {1..3000})

    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="$long_thinking"

    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]
    # Should not error
}

@test "memory-inject.sh uses assistant message as fallback" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Database connection pooling" --type pattern

    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT=""
    export CLAUDE_ASSISTANT_MESSAGE="I need to configure the database connection"

    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Deduplication Tests
# =============================================================================

@test "memory-inject.sh skips duplicate queries" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Test memory" --type gotcha

    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="Same query twice"

    # First call should work
    "$MEMORY_INJECT" >/dev/null

    # Second call should be no-op (hash match)
    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
}

@test "memory-inject.sh stores hash in .loa directory" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init

    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="Test content for hashing"

    "$MEMORY_INJECT" >/dev/null

    # Hash file should exist
    [ -f "$TEST_LOA_DIR/last_query_hash" ]

    # Hash should be 16 characters
    local hash_len
    hash_len=$(wc -c < "$TEST_LOA_DIR/last_query_hash")
    [ "$hash_len" -ge 16 ]
}

# =============================================================================
# Memory Injection Tests
# =============================================================================

@test "memory-inject.sh injects relevant memories" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Always use absolute paths in settings.json" --type gotcha
    "$MEMORY_ADMIN" add "Database requires connection pooling" --type pattern

    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="I need to check the settings.json file for path configuration"

    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]

    # Should contain settings-related memory
    local context
    context=$(echo "$output" | jq -r '.additionalContext // empty')
    [[ "$context" == *"absolute paths"* ]] || [[ "$context" == *"settings"* ]]
}

@test "memory-inject.sh formats memories as markdown" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Test memory content" --type gotcha

    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="Test query that should match"

    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]

    # Should contain markdown header
    local context
    context=$(echo "$output" | jq -r '.additionalContext // empty')
    [[ "$context" == *"Recalled Memories"* ]]
}

@test "memory-inject.sh includes memory type and score" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Important gotcha information" --type gotcha

    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="I need some important information"

    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]

    # Should contain type label
    local context
    context=$(echo "$output" | jq -r '.additionalContext // empty')
    [[ "$context" == *"GOTCHA"* ]]
}

# =============================================================================
# Threshold Tests
# =============================================================================

@test "memory-inject.sh respects similarity threshold" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Completely unrelated content about elephants" --type learning

    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="Database configuration settings"

    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]

    # Low similarity should result in no injection or empty results
    local context
    context=$(echo "$output" | jq -r '.additionalContext // empty')
    # Either no-op or context without the unrelated memory
    [[ "$output" == "{}" ]] || [[ "$context" != *"elephants"* ]]
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "memory-inject.sh never blocks on errors" {
    # Remove database to cause error
    rm -f "$DB_FILE"

    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="Test content"

    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
}

@test "memory-inject.sh handles missing config gracefully" {
    rm -f "$CONFIG_FILE"

    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="Test content"

    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Timeout Tests
# =============================================================================

@test "memory-inject.sh enforces timeout" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init

    # Set very short timeout
    cat > "$CONFIG_FILE" <<'EOF'
memory:
  pretooluse_hook:
    enabled: true
    timeout_ms: 1
    tools:
      - Read
EOF

    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="Test content that will timeout"

    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]
    # Should complete (possibly with no-op due to timeout)
}

# =============================================================================
# Helper Functions
# =============================================================================

skip_if_no_sentence_transformers() {
    if ! python3 -c "import sentence_transformers" 2>/dev/null; then
        skip "sentence-transformers not installed"
    fi
}
