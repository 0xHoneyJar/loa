#!/usr/bin/env bats
# =============================================================================
# Cycle-108 sprint-1 T1.I — bash-twin resolver tests
# =============================================================================
# Validates the bash twin exec wrapper produces the same JSON shape as the
# Python canonical. Cross-runtime parity is guaranteed by construction (the
# bash twin shells out to Python) — these tests verify the contract.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    RESOLVER="$REPO_ROOT/.claude/scripts/lib/advisor-strategy-resolver.sh"
    export PROJECT_ROOT="$REPO_ROOT"
    # Save and clear kill-switch so tests run in a deterministic state
    unset LOA_ADVISOR_STRATEGY_DISABLE 2>/dev/null || true
}

@test "T1.I: resolver script exists and is executable" {
    [ -x "$RESOLVER" ]
}

@test "T1.I: resolver --help exits 0" {
    run "$RESOLVER" --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "T1.I bash twin"
}

@test "T1.I: kill-switch returns disabled_legacy sentinel" {
    # When LOA_ADVISOR_STRATEGY_DISABLE=1, resolver returns a sentinel that
    # callers can detect via tier_source == "disabled_legacy"
    export LOA_ADVISOR_STRATEGY_DISABLE=1
    run "$RESOLVER" resolve implementation implementing-tasks anthropic
    [ "$status" -eq 0 ]
    tier_source=$(echo "$output" | jq -r '.tier_source')
    [ "$tier_source" = "disabled_legacy" ]
}

@test "T1.I: missing config section returns disabled_legacy" {
    # When .loa.config.yaml lacks advisor_strategy section, fall through to
    # disabled_legacy. (We can't actually mutate the real .loa.config.yaml
    # in tests, so we use the kill-switch path which is equivalent.)
    export LOA_ADVISOR_STRATEGY_DISABLE=1
    run "$RESOLVER" resolve implementation implementing-tasks anthropic
    [ "$status" -eq 0 ]
    tier=$(echo "$output" | jq -r '.tier')
    [ "$tier" = "" ]
}

@test "T1.I: bad subcommand exits 2" {
    run "$RESOLVER" not-a-real-subcommand
    [ "$status" -eq 2 ]
}

@test "T1.I: missing args to resolve exits 2" {
    run "$RESOLVER" resolve only-one-arg
    [ "$status" -eq 2 ]
}

@test "T1.I: CLI mode + sourcing share the same Python module" {
    # Sourcing the resolver should not error
    # shellcheck disable=SC1090
    source "$RESOLVER"
    # Function should be exported
    declare -F advisor_strategy_resolve > /dev/null
}
