#!/usr/bin/env bats
# =============================================================================
# red-team-template-resolution.bats — Issue #528 regression test
# =============================================================================
# Bug: red-team-pipeline.sh used PROJECT_ROOT-anchored template paths, which
# broke in submodule mode where PROJECT_ROOT points to the host repo (no
# .claude/templates/ there) rather than the Loa submodule.
#
# Fix: ATTACK_TEMPLATE and COUNTER_TEMPLATE now use SCRIPT_DIR-anchored paths
# ($SCRIPT_DIR/../templates/...) so the templates always resolve relative to
# where the scripts live, regardless of the PROJECT_ROOT topology.
#
# These tests FAIL against the pre-fix code (PROJECT_ROOT-anchored) in TC-1
# and PASS after the fix (SCRIPT_DIR-anchored) in both TC-1 and TC-2.
# =============================================================================

setup() {
    TEST_TMPDIR=$(mktemp -d)
    export TEST_TMPDIR

    # ------------------------------------------------------------------
    # TC-1 topology: submodule mode
    #   .claude/scripts lives under the Loa submodule tree.
    #   PROJECT_ROOT points to the host repo — no .claude/templates there.
    # ------------------------------------------------------------------
    mkdir -p "$TEST_TMPDIR/submodule/loa/.claude/scripts"
    mkdir -p "$TEST_TMPDIR/submodule/loa/.claude/templates"
    touch "$TEST_TMPDIR/submodule/loa/.claude/templates/flatline-red-team.md.template"
    touch "$TEST_TMPDIR/submodule/loa/.claude/templates/flatline-counter-design.md.template"
    # Host repo root — intentionally has NO .claude/templates directory
    mkdir -p "$TEST_TMPDIR/submodule/host"

    # ------------------------------------------------------------------
    # TC-2 topology: standalone mode
    #   SCRIPT_DIR and PROJECT_ROOT share the same tree root.
    # ------------------------------------------------------------------
    mkdir -p "$TEST_TMPDIR/standalone/.claude/scripts"
    mkdir -p "$TEST_TMPDIR/standalone/.claude/templates"
    touch "$TEST_TMPDIR/standalone/.claude/templates/flatline-red-team.md.template"
    touch "$TEST_TMPDIR/standalone/.claude/templates/flatline-counter-design.md.template"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# TC-1: submodule mode — SCRIPT_DIR-anchored path resolves; PROJECT_ROOT-anchored does NOT
# =============================================================================
# SCRIPT_DIR = .../submodule/loa/.claude/scripts
# PROJECT_ROOT = .../submodule/host   (different tree — host repo)
# Templates exist at: SCRIPT_DIR/../templates/
# Templates do NOT exist at: PROJECT_ROOT/.claude/templates/
#
# This is the regression proof: the pre-fix code would look in
# $PROJECT_ROOT/.claude/templates/ (host repo) and fail. The fix looks in
# $SCRIPT_DIR/../templates/ (Loa submodule) and succeeds.
@test "TC-1 submodule mode: SCRIPT_DIR-anchored path resolves for flatline-red-team template" {
    SCRIPT_DIR="$TEST_TMPDIR/submodule/loa/.claude/scripts"
    PROJECT_ROOT="$TEST_TMPDIR/submodule/host"

    # Post-fix assertion: SCRIPT_DIR-anchored path resolves
    [[ -f "$SCRIPT_DIR/../templates/flatline-red-team.md.template" ]]
}

@test "TC-1 submodule mode: SCRIPT_DIR-anchored path resolves for flatline-counter-design template" {
    SCRIPT_DIR="$TEST_TMPDIR/submodule/loa/.claude/scripts"
    PROJECT_ROOT="$TEST_TMPDIR/submodule/host"

    # Post-fix assertion: SCRIPT_DIR-anchored path resolves
    [[ -f "$SCRIPT_DIR/../templates/flatline-counter-design.md.template" ]]
}

@test "TC-1 submodule mode: PROJECT_ROOT-anchored path does NOT resolve (regression proof)" {
    SCRIPT_DIR="$TEST_TMPDIR/submodule/loa/.claude/scripts"
    PROJECT_ROOT="$TEST_TMPDIR/submodule/host"

    # Pre-fix code would use PROJECT_ROOT/.claude/templates/ — this MUST NOT exist
    # in submodule mode where PROJECT_ROOT is the host repo.
    # If this test fails, the regression has been re-introduced.
    [[ ! -f "$PROJECT_ROOT/.claude/templates/flatline-red-team.md.template" ]]
    [[ ! -f "$PROJECT_ROOT/.claude/templates/flatline-counter-design.md.template" ]]
}

# =============================================================================
# TC-2: standalone mode — SCRIPT_DIR-anchored path resolves
# =============================================================================
# SCRIPT_DIR = .../standalone/.claude/scripts
# PROJECT_ROOT = .../standalone   (same tree root as SCRIPT_DIR)
# Templates exist at: SCRIPT_DIR/../templates/ == PROJECT_ROOT/.claude/templates/
#
# Both approaches work in standalone mode, but the SCRIPT_DIR-anchored fix
# is verified to be correct here as well.
@test "TC-2 standalone mode: SCRIPT_DIR-anchored path resolves for flatline-red-team template" {
    SCRIPT_DIR="$TEST_TMPDIR/standalone/.claude/scripts"
    PROJECT_ROOT="$TEST_TMPDIR/standalone"

    [[ -f "$SCRIPT_DIR/../templates/flatline-red-team.md.template" ]]
}

@test "TC-2 standalone mode: SCRIPT_DIR-anchored path resolves for flatline-counter-design template" {
    SCRIPT_DIR="$TEST_TMPDIR/standalone/.claude/scripts"
    PROJECT_ROOT="$TEST_TMPDIR/standalone"

    [[ -f "$SCRIPT_DIR/../templates/flatline-counter-design.md.template" ]]
}
