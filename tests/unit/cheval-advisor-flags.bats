#!/usr/bin/env bats
# =============================================================================
# Cycle-108 sprint-1 T1.H — cheval --role / --skill / --sprint-kind flag tests
# =============================================================================
# Validates the new advisor-strategy flags accept correctly without breaking
# the existing cheval invocation path (backward-compat is non-negotiable).
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CHEVAL="$REPO_ROOT/.claude/adapters/cheval.py"
    export PROJECT_ROOT="$REPO_ROOT"
    # Ensure feature is disabled so existing cheval behavior is preserved
    unset LOA_ADVISOR_STRATEGY_DISABLE 2>/dev/null || true
}

@test "T1.H: cheval --help lists --role flag" {
    run python3 "$CHEVAL" --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '\-\-role'
}

@test "T1.H: cheval --help lists --skill flag" {
    run python3 "$CHEVAL" --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '\-\-skill'
}

@test "T1.H: cheval --help lists --sprint-kind flag" {
    run python3 "$CHEVAL" --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '\-\-sprint-kind'
}

@test "T1.H: --role accepts 'planning' value" {
    # Missing --agent triggers INVALID_INPUT. We assert that argparse accepted
    # --role planning (no "invalid choice" error in output), proven by the
    # structured JSON error being INVALID_INPUT not argparse failure.
    run python3 "$CHEVAL" --role planning --dry-run
    echo "$output" | grep -q '"code": "INVALID_INPUT"'
    ! (echo "$output" | grep -q "invalid choice")
}

@test "T1.H: --role rejects invalid enum value" {
    run python3 "$CHEVAL" --role hacker --dry-run
    # argparse rejects with exit 2
    [ "$status" -eq 2 ]
    echo "$output" | grep -qiE "(invalid choice|argument --role)"
}

@test "T1.H: --role accepts review value" {
    run python3 "$CHEVAL" --role review --dry-run
    echo "$output" | grep -q '"code": "INVALID_INPUT"'
    ! (echo "$output" | grep -q "invalid choice")
}

@test "T1.H: --role accepts implementation value" {
    run python3 "$CHEVAL" --role implementation --dry-run
    echo "$output" | grep -q '"code": "INVALID_INPUT"'
    ! (echo "$output" | grep -q "invalid choice")
}

@test "T1.H: backward-compat — invocation without --role parses cleanly" {
    # Existing callers omitting --role should produce no argparse-level errors.
    # We use --print-effective-config which is the easiest non-API path.
    run python3 "$CHEVAL" --print-effective-config
    ! (echo "$output" | grep -qE "invalid choice|unrecognized arguments")
}

@test "T1.H: --skill accepts arbitrary string" {
    run python3 "$CHEVAL" --skill foo-bar-baz --dry-run
    ! (echo "$output" | grep -qE "invalid choice|unrecognized arguments")
}

@test "T1.H: --sprint-kind accepts arbitrary string" {
    run python3 "$CHEVAL" --sprint-kind glue --dry-run
    ! (echo "$output" | grep -qE "invalid choice|unrecognized arguments")
}
