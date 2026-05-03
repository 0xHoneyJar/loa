#!/usr/bin/env bats
# =============================================================================
# Unit tests for post-pr-e2e.sh bats support — issue #633
#
# sprint-bug-140 (TIER 1 batch). Pre-fix: post-pr-e2e.sh's detect_test_command
# probes for npm/Makefile/Cargo/Go/pytest project markers but not bats. Bash
# repos (including loa itself) had no auto-detected test command and even
# explicit `TEST_CMD="bats tests/unit/"` was rejected by validate_command's
# allowlist. Result: orchestrator iterated 3× and HALTed with `e2e_max_iterations`.
#
# Post-fix:
# - detect_test_command probes for tests/unit/*.bats (after project-specific
#   markers so they take priority)
# - validate_command allowlist includes "bats "
# =============================================================================

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT_REAL="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT_REAL/.claude/scripts/post-pr-e2e.sh"

    [[ -f "$SCRIPT" ]] || skip "post-pr-e2e.sh not found"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/post-pr-e2e-bats-$$"
    mkdir -p "$TEST_TMPDIR"
}

teardown() {
    cd /
    [[ -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# Helper: source post-pr-e2e.sh's pure functions in a subshell. Avoids the
# script's main() execution by using a bash -c subshell with explicit function
# extraction.
_source_e2e_funcs() {
    # The script auto-runs only when invoked, not sourced — but it requires
    # compat-lib.sh + state-script. For unit tests we extract just the function
    # bodies we need.
    bash -c '
        cd "'"$1"'"
        TEST_CMD="${TEST_CMD:-}"
        unset PR_URL PR_BRANCH GH_TOKEN  # avoid argument validation
        # Extract validate_command + detect_test_command bodies via awk.
        eval "$(awk '\''/^validate_command\(\) \{/,/^\}$/'\'' "'"$SCRIPT_REAL"'")"
        eval "$(awk '\''/^detect_test_command\(\) \{/,/^\}$/'\'' "'"$SCRIPT_REAL"'")"
        # log_error is referenced by validate_command. Stub it.
        log_error() { echo "[ERR] $*" >&2; }
        '"$2"'
    '
}

# -----------------------------------------------------------------------------
# Scenario 2.a: detect_test_command finds bats in tests/unit/
# -----------------------------------------------------------------------------
@test "post-pr-e2e: detect_test_command finds bats tests" {
    local workdir="$TEST_TMPDIR/bats-only"
    mkdir -p "$workdir/tests/unit"
    echo "@test 'foo' { :; }" > "$workdir/tests/unit/foo.bats"

    SCRIPT_REAL="$SCRIPT" run _source_e2e_funcs "$workdir" "detect_test_command"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"bats tests/unit/"* ]] || {
        echo "Expected 'bats tests/unit/' detection; got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Scenario 2.b: detect_test_command on dir with no bats files → empty output
# -----------------------------------------------------------------------------
@test "post-pr-e2e: detect_test_command returns empty when no project markers" {
    local workdir="$TEST_TMPDIR/empty"
    mkdir -p "$workdir"
    echo "junk" > "$workdir/foo.txt"

    SCRIPT_REAL="$SCRIPT" run _source_e2e_funcs "$workdir" "detect_test_command"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]] || {
        echo "Expected empty output; got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Scenario 2.c: validate_command accepts "bats tests/unit/"
# -----------------------------------------------------------------------------
@test "post-pr-e2e: validate_command accepts 'bats tests/unit/'" {
    SCRIPT_REAL="$SCRIPT" run _source_e2e_funcs "$TEST_TMPDIR" "validate_command 'bats tests/unit/'"
    [[ "$status" -eq 0 ]] || {
        echo "Expected exit 0; got $status, output: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Scenario 2.d: validate_command rejects truly-malicious commands (e.g. rm -rf /)
# -----------------------------------------------------------------------------
@test "post-pr-e2e: validate_command rejects 'rm -rf /'" {
    SCRIPT_REAL="$SCRIPT" run _source_e2e_funcs "$TEST_TMPDIR" "validate_command 'rm -rf /'"
    [[ "$status" -ne 0 ]] || {
        echo "Expected non-zero exit; got $status"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Scenario 2.e: project-specific markers take priority over bats probe
# -----------------------------------------------------------------------------
@test "post-pr-e2e: project markers take priority over bats probe" {
    local workdir="$TEST_TMPDIR/multi"
    mkdir -p "$workdir/tests/unit"
    echo "@test 'foo' { :; }" > "$workdir/tests/unit/foo.bats"
    # Add a Cargo.toml — should win over bats since project-specific markers come first.
    cat > "$workdir/Cargo.toml" <<'TOML'
[package]
name = "test"
version = "0.1.0"
TOML

    SCRIPT_REAL="$SCRIPT" run _source_e2e_funcs "$workdir" "detect_test_command"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"cargo test"* ]] || {
        echo "Expected 'cargo test' (project marker priority); got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Scenario 2.f: detect_test_command also finds bats in tests/integration/
# -----------------------------------------------------------------------------
@test "post-pr-e2e: detect_test_command finds bats in tests/integration/" {
    local workdir="$TEST_TMPDIR/integration-only"
    mkdir -p "$workdir/tests/integration"
    echo "@test 'foo' { :; }" > "$workdir/tests/integration/foo.bats"

    SCRIPT_REAL="$SCRIPT" run _source_e2e_funcs "$workdir" "detect_test_command"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"bats"* ]]
}
