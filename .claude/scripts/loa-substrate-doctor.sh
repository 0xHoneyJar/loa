#!/usr/bin/env bash
# =============================================================================
# .claude/scripts/loa-substrate-doctor.sh
# =============================================================================
# Cycle-110 sprint-2b2a T2.9 — `loa substrate doctor` CLI shim (FR-4.1 / FR-4.5).
#
# Operator-facing OAuth pre-flight probe before flipping
# `dispatch_preference: headless` in production. Shells out to the canonical
# Python implementation at `.claude/adapters/loa_cheval/doctor.py` so the
# probe-table + classification logic is single-sourced (bash never
# reimplements the per-CLI probe machinery).
#
# Usage:
#   .claude/scripts/loa-substrate-doctor.sh
#   .claude/scripts/loa-substrate-doctor.sh --json
#   .claude/scripts/loa-substrate-doctor.sh --provider anthropic
#   .claude/scripts/loa-substrate-doctor.sh --timeout 20
#
# NFR-Sec-3: per-probe timeout + < /dev/null + process-group kill -9
# + streaming-read with byte cap. ProcessLookupError-safe (C6 closure).
# NFR-Sec-4: fixed-template hints (no user-content interpolation, SKP-003).
# Exit codes:
#   0 — all probes return auth_state=ok (operator may flip dispatch_preference)
#   2 — one or more probes returned non-ok auth_state
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHONPATH="$PROJECT_ROOT/.claude/adapters${PYTHONPATH:+:$PYTHONPATH}"
export PYTHONPATH

# Forward args verbatim to the Python implementation.
exec python3 -m loa_cheval.doctor "$@"
