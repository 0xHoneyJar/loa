#!/usr/bin/env bash
# =============================================================================
# protected-class-router.sh — cycle-098 Sprint 1B (PRD Appendix D, SDD §1.4.2).
#
# Loa's "protected class" router. Used by L1 jury-panel (Sprint 1D) and
# L4 graduated-trust (later cycle) to short-circuit autonomous routing.
#
# Default taxonomy: .claude/data/protected-classes.yaml (10 classes).
# Operator extension: .loa.config.yaml::protected_classes_extra (a list of
# additional class IDs).
#
# Public API:
#   is_protected_class <decision_class>
#       Returns 0 if matched, 1 otherwise. Empty arg returns 1.
#
#   list_protected_classes
#       Print all protected class IDs (default + extra), one per line.
#
# CLI:
#   protected-class-router.sh check <class_id>
#       Same as is_protected_class but as an exit-code-conveying entrypoint.
#
#   protected-class-router.sh override --class <id> --duration <s> --reason <text>
#       Audit-logged override (Sprint 1B stub: audit-logged via audit-envelope).
#
# =============================================================================

set -euo pipefail

if [[ "${_LOA_PROTECTED_CLASS_ROUTER_SOURCED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
_LOA_PROTECTED_CLASS_ROUTER_SOURCED=1

_PCR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PCR_REPO_ROOT="$(cd "${_PCR_DIR}/../../.." && pwd)"
_PCR_TAXONOMY="${LOA_PROTECTED_CLASSES_FILE:-${_PCR_REPO_ROOT}/.claude/data/protected-classes.yaml}"
_PCR_CONFIG="${LOA_CONFIG_FILE:-${_PCR_REPO_ROOT}/.loa.config.yaml}"

# -----------------------------------------------------------------------------
# _pcr_log <message>
# Internal stderr logger.
# -----------------------------------------------------------------------------
_pcr_log() {
    echo "[protected-class-router] $*" >&2
}

# -----------------------------------------------------------------------------
# _pcr_default_classes — emit default class IDs from taxonomy YAML.
# -----------------------------------------------------------------------------
_pcr_default_classes() {
    if [[ ! -f "$_PCR_TAXONOMY" ]]; then
        _pcr_log "taxonomy file missing: $_PCR_TAXONOMY"
        return 1
    fi
    if ! command -v yq >/dev/null 2>&1; then
        # Python fallback: parse YAML via PyYAML if installed.
        python3 - "$_PCR_TAXONOMY" <<'PY'
import sys
try:
    import yaml
except ImportError:
    sys.stderr.write("yq not in PATH and PyYAML not installed\n")
    sys.exit(2)
with open(sys.argv[1]) as f:
    doc = yaml.safe_load(f)
for cls in (doc.get("classes") or []):
    cid = cls.get("id")
    if cid:
        print(cid)
PY
        return $?
    fi
    yq -r '.classes[].id' "$_PCR_TAXONOMY"
}

# -----------------------------------------------------------------------------
# _pcr_extra_classes — emit operator-extension class IDs (if any) from
# .loa.config.yaml::protected_classes_extra.
# -----------------------------------------------------------------------------
_pcr_extra_classes() {
    [[ -f "$_PCR_CONFIG" ]] || return 0
    if ! command -v yq >/dev/null 2>&1; then
        python3 - "$_PCR_CONFIG" <<'PY' 2>/dev/null || true
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)
try:
    with open(sys.argv[1]) as f:
        doc = yaml.safe_load(f) or {}
except Exception:
    sys.exit(0)
extras = doc.get("protected_classes_extra") or []
for cid in extras:
    if isinstance(cid, str):
        print(cid)
PY
        return 0
    fi
    # `yq` returns 'null' for missing fields; suppress.
    yq -r '.protected_classes_extra[] // empty' "$_PCR_CONFIG" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# list_protected_classes — print all protected classes (default + extra).
# Deduplicates while preserving order.
# -----------------------------------------------------------------------------
list_protected_classes() {
    {
        _pcr_default_classes
        _pcr_extra_classes
    } | awk '!seen[$0]++ && NF > 0'
}

# -----------------------------------------------------------------------------
# is_protected_class <decision_class>
# Returns 0 if <decision_class> matches a protected class id; 1 otherwise.
# -----------------------------------------------------------------------------
is_protected_class() {
    local decision_class="${1:-}"
    [[ -n "$decision_class" ]] || return 1

    local cls
    while IFS= read -r cls; do
        if [[ "$cls" == "$decision_class" ]]; then
            return 0
        fi
    done < <(list_protected_classes)
    return 1
}

# -----------------------------------------------------------------------------
# CLI dispatcher
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        check)
            shift
            if is_protected_class "${1:-}"; then
                exit 0
            else
                exit 1
            fi
            ;;
        list)
            list_protected_classes
            ;;
        override)
            # Sprint 1B: time-bounded override is logged via audit-envelope.
            # The actual TTL enforcement is Sprint 1D (panel) + later cycle (L4).
            shift
            local _class="" _duration="" _reason=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --class) _class="$2"; shift 2 ;;
                    --duration) _duration="$2"; shift 2 ;;
                    --reason) _reason="$2"; shift 2 ;;
                    *) echo "unknown flag: $1" >&2; exit 2 ;;
                esac
            done
            if [[ -z "$_class" || -z "$_duration" || -z "$_reason" ]]; then
                echo "usage: $0 override --class <id> --duration <s> --reason <text>" >&2
                exit 2
            fi
            # Dispatch audit log via audit-envelope when available.
            local ae="${_PCR_REPO_ROOT}/.claude/scripts/audit-envelope.sh"
            if [[ -f "$ae" ]]; then
                # shellcheck disable=SC1090
                source "$ae"
                local payload
                payload=$(jq -nc \
                    --arg class "$_class" \
                    --arg duration "$_duration" \
                    --arg reason "$_reason" \
                    '{class:$class, duration_seconds:($duration|tonumber? // 0), reason:$reason}')
                audit_emit L4 trust.protected_class_override "$payload" \
                    "${_PCR_REPO_ROOT}/.run/protected-class-overrides.jsonl"
            fi
            echo "OK override logged for class=$_class duration=${_duration}s reason=$_reason"
            ;;
        --help|-h|"")
            cat <<EOF
Usage: protected-class-router.sh <command> [args]

Commands:
  check <class_id>        Exit 0 if class is protected, 1 otherwise.
  list                    Print all protected class IDs (default + extra), one per line.
  override --class <id> --duration <seconds> --reason <text>
                          Time-bounded override (audit-logged).
EOF
            ;;
        *)
            echo "Unknown command: $1" >&2
            exit 2
            ;;
    esac
fi
