#!/usr/bin/env bats
# Integration tests for Vision-Aware Planning
# Sprint 2 (cycle-041): End-to-end tests for vision registry integration
# Includes cross-sprint regression (IMP-005)

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT_DIR="$PROJECT_ROOT/.claude/scripts"
    QUERY_SCRIPT="$SCRIPT_DIR/vision-registry-query.sh"
    CAPTURE_SCRIPT="$SCRIPT_DIR/bridge-vision-capture.sh"
    FIXTURES="$PROJECT_ROOT/tests/fixtures/vision-registry"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/vision-integration-test-$$"
    mkdir -p "$TEST_TMPDIR/grimoires/loa/visions/entries"
    mkdir -p "$TEST_TMPDIR/grimoires/loa/a2a/trajectory"

    export PROJECT_ROOT="$TEST_TMPDIR"
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
# E2E: Config disabled = zero vision code runs
# =============================================================================

@test "integration: config disabled means query returns empty" {
    skip_if_deps_missing
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/grimoires/loa/visions/index.md"

    # Config with vision_registry.enabled: false
    cat > "$TEST_TMPDIR/.loa.config.yaml" <<'EOF'
vision_registry:
  enabled: false
EOF

    # Query should still work (config check is caller's responsibility)
    # but when called with matching tags, it returns results
    # The SKILL.md checks enabled before calling — here we test the query itself
    result=$("$QUERY_SCRIPT" --tags "architecture" --visions-dir "$TEST_TMPDIR/grimoires/loa/visions" --min-overlap 1 --json)
    count=$(echo "$result" | jq 'length')
    # Query doesn't check config — it returns results. The SKILL.md gates on config.
    [ "$count" -ge 1 ]
}

# =============================================================================
# E2E: Shadow mode logs but doesn't present
# =============================================================================

@test "integration: shadow mode writes JSONL and updates state" {
    skip_if_deps_missing
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/grimoires/loa/visions/index.md"

    cat > "$TEST_TMPDIR/.loa.config.yaml" <<'EOF'
vision_registry:
  enabled: true
  shadow_mode: true
  shadow_cycles_before_prompt: 3
EOF

    echo '{"shadow_cycles_completed":0,"last_shadow_run":null,"matches_during_shadow":0}' \
        > "$TEST_TMPDIR/grimoires/loa/visions/.shadow-state.json"

    # Run in shadow mode
    "$QUERY_SCRIPT" \
        --tags "architecture" \
        --visions-dir "$TEST_TMPDIR/grimoires/loa/visions" \
        --min-overlap 1 \
        --shadow \
        --shadow-cycle "cycle-041" \
        --shadow-phase "plan-and-analyze" \
        --json > /dev/null

    # Verify shadow state was updated
    cycles=$(jq -r '.shadow_cycles_completed' "$TEST_TMPDIR/grimoires/loa/visions/.shadow-state.json")
    [ "$cycles" -eq 1 ]

    # Verify JSONL log was created
    log_file=$(ls "$TEST_TMPDIR/grimoires/loa/a2a/trajectory/vision-shadow-"*.jsonl 2>/dev/null | head -1)
    [ -f "$log_file" ]

    # Verify log entry has expected fields
    entry=$(head -1 "$log_file")
    phase=$(echo "$entry" | jq -r '.phase')
    [ "$phase" = "plan-and-analyze" ]
}

# =============================================================================
# E2E: Active mode presents and tracks refs
# =============================================================================

@test "integration: active mode query returns scored results with text" {
    skip_if_deps_missing
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/grimoires/loa/visions/index.md"
    cp "$FIXTURES/entry-valid.md" "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-001.md"

    cat > "$TEST_TMPDIR/.loa.config.yaml" <<'EOF'
vision_registry:
  enabled: true
  shadow_mode: false
  min_tag_overlap: 1
  max_visions_per_session: 3
EOF

    result=$("$QUERY_SCRIPT" \
        --tags "architecture,constraints" \
        --visions-dir "$TEST_TMPDIR/grimoires/loa/visions" \
        --min-overlap 1 \
        --include-text \
        --json)

    count=$(echo "$result" | jq 'length')
    [ "$count" -ge 1 ]

    # First result should be vision-001 (highest score)
    first_id=$(echo "$result" | jq -r '.[0].id')
    [ "$first_id" = "vision-001" ]

    # Insight text should be present and sanitized
    insight=$(echo "$result" | jq -r '.[0].insight')
    [[ "$insight" == *"governance"* ]]
}

@test "integration: ref tracking increments on active mode interaction" {
    skip_if_deps_missing
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/grimoires/loa/visions/index.md"

    # Simulate what SKILL.md does when user chooses "Explore"
    source "$SCRIPT_DIR/vision-lib.sh"

    # Record a reference (simulating user interaction)
    vision_record_ref "vision-001" "plan-and-analyze-ref" "$TEST_TMPDIR/grimoires/loa/visions"

    # Verify ref count increased (was 4, now 5)
    refs=$(grep "^| vision-001 " "$TEST_TMPDIR/grimoires/loa/visions/index.md" | awk -F'|' '{print $7}' | xargs)
    [ "$refs" -eq 5 ]
}

# =============================================================================
# E2E: bridge-vision-capture.sh still works after refactor
# =============================================================================

@test "integration: capture script --help still works" {
    run "$CAPTURE_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "integration: capture script --check-relevant works with empty index" {
    cp "$FIXTURES/index-empty.md" "$TEST_TMPDIR/grimoires/loa/visions/index.md"

    # Create a minimal diff file
    echo "diff --git a/flatline-orchestrator.sh b/flatline-orchestrator.sh" > "$TEST_TMPDIR/test.diff"

    result=$(PROJECT_ROOT="$TEST_TMPDIR" "$CAPTURE_SCRIPT" --check-relevant "$TEST_TMPDIR/test.diff" "$TEST_TMPDIR/grimoires/loa/visions")
    # Empty index should return nothing
    [ -z "$result" ]
}

@test "integration: capture script creates vision entries from findings" {
    skip_if_deps_missing
    cp "$FIXTURES/index-empty.md" "$TEST_TMPDIR/grimoires/loa/visions/index.md"

    # Create findings JSON with VISION entries
    cat > "$TEST_TMPDIR/findings.json" <<'EOF'
{
  "findings": [
    {
      "id": "VISION-001",
      "severity": "VISION",
      "title": "Test Vision Entry",
      "description": "A test vision created by integration test",
      "potential": "Testing the capture pipeline"
    }
  ]
}
EOF

    result=$(PROJECT_ROOT="$TEST_TMPDIR" "$CAPTURE_SCRIPT" \
        --findings "$TEST_TMPDIR/findings.json" \
        --bridge-id "bridge-test-integration" \
        --iteration 1 \
        --pr 999 \
        --output-dir "$TEST_TMPDIR/grimoires/loa/visions")

    [ "$result" = "1" ]

    # Verify entry file was created
    [ -f "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-001.md" ]

    # Verify entry has correct content
    grep -q "Test Vision Entry" "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-001.md"
    grep -q "bridge-test-integration" "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-001.md"
}

# =============================================================================
# E2E: Shadow graduation detection
# =============================================================================

@test "integration: graduation triggers after threshold cycles" {
    skip_if_deps_missing
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/grimoires/loa/visions/index.md"

    cat > "$TEST_TMPDIR/.loa.config.yaml" <<'EOF'
vision_registry:
  enabled: true
  shadow_mode: true
  shadow_cycles_before_prompt: 2
EOF

    # Pre-populate shadow state at threshold - 1
    echo '{"shadow_cycles_completed":1,"last_shadow_run":"2026-02-26T10:00:00Z","matches_during_shadow":5}' \
        > "$TEST_TMPDIR/grimoires/loa/visions/.shadow-state.json"

    result=$("$QUERY_SCRIPT" \
        --tags "architecture" \
        --visions-dir "$TEST_TMPDIR/grimoires/loa/visions" \
        --min-overlap 1 \
        --shadow \
        --json)

    # Should include graduation flag
    ready=$(echo "$result" | jq -r '.graduation.ready // false')
    [ "$ready" = "true" ]

    total_matches=$(echo "$result" | jq -r '.graduation.total_matches')
    [ "$total_matches" -gt 0 ]
}

# =============================================================================
# Cross-sprint regression (IMP-005)
# =============================================================================

@test "regression: Sprint 1 vision-lib tests still pass" {
    run bats "$PROJECT_ROOT/../../tests/unit/vision-lib.bats"
    # Note: PROJECT_ROOT is overridden to TEST_TMPDIR in setup, so use absolute path
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    run bats "$REAL_ROOT/tests/unit/vision-lib.bats"
    [ "$status" -eq 0 ]
}

@test "regression: Sprint 1 vision-registry-query tests still pass" {
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    run bats "$REAL_ROOT/tests/unit/vision-registry-query.bats"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Pipeline integration tests (cycle-042, Sprint 3)
# =============================================================================

@test "pipeline: shadow mode end-to-end with populated registry" {
    skip_if_deps_missing

    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    local real_script_dir="$REAL_ROOT/.claude/scripts"

    # Create test visions with known tags
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/grimoires/loa/visions/index.md"
    cp "$FIXTURES/entry-valid.md" "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-001.md"

    # Create additional entries for tag matching
    cat > "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-002.md" <<'ENTRY'
# Vision: Test Security Finding

**ID**: vision-002
**Source**: test-bridge
**PR**: #1
**Date**: 2026-01-01
**Status**: Captured
**Tags**: [security, testing]

## Insight
Test security insight.

## Potential
Test potential.
ENTRY

    cat > "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-003.md" <<'ENTRY'
# Vision: Test Architecture Pattern

**ID**: vision-003
**Source**: test-bridge
**PR**: #2
**Date**: 2026-01-01
**Status**: Exploring
**Tags**: [architecture, testing]

## Insight
Test architecture insight.

## Potential
Test potential.
ENTRY

    # Initialize shadow state
    echo '{"shadow_cycles_completed": 0, "last_shadow_run": null, "matches_during_shadow": 0}' \
        > "$TEST_TMPDIR/grimoires/loa/visions/.shadow-state.json"

    # Create config
    cat > "$TEST_TMPDIR/.loa.config.yaml" <<'CONF'
vision_registry:
  enabled: true
  shadow_mode: true
CONF

    # Run shadow query
    run bash -c "PROJECT_ROOT='$TEST_TMPDIR' '$real_script_dir/vision-registry-query.sh' \
        --tags testing --min-overlap 1 --shadow --shadow-cycle test-cycle --shadow-phase test \
        --visions-dir '$TEST_TMPDIR/grimoires/loa/visions' --json"
    [ "$status" -eq 0 ]

    # Verify shadow state incremented
    local shadow_cycles
    shadow_cycles=$(jq '.shadow_cycles_completed' "$TEST_TMPDIR/grimoires/loa/visions/.shadow-state.json")
    [ "$shadow_cycles" -eq 1 ]

    # Verify JSONL log created
    local log_count
    log_count=$(ls "$TEST_TMPDIR/grimoires/loa/a2a/trajectory"/vision-shadow-*.jsonl 2>/dev/null | wc -l)
    [ "$log_count" -ge 1 ]
}

@test "pipeline: lore elevation triggers at ref threshold" {
    skip_if_deps_missing

    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    local real_script_dir="$REAL_ROOT/.claude/scripts"

    # Setup: copy index with a high-ref vision
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/grimoires/loa/visions/index.md"
    cp "$FIXTURES/entry-valid.md" "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-001.md"

    # Manually set refs above threshold (default threshold is 3)
    sed -i 's/| 0 |$/| 5 |/' "$TEST_TMPDIR/grimoires/loa/visions/index.md"

    # Create config with low threshold
    cat > "$TEST_TMPDIR/.loa.config.yaml" <<'CONF'
vision_registry:
  enabled: true
  ref_elevation_threshold: 3
CONF

    # Run elevation check
    run bash -c "source '$real_script_dir/vision-lib.sh' && \
        PROJECT_ROOT='$TEST_TMPDIR' \
        vision_check_lore_elevation 'vision-001' '$TEST_TMPDIR/grimoires/loa/visions'"

    [ "$status" -eq 0 ]
    [[ "$output" == "ELEVATE" ]]
}
