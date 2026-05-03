#!/usr/bin/env bash
# =============================================================================
# budget-reconcile-cron.sh — L2 reconciliation cron entrypoint (Sprint 2B)
#
# cycle-098 Sprint 2B — un-deferred reconciliation cron per SKP-005.
#
# Designed to be invoked from a crontab entry every 6h (default cadence):
#
#   0 */6 * * * /path/to/.claude/scripts/budget/budget-reconcile-cron.sh \
#     >> /path/to/repo/.run/cost-budget-cron.log 2>&1
#
# Behavior:
#   - Sources cost-budget-enforcer-lib.sh
#   - Iterates over configured providers (or "aggregate" default)
#   - Runs budget_reconcile per provider
#   - Acquires flock per repo to prevent overlapping invocations
#   - Exits non-zero if any provider's reconciliation emits a BLOCKER
#
# Flags:
#   --provider <id>       Reconcile a single provider (default: all configured)
#   --force-reason <text> Operator force-reconcile with audit-logged reason
#   --dry-run             Print intent; no audit-log writes (useful for ops)
#   --once                Single-shot (default cron behavior)
#   --help                Show usage
# =============================================================================

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "${_SCRIPT_DIR}/../../.." && pwd)"

usage() {
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
    exit 0
}

# Parse args.
PROVIDER=""
FORCE_REASON=""
DRY_RUN=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --provider) PROVIDER="$2"; shift 2 ;;
        --force-reason) FORCE_REASON="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --once) shift ;;
        --help|-h) usage ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

# Source the lib (idempotent).
# shellcheck source=../lib/cost-budget-enforcer-lib.sh
source "${_REPO_ROOT}/.claude/scripts/lib/cost-budget-enforcer-lib.sh"

# Resolve the lock + log paths.
RECONCILE_LOCK="${LOA_BUDGET_RECONCILE_LOCK:-${_REPO_ROOT}/.run/budget-reconcile.lock}"
mkdir -p "$(dirname "$RECONCILE_LOCK")"
: > "$RECONCILE_LOCK" 2>/dev/null || touch "$RECONCILE_LOCK"

_audit_require_flock || exit 1

# Determine providers to reconcile.
providers=()
if [[ -n "$PROVIDER" ]]; then
    providers=("$PROVIDER")
else
    # Read configured providers from .loa.config.yaml::cost_budget_enforcer.providers
    # Fall back to "aggregate" if none configured.
    config_providers="$(_l2_config_get '.cost_budget_enforcer.providers // []' '' 2>/dev/null || true)"
    if [[ -n "$config_providers" && "$config_providers" != "[]" && "$config_providers" != "null" ]]; then
        # Parse YAML list. yq path returns the YAML representation; we want a
        # newline-separated list of provider ids.
        if command -v yq >/dev/null 2>&1; then
            mapfile -t providers < <(yq -r '.cost_budget_enforcer.providers[] // empty' "$(_l2_config_path)" 2>/dev/null || true)
        fi
    fi
    if [[ ${#providers[@]} -eq 0 ]]; then
        providers=("aggregate")
    fi
fi

overall_status=0

# Wrap the reconcile loop in a single flock so concurrent cron firings cannot
# stomp each other. Wait up to 5min for the lock (cron runs every 6h, so 5min
# is generous but bounded).
{
    if ! flock -w 300 9; then
        echo "[budget-reconcile-cron] could not acquire lock at $RECONCILE_LOCK (timeout 300s)" >&2
        exit 1
    fi

    for provider in ${providers[@]+"${providers[@]}"}; do
        if (( DRY_RUN )); then
            echo "[budget-reconcile-cron] DRY-RUN provider=$provider" >&2
            continue
        fi

        rc=0
        if [[ -n "$FORCE_REASON" ]]; then
            budget_reconcile --provider "$provider" --force-reason "$FORCE_REASON" || rc=$?
        else
            budget_reconcile --provider "$provider" || rc=$?
        fi

        if (( rc == 0 )); then
            echo "[budget-reconcile-cron] OK provider=$provider" >&2
        elif (( rc == 1 )); then
            # blocker emitted; log but continue with other providers.
            echo "[budget-reconcile-cron] BLOCKER provider=$provider — operator review required" >&2
            overall_status=1
        elif (( rc == 2 )); then
            # defer (e.g., 429); skip silently.
            echo "[budget-reconcile-cron] DEFER provider=$provider — billing API rate-limited; will retry next interval" >&2
        else
            echo "[budget-reconcile-cron] ERROR provider=$provider rc=$rc" >&2
            overall_status=1
        fi
    done
} 9>"$RECONCILE_LOCK"

exit "$overall_status"
