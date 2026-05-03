#!/usr/bin/env bash
# =============================================================================
# budget-cli.sh — operator + caller-facing CLI for L2 cost-budget-enforcer
#
# cycle-098 Sprint 2D — thin CLI wrapper over cost-budget-enforcer-lib.sh.
#
# Subcommands:
#   verdict <estimated_usd> [--provider <id>] [--cycle-id <id>]
#       Pre-call gate. Stdout: verdict payload JSON.
#       Exit 0=allow/warn-90, 1=halt-100/halt-uncertainty.
#
#   usage [--provider <id>]
#       Read-only state query. Stdout: state JSON.
#
#   record <actual_usd> --provider <id> [--cycle-id <id>] [--model-id <id>]
#                                       [--verdict-ref <hash>]
#       Post-call accounting. Stdout: record envelope.
#
#   reconcile [--provider <id>] [--force-reason <text>]
#       Reconciliation event. Exit 0=OK, 1=BLOCKER, 2=DEFER.
#
#   --help, -h
#       Show usage.
# =============================================================================

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "${_SCRIPT_DIR}/../../.." && pwd)"

usage() {
    sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
    exit 0
}

if [[ $# -eq 0 ]]; then
    usage
fi

# shellcheck source=../lib/cost-budget-enforcer-lib.sh
source "${_REPO_ROOT}/.claude/scripts/lib/cost-budget-enforcer-lib.sh"

cmd="$1"
shift

case "$cmd" in
    verdict)   budget_verdict "$@" ;;
    usage)     budget_get_usage "$@" ;;
    record)    budget_record_call "$@" ;;
    reconcile) budget_reconcile "$@" ;;
    --help|-h) usage ;;
    *)         echo "unknown subcommand: $cmd" >&2; exit 2 ;;
esac
