#!/usr/bin/env bats
# Unit tests for vision-lifecycle.sh
# Cycle-069 (#486): Vision Registry Lifecycle CLI

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/vision-lifecycle.sh"
    QUERY_SCRIPT="$PROJECT_ROOT/.claude/scripts/vision-query.sh"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/vision-lifecycle-test-$$"
    mkdir -p "$TEST_TMPDIR/grimoires/loa/visions/entries"
    mkdir -p "$TEST_TMPDIR/grimoires/loa/a2a/trajectory"
    mkdir -p "$TEST_TMPDIR/.claude/data/lore/discovered"

    # Override PROJECT_ROOT
    export PROJECT_ROOT="$TEST_TMPDIR"

    # Create a lore file for promote tests
    cat > "$TEST_TMPDIR/.claude/data/lore/discovered/visions.yaml" << 'LORE'
# Discovered lore from vision elevation
LORE

    # Create test vision entries
    _create_entry() {
        local id="$1" status="$2" title="$3" tags="${4:-architecture}"
        cat > "$TEST_TMPDIR/grimoires/loa/visions/entries/${id}.md" << ENTRY
# Vision: ${title}

**ID**: ${id}
**Source**: Test source
**Date**: 2026-04-14T10:00:00Z
**Status**: ${status}
**Tags**: [${tags}]

## Insight

Test insight for ${id}.

## Potential

To be explored
ENTRY
    }

    _create_entry "vision-001" "Captured" "Test Captured Vision"
    _create_entry "vision-002" "Exploring" "Test Exploring Vision" "security"
    _create_entry "vision-003" "Proposed" "Test Proposed Vision"
    _create_entry "vision-004" "Implemented" "Test Implemented Vision"

    # Build initial index
    "$QUERY_SCRIPT" --rebuild-index 2>/dev/null || true
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

@test "vision-lifecycle: requires command and vision-id" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
}

@test "vision-lifecycle: rejects invalid vision ID format" {
    run "$SCRIPT" promote "bad-id"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Invalid vision ID"* ]]
}

@test "vision-lifecycle: rejects unknown command" {
    run "$SCRIPT" destroy vision-001
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown command"* ]]
}

@test "vision-lifecycle: reject requires --reason" {
    run "$SCRIPT" reject vision-001
    [ "$status" -eq 2 ]
    [[ "$output" == *"--reason is required"* ]]
}

# =============================================================================
# Simple Transitions
# =============================================================================

@test "vision-lifecycle: explore transitions Captured to Exploring" {
    run "$SCRIPT" explore vision-001
    [ "$status" -eq 0 ]
    [[ "$output" == *"Exploring"* ]]
    run grep 'Status' "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-001.md"
    [[ "$output" == *"Exploring"* ]]
}

@test "vision-lifecycle: propose transitions Exploring to Proposed" {
    run "$SCRIPT" propose vision-002
    [ "$status" -eq 0 ]
    [[ "$output" == *"Proposed"* ]]
    run grep 'Status' "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-002.md"
    [[ "$output" == *"Proposed"* ]]
}

@test "vision-lifecycle: defer transitions to Deferred" {
    run "$SCRIPT" defer vision-003
    [ "$status" -eq 0 ]
    [[ "$output" == *"Deferred"* ]]
    run grep 'Status' "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-003.md"
    [[ "$output" == *"Deferred"* ]]
}

@test "vision-lifecycle: defer accepts optional --reason" {
    run "$SCRIPT" defer vision-003 --reason "Not priority this cycle"
    [ "$status" -eq 0 ]
    run grep 'Deferred-Reason' "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-003.md"
    [[ "$output" == *"Not priority this cycle"* ]]
}

# =============================================================================
# Terminal State Blocking
# =============================================================================

@test "vision-lifecycle: blocks promote on Implemented (terminal)" {
    run "$SCRIPT" promote vision-004
    [ "$status" -eq 5 ]
    [[ "$output" == *"terminal state"* ]]
}

@test "vision-lifecycle: blocks archive on Implemented (terminal)" {
    run "$SCRIPT" archive vision-004
    [ "$status" -eq 5 ]
    [[ "$output" == *"terminal state"* ]]
}

@test "vision-lifecycle: blocks reject on Implemented (terminal)" {
    run "$SCRIPT" reject vision-004 --reason "test"
    [ "$status" -eq 5 ]
    [[ "$output" == *"terminal state"* ]]
}

@test "vision-lifecycle: blocks explore on Implemented (terminal)" {
    run "$SCRIPT" explore vision-004
    [ "$status" -eq 5 ]
}

# =============================================================================
# Archive with Reason
# =============================================================================

@test "vision-lifecycle: archive updates status to Archived" {
    run "$SCRIPT" archive vision-001 --reason "Stale"
    [ "$status" -eq 0 ]
    run grep 'Status' "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-001.md"
    [[ "$output" == *"Archived"* ]]
}

@test "vision-lifecycle: archive adds Archived-Reason to frontmatter" {
    run "$SCRIPT" archive vision-001 --reason "No longer relevant"
    [ "$status" -eq 0 ]
    run grep 'Archived-Reason' "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-001.md"
    [[ "$output" == *"No longer relevant"* ]]
}

@test "vision-lifecycle: archive makes vision terminal" {
    "$SCRIPT" archive vision-001 --reason "Stale" 2>/dev/null
    run "$SCRIPT" promote vision-001
    [ "$status" -eq 5 ]
}

# =============================================================================
# Reject with Reason
# =============================================================================

@test "vision-lifecycle: reject updates status to Rejected" {
    run "$SCRIPT" reject vision-001 --reason "Invalid premise"
    [ "$status" -eq 0 ]
    run grep 'Status' "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-001.md"
    [[ "$output" == *"Rejected"* ]]
}

@test "vision-lifecycle: reject adds Rejected-Reason to frontmatter" {
    run "$SCRIPT" reject vision-001 --reason "Does not apply"
    [ "$status" -eq 0 ]
    run grep 'Rejected-Reason' "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-001.md"
    [[ "$output" == *"Does not apply"* ]]
}

# =============================================================================
# Input Sanitization (Review Fix #1)
# =============================================================================

@test "vision-lifecycle: reason with pipe char is sanitized" {
    run "$SCRIPT" archive vision-001 --reason "reason | with pipes"
    [ "$status" -eq 0 ]
    run grep 'Archived-Reason' "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-001.md"
    [[ "$output" != *"|"* ]]
    [[ "$output" == *"reason - with pipes"* ]]
}

@test "vision-lifecycle: reason with forward slash is sanitized" {
    run "$SCRIPT" archive vision-002 --reason "path/to/something"
    [ "$status" -eq 0 ]
    run grep 'Archived-Reason' "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-002.md"
    [[ "$output" != *"/"* ]]
}

@test "vision-lifecycle: reason with ampersand is sanitized" {
    run "$SCRIPT" archive vision-003 --reason "this & that"
    [ "$status" -eq 0 ]
    run grep 'Archived-Reason' "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-003.md"
    [[ "$output" == *"this and that"* ]]
}

# =============================================================================
# Promote Flow
# =============================================================================

@test "vision-lifecycle: promote updates status to Implemented" {
    run "$SCRIPT" promote vision-001
    [ "$status" -eq 0 ]
    run grep 'Status' "$TEST_TMPDIR/grimoires/loa/visions/entries/vision-001.md"
    [[ "$output" == *"Implemented"* ]]
}

@test "vision-lifecycle: promote creates lore entry" {
    run "$SCRIPT" promote vision-001
    [ "$status" -eq 0 ]
    run grep 'vision-001' "$TEST_TMPDIR/.claude/data/lore/discovered/visions.yaml"
    [[ "$output" == *"vision-001"* ]]
}

@test "vision-lifecycle: double promote is idempotent (second blocked by terminal)" {
    "$SCRIPT" promote vision-001 2>/dev/null
    run "$SCRIPT" promote vision-001
    [ "$status" -eq 5 ]
}

@test "vision-lifecycle: promote rebuilds index" {
    "$SCRIPT" promote vision-001 2>/dev/null
    run grep 'vision-001' "$TEST_TMPDIR/grimoires/loa/visions/index.md"
    [[ "$output" == *"Implemented"* ]]
}

# =============================================================================
# Trajectory Logging
# =============================================================================

@test "vision-lifecycle: transitions log to trajectory" {
    "$SCRIPT" explore vision-001 2>/dev/null
    local log_file
    log_file=$(ls "$TEST_TMPDIR/grimoires/loa/a2a/trajectory"/vision-lifecycle-*.jsonl 2>/dev/null | head -1)
    [ -n "$log_file" ]
    [ -f "$log_file" ]
    run jq -r '.event' "$log_file"
    [[ "$output" == *"vision_transition"* ]]
}

@test "vision-lifecycle: promote logs vision_promoted event" {
    "$SCRIPT" promote vision-001 2>/dev/null
    local log_file
    log_file=$(ls "$TEST_TMPDIR/grimoires/loa/a2a/trajectory"/vision-lifecycle-*.jsonl 2>/dev/null | head -1)
    run grep 'vision_promoted' "$log_file"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Missing Entry Handling
# =============================================================================

@test "vision-lifecycle: nonexistent vision exits 4" {
    run "$SCRIPT" explore vision-099
    [ "$status" -eq 4 ]
    [[ "$output" == *"not found"* ]]
}
