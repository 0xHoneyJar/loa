#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-109-t4-9-repro-fixtures.bats
#
# cycle-109 Sprint 4 T4.9 — repro fixtures for #866 / #823 (KF-002
# layer-1). Pre-Sprint-4 the substrate empty-contented on oversized
# inputs; post-Sprint-4 the chunking package + streaming-with-recovery
# closes the failure class.
#
# Each fixture pins:
#   1. Fixture metadata exists and validates (issue, ceiling, sizes)
#   2. The substrate would route through chunking given the documented
#      input size + ceiling (estimated_input > ceiling × 0.7)
#   3. KF-002 class + layer + G-2 relevance flags pin the bug class
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/cycle-109/sprint-4-repro"
}

# =============================================================================
# RP-1..2: Fixture corpus complete
# =============================================================================

@test "RP1: #866 fixture file exists + parses" {
    [[ -f "$FIXTURE_DIR/issue-866-large-doc-empty-content.json" ]]
    jq empty "$FIXTURE_DIR/issue-866-large-doc-empty-content.json"
}

@test "RP2: #823 fixture file exists + parses" {
    [[ -f "$FIXTURE_DIR/issue-823-empty-content-40k.json" ]]
    jq empty "$FIXTURE_DIR/issue-823-empty-content-40k.json"
}

# =============================================================================
# RP-3..4: Each fixture documents the should_chunk decision
# =============================================================================

@test "RP3: #866 fixture asserts should_chunk = true" {
    local should
    should=$(jq -r '.should_chunk' "$FIXTURE_DIR/issue-866-large-doc-empty-content.json")
    [ "$should" = "true" ]
}

@test "RP4: #823 fixture asserts should_chunk = true" {
    local should
    should=$(jq -r '.should_chunk' "$FIXTURE_DIR/issue-823-empty-content-40k.json")
    [ "$should" = "true" ]
}

# =============================================================================
# RP-5: Both fixtures cross-reference KF-002 layer-1 (G-2 closure path)
# =============================================================================

@test "RP5: both fixtures flag KF-002 layer-1 + G-2 relevance" {
    for f in "$FIXTURE_DIR/issue-866-large-doc-empty-content.json" \
             "$FIXTURE_DIR/issue-823-empty-content-40k.json"; do
        local kf_class kf_layer g2
        kf_class=$(jq -r '.kf_002_class' "$f")
        kf_layer=$(jq -r '.kf_002_layer' "$f")
        g2=$(jq -r '.g_2_relevant' "$f")
        [ "$kf_class" = "true" ]
        [ "$kf_layer" = "1" ]
        [ "$g2" = "true" ]
    done
}

# =============================================================================
# RP-6: chunking budget math holds (estimated_input > ceiling × 0.7)
# =============================================================================

@test "RP6: each fixture's input would route through chunking per pre-flight" {
    for f in "$FIXTURE_DIR/issue-866-large-doc-empty-content.json" \
             "$FIXTURE_DIR/issue-823-empty-content-40k.json"; do
        local est_input ceiling
        est_input=$(jq -r '.estimated_input_tokens' "$f")
        ceiling=$(jq -r '.effective_input_ceiling' "$f")
        # Compare est_input > ceiling × 0.7 using awk (bash can't do float)
        result=$(awk -v est="$est_input" -v ceil="$ceiling" \
            'BEGIN { print (est > ceil * 0.7) ? "true" : "false" }')
        [ "$result" = "true" ] || {
            echo "FAIL: $f — est_input=$est_input not > ceiling × 0.7 (= $(awk -v c="$ceiling" 'BEGIN{print c*0.7}'))" >&2
            return 1
        }
    done
}

# =============================================================================
# RP-7: substrate post-Sprint-4 has the chunking + streaming-recovery modules
# =============================================================================

@test "RP7: loa_cheval.chunking package importable (post-Sprint-4 substrate present)" {
    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi
    PYTHONPATH="$PROJECT_ROOT/.claude/adapters" "$PYTHON_BIN" -c \
        "from loa_cheval.chunking import chunk_pr_for_review, aggregate_findings; \
         from loa_cheval.chunking.chunker import ChunkingExceeded; \
         from loa_cheval.streaming import StreamingRecoveryTracker, StreamingRecoveryConfig; \
         print('OK')"
}

# =============================================================================
# RP-8: Exit code 13 wired in cheval (post-T4.5)
# =============================================================================

@test "RP8: cheval.py declares CHUNKING_EXCEEDED = 13 exit code" {
    grep -q '"CHUNKING_EXCEEDED": 13' "$PROJECT_ROOT/.claude/adapters/cheval.py"
}
