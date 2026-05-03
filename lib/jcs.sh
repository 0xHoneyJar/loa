#!/usr/bin/env bash
# =============================================================================
# lib/jcs.sh — RFC 8785 JCS canonicalization for bash callers.
#
# cycle-098 Sprint 1 (IMP-001 HIGH_CONSENSUS 736). Per SDD §2.2 stack table,
# `jq -S -c` is NOT equivalent to JCS (does not canonicalize numbers per
# ECMAScript ToNumber, does not canonicalize Unicode escapes). Chain hashes
# and Ed25519 signature inputs MUST flow through this canonicalizer.
#
# This bash adapter delegates the hot work to .claude/scripts/lib/jcs-helper.py
# which wraps the `rfc8785` Python reference implementation.
#
# Public API:
#   jcs_canonicalize <json-input>   — emit canonical-JSON bytes on stdout
#   jcs_canonicalize_file <path>    — same, reading from a file
#   jcs_available                   — return 0 if helper + rfc8785 available
#
# Conformance: tests/conformance/jcs/run.sh verifies byte-identity vs Python
# and Node adapters.
# =============================================================================

set -euo pipefail

# Idempotent source guard.
if [[ "${_LOA_JCS_SOURCED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
_LOA_JCS_SOURCED=1

# Resolve helper path. Use portable-realpath when sourced from various depths.
_LOA_JCS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LOA_JCS_REPO_ROOT="$(cd "${_LOA_JCS_DIR}/.." && pwd)"
_LOA_JCS_HELPER="${_LOA_JCS_REPO_ROOT}/.claude/scripts/lib/jcs-helper.py"

# -----------------------------------------------------------------------------
# jcs_available — return 0 if the helper script and rfc8785 package are present.
# Side effect: prints the failure reason on stderr when returning non-zero.
# -----------------------------------------------------------------------------
jcs_available() {
    if [[ ! -f "${_LOA_JCS_HELPER}" ]]; then
        echo "jcs: helper script missing at ${_LOA_JCS_HELPER}" >&2
        return 1
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        echo "jcs: python3 not found in PATH" >&2
        return 1
    fi
    if ! python3 -c 'import rfc8785' >/dev/null 2>&1; then
        echo "jcs: 'rfc8785' Python package not installed (pip install rfc8785)" >&2
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# jcs_canonicalize <json-input>
#
# Emits canonical-JSON bytes per RFC 8785 on stdout. No trailing newline.
# Input is a single JSON value (string, number, object, array, true/false/null).
# Returns non-zero on parse error or missing dependency.
# -----------------------------------------------------------------------------
jcs_canonicalize() {
    local input="${1:-}"

    # Support piped input.
    if [[ -z "$input" ]] && [[ ! -t 0 ]]; then
        input="$(cat)"
    fi

    if [[ -z "$input" ]]; then
        echo "jcs_canonicalize: empty input" >&2
        return 2
    fi

    if ! jcs_available; then
        return 3
    fi

    # Pipe through helper.
    printf '%s' "$input" | python3 "${_LOA_JCS_HELPER}"
}

# -----------------------------------------------------------------------------
# jcs_canonicalize_file <path>
#
# Read JSON from <path>, emit canonical-JSON on stdout.
# -----------------------------------------------------------------------------
jcs_canonicalize_file() {
    local path="${1:-}"
    if [[ -z "$path" ]]; then
        echo "jcs_canonicalize_file: missing path argument" >&2
        return 2
    fi
    if [[ ! -f "$path" ]]; then
        echo "jcs_canonicalize_file: file not found: $path" >&2
        return 2
    fi
    if ! jcs_available; then
        return 3
    fi
    python3 "${_LOA_JCS_HELPER}" < "$path"
}

# CLI entrypoint when invoked directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --help|-h)
            cat <<EOF
Usage: jcs.sh [<json>]

Read a single JSON value (from argv or stdin) and emit canonical-JSON
serialization per RFC 8785 on stdout.

Examples:
  echo '{"b":2,"a":1}' | jcs.sh
  jcs.sh '{"b":2,"a":1}'
EOF
            ;;
        --check)
            if jcs_available; then
                echo "jcs: ready"
                exit 0
            fi
            exit 1
            ;;
        "")
            # No argv → read stdin.
            if [[ -t 0 ]]; then
                # Interactive shell with no input — print usage.
                cat <<EOF
Usage: jcs.sh [<json>]

Read a single JSON value (from argv or stdin) and emit canonical-JSON
serialization per RFC 8785 on stdout.
EOF
                exit 0
            fi
            jcs_canonicalize ""
            ;;
        *)
            jcs_canonicalize "$1"
            ;;
    esac
fi
