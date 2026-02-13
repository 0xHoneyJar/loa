#!/usr/bin/env bats
# Unit tests for post-merge-orchestrator.sh
# Sprint 1 cycle-007: Pipeline orchestrator — args, state, phase matrix, dry-run

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/post-merge-orchestrator.sh"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/post-merge-test-$$"
    mkdir -p "$TEST_TMPDIR"

    # Create isolated git repo for testing
    export TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/.claude/scripts"
    mkdir -p "$TEST_REPO/.run"
    git -C "$TEST_REPO" init --quiet
    git -C "$TEST_REPO" config user.email "test@test.com"
    git -C "$TEST_REPO" config user.name "Test"

    # Create initial commit so HEAD exists
    echo "init" > "$TEST_REPO/README.md"
    git -C "$TEST_REPO" add README.md
    git -C "$TEST_REPO" commit -m "initial" --quiet

    # Copy bootstrap and required scripts
    cp "$PROJECT_ROOT/.claude/scripts/bootstrap.sh" "$TEST_REPO/.claude/scripts/"
    if [[ -f "$PROJECT_ROOT/.claude/scripts/path-lib.sh" ]]; then
        cp "$PROJECT_ROOT/.claude/scripts/path-lib.sh" "$TEST_REPO/.claude/scripts/"
    fi
    cp "$SCRIPT" "$TEST_REPO/.claude/scripts/"
    cp "$PROJECT_ROOT/.claude/scripts/semver-bump.sh" "$TEST_REPO/.claude/scripts/"
    cp "$PROJECT_ROOT/.claude/scripts/release-notes-gen.sh" "$TEST_REPO/.claude/scripts/"

    # Override PROJECT_ROOT for testing
    export PROJECT_ROOT="$TEST_REPO"

    # Use the test repo copy of the script
    TEST_SCRIPT="$TEST_REPO/.claude/scripts/post-merge-orchestrator.sh"

    # Create a fake merge SHA
    MERGE_SHA=$(git -C "$TEST_REPO" rev-parse HEAD)
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

# =============================================================================
# Basic Tests
# =============================================================================

@test "post-merge: script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "post-merge: shows help with --help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"post-merge-orchestrator.sh"* ]]
}

@test "post-merge: rejects unknown arguments" {
    run "$TEST_SCRIPT" --bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown argument"* ]]
}

# =============================================================================
# Argument Validation Tests
# =============================================================================

@test "post-merge: requires --pr" {
    run "$TEST_SCRIPT" --type cycle --sha abc123
    [ "$status" -eq 1 ]
    [[ "$output" == *"--pr is required"* ]]
}

@test "post-merge: requires --type" {
    run "$TEST_SCRIPT" --pr 42 --sha abc123
    [ "$status" -eq 1 ]
    [[ "$output" == *"--type is required"* ]]
}

@test "post-merge: requires --sha" {
    run "$TEST_SCRIPT" --pr 42 --type cycle
    [ "$status" -eq 1 ]
    [[ "$output" == *"--sha is required"* ]]
}

@test "post-merge: rejects invalid --type" {
    run "$TEST_SCRIPT" --pr 42 --type invalid --sha abc123
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid --type"* ]]
}

@test "post-merge: accepts cycle type" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 42 --type cycle --sha "$MERGE_SHA" --dry-run
    [ "$status" -eq 0 ]
}

@test "post-merge: accepts bugfix type" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 42 --type bugfix --sha "$MERGE_SHA" --dry-run
    [ "$status" -eq 0 ]
}

@test "post-merge: accepts other type" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 42 --type other --sha "$MERGE_SHA" --dry-run
    [ "$status" -eq 0 ]
}

# =============================================================================
# State File Tests
# =============================================================================

@test "post-merge: creates state file on execution" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 42 --type bugfix --sha "$MERGE_SHA" --dry-run
    [ "$status" -eq 0 ]
    [ -f "$TEST_REPO/.run/post-merge-state.json" ]
}

@test "post-merge: state file has correct schema_version" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 42 --type bugfix --sha "$MERGE_SHA" --dry-run
    [ "$status" -eq 0 ]
    local version
    version=$(jq -r '.schema_version' "$TEST_REPO/.run/post-merge-state.json")
    [ "$version" = "1" ]
}

@test "post-merge: state file records pr_number" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 99 --type bugfix --sha "$MERGE_SHA" --dry-run
    [ "$status" -eq 0 ]
    local pr
    pr=$(jq -r '.pr_number' "$TEST_REPO/.run/post-merge-state.json")
    [ "$pr" = "99" ]
}

@test "post-merge: state file records pr_type" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 42 --type cycle --sha "$MERGE_SHA" --dry-run
    [ "$status" -eq 0 ]
    local type
    type=$(jq -r '.pr_type' "$TEST_REPO/.run/post-merge-state.json")
    [ "$type" = "cycle" ]
}

@test "post-merge: state file finishes with DONE state" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 42 --type bugfix --sha "$MERGE_SHA" --dry-run
    [ "$status" -eq 0 ]
    local state
    state=$(jq -r '.state' "$TEST_REPO/.run/post-merge-state.json")
    [ "$state" = "DONE" ]
}

# =============================================================================
# Phase Matrix Tests
# =============================================================================

@test "post-merge: cycle type runs all 8 phases" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 42 --type cycle --sha "$MERGE_SHA" --dry-run
    [ "$status" -eq 0 ]

    # In dry-run, no phase should be "not in phase matrix" skipped
    local matrix_skipped
    matrix_skipped=$(jq '[.phases[] | select(.result.reason == "not in phase matrix for this PR type")] | length' "$TEST_REPO/.run/post-merge-state.json")
    [ "$matrix_skipped" = "0" ]
}

@test "post-merge: bugfix type skips changelog, gt_regen, rtfm, release" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 42 --type bugfix --sha "$MERGE_SHA" --dry-run
    [ "$status" -eq 0 ]

    # Bugfix only runs: classify, semver, tag, notify
    # So changelog, gt_regen, rtfm, release should be matrix-skipped
    for phase in changelog gt_regen rtfm release; do
        local reason
        reason=$(jq -r ".phases.${phase}.result.reason // empty" "$TEST_REPO/.run/post-merge-state.json")
        [[ "$reason" == "not in phase matrix for this PR type" ]]
    done
}

@test "post-merge: other type skips changelog, gt_regen, rtfm, release" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 42 --type other --sha "$MERGE_SHA" --dry-run
    [ "$status" -eq 0 ]

    for phase in changelog gt_regen rtfm release; do
        local reason
        reason=$(jq -r ".phases.${phase}.result.reason // empty" "$TEST_REPO/.run/post-merge-state.json")
        [[ "$reason" == "not in phase matrix for this PR type" ]]
    done
}

# =============================================================================
# Dry-Run Tests
# =============================================================================

@test "post-merge: dry-run does not create tags" {
    skip_if_deps_missing

    # Set up a version tag so semver can compute
    echo "v" > "$TEST_REPO/v.txt"
    git -C "$TEST_REPO" add v.txt
    git -C "$TEST_REPO" commit -m "feat: something" --quiet
    git -C "$TEST_REPO" tag -a v1.0.0 -m "v1.0.0"
    echo "more" > "$TEST_REPO/more.txt"
    git -C "$TEST_REPO" add more.txt
    git -C "$TEST_REPO" commit -m "feat: new feature" --quiet
    MERGE_SHA=$(git -C "$TEST_REPO" rev-parse HEAD)

    run "$TEST_SCRIPT" --pr 42 --type cycle --sha "$MERGE_SHA" --dry-run
    [ "$status" -eq 0 ]

    # No new tag should be created
    local tag_count
    tag_count=$(git -C "$TEST_REPO" tag -l 'v1.1.0' | wc -l)
    [ "$tag_count" -eq 0 ]
}

@test "post-merge: dry-run displays phase actions" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 42 --type cycle --sha "$MERGE_SHA" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"dry-run"* ]] || [[ "$output" == *"DRY RUN"* ]]
}

# =============================================================================
# Flag Combination Tests
# =============================================================================

@test "post-merge: --skip-gt flag skips ground truth" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 42 --type cycle --sha "$MERGE_SHA" --dry-run --skip-gt
    [ "$status" -eq 0 ]

    local reason
    reason=$(jq -r '.phases.gt_regen.result.reason // empty' "$TEST_REPO/.run/post-merge-state.json")
    [[ "$reason" == *"--skip-gt"* ]]
}

@test "post-merge: --skip-rtfm flag skips RTFM" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 42 --type cycle --sha "$MERGE_SHA" --dry-run --skip-rtfm
    [ "$status" -eq 0 ]

    local reason
    reason=$(jq -r '.phases.rtfm.result.reason // empty' "$TEST_REPO/.run/post-merge-state.json")
    [[ "$reason" == *"--skip-rtfm"* ]] || [[ "$reason" == *"placeholder"* ]]
}

@test "post-merge: pipeline header shows PR and type" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 42 --type cycle --sha "$MERGE_SHA" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"PR: #42"* ]]
    [[ "$output" == *"Type: cycle"* ]]
}

@test "post-merge: pipeline displays completion summary" {
    skip_if_deps_missing
    run "$TEST_SCRIPT" --pr 42 --type bugfix --sha "$MERGE_SHA" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pipeline Complete"* ]]
}
