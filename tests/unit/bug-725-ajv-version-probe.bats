#!/usr/bin/env bats
# =============================================================================
# tests/unit/bug-725-ajv-version-probe.bats
#
# Bug #725 — loa-doctor.sh captured ajv-cli@5+ usage-error stderr text
# as if it were the version, displaying garbage in the optional-tools
# section. Fix: try `ajv --version` first; if exit non-zero or output
# doesn't look like a version, fall back to `--help` parse; final
# fallback is a labeled placeholder.
#
# Tests use hermetic stub-bin fixtures on PATH to exercise:
#   - v4 path (--version returns "5.0.0\n", exit 0)
#   - v5 path (--version returns usage error, exit 1; --help has "version 5.6.0")
#   - v5 path WITHOUT --help version line (placeholder fallback)
#   - missing tool (positive control)
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT

    TEST_TMP="$(mktemp -d "${BATS_TMPDIR}/bug-725.XXXXXX")"
    export TEST_TMP

    STUB_BIN="$TEST_TMP/bin"
    mkdir -p "$STUB_BIN"
}

teardown() {
    rm -rf "$TEST_TMP"
}

# Helper: extract the production `_loa_probe_ajv_version` function from
# loa-doctor.sh and exercise it under a stubbed PATH. BB #916 F-001
# closure — tests now hit the real code path, not a hand-written replica.
# F1 closure — the harness enables `set -e` + `set -o pipefail` so the
# pipefail-guard in the production function is verified end-to-end.
_run_probe() {
    local stub_path="$STUB_BIN"
    PATH="$stub_path:/usr/bin:/bin" bash -c "
        set -eo pipefail
        # Extract just _loa_probe_ajv_version() from the production
        # script via awk (same pattern as bug-899 in-place extraction).
        # Avoids running loa-doctor.sh's main() side effects.
        eval \"\$(awk '/^_loa_probe_ajv_version\\(\\)/,/^}/' '$PROJECT_ROOT/.claude/scripts/loa-doctor.sh')\"
        if command -v ajv >/dev/null 2>&1; then
            ajv_ver=\$(_loa_probe_ajv_version)
            echo \"ajv_ver=\$ajv_ver\"
        else
            echo \"ajv_ver=not-installed\"
        fi
    "
}

@test "bug-725-1: v4 ajv (working --version flag) — probe surfaces the version" {
    # BB #916 F-002 fix: v4-era version string (was 5.6.0 — looked like v5).
    cat > "$STUB_BIN/ajv" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    --version) echo "4.2.0"; exit 0 ;;
    *)         echo "v4 stub: unhandled $*" >&2; exit 0 ;;
esac
STUB
    chmod +x "$STUB_BIN/ajv"
    run _run_probe
    [ "$status" -eq 0 ]
    [[ "$output" == *"ajv_ver=4.2.0"* ]]
}

@test "bug-725-2: v5+ ajv (--version errors, --help has version) — probe falls back to --help parse" {
    cat > "$STUB_BIN/ajv" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    --version)
        # Mimic ajv-cli@5+ shape: writes usage errors to stderr, exits 1
        echo "error: parameter -s is required" >&2
        echo "error: parameter -d is required" >&2
        echo "error: parameter --version is unknown" >&2
        exit 1
        ;;
    --help)
        cat <<'HELP'
Usage: ajv <command> [options]

ajv-cli version 5.6.0

Commands:
  ajv validate  Validate data file(s) against a schema
HELP
        exit 0
        ;;
    *)
        echo "v5 stub: unhandled $*" >&2; exit 1 ;;
esac
STUB
    chmod +x "$STUB_BIN/ajv"
    run _run_probe
    [ "$status" -eq 0 ]
    [[ "$output" == *"ajv_ver=5.6.0"* ]]
    # Must NOT contain the usage-error text.
    [[ "$output" != *"error: parameter"* ]]
    [[ "$output" != *"is required"* ]]
}

@test "bug-725-3: v5+ ajv WITHOUT --help version line — probe falls to labeled placeholder" {
    cat > "$STUB_BIN/ajv" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    --version)
        echo "error: --version unknown" >&2
        exit 1
        ;;
    --help)
        # No "version X.Y.Z" line at all
        echo "Usage: ajv [options]" >&2
        exit 0
        ;;
esac
STUB
    chmod +x "$STUB_BIN/ajv"
    run _run_probe
    [ "$status" -eq 0 ]
    [[ "$output" == *"ajv_ver=unknown (ajv-cli@5+)"* ]]
    [[ "$output" != *"error:"* ]]
}

@test "bug-725-4: missing ajv — probe reports not-installed (positive control)" {
    # Don't create a stub. PATH includes only the empty STUB_BIN plus
    # /usr/bin + /bin so basic shell utilities (`command`, `echo`) work,
    # but no `ajv` is available.
    run env PATH="$STUB_BIN:/usr/bin:/bin" bash -c '
        if command -v ajv >/dev/null 2>&1; then
            echo "ajv_ver=present"
        else
            echo "ajv_ver=not-installed"
        fi
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ajv_ver=not-installed"* ]]
}

# =============================================================================
# Source-level anti-regression on the doctor script itself
# =============================================================================

@test "bug-725-5-source: loa-doctor.sh references bug-725 in the ajv probe block" {
    grep -qE '# bug-725:' "$PROJECT_ROOT/.claude/scripts/loa-doctor.sh"
}

@test "bug-725-6-source: probe contains --help fallback parse (post-extraction multi-line)" {
    # After BB #916 F-001 extraction into _loa_probe_ajv_version, the
    # pipe is multi-line. Verify the two anchor pieces are present:
    # (1) the `ajv --help` capture and (2) the `version X.Y` regex parse.
    grep -qE 'ajv --help' "$PROJECT_ROOT/.claude/scripts/loa-doctor.sh"
    grep -qE "version \[0-9\]\+\\\\\.\[0-9\]\+" "$PROJECT_ROOT/.claude/scripts/loa-doctor.sh"
}

@test "bug-725-7-source: probe contains 'unknown (ajv-cli@5+)' placeholder" {
    grep -qF 'unknown (ajv-cli@5+)' "$PROJECT_ROOT/.claude/scripts/loa-doctor.sh"
}

@test "bug-725-9: BB #916 F1 — pipefail-guarded fallback returns placeholder, doesn't abort caller" {
    # BB #916 F1 (MEDIUM, 0.82 conf — gpt-5.5-pro): the help-fallback pipe
    # was unguarded against `set -e` + `pipefail`. If --help output has no
    # matching version line, grep returns 1, pipefail propagates it, and
    # errexit aborts the caller BEFORE the "unknown (ajv-cli@5+)"
    # placeholder is assigned. This test exercises EXACTLY that path under
    # `set -eo pipefail` (active in _run_probe's bash -c) — function MUST
    # return the placeholder cleanly, not abort.
    cat > "$STUB_BIN/ajv" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    --version)
        echo "error: unknown flag" >&2; exit 1 ;;
    --help)
        # Deliberately NO "version X.Y.Z" line — exercises the F1 path.
        echo "Usage: ajv command [options]"; exit 0 ;;
esac
STUB
    chmod +x "$STUB_BIN/ajv"
    run _run_probe
    [ "$status" -eq 0 ]   # MUST NOT abort — function must complete cleanly
    [[ "$output" == *"ajv_ver=unknown (ajv-cli@5+)"* ]]
}

@test "bug-725-10: BB #916 F1 — pipefail-guarded fallback when ajv --help itself errors (exit non-zero)" {
    # F1 corollary: if `ajv --help` itself returns non-zero (e.g., the v5
    # CLI's --help path also errors on some sub-invocation), the function
    # must still produce the placeholder without aborting the caller.
    cat > "$STUB_BIN/ajv" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    --version) echo "error" >&2; exit 1 ;;
    --help)    echo "error: help broke" >&2; exit 2 ;;
esac
STUB
    chmod +x "$STUB_BIN/ajv"
    run _run_probe
    [ "$status" -eq 0 ]
    [[ "$output" == *"ajv_ver=unknown (ajv-cli@5+)"* ]]
}

@test "bug-725-8-source: legacy single-line probe shape is NOT present on a code line (anti-regression)" {
    # The exact bad pattern: `ajv --version 2>&1 | head -1 || echo "unknown"`
    # MUST NOT reappear on a code line. Comment lines that mention the
    # legacy pattern (documenting WHY it was removed) are filtered out.
    local hits
    hits=$(grep -hE 'ajv --version 2>&1 \| head -1' \
        "$PROJECT_ROOT/.claude/scripts/loa-doctor.sh" \
        | grep -vE '^[[:space:]]*#' || true)
    if [[ -n "$hits" ]]; then
        echo "FAIL: legacy probe pattern resurfaced on a code line:" >&2
        echo "$hits" >&2
        return 1
    fi
}
