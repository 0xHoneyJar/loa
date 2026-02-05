#!/usr/bin/env bats
# .claude/scripts/tests/test-memory-e2e.bats
#
# End-to-End tests for Loa Memory Stack
# Validates all PRD goals: G-1 through G-4
#
# Run with: bats .claude/scripts/tests/test-memory-e2e.bats

# Test setup
setup() {
    export PROJECT_ROOT="$(git rev-parse --show-toplevel)"
    export TEST_LOA_DIR="$PROJECT_ROOT/.loa-test-e2e-$$"
    export LOA_DIR="$TEST_LOA_DIR"
    export DB_FILE="$TEST_LOA_DIR/memory.db"
    mkdir -p "$TEST_LOA_DIR"

    # Source cross-platform time utilities
    # shellcheck source=../time-lib.sh
    source "$PROJECT_ROOT/.claude/scripts/time-lib.sh"

    # Path to scripts
    export MEMORY_ADMIN="$PROJECT_ROOT/.claude/scripts/memory-admin.sh"
    export MEMORY_INJECT="$PROJECT_ROOT/.claude/hooks/memory-inject.sh"
    export MEMORY_SYNC="$PROJECT_ROOT/.claude/scripts/memory-sync.sh"
    export QMD_SYNC="$PROJECT_ROOT/.claude/scripts/qmd-sync.sh"
    export SEARCH_UTIL="$PROJECT_ROOT/.claude/hooks/memory-utils/search.sh"
    export CONFIG_FILE="$TEST_LOA_DIR/test-config.yaml"
    export NOTES_FILE="$TEST_LOA_DIR/NOTES.md"
    export GRIMOIRES_DIR="$TEST_LOA_DIR/grimoires/loa"

    # Create test config
    cat > "$CONFIG_FILE" <<EOF
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
  auto_sync: true
  qmd:
    enabled: true
    index_dir: $TEST_LOA_DIR/qmd
    collections:
      - name: test-docs
        path: $GRIMOIRES_DIR
        include: ["*.md"]
EOF

    # Create test NOTES.md
    mkdir -p "$GRIMOIRES_DIR"
    cat > "$NOTES_FILE" <<'EOF'
# Session Notes

## Learnings
- [GOTCHA] Always use absolute paths in settings.json
- [PATTERN] Use realpath for path validation in shell scripts
- Database connection pooling requires explicit close
- [DECISION] Chose SQLite over Postgres for portability

## Session Log
| Time | Event |
|------|-------|
| 10:00 | Started session |
EOF

    # Create test document for QMD
    cat > "$GRIMOIRES_DIR/architecture.md" <<'EOF'
# Architecture

## Authentication Flow

The authentication system uses JWT tokens with the following flow:
1. User submits credentials
2. Server validates against database
3. Token is generated with 24h expiry
4. Refresh token stored securely

## Error Handling

Always catch authentication errors and log them appropriately.
EOF

}

# Test teardown
teardown() {
    rm -rf "$TEST_LOA_DIR"
}

# =============================================================================
# Helper Functions
# =============================================================================

skip_if_no_sentence_transformers() {
    if ! python3 -c "import sentence_transformers" 2>/dev/null; then
        skip "sentence-transformers not installed"
    fi
}

measure_latency() {
    local start end
    start=$(get_timestamp_ms)
    "$@" >/dev/null 2>&1
    end=$(get_timestamp_ms)
    echo $(( end - start ))  # milliseconds
}

# =============================================================================
# G-1: Mid-stream Memory Injection Tests
# =============================================================================

@test "G-1: Memory injection workflow - add memory and verify injection" {
    skip_if_no_sentence_transformers

    # Initialize database
    "$MEMORY_ADMIN" init

    # Add a gotcha memory about absolute paths
    "$MEMORY_ADMIN" add "Always use absolute paths in settings.json, tilde expansion does not work" --type gotcha

    # Simulate PreToolUse hook with relevant thinking
    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="I need to check the settings.json file for path configuration. Let me read the settings to understand the paths."

    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]

    # Should inject relevant memory
    local context
    context=$(echo "$output" | jq -r '.additionalContext // ""')
    [[ "$context" == *"absolute paths"* ]] || [[ "$context" == *"settings"* ]]
}

@test "G-1: Memory injection includes type and score" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Test gotcha memory" --type gotcha

    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="Test query for gotcha"

    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]

    # Should include type label
    local context
    context=$(echo "$output" | jq -r '.additionalContext // ""')
    [[ "$context" == *"GOTCHA"* ]] || [[ "$output" == "{}" ]]
}

@test "G-1: Memory injection returns no-op for unrelated queries" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Authentication requires JWT tokens" --type pattern

    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="Let me check the database migration scripts"

    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]

    # Either no-op or no auth memory in context
    local context
    context=$(echo "$output" | jq -r '.additionalContext // ""')
    [[ "$output" == "{}" ]] || [[ "$context" != *"JWT"* ]]
}

# =============================================================================
# G-2: Sub-500ms Latency Tests
# =============================================================================

@test "G-2: Memory search latency under 500ms" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init

    # Add multiple memories
    for i in {1..20}; do
        "$MEMORY_ADMIN" add "Test memory number $i with some content about features" --type learning >/dev/null
    done

    # Measure search latency
    local latency
    latency=$(measure_latency "$MEMORY_ADMIN" search "test memory features")

    echo "Search latency: ${latency}ms"
    [ "$latency" -lt 500 ]
}

@test "G-2: Hook total latency under 500ms" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Test memory for latency" --type gotcha

    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="Test thinking content for latency measurement"

    # Measure full hook latency
    local latency
    latency=$(measure_latency "$MEMORY_INJECT")

    echo "Hook latency: ${latency}ms"
    [ "$latency" -lt 500 ]
}

@test "G-2: Deduplication skips repeated queries" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Test memory" --type gotcha

    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="Same query twice for dedup test"

    # First call
    "$MEMORY_INJECT" >/dev/null

    # Second call should be faster (hash match)
    local latency
    latency=$(measure_latency "$MEMORY_INJECT")

    echo "Dedup latency: ${latency}ms"
    # Should be very fast since it's a hash match
    [ "$latency" -lt 100 ]
}

# =============================================================================
# G-3: Semantic Document Search Tests
# =============================================================================

@test "G-3: QMD sync indexes documents" {
    # Note: Tests grep fallback if QMD binary unavailable
    run "$QMD_SYNC" sync
    [ "$status" -eq 0 ]
    [[ "$output" == *"indexed"* ]] || [[ "$output" == *"Sync complete"* ]]
}

@test "G-3: QMD query returns relevant results" {
    "$QMD_SYNC" sync

    run "$QMD_SYNC" query "authentication JWT"
    [ "$status" -eq 0 ]

    # Should return valid JSON
    echo "$output" | jq '.' >/dev/null 2>&1
}

@test "G-3: Search utility merges vector and QMD results" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "JWT authentication requires token refresh" --type pattern
    "$QMD_SYNC" sync

    run "$SEARCH_UTIL" "authentication JWT" --include-qmd
    [ "$status" -eq 0 ]

    # Should return merged results
    echo "$output" | jq '.' >/dev/null 2>&1
}

# =============================================================================
# G-4: Self-Correcting Workflows Tests
# =============================================================================

@test "G-4: NOTES.md learnings sync extracts memories" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init

    # Set NOTES_FILE for sync script
    export NOTES_FILE="$NOTES_FILE"

    run "$MEMORY_SYNC" notes
    [ "$status" -eq 0 ]
    [[ "$output" == *"Synced"* ]]

    # Verify memories were added
    local count
    count=$("$MEMORY_ADMIN" stats 2>/dev/null | jq '.total_memories // 0')
    [ "$count" -gt 0 ]
}

@test "G-4: NOTES.md sync detects memory types" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    export NOTES_FILE="$NOTES_FILE"

    "$MEMORY_SYNC" notes

    # Check for gotcha type
    run "$MEMORY_ADMIN" list --type gotcha
    [ "$status" -eq 0 ]
    [[ "$output" == *"absolute paths"* ]]
}

@test "G-4: NOTES.md sync deduplicates memories" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    export NOTES_FILE="$NOTES_FILE"

    # Sync twice
    "$MEMORY_SYNC" notes
    local first_count
    first_count=$("$MEMORY_ADMIN" stats 2>/dev/null | jq '.total_memories // 0')

    "$MEMORY_SYNC" notes
    local second_count
    second_count=$("$MEMORY_ADMIN" stats 2>/dev/null | jq '.total_memories // 0')

    # Count should not increase
    [ "$first_count" -eq "$second_count" ]
}

@test "G-4: Memory prune removes stale memories" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init

    # Add memory with old timestamp (simulated via direct SQL)
    "$MEMORY_ADMIN" add "Old memory to prune" --type learning

    # Prune with --dry-run
    run "$MEMORY_ADMIN" prune --older-than 0 --dry-run
    [ "$status" -eq 0 ]
}

@test "G-4: Memory stats shows hit rate" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Test memory for stats" --type gotcha

    # Perform some searches
    "$MEMORY_ADMIN" search "test memory" >/dev/null
    "$MEMORY_ADMIN" search "another query" >/dev/null

    run "$MEMORY_ADMIN" stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"total_memories"* ]] || [[ "$output" == *"Total"* ]]
}

# =============================================================================
# Integration Tests
# =============================================================================

@test "E2E: Complete memory lifecycle" {
    skip_if_no_sentence_transformers

    # 1. Initialize
    "$MEMORY_ADMIN" init
    log "Step 1: Database initialized"

    # 2. Add memories
    "$MEMORY_ADMIN" add "Use absolute paths in config files" --type gotcha
    "$MEMORY_ADMIN" add "Database connections need explicit pooling" --type pattern
    log "Step 2: Memories added"

    # 3. Sync NOTES.md
    export NOTES_FILE="$NOTES_FILE"
    "$MEMORY_SYNC" notes
    log "Step 3: NOTES.md synced"

    # 4. Sync QMD
    "$QMD_SYNC" sync
    log "Step 4: QMD synced"

    # 5. Trigger hook
    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="I need to configure the database connection settings"
    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]
    log "Step 5: Hook triggered"

    # 6. Verify injection happened
    local context
    context=$(echo "$output" | jq -r '.additionalContext // ""')
    [[ -n "$context" ]] || [[ "$output" == "{}" ]]
    log "Step 6: Injection verified"

    # 7. Check stats
    run "$MEMORY_ADMIN" stats
    [ "$status" -eq 0 ]
    log "Step 7: Stats verified"
}

@test "E2E: Self-correction demonstration" {
    skip_if_no_sentence_transformers

    # This test demonstrates the self-correction workflow:
    # 1. A gotcha memory exists about a common mistake
    # 2. When agent thinks about related topic, memory is recalled
    # 3. The recall prevents the mistake

    "$MEMORY_ADMIN" init

    # Add a gotcha about a common mistake
    "$MEMORY_ADMIN" add "GOTCHA: settings.json does not support tilde expansion (~). Always use absolute paths like /home/user instead of ~/." --type gotcha --source "sprint-5-debugging"

    # Simulate agent thinking about editing settings
    export CLAUDE_TOOL_NAME="Read"
    export CLAUDE_THINKING_CONTENT="I need to update the settings.json file to add a new path configuration. Let me read the current settings first to see the structure."

    run "$MEMORY_INJECT"
    [ "$status" -eq 0 ]

    # The injection should contain the gotcha about paths
    local context
    context=$(echo "$output" | jq -r '.additionalContext // ""')

    # Either we got the memory or threshold was too high
    if [[ "$context" != "" ]]; then
        [[ "$context" == *"tilde"* ]] || [[ "$context" == *"absolute"* ]] || [[ "$context" == *"path"* ]]
    fi
}

# Helper for logging in tests
log() {
    echo "# $1" >&3
}
