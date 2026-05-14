#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-109-t3-5-fl-env-and-alias-rec.bats
#
# cycle-109 Sprint 3 T3.5 — closes #820 Issues C + D.
#
#   Issue C: flatline-readiness.sh recommendation references
#            'gemini-3.1-pro' (unregistered) instead of an alias that
#            actually exists in model-config.yaml.
#   Issue D: flatline-orchestrator.sh does not source .env / .env.local
#            before invoking model adapters (BB does; FL does not).
#   Issue D': scoring parser empty-output — already covered by T3.3
#             extract_json_content regression corpus.
#
# These tests use grep-style wiring assertions because the actual
# behavior (env loading semantics + recommendation text) is structural;
# integration tests with live model invocation are out of scope for the
# unit suite.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
}

# =============================================================================
# T35-1..3: Issue D — flatline-orchestrator.sh sources .env / .env.local
# =============================================================================

@test "T35-1: flatline-orchestrator.sh sources .env when present" {
    grep -qE 'source[[:space:]]+\.env\b|set[[:space:]]+-a[[:space:]]*;[[:space:]]*source[[:space:]]+\.env' \
        "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

@test "T35-2: flatline-orchestrator.sh sources .env.local when present" {
    grep -qE 'source[[:space:]]+\.env\.local|\.env\.local[[:space:]]+;' \
        "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

@test "T35-3: flatline-orchestrator.sh uses 'set -a / set +a' export pattern" {
    # Mirror the BB pattern: set -a exports all sourced vars, set +a restores.
    # Anchors the contract that .env vars CROSS subprocess boundaries (which
    # is the whole point of sourcing — env vars only propagate when exported).
    grep -qE 'set[[:space:]]+-a' "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
    grep -qE 'set[[:space:]]+\+a' "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

# =============================================================================
# T35-4: Issue C — recommendation text doesn't reference an unregistered alias
# =============================================================================

@test "T35-4: flatline-readiness.sh recommendation does NOT suggest unregistered 'gemini-3.1-pro'" {
    # #820 Issue C: the recommendation text literally says "use
    # 'gemini-3.1-pro' instead of 'gemini-3.1-pro-preview'" but
    # gemini-3.1-pro is NOT a registered alias. Either the recommendation
    # must reference a real alias OR drop the literal alias suggestion
    # and only point at the pin-form.
    #
    # Acceptable post-fix shapes:
    #   - "use 'google:<model_id>' pin form" (drops the alias suggestion)
    #   - References any alias that IS in model-config.yaml's aliases map
    #
    # Disallowed: the literal 'gemini-3.1-pro' string appearing as a
    # recommendation when no such alias exists.
    if grep -qE "'gemini-3\.1-pro'[[:space:]]+instead" "$PROJECT_ROOT/.claude/scripts/flatline-readiness.sh"; then
        echo "FAIL: recommendation still suggests 'gemini-3.1-pro' instead of a real alias" >&2
        return 1
    fi
}

# =============================================================================
# T35-5: BB / FL .env-load parity (positive control on the design intent)
# =============================================================================

@test "T35-5: BB entry.sh has the same .env loading pattern (parity baseline)" {
    grep -qE 'set[[:space:]]+-a[[:space:]]*;[[:space:]]*source[[:space:]]+\.env' \
        "$PROJECT_ROOT/.claude/skills/bridgebuilder-review/resources/entry.sh"
}

# =============================================================================
# T35-6: Issue D' coverage already enforced by T3.3 corpus
# =============================================================================

@test "T35-6: extract_json_content regression corpus exists (Issue D' coverage)" {
    [[ -f "$PROJECT_ROOT/tests/unit/cycle-109-t3-3-flatline-extract-json-content.bats" ]]
}
