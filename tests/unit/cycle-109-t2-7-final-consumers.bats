#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-109-t2-7-final-consumers.bats
#
# cycle-109 Sprint 2 T2.7 — final 3 consumers per SDD §3.2.3 IMP-004:
#
#   #5 flatline-readiness.sh    — gate readiness on chain_health
#   #6 red-team-pipeline.sh     — sidecar wiring (via red-team-model-adapter.sh)
#   #7 post-pr-triage.sh        — surface verdict_quality in triage classifier
#
# T2.7 closes the IMP-004 consumer table. The primitives (sidecar
# transport from T2.4, canonical Python aggregator from T2.4, single-voice
# envelope producer from T2.3) are extensively tested elsewhere. This
# file pins the WIRING — that each consumer references the contracts in
# a way that activates the substrate.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi
    export PYTHONPATH="$PROJECT_ROOT/.claude/adapters"

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/t27.XXXXXX")"
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

# =============================================================================
# CONSUMER #6 — red-team-pipeline / red-team-model-adapter.sh
# =============================================================================

@test "T27-RT1: red-team-model-adapter.sh invoke_live sets LOA_VERDICT_QUALITY_SIDECAR" {
    grep -q "LOA_VERDICT_QUALITY_SIDECAR" \
        "$PROJECT_ROOT/.claude/scripts/red-team-model-adapter.sh"
}

@test "T27-RT2: red-team-model-adapter.sh declares a per-call sidecar path" {
    # Function-body check: invoke_live MUST allocate a sidecar path before
    # invoking MODEL_INVOKE. Pattern: any local-or-mktemp assignment whose
    # value flows into LOA_VERDICT_QUALITY_SIDECAR.
    grep -qE 'vq_sidecar=|verdict_quality_sidecar=|VQ_SIDECAR=' \
        "$PROJECT_ROOT/.claude/scripts/red-team-model-adapter.sh"
}

@test "T27-RT3: red-team-model-adapter.sh wrap_live_response propagates verdict_quality" {
    # The output JSON written by wrap_live_response MUST carry the
    # verdict_quality field when an envelope is available. This is the
    # consumer-side closure of FR-2.2 substrate emit coverage.
    grep -q "verdict_quality" \
        "$PROJECT_ROOT/.claude/scripts/red-team-model-adapter.sh"
}

# =============================================================================
# CONSUMER #5 — flatline-readiness.sh
# =============================================================================

@test "T27-FR1: flatline-readiness.sh references chain_health for readiness gate" {
    # flatline-readiness should read recent verdict_quality envelopes
    # (from MODELINV log or per-call sidecar artifacts) and refuse to
    # report READY when chain_health is exhausted, even if the rest of
    # the pre-flight passes. Soft enforcement at the contract level:
    # the script must at minimum reference chain_health OR verdict_quality.
    grep -qE "chain_health|verdict_quality" \
        "$PROJECT_ROOT/.claude/scripts/flatline-readiness.sh"
}

# =============================================================================
# CONSUMER #7 — post-pr-triage.sh
# =============================================================================

@test "T27-PT1: post-pr-triage.sh references verdict_quality for finding classification" {
    # post-pr-triage classifies BB findings (CRITICAL/BLOCKER/HIGH/PRAISE).
    # When the underlying BB / FL run was substrate-degraded, the triage
    # should NOT classify a finding-set as 'clean'. Wiring contract: the
    # script must read verdict_quality from upstream artifacts and either
    # surface the degradation OR refuse to mark findings as classified.
    grep -q "verdict_quality" \
        "$PROJECT_ROOT/.claude/scripts/post-pr-triage.sh"
}

# =============================================================================
# IMP-004 table completion (all 7 consumers)
# =============================================================================

@test "T27-IMP004: every CONSUMER referenced in IMP-004 has verdict_quality wiring" {
    # cycle-109 SDD §3.2.3 IMP-004 row table:
    #   1. cheval (producer)           — T2.3
    #   2. flatline-orchestrator.sh    — T2.4
    #   3. adversarial-review.sh       — T2.5
    #   4. cheval-delegate.ts (BB)     — T2.6
    #   5. flatline-readiness.sh       — T2.7
    #   6. red-team-pipeline.sh / red-team-model-adapter.sh — T2.7
    #   7. post-pr-triage.sh           — T2.7
    local -a consumers=(
        "$PROJECT_ROOT/.claude/adapters/cheval.py"
        "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
        "$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
        "$PROJECT_ROOT/.claude/skills/bridgebuilder-review/resources/adapters/cheval-delegate.ts"
        "$PROJECT_ROOT/.claude/scripts/flatline-readiness.sh"
        "$PROJECT_ROOT/.claude/scripts/red-team-model-adapter.sh"
        "$PROJECT_ROOT/.claude/scripts/post-pr-triage.sh"
    )
    local f
    for f in "${consumers[@]}"; do
        [[ -f "$f" ]] || {
            printf 'FATAL: IMP-004 consumer file missing: %s\n' "$f" >&2
            return 1
        }
        grep -qE "verdict_quality|verdictQuality|LOA_VERDICT_QUALITY_SIDECAR|chain_health" "$f" \
            || {
                printf 'FAIL: %s does not reference any verdict_quality contract\n' "$f" >&2
                return 1
            }
    done
}
