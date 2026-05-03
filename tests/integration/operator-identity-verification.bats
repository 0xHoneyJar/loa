#!/usr/bin/env bats
# =============================================================================
# tests/integration/operator-identity-verification.bats
#
# cycle-098 Sprint 1B — Operator Identity (PRD §Cross-cutting).
# Tests verify_operator returns success for a known ID and fails for unknown.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    OP_IDENTITY="$PROJECT_ROOT/.claude/scripts/operator-identity.sh"

    [[ -f "$OP_IDENTITY" ]] || skip "operator-identity.sh not present"

    TEST_DIR="$(mktemp -d)"
    OPERATORS_FILE="$TEST_DIR/operators.md"

    # Build a fixture OPERATORS.md with two operators.
    cat > "$OPERATORS_FILE" <<'EOF'
---
schema_version: "1.0"
operators:
  - id: deep-name
    display_name: "Deep Name"
    github_handle: janitooor
    git_email: "deep-name@example.com"
    capabilities:
      - dispatch
      - merge
    active_since: "2026-05-03T00:00:00Z"
  - id: legacy-operator
    display_name: "Legacy Operator"
    github_handle: legacy-handle
    git_email: "legacy@example.com"
    capabilities: []
    active_since: "2026-01-01T00:00:00Z"
    active_until: "2026-04-01T00:00:00Z"
---

# Test fixture
EOF

    export LOA_OPERATORS_FILE="$OPERATORS_FILE"

    # shellcheck disable=SC1090
    source "$OP_IDENTITY"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
    fi
    unset LOA_OPERATORS_FILE
}

# -----------------------------------------------------------------------------
# Lookup
# -----------------------------------------------------------------------------
@test "operator-identity: lookup known operator returns YAML object" {
    run operator_identity_lookup "deep-name"
    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "deep-name"
    echo "$output" | grep -q "janitooor"
}

@test "operator-identity: lookup unknown operator fails" {
    run operator_identity_lookup "nonexistent-operator"
    [[ "$status" -ne 0 ]]
}

# -----------------------------------------------------------------------------
# Verification
# -----------------------------------------------------------------------------
@test "operator-identity: verify known active operator returns 0" {
    run operator_identity_verify "deep-name"
    [[ "$status" -eq 0 ]]
}

@test "operator-identity: verify unknown operator returns 2 (unknown)" {
    run operator_identity_verify "nonexistent-operator"
    [[ "$status" -eq 2 ]]
}

@test "operator-identity: verify offboarded operator returns 1 (unverified)" {
    # legacy-operator has active_until in the past — not active.
    run operator_identity_verify "legacy-operator"
    [[ "$status" -eq 1 ]]
}

# -----------------------------------------------------------------------------
# Schema validation
# -----------------------------------------------------------------------------
@test "operator-identity: validate well-formed schema returns 0" {
    run operator_identity_validate_schema "$OPERATORS_FILE"
    [[ "$status" -eq 0 ]]
}

@test "operator-identity: validate malformed schema fails" {
    cat > "$TEST_DIR/bad.md" <<'EOF'
---
schema_version: "1.0"
operators:
  - id: missing-required-fields
---
EOF
    run operator_identity_validate_schema "$TEST_DIR/bad.md"
    [[ "$status" -ne 0 ]]
}

# -----------------------------------------------------------------------------
# Real OPERATORS.md (the one we ship)
# -----------------------------------------------------------------------------
@test "operator-identity: real grimoires/loa/operators.md validates" {
    local real="$PROJECT_ROOT/grimoires/loa/operators.md"
    [[ -f "$real" ]]
    run operator_identity_validate_schema "$real"
    [[ "$status" -eq 0 ]]
}

@test "operator-identity: real OPERATORS.md contains deep-name" {
    local real="$PROJECT_ROOT/grimoires/loa/operators.md"
    LOA_OPERATORS_FILE="$real" run operator_identity_lookup "deep-name"
    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "deep-name"
}
