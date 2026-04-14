#!/usr/bin/env bats
# Unit tests for vision-query.sh
# Cycle-069 (#486): Vision Registry Query CLI

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/vision-query.sh"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/vision-query-test-$$"
    mkdir -p "$TEST_TMPDIR/grimoires/loa/visions/entries"

    # Override PROJECT_ROOT so the script reads our test fixtures
    export PROJECT_ROOT="$TEST_TMPDIR"

    # Create test vision entries
    cat > "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-001.md" << 'ENTRY'
# Vision: Test Security Pattern

**ID**: vision-001
**Source**: Bridge iteration 1 of bridge-test-001
**PR**: #100
**Date**: 2026-04-01T10:00:00Z
**Status**: Captured
**Tags**: [security, architecture]

## Insight

This is a test insight about security patterns.

## Potential

To be explored
ENTRY

    cat > "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-002.md" << 'ENTRY'
# Vision: Test Performance Pattern

**ID**: vision-002
**Source**: Bridge iteration 2 of bridge-test-002
**PR**: #200
**Date**: 2026-03-15T10:00:00Z
**Status**: Exploring
**Tags**: [performance, testing]

## Insight

This is a test insight about performance patterns.

## Potential

To be explored
ENTRY

    cat > "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-003.md" << 'ENTRY'
# Vision: Test Implemented Pattern

**ID**: vision-003
**Source**: Issue #300
**Date**: 2026-02-01T10:00:00Z
**Status**: Implemented
**Tags**: [architecture]

## Insight

This vision was already implemented.

## Potential

Done
ENTRY
}

teardown() {
    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# =============================================================================
# Argument Validation
# =============================================================================

@test "vision-query: rejects unknown option" {
    run "$SCRIPT" --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "vision-query: rejects invalid status" {
    run "$SCRIPT" --status "InvalidStatus"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Invalid status"* ]]
}

@test "vision-query: rejects invalid tag format" {
    run "$SCRIPT" --tags "UPPERCASE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Invalid tag"* ]]
}

@test "vision-query: rejects malformed date" {
    run "$SCRIPT" --since "not-a-date"
    [ "$status" -eq 2 ]
    [[ "$output" == *"ISO-8601"* ]]
}

@test "vision-query: rejects invalid format option" {
    run "$SCRIPT" --format xml
    [ "$status" -eq 2 ]
    [[ "$output" == *"json, table, or ids"* ]]
}

# =============================================================================
# JSON Output
# =============================================================================

@test "vision-query: default format returns valid JSON" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | jq empty
}

@test "vision-query: returns all 3 entries with no filters" {
    run "$SCRIPT" --format json
    [ "$status" -eq 0 ]
    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -eq 3 ]
}

@test "vision-query: entries sorted by date descending" {
    run "$SCRIPT" --format json
    [ "$status" -eq 0 ]
    local first_date last_date
    first_date=$(echo "$output" | jq -r '.[0].date')
    last_date=$(echo "$output" | jq -r '.[-1].date')
    [[ "$first_date" > "$last_date" ]]
}

# =============================================================================
# Tag Filtering
# =============================================================================

@test "vision-query: --tags security returns only security-tagged visions" {
    run "$SCRIPT" --tags security --format ids
    [ "$status" -eq 0 ]
    [[ "$output" == *"vision-001"* ]]
    [[ "$output" != *"vision-002"* ]]
    [[ "$output" != *"vision-003"* ]]
}

@test "vision-query: --tags performance returns only performance-tagged visions" {
    run "$SCRIPT" --tags performance --format ids
    [ "$status" -eq 0 ]
    [[ "$output" == *"vision-002"* ]]
    [[ "$output" != *"vision-001"* ]]
}

@test "vision-query: --tags with multiple values uses ANY match" {
    run "$SCRIPT" --tags security,performance --format ids
    [ "$status" -eq 0 ]
    [[ "$output" == *"vision-001"* ]]
    [[ "$output" == *"vision-002"* ]]
}

@test "vision-query: --tags with no matches returns exit 1" {
    run "$SCRIPT" --tags nonexistent
    [ "$status" -eq 1 ]
}

# =============================================================================
# Status Filtering
# =============================================================================

@test "vision-query: --status Captured returns only captured" {
    run "$SCRIPT" --status Captured --count
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

@test "vision-query: --status comma-list returns multiple statuses" {
    run "$SCRIPT" --status Captured,Exploring --count
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]
}

@test "vision-query: --status is case-insensitive" {
    run "$SCRIPT" --status captured --count
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

@test "vision-query: --status Implemented returns implemented visions" {
    run "$SCRIPT" --status Implemented --format ids
    [ "$status" -eq 0 ]
    [[ "$output" == *"vision-003"* ]]
}

# =============================================================================
# Source Filtering (fixed-string match)
# =============================================================================

@test "vision-query: --source filters by fixed-string match" {
    run "$SCRIPT" --source "bridge-test-001" --format ids
    [ "$status" -eq 0 ]
    [[ "$output" == *"vision-001"* ]]
    [[ "$output" != *"vision-002"* ]]
}

@test "vision-query: --source is case-insensitive" {
    run "$SCRIPT" --source "BRIDGE-TEST-001" --format ids
    [ "$status" -eq 0 ]
    [[ "$output" == *"vision-001"* ]]
}

@test "vision-query: --source Issue matches issue-sourced vision" {
    run "$SCRIPT" --source "Issue" --format ids
    [ "$status" -eq 0 ]
    [[ "$output" == *"vision-003"* ]]
}

# =============================================================================
# Date Filtering
# =============================================================================

@test "vision-query: --since filters by date" {
    run "$SCRIPT" --since 2026-04-01 --count
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

@test "vision-query: --before filters by date" {
    run "$SCRIPT" --before 2026-03-01 --count
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

@test "vision-query: --since and --before combined" {
    run "$SCRIPT" --since 2026-03-01 --before 2026-04-01 --count
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

# =============================================================================
# Combined Filters (AND logic)
# =============================================================================

@test "vision-query: combined --tags and --status filters AND" {
    run "$SCRIPT" --tags architecture --status Captured --count
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

@test "vision-query: combined filters with no matches returns exit 1" {
    run "$SCRIPT" --tags security --status Implemented
    [ "$status" -eq 1 ]
}

# =============================================================================
# Output Formats
# =============================================================================

@test "vision-query: --format table produces pipe-delimited rows" {
    run "$SCRIPT" --format table
    [ "$status" -eq 0 ]
    [[ "$output" == *"| ID |"* ]]
    [[ "$output" == *"| vision-001 |"* ]]
}

@test "vision-query: --format ids produces one ID per line" {
    run "$SCRIPT" --format ids
    [ "$status" -eq 0 ]
    local count
    count=$(echo "$output" | wc -l)
    [ "$count" -eq 3 ]
}

@test "vision-query: --count returns integer" {
    run "$SCRIPT" --count
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
    [ "$output" -eq 3 ]
}

@test "vision-query: --limit restricts results" {
    run "$SCRIPT" --limit 1 --format json
    [ "$status" -eq 0 ]
    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -eq 1 ]
}

# =============================================================================
# Index Rebuild
# =============================================================================

@test "vision-query: --rebuild-index creates index.md" {
    run "$SCRIPT" --rebuild-index
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/grimoires/loa/visions/index.md" ]
}

@test "vision-query: rebuilt index contains all entries" {
    "$SCRIPT" --rebuild-index 2>/dev/null
    run grep -c '| vision-' "$TEST_TMPDIR/grimoires/loa/visions/index.md"
    [ "$output" -eq 3 ]
}

@test "vision-query: rebuilt index has correct statistics" {
    "$SCRIPT" --rebuild-index 2>/dev/null
    run grep 'Total captured:' "$TEST_TMPDIR/grimoires/loa/visions/index.md"
    [[ "$output" == *"Total captured: 1"* ]]
    run grep 'Total exploring:' "$TEST_TMPDIR/grimoires/loa/visions/index.md"
    [[ "$output" == *"Total exploring: 1"* ]]
    run grep 'Total implemented:' "$TEST_TMPDIR/grimoires/loa/visions/index.md"
    [[ "$output" == *"Total implemented: 1"* ]]
}

@test "vision-query: --rebuild-index is idempotent" {
    "$SCRIPT" --rebuild-index 2>/dev/null
    local first_hash
    first_hash=$(sha256sum "$TEST_TMPDIR/grimoires/loa/visions/index.md" | awk '{print $1}')
    "$SCRIPT" --rebuild-index 2>/dev/null
    local second_hash
    second_hash=$(sha256sum "$TEST_TMPDIR/grimoires/loa/visions/index.md" | awk '{print $1}')
    [ "$first_hash" = "$second_hash" ]
}

@test "vision-query: --rebuild-index --dry-run does not write file" {
    run "$SCRIPT" --rebuild-index --dry-run
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_TMPDIR/grimoires/loa/visions/index.md" ]
}

# =============================================================================
# Quarantine / Malformed Entries
# =============================================================================

@test "vision-query: malformed entry is quarantined in non-strict mode" {
    cat > "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-099.md" << 'ENTRY'
# Vision: Broken

This entry has no frontmatter fields at all.
ENTRY

    local json_output
    json_output=$("$SCRIPT" --format json 2>/dev/null)
    local exit_code=$?
    [ "$exit_code" -eq 0 ]
    # Should still return the 3 valid entries + 1 quarantined
    echo "$json_output" | jq -e '[.[] | select(.parse_error == true)] | length == 1'
}

@test "vision-query: --strict exits 3 on malformed entry" {
    cat > "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-099.md" << 'ENTRY'
# Vision: Broken

No frontmatter here.
ENTRY

    run "$SCRIPT" --strict
    [ "$status" -eq 3 ]
}

# =============================================================================
# JSON field correctness
# =============================================================================

@test "vision-query: JSON entries contain expected fields" {
    run "$SCRIPT" --format json --limit 1
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.[0] | has("id", "title", "source", "date", "status", "tags", "insight_excerpt", "refs")'
}

@test "vision-query: insight_excerpt is populated from ## Insight section" {
    run "$SCRIPT" --format json --limit 1
    [ "$status" -eq 0 ]
    local excerpt
    excerpt=$(echo "$output" | jq -r '.[0].insight_excerpt')
    [ -n "$excerpt" ]
    [[ "$excerpt" != "null" ]]
}

# =============================================================================
# Health Report
# =============================================================================

@test "vision-query: --health returns valid JSON" {
    run "$SCRIPT" --health
    [ "$status" -eq 0 ]
    echo "$output" | jq empty
}

@test "vision-query: --health reports correct total" {
    run "$SCRIPT" --health
    [ "$status" -eq 0 ]
    local total
    total=$(echo "$output" | jq '.total')
    [ "$total" -eq 3 ]
}

@test "vision-query: --health reports correct by_status breakdown" {
    run "$SCRIPT" --health
    [ "$status" -eq 0 ]
    local captured exploring implemented
    captured=$(echo "$output" | jq '.by_status.Captured')
    exploring=$(echo "$output" | jq '.by_status.Exploring')
    implemented=$(echo "$output" | jq '.by_status.Implemented')
    [ "$captured" -eq 1 ]
    [ "$exploring" -eq 1 ]
    [ "$implemented" -eq 1 ]
}

@test "vision-query: --health by_status has all seven keys" {
    run "$SCRIPT" --health
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.by_status | has("Captured","Exploring","Proposed","Implemented","Deferred","Archived","Rejected")'
}

@test "vision-query: --health exits 0 when entries exist (healthy true)" {
    run "$SCRIPT" --health
    [ "$status" -eq 0 ]
    local healthy
    healthy=$(echo "$output" | jq '.healthy')
    [ "$healthy" = "true" ]
}

@test "vision-query: --health exits 1 when no entries (healthy false)" {
    rm -f "$TEST_TMPDIR/grimoires/loa/visions/entries/"*.md
    run "$SCRIPT" --health
    [ "$status" -eq 1 ]
    local healthy total
    healthy=$(echo "$output" | jq '.healthy')
    total=$(echo "$output" | jq '.total')
    [ "$healthy" = "false" ]
    [ "$total" -eq 0 ]
}

@test "vision-query: --health newest_entry_modified is valid ISO timestamp" {
    run "$SCRIPT" --health
    [ "$status" -eq 0 ]
    local ts
    ts=$(echo "$output" | jq -r '.newest_entry_modified')
    [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "vision-query: --health newest_entry_modified is null when empty" {
    rm -f "$TEST_TMPDIR/grimoires/loa/visions/entries/"*.md
    run "$SCRIPT" --health
    [ "$status" -eq 1 ]
    local ts
    ts=$(echo "$output" | jq -r '.newest_entry_modified')
    [ "$ts" = "null" ]
}

@test "vision-query: --health --tags exits 2 (mutual exclusivity)" {
    run "$SCRIPT" --health --tags security
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot be combined"* ]]
}

@test "vision-query: --health --rebuild-index exits 2 (mutual exclusivity)" {
    run "$SCRIPT" --health --rebuild-index
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot be combined"* ]]
}

@test "vision-query: --health --status exits 2 (mutual exclusivity)" {
    run "$SCRIPT" --health --status Captured
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot be combined"* ]]
}
