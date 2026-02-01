#!/usr/bin/env bats
# .claude/scripts/tests/test-memory-stack.bats
#
# Unit tests for Loa Memory Stack core infrastructure
# Run with: bats .claude/scripts/tests/test-memory-stack.bats

# Test setup
setup() {
    export PROJECT_ROOT="$(git rev-parse --show-toplevel)"
    export TEST_LOA_DIR="$PROJECT_ROOT/.loa-test-$$"
    export LOA_DIR="$TEST_LOA_DIR"
    export DB_FILE="$TEST_LOA_DIR/memory.db"
    mkdir -p "$TEST_LOA_DIR"

    # Path to scripts
    export MEMORY_ADMIN="$PROJECT_ROOT/.claude/scripts/memory-admin.sh"
    export EMBED_PY="$PROJECT_ROOT/.claude/hooks/memory-utils/embed.py"
}

# Test teardown
teardown() {
    rm -rf "$TEST_LOA_DIR"
}

# =============================================================================
# Database Initialization Tests
# =============================================================================

@test "memory-admin.sh init creates database" {
    run "$MEMORY_ADMIN" init
    [ "$status" -eq 0 ]
    [ -f "$DB_FILE" ]
}

@test "memory-admin.sh init creates required tables" {
    "$MEMORY_ADMIN" init

    # Check memories table
    run sqlite3 "$DB_FILE" "SELECT name FROM sqlite_master WHERE type='table' AND name='memories';"
    [ "$status" -eq 0 ]
    [ "$output" = "memories" ]

    # Check memory_embeddings table
    run sqlite3 "$DB_FILE" "SELECT name FROM sqlite_master WHERE type='table' AND name='memory_embeddings';"
    [ "$status" -eq 0 ]
    [ "$output" = "memory_embeddings" ]

    # Check query_cache table
    run sqlite3 "$DB_FILE" "SELECT name FROM sqlite_master WHERE type='table' AND name='query_cache';"
    [ "$status" -eq 0 ]
    [ "$output" = "query_cache" ]
}

@test "memory-admin.sh init creates indexes" {
    "$MEMORY_ADMIN" init

    # Check indexes exist
    local index_count
    index_count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%';")
    [ "$index_count" -ge 3 ]
}

# =============================================================================
# Embedding Service Tests
# =============================================================================

@test "embed.py --check returns availability status" {
    skip_if_no_sentence_transformers

    run python3 "$EMBED_PY" --check
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.available' >/dev/null
}

@test "embed.py generates 384-dimension embeddings" {
    skip_if_no_sentence_transformers

    run bash -c 'echo "test text" | python3 "$EMBED_PY"'
    [ "$status" -eq 0 ]

    local dimension
    dimension=$(echo "$output" | jq '.dimension')
    [ "$dimension" -eq 384 ]
}

@test "embed.py includes content hash" {
    skip_if_no_sentence_transformers

    run bash -c 'echo "test text" | python3 "$EMBED_PY"'
    [ "$status" -eq 0 ]

    local hash
    hash=$(echo "$output" | jq -r '.content_hash')
    [ ${#hash} -eq 16 ]
}

@test "embed.py --similarity calculates cosine similarity" {
    skip_if_no_sentence_transformers

    run python3 "$EMBED_PY" --similarity "hello world" "hello there"
    [ "$status" -eq 0 ]

    local similarity
    similarity=$(echo "$output" | jq '.similarity')
    # Similar texts should have similarity > 0.5
    [ "$(echo "$similarity > 0.5" | bc -l)" -eq 1 ]
}

# =============================================================================
# Memory Add Tests
# =============================================================================

@test "memory-admin.sh add stores memory with type" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    run "$MEMORY_ADMIN" add "Test memory content" --type gotcha
    [ "$status" -eq 0 ]

    # Verify memory exists
    local count
    count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM memories WHERE memory_type='gotcha';")
    [ "$count" -eq 1 ]
}

@test "memory-admin.sh add stores embedding" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Test memory content" --type learning

    # Verify embedding exists
    local count
    count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM memory_embeddings;")
    [ "$count" -eq 1 ]
}

@test "memory-admin.sh add requires type" {
    "$MEMORY_ADMIN" init
    run "$MEMORY_ADMIN" add "Test memory content"
    [ "$status" -ne 0 ]
}

@test "memory-admin.sh add validates type" {
    "$MEMORY_ADMIN" init
    run "$MEMORY_ADMIN" add "Test" --type invalid
    [ "$status" -ne 0 ]
}

@test "memory-admin.sh add truncates long content" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init

    # Create content > 2000 chars
    local long_content
    long_content=$(printf 'x%.0s' {1..3000})

    run "$MEMORY_ADMIN" add "$long_content" --type learning
    [ "$status" -eq 0 ]

    # Verify truncation
    local length
    length=$(sqlite3 "$DB_FILE" "SELECT length(content) FROM memories LIMIT 1;")
    [ "$length" -le 2000 ]
}

# =============================================================================
# Memory List Tests
# =============================================================================

@test "memory-admin.sh list returns JSON" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Test memory" --type gotcha

    run "$MEMORY_ADMIN" list
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.' >/dev/null
}

@test "memory-admin.sh list filters by type" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Gotcha memory" --type gotcha
    "$MEMORY_ADMIN" add "Pattern memory" --type pattern

    run "$MEMORY_ADMIN" list --type gotcha
    [ "$status" -eq 0 ]

    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -eq 1 ]
}

@test "memory-admin.sh list respects limit" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    for i in {1..5}; do
        "$MEMORY_ADMIN" add "Memory $i" --type learning
    done

    run "$MEMORY_ADMIN" list --limit 3
    [ "$status" -eq 0 ]

    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -eq 3 ]
}

# =============================================================================
# Memory Search Tests
# =============================================================================

@test "memory-admin.sh search returns similar memories" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Use absolute paths in settings.json" --type gotcha
    "$MEMORY_ADMIN" add "Database connection pooling" --type pattern

    run "$MEMORY_ADMIN" search "settings path"
    [ "$status" -eq 0 ]

    # First result should be about settings
    local first_content
    first_content=$(echo "$output" | jq -r '.[0].content // empty')
    [[ "$first_content" == *"settings"* ]]
}

@test "memory-admin.sh search respects threshold" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Unrelated content about cats" --type learning

    # High threshold should return empty for unrelated query
    run "$MEMORY_ADMIN" search "database configuration" --threshold 0.9
    [ "$status" -eq 0 ]

    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -eq 0 ]
}

@test "memory-admin.sh search updates match count" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Test memory for counting" --type gotcha

    # Search twice
    "$MEMORY_ADMIN" search "test counting" >/dev/null
    "$MEMORY_ADMIN" search "test counting" >/dev/null

    local match_count
    match_count=$(sqlite3 "$DB_FILE" "SELECT match_count FROM memories LIMIT 1;")
    [ "$match_count" -ge 1 ]
}

# =============================================================================
# Memory Delete Tests
# =============================================================================

@test "memory-admin.sh delete removes memory" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "To be deleted" --type gotcha

    local id
    id=$(sqlite3 "$DB_FILE" "SELECT id FROM memories LIMIT 1;")

    run "$MEMORY_ADMIN" delete "$id"
    [ "$status" -eq 0 ]

    local count
    count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM memories;")
    [ "$count" -eq 0 ]
}

@test "memory-admin.sh delete cascades to embeddings" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "To be deleted" --type gotcha

    local id
    id=$(sqlite3 "$DB_FILE" "SELECT id FROM memories LIMIT 1;")

    "$MEMORY_ADMIN" delete "$id"

    local emb_count
    emb_count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM memory_embeddings;")
    [ "$emb_count" -eq 0 ]
}

# =============================================================================
# Memory Stats Tests
# =============================================================================

@test "memory-admin.sh stats returns counts" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Gotcha 1" --type gotcha
    "$MEMORY_ADMIN" add "Pattern 1" --type pattern

    run "$MEMORY_ADMIN" stats
    [ "$status" -eq 0 ]

    local total
    total=$(echo "$output" | jq '.[0].total_memories')
    [ "$total" -eq 2 ]
}

# =============================================================================
# Memory Export/Import Tests
# =============================================================================

@test "memory-admin.sh export produces valid JSON" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Export test" --type learning

    run "$MEMORY_ADMIN" export --format json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.' >/dev/null
}

@test "memory-admin.sh import restores memories" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init

    # Create import file
    echo '[{"content": "Imported memory", "memory_type": "gotcha"}]' > "$TEST_LOA_DIR/import.json"

    run "$MEMORY_ADMIN" import "$TEST_LOA_DIR/import.json"
    [ "$status" -eq 0 ]

    local count
    count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM memories;")
    [ "$count" -eq 1 ]
}

# =============================================================================
# Memory Prune Tests
# =============================================================================

@test "memory-admin.sh prune --dry-run shows candidates" {
    skip_if_no_sentence_transformers

    "$MEMORY_ADMIN" init
    "$MEMORY_ADMIN" add "Old memory" --type learning

    # Update created_at to be old
    sqlite3 "$DB_FILE" "UPDATE memories SET created_at = datetime('now', '-100 days');"

    run "$MEMORY_ADMIN" prune --older-than 90 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Would prune"* ]] || [[ "$output" == *"preview"* ]]
}

# =============================================================================
# Helper Functions
# =============================================================================

skip_if_no_sentence_transformers() {
    if ! python3 -c "import sentence_transformers" 2>/dev/null; then
        skip "sentence-transformers not installed"
    fi
}
