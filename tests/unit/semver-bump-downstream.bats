#!/usr/bin/env bats
# Unit tests for semver-bump.sh --downstream flag
# Sprint 108 cycle-052: Zone-aware release filtering

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/semver-bump.sh"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/semver-downstream-test-$$"
    mkdir -p "$TEST_TMPDIR"

    # Create isolated git repo for testing
    export TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/.claude/scripts"
    git -C "$TEST_REPO" init --quiet
    git -C "$TEST_REPO" config user.email "test@test.com"
    git -C "$TEST_REPO" config user.name "Test"

    # Copy scripts
    cp "$PROJECT_ROOT/.claude/scripts/bootstrap.sh" "$TEST_REPO/.claude/scripts/"
    if [[ -f "$PROJECT_ROOT/.claude/scripts/path-lib.sh" ]]; then
        cp "$PROJECT_ROOT/.claude/scripts/path-lib.sh" "$TEST_REPO/.claude/scripts/"
    fi
    cp "$PROJECT_ROOT/.claude/scripts/classify-commit-zone.sh" "$TEST_REPO/.claude/scripts/"
    cp "$SCRIPT" "$TEST_REPO/.claude/scripts/"

    # Override PROJECT_ROOT for testing
    export PROJECT_ROOT="$TEST_REPO"

    # Use the test repo copy of the script
    TEST_SCRIPT="$TEST_REPO/.claude/scripts/semver-bump.sh"
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

# Helper: create a commit touching specific files
make_commit_with_files() {
    local msg="$1"
    shift
    for file in "$@"; do
        mkdir -p "$TEST_REPO/$(dirname "$file")"
        echo "content-$RANDOM" > "$TEST_REPO/$file"
        git -C "$TEST_REPO" add "$file"
    done
    git -C "$TEST_REPO" commit -m "$msg" --quiet
}

# Helper: create a version tag
make_tag() {
    local version="$1"
    git -C "$TEST_REPO" tag -a "v${version}" -m "Release v${version}"
}

# =============================================================================
# --downstream Flag Tests
# =============================================================================

@test "semver-bump --downstream: flag is accepted" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    make_tag "1.0.0"
    make_commit_with_files "feat: add feature" "src/app.ts"

    run "$TEST_SCRIPT" --downstream
    [ "$status" -eq 0 ]
}

@test "semver-bump --downstream: filters system-only commits" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    make_tag "1.0.0"
    make_commit_with_files "feat: add app feature" "src/app.ts"
    make_commit_with_files "chore: update rules" ".claude/rules/test.md"

    run "$TEST_SCRIPT" --downstream
    [ "$status" -eq 0 ]

    # Should only have 1 commit (the app one), not 2
    local commit_count
    commit_count=$(echo "$output" | jq '.commits | length')
    [ "$commit_count" -eq 1 ]

    # The remaining commit should be the feat
    local type
    type=$(echo "$output" | jq -r '.commits[0].type')
    [ "$type" = "feat" ]
}

@test "semver-bump --downstream: keeps app-zone commits" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    make_tag "1.0.0"
    make_commit_with_files "feat: user feature" "src/feature.ts"
    make_commit_with_files "fix: user bug fix" "lib/utils.ts"

    run "$TEST_SCRIPT" --downstream
    [ "$status" -eq 0 ]

    local commit_count
    commit_count=$(echo "$output" | jq '.commits | length')
    [ "$commit_count" -eq 2 ]
}

@test "semver-bump --downstream: all-internal = no bump (exit 1)" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    make_tag "1.0.0"
    make_commit_with_files "chore: update system" ".claude/scripts/test.sh"
    make_commit_with_files "chore: update state" "grimoires/loa/notes.md"

    run "$TEST_SCRIPT" --downstream
    [ "$status" -eq 1 ]
    [[ "$output" == *"No app-zone commits"* ]] || [[ "$output" == *"all filtered"* ]]
}

@test "semver-bump --downstream: without flag = unchanged behavior" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    make_tag "1.0.0"
    make_commit_with_files "feat: app feature" "src/app.ts"
    make_commit_with_files "chore: system change" ".claude/rules/test.md"

    run "$TEST_SCRIPT"
    [ "$status" -eq 0 ]

    # Without --downstream, both commits should be included
    local commit_count
    commit_count=$(echo "$output" | jq '.commits | length')
    [ "$commit_count" -eq 2 ]
}

@test "semver-bump --downstream: mixed app+internal includes app in result" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    make_tag "1.0.0"
    # This commit touches both app and system zones
    make_commit_with_files "feat: add feature with config" "src/main.ts" ".claude/rules/new.md"

    run "$TEST_SCRIPT" --downstream
    [ "$status" -eq 0 ]

    # A commit touching both app + system should be classified as "app" and included
    local commit_count
    commit_count=$(echo "$output" | jq '.commits | length')
    [ "$commit_count" -eq 1 ]
}
