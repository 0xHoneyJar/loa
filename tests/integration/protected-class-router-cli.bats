#!/usr/bin/env bats
# =============================================================================
# tests/integration/protected-class-router-cli.bats
#
# cycle-098 Sprint 1 review remediation — F2 (BUG).
#
# protected-class-router.sh `override` CLI was broken: line 154 used `local`
# at top-level (case-arm body, NOT inside a function). bash refuses with
# "local: can only be used in a function" and exits 1 with no override logged.
#
# Fix: wrap the override case-arm body in a function `_protected_class_override_cli`.
#
# This test runs the override CLI subcommand end-to-end with synthetic args
# and verifies exit 0 + override entry persisted.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    ROUTER="$PROJECT_ROOT/.claude/scripts/lib/protected-class-router.sh"
    TAXONOMY="$PROJECT_ROOT/.claude/data/protected-classes.yaml"

    [[ -f "$ROUTER" ]] || skip "protected-class-router.sh not present"
    [[ -f "$TAXONOMY" ]] || skip "protected-classes.yaml not present"

    TEST_DIR="$(mktemp -d)"

    # F1 isolation: point at permissive test trust-store so the override audit
    # write (unsigned) is not rejected by post-cutoff strict-sign rule.
    TEST_TRUST_STORE="$TEST_DIR/trust-store.yaml"
    cat > "$TEST_TRUST_STORE" <<'EOF'
schema_version: "1.0"
root_signature:
  algorithm: ed25519
  signer_pubkey: ""
  signed_at: ""
  signature: ""
keys: []
revocations: []
trust_cutoff:
  default_strict_after: "2099-01-01T00:00:00Z"
EOF
    export LOA_TRUST_STORE_FILE="$TEST_TRUST_STORE"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
    fi
    unset LOA_TRUST_STORE_FILE
}

# -----------------------------------------------------------------------------
# F2: override CLI must succeed end-to-end.
# -----------------------------------------------------------------------------

@test "router-cli: override exits 0 with all required flags" {
    run bash "$ROUTER" override \
        --class credential.rotate \
        --duration 3600 \
        --reason "test override"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK override logged"* ]]
}

@test "router-cli: override fails 2 when --class missing" {
    run bash "$ROUTER" override --duration 3600 --reason "x"
    [[ "$status" -eq 2 ]]
}

@test "router-cli: override fails 2 when --duration missing" {
    run bash "$ROUTER" override --class credential.rotate --reason "x"
    [[ "$status" -eq 2 ]]
}

@test "router-cli: override fails 2 when --reason missing" {
    run bash "$ROUTER" override --class credential.rotate --duration 3600
    [[ "$status" -eq 2 ]]
}

@test "router-cli: override fails 2 on unknown flag" {
    run bash "$ROUTER" override --bogus value
    [[ "$status" -eq 2 ]]
}

@test "router-cli: override does NOT emit 'local can only be used in a function' (F2 regression)" {
    run bash "$ROUTER" override \
        --class credential.rotate \
        --duration 3600 \
        --reason "F2 regression check"
    [[ "$output" != *"local: can only be used in a function"* ]]
    [[ "$output" != *"local: can only be used"* ]]
}

@test "router-cli: check command still works (existing path)" {
    run bash "$ROUTER" check credential.rotate
    [[ "$status" -eq 0 ]]
}

@test "router-cli: check returns 1 for non-protected" {
    run bash "$ROUTER" check unmatched.thing
    [[ "$status" -eq 1 ]]
}
