#!/usr/bin/env bash
# =============================================================================
# tools/model-economy-roll-up.sh
# =============================================================================
# cycle-112 Sprint 1 (#166) T1.3 — model-economy roll-up CLI shim (FR-1).
#
# Surfaces operator-facing model-economy roll-up by aggregating
# .run/model-invoke.jsonl over a configurable window. Shells out to the
# canonical Python aggregator at .claude/adapters/loa_cheval/economy.py
# (single canonical writer per SDD §5.2.1 — bash never reimplements
# aggregation logic).
#
# Usage:
#   tools/model-economy-roll-up.sh
#   tools/model-economy-roll-up.sh --window 7d
#   tools/model-economy-roll-up.sh --json
#   tools/model-economy-roll-up.sh --skill /review-sprint
#   tools/model-economy-roll-up.sh --model claude-opus-4-7
#   tools/model-economy-roll-up.sh --cost-snapshot HEAD~10
#
# NFR-Perf-1: <5s for 30d window on 100K-entry log.
# NFR-Sec-1: output piped through log-redactor before stdout (defense in
#            depth — MODELINV writer already redacts on write).
#
# Exit codes (per SDD §5.1):
#   0  success
#   2  invalid args
#   3  log unreadable / model-config.yaml unreadable
#   4  schema-validation failure on --json mode
#   5  --cost-snapshot <ref> invalid git ref
#  64  python3 missing on PATH
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHONPATH="$PROJECT_ROOT/.claude/adapters${PYTHONPATH:+:$PYTHONPATH}"
export PYTHONPATH

DEFAULT_LOG_PATH="$PROJECT_ROOT/.run/model-invoke.jsonl"
DEFAULT_MODEL_CONFIG="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
REDACTOR="$PROJECT_ROOT/.claude/scripts/lib/log-redactor.sh"

if ! command -v python3 >/dev/null 2>&1; then
    echo "[model-economy-roll-up] error: python3 not found on PATH" >&2
    exit 64
fi

ARGS=("$@")

# Inject defaults when caller didn't supply --log-path / --model-config.
HAS_LOG_PATH=false
HAS_MODEL_CONFIG=false
for a in "${ARGS[@]}"; do
    case "$a" in
        --log-path) HAS_LOG_PATH=true ;;
        --model-config) HAS_MODEL_CONFIG=true ;;
    esac
done
if [[ "$HAS_LOG_PATH" == "false" ]]; then
    ARGS+=("--log-path" "$DEFAULT_LOG_PATH")
fi
if [[ "$HAS_MODEL_CONFIG" == "false" ]]; then
    ARGS+=("--model-config" "$DEFAULT_MODEL_CONFIG")
fi

run_aggregator() {
    python3 -m loa_cheval.economy "${ARGS[@]}"
}

# NFR-Sec-1: pipe stdout through log-redactor when present. Stderr passes
# through untouched so error messages remain visible to operators.
if [[ -x "$REDACTOR" ]]; then
    set +e
    OUTPUT="$(run_aggregator)"
    RC=$?
    set -e
    if [[ -n "$OUTPUT" ]]; then
        printf '%s' "$OUTPUT" | "$REDACTOR"
        # Preserve trailing newline shape of upstream stdout.
        case "$OUTPUT" in
            *$'\n') ;;
            *) printf '\n' ;;
        esac
    fi
    exit "$RC"
else
    run_aggregator
fi
