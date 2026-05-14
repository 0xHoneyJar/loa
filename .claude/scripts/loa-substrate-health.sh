#!/usr/bin/env bash
# =============================================================================
# .claude/scripts/loa-substrate-health.sh
# =============================================================================
# cycle-109 Sprint 5 T5.4 — substrate-health CLI shim (FR-5.4).
#
# Surfaces operator-facing substrate health by aggregating .run/model-invoke.jsonl
# over a configurable window. Shells out to the canonical Python aggregator
# at .claude/adapters/loa_cheval/health.py (single canonical writer per
# SDD §5.2.1 — bash never reimplements the aggregation logic).
#
# Usage:
#   .claude/scripts/loa-substrate-health.sh
#   .claude/scripts/loa-substrate-health.sh --window 7d
#   .claude/scripts/loa-substrate-health.sh --json
#   .claude/scripts/loa-substrate-health.sh --model claude-opus-4-7
#
# NFR-Perf-3: <2s for 24h window on 100K-entry log.
# NFR-Sec-3: output piped through log-redactor before stdout.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHONPATH="$PROJECT_ROOT/.claude/adapters${PYTHONPATH:+:$PYTHONPATH}"
export PYTHONPATH

# Default log path; --log-path overrides
DEFAULT_LOG_PATH="$PROJECT_ROOT/.run/model-invoke.jsonl"

# Forward args verbatim to the Python aggregator. Pipe stdout through
# the log-redactor (NFR-Sec-3) to scrub any rationale-borne secret shapes.
REDACTOR="$PROJECT_ROOT/.claude/scripts/lib/log-redactor.sh"

run_aggregator() {
    if [[ ! -e "$DEFAULT_LOG_PATH" ]] && [[ "$*" != *"--log-path"* ]]; then
        # No log yet — still emit a structurally-valid empty report so
        # callers don't break. The Python aggregator handles missing
        # files gracefully (returns zero invocations).
        :
    fi
    python3 -m loa_cheval.health "$@"
}

# Honor explicit log-path override; otherwise default
ARGS=("$@")
HAS_LOG_PATH=false
for a in "${ARGS[@]}"; do
    if [[ "$a" == "--log-path" ]]; then
        HAS_LOG_PATH=true
        break
    fi
done

if [[ "$HAS_LOG_PATH" == "false" ]]; then
    ARGS+=("--log-path" "$DEFAULT_LOG_PATH")
fi

if [[ -x "$REDACTOR" ]]; then
    run_aggregator "${ARGS[@]}" | "$REDACTOR"
else
    run_aggregator "${ARGS[@]}"
fi
