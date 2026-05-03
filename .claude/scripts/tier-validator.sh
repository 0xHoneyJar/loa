#!/usr/bin/env bash
# =============================================================================
# tier-validator.sh — cycle-098 Sprint 1C (CC-10 enforcement).
#
# Per PRD §Supported Configuration Tiers + SDD §1.4.1:
#   Tier 0: Baseline — no agent-network primitives enabled
#   Tier 1: L4 + L7 (Identity & Trust)
#   Tier 2: L2 + L4 + L6 + L7 (Resource & Handoff)
#   Tier 3: L1 + L2 + L3 + L4 + L6 + L7 (Adjudication & Orchestration)
#   Tier 4: All 7 (L1..L7) — Full Network
#
# Behavior:
#   At Loa boot or skill load, inspect `.loa.config.yaml` for enabled
#   primitives; match the enabled set against the 5 supported tiers above;
#   apply tier_enforcement_mode (warn|refuse).
#
# Default: warn (Operator Option C per
#   cycles/cycle-098-agent-network/decisions/tier-enforcement-default.md).
#
# Outputs:
#   stdout: `tier-N` identifier (when supported) OR `unsupported` token
#   stderr: WARNING / ERROR message (when applicable)
#
# Exit codes:
#   0 = supported tier
#   1 = unsupported, mode=warn
#   2 = unsupported, mode=refuse (or invalid args / config errors)
#
# Subcommands:
#   check                       (default) Inspect config, classify, apply mode
#   list-supported              Print the 5 supported tier identifiers + labels
#   --help|-h                   Usage
#
# Env vars:
#   LOA_CONFIG_FILE             Override .loa.config.yaml path (test fixture)
# =============================================================================

set -euo pipefail

_TV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_TV_REPO_ROOT="$(cd "$_TV_DIR/.." && pwd)"
_TV_CONFIG="${LOA_CONFIG_FILE:-${_TV_REPO_ROOT}/.loa.config.yaml}"

_tv_log() { echo "[tier-validator] $*" >&2; }

# -----------------------------------------------------------------------------
# _tv_read_enabled — emit one enabled primitive per line (e.g. "L1\nL4\n").
# Reads .loa.config.yaml::agent_network.primitives.<L?>.enabled. Missing config
# returns nothing (= Tier 0).
# -----------------------------------------------------------------------------
_tv_read_enabled() {
    local config="$1"
    [[ -f "$config" ]] || return 0
    if command -v yq >/dev/null 2>&1; then
        local p
        for p in L1 L2 L3 L4 L5 L6 L7; do
            local v
            v=$(yq -r ".agent_network.primitives.${p}.enabled // false" "$config" 2>/dev/null)
            if [[ "$v" == "true" ]]; then
                echo "$p"
            fi
        done
        return 0
    fi
    # Python fallback when yq is unavailable.
    LOA_CONFIG_PATH="$config" python3 - <<'PY'
import os, sys
try:
    import yaml
except ImportError:
    sys.exit(0)
path = os.environ.get("LOA_CONFIG_PATH", "")
try:
    with open(path) as f:
        doc = yaml.safe_load(f) or {}
except Exception:
    sys.exit(0)
primitives = (doc.get("agent_network") or {}).get("primitives") or {}
for p in ("L1", "L2", "L3", "L4", "L5", "L6", "L7"):
    spec = primitives.get(p) or {}
    if spec.get("enabled") is True:
        print(p)
PY
}

# -----------------------------------------------------------------------------
# _tv_read_mode — emit the configured tier_enforcement_mode (default: warn).
# -----------------------------------------------------------------------------
_tv_read_mode() {
    local config="$1"
    if [[ -f "$config" ]] && command -v yq >/dev/null 2>&1; then
        local m
        m=$(yq -r '.tier_enforcement_mode // "warn"' "$config" 2>/dev/null)
        case "$m" in
            warn|refuse) echo "$m"; return 0 ;;
            null|"") echo "warn"; return 0 ;;
            *) echo "warn"; return 0 ;;
        esac
    fi
    echo "warn"
}

# -----------------------------------------------------------------------------
# _tv_classify <enabled-set>
# Argument: space-separated sorted list of enabled primitives.
# Emits the tier identifier (tier-0..tier-4) on stdout when supported,
# OR the literal "unsupported" when not.
# -----------------------------------------------------------------------------
_tv_classify() {
    local enabled="$1"
    case "$enabled" in
        "")                    echo "tier-0" ;;  # Baseline
        "L4 L7")               echo "tier-1" ;;
        "L2 L4 L6 L7")         echo "tier-2" ;;
        "L1 L2 L3 L4 L6 L7")   echo "tier-3" ;;
        "L1 L2 L3 L4 L5 L6 L7") echo "tier-4" ;;
        *)                     echo "unsupported" ;;
    esac
}

# -----------------------------------------------------------------------------
# tier_validator_check — main entrypoint.
# -----------------------------------------------------------------------------
tier_validator_check() {
    local enabled tier mode
    # Sort for deterministic comparison against canonical sets.
    enabled="$(_tv_read_enabled "$_TV_CONFIG" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ *$//')"
    tier="$(_tv_classify "$enabled")"
    mode="$(_tv_read_mode "$_TV_CONFIG")"

    if [[ "$tier" != "unsupported" ]]; then
        # Print tier identifier + label
        local label=""
        case "$tier" in
            tier-0) label="Baseline" ;;
            tier-1) label="Identity & Trust" ;;
            tier-2) label="Resource & Handoff" ;;
            tier-3) label="Adjudication & Orchestration" ;;
            tier-4) label="Full Network" ;;
        esac
        echo "${tier} (${label})"
        return 0
    fi

    # Unsupported: format diagnostic + apply mode.
    local enabled_pretty="${enabled:-(none)}"
    local hint='Run "/loa diag config-tier" for details.'
    case "$mode" in
        refuse)
            echo "unsupported"
            _tv_log "ERROR: Configuration tier is unsupported (enabled: ${enabled_pretty}). Only tiers 0-4 are tested. ${hint}"
            return 2
            ;;
        *)
            echo "unsupported"
            _tv_log "WARNING: Configuration tier is unsupported (enabled: ${enabled_pretty}). Only tiers 0-4 are tested. cycle-099 will refuse boot on unsupported tiers (planned migration). ${hint}"
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# tier_validator_list_supported — print the 5 supported tiers + their composition
# -----------------------------------------------------------------------------
tier_validator_list_supported() {
    cat <<'EOF'
tier-0: Baseline (no primitives enabled)
tier-1: Identity & Trust (L4 + L7)
tier-2: Resource & Handoff (L2 + L4 + L6 + L7)
tier-3: Adjudication & Orchestration (L1 + L2 + L3 + L4 + L6 + L7)
tier-4: Full Network (L1 + L2 + L3 + L4 + L5 + L6 + L7)
EOF
}

# -----------------------------------------------------------------------------
# CLI dispatcher
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-check}" in
        check)
            tier_validator_check
            ;;
        list-supported)
            tier_validator_list_supported
            ;;
        --help|-h)
            cat <<'EOF'
Usage: tier-validator.sh [check|list-supported]

  check             Inspect .loa.config.yaml; classify enabled primitives
                    against supported tiers; apply tier_enforcement_mode.
                    Exit 0 = supported; 1 = unsupported (warn);
                    2 = unsupported (refuse) or error.
  list-supported    Print the 5 supported tiers and their compositions.

Env:
  LOA_CONFIG_FILE   Override path to .loa.config.yaml (test fixture).
EOF
            ;;
        *)
            echo "Unknown command: $1" >&2
            exit 2
            ;;
    esac
fi
