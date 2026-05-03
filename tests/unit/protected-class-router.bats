#!/usr/bin/env bats
# =============================================================================
# tests/unit/protected-class-router.bats
#
# cycle-098 Sprint 1B — protected-class-router.sh.
# Per PRD Appendix D + SDD §1.4.2: 10-class default taxonomy. Router must
# return 0 for matched class, 1 otherwise.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    ROUTER="$PROJECT_ROOT/.claude/scripts/lib/protected-class-router.sh"
    TAXONOMY="$PROJECT_ROOT/.claude/data/protected-classes.yaml"

    [[ -f "$ROUTER" ]] || skip "protected-class-router.sh not present"
    [[ -f "$TAXONOMY" ]] || skip "protected-classes.yaml not present"

    # shellcheck disable=SC1090
    source "$ROUTER"
}

# -----------------------------------------------------------------------------
# 10 default classes (PRD Appendix D)
# -----------------------------------------------------------------------------
@test "protected-class: credential.rotate is protected" {
    run is_protected_class "credential.rotate"
    [[ "$status" -eq 0 ]]
}

@test "protected-class: credential.revoke is protected" {
    run is_protected_class "credential.revoke"
    [[ "$status" -eq 0 ]]
}

@test "protected-class: production.deploy is protected" {
    run is_protected_class "production.deploy"
    [[ "$status" -eq 0 ]]
}

@test "protected-class: production.rollback is protected" {
    run is_protected_class "production.rollback"
    [[ "$status" -eq 0 ]]
}

@test "protected-class: destructive.irreversible is protected" {
    run is_protected_class "destructive.irreversible"
    [[ "$status" -eq 0 ]]
}

@test "protected-class: git.merge_main is protected" {
    run is_protected_class "git.merge_main"
    [[ "$status" -eq 0 ]]
}

@test "protected-class: schema.migration is protected" {
    run is_protected_class "schema.migration"
    [[ "$status" -eq 0 ]]
}

@test "protected-class: cycle.archive is protected" {
    run is_protected_class "cycle.archive"
    [[ "$status" -eq 0 ]]
}

@test "protected-class: trust.force_grant is protected" {
    run is_protected_class "trust.force_grant"
    [[ "$status" -eq 0 ]]
}

@test "protected-class: budget.cap_increase is protected" {
    run is_protected_class "budget.cap_increase"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Non-classes return 1
# -----------------------------------------------------------------------------
@test "protected-class: random non-class returns 1" {
    run is_protected_class "noop.benign"
    [[ "$status" -eq 1 ]]
}

@test "protected-class: empty arg returns 1" {
    run is_protected_class ""
    [[ "$status" -eq 1 ]]
}

@test "protected-class: typo of real class returns 1" {
    # Subtle: production.deploy_typo isn't protected.
    run is_protected_class "production.deploy_typo"
    [[ "$status" -eq 1 ]]
}

# -----------------------------------------------------------------------------
# CLI dispatch
# -----------------------------------------------------------------------------
@test "protected-class CLI: check command returns 0 for protected class" {
    run "$ROUTER" check "credential.rotate"
    [[ "$status" -eq 0 ]]
}

@test "protected-class CLI: check command returns 1 for non-class" {
    run "$ROUTER" check "noop.benign"
    [[ "$status" -eq 1 ]]
}

# -----------------------------------------------------------------------------
# All 10 classes are loaded
# -----------------------------------------------------------------------------
@test "protected-class: list_protected_classes returns all 10 default classes" {
    run list_protected_classes
    [[ "$status" -eq 0 ]]
    local count
    count=$(echo "$output" | grep -c .)
    [[ "$count" -eq 10 ]]
}
