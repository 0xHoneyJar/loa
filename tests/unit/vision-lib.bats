#!/usr/bin/env bats
# Unit tests for vision-lib.sh
# Sprint 1 (cycle-041): Shared vision library — load, match, sanitize, validate

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT_DIR="$PROJECT_ROOT/.claude/scripts"
    FIXTURES="$PROJECT_ROOT/tests/fixtures/vision-registry"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/vision-lib-test-$$"
    mkdir -p "$TEST_TMPDIR"
    mkdir -p "$TEST_TMPDIR/entries"

    export PROJECT_ROOT
}

teardown() {
    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

skip_if_deps_missing() {
    if ! command -v jq &>/dev/null; then
        skip "jq not installed"
    fi
}

# Source the library for function testing
load_vision_lib() {
    skip_if_deps_missing
    # Source in subshell-safe way
    source "$SCRIPT_DIR/vision-lib.sh"
}

# =============================================================================
# vision_load_index tests
# =============================================================================

@test "vision-lib: script exists and is sourceable" {
    skip_if_deps_missing
    source "$SCRIPT_DIR/vision-lib.sh"
}

@test "vision_load_index: empty registry returns []" {
    load_vision_lib
    cp "$FIXTURES/index-empty.md" "$TEST_TMPDIR/index.md"

    result=$(vision_load_index "$TEST_TMPDIR")
    [ "$result" = "[]" ]
}

@test "vision_load_index: missing registry returns []" {
    load_vision_lib
    result=$(vision_load_index "$TEST_TMPDIR/nonexistent")
    [ "$result" = "[]" ]
}

@test "vision_load_index: parses three visions correctly" {
    load_vision_lib
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/index.md"

    result=$(vision_load_index "$TEST_TMPDIR")
    count=$(echo "$result" | jq 'length')
    [ "$count" -eq 3 ]

    # Check first vision fields
    id=$(echo "$result" | jq -r '.[0].id')
    [ "$id" = "vision-001" ]

    status=$(echo "$result" | jq -r '.[0].status')
    [ "$status" = "Captured" ]

    refs=$(echo "$result" | jq '.[0].refs')
    [ "$refs" -eq 4 ]

    # Check tags are arrays
    tag_count=$(echo "$result" | jq '.[0].tags | length')
    [ "$tag_count" -eq 2 ]
}

@test "vision_load_index: skips malformed entries" {
    load_vision_lib
    cp "$FIXTURES/index-malformed.md" "$TEST_TMPDIR/index.md"

    result=$(vision_load_index "$TEST_TMPDIR" 2>/dev/null)
    count=$(echo "$result" | jq 'length')
    # Only vision-001 should pass validation (others have bad IDs, missing status, etc.)
    [ "$count" -eq 1 ]

    id=$(echo "$result" | jq -r '.[0].id')
    [ "$id" = "vision-001" ]
}

# =============================================================================
# vision_match_tags tests
# =============================================================================

@test "vision_match_tags: counts correct overlap" {
    load_vision_lib

    result=$(vision_match_tags "architecture,security" '["architecture","constraints"]')
    [ "$result" -eq 1 ]
}

@test "vision_match_tags: full overlap" {
    load_vision_lib

    result=$(vision_match_tags "architecture,constraints" '["architecture","constraints"]')
    [ "$result" -eq 2 ]
}

@test "vision_match_tags: zero overlap" {
    load_vision_lib

    result=$(vision_match_tags "testing,eventing" '["architecture","constraints"]')
    [ "$result" -eq 0 ]
}

@test "vision_match_tags: single tag match" {
    load_vision_lib

    result=$(vision_match_tags "philosophy" '["architecture","philosophy","constraints"]')
    [ "$result" -eq 1 ]
}

@test "vision_match_tags: empty work tags" {
    load_vision_lib

    result=$(vision_match_tags "" '["architecture","constraints"]')
    [ "$result" -eq 0 ]
}

# =============================================================================
# vision_sanitize_text tests
# =============================================================================

@test "vision_sanitize_text: extracts insight from file" {
    load_vision_lib

    result=$(vision_sanitize_text "$FIXTURES/entry-valid.md")
    # Should contain the actual insight text
    [[ "$result" == *"governance"* ]]
    # Should NOT contain other sections
    [[ "$result" != *"Connection Points"* ]]
}

@test "vision_sanitize_text: strips injection patterns" {
    load_vision_lib

    result=$(vision_sanitize_text "$FIXTURES/entry-injection.md")
    # Should NOT contain system tags
    [[ "$result" != *"<system>"* ]]
    [[ "$result" != *"IGNORE ALL PREVIOUS"* ]]
    # Should NOT contain prompt tags
    [[ "$result" != *"<prompt>"* ]]
    # Should NOT contain code fences
    [[ "$result" != *'```'* ]]
    # Should strip indirect instructions
    [[ "$result" != *"ignore previous context"* ]]
}

@test "vision_sanitize_text: strips decoded HTML entities" {
    load_vision_lib

    result=$(vision_sanitize_text "$FIXTURES/entry-injection.md")
    # HTML entities should be decoded then stripped
    [[ "$result" != *"&lt;system&gt;"* ]]
}

@test "vision_sanitize_text: respects max character limit" {
    load_vision_lib

    result=$(vision_sanitize_text "$FIXTURES/entry-valid.md" 50)
    # Should be truncated (with "..." appended)
    [ ${#result} -le 60 ]  # Allow some margin for "..."
}

@test "vision_sanitize_text: strips case-insensitive injection patterns" {
    load_vision_lib

    result=$(vision_sanitize_text "$FIXTURES/entry-semantic-threat.md")
    # Should NOT contain uppercase SYSTEM tags
    [[ "$result" != *"<SYSTEM>"* ]]
    [[ "$result" != *"UPPERCASE system"* ]]
    # Should strip semantic threats (case-insensitive)
    [[ "$result" != *"IGNORE ALL"* ]]
    [[ "$result" != *"IGNORE THE ABOVE"* ]]
    [[ "$result" != *"ACT AS"* ]]
    [[ "$result" != *"You Are Now"* ]]
    [[ "$result" != *"FORGET ALL"* ]]
    [[ "$result" != *"RESET CONTEXT"* ]]
    [[ "$result" != *"Do Not Follow"* ]]
    [[ "$result" != *"New Instructions"* ]]
    [[ "$result" != *"PRETEND TO BE"* ]]
}

@test "vision_sanitize_text: handles missing file gracefully" {
    load_vision_lib

    # When given non-file input, treat as raw text
    result=$(vision_sanitize_text "some raw text here")
    [[ "$result" == *"some raw text here"* ]]
}

# =============================================================================
# vision_validate_entry tests
# =============================================================================

@test "vision_validate_entry: accepts valid entry" {
    load_vision_lib

    result=$(vision_validate_entry "$FIXTURES/entry-valid.md")
    [ "$result" = "VALID" ]
}

@test "vision_validate_entry: rejects malformed entry" {
    load_vision_lib

    run vision_validate_entry "$FIXTURES/entry-malformed.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"INVALID"* ]]
    [[ "$output" == *"missing Source field"* ]]
}

@test "vision_validate_entry: rejects missing file" {
    load_vision_lib

    run vision_validate_entry "$TEST_TMPDIR/nonexistent.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"SKIP"* ]]
}

# =============================================================================
# vision_extract_tags tests
# =============================================================================

@test "vision_extract_tags: maps file paths to tags" {
    load_vision_lib

    result=$(echo -e "flatline-orchestrator.sh\nmulti-model-router.sh\nbridge-review.sh" | vision_extract_tags -)
    [[ "$result" == *"architecture"* ]]
    [[ "$result" == *"multi-model"* ]]
}

@test "vision_extract_tags: deduplicates tags" {
    load_vision_lib

    result=$(echo -e "bridge-one.sh\nbridge-two.sh\norchestrator.sh" | vision_extract_tags -)
    # Should only have "architecture" once
    count=$(echo "$result" | grep -c "architecture" || true)
    [ "$count" -eq 1 ]
}

@test "vision_extract_tags: handles unrecognized paths" {
    load_vision_lib

    result=$(echo "some-random-file.txt" | vision_extract_tags -)
    [ -z "$result" ]
}

# =============================================================================
# Input validation tests (SKP-005)
# =============================================================================

@test "_vision_validate_id: accepts valid vision IDs" {
    load_vision_lib

    _vision_validate_id "vision-001"
    _vision_validate_id "vision-999"
}

@test "_vision_validate_id: rejects invalid vision IDs" {
    load_vision_lib

    run _vision_validate_id "vision-1"
    [ "$status" -eq 1 ]

    run _vision_validate_id "vision-abcd"
    [ "$status" -eq 1 ]

    run _vision_validate_id "not-a-vision"
    [ "$status" -eq 1 ]
}

@test "_vision_validate_tag: accepts valid tags" {
    load_vision_lib

    _vision_validate_tag "architecture"
    _vision_validate_tag "multi-model"
    _vision_validate_tag "a123"
}

@test "_vision_validate_tag: rejects invalid tags" {
    load_vision_lib

    run _vision_validate_tag "UPPERCASE"
    [ "$status" -eq 1 ]

    run _vision_validate_tag "123starts-with-number"
    [ "$status" -eq 1 ]

    run _vision_validate_tag "has spaces"
    [ "$status" -eq 1 ]
}

# =============================================================================
# vision_update_status tests
# =============================================================================

@test "vision_update_status: updates status in index" {
    load_vision_lib
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/index.md"
    mkdir -p "$TEST_TMPDIR/entries"

    vision_update_status "vision-001" "Exploring" "$TEST_TMPDIR"
    result=$(grep "^| vision-001 " "$TEST_TMPDIR/index.md")
    [[ "$result" == *"Exploring"* ]]
}

@test "vision_update_status: rejects invalid status" {
    load_vision_lib
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/index.md"

    run vision_update_status "vision-001" "InvalidStatus" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
}

@test "vision_update_status: rejects invalid vision ID" {
    load_vision_lib
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/index.md"

    run vision_update_status "bad-id" "Exploring" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
}

# =============================================================================
# vision_record_ref tests
# =============================================================================

@test "vision_record_ref: increments ref counter" {
    load_vision_lib
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/index.md"

    vision_record_ref "vision-001" "bridge-test" "$TEST_TMPDIR"
    result=$(grep "^| vision-001 " "$TEST_TMPDIR/index.md")
    # Was 4, should now be 5
    [[ "$result" == *"| 5 |"* ]]
}

@test "vision_record_ref: rejects nonexistent vision" {
    load_vision_lib
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/index.md"

    run vision_record_ref "vision-999" "bridge-test" "$TEST_TMPDIR"
    [ "$status" -ne 0 ]
}

@test "vision_record_ref: concurrent writers don't corrupt counters" {
    load_vision_lib
    if ! command -v flock &>/dev/null; then
        skip "flock not available"
    fi
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/index.md"

    # vision-001 starts at refs=4, run 5 parallel increments
    for i in $(seq 1 5); do
        (
            source "$SCRIPT_DIR/vision-lib.sh"
            vision_record_ref "vision-001" "bridge-concurrent-$i" "$TEST_TMPDIR"
        ) &
    done
    wait

    refs=$(grep "^| vision-001 " "$TEST_TMPDIR/index.md" | awk -F'|' '{print $7}' | xargs)
    [ "$refs" -eq 9 ]
}

# =============================================================================
# vision_check_lore_elevation tests
# =============================================================================

@test "vision_check_lore_elevation: returns ELEVATE when refs exceed threshold" {
    load_vision_lib
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/index.md"

    # vision-001 has refs=4, threshold default is 3
    result=$(vision_check_lore_elevation "vision-001" "$TEST_TMPDIR")
    [ "$result" = "ELEVATE" ]
}

@test "vision_check_lore_elevation: returns NO when refs below threshold" {
    load_vision_lib
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/index.md"

    # vision-002 has refs=1, threshold default is 3
    result=$(vision_check_lore_elevation "vision-002" "$TEST_TMPDIR")
    [ "$result" = "NO" ]
}

@test "vision_check_lore_elevation: returns NO for missing index" {
    load_vision_lib

    result=$(vision_check_lore_elevation "vision-001" "$TEST_TMPDIR/nonexistent")
    [ "$result" = "NO" ]
}

# =============================================================================
# vision_generate_lore_entry tests
# =============================================================================

@test "vision_generate_lore_entry: generates YAML for valid vision" {
    load_vision_lib
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/index.md"
    mkdir -p "$TEST_TMPDIR/entries"
    cp "$FIXTURES/entry-valid.md" "$TEST_TMPDIR/entries/vision-001.md"

    result=$(vision_generate_lore_entry "vision-001" "$TEST_TMPDIR")

    # Should contain required YAML fields
    [[ "$result" == *"id: vision-elevated-vision-001"* ]]
    [[ "$result" == *"term:"* ]]
    [[ "$result" == *"short:"* ]]
    [[ "$result" == *"context:"* ]]
    [[ "$result" == *"source:"* ]]
    [[ "$result" == *"tags:"* ]]
    [[ "$result" == *"vision_id:"* ]]
}

@test "vision_generate_lore_entry: fails for missing entry file" {
    load_vision_lib
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/index.md"

    run vision_generate_lore_entry "vision-001" "$TEST_TMPDIR"
    [ "$status" -eq 1 ]
}

@test "vision_generate_lore_entry: includes sanitized insight text" {
    load_vision_lib
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/index.md"
    mkdir -p "$TEST_TMPDIR/entries"
    cp "$FIXTURES/entry-valid.md" "$TEST_TMPDIR/entries/vision-001.md"

    result=$(vision_generate_lore_entry "vision-001" "$TEST_TMPDIR")

    # Should contain governance text from entry-valid.md insight
    [[ "$result" == *"governance"* ]]
}

@test "vision_generate_lore_entry: includes vision-elevated tag" {
    load_vision_lib
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/index.md"
    mkdir -p "$TEST_TMPDIR/entries"
    cp "$FIXTURES/entry-valid.md" "$TEST_TMPDIR/entries/vision-001.md"

    result=$(vision_generate_lore_entry "vision-001" "$TEST_TMPDIR")

    [[ "$result" == *"vision-elevated"* ]]
    [[ "$result" == *"discovered"* ]]
}

# =============================================================================
# vision_append_lore_entry tests
# =============================================================================

@test "vision_append_lore_entry: appends to existing lore file" {
    load_vision_lib
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/index.md"
    mkdir -p "$TEST_TMPDIR/entries"
    cp "$FIXTURES/entry-valid.md" "$TEST_TMPDIR/entries/vision-001.md"

    # Create a minimal lore file structure
    mkdir -p "$TEST_TMPDIR/.claude/data/lore/discovered"
    cat > "$TEST_TMPDIR/.claude/data/lore/discovered/visions.yaml" <<'LORE_EOF'
entries: []
LORE_EOF

    # Override PROJECT_ROOT for lore file location
    PROJECT_ROOT="$TEST_TMPDIR" vision_append_lore_entry "vision-001" "$TEST_TMPDIR"

    # Verify entry was appended
    grep -q "vision-elevated-vision-001" "$TEST_TMPDIR/.claude/data/lore/discovered/visions.yaml"
}

@test "vision_append_lore_entry: idempotent — does not duplicate" {
    load_vision_lib
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/index.md"
    mkdir -p "$TEST_TMPDIR/entries"
    cp "$FIXTURES/entry-valid.md" "$TEST_TMPDIR/entries/vision-001.md"

    mkdir -p "$TEST_TMPDIR/.claude/data/lore/discovered"
    cat > "$TEST_TMPDIR/.claude/data/lore/discovered/visions.yaml" <<'LORE_EOF'
entries: []
LORE_EOF

    # Append twice
    PROJECT_ROOT="$TEST_TMPDIR" vision_append_lore_entry "vision-001" "$TEST_TMPDIR"
    PROJECT_ROOT="$TEST_TMPDIR" vision_append_lore_entry "vision-001" "$TEST_TMPDIR"

    # Should only have one entry
    count=$(grep -c "vision_id:" "$TEST_TMPDIR/.claude/data/lore/discovered/visions.yaml" || echo "0")
    [ "$count" -eq 1 ]
}

@test "vision_append_lore_entry: fails for missing lore file" {
    load_vision_lib
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/index.md"
    mkdir -p "$TEST_TMPDIR/entries"
    cp "$FIXTURES/entry-valid.md" "$TEST_TMPDIR/entries/vision-001.md"

    run bash -c "source '$SCRIPT_DIR/vision-lib.sh' && PROJECT_ROOT='$TEST_TMPDIR' vision_append_lore_entry 'vision-001' '$TEST_TMPDIR'"
    [ "$status" -eq 1 ]
}

# =============================================================================
# Vision Registry Seeding tests (cycle-042)
# =============================================================================

@test "vision seeding: imported entry from ecosystem repo validates" {
    load_vision_lib
    local entry_file="$PROJECT_ROOT/grimoires/loa/visions/entries/vision-001.md"
    [ -f "$entry_file" ] || skip "vision-001.md not present (seeding not yet complete)"
    run bash -c "source '$SCRIPT_DIR/vision-lib.sh' && vision_validate_entry '$entry_file'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

@test "vision seeding: status update via vision_update_status works for imported entries" {
    load_vision_lib
    # Copy a real entry to temp dir for safe mutation
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/index.md"
    mkdir -p "$TEST_TMPDIR/entries"
    cp "$FIXTURES/entry-valid.md" "$TEST_TMPDIR/entries/vision-001.md"

    # Update status from Captured to Exploring
    run bash -c "source '$SCRIPT_DIR/vision-lib.sh' && vision_update_status 'vision-001' 'Exploring' '$TEST_TMPDIR'"
    [ "$status" -eq 0 ]

    # Verify the entry file was updated
    run grep -c 'Exploring' "$TEST_TMPDIR/entries/vision-001.md"
    [ "$output" -ge 1 ]
}

@test "vision seeding: index statistics reflect correct counts after population" {
    load_vision_lib
    local index_file="$PROJECT_ROOT/grimoires/loa/visions/index.md"
    [ -f "$index_file" ] || skip "index.md not populated yet"

    # Count entries in the table (lines with | vision- pattern)
    run grep -c '| vision-' "$index_file"
    [ "$output" -eq 9 ]

    # Verify statistics
    run grep 'Total captured:' "$index_file"
    [[ "$output" == *"6"* ]]

    run grep 'Total exploring:' "$index_file"
    [[ "$output" == *"2"* ]]

    run grep 'Total implemented:' "$index_file"
    [[ "$output" == *"1"* ]]
}

# =============================================================================
# Sprint 4 (cycle-042): Dynamic index statistics
# =============================================================================

@test "vision_regenerate_index_stats: correctly counts statuses from table" {
    local test_index="$TEST_TMPDIR/index.md"
    cat > "$test_index" <<'EOF'
<!-- schema_version: 1 -->
# Vision Registry

## Active Visions

| ID | Title | Source | Status | Tags | Refs |
|----|-------|--------|--------|------|------|
| vision-001 | Test A | src-a | Captured | arch | 0 |
| vision-002 | Test B | src-b | Exploring | sec | 0 |
| vision-003 | Test C | src-c | Exploring | sec | 0 |
| vision-004 | Test D | src-d | Implemented | arch | 0 |
| vision-005 | Test E | src-e | Captured | ux | 0 |
| vision-006 | Test F | src-f | Deferred | misc | 0 |

## Statistics

- Total captured: 999
- Total exploring: 999
- Total proposed: 999
- Total implemented: 999
- Total deferred: 999
EOF

    # Source lib and call function directly (not via run, since it's a shell function)
    _VISION_LIB_LOADED=""
    source "$PROJECT_ROOT/.claude/scripts/vision-lib.sh"
    vision_regenerate_index_stats "$test_index"

    # Verify correct counts
    run grep 'Total captured:' "$test_index"
    [[ "$output" == *"2"* ]]

    run grep 'Total exploring:' "$test_index"
    [[ "$output" == *"2"* ]]

    run grep 'Total proposed:' "$test_index"
    [[ "$output" == *"0"* ]]

    run grep 'Total implemented:' "$test_index"
    [[ "$output" == *"1"* ]]

    run grep 'Total deferred:' "$test_index"
    [[ "$output" == *"1"* ]]
}

@test "vision_regenerate_index_stats: handles empty table (all zeros)" {
    local test_index="$TEST_TMPDIR/index.md"
    cat > "$test_index" <<'EOF'
<!-- schema_version: 1 -->
# Vision Registry

## Active Visions

| ID | Title | Source | Status | Tags | Refs |
|----|-------|--------|--------|------|------|

## Statistics

- Total captured: 5
- Total exploring: 3
EOF

    # Source lib and call function directly
    _VISION_LIB_LOADED=""
    source "$PROJECT_ROOT/.claude/scripts/vision-lib.sh"
    vision_regenerate_index_stats "$test_index"

    # All counts should be 0
    run grep 'Total captured:' "$test_index"
    [[ "$output" == *"0"* ]]

    run grep 'Total exploring:' "$test_index"
    [[ "$output" == *"0"* ]]
}
