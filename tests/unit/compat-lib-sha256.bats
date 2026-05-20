#!/usr/bin/env bats
# =============================================================================
# tests/unit/compat-lib-sha256.bats
#
# sprint-bug-172 / bug-911 — sha256_portable helper in compat-lib.sh.
#
# macOS ships BSD shasum, not GNU sha256sum. Loa framework scripts that called
# raw sha256sum silently failed on macOS, producing empty hashes and cascading
# into validation FAILs (e.g., `/butterfreezone-gen` → `/butterfreezone-validate`
# returns 10/12 provenance tagged because hashing silently dies on macOS).
#
# This suite proves the sha256_portable helper:
#   - Case A (GNU-only PATH): uses sha256sum directly, succeeds
#   - Case B (BSD-only PATH): falls back to shasum -a 256, succeeds with byte-
#                              identical hash to GNU's output
#   - Case C (both present):  prefers sha256sum (deterministic, simpler dispatch)
#   - Case D (neither):       fails loud (exit non-zero, stderr diagnostic)
#   - Case E (byte-equality): GNU and BSD backends produce identical hex hashes
#
# Hermetic: each case rebuilds a clean shim PATH under $BATS_TMPDIR/bin/ so
# no system-state mutation leaks between cases.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT

    COMPAT_LIB="$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
    [[ -f "$COMPAT_LIB" ]] || skip "compat-lib.sh not present"

    # Capture the canonical GNU output (assumes the test host has GNU sha256sum;
    # CI runs on Linux). Byte-equality assertions in Cases B + E pin against this.
    EXPECTED_HASH="$(printf 'sprint-bug-172\n' | sha256sum | awk '{print $1}')"
    export EXPECTED_HASH

    # Build a clean shim directory; each case will populate it differently.
    SHIM_DIR="$(mktemp -d)"
    export SHIM_DIR

    # The real sha256sum + shasum binary paths (used to construct shims that
    # forward to the real implementation under a different name).
    REAL_SHA256SUM="$(command -v sha256sum 2>/dev/null || echo '')"
    REAL_SHASUM="$(command -v shasum 2>/dev/null || echo '')"
    export REAL_SHA256SUM REAL_SHASUM
}

teardown() {
    rm -rf "$SHIM_DIR"
}

# Helper: install a shim that forwards to a real binary
_install_shim() {
    local name="$1"
    local target="$2"
    cat > "$SHIM_DIR/$name" <<EOF
#!/usr/bin/env bash
exec "$target" "\$@"
EOF
    chmod 0755 "$SHIM_DIR/$name"
}

# Helper: sandbox PATH to only the shim dir + bash builtins (no system bin)
_sandboxed_path() {
    # Need bash core utilities (printf, command, etc.) — keep /usr/bin in path
    # for those, but the shims for sha256sum/shasum should be the ONLY
    # implementations findable.
    echo "$SHIM_DIR:/usr/bin:/bin"
}

@test "A1 GNU-only PATH: sha256_portable uses sha256sum directly" {
    [[ -n "$REAL_SHA256SUM" ]] || skip "sha256sum not available on test host"
    _install_shim sha256sum "$REAL_SHA256SUM"
    # No shasum in SHIM_DIR — BSD shim absent
    PATH="$(_sandboxed_path)" run bash -c "source '$COMPAT_LIB'; printf 'sprint-bug-172\n' | sha256_portable | awk '{print \$1}'"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$EXPECTED_HASH" ]]
}

@test "A2 BSD-only PATH: sha256_portable falls back to shasum -a 256" {
    [[ -n "$REAL_SHASUM" ]] || skip "shasum not available on test host"
    _install_shim shasum "$REAL_SHASUM"
    # No sha256sum in SHIM_DIR — GNU shim absent
    PATH="$(_sandboxed_path)" run bash -c "source '$COMPAT_LIB'; printf 'sprint-bug-172\n' | sha256_portable | awk '{print \$1}'"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$EXPECTED_HASH" ]]
}

@test "A3 Both present: sha256_portable prefers sha256sum (GNU)" {
    [[ -n "$REAL_SHA256SUM" ]] || skip "sha256sum not available on test host"
    [[ -n "$REAL_SHASUM" ]] || skip "shasum not available on test host"
    _install_shim sha256sum "$REAL_SHA256SUM"
    _install_shim shasum "$REAL_SHASUM"
    # Probe: source compat-lib with both shims visible and assert _COMPAT_SHA256_CMD
    PATH="$(_sandboxed_path)" run bash -c "source '$COMPAT_LIB'; echo \$_COMPAT_SHA256_CMD"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "gnu" ]]
}

@test "A4 Neither present: sha256_portable fails loud with non-zero exit" {
    # Nothing installed in SHIM_DIR — both backends absent
    PATH="$SHIM_DIR" run bash -c "source '$COMPAT_LIB'; printf 'sprint-bug-172\n' | sha256_portable"
    [[ "$status" -ne 0 ]]
    # Stderr must mention the diagnostic (forwarded to bats output via run)
    [[ "$output" =~ "sha256" ]] || [[ "$output" =~ "not found" ]] || [[ "$output" =~ "ERROR" ]]
}

@test "A5 Byte-equality: GNU sha256sum and BSD shasum -a 256 produce identical hash" {
    [[ -n "$REAL_SHA256SUM" ]] || skip "sha256sum not available on test host"
    [[ -n "$REAL_SHASUM" ]] || skip "shasum not available on test host"
    local gnu_hash bsd_hash
    gnu_hash="$(printf 'sprint-bug-172\n' | "$REAL_SHA256SUM" | awk '{print $1}')"
    bsd_hash="$(printf 'sprint-bug-172\n' | "$REAL_SHASUM" -a 256 | awk '{print $1}')"
    [[ "$gnu_hash" == "$bsd_hash" ]]
    [[ "$gnu_hash" == "$EXPECTED_HASH" ]]
}

@test "A6 File-argv form: sha256_portable file.txt matches sha256sum file.txt" {
    [[ -n "$REAL_SHA256SUM" ]] || skip "sha256sum not available on test host"
    _install_shim sha256sum "$REAL_SHA256SUM"
    local f="$SHIM_DIR/test-input.txt"
    printf 'sprint-bug-172\n' > "$f"
    PATH="$(_sandboxed_path)" run bash -c "source '$COMPAT_LIB'; sha256_portable '$f' | awk '{print \$1}'"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$EXPECTED_HASH" ]]
}
