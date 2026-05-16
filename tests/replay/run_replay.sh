#!/usr/bin/env bash
# =============================================================================
# tests/replay/run_replay.sh
#
# cycle-103 sprint-2 T2.1 — operator-facing wrapper for the KF-002 layer 2
# empirical replay. Handles the LOA_RUN_LIVE_TESTS gate, credential
# pre-flight, budget warning, and dispatches pytest.
#
# Usage:
#   tests/replay/run_replay.sh                # dry-run (gated; tells you how to run live)
#   LOA_RUN_LIVE_TESTS=1 tests/replay/run_replay.sh
#                                            # live run (consumes ~$3 of API budget)
#
# Exit codes:
#   0  replay complete (or correctly skipped in dry-run mode)
#   1  credentials missing or other pre-flight failure
#   2  pytest run failed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$PROJECT_ROOT"

if [[ "${LOA_RUN_LIVE_TESTS:-}" != "1" ]]; then
    cat <<'EOF'
DRY-RUN MODE
============
LOA_RUN_LIVE_TESTS is unset. All replay cells will be skipped.

To run live (consumes ~$3 of Anthropic API budget):

  ANTHROPIC_API_KEY=sk-ant-... \
  LOA_RUN_LIVE_TESTS=1 \
  tests/replay/run_replay.sh

Output:
  - Per-trial JSONL at: grimoires/loa/cycles/cycle-103-provider-unification/sprint-2-corpus/results-<timestamp>.jsonl
  - Disposition summary alongside: ...-<timestamp>.summary.json

Running offline collection check now to verify the scaffold is well-formed...
EOF
    python3 -m pytest tests/replay/test_opus_empty_content_thresholds.py --collect-only -q 2>&1 \
        | tail -5
    echo ""
    echo "Scaffold OK. Re-run with LOA_RUN_LIVE_TESTS=1 to execute live."
    exit 0
fi

# Live-mode pre-flight checks.
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "ERROR: ANTHROPIC_API_KEY required for live replay." >&2
    echo "Set: export ANTHROPIC_API_KEY=sk-ant-..." >&2
    exit 1
fi

# Budget warning. Default 150 cells × ~$0.02 = ~$3.
echo "============================================================"
echo "LIVE REPLAY — KF-002 LAYER 2 (cycle-103 sprint-2 T2.1)"
echo "============================================================"
echo "Estimated API budget: ~\$3 USD (Anthropic claude-opus-4.7)"
echo "Matrix: 5 input sizes × 5 trials × 3 thinking × 2 max_tokens"
echo "      = 150 live calls"
echo ""
echo "Press Ctrl-C within 5 seconds to abort..."
sleep 5
echo "Proceeding..."
echo ""

# Run pytest. Use --tb=line to keep per-cell output readable across 150 tests.
# Use -p no:cacheprovider so the long run doesn't trip pytest cache invalidation
# halfway through.
python3 -m pytest \
    tests/replay/test_opus_empty_content_thresholds.py \
    -v \
    --tb=line \
    -p no:cacheprovider \
    2>&1 \
    || {
        echo ""
        echo "ERROR: pytest run failed. Check the JSONL output for partial results:" >&2
        ls -lt grimoires/loa/cycles/cycle-103-provider-unification/sprint-2-corpus/results-*.jsonl 2>/dev/null | head -3 >&2 || true
        exit 2
    }

echo ""
echo "============================================================"
echo "REPLAY COMPLETE"
echo "============================================================"
echo "Results: grimoires/loa/cycles/cycle-103-provider-unification/sprint-2-corpus/"
ls -lt grimoires/loa/cycles/cycle-103-provider-unification/sprint-2-corpus/results-*.jsonl 2>/dev/null | head -2
ls -lt grimoires/loa/cycles/cycle-103-provider-unification/sprint-2-corpus/results-*.summary.json 2>/dev/null | head -2
echo ""
echo "Next step: review the .summary.json file. The 'disposition' field is"
echo "either 'structural' (apply T2.2a) or 'vendor-side' (apply T2.2b)."
