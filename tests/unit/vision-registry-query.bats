#!/usr/bin/env bats
# Unit tests for vision-registry-query.sh
# Sprint 1 (cycle-041): Query script — scoring, filtering, shadow mode

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/vision-registry-query.sh"
    FIXTURES="$PROJECT_ROOT/tests/fixtures/vision-registry"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/vision-query-test-$$"
    mkdir -p "$TEST_TMPDIR/visions/entries"
    mkdir -p "$TEST_TMPDIR/trajectory"

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
    if ! command -v yq &>/dev/null; then
        skip "yq not installed"
    fi
}

# =============================================================================
# Basic script tests
# =============================================================================

@test "vision-registry-query: script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "vision-registry-query: shows help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "vision-registry-query: requires --tags" {
    run "$SCRIPT" --json
    [ "$status" -eq 2 ]
    [[ "$output" == *"--tags is required"* ]]
}

@test "vision-registry-query: rejects invalid tag format" {
    run "$SCRIPT" --tags "INVALID_UPPERCASE" --json
    [ "$status" -eq 2 ]
    [[ "$output" == *"Invalid tag format"* ]]
}

# =============================================================================
# Empty registry tests
# =============================================================================

@test "vision-registry-query: empty registry returns []" {
    skip_if_deps_missing
    cp "$FIXTURES/index-empty.md" "$TEST_TMPDIR/visions/index.md"

    result=$(PROJECT_ROOT="$TEST_TMPDIR" "$SCRIPT" --tags "architecture" --visions-dir "$TEST_TMPDIR/visions" --json)
    [ "$result" = "[]" ]
}

@test "vision-registry-query: missing registry returns []" {
    skip_if_deps_missing

    result=$(PROJECT_ROOT="$TEST_TMPDIR" "$SCRIPT" --tags "architecture" --visions-dir "$TEST_TMPDIR/nonexistent" --json 2>/dev/null || echo "[]")
    [ "$result" = "[]" ]
}

# =============================================================================
# Matching tests
# =============================================================================

@test "vision-registry-query: returns matching visions" {
    skip_if_deps_missing
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/visions/index.md"

    result=$(PROJECT_ROOT="$TEST_TMPDIR" "$SCRIPT" --tags "architecture,constraints" --visions-dir "$TEST_TMPDIR/visions" --min-overlap 1 --json)
    count=$(echo "$result" | jq 'length')
    # vision-001 has architecture+constraints, vision-002 has architecture
    [ "$count" -ge 2 ]
}

@test "vision-registry-query: respects min-overlap" {
    skip_if_deps_missing
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/visions/index.md"

    result=$(PROJECT_ROOT="$TEST_TMPDIR" "$SCRIPT" --tags "architecture,constraints" --visions-dir "$TEST_TMPDIR/visions" --min-overlap 2 --json)
    count=$(echo "$result" | jq 'length')
    # Only vision-001 has both architecture and constraints
    [ "$count" -eq 1 ]

    id=$(echo "$result" | jq -r '.[0].id')
    [ "$id" = "vision-001" ]
}

@test "vision-registry-query: respects max-results" {
    skip_if_deps_missing
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/visions/index.md"

    result=$(PROJECT_ROOT="$TEST_TMPDIR" "$SCRIPT" --tags "architecture,constraints,multi-model,security,philosophy" --visions-dir "$TEST_TMPDIR/visions" --min-overlap 1 --max-results 1 --json)
    count=$(echo "$result" | jq 'length')
    [ "$count" -eq 1 ]
}

@test "vision-registry-query: status filter works" {
    skip_if_deps_missing
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/visions/index.md"

    # Only Exploring visions
    result=$(PROJECT_ROOT="$TEST_TMPDIR" "$SCRIPT" --tags "architecture" --status "Exploring" --visions-dir "$TEST_TMPDIR/visions" --min-overlap 1 --json)
    count=$(echo "$result" | jq 'length')
    [ "$count" -eq 1 ]

    id=$(echo "$result" | jq -r '.[0].id')
    [ "$id" = "vision-002" ]
}

# =============================================================================
# Scoring tests
# =============================================================================

@test "vision-registry-query: scoring algorithm ranks correctly" {
    skip_if_deps_missing
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/visions/index.md"

    result=$(PROJECT_ROOT="$TEST_TMPDIR" "$SCRIPT" --tags "architecture,constraints" --visions-dir "$TEST_TMPDIR/visions" --min-overlap 1 --json)

    # vision-001: overlap=2 (architecture+constraints), refs=4 → score = 6 + 8 = 14
    # vision-002: overlap=1 (architecture), refs=2 → score = 3 + 4 = 7
    first_id=$(echo "$result" | jq -r '.[0].id')
    first_score=$(echo "$result" | jq '.[0].score')
    second_score=$(echo "$result" | jq '.[1].score')

    [ "$first_id" = "vision-001" ]
    [ "$first_score" -gt "$second_score" ]
}

@test "vision-registry-query: includes matched_tags in output" {
    skip_if_deps_missing
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/visions/index.md"

    result=$(PROJECT_ROOT="$TEST_TMPDIR" "$SCRIPT" --tags "architecture,constraints" --visions-dir "$TEST_TMPDIR/visions" --min-overlap 1 --json)

    # vision-001 should show both matched tags
    matched=$(echo "$result" | jq -r '.[0].matched_tags | sort | join(",")')
    [ "$matched" = "architecture,constraints" ]
}

# =============================================================================
# Include text tests
# =============================================================================

@test "vision-registry-query: --include-text returns sanitized insight" {
    skip_if_deps_missing
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/visions/index.md"
    cp "$FIXTURES/entry-valid.md" "$TEST_TMPDIR/visions/entries/vision-001.md"

    result=$(PROJECT_ROOT="$TEST_TMPDIR" "$SCRIPT" --tags "architecture,constraints" --visions-dir "$TEST_TMPDIR/visions" --min-overlap 2 --include-text --json)

    insight=$(echo "$result" | jq -r '.[0].insight')
    [[ "$insight" == *"governance"* ]]
}

@test "vision-registry-query: without --include-text omits insight field" {
    skip_if_deps_missing
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/visions/index.md"

    result=$(PROJECT_ROOT="$TEST_TMPDIR" "$SCRIPT" --tags "architecture,constraints" --visions-dir "$TEST_TMPDIR/visions" --min-overlap 2 --json)

    has_insight=$(echo "$result" | jq '.[0] | has("insight")')
    [ "$has_insight" = "false" ]
}

# =============================================================================
# Shadow mode tests
# =============================================================================

@test "vision-registry-query: shadow mode writes to JSONL log" {
    skip_if_deps_missing
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/visions/index.md"

    # Create shadow state
    echo '{"shadow_cycles_completed":0,"last_shadow_run":null,"matches_during_shadow":0}' > "$TEST_TMPDIR/visions/.shadow-state.json"

    # Create trajectory dir where shadow logs go
    mkdir -p "$TEST_TMPDIR/a2a/trajectory"

    # Override PROJECT_ROOT so shadow log goes to test dir
    PROJECT_ROOT="$TEST_TMPDIR" "$SCRIPT" \
        --tags "architecture" \
        --visions-dir "$TEST_TMPDIR/visions" \
        --min-overlap 1 \
        --shadow \
        --shadow-cycle "cycle-041" \
        --json >/dev/null

    # Check shadow state was updated
    cycles=$(jq -r '.shadow_cycles_completed' "$TEST_TMPDIR/visions/.shadow-state.json")
    [ "$cycles" -eq 1 ]
}

@test "vision-registry-query: shadow mode increments counter" {
    skip_if_deps_missing
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/visions/index.md"

    echo '{"shadow_cycles_completed":1,"last_shadow_run":"2026-02-26T10:00:00Z","matches_during_shadow":2}' > "$TEST_TMPDIR/visions/.shadow-state.json"
    mkdir -p "$TEST_TMPDIR/a2a/trajectory"

    PROJECT_ROOT="$TEST_TMPDIR" "$SCRIPT" \
        --tags "architecture" \
        --visions-dir "$TEST_TMPDIR/visions" \
        --min-overlap 1 \
        --shadow \
        --json >/dev/null

    cycles=$(jq -r '.shadow_cycles_completed' "$TEST_TMPDIR/visions/.shadow-state.json")
    [ "$cycles" -eq 2 ]
}

@test "vision-registry-query: shadow graduation detected" {
    skip_if_deps_missing
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/visions/index.md"

    # Set shadow cycles to threshold - 1 so next run triggers graduation
    echo '{"shadow_cycles_completed":1,"last_shadow_run":"2026-02-26T10:00:00Z","matches_during_shadow":3}' > "$TEST_TMPDIR/visions/.shadow-state.json"
    mkdir -p "$TEST_TMPDIR/a2a/trajectory"

    # Create minimal config with threshold
    cat > "$TEST_TMPDIR/.loa.config.yaml" <<'EOF'
vision_registry:
  shadow_cycles_before_prompt: 2
EOF

    result=$(PROJECT_ROOT="$TEST_TMPDIR" "$SCRIPT" \
        --tags "architecture" \
        --visions-dir "$TEST_TMPDIR/visions" \
        --min-overlap 1 \
        --shadow \
        --json)

    # Should include graduation info
    ready=$(echo "$result" | jq -r '.graduation.ready // false')
    [ "$ready" = "true" ]
}

# =============================================================================
# Invalid input tests (SKP-005)
# =============================================================================

@test "vision-registry-query: rejects invalid status value" {
    skip_if_deps_missing

    run "$SCRIPT" --tags "architecture" --status "Invalid" --json
    [ "$status" -eq 2 ]
}

@test "vision-registry-query: rejects unknown options" {
    run "$SCRIPT" --tags "architecture" --unknown-flag
    [ "$status" -eq 2 ]
}
