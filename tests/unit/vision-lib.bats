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
