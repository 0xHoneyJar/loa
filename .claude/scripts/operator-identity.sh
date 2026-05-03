#!/usr/bin/env bash
# =============================================================================
# operator-identity.sh — cycle-098 Sprint 1B (PRD §Operator Identity Model,
# SDD §Operator Identity Library).
#
# Public API:
#   operator_identity_lookup <slug>       Print YAML object for the operator;
#                                         exit non-zero if unknown.
#   operator_identity_verify <slug>       Returns 0 = verified, 1 = unverified
#                                         (e.g., offboarded), 2 = unknown.
#   operator_identity_validate_schema <path>  CI-time validation; exit non-zero
#                                             on malformed schema.
#
# Verification chain (per PRD §Operator Identity Model):
#   1. Lookup `<slug>` in `OPERATORS.md` (identified by frontmatter).
#   2. If `verify_git_match: true` in .loa.config.yaml — cross-check
#      `git_email` against current `git config user.email`.
#   3. If `verify_gpg: true` — cross-check `gpg_key_fingerprint` against
#      GPG-signed commits.
#   4. On verification failure: handoff schema validation FAILS in strict
#      mode; WARN with `[UNVERIFIED-IDENTITY]` marker in warn mode.
#
# Source: grimoires/loa/operators.md (configurable via LOA_OPERATORS_FILE).
# =============================================================================

set -euo pipefail

if [[ "${_LOA_OPERATOR_IDENTITY_SOURCED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
_LOA_OPERATOR_IDENTITY_SOURCED=1

_OI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_OI_REPO_ROOT="$(cd "${_OI_DIR}/.." && pwd)"

_oi_log() {
    echo "[operator-identity] $*" >&2
}

# -----------------------------------------------------------------------------
# _oi_operators_file — resolve the operators file path at call time.
# Honors LOA_OPERATORS_FILE; defaults to grimoires/loa/operators.md.
# -----------------------------------------------------------------------------
_oi_operators_file() {
    echo "${LOA_OPERATORS_FILE:-${_OI_REPO_ROOT}/grimoires/loa/operators.md}"
}

# -----------------------------------------------------------------------------
# _oi_extract_frontmatter <path>
# Print the YAML frontmatter of an OPERATORS.md file (text between the leading
# '---' and the next '---' line). No-op (empty stdout) if frontmatter missing.
# -----------------------------------------------------------------------------
_oi_extract_frontmatter() {
    local path="$1"
    awk 'BEGIN{infm=0; started=0}
         /^---$/ { if (!started) { started=1; infm=1; next } else if (infm) { exit } }
         { if (infm) print }
    ' "$path"
}

# -----------------------------------------------------------------------------
# _oi_parse_yaml_to_json <path>
# Print frontmatter as compact JSON. Uses yq if available, PyYAML otherwise.
# -----------------------------------------------------------------------------
_oi_parse_yaml_to_json() {
    local path="$1"
    local fm
    fm="$(_oi_extract_frontmatter "$path")"
    if [[ -z "$fm" ]]; then
        echo "{}"
        return 0
    fi
    if command -v yq >/dev/null 2>&1; then
        printf '%s' "$fm" | yq -o=json -I=0 '.'
        return 0
    fi
    # PyYAML fallback.
    printf '%s' "$fm" | python3 - <<'PY'
import json, sys
try:
    import yaml
except ImportError:
    sys.stderr.write("operator-identity: yq not in PATH and PyYAML not installed\n")
    sys.exit(2)
print(json.dumps(yaml.safe_load(sys.stdin.read()) or {}, separators=(",", ":")))
PY
}

# -----------------------------------------------------------------------------
# operator_identity_lookup <slug>
# Print the operator's YAML object as compact JSON; non-zero if not found.
# -----------------------------------------------------------------------------
operator_identity_lookup() {
    local slug="${1:-}"
    [[ -n "$slug" ]] || { _oi_log "lookup: empty slug"; return 2; }

    local file
    file="$(_oi_operators_file)"
    [[ -f "$file" ]] || { _oi_log "operators file not found: $file"; return 2; }

    local json
    json="$(_oi_parse_yaml_to_json "$file")"
    local entry
    entry="$(printf '%s' "$json" | jq -c --arg slug "$slug" \
        '.operators[]? // empty | select(.id == $slug)')"
    if [[ -z "$entry" ]]; then
        _oi_log "operator not found: $slug"
        return 1
    fi
    printf '%s\n' "$entry"
}

# -----------------------------------------------------------------------------
# operator_identity_verify <slug>
# Returns:
#   0 = verified (active and verification chain passed)
#   1 = unverified (offboarded, or verify_git_match/verify_gpg failed)
#   2 = unknown (not present in OPERATORS.md)
# -----------------------------------------------------------------------------
operator_identity_verify() {
    local slug="${1:-}"
    [[ -n "$slug" ]] || return 2

    local entry
    if ! entry="$(operator_identity_lookup "$slug" 2>/dev/null)"; then
        return 2
    fi

    # Active-window check.
    local active_until
    active_until="$(printf '%s' "$entry" | jq -r '.active_until // ""')"
    if [[ -n "$active_until" ]]; then
        # If active_until is set and in the past, the operator is offboarded.
        local now epoch_until epoch_now
        now="$(date -u +%s)"
        # Parse ISO-8601 → epoch. macOS BSD date doesn't accept the same -d format,
        # so use python3 for portability.
        epoch_until="$(python3 -c '
import sys
from datetime import datetime
s = sys.argv[1]
# Replace Z with +00:00 for fromisoformat compatibility.
s2 = s.replace("Z", "+00:00")
print(int(datetime.fromisoformat(s2).timestamp()))
' "$active_until" 2>/dev/null)"
        if [[ -n "$epoch_until" ]] && [[ "$epoch_until" -lt "$now" ]]; then
            _oi_log "operator $slug is offboarded (active_until=$active_until)"
            return 1
        fi
    fi

    # Optional cross-checks.
    local config="${LOA_CONFIG_FILE:-${_OI_REPO_ROOT}/.loa.config.yaml}"
    if [[ -f "$config" ]]; then
        local verify_git verify_gpg
        verify_git="$(yq -r '.operator_identity.verify_git_match // false' "$config" 2>/dev/null || echo false)"
        verify_gpg="$(yq -r '.operator_identity.verify_gpg // false' "$config" 2>/dev/null || echo false)"

        if [[ "$verify_git" == "true" ]]; then
            local declared_email actual_email
            declared_email="$(printf '%s' "$entry" | jq -r '.git_email // ""')"
            actual_email="$(git config user.email 2>/dev/null || echo "")"
            if [[ -n "$declared_email" && -n "$actual_email" && "$declared_email" != "$actual_email" ]]; then
                _oi_log "git_email mismatch for $slug: declared=$declared_email actual=$actual_email"
                return 1
            fi
        fi

        if [[ "$verify_gpg" == "true" ]]; then
            local fp
            fp="$(printf '%s' "$entry" | jq -r '.gpg_key_fingerprint // ""')"
            if [[ -z "$fp" ]]; then
                _oi_log "operator $slug has no gpg_key_fingerprint declared"
                return 1
            fi
            # Cross-check against the most recent signed commit (if any).
            local sig_status
            sig_status="$(git log -1 --pretty=%G? 2>/dev/null || echo "N")"
            if [[ "$sig_status" != "G" && "$sig_status" != "U" ]]; then
                _oi_log "no GPG signature on most recent commit"
                return 1
            fi
            local commit_fp
            commit_fp="$(git log -1 --pretty=%GF 2>/dev/null || echo "")"
            if [[ "${commit_fp,,}" != "${fp,,}" ]]; then
                _oi_log "GPG fingerprint mismatch for $slug: declared=$fp commit=$commit_fp"
                return 1
            fi
        fi
    fi

    return 0
}

# -----------------------------------------------------------------------------
# operator_identity_validate_schema <path>
# Validate OPERATORS.md frontmatter shape. Exit non-zero on malformed.
# -----------------------------------------------------------------------------
operator_identity_validate_schema() {
    local path="${1:-}"
    [[ -n "$path" ]] || { _oi_log "validate: missing path"; return 2; }
    [[ -f "$path" ]] || { _oi_log "validate: file not found: $path"; return 2; }

    local json
    json="$(_oi_parse_yaml_to_json "$path")"

    # Required: schema_version + operators array; each operator must have id,
    # display_name, github_handle, git_email, capabilities, active_since.
    local err
    err="$(printf '%s' "$json" | jq -r '
      def required_op_fields: ["id","display_name","github_handle","git_email","capabilities","active_since"];
      def is_iso8601_z: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z?(\\+[0-9]{2}:[0-9]{2})?$");
      [
        if (.schema_version // "") == "" then "missing schema_version" else empty end,
        if (.operators | type) != "array" then "operators must be an array" else empty end,
        ( (.operators // [])
          | to_entries[]
          | . as $entry
          | $entry.value
          | (required_op_fields[] as $f
              | if has($f) | not then "operator[\($entry.key)] missing field \($f)" else empty end)
        ),
        ( (.operators // [])
          | to_entries[]
          | . as $entry
          | $entry.value
          | (
              if (.id | type) != "string" or (.id | length) == 0 then
                "operator[\($entry.key)].id must be non-empty string"
              elif (.id | test("^[a-z0-9][a-z0-9_-]*$")) | not then
                "operator[\($entry.key)].id must match ^[a-z0-9][a-z0-9_-]*$"
              elif (.capabilities | type) != "array" then
                "operator[\($entry.key)].capabilities must be array"
              elif (.active_since | is_iso8601_z) | not then
                "operator[\($entry.key)].active_since must be ISO-8601"
              else empty end
            )
        )
      ] | map(select(. != null)) | .[]
    ' 2>&1 || true)"

    if [[ -n "$err" ]]; then
        _oi_log "schema validation failed:"
        printf '%s\n' "$err" >&2
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# CLI dispatcher
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        lookup)
            shift
            operator_identity_lookup "$@"
            ;;
        verify)
            shift
            operator_identity_verify "$@"
            ;;
        validate)
            shift
            operator_identity_validate_schema "$@"
            ;;
        --help|-h|"")
            cat <<EOF
Usage: operator-identity.sh <command> [args]

Commands:
  lookup <slug>           Print operator's YAML object (as JSON).
  verify <slug>           Returns 0 = verified, 1 = unverified, 2 = unknown.
  validate <path>         Validate OPERATORS.md schema; exit non-zero on error.
EOF
            ;;
        *)
            echo "Unknown command: $1" >&2
            exit 2
            ;;
    esac
fi
