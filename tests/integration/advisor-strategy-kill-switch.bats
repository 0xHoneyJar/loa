#!/usr/bin/env bats
# =============================================================================
# Cycle-108 sprint-1 T1.J — tier_resolution + in-flight kill-switch integration
# =============================================================================
# Closes:
#   - SDD §3.6 (FR-9 tier_resolution mode: static pin to git SHA)
#   - SDD §7.1 (FR-7 IMP-007 in-flight kill-switch semantics)
#   - NFR-Sec3 (kill-switch env var precedence)
#
# These are INTEGRATION tests — they exercise the full T1.C loader +
# T1.I bash twin + T1.H cheval CLI path together. Unit tests for each
# component live in their respective files.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    RESOLVER="$REPO_ROOT/.claude/scripts/lib/advisor-strategy-resolver.sh"
    CHEVAL="$REPO_ROOT/.claude/adapters/cheval.py"
    export PROJECT_ROOT="$REPO_ROOT"
    unset LOA_ADVISOR_STRATEGY_DISABLE 2>/dev/null || true
}

# --- Kill-switch precedence (NFR-Sec3) -------------------------------------

@test "T1.J: kill-switch env var precedence — bash twin honors LOA_ADVISOR_STRATEGY_DISABLE" {
    # Even when other config would resolve to a non-advisor tier, the
    # kill-switch env var MUST win.
    export LOA_ADVISOR_STRATEGY_DISABLE=1
    run "$RESOLVER" resolve implementation implementing-tasks anthropic
    [ "$status" -eq 0 ]
    tier_source=$(echo "$output" | jq -r '.tier_source')
    [ "$tier_source" = "disabled_legacy" ]
}

@test "T1.J: kill-switch env var precedence — Python loader honors LOA_ADVISOR_STRATEGY_DISABLE" {
    export LOA_ADVISOR_STRATEGY_DISABLE=1
    run python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$REPO_ROOT/.claude/adapters')
from loa_cheval.config.advisor_strategy import load_advisor_strategy
cfg = load_advisor_strategy('$REPO_ROOT')
print(f'enabled={cfg.enabled}')
print(f'config_sha={cfg.config_sha}')
"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "enabled=False"
    echo "$output" | grep -q "config_sha=DISABLED"
}

# --- In-flight kill-switch semantics (FR-7 IMP-007) ------------------------

@test "T1.J: in-flight kill-switch — first call w/o env, second call w/ env" {
    # Simulate the in-flight scenario: caller does TWO sequential resolutions;
    # we flip the env between them. The first MUST honor the current state;
    # the second MUST see the new state.

    # Step 1: env unset → loader returns whatever config produces
    unset LOA_ADVISOR_STRATEGY_DISABLE
    first_run=$("$RESOLVER" resolve implementation implementing-tasks anthropic 2>/dev/null)
    first_tier_source=$(echo "$first_run" | jq -r '.tier_source')

    # Step 2: env set → next call MUST see disabled_legacy
    export LOA_ADVISOR_STRATEGY_DISABLE=1
    second_run=$("$RESOLVER" resolve implementation implementing-tasks anthropic 2>/dev/null)
    second_tier_source=$(echo "$second_run" | jq -r '.tier_source')

    # The second call MUST be disabled_legacy regardless of first
    [ "$second_tier_source" = "disabled_legacy" ]

    # Step 3: unset → next call MUST honor disabled-by-absence (since
    # .loa.config.yaml currently has no advisor_strategy section)
    unset LOA_ADVISOR_STRATEGY_DISABLE
    third_run=$("$RESOLVER" resolve implementation implementing-tasks anthropic 2>/dev/null)
    third_tier_source=$(echo "$third_run" | jq -r '.tier_source')
    [ "$third_tier_source" = "disabled_legacy" ]
}

# --- Static-mode pinning (FR-9) --------------------------------------------

@test "T1.J: static-mode pinning captures git SHA of .loa.config.yaml" {
    # When the config has an advisor_strategy section AND tier_resolution is
    # static (the default), config_sha MUST capture the git commit SHA of
    # .loa.config.yaml. Currently the repo .loa.config.yaml has no
    # advisor_strategy section, so this test verifies the DISABLED sentinel
    # path; the positive path is covered in test_advisor_strategy_loader.py
    # against fixture configs.
    unset LOA_ADVISOR_STRATEGY_DISABLE
    run python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$REPO_ROOT/.claude/adapters')
from loa_cheval.config.advisor_strategy import load_advisor_strategy
cfg = load_advisor_strategy('$REPO_ROOT')
print(f'config_sha={cfg.config_sha}')
print(f'enabled={cfg.enabled}')
"
    [ "$status" -eq 0 ]
    # Since advisor_strategy section is absent, expect DISABLED sentinel
    echo "$output" | grep -q "config_sha=DISABLED"
    echo "$output" | grep -q "enabled=False"
}

# --- Full-cycle integration via cheval (T1.H wire-up) ----------------------

@test "T1.J: cheval --role implementation invokes advisor-strategy resolution" {
    # When --role is provided, cheval should ATTEMPT to load advisor-strategy
    # config. Currently the config section is absent, so it falls through to
    # disabled-by-absence; cheval proceeds as legacy and reports missing
    # --agent. The smoke is: no ImportError, no unexpected crash.
    unset LOA_ADVISOR_STRATEGY_DISABLE
    run python3 "$CHEVAL" --role implementation --skill implementing-tasks --dry-run
    # Expect INVALID_INPUT (missing --agent), not any advisor-strategy error
    echo "$output" | grep -q '"code": "INVALID_INPUT"'
    ! (echo "$output" | grep -qE "advisor-strategy.*failed")
}

@test "T1.J: cheval with kill-switch env preserves legacy path" {
    # With kill-switch active, even --role provided should not trigger
    # advisor-strategy resolution at all (the loader returns disabled_legacy
    # before any resolve() call).
    export LOA_ADVISOR_STRATEGY_DISABLE=1
    run python3 "$CHEVAL" --role implementation --skill implementing-tasks --dry-run
    # Same expected behavior as without kill-switch: legacy path fires.
    echo "$output" | grep -q '"code": "INVALID_INPUT"'
    ! (echo "$output" | grep -qE "advisor-strategy.*failed")
}

# --- Disabled-by-absence semantics -----------------------------------------

@test "T1.J: missing advisor_strategy section returns disabled_legacy" {
    # The current .loa.config.yaml does not have an advisor_strategy
    # section (cycle-108 ships the schema + loader; operator opt-in
    # adds the config section). Resolver must handle this gracefully.
    unset LOA_ADVISOR_STRATEGY_DISABLE
    run "$RESOLVER" resolve review reviewing-code anthropic
    [ "$status" -eq 0 ]
    tier_source=$(echo "$output" | jq -r '.tier_source')
    [ "$tier_source" = "disabled_legacy" ]
}
