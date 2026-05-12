#!/usr/bin/env bats
# =============================================================================
# Cycle-108 T1.D: role/primary_role validator tests
# =============================================================================
# Tests the role-aware extensions to validate-skill-capabilities.sh.
# Closes:
#   - PRD §5 FR-3 (role field requirement)
#   - SDD §4 (skill annotation contract)
#   - SDD §20.5 ATK-A13 (heuristic linter for sham review skills)
#   - SDD §20.10 ATK-A2 (diff-aware role-change rule)
#   - SDD §21 IMP-012 (multi-role tiebreaker — advisor-wins-ties)
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    VALIDATOR="$REPO_ROOT/.claude/scripts/validate-skill-capabilities.sh"
    FIXTURES="$REPO_ROOT/tests/fixtures/skills/role-lint"
    # Each fixture lives in its own dir so SKILLS_DIR can target one at a time.
    export PROJECT_ROOT="$REPO_ROOT"
    export LOA_VALIDATE_ROLE=1
}

# --- Helpers ----------------------------------------------------------------

run_validator_on_fixture() {
    # Single-fixture invocation via SKILLS_DIR=<fixture-parent> + --skill <name>
    local fixture_name="$1"
    SKILLS_DIR="$FIXTURES" run "$VALIDATOR" --skill "$fixture_name" --json
}

# --- Positive fixtures ------------------------------------------------------

@test "T1.D: positive-review fixture passes role + keyword checks" {
    run_validator_on_fixture "positive-review"
    [ "$status" -eq 0 ]
    # Should have 0 errors related to role
    role_errors=$(echo "$output" | jq '[.results[] | select(.level == "error") | select(.message | contains("cycle-108 T1.D"))] | length')
    [ "$role_errors" -eq 0 ]
}

@test "T1.D: positive-implementation fixture passes (no review-keyword requirement)" {
    run_validator_on_fixture "positive-implementation"
    [ "$status" -eq 0 ]
    role_errors=$(echo "$output" | jq '[.results[] | select(.level == "error") | select(.message | contains("cycle-108 T1.D"))] | length')
    [ "$role_errors" -eq 0 ]
}

@test "T1.D: positive-planning fixture passes" {
    run_validator_on_fixture "positive-planning"
    [ "$status" -eq 0 ]
    role_errors=$(echo "$output" | jq '[.results[] | select(.level == "error") | select(.message | contains("cycle-108 T1.D"))] | length')
    [ "$role_errors" -eq 0 ]
}

# --- Negative fixtures ------------------------------------------------------

@test "T1.D: negative-no-role fixture fails with missing role error" {
    run_validator_on_fixture "negative-no-role"
    [ "$status" -ne 0 ]
    msg_match=$(echo "$output" | jq -r '[.results[] | select(.level == "error") | .message] | join("|")')
    echo "$msg_match" | grep -q "Missing required 'role' field"
}

@test "T1.D: negative-invalid-role fixture fails with enum error" {
    run_validator_on_fixture "negative-invalid-role"
    [ "$status" -ne 0 ]
    msg_match=$(echo "$output" | jq -r '[.results[] | select(.level == "error") | .message] | join("|")')
    echo "$msg_match" | grep -q "Invalid role 'hacker'"
}

@test "T1.D: negative-sham-review fixture emits warning (no REVIEW-EXEMPT)" {
    # Default mode: warning, not error
    run_validator_on_fixture "negative-sham-review"
    msg_match=$(echo "$output" | jq -r '[.results[] | select(.level == "warning") | .message] | join("|")')
    echo "$msg_match" | grep -q "role: review but body has only"
}

@test "T1.D: negative-sham-review with --strict promotes warning to error" {
    SKILLS_DIR="$FIXTURES" run "$VALIDATOR" --skill "negative-sham-review" --strict --json
    [ "$status" -ne 0 ]
    msg_match=$(echo "$output" | jq -r '[.results[] | select(.level == "error") | .message] | join("|")')
    echo "$msg_match" | grep -q "role: review but body has only"
}

@test "T1.D: negative-bad-primary-role fails (advisor-wins-ties violation)" {
    run_validator_on_fixture "negative-bad-primary-role"
    [ "$status" -ne 0 ]
    msg_match=$(echo "$output" | jq -r '[.results[] | select(.level == "error") | .message] | join("|")')
    echo "$msg_match" | grep -q "advisor-wins-ties"
}

# --- LOA_VALIDATE_ROLE opt-in semantics -------------------------------------

@test "T1.D: skill without role: field passes when LOA_VALIDATE_ROLE unset (back-compat)" {
    unset LOA_VALIDATE_ROLE
    SKILLS_DIR="$FIXTURES" run "$VALIDATOR" --skill "negative-no-role" --json
    role_errors=$(echo "$output" | jq '[.results[] | select(.level == "error") | select(.message | contains("cycle-108 T1.D"))] | length')
    [ "$role_errors" -eq 0 ]
}

@test "T1.D: skill WITH role: field is validated even when LOA_VALIDATE_ROLE unset" {
    # Forward-compat: once a skill declares role:, the validator enforces.
    unset LOA_VALIDATE_ROLE
    run_validator_on_fixture "negative-invalid-role"
    [ "$status" -ne 0 ]
}

# --- Existing skills don't regress -----------------------------------------

@test "T1.D: existing skills (no role: yet) still pass when LOA_VALIDATE_ROLE unset" {
    # Smoke check that the cycle-108 extension is back-compat by default.
    # We pick a known-good existing skill from the production set.
    unset LOA_VALIDATE_ROLE
    SKILLS_DIR="$REPO_ROOT/.claude/skills" run "$VALIDATOR" --skill "implementing-tasks" --json
    # Existing skill should still pass overall validation (some warnings are OK)
    # Specifically: should NOT have any cycle-108 T1.D errors
    role_errors=$(echo "$output" | jq '[.results[] | select(.level == "error") | select(.message | contains("cycle-108 T1.D"))] | length')
    [ "$role_errors" -eq 0 ]
}
