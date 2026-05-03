#!/usr/bin/env bash
# =============================================================================
# audit-snapshot-install.sh — install/uninstall daily snapshot cron entry
#
# cycle-098 Sprint 2C — operator-facing helper for the daily snapshot cron.
# Convention is identical to budget-reconcile-install.sh; one marker per
# cron entry. Daily run at 04:00 UTC by default (per SDD §3.7).
#
# Subcommands:
#   install     Append (idempotent) the daily snapshot cron line to the user's
#               crontab. Time read from
#               .loa.config.yaml::audit_snapshot.cron_expression
#               (default "0 4 * * *").
#   uninstall   Remove the snapshot cron line by marker comment.
#   status      Print whether the cron entry is installed.
#   show        Print the cron line that WOULD be installed (no side effects).
#
# Marker convention: `# loa-cycle098-audit-snapshot  managed entry`
# =============================================================================

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "${_SCRIPT_DIR}/../../.." && pwd)"
_SNAPSHOT_SCRIPT="${_REPO_ROOT}/.claude/scripts/audit/audit-snapshot.sh"
_LOG_PATH="${_REPO_ROOT}/.run/audit-snapshot-cron.log"
MARKER="# loa-cycle098-audit-snapshot  managed entry"

usage() {
    sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
    exit 0
}

read_cron_expr() {
    local config="${LOA_BUDGET_CONFIG_FILE:-${_REPO_ROOT}/.loa.config.yaml}"
    if [[ ! -f "$config" ]]; then
        echo "0 4 * * *"
        return 0
    fi
    if command -v yq >/dev/null 2>&1; then
        local v
        v="$(yq -r '.audit_snapshot.cron_expression // "0 4 * * *"' "$config" 2>/dev/null || echo "0 4 * * *")"
        [[ -z "$v" || "$v" == "null" ]] && v="0 4 * * *"
        echo "$v"
        return 0
    fi
    python3 - "$config" <<'PY' 2>/dev/null || echo "0 4 * * *"
import sys
try:
    import yaml
except ImportError:
    print("0 4 * * *")
    sys.exit(0)
try:
    with open(sys.argv[1]) as f:
        doc = yaml.safe_load(f) or {}
except Exception:
    print("0 4 * * *")
    sys.exit(0)
v = (doc.get('audit_snapshot') or {}).get('cron_expression', '0 4 * * *')
print(v if v else '0 4 * * *')
PY
}

# Validate cron expression (5 space-separated fields).
validate_cron_expr() {
    local expr="$1"
    local field_count
    field_count="$(echo "$expr" | awk '{print NF}')"
    if [[ "$field_count" != "5" ]]; then
        echo "Invalid cron expression: '$expr' (expected 5 space-separated fields)" >&2
        return 1
    fi
}

build_cron_line() {
    local expr
    expr="$(read_cron_expr)"
    validate_cron_expr "$expr" || return 1
    echo "${expr} ${_SNAPSHOT_SCRIPT} >> ${_LOG_PATH} 2>&1  ${MARKER}"
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
    fi
    echo "NOT-INSTALLED"
    return 0
}

cmd_install() {
    if ! command -v crontab >/dev/null 2>&1; then
        echo "crontab not available on this system" >&2
        return 1
    fi
    [[ -x "$_SNAPSHOT_SCRIPT" ]] || chmod +x "$_SNAPSHOT_SCRIPT" 2>/dev/null || true
    local desired
    desired="$(build_cron_line)" || return 1
    local existing
    existing="$(crontab -l 2>/dev/null || true)"
    if printf '%s\n' "$existing" | grep -qF "$MARKER"; then
        local current_line
        current_line="$(printf '%s\n' "$existing" | grep -F "$MARKER" | head -1)"
        if [[ "$current_line" == "$desired" ]]; then
            echo "Already installed (cadence matches): $desired"
            return 0
        fi
        echo "Schedule changed; updating cron line."
        echo "  was:  $current_line"
        echo "  now:  $desired"
        local updated
        updated="$(printf '%s\n' "$existing" | grep -vF "$MARKER")"
        printf '%s\n%s\n' "$updated" "$desired" | crontab -
        return 0
    fi
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
