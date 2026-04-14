#!/usr/bin/env bats
# Tests for --version flag on vision-lifecycle.sh
# Sprint 1 — cycle bench-sonnet-v2
# Traces: PRD AC-1..AC-3, SDD 2.1-2.3, Flatline FL-1..FL-3, F1, F2, F4

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/vision-lifecycle.sh"
}

# ---------------------------------------------------------------------------
# Test 1: --version prints correct format
# Traces: PRD AC-1, AC-3, G3
# ---------------------------------------------------------------------------
@test "--version prints correct format" {
    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
    [ "$output" = "vision-lifecycle.sh 1.0.0" ]
}

# ---------------------------------------------------------------------------
# Test 2: --version exits with code 0
# Traces: PRD AC-2
# ---------------------------------------------------------------------------
@test "--version exits 0" {
    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Test 3: --version works without other arguments (no usage/error output)
# Traces: PRD AC-3
# ---------------------------------------------------------------------------
@test "--version works without other arguments" {
    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
    # Must not print usage or error messages
    [[ "$output" != *"Usage:"* ]]
    [[ "$output" != *"ERROR"* ]]
}

# ---------------------------------------------------------------------------
# Test 4: --version ignores trailing args
# Traces: SDD 2.2, Flatline F1
# ---------------------------------------------------------------------------
@test "--version ignores trailing args" {
    run "$SCRIPT" --version promote V001
    [ "$status" -eq 0 ]
    [ "$output" = "vision-lifecycle.sh 1.0.0" ]
}

# ---------------------------------------------------------------------------
# Test 5: --version does not source dependencies (FL-3 resolution)
# Uses temp-dir-copy approach with poisoned bootstrap.sh + vision-lib.sh.
# SCRIPT_DIR resolves to the temp dir, so if --version sources anything it
# will hit the poisoned scripts and exit 99 instead of 0.
# Traces: PRD FR-1.3, SDD 2.3, FL-3
# ---------------------------------------------------------------------------
@test "--version does not source dependencies" {
    local tmpdir
    tmpdir="$(mktemp -d)"

    # Copy the real script into tmpdir
    cp "$SCRIPT" "$tmpdir/vision-lifecycle.sh"
    chmod +x "$tmpdir/vision-lifecycle.sh"

    # Poisoned deps: if sourced, the script exits 99
    printf '#!/usr/bin/env bash\nexit 99\n' > "$tmpdir/bootstrap.sh"
    printf '#!/usr/bin/env bash\nexit 99\n' > "$tmpdir/vision-lib.sh"

    run "$tmpdir/vision-lifecycle.sh" --version

    rm -rf "$tmpdir"

    [ "$status" -eq 0 ]
    [ "$output" = "vision-lifecycle.sh 1.0.0" ]
}

# ---------------------------------------------------------------------------
# Test 6: --version outputs only to stdout; stderr is empty
# Traces: FL-2
# ---------------------------------------------------------------------------
@test "--version outputs only to stdout, stderr is empty" {
    # Capture stdout and stderr separately
    local stdout_file stderr_file
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"

    "$SCRIPT" --version >"$stdout_file" 2>"$stderr_file"
    local exit_code=$?

    local stdout_content stderr_content
    stdout_content="$(cat "$stdout_file")"
    stderr_content="$(cat "$stderr_file")"

    rm -f "$stdout_file" "$stderr_file"

    [ "$exit_code" -eq 0 ]
    [ -n "$stdout_content" ]
    [ -z "$stderr_content" ]
}

# ---------------------------------------------------------------------------
# Test 7: VERSION variable in script source matches --version output
# Guards against single-source-of-truth drift (reads from source, not hardcoded).
# Traces: SDD 2.1, Flatline F4, FL-1
# ---------------------------------------------------------------------------
@test "VERSION variable matches --version output" {
    # Extract version from script source (single source of truth)
    local source_version
    source_version="$(grep '^VERSION=' "$SCRIPT" | head -1 | sed 's/VERSION="\(.*\)"/\1/')"

    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
    [ "$output" = "vision-lifecycle.sh $source_version" ]
}

# ---------------------------------------------------------------------------
# Test 8: --version at non-$1 position is NOT recognized
# e.g. "promote --version V001" should fall through to subcommand handling,
# not print the version banner.
# Traces: SDD 2.2, Flatline F2
# ---------------------------------------------------------------------------
@test "--version not recognized at non-\$1 position" {
    # "promote --version V001" — $1 is "promote", not "--version"
    # Should NOT print version format; will fail on missing deps/env but that's fine
    run "$SCRIPT" promote --version V001 2>/dev/null || true
    [[ "$output" != "vision-lifecycle.sh 1.0.0" ]]
}
