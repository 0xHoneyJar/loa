#!/usr/bin/env bats
# Unit tests for semver-bump.sh
# Sprint 1 cycle-007: Conventional commit semver parser

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/semver-bump.sh"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/semver-bump-test-$$"
    mkdir -p "$TEST_TMPDIR"

    # Create isolated git repo for testing
    export TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/.claude/scripts"
    git -C "$TEST_REPO" init --quiet
    git -C "$TEST_REPO" config user.email "test@test.com"
    git -C "$TEST_REPO" config user.name "Test"

    # Copy bootstrap and the script to test repo so bootstrap detects test repo as root
    cp "$PROJECT_ROOT/.claude/scripts/bootstrap.sh" "$TEST_REPO/.claude/scripts/"
    if [[ -f "$PROJECT_ROOT/.claude/scripts/path-lib.sh" ]]; then
        cp "$PROJECT_ROOT/.claude/scripts/path-lib.sh" "$TEST_REPO/.claude/scripts/"
    fi
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

# Helper: create a commit with a message
make_commit() {
    local msg="$1"
    local file="${2:-file-$RANDOM.txt}"
    echo "$msg" > "$TEST_REPO/$file"
    git -C "$TEST_REPO" add "$file"
    git -C "$TEST_REPO" commit -m "$msg" --quiet
}

# Helper: create a version tag
make_tag() {
    local version="$1"
    git -C "$TEST_REPO" tag -a "v${version}" -m "Release v${version}"
}

# =============================================================================
# Basic Tests
# =============================================================================

@test "semver-bump: script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "semver-bump: shows help with --help" {
    run "$TEST_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"semver-bump.sh"* ]]
}

@test "semver-bump: rejects unknown arguments" {
    run "$TEST_SCRIPT" --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown argument"* ]]
}

# =============================================================================
# Version Source Tests
# =============================================================================

@test "semver-bump: reads version from git tag" {
    skip_if_deps_missing

    make_commit "initial commit"
    make_tag "1.0.0"
    make_commit "feat: add feature"

    run "$TEST_SCRIPT" --from-tag
    [ "$status" -eq 0 ]
    local current
    current=$(echo "$output" | jq -r '.current')
    [ "$current" = "1.0.0" ]
}

@test "semver-bump: reads version from CHANGELOG fallback" {
    skip_if_deps_missing

    # Create CHANGELOG with version
    cat > "$TEST_REPO/CHANGELOG.md" <<'EOF'
# Changelog

## [2.5.0] - 2026-01-15

### Added
- Something new
EOF
    make_commit "initial with changelog"
    make_tag "2.5.0"
    make_commit "fix: patch something"

    run "$TEST_SCRIPT" --from-changelog
    [ "$status" -eq 0 ]
    local current
    current=$(echo "$output" | jq -r '.current')
    [ "$current" = "2.5.0" ]
}

@test "semver-bump: auto mode tries tag first" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "3.1.0"
    make_commit "fix: something"

    run "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    local current
    current=$(echo "$output" | jq -r '.current')
    [ "$current" = "3.1.0" ]
}

@test "semver-bump: errors when no version source found" {
    skip_if_deps_missing

    make_commit "initial commit"

    run "$TEST_SCRIPT"
    [ "$status" -ne 0 ]
}

@test "semver-bump: errors when no commits since tag" {
    skip_if_deps_missing

    make_commit "initial commit"
    make_tag "1.0.0"

    run "$TEST_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No commits since"* ]]
}

# =============================================================================
# Bump Type Tests
# =============================================================================

@test "semver-bump: feat commit → minor bump" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "1.0.0"
    make_commit "feat: add new feature"

    run "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    local bump next
    bump=$(echo "$output" | jq -r '.bump')
    next=$(echo "$output" | jq -r '.next')
    [ "$bump" = "minor" ]
    [ "$next" = "1.1.0" ]
}

@test "semver-bump: fix commit → patch bump" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "1.0.0"
    make_commit "fix: resolve bug"

    run "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    local bump next
    bump=$(echo "$output" | jq -r '.bump')
    next=$(echo "$output" | jq -r '.next')
    [ "$bump" = "patch" ]
    [ "$next" = "1.0.1" ]
}

@test "semver-bump: chore commit → patch bump" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "2.3.1"
    make_commit "chore: update deps"

    run "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    local bump next
    bump=$(echo "$output" | jq -r '.bump')
    next=$(echo "$output" | jq -r '.next')
    [ "$bump" = "patch" ]
    [ "$next" = "2.3.2" ]
}

@test "semver-bump: BREAKING CHANGE in body → major bump" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "1.5.0"

    # Create commit with breaking change in body
    echo "break" > "$TEST_REPO/breaking.txt"
    git -C "$TEST_REPO" add breaking.txt
    git -C "$TEST_REPO" commit -m "feat: redesign API" -m "BREAKING CHANGE: removed v1 endpoints" --quiet

    run "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    local bump next
    bump=$(echo "$output" | jq -r '.bump')
    next=$(echo "$output" | jq -r '.next')
    [ "$bump" = "major" ]
    [ "$next" = "2.0.0" ]
}

@test "semver-bump: bang suffix (feat!) → major bump" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "1.0.0"
    make_commit "feat!: completely new API"

    run "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    local bump
    bump=$(echo "$output" | jq -r '.bump')
    [ "$bump" = "major" ]
}

@test "semver-bump: scoped bang suffix (feat(api)!) → major bump" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "1.0.0"
    make_commit "feat(api)!: breaking change"

    run "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    local bump
    bump=$(echo "$output" | jq -r '.bump')
    [ "$bump" = "major" ]
}

@test "semver-bump: mixed commits — highest bump wins (feat > fix → minor)" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "1.0.0"
    make_commit "fix: patch first"
    make_commit "feat: then feature"
    make_commit "chore: cleanup"

    run "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    local bump
    bump=$(echo "$output" | jq -r '.bump')
    [ "$bump" = "minor" ]
}

@test "semver-bump: multiple fix commits → single patch bump" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "1.2.3"
    make_commit "fix: bug one"
    make_commit "fix: bug two"
    make_commit "fix: bug three"

    run "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    local next
    next=$(echo "$output" | jq -r '.next')
    [ "$next" = "1.2.4" ]
}

# =============================================================================
# JSON Output Tests
# =============================================================================

@test "semver-bump: output is valid JSON" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "1.0.0"
    make_commit "fix: something"

    run "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | jq . > /dev/null 2>&1
}

@test "semver-bump: JSON has required fields" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "1.0.0"
    make_commit "feat: add thing"

    run "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    local has_current has_next has_bump has_commits
    has_current=$(echo "$output" | jq 'has("current")')
    has_next=$(echo "$output" | jq 'has("next")')
    has_bump=$(echo "$output" | jq 'has("bump")')
    has_commits=$(echo "$output" | jq 'has("commits")')
    [ "$has_current" = "true" ]
    [ "$has_next" = "true" ]
    [ "$has_bump" = "true" ]
    [ "$has_commits" = "true" ]
}

@test "semver-bump: commits array contains parsed commits" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "1.0.0"
    make_commit "feat: feature one"
    make_commit "fix: bug fix"

    run "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    local count
    count=$(echo "$output" | jq '.commits | length')
    [ "$count" -eq 2 ]
}

@test "semver-bump: commit entries have type field" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "1.0.0"
    make_commit "feat(auth): add login"

    run "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    local type scope
    type=$(echo "$output" | jq -r '.commits[0].type')
    scope=$(echo "$output" | jq -r '.commits[0].scope')
    [ "$type" = "feat" ]
    [ "$scope" = "auth" ]
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "semver-bump: non-conventional commit gets patch bump" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "1.0.0"
    make_commit "just a random commit message"

    run "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    local bump
    bump=$(echo "$output" | jq -r '.bump')
    [ "$bump" = "patch" ]
}

@test "semver-bump: picks latest tag from multiple tags" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "1.0.0"
    make_commit "feat: v1.1"
    make_tag "1.1.0"
    make_commit "feat: v1.2"
    make_tag "1.2.0"
    make_commit "fix: latest fix"

    run "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    local current
    current=$(echo "$output" | jq -r '.current')
    [ "$current" = "1.2.0" ]
}

# =============================================================================
# Prerelease Tag Tests (alpha/beta/rc)
# =============================================================================
#
# Pre-1.0 projects (or major-version cadences shipping through prereleases)
# tag with `vX.Y.Z-alpha.N` / `vX.Y.Z-beta.N` / `vX.Y.Z-rc.N`. The
# release-only glob in get_version_from_tag() previously skipped these,
# silently breaking downstream post-merge automation (no current version
# resolved → empty next → semver phase exit 0 with empty result → tag/
# CHANGELOG/release phases skipped). These tests pin the prerelease path.

@test "semver-bump: detects prerelease tag (alpha)" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "2.0.0-alpha.7"
    make_commit "feat: post-alpha-7 work"

    run "$TEST_SCRIPT" --from-tag
    [ "$status" -eq 0 ]
    local current
    current=$(echo "$output" | jq -r '.current')
    [ "$current" = "2.0.0-alpha.7" ]
}

@test "semver-bump: detects prerelease tag (beta)" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "1.5.0-beta.2"
    make_commit "fix: post-beta-2 work"

    run "$TEST_SCRIPT" --from-tag
    [ "$status" -eq 0 ]
    local current
    current=$(echo "$output" | jq -r '.current')
    [ "$current" = "1.5.0-beta.2" ]
}

@test "semver-bump: detects prerelease tag (rc)" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "3.0.0-rc.1"
    make_commit "feat: post-rc-1 work"

    run "$TEST_SCRIPT" --from-tag
    [ "$status" -eq 0 ]
    local current
    current=$(echo "$output" | jq -r '.current')
    [ "$current" = "3.0.0-rc.1" ]
}

@test "semver-bump: prerelease bump increments prerelease number on feat commit" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "2.0.0-alpha.7"
    make_commit "feat: add new feature during alpha"

    run "$TEST_SCRIPT" --from-tag
    [ "$status" -eq 0 ]
    local next
    next=$(echo "$output" | jq -r '.next')
    [ "$next" = "2.0.0-alpha.8" ]
}

@test "semver-bump: prerelease bump increments prerelease number on fix commit" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "2.0.0-alpha.7"
    make_commit "fix: patch something during alpha"

    run "$TEST_SCRIPT" --from-tag
    [ "$status" -eq 0 ]
    local next
    next=$(echo "$output" | jq -r '.next')
    [ "$next" = "2.0.0-alpha.8" ]
}

@test "semver-bump: prerelease bump is type-agnostic — major commit also increments prerelease N" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "2.0.0-alpha.7"
    make_commit "feat!: breaking change during alpha"

    run "$TEST_SCRIPT" --from-tag
    [ "$status" -eq 0 ]
    local next
    next=$(echo "$output" | jq -r '.next')
    # While on prerelease, conventional-commit type does not warrant
    # major/minor/patch flip — project is still pre-1.0-of-this-major.
    # Promotion (alpha → beta, rc → release) is operator-driven.
    [ "$next" = "2.0.0-alpha.8" ]
}

@test "semver-bump: prerelease bump for beta increments beta number" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "1.5.0-beta.9"
    make_commit "fix: post-beta-9"

    run "$TEST_SCRIPT" --from-tag
    [ "$status" -eq 0 ]
    local next
    next=$(echo "$output" | jq -r '.next')
    [ "$next" = "1.5.0-beta.10" ]
}

@test "semver-bump: prerelease bump for rc increments rc number" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "3.0.0-rc.1"
    make_commit "fix: post-rc-1"

    run "$TEST_SCRIPT" --from-tag
    [ "$status" -eq 0 ]
    local next
    next=$(echo "$output" | jq -r '.next')
    [ "$next" = "3.0.0-rc.2" ]
}

@test "semver-bump: release bump still works for plain X.Y.Z (no regression)" {
    skip_if_deps_missing

    # Defense regression: VULN-002-style fix should not break release-only
    # path. This test re-runs the canonical "feat → minor bump" case to
    # confirm the bump_version() refactor is additive.
    make_commit "initial"
    make_tag "1.0.0"
    make_commit "feat: minor bump"

    run "$TEST_SCRIPT" --from-tag
    [ "$status" -eq 0 ]
    local next
    next=$(echo "$output" | jq -r '.next')
    [ "$next" = "1.1.0" ]
}

@test "semver-bump: malformed prerelease tag (missing .N suffix) rejected by version regex" {
    skip_if_deps_missing

    # The grep regex in get_version_from_tag() requires the prerelease
    # to have an explicit numeric suffix. A bare `v1.0.0-alpha` (no .N)
    # is matched neither by the strict regex nor by the prerelease regex,
    # so get_version_from_tag returns 1 (no version source) — the script
    # falls back to changelog or fails cleanly.
    make_commit "initial"
    git -C "$TEST_REPO" tag -a "v1.0.0-alpha" -m "malformed prerelease"
    make_commit "feat: post-malformed"

    run "$TEST_SCRIPT" --from-tag
    # Either exit 2 (no version source) OR fall back to changelog (which
    # is also empty in this fixture, also exit 2). Behavior must NOT
    # silently accept the malformed tag and produce empty/garbage next.
    [ "$status" -ne 0 ]
}

@test "semver-bump: picks latest version-sorted prerelease across alpha.N range" {
    skip_if_deps_missing

    make_commit "initial"
    make_tag "2.0.0-alpha.1"
    make_commit "c2"
    make_tag "2.0.0-alpha.2"
    make_commit "c3"
    make_tag "2.0.0-alpha.10"
    make_commit "feat: post-alpha-10"

    run "$TEST_SCRIPT" --from-tag
    [ "$status" -eq 0 ]
    local current
    current=$(echo "$output" | jq -r '.current')
    # Version-aware sort: alpha.10 > alpha.2 > alpha.1 (NOT lexicographic).
    [ "$current" = "2.0.0-alpha.10" ]
}

@test "semver-bump: picks latest tag when release and prerelease coexist" {
    skip_if_deps_missing

    # Mixed history: project shipped v1.x stable, then started v2 prerelease
    # cadence. The post-merge orchestrator should pick the latest tag by
    # version sort regardless of prerelease vs release shape.
    make_commit "initial"
    make_tag "1.5.0"
    make_commit "c2"
    make_tag "2.0.0-alpha.1"
    make_commit "c3"
    make_tag "2.0.0-alpha.5"
    make_commit "feat: post-alpha-5"

    run "$TEST_SCRIPT" --from-tag
    [ "$status" -eq 0 ]
    local current
    current=$(echo "$output" | jq -r '.current')
    [ "$current" = "2.0.0-alpha.5" ]
}
