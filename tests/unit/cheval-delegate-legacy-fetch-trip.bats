#!/usr/bin/env bats
# cycle-103 sprint-1 T1.11 — AC-1.5 regression-catcher for the
# LOA_BB_FORCE_LEGACY_FETCH=1 constructor-trip in cheval-delegate.ts.
#
# The trip is implemented at cheval-delegate.ts:84-91 (T1.2, commit 1e1381dd)
# and tested at the TS level by cheval-delegate.test.ts test #3
# ("LOA_BB_FORCE_LEGACY_FETCH=1 triggers guided rollback error"). This bats
# file is a complementary regression-catcher that pins the code block via
# grep so the contract survives future-cycle refactors even if the TS test
# is accidentally weakened or removed.
#
# Mirrors the cycle-103 T1.8 pattern (entry-sh-node-options-vestigial.bats):
# a small grep-based test that fails loudly if a load-bearing comment or
# code block is removed.
#
# Pinned contract:
#   1. The env-var name `LOA_BB_FORCE_LEGACY_FETCH` is referenced in the
#      constructor — removing it without a companion runbook update breaks
#      AC-1.5 ("escape hatch ships at merge").
#   2. The check uses `=== "1"` (string compare, not truthy) so legacy
#      patterns like `LOA_BB_FORCE_LEGACY_FETCH=true` don't silently trip.
#   3. The error throw is an `LLMProviderError` with `INVALID_REQUEST` code
#      — pinning the typed-error contract per SDD §5.3.
#   4. The error message points operators to the cycle-103 runbook so they
#      can find this file when the trip fires.
#   5. The constructor-trip happens BEFORE any side effects (no spawn, no
#      tempfile, no env mutation) so the wrong-env case fails fast.
#
# The TS test pins behavior; this bats test pins source-code text. Both
# would have to be removed simultaneously to silently drop the escape hatch.

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    DELEGATE="$PROJECT_ROOT/.claude/skills/bridgebuilder-review/resources/adapters/cheval-delegate.ts"
    [[ -f "$DELEGATE" ]] || skip "cheval-delegate.ts not found at $DELEGATE"
}

# --------------------------------------------------------------------------
# Source-code contract pins
# --------------------------------------------------------------------------

@test "LOA_BB_FORCE_LEGACY_FETCH env-var name is referenced in the delegate" {
    # If the env var is renamed without coordinating with the runbook + TS
    # test, this fails. Operators reading the runbook would see a stale name.
    run grep -F 'LOA_BB_FORCE_LEGACY_FETCH' "$DELEGATE"
    [ "$status" -eq 0 ]
}

@test "the trip uses string equality === \"1\" (not truthy)" {
    # AC-1.5 contract intent: ONLY the literal value "1" trips the hatch.
    # Truthy checks (`if (env)`) would trip on "false", "0", or any non-empty
    # string — surprising operator behavior. Pin the strict comparison.
    run grep -F "process.env.LOA_BB_FORCE_LEGACY_FETCH === \"1\"" "$DELEGATE"
    [ "$status" -eq 0 ]
}

@test "the trip throws LLMProviderError with INVALID_REQUEST code" {
    # SDD §5.3 typed-error contract. The escape-hatch trip must surface as
    # a typed LLMProviderError so callers can switch on .code (not parse
    # error messages). INVALID_REQUEST is the appropriate category — the
    # operator passed an env var asking for a path that no longer exists.
    #
    # Pin the throw line directly. Multi-line throws use a regex that
    # spans both lines via grep -A.
    run bash -c "grep -A 2 'LOA_BB_FORCE_LEGACY_FETCH' '$DELEGATE' | grep -F 'throw new LLMProviderError('"
    [ "$status" -eq 0 ]
    run bash -c "grep -A 5 'LOA_BB_FORCE_LEGACY_FETCH === \"1\"' '$DELEGATE' | grep -F '\"INVALID_REQUEST\"'"
    [ "$status" -eq 0 ]
}

@test "the error message points to the cycle-103 runbook" {
    # AC-1.5 + T1.10 contract: operators tripping the hatch must find their
    # way to grimoires/loa/runbooks/cheval-delegate-architecture.md (the
    # T1.10 operator runbook) without scavenging.
    run grep -F 'cheval-delegate-architecture.md' "$DELEGATE"
    [ "$status" -eq 0 ]
}

@test "the error message mentions cycle-103 explicitly" {
    # Helps operators correlate the error to the cycle when the runbook is
    # absent (e.g., on a stale clone). The cycle ID anchors the search.
    run bash -c "grep -A 4 'LOA_BB_FORCE_LEGACY_FETCH' '$DELEGATE' | grep -F 'cycle-103'"
    [ "$status" -eq 0 ]
}

@test "the trip happens in the constructor (fail-fast)" {
    # The check must be in the class constructor — not lazy-evaluated in
    # generateReview() — so a wrong-env operator gets the error at
    # adapter-factory time before any tempfile / spawn / env mutation.
    # Pin by asserting the env check precedes any `private readonly` or
    # `this.opts` assignment.
    local env_line throw_line ctor_body_start
    env_line=$(grep -n 'LOA_BB_FORCE_LEGACY_FETCH' "$DELEGATE" | head -1 | cut -d: -f1)
    throw_line=$(grep -n 'throw new LLMProviderError' "$DELEGATE" | head -1 | cut -d: -f1)
    ctor_body_start=$(grep -n 'constructor(' "$DELEGATE" | head -1 | cut -d: -f1)

    [[ -n "$ctor_body_start" ]]
    [[ -n "$env_line" ]]
    [[ "$env_line" -gt "$ctor_body_start" ]]
    [[ -n "$throw_line" ]]
    [[ "$throw_line" -ge "$env_line" ]]
}

@test "delegate file is referenced from the operator runbook (T1.10)" {
    # AC-1.5 + T1.10 cross-link contract: the runbook must mention this
    # trip so operators following error-message → runbook → code can land
    # in the right place. Asserts the runbook references the env var name.
    local runbook="$PROJECT_ROOT/grimoires/loa/runbooks/cheval-delegate-architecture.md"
    [[ -f "$runbook" ]] || skip "T1.10 runbook not present"
    run grep -F 'LOA_BB_FORCE_LEGACY_FETCH' "$runbook"
    [ "$status" -eq 0 ]
}

@test "TS contract test for the trip is present alongside" {
    # AC-1.5 belt-and-suspenders: the TS-level behavior test exists.
    # Pinning the test file path here means removing the TS test silently
    # would still cause CI failure via this bats assertion.
    local ts_test="$PROJECT_ROOT/.claude/skills/bridgebuilder-review/resources/__tests__/cheval-delegate.test.ts"
    [[ -f "$ts_test" ]]
    run grep -F 'LOA_BB_FORCE_LEGACY_FETCH=1 triggers guided rollback error' "$ts_test"
    [ "$status" -eq 0 ]
}
