#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-109-t3-6-feature-flag-removal.bats
#
# cycle-109 Sprint 3 T3.6 — commit C in SDD §5.3.1 sequence. Removes
# the `is_flatline_routing_enabled` feature-flag branches from the two
# load-bearing operator-facing entrypoints so cheval is the unconditional
# default path:
#
#   1. model-adapter.sh::main() — pre-fix: `if ! is_flatline_routing_enabled;
#      then delegate_to_legacy "$@"; fi` guard at line 369-372. Post-fix:
#      no early-exit to legacy; main() always proceeds to the cheval
#      dispatch path.
#
#   2. flatline-orchestrator.sh::call_model — pre-fix: `if
#      is_flatline_routing_enabled && [[ -x "$MODEL_INVOKE" ]]; then
#      <cheval path>; else <legacy path>; fi`. Post-fix: always uses
#      cheval (model-invoke); else-branch removed.
#
# Mock-mode delegation at model-adapter.sh line ~522 is intentionally
# RETAINED — it routes to legacy fixtures when FLATLINE_MOCK_MODE=true.
# That path is T3.8 cleanup (after T3.7's destructive legacy deletion
# under C109.OP-S3 operator approval). T3.6 stays non-destructive.
#
# is_flatline_routing_enabled() the function definition is also retained
# so other callers (gpt-review-api.sh, lib-route-table.sh, lib-curl-
# fallback.sh, red-team-model-adapter.sh) continue to work; they'll be
# cleaned up in T3.8.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
}

# =============================================================================
# T36-1: flatline-orchestrator.sh::call_model no longer branches on flag
# =============================================================================

@test "T36-1: flatline-orchestrator.sh call_model no longer conditionally branches on is_flatline_routing_enabled" {
    # Pre-fix shape (line ~626): `if is_flatline_routing_enabled && ...; then`
    # Post-fix: that exact conditional should be GONE. The cheval-dispatch
    # body must still exist (we're not removing the cheval path — only
    # the branching).
    local fl="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"

    # The legacy-fallback else-branch invoking $MODEL_ADAPTER should be
    # gone — specifically the `"$MODEL_ADAPTER" --model "$model" --mode
    # "$mode" \` invocation that pre-fix lived in the else-branch.
    if grep -qE '^\s*"\$MODEL_ADAPTER"\s+--model\s+"\$model"\s+--mode\s+"\$mode"\s*\\\s*$' "$fl"; then
        echo "FAIL: legacy MODEL_ADAPTER fallback invocation still present in call_model" >&2
        return 1
    fi
}

# =============================================================================
# T36-2: model-adapter.sh main() no longer early-exits to legacy
# =============================================================================

@test "T36-2: model-adapter.sh main() no longer conditional-exec's to legacy on flag=false" {
    # Pre-fix (line 369-372):
    #   if ! is_flatline_routing_enabled; then
    #       delegate_to_legacy "$@"
    #   fi
    # Post-fix: that block should be removed.
    local ma="$PROJECT_ROOT/.claude/scripts/model-adapter.sh"

    # Search for the specific pre-fix shape — a `! is_flatline_routing_enabled`
    # negation followed by delegate_to_legacy. That exact pairing is the
    # feature-flag guard.
    if grep -nE 'if\s+!\s+is_flatline_routing_enabled' "$ma" | head -1 | grep -q .; then
        echo "FAIL: model-adapter.sh still has 'if ! is_flatline_routing_enabled' guard" >&2
        return 1
    fi
}

# =============================================================================
# T36-3: is_flatline_routing_enabled() function definition retained
# =============================================================================

@test "T36-3: is_flatline_routing_enabled() function definition is retained for other callers" {
    # Other consumers (gpt-review-api.sh, lib-route-table.sh, lib-curl-fallback.sh,
    # red-team-model-adapter.sh) still call this helper. T3.6 only removes
    # the BRANCH SITES we own; the function itself stays defined so we
    # don't break upstream-of-us consumers. Cleanup deferred to T3.8.
    grep -q "is_flatline_routing_enabled()" \
        "$PROJECT_ROOT/.claude/scripts/model-adapter.sh"
    grep -q "is_flatline_routing_enabled()" \
        "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

# =============================================================================
# T36-4: mock-mode delegation to legacy is RETAINED (T3.6 stays non-destructive)
# =============================================================================

@test "T36-4: mock-mode delegation to legacy is retained (T3.6 stays non-destructive)" {
    # FLATLINE_MOCK_MODE=true at model-adapter.sh line ~520-526 delegates
    # to legacy's get_mock_response. CI tests
    # (test_flatline_routing.py + model-adapter-aliases.bats +
    # adversarial-review-e2e.bats) depend on this path. T3.6 must NOT
    # touch it; T3.7 + T3.8 handle the migration under operator approval.
    grep -qE 'FLATLINE_MOCK_MODE.*delegate_to_legacy|delegate_to_legacy.*--model.*--mode' \
        "$PROJECT_ROOT/.claude/scripts/model-adapter.sh"
}

# =============================================================================
# T36-5: legacy file still on disk (T3.6 is non-destructive)
# =============================================================================

@test "T36-5: legacy adapter file still on disk (T3.7 destructive deletion is gated)" {
    [[ -f "$PROJECT_ROOT/.claude/scripts/model-adapter.sh.legacy" ]]
}

# =============================================================================
# T36-6: cheval dispatch path is still present (we removed branches, not body)
# =============================================================================

@test "T36-6: flatline-orchestrator.sh call_model still uses MODEL_INVOKE" {
    grep -q '\$MODEL_INVOKE' "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

@test "T36-7: model-adapter.sh main() still invokes MODEL_INVOKE post-fix" {
    grep -q '\$MODEL_INVOKE' "$PROJECT_ROOT/.claude/scripts/model-adapter.sh"
}

# =============================================================================
# T36-8: shell syntax still valid after edits
# =============================================================================

@test "T36-8: flatline-orchestrator.sh bash -n passes (no syntax errors)" {
    bash -n "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

@test "T36-9: model-adapter.sh bash -n passes (no syntax errors)" {
    bash -n "$PROJECT_ROOT/.claude/scripts/model-adapter.sh"
}
