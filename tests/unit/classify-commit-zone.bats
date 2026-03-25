#!/usr/bin/env bats
# Unit tests for classify-commit-zone.sh
# Sprint 107 cycle-052: Commit zone classification

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/classify-commit-zone.sh"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/classify-zone-test-$$"
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
    cp "$SCRIPT" "$TEST_REPO/.claude/scripts/"

    # Override PROJECT_ROOT for testing
    export PROJECT_ROOT="$TEST_REPO"

    # Use the test repo copy of the script
    TEST_SCRIPT="$TEST_REPO/.claude/scripts/classify-commit-zone.sh"
}

teardown() {
    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# Helper: create a commit touching specific files
make_commit_with_files() {
    local msg="$1"
    shift
    for file in "$@"; do
        mkdir -p "$TEST_REPO/$(dirname "$file")"
        echo "content" > "$TEST_REPO/$file"
        git -C "$TEST_REPO" add "$file"
    done
    git -C "$TEST_REPO" commit -m "$msg" --quiet
}

# Helper: get HEAD SHA
get_head_sha() {
    git -C "$TEST_REPO" rev-parse HEAD
}

# =============================================================================
# Zone Classification Tests
# =============================================================================

@test "classify-commit-zone: script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "classify-commit-zone: shows help with --help" {
    run "$TEST_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"classify-commit-zone"* ]]
}

@test "classify-commit-zone: system-only for .claude/ changes" {
    make_commit_with_files "chore: update rules" ".claude/rules/test.md"
    local sha
    sha=$(get_head_sha)

    run "$TEST_SCRIPT" "$sha"
    [ "$status" -eq 0 ]
    [ "$output" = "system-only" ]
}

@test "classify-commit-zone: state-only for grimoires/ changes" {
    make_commit_with_files "chore: update notes" "grimoires/loa/NOTES.md"
    local sha
    sha=$(get_head_sha)

    run "$TEST_SCRIPT" "$sha"
    [ "$status" -eq 0 ]
    [ "$output" = "state-only" ]
}

@test "classify-commit-zone: state-only for .beads/ changes" {
    make_commit_with_files "chore: update beads" ".beads/data.json"
    local sha
    sha=$(get_head_sha)

    run "$TEST_SCRIPT" "$sha"
    [ "$status" -eq 0 ]
    [ "$output" = "state-only" ]
}

@test "classify-commit-zone: state-only for .run/ changes" {
    make_commit_with_files "chore: run state" ".run/state.json"
    local sha
    sha=$(get_head_sha)

    run "$TEST_SCRIPT" "$sha"
    [ "$status" -eq 0 ]
    [ "$output" = "state-only" ]
}

@test "classify-commit-zone: state-only for .ck/ changes" {
    make_commit_with_files "chore: ck state" ".ck/data.json"
    local sha
    sha=$(get_head_sha)

    run "$TEST_SCRIPT" "$sha"
    [ "$status" -eq 0 ]
    [ "$output" = "state-only" ]
}

@test "classify-commit-zone: app for src/ changes" {
    make_commit_with_files "feat: add feature" "src/main.ts"
    local sha
    sha=$(get_head_sha)

    run "$TEST_SCRIPT" "$sha"
    [ "$status" -eq 0 ]
    [ "$output" = "app" ]
}

@test "classify-commit-zone: app for mixed app+system changes" {
    make_commit_with_files "feat: add feature with config" "src/main.ts" ".claude/rules/new.md"
    local sha
    sha=$(get_head_sha)

    run "$TEST_SCRIPT" "$sha"
    [ "$status" -eq 0 ]
    [ "$output" = "app" ]
}

@test "classify-commit-zone: mixed-internal for system+state changes" {
    make_commit_with_files "chore: internal update" ".claude/rules/test.md" "grimoires/loa/data.json"
    local sha
    sha=$(get_head_sha)

    run "$TEST_SCRIPT" "$sha"
    [ "$status" -eq 0 ]
    [ "$output" = "mixed-internal" ]
}

@test "classify-commit-zone: invalid SHA returns error" {
    make_commit_with_files "initial" "README.md"

    run "$TEST_SCRIPT" "deadbeef1234567890"
    [ "$status" -ne 0 ]
}

@test "classify-commit-zone: batch mode outputs JSONL" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    git -C "$TEST_REPO" tag -a "v1.0.0" -m "v1.0.0"
    make_commit_with_files "feat: app change" "src/app.ts"
    make_commit_with_files "chore: system change" ".claude/rules/x.md"

    run "$TEST_SCRIPT" --batch --range "v1.0.0..HEAD"
    [ "$status" -eq 0 ]
    # Should have 2 lines of JSONL
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    [ "$line_count" -eq 2 ]
    # Each line should be valid JSON
    echo "$output" | head -1 | jq . > /dev/null 2>&1
    echo "$output" | tail -1 | jq . > /dev/null 2>&1
}

@test "classify-commit-zone: batch mode has correct zone fields" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    git -C "$TEST_REPO" tag -a "v1.0.0" -m "v1.0.0"
    make_commit_with_files "feat: app change" "src/app.ts"

    run "$TEST_SCRIPT" --batch --range "v1.0.0..HEAD"
    [ "$status" -eq 0 ]
    local zone
    zone=$(echo "$output" | jq -r '.zone')
    [ "$zone" = "app" ]
}

# =============================================================================
# is_loa_repo Tests
# =============================================================================

@test "classify-commit-zone: is_loa_repo detects by remote URL" {
    # Set remote to loa repo
    git -C "$TEST_REPO" remote add origin "https://github.com/0xHoneyJar/loa.git" 2>/dev/null || \
        git -C "$TEST_REPO" remote set-url origin "https://github.com/0xHoneyJar/loa.git"
    make_commit_with_files "initial" "README.md"

    source "$TEST_SCRIPT"
    run is_loa_repo
    [ "$status" -eq 0 ]
}

@test "classify-commit-zone: is_loa_repo detects by heuristic (CLAUDE.loa.md)" {
    make_commit_with_files "initial" "README.md"
    mkdir -p "$TEST_REPO/.claude/loa"
    echo "# Loa" > "$TEST_REPO/.claude/loa/CLAUDE.loa.md"

    source "$TEST_SCRIPT"
    run is_loa_repo
    [ "$status" -eq 0 ]
}

@test "classify-commit-zone: is_loa_repo returns 1 for downstream repo" {
    # Set remote to something other than loa
    git -C "$TEST_REPO" remote add origin "https://github.com/example/myapp.git" 2>/dev/null || \
        git -C "$TEST_REPO" remote set-url origin "https://github.com/example/myapp.git"
    make_commit_with_files "initial" "README.md"

    source "$TEST_SCRIPT"
    run is_loa_repo
    [ "$status" -eq 1 ]
}

skip_if_deps_missing() {
    if ! command -v jq &>/dev/null; then
        skip "jq not installed"
    fi
}
