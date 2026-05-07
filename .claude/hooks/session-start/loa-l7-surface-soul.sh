#!/usr/bin/env bash
# =============================================================================
# loa-l7-surface-soul.sh — SessionStart hook (cycle-098 Sprint 7B).
#
# At session start, read SOUL.md (project root, descriptive identity doc),
# validate against the L7 schema, and surface the body wrapped in
# sanitize_for_session_start("L7", body) into the session context. Always
# silent (exit 0 with no stdout) when:
#   - soul_identity_doc.enabled is not true in .loa.config.yaml
#   - SOUL.md is missing
#   - the config file is absent or malformed
#   - schema_mode=strict and validation fails (NFR-Sec3 prescriptive
#     rejection or required-section absence)
#
# Always emits a soul.surface audit event (when enabled) capturing the
# outcome (surfaced | schema-warning | schema-refused | file-missing).
#
# FR-L7-1 (load at session start), FR-L7-2 (warn|strict), FR-L7-4 (cap +
# reference path), FR-L7-5 (single-fire — re-source no-ops via LOA_L7_SURFACED
# env marker), FR-L7-6 (silent on disabled / missing / refused).
#
# Trust boundary: the SOUL.md body is OPERATOR-AUTHORED but UNTRUSTED at
# surfacing. soul_load wraps the body via sanitize_for_session_start("L7",
# body) before reaching session context — never interpret as instructions.
# =============================================================================

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HOOK_DIR}/../../.." && pwd)"
LIB="${REPO_ROOT}/.claude/scripts/lib/soul-identity-lib.sh"
[[ -f "$LIB" ]] || exit 0

# Cache scoped to session — re-source no-ops (FR-L7-5).
[[ "${LOA_L7_SURFACED:-0}" == "1" ]] && exit 0

# -----------------------------------------------------------------------------
# Test-mode env-gated path overrides (LOA_SOUL_TEST_CONFIG +
# LOA_SOUL_TEST_PATH). Honored ONLY under bats / LOA_SOUL_TEST_MODE=1 with a
# bats-detected ancestor. Mirrors L4/L6 cycle-098 patterns.
# -----------------------------------------------------------------------------
_l7_test_mode_active() {
    if [[ -n "${BATS_TEST_DIRNAME:-}" ]] || [[ -n "${BATS_TMPDIR:-}" ]]; then
        return 0
    fi
    if [[ "${LOA_SOUL_TEST_MODE:-0}" == "1" ]] && [[ -n "${BATS_TEST_DIRNAME:-${BATS_TMPDIR:-}}" ]]; then
        return 0
    fi
    return 1
}

config_path="${REPO_ROOT}/.loa.config.yaml"
if _l7_test_mode_active && [[ -n "${LOA_SOUL_TEST_CONFIG:-}" ]]; then
    config_path="$LOA_SOUL_TEST_CONFIG"
fi

# Gate on yq availability + config presence.
command -v yq >/dev/null 2>&1 || exit 0
[[ -f "$config_path" ]] || exit 0

# Read enable / mode / max-chars / path keys. Silent on malformed YAML
# (each yq returns the default).
enabled="$(yq '.soul_identity_doc.enabled // false' "$config_path" 2>/dev/null || echo false)"
[[ "$enabled" == "true" ]] || exit 0

schema_mode="$(yq '.soul_identity_doc.schema_mode // "warn"' "$config_path" 2>/dev/null || echo warn)"
case "$schema_mode" in
    strict|warn) ;;
    *) schema_mode="warn" ;;
esac

max_chars="$(yq '.soul_identity_doc.surface_max_chars // 2000' "$config_path" 2>/dev/null || echo 2000)"
case "$max_chars" in
    ''|*[!0-9]*) max_chars=2000 ;;
esac

# Resolve SOUL.md path:
#   1) LOA_SOUL_TEST_PATH (test-mode only)
#   2) .loa.config.yaml::soul_identity_doc.path (absolute or repo-relative)
#   3) ${REPO_ROOT}/SOUL.md
soul_path="${REPO_ROOT}/SOUL.md"
if _l7_test_mode_active && [[ -n "${LOA_SOUL_TEST_PATH:-}" ]]; then
    soul_path="$LOA_SOUL_TEST_PATH"
else
    cfg_path="$(yq '.soul_identity_doc.path // ""' "$config_path" 2>/dev/null || echo "")"
    if [[ -n "$cfg_path" && "$cfg_path" != "null" ]]; then
        if [[ "$cfg_path" == /* ]]; then
            soul_path="$cfg_path"
        else
            if _l7_test_mode_active; then
                # Relative path resolves relative to the test config's directory.
                soul_path="$(dirname "$config_path")/$cfg_path"
            else
                soul_path="${REPO_ROOT}/$cfg_path"
            fi
        fi
    fi
fi

# Silent on missing file (FR-L7-6) — no audit event for "the file just
# wasn't there"; that's not an L7 lifecycle event worth chaining.
[[ -f "$soul_path" ]] || exit 0

# Source lib (after preflight gates pass — keeps no-op exit fast).
# shellcheck source=/dev/null
source "$LIB" 2>/dev/null || exit 0

# Lib uses `set -euo pipefail`. Disable -e for our error-tolerant flow.
set +e

# Validate (capture stdout+stderr together; status separately).
validate_out="$(soul_validate "$soul_path" --"$schema_mode" 2>&1)"
validate_status=$?

# Outcome resolution:
#   strict + non-zero → schema-refused (no surface; audit event recorded)
#   warn + SCHEMA-WARNING-marker present → schema-warning (surface with marker)
#   else → surfaced
outcome="surfaced"
if [[ "$schema_mode" == "strict" && "$validate_status" -ne 0 ]]; then
    outcome="schema-refused"
elif [[ "$schema_mode" == "warn" && "$validate_out" == *"SCHEMA-WARNING"* ]]; then
    outcome="schema-warning"
fi

# Build payload (best-effort; degrade to empty on lib error).
payload="$(soul_compute_surface_payload "$soul_path" "$schema_mode" "$outcome" 2>/dev/null)"
[[ -z "$payload" ]] && payload='{"file_path":"SOUL.md","schema_version":"1.0","schema_mode":"warn","identity_for":"this-repo","outcome":"surfaced"}'

# Emit audit event (silent — stderr/stdout suppressed; failures non-fatal).
soul_emit "soul.surface" "$payload" >/dev/null 2>&1 || true

# Surface body unless strict-refused.
if [[ "$outcome" != "schema-refused" ]]; then
    if [[ "$outcome" == "schema-warning" && -n "$validate_out" ]]; then
        # Print only the SCHEMA-WARNING lines; skip any noise.
        while IFS= read -r line; do
            [[ "$line" == *"SCHEMA-WARNING"* ]] && printf '%s\n' "$line"
        done <<<"$validate_out"
    fi
    soul_load "$soul_path" --max-chars "$max_chars" 2>/dev/null || true
fi

export LOA_L7_SURFACED=1
set -e
exit 0
