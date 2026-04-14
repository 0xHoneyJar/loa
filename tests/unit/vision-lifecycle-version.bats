#!/usr/bin/env bats
# Unit tests for vision-lifecycle.sh --version flag
# Sprint: Add --version Flag to vision-lifecycle.sh
# Tests: PRD AC-1..AC-3, SDD 2.1/2.2/2.3, Flatline FL-1..FL-3

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/vision-lifecycle.sh"
}

# =============================================================================
# Test 1: --version prints correct format (PRD AC-1, AC-3, G3)
# =============================================================================

@test "version: --version prints correct format" {
    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
    [ "$output" = "vision-lifecycle.sh 1.0.0" ]
}

# =============================================================================
# Test 2: --version exits 0 (PRD AC-2)
# =============================================================================

@test "version: --version exits 0" {
    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
}

# =============================================================================
# Test 3: --version works without other arguments (PRD AC-3)
# =============================================================================

@test "version: --version works without other arguments" {
    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
    # No usage message printed
    [[ "$output" != *"Usage:"* ]]
}

# =============================================================================
# Test 4: --version ignores trailing args (SDD 2.2, Flatline F1)
# =============================================================================

@test "version: --version ignores trailing args" {
    run "$SCRIPT" --version promote V001
    [ "$status" -eq 0 ]
    [ "$output" = "vision-lifecycle.sh 1.0.0" ]
}

# =============================================================================
# Test 5: --version does not source dependencies (PRD FR-1.3, SDD 2.3, FL-3)
# Copy script to temp dir with poisoned deps that exit 99.
# =============================================================================

@test "version: --version does not source dependencies" {
    local tmpdir
    tmpdir="$(mktemp -d)"

    # Copy the script to a temp directory
    cp "$SCRIPT" "$tmpdir/vision-lifecycle.sh"
    chmod +x "$tmpdir/vision-lifecycle.sh"

    # Create poisoned dependencies that exit 99 if sourced
    printf '#!/usr/bin/env bash\nexit 99\n' > "$tmpdir/bootstrap.sh"
    printf '#!/usr/bin/env bash\nexit 99\n' > "$tmpdir/vision-lib.sh"

    # --version must exit 0 before sourcing the poisoned deps
    run "$tmpdir/vision-lifecycle.sh" --version
    [ "$status" -eq 0 ]
    [ "$output" = "vision-lifecycle.sh 1.0.0" ]

    rm -rf "$tmpdir"
}

# =============================================================================
# Test 6: --version outputs only to stdout, stderr is empty (FL-2)
# =============================================================================

@test "version: --version outputs only to stdout" {
    local tmpdir
    tmpdir="$(mktemp -d)"

    "$SCRIPT" --version >"$tmpdir/stdout" 2>"$tmpdir/stderr"
    local exit_code=$?

    [ "$exit_code" -eq 0 ]
    # stdout has content
    [ -s "$tmpdir/stdout" ]
    # stderr is empty
    [ ! -s "$tmpdir/stderr" ]

    rm -rf "$tmpdir"
}

# =============================================================================
# Test 7: VERSION variable matches output (SDD 2.1, Flatline F4, FL-1)
# Read VERSION= from script source, compare to --version output.
# =============================================================================

@test "version: VERSION variable matches output" {
    # Extract version from source (single source of truth)
    local src_version
    src_version=$(grep '^VERSION=' "$SCRIPT" | head -1 | sed 's/^VERSION="//;s/"$//')
    [ -n "$src_version" ]

    # Get runtime output
    local runtime_output
    runtime_output=$("$SCRIPT" --version)

    [ "$runtime_output" = "vision-lifecycle.sh $src_version" ]
}

# =============================================================================
# Test 8: --version not recognized at non-$1 position (SDD 2.2, Flatline F2)
# =============================================================================

@test "version: --version not recognized at non-\$1 position" {
    # When --version is at $2+ position, it should NOT print version.
    # 'promote --version' should fall through to subcommand handling (will fail
    # because --version is not a valid vision ID, but the point is it does NOT
    # print the version string).
    run "$SCRIPT" promote --version
    [ "$status" -ne 0 ]
    [[ "$output" != "vision-lifecycle.sh 1.0.0" ]]
}
