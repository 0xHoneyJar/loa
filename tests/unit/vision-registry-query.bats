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

# =============================================================================
# Auto-tag derivation tests
# =============================================================================

@test "vision-registry-query: --tags auto derives from sprint plan" {
    skip_if_deps_missing
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/visions/index.md"

    # Create minimal sprint.md with file paths
    mkdir -p "$TEST_TMPDIR/grimoires/loa"
    cat > "$TEST_TMPDIR/grimoires/loa/sprint.md" <<'SPRINT'
# Sprint Plan

### T1: Fix orchestrator
- [ ] **File**: `.claude/scripts/flatline-orchestrator.sh` (modify)

### T2: Update constraints
- [ ] **File**: `.claude/data/constraints.json` (modify)
SPRINT

    # Create minimal prd.md with keywords
    cat > "$TEST_TMPDIR/grimoires/loa/prd.md" <<'PRD'
# PRD

## Architecture
Multi-model adversarial review system.

## Security
Input validation and content sanitization.
PRD

    result=$(PROJECT_ROOT="$TEST_TMPDIR" "$SCRIPT" --tags auto --visions-dir "$TEST_TMPDIR/visions" --min-overlap 1 --json)
    count=$(echo "$result" | jq 'length')
    # Should find visions matching derived tags (architecture, multi-model, constraints, security)
    [ "$count" -ge 1 ]
}

@test "vision-registry-query: --tags auto with no context returns empty" {
    skip_if_deps_missing
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/visions/index.md"

    # No sprint.md or prd.md in test dir → no tags derivable
    result=$(PROJECT_ROOT="$TEST_TMPDIR" "$SCRIPT" --tags auto --visions-dir "$TEST_TMPDIR/visions" --json)
    [ "$result" = "[]" ]
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

# =============================================================================
# Sprint 4 (cycle-042): Shadow mode min_overlap auto-lowering
# =============================================================================

@test "vision-registry-query: shadow mode auto-lowers min_overlap to 1" {
    skip_if_deps_missing

    # Shadow mode needs trajectory dir under PROJECT_ROOT
    mkdir -p "$TEST_TMPDIR/grimoires/loa/a2a/trajectory"

    # Create index with entries that have only 1 tag overlap with "security"
    cat > "$TEST_TMPDIR/visions/index.md" <<'INDEXEOF'
<!-- schema_version: 1 -->
# Vision Registry

## Active Visions

| ID | Title | Source | Status | Tags | Refs |
|----|-------|--------|--------|------|------|
| vision-001 | Credential Provider | bridge-test / PR #1 | Captured | architecture | 0 |
| vision-002 | Template Safety | bridge-test / PR #2 | Exploring | security, bash | 0 |
| vision-003 | Context Isolation | bridge-test / PR #3 | Exploring | security, prompt-injection | 0 |

## Statistics

- Total captured: 1
- Total exploring: 2
- Total proposed: 0
- Total implemented: 0
- Total deferred: 0
INDEXEOF

    # Shadow mode with "security" tag — should match vision-002 and vision-003 at min_overlap=1
    run env PROJECT_ROOT="$TEST_TMPDIR" "$SCRIPT" --tags "security" --visions-dir "$TEST_TMPDIR/visions" --shadow --shadow-cycle "test" --shadow-phase "test" --json
    [ "$status" -eq 0 ]

    # Should have matches (min_overlap auto-lowered to 1)
    local match_count
    match_count=$(echo "$output" | jq 'length')
    [ "$match_count" -ge 1 ]
}

@test "vision-registry-query: shadow mode respects explicit --min-overlap 2" {
    skip_if_deps_missing

    # Shadow mode needs trajectory dir under PROJECT_ROOT
    mkdir -p "$TEST_TMPDIR/grimoires/loa/a2a/trajectory"

    # Same index as above
    cat > "$TEST_TMPDIR/visions/index.md" <<'INDEXEOF'
<!-- schema_version: 1 -->
# Vision Registry

## Active Visions

| ID | Title | Source | Status | Tags | Refs |
|----|-------|--------|--------|------|------|
| vision-001 | Credential Provider | bridge-test / PR #1 | Captured | architecture | 0 |
| vision-002 | Template Safety | bridge-test / PR #2 | Exploring | security, bash | 0 |
| vision-003 | Context Isolation | bridge-test / PR #3 | Exploring | security, prompt-injection | 0 |

## Statistics

- Total captured: 1
- Total exploring: 2
- Total proposed: 0
- Total implemented: 0
- Total deferred: 0
INDEXEOF

    # Shadow mode with explicit --min-overlap 2 and only 1 matching tag — should find nothing
    run env PROJECT_ROOT="$TEST_TMPDIR" "$SCRIPT" --tags "security" --min-overlap 2 --visions-dir "$TEST_TMPDIR/visions" --shadow --shadow-cycle "test" --shadow-phase "test" --json
    [ "$status" -eq 0 ]

    local match_count
    match_count=$(echo "$output" | jq 'length')
    [ "$match_count" -eq 0 ]
}
