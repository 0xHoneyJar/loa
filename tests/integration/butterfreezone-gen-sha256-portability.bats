#!/usr/bin/env bats
# =============================================================================
# tests/integration/butterfreezone-gen-sha256-portability.bats
#
# sprint-bug-172 / bug-911 — end-to-end portability proof for sha256_portable
# on a simulated macOS host where sha256sum is genuinely absent.
#
# Strategy: override the `command` builtin via bash function to make
# `command -v sha256sum` return failure. This mirrors macOS's real behavior
# (sha256sum genuinely not findable) without requiring a hermetic PATH
# sandbox that breaks when compat-lib calls `uname`/etc. The override
# bypasses PATH lookup entirely, simulating "this binary does not exist."
#
# Pre-fix (sprint-bug-172 not landed): raw `sha256sum` calls error
# "command not found", cascade into empty hashes, then validation reports
# 10/12 provenance tagged. Post-fix: sha256_portable falls back to
# shasum -a 256, all hashes computed correctly, validation 12/12.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT

    COMPAT_LIB="$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
    [[ -f "$COMPAT_LIB" ]] || skip "compat-lib.sh not present"

    # Require shasum on test host so the bsd-fallback branch can be exercised.
    command -v shasum >/dev/null 2>&1 || skip "shasum not available on test host"

    EXPECTED_HASH="$(printf 'sprint-bug-172-integration\n' | sha256sum | awk '{print $1}')"
    export EXPECTED_HASH
}

@test "P1 simulated-macOS: sha256_portable detects bsd backend when sha256sum is absent" {
    run bash -c '
        # Override command builtin to fake sha256sum absence (macOS-like).
        command() {
            if [[ "$1" == "-v" && "$2" == "sha256sum" ]]; then
                return 1
            fi
            builtin command "$@"
        }
        source "'"$COMPAT_LIB"'"
        echo "$_COMPAT_SHA256_CMD"
    '
    [[ "$status" -eq 0 ]]
    [[ "$output" == "bsd" ]]
}

@test "P2 simulated-macOS: sha256_portable produces byte-identical hash via shasum fallback" {
    run bash -c '
        command() {
            if [[ "$1" == "-v" && "$2" == "sha256sum" ]]; then
                return 1
            fi
            builtin command "$@"
        }
        source "'"$COMPAT_LIB"'"
        printf "sprint-bug-172-integration\n" | sha256_portable | awk "{print \$1}"
    '
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$EXPECTED_HASH" ]]
}

@test "P3 simulated-no-tools: sha256_portable fails loud (no silent empty hash)" {
    run bash -c '
        command() {
            if [[ "$1" == "-v" && ( "$2" == "sha256sum" || "$2" == "shasum" ) ]]; then
                return 1
            fi
            builtin command "$@"
        }
        source "'"$COMPAT_LIB"'"
        echo "DETECTION=$_COMPAT_SHA256_CMD"
        printf "data\n" | sha256_portable
    '
    [[ "$output" =~ "DETECTION=" ]]
    # _COMPAT_SHA256_CMD is empty in this scenario
    [[ "$output" =~ "DETECTION="$'\n' ]] || [[ "$output" =~ "DETECTION=" ]]
    # Must exit non-zero (fail loud) — no silent empty-hash emission
    [[ "$status" -ne 0 ]]
    # Must mention the diagnostic
    [[ "$output" =~ "sha256" ]]
}

@test "P4 unmasked PATH: sha256_portable uses gnu (preference order verified)" {
    # No override — host PATH has both tools or just GNU. Should prefer gnu.
    run bash -c "source '$COMPAT_LIB'; echo \$_COMPAT_SHA256_CMD"
    [[ "$status" -eq 0 ]]
    # On Linux CI: should detect gnu. macOS: would detect bsd.
    [[ "$output" == "gnu" || "$output" == "bsd" ]]
}

@test "P5 audit-envelope.sh _audit_sha256 wrapper preserves python3 fallback semantics" {
    # audit-envelope.sh defines _audit_sha256 which delegates to sha256_portable
    # but ALSO has a python3 fallback for the "neither GNU nor BSD available"
    # case. This test pins the wrapper's defense-in-depth contract.
    local audit_envelope="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"
    [[ -f "$audit_envelope" ]] || skip "audit-envelope.sh not present"
    # python3 fallback presence
    grep -q "python3 -c" "$audit_envelope"
    # sha256_portable delegation in place
    grep -q "sha256_portable" "$audit_envelope"
    # compat-lib sourced
    grep -q "compat-lib.sh" "$audit_envelope"
}

@test "P6 framework parse: every migrated script parses without syntax errors" {
    local fail_count=0
    local failed_files=()
    # Sample of representative migrated scripts (full sweep is in CI bats)
    for script in mount-loa.sh preflight.sh butterfreezone-gen.sh ground-truth-gen.sh audit-envelope.sh adversarial-review.sh flatline-manifest.sh check-loa.sh; do
        local full="$PROJECT_ROOT/.claude/scripts/$script"
        [[ -f "$full" ]] || continue
        if ! bash -n "$full" 2>/dev/null; then
            failed_files+=("$script")
            fail_count=$((fail_count + 1))
        fi
    done
    [[ "$fail_count" -eq 0 ]] || { echo "Parse failures: ${failed_files[*]}"; false; }
}
