#!/usr/bin/env bash
# =============================================================================
# .claude/hooks/safety/zone-write-guard.sh
# =============================================================================
# cycle-106 sprint-1 T1.3 — PreToolUse hook for Write/Edit. Enforces the
# framework-zone vs project-zone boundary declared in
# grimoires/loa/zones.yaml. Blocks zone-violating writes with an
# operator-readable diagnostic.
#
# Decision matrix (SDD §3.1):
#   framework zone + project-work    → BLOCK
#   framework zone + update-loa      → ALLOW
#   framework zone + other actor     → BLOCK + log
#   project zone   + project-work    → ALLOW
#   project zone   + update-loa      → BLOCK
#   project zone   + other actor     → ALLOW
#   shared zone    + any actor       → ALLOW
#   unclassified path                → ALLOW (positive-declaration only)
#
# Actor identification (LOA_ACTOR env var):
#   - "project-work" — default (operator's day-to-day)
#   - "update-loa"   — set by .claude/scripts/update-loa.sh
#   - "sync-constructs" — set by sync-constructs.sh
#   - unset / other  — treated as "project-work"
#
# Escape hatches:
#   LOA_ZONE_GUARD_BYPASS=1  → ALLOW + stderr WARN + trajectory log
#   LOA_ZONE_GUARD_DISABLE=1 → ALLOW with no diagnostic (framework bootstrap only)
#
# Path input (Claude Code PreToolUse hook contract):
#   $CLAUDE_TOOL_FILE_PATH — the path being written
#   Falls back to $1 when run as a CLI for testing.
#
# Exit codes:
#   0 = ALLOW
#   1 = BLOCK (Claude Code: refuses the tool call)
#   2 = bad config (missing zones.yaml + LOA_REQUIRE_ZONES=1, malformed YAML)
#
# Tested by tests/unit/zone-write-guard.bats (ZWG-T1..T12).
# =============================================================================

set -uo pipefail
# NB: don't set -e — we need to handle missing files / malformed YAML
# gracefully without aborting the hook.

# ---- early exits ----------------------------------------------------------

if [[ "${LOA_ZONE_GUARD_DISABLE:-}" == "1" ]]; then
    exit 0  # framework bootstrap path
fi

# Resolve target path
TARGET="${CLAUDE_TOOL_FILE_PATH:-${1:-}}"
if [[ -z "${TARGET}" ]]; then
    # No path = nothing to guard
    exit 0
fi

# ---- locate zones.yaml ---------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
ZONES_FILE="${LOA_ZONES_FILE:-${PROJECT_ROOT}/grimoires/loa/zones.yaml}"

if [[ ! -f "${ZONES_FILE}" ]]; then
    if [[ "${LOA_REQUIRE_ZONES:-0}" == "1" ]]; then
        echo "[zone-write-guard] ERROR: zones.yaml required but not found at ${ZONES_FILE}" >&2
        exit 2
    fi
    # Graceful degradation — no manifest means no opinions
    exit 0
fi

if ! command -v yq >/dev/null 2>&1; then
    echo "[zone-write-guard] WARN: yq not available; cannot enforce zones — allowing" >&2
    exit 0
fi

# ---- classify the path ---------------------------------------------------

# Normalize the target to repo-relative for matching.
if [[ "${TARGET}" == /* ]]; then
    case "${TARGET}" in
        ${PROJECT_ROOT}/*) TARGET="${TARGET#${PROJECT_ROOT}/}" ;;
    esac
fi

_path_matches_glob() {
    local path="$1"
    local pattern="$2"
    # Use bash extglob ** support via shopt
    shopt -s extglob globstar nullglob
    # shellcheck disable=SC2053
    [[ "$path" == $pattern ]]
}

_zone_for_path() {
    local path="$1"
    local zone_name
    for zone_name in framework project shared; do
        # Read the zone's tracked_paths array
        local patterns
        patterns=$(yq -r ".zones.${zone_name}.tracked_paths[]?" "${ZONES_FILE}" 2>/dev/null) || continue
        local pattern
        while IFS= read -r pattern; do
            [[ -z "$pattern" ]] && continue
            if _path_matches_glob "$path" "$pattern"; then
                echo "$zone_name"
                return 0
            fi
        done <<< "$patterns"
    done
    echo "unclassified"
}

ZONE="$(_zone_for_path "${TARGET}")"
ACTOR="${LOA_ACTOR:-project-work}"

# ---- decision ------------------------------------------------------------

_emit_decision() {
    local decision="$1"
    local reason="$2"
    local trajectory_dir="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"
    local log_file="${trajectory_dir}/zone-guard-$(date -u +%Y-%m-%d).jsonl"
    if [[ -d "${trajectory_dir}" ]]; then
        local ts
        ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        printf '{"timestamp":"%s","decision":"%s","actor":"%s","zone":"%s","path":"%s","reason":"%s"}\n' \
            "$ts" "$decision" "$ACTOR" "$ZONE" "$TARGET" "$reason" >> "${log_file}" 2>/dev/null || true
    fi
}

_block() {
    local reason="$1"
    cat <<EOF >&2
[zone-write-guard] BLOCKED: actor=${ACTOR} path=${TARGET} zone=${ZONE}
  Reason: ${reason}
  Override: LOA_ZONE_GUARD_BYPASS=1 <retry command>
  Reference: grimoires/loa/runbooks/zone-hygiene.md
EOF
    _emit_decision "BLOCK" "${reason}"
    exit 1
}

_allow() {
    _emit_decision "ALLOW" "${1:-default}"
    exit 0
}

# Bypass escape hatch
if [[ "${LOA_ZONE_GUARD_BYPASS:-}" == "1" ]]; then
    echo "[zone-write-guard] WARNING: LOA_ZONE_GUARD_BYPASS=1; allowing actor=${ACTOR} path=${TARGET} zone=${ZONE}" >&2
    _emit_decision "BYPASS" "operator-override-via-env"
    exit 0
fi

case "${ZONE}" in
    framework)
        case "${ACTOR}" in
            update-loa)        _allow "update-loa writes framework zone" ;;
            project-work)      _block "framework-zone is upstream-managed; use overrides or file upstream" ;;
            *)                 _block "actor=${ACTOR} not authorized to write framework zone" ;;
        esac
        ;;
    project)
        case "${ACTOR}" in
            update-loa)        _block "/update-loa MUST NOT write project-zone paths (cycle-106)" ;;
            *)                 _allow "actor=${ACTOR} writes project zone" ;;
        esac
        ;;
    shared)
        _allow "shared zone accepts any actor"
        ;;
    unclassified)
        # zones.yaml is a positive declaration. Unclassified = no opinion.
        _allow "path not declared in zones.yaml; no opinion"
        ;;
    *)
        _allow "unknown zone classification — defaulting to ALLOW"
        ;;
esac
