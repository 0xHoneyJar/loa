#!/usr/bin/env bash
# =============================================================================
# verdict-quality.sh — cycle-109 Sprint 2 T2.2 — bash twin for the
# loa_cheval.verdict.quality canonical classifier.
#
# Shells out to the Python canonical (no logic duplication) — drift is
# impossible by construction per SDD §5.2.1. The single Python entry-point
# at `loa_cheval.verdict.quality._cli_main` accepts the envelope JSON on
# stdin and prints either the status string (`compute` subcommand) or the
# validated+stamped envelope JSON (`emit` subcommand) on stdout.
#
# Public API (sourced):
#
#   verdict_quality_compute < envelope.json
#     Echoes the status enum value (APPROVED|DEGRADED|FAILED) to stdout.
#     Exit codes: 0 success; 2 invariant violation; 3 malformed JSON;
#     64 usage error.
#
#   verdict_quality_emit < envelope.json
#     Echoes the validated + status-stamped envelope JSON to stdout.
#     Same exit codes as compute.
#
# Public API (CLI):
#
#   ./verdict-quality.sh compute < envelope.json
#   ./verdict-quality.sh emit    < envelope.json
#
# Bash sources this script via:
#     source "$(dirname "$0")/lib/verdict-quality.sh"
#     status="$(echo "$envelope_json" | verdict_quality_compute)"
# =============================================================================

set -euo pipefail

if [[ "${_LOA_VERDICT_QUALITY_SOURCED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
_LOA_VERDICT_QUALITY_SOURCED=1

# Resolve the Python entry-point. The bash twin lives at
# `.claude/scripts/lib/verdict-quality.sh`; the Python module is at
# `.claude/adapters/loa_cheval/verdict/quality.py`. Sibling resolution:
_VQ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_VQ_REPO_ROOT="$(cd "${_VQ_DIR}/../../.." && pwd)"
_VQ_ADAPTERS_DIR="${_VQ_REPO_ROOT}/.claude/adapters"

_vq_python() {
    # Prefer the venv interpreter; fall back to system python3.
    local py
    if [[ -x "${_VQ_REPO_ROOT}/.venv/bin/python" ]]; then
        py="${_VQ_REPO_ROOT}/.venv/bin/python"
    else
        py="$(command -v python3)"
    fi
    PYTHONPATH="${_VQ_ADAPTERS_DIR}${PYTHONPATH:+:${PYTHONPATH}}" \
        "$py" -m loa_cheval.verdict.quality "$@"
}

# verdict_quality_compute — reads envelope JSON on stdin, prints status
# enum value to stdout. Caller captures via $(...).
verdict_quality_compute() {
    _vq_python compute
}

# verdict_quality_emit — reads envelope JSON on stdin, prints validated +
# status-stamped envelope JSON to stdout.
verdict_quality_emit() {
    _vq_python emit
}

# CLI mode: when executed directly, dispatch to the named subcommand.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 1 ]]; then
        echo "usage: verdict-quality.sh {compute|emit}" >&2
        exit 64
    fi
    case "$1" in
        compute) shift; verdict_quality_compute "$@" ;;
        emit)    shift; verdict_quality_emit "$@" ;;
        *)
            echo "usage: verdict-quality.sh {compute|emit}" >&2
            exit 64
            ;;
    esac
fi
