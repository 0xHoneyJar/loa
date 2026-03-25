#!/usr/bin/env bats
# Unit tests for generate-release-summary.sh
# Sprint 107 cycle-052: User-friendly release summaries

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/generate-release-summary.sh"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/release-summary-test-$$"
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
    TEST_SCRIPT="$TEST_REPO/.claude/scripts/generate-release-summary.sh"
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

# Helper: create a CHANGELOG with version sections
create_changelog() {
    local content="$1"
    echo "$content" > "$TEST_REPO/CHANGELOG.md"
}

# =============================================================================
# Basic Tests
# =============================================================================

@test "generate-release-summary: script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "generate-release-summary: shows help with --help" {
    run "$TEST_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"generate-release-summary"* ]]
}

@test "generate-release-summary: requires --from and --to" {
    run "$TEST_SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"--from and --to are required"* ]]
}

# =============================================================================
# CHANGELOG Parsing Tests
# =============================================================================

@test "generate-release-summary: parses CHANGELOG bullet points" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    git -C "$TEST_REPO" tag -a "v1.0.0" -m "v1.0.0"
    make_commit_with_files "feat: add golden path" "src/golden.ts"
    git -C "$TEST_REPO" tag -a "v1.1.0" -m "v1.1.0"

    create_changelog "# Changelog

## [1.1.0] - 2026-03-25

### Added
- Golden Path commands for simplified workflow

## [1.0.0] - 2026-03-20

### Added
- Initial release
"

    run "$TEST_SCRIPT" --from 1.0.0 --to 1.1.0 --changelog "$TEST_REPO/CHANGELOG.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Golden Path"* ]]
}

@test "generate-release-summary: emoji mapping for feat" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    git -C "$TEST_REPO" tag -a "v1.0.0" -m "v1.0.0"
    make_commit_with_files "feat: add feature" "src/feature.ts"
    git -C "$TEST_REPO" tag -a "v1.1.0" -m "v1.1.0"

    create_changelog "# Changelog

## [1.1.0] - 2026-03-25

### Added
- New feature for users

## [1.0.0] - 2026-03-20

### Added
- Initial release
"

    run "$TEST_SCRIPT" --from 1.0.0 --to 1.1.0 --changelog "$TEST_REPO/CHANGELOG.md"
    [ "$status" -eq 0 ]
    # Should contain the sparkles emoji for feat
    [[ "$output" == *"✨"* ]]
}

@test "generate-release-summary: emoji mapping for fix" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    git -C "$TEST_REPO" tag -a "v1.0.0" -m "v1.0.0"
    make_commit_with_files "fix: resolve crash" "src/fix.ts"
    git -C "$TEST_REPO" tag -a "v1.0.1" -m "v1.0.1"

    create_changelog "# Changelog

## [1.0.1] - 2026-03-25

### Fixed
- Resolved crash on startup

## [1.0.0] - 2026-03-20

### Added
- Initial release
"

    run "$TEST_SCRIPT" --from 1.0.0 --to 1.0.1 --changelog "$TEST_REPO/CHANGELOG.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"🔧"* ]]
}

# =============================================================================
# Git Log Fallback Tests
# =============================================================================

@test "generate-release-summary: git log fallback when no CHANGELOG" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    git -C "$TEST_REPO" tag -a "v1.0.0" -m "v1.0.0"
    make_commit_with_files "feat: add new feature" "src/feature.ts"
    git -C "$TEST_REPO" tag -a "v1.1.0" -m "v1.1.0"

    run "$TEST_SCRIPT" --from 1.0.0 --to 1.1.0
    [ "$status" -eq 0 ]
    [[ "$output" == *"new feature"* ]]
}

# =============================================================================
# Zone Filtering Tests
# =============================================================================

@test "generate-release-summary: filters internal-only commits" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    git -C "$TEST_REPO" tag -a "v1.0.0" -m "v1.0.0"
    # Only internal changes
    make_commit_with_files "chore: update rules" ".claude/rules/test.md"
    git -C "$TEST_REPO" tag -a "v1.0.1" -m "v1.0.1"

    run "$TEST_SCRIPT" --from 1.0.0 --to 1.0.1
    # Should exit 1 (no user-facing changes) since all commits are system-only
    [ "$status" -eq 1 ]
}

@test "generate-release-summary: includes mixed commits with app zone" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    git -C "$TEST_REPO" tag -a "v1.0.0" -m "v1.0.0"
    make_commit_with_files "feat: add feature" "src/app.ts"
    make_commit_with_files "chore: update rules" ".claude/rules/test.md"
    git -C "$TEST_REPO" tag -a "v1.1.0" -m "v1.1.0"

    run "$TEST_SCRIPT" --from 1.0.0 --to 1.1.0
    [ "$status" -eq 0 ]
    [[ "$output" == *"add feature"* ]]
}

# =============================================================================
# Max Lines / Sorting Tests
# =============================================================================

@test "generate-release-summary: caps at 5 lines" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    git -C "$TEST_REPO" tag -a "v1.0.0" -m "v1.0.0"

    # Create 8 app commits
    for i in $(seq 1 8); do
        make_commit_with_files "feat: feature number $i" "src/feature-$i.ts"
    done
    git -C "$TEST_REPO" tag -a "v1.1.0" -m "v1.1.0"

    run "$TEST_SCRIPT" --from 1.0.0 --to 1.1.0
    [ "$status" -eq 0 ]
    local line_count
    line_count=$(echo "$output" | grep -c "✨" || true)
    [ "$line_count" -le 5 ]
}

# =============================================================================
# JSON Output Tests
# =============================================================================

@test "generate-release-summary: --json outputs valid JSON" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    git -C "$TEST_REPO" tag -a "v1.0.0" -m "v1.0.0"
    make_commit_with_files "feat: add feature" "src/app.ts"
    git -C "$TEST_REPO" tag -a "v1.1.0" -m "v1.1.0"

    run "$TEST_SCRIPT" --from 1.0.0 --to 1.1.0 --json
    [ "$status" -eq 0 ]
    echo "$output" | jq . > /dev/null 2>&1
}

@test "generate-release-summary: --json has required fields" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    git -C "$TEST_REPO" tag -a "v1.0.0" -m "v1.0.0"
    make_commit_with_files "feat: add feature" "src/app.ts"
    git -C "$TEST_REPO" tag -a "v1.1.0" -m "v1.1.0"

    run "$TEST_SCRIPT" --from 1.0.0 --to 1.1.0 --json
    [ "$status" -eq 0 ]

    local has_from has_to has_entries has_count
    has_from=$(echo "$output" | jq 'has("from")')
    has_to=$(echo "$output" | jq 'has("to")')
    has_entries=$(echo "$output" | jq 'has("entries")')
    has_count=$(echo "$output" | jq 'has("count")')
    [ "$has_from" = "true" ]
    [ "$has_to" = "true" ]
    [ "$has_entries" = "true" ]
    [ "$has_count" = "true" ]
}

# =============================================================================
# Empty / All-Internal Tests
# =============================================================================

@test "generate-release-summary: empty changelog section returns exit 1" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    git -C "$TEST_REPO" tag -a "v1.0.0" -m "v1.0.0"
    make_commit_with_files "chore: nothing user-facing" "grimoires/loa/data.json"
    git -C "$TEST_REPO" tag -a "v1.0.1" -m "v1.0.1"

    create_changelog "# Changelog

## [1.0.1] - 2026-03-25

## [1.0.0] - 2026-03-20

### Added
- Initial release
"

    run "$TEST_SCRIPT" --from 1.0.0 --to 1.0.1 --changelog "$TEST_REPO/CHANGELOG.md"
    # Empty section = no entries → falls back to git log → state-only filtered → exit 1
    [ "$status" -eq 1 ]
}

@test "generate-release-summary: all-internal release returns exit 1 via git log" {
    skip_if_deps_missing

    make_commit_with_files "initial" "README.md"
    git -C "$TEST_REPO" tag -a "v1.0.0" -m "v1.0.0"
    make_commit_with_files "chore: update system" ".claude/scripts/test.sh"
    make_commit_with_files "chore: update state" "grimoires/loa/notes.md"
    git -C "$TEST_REPO" tag -a "v1.0.1" -m "v1.0.1"

    run "$TEST_SCRIPT" --from 1.0.0 --to 1.0.1
    [ "$status" -eq 1 ]
}
