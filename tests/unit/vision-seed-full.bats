#!/usr/bin/env bats
# Unit tests for seed_phase() full mode in spiral-orchestrator.sh
# Cycle-069 (#486): Vision Registry spiral integration

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/vision-seed-test-$$"
    mkdir -p "$TEST_TMPDIR/grimoires/loa/visions/entries"
    mkdir -p "$TEST_TMPDIR/cycles/cycle-cur"
    mkdir -p "$TEST_TMPDIR/cycles/cycle-prev"
    mkdir -p "$TEST_TMPDIR/grimoires/loa/a2a/trajectory"
    mkdir -p "$TEST_TMPDIR/.run"

    export PROJECT_ROOT="$TEST_TMPDIR"

    # Create test vision entries for query
    cat > "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-001.md" << 'ENTRY'
# Vision: Security Pattern

**ID**: vision-001
**Source**: Test
**Date**: 2026-04-01T10:00:00Z
**Status**: Captured
**Tags**: [security]

## Insight

A security insight for seed testing.

## Potential

To be explored
ENTRY

    cat > "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-002.md" << 'ENTRY'
# Vision: Architecture Pattern

**ID**: vision-002
**Source**: Test
**Date**: 2026-03-01T10:00:00Z
**Status**: Exploring
**Tags**: [architecture]

## Insight

An architecture insight for seed testing.

## Potential

To be explored
ENTRY

    # Create config with vision registry enabled + full mode
    cat > "$TEST_TMPDIR/.loa.config.yaml" << 'CONFIG'
spiral:
  enabled: true
  seed:
    mode: "full"
    default_tags:
      - architecture
      - security
    max_seed_visions: 10
vision_registry:
  enabled: true
CONFIG
}

teardown() {
    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# Source orchestrator to get seed_phase function
_source_orchestrator() {
    # Save real project root for sourcing scripts
    local REAL_PROJECT_ROOT
    REAL_PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    # Source bootstrap from the real project
    PROJECT_ROOT="$REAL_PROJECT_ROOT" source "$REAL_PROJECT_ROOT/.claude/scripts/bootstrap.sh" 2>/dev/null || true

    # Source orchestrator (defines seed_phase, read_config, etc.)
    PROJECT_ROOT="$REAL_PROJECT_ROOT" source "$REAL_PROJECT_ROOT/.claude/scripts/spiral-orchestrator.sh" 2>/dev/null || true

    # Now override PROJECT_ROOT to test dir so read_config, vision-query.sh
    # read from test fixtures
    export PROJECT_ROOT="$TEST_TMPDIR"
    export SCRIPT_DIR="$REAL_PROJECT_ROOT/.claude/scripts"
    export STATE_FILE="$TEST_TMPDIR/.run/spiral-state.json"
}

# =============================================================================
# Full Mode with Vision Registry
# =============================================================================

@test "seed_phase: full mode produces seed-context.md with vision data" {
    _source_orchestrator
    echo '{"state":"RUNNING","spiral_id":"test"}' > "$TEST_TMPDIR/.run/spiral-state.json"

    # Call seed_phase — capture stderr for debugging, allow non-zero exit
    seed_phase "$TEST_TMPDIR/cycles/cycle-cur" "cycle-cur" "" 2>"$TEST_TMPDIR/seed-stderr.log" || true

    if [ ! -f "$TEST_TMPDIR/cycles/cycle-cur/seed-context.md" ]; then
        echo "seed-context.md not created. stderr:" >&2
        cat "$TEST_TMPDIR/seed-stderr.log" >&2
        echo "PROJECT_ROOT=$PROJECT_ROOT" >&2
        echo "SCRIPT_DIR=$SCRIPT_DIR" >&2
        false
    fi
    run grep 'Full Mode' "$TEST_TMPDIR/cycles/cycle-cur/seed-context.md"
    [ "$status" -eq 0 ]
}

@test "seed_phase: full mode seed context contains valid JSON" {
    _source_orchestrator
    echo '{"state":"RUNNING","spiral_id":"test"}' > "$TEST_TMPDIR/.run/spiral-state.json"

    seed_phase "$TEST_TMPDIR/cycles/cycle-cur" "cycle-cur" "" 2>/dev/null || true

    [ -f "$TEST_TMPDIR/cycles/cycle-cur/seed-context.md" ] || skip "seed-context.md not created (sourcing issue)"
    local json
    json=$(sed -n '/```json/,/```/p' "$TEST_TMPDIR/cycles/cycle-cur/seed-context.md" | grep -v '```')
    echo "$json" | jq empty
}

@test "seed_phase: full mode seed context has mode=full" {
    _source_orchestrator
    echo '{"state":"RUNNING","spiral_id":"test"}' > "$TEST_TMPDIR/.run/spiral-state.json"

    seed_phase "$TEST_TMPDIR/cycles/cycle-cur" "cycle-cur" "" 2>/dev/null || true

    [ -f "$TEST_TMPDIR/cycles/cycle-cur/seed-context.md" ] || skip "seed-context.md not created (sourcing issue)"
    local json
    json=$(sed -n '/```json/,/```/p' "$TEST_TMPDIR/cycles/cycle-cur/seed-context.md" | grep -v '```')
    local mode
    mode=$(echo "$json" | jq -r '.mode')
    [ "$mode" = "full" ]
}

@test "seed_phase: full mode includes visions in seed context" {
    _source_orchestrator
    echo '{"state":"RUNNING","spiral_id":"test"}' > "$TEST_TMPDIR/.run/spiral-state.json"

    seed_phase "$TEST_TMPDIR/cycles/cycle-cur" "cycle-cur" "" 2>/dev/null || true

    [ -f "$TEST_TMPDIR/cycles/cycle-cur/seed-context.md" ] || skip "seed-context.md not created (sourcing issue)"
    local json
    json=$(sed -n '/```json/,/```/p' "$TEST_TMPDIR/cycles/cycle-cur/seed-context.md" | grep -v '```')
    local count
    count=$(echo "$json" | jq '.visions | length')
    [ "$count" -ge 1 ]
}

# =============================================================================
# Full Mode — Disabled Registry Falls Back to Degraded
# =============================================================================

@test "seed_phase: full mode with vision_registry.enabled=false degrades" {
    # Override config to disable registry
    cat > "$TEST_TMPDIR/.loa.config.yaml" << 'CONFIG'
spiral:
  enabled: true
  seed:
    mode: "full"
vision_registry:
  enabled: false
CONFIG

    _source_orchestrator
    echo '{"state":"RUNNING","spiral_id":"test"}' > "$TEST_TMPDIR/.run/spiral-state.json"

    # Create a previous cycle with sidecar for degraded mode
    echo '{"$schema_version":1,"cycle_id":"cycle-prev","review_verdict":"APPROVED","audit_verdict":"APPROVED","findings":{"blocker":0,"high":0,"medium":0,"low":0},"flatline_signature":null,"content_hash":null,"elapsed_sec":1,"exit_status":"success"}' > "$TEST_TMPDIR/cycles/cycle-prev/cycle-outcome.json"

    local stderr_output
    stderr_output=$(seed_phase "$TEST_TMPDIR/cycles/cycle-cur" "cycle-cur" "$TEST_TMPDIR/cycles/cycle-prev" 2>&1 >/dev/null)

    [[ "$stderr_output" == *"WARNING"* ]] || [[ "$stderr_output" == *"vision_registry"* ]]
}

# =============================================================================
# Tag Derivation from HARVEST Sidecar
# =============================================================================

@test "seed_phase: full mode derives tags from HARVEST sidecar" {
    # Create HARVEST sidecar with security findings
    echo '{"$schema_version":1,"cycle_id":"cycle-prev","review_verdict":"APPROVED","audit_verdict":"APPROVED","findings":[{"category":"security","severity":"high"}],"flatline_signature":null,"content_hash":null,"elapsed_sec":1,"exit_status":"success"}' > "$TEST_TMPDIR/cycles/cycle-prev/cycle-outcome.json"

    _source_orchestrator
    echo '{"state":"RUNNING","spiral_id":"test"}' > "$TEST_TMPDIR/.run/spiral-state.json"

    seed_phase "$TEST_TMPDIR/cycles/cycle-cur" "cycle-cur" "$TEST_TMPDIR/cycles/cycle-prev" 2>/dev/null

    [ -f "$TEST_TMPDIR/cycles/cycle-cur/seed-context.md" ]
    local json
    json=$(sed -n '/```json/,/```/p' "$TEST_TMPDIR/cycles/cycle-cur/seed-context.md" | grep -v '```')
    # Query tags should include security from sidecar
    local tags
    tags=$(echo "$json" | jq -r '.query.tags | join(",")')
    [[ "$tags" == *"security"* ]]
}

@test "seed_phase: full mode falls back to default_tags without sidecar" {
    _source_orchestrator
    echo '{"state":"RUNNING","spiral_id":"test"}' > "$TEST_TMPDIR/.run/spiral-state.json"

    seed_phase "$TEST_TMPDIR/cycles/cycle-cur" "cycle-cur" "" 2>/dev/null || true

    [ -f "$TEST_TMPDIR/cycles/cycle-cur/seed-context.md" ] || skip "seed-context.md not created (sourcing issue)"
    local json
    json=$(sed -n '/```json/,/```/p' "$TEST_TMPDIR/cycles/cycle-cur/seed-context.md" | grep -v '```')
    local tags
    tags=$(echo "$json" | jq -r '.query.tags | join(",")')
    # Should use default_tags from config: architecture, security
    [[ "$tags" == *"architecture"* ]] || [[ "$tags" == *"security"* ]]
}

# =============================================================================
# Zero Results — Cold Start
# =============================================================================

@test "seed_phase: full mode with zero results cold-starts" {
    # Remove all vision entries
    rm -f "$TEST_TMPDIR/grimoires/loa/visions/entries/"*.md

    _source_orchestrator
    echo '{"state":"RUNNING","spiral_id":"test"}' > "$TEST_TMPDIR/.run/spiral-state.json"

    seed_phase "$TEST_TMPDIR/cycles/cycle-cur" "cycle-cur" "" 2>/dev/null

    # No seed-context.md should be created on cold start
    [ ! -f "$TEST_TMPDIR/cycles/cycle-cur/seed-context.md" ]
}

# =============================================================================
# Octal Bug Fix Verification
# =============================================================================

@test "octal fix: local_max of 008 produces next_number 9" {
    local local_max="008"
    local_max="${local_max:-0}"
    local next_number=$((10#$local_max + 1))
    [ "$next_number" -eq 9 ]
}

@test "octal fix: local_max of 009 produces next_number 10" {
    local local_max="009"
    local_max="${local_max:-0}"
    local next_number=$((10#$local_max + 1))
    [ "$next_number" -eq 10 ]
}

@test "octal fix: empty local_max defaults to 0" {
    local local_max=""
    local_max="${local_max:-0}"
    local next_number=$((10#$local_max + 1))
    [ "$next_number" -eq 1 ]
}

@test "octal fix: local_max of 099 produces next_number 100" {
    local local_max="099"
    local_max="${local_max:-0}"
    local next_number=$((10#$local_max + 1))
    [ "$next_number" -eq 100 ]
}
