#!/usr/bin/env bash
# =============================================================================
# budget-reconcile-install.sh — install/uninstall L2 reconciliation cron entry
#
# cycle-098 Sprint 2B — operator-facing helper for crontab integration.
#
# Subcommands:
#   install    Append (idempotent) the L2 reconciliation cron line to the
#              current user's crontab. Cadence read from
#              .loa.config.yaml::cost_budget_enforcer.reconciliation.interval_hours
#              (default 6). Marker comment makes the line uninstallable.
#   uninstall  Remove the L2 reconciliation cron line by marker comment.
#   status     Print whether the cron entry is installed.
#   show       Print the cron line that WOULD be installed (no side effects).
#
# Usage examples:
#   .claude/scripts/budget/budget-reconcile-install.sh status
#   .claude/scripts/budget/budget-reconcile-install.sh install
#   .claude/scripts/budget/budget-reconcile-install.sh uninstall
#
# Marker convention: `# loa-cycle098-l2-reconcile  managed entry`
# =============================================================================

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "${_SCRIPT_DIR}/../../.." && pwd)"
_CRON_ENTRY_SCRIPT="${_REPO_ROOT}/.claude/scripts/budget/budget-reconcile-cron.sh"
_LOG_PATH="${_REPO_ROOT}/.run/cost-budget-cron.log"
MARKER="# loa-cycle098-l2-reconcile  managed entry"

usage() {
    sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
    exit 0
}

# Read interval_hours from config; default 6.
read_interval_hours() {
    local config="${LOA_BUDGET_CONFIG_FILE:-${_REPO_ROOT}/.loa.config.yaml}"
    if [[ ! -f "$config" ]]; then
        echo "6"
        return 0
    fi
    if command -v yq >/dev/null 2>&1; then
        local v
        v="$(yq -r '.cost_budget_enforcer.reconciliation.interval_hours // 6' "$config" 2>/dev/null || echo 6)"
        [[ "$v" == "null" || -z "$v" ]] && v=6
        echo "$v"
        return 0
    fi
    python3 - "$config" <<'PY' 2>/dev/null || echo 6
import sys
try:
    import yaml
except ImportError:
    print(6)
    sys.exit(0)
try:
    with open(sys.argv[1]) as f:
        doc = yaml.safe_load(f) or {}
except Exception:
    print(6)
    sys.exit(0)
v = ((doc.get('cost_budget_enforcer') or {}).get('reconciliation') or {}).get('interval_hours', 6)
print(v if v else 6)
PY
}

# Build the cron line.
build_cron_line() {
    local hours
    hours="$(read_interval_hours)"
    if ! [[ "$hours" =~ ^[0-9]+$ ]] || (( hours < 1 || hours > 24 )); then
        echo "Invalid reconciliation.interval_hours: $hours (must be 1..24)" >&2
        return 1
    fi
    # Cron expression: every <hours> hours.
    local cron_expr
    if (( hours == 24 )); then
        cron_expr="0 0 * * *"
    else
        cron_expr="0 */${hours} * * *"
    fi
    echo "${cron_expr} ${_CRON_ENTRY_SCRIPT} >> ${_LOG_PATH} 2>&1  ${MARKER}"
}

cmd_show() {
    build_cron_line
}

cmd_status() {
    if ! command -v crontab >/dev/null 2>&1; then
        echo "crontab not available on this system"
        return 1
    fi
    if crontab -l 2>/dev/null | grep -qF "$MARKER"; then
        echo "INSTALLED"
        crontab -l 2>/dev/null | grep -F "$MARKER"
        return 0
    else
        echo "NOT-INSTALLED"
        return 0
    fi
}

cmd_install() {
    if ! command -v crontab >/dev/null 2>&1; then
        echo "crontab not available on this system; cannot install cron entry" >&2
        return 1
    fi
    [[ -x "$_CRON_ENTRY_SCRIPT" ]] || chmod +x "$_CRON_ENTRY_SCRIPT" 2>/dev/null || true
    local desired
    desired="$(build_cron_line)"
    local existing
    existing="$(crontab -l 2>/dev/null || true)"
    if printf '%s\n' "$existing" | grep -qF "$MARKER"; then
        # Already installed. Idempotent: replace the line if cadence changed.
        local current_line
        current_line="$(printf '%s\n' "$existing" | grep -F "$MARKER" | head -1)"
        if [[ "$current_line" == "$desired" ]]; then
            echo "Already installed (cadence matches): $desired"
            return 0
        fi
        echo "Cadence changed; updating cron line."
        echo "  was:  $current_line"
        echo "  now:  $desired"
        local updated
        updated="$(printf '%s\n' "$existing" | grep -vF "$MARKER")"
        printf '%s\n%s\n' "$updated" "$desired" | crontab -
        return 0
    fi
    # Append new line.
    printf '%s\n%s\n' "$existing" "$desired" | crontab -
    echo "Installed: $desired"
}

cmd_uninstall() {
    if ! command -v crontab >/dev/null 2>&1; then
        echo "crontab not available on this system" >&2
        return 1
    fi
    local existing
    existing="$(crontab -l 2>/dev/null || true)"
    if ! printf '%s\n' "$existing" | grep -qF "$MARKER"; then
        echo "Not installed; nothing to remove."
        return 0
    fi
    local updated
    updated="$(printf '%s\n' "$existing" | grep -vF "$MARKER")"
    printf '%s\n' "$updated" | crontab -
    echo "Uninstalled."
}

# Main.
if [[ $# -eq 0 ]]; then
    usage
fi
case "$1" in
    install)   cmd_install ;;
    uninstall) cmd_uninstall ;;
    status)    cmd_status ;;
    show)      cmd_show ;;
    --help|-h) usage ;;
    *) echo "unknown subcommand: $1" >&2; exit 2 ;;
esac
