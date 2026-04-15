#!/usr/bin/env bats
# Tests for spiral harness pipeline profiles (cycle-072)
# Sources REAL implementation — no shadow testing (Bridgebuilder SPIRAL-001)
# Covers: AC-3, AC-4, AC-5, AC-21, AC-26

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    # Source the real harness functions (main guard prevents execution)
    export PROJECT_ROOT
    TEST_TMPDIR="$(mktemp -d)"
    ORIG_DIR="$PWD"
    source "$PROJECT_ROOT/.claude/scripts/spiral-evidence.sh"
    _init_flight_recorder "$TEST_TMPDIR"
    source "$PROJECT_ROOT/.claude/scripts/spiral-harness.sh"
}

teardown() {
    cd "$ORIG_DIR"  # Restore working directory (F-008/F-011)
    rm -rf "$TEST_TMPDIR"
}

# ---------------------------------------------------------------------------
# Test 1: standard profile resolves to sprint-only gates (AC-3)
# ---------------------------------------------------------------------------
@test "profiles: standard resolves to sprint-only gates" {
    PIPELINE_PROFILE="standard"
    _resolve_profile
    [[ "$FLATLINE_GATES" == "sprint" ]]
}

# ---------------------------------------------------------------------------
# Test 2: full profile resolves to all gates (AC-5)
# ---------------------------------------------------------------------------
@test "profiles: full resolves to all gates" {
    PIPELINE_PROFILE="full"
    _resolve_profile
    [[ "$FLATLINE_GATES" == "prd,sdd,sprint" ]]
}

# ---------------------------------------------------------------------------
# Test 3: light profile resolves to no gates + Sonnet advisor (AC-4)
# ---------------------------------------------------------------------------
@test "profiles: light resolves to no gates and Sonnet advisor" {
    PIPELINE_PROFILE="light"
    _resolve_profile
    [[ -z "$FLATLINE_GATES" ]]
    [[ "$ADVISOR_MODEL" == "$EXECUTOR_MODEL" ]]
}

# ---------------------------------------------------------------------------
# Test 4: unknown profile falls back to standard
# ---------------------------------------------------------------------------
@test "profiles: unknown profile falls back to standard" {
    PIPELINE_PROFILE="unknown_garbage"
    _resolve_profile
    [[ "$PIPELINE_PROFILE" == "standard" ]]
    [[ "$FLATLINE_GATES" == "sprint" ]]
}

# ---------------------------------------------------------------------------
# Test 5: _should_run_flatline correct for standard profile
# ---------------------------------------------------------------------------
@test "profiles: should_run_flatline correct for standard" {
    PIPELINE_PROFILE="standard"
    _resolve_profile

    _should_run_flatline "sprint"
    ! _should_run_flatline "prd"
    ! _should_run_flatline "sdd"
}

# ---------------------------------------------------------------------------
# Test 6: auto-escalation triggers on auth keyword (AC-21)
# ---------------------------------------------------------------------------
@test "profiles: auto-escalation triggers on auth keyword" {
    PIPELINE_PROFILE="light"
    _PROFILE_EXPLICITLY_SET=false
    _resolve_profile
    _auto_escalate_profile "Implement authentication middleware"
    [[ "$PIPELINE_PROFILE" == "full" ]]
    [[ "$FLATLINE_GATES" == "prd,sdd,sprint" ]]
}

# ---------------------------------------------------------------------------
# Test 7: auto-escalation triggers on system path in sprint (AC-21)
# ---------------------------------------------------------------------------
@test "profiles: auto-escalation triggers on system path in sprint" {
    PIPELINE_PROFILE="standard"
    _PROFILE_EXPLICITLY_SET=false

    local tmpdir
    tmpdir="$(mktemp -d)"

    # Create a sprint plan referencing .claude/scripts
    mkdir -p "$tmpdir/grimoires/loa"
    echo "## Sprint 1: Modify .claude/scripts/harness" > "$tmpdir/grimoires/loa/sprint.md"

    # Run escalation from temp directory
    cd "$tmpdir"
    _auto_escalate_profile "Update the harness"
    cd "$PROJECT_ROOT"

    [[ "$PIPELINE_PROFILE" == "full" ]]
    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# Test 8: SKILL.md dispatch guard contains harness route (AC-26)
# ---------------------------------------------------------------------------
@test "profiles: SKILL.md dispatch guard routes to spiral-harness.sh" {
    local skill_md="$PROJECT_ROOT/.claude/skills/spiraling/SKILL.md"
    [[ -f "$skill_md" ]]
    grep -q "DISPATCH GUARD" "$skill_md"
    grep -q "spiral-harness.sh" "$skill_md"
    grep -q "MUST NOT implement code directly" "$skill_md"
}
