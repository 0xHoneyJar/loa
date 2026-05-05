#!/usr/bin/env bash
# =============================================================================
# endpoint-validator.sh — bash wrapper per cycle-099 SDD §1.9.1.
#
# The Python canonical at .claude/scripts/lib/endpoint-validator.py is the
# sole implementation of the SDD §6.5 8-step URL canonicalization pipeline.
# This wrapper delegates to it via subprocess so bash callers (red-team
# adapter, model-adapter.sh) get byte-identical validation outcomes.
#
# Rationale: a pure-bash port of urllib.parse + idna + ipaddress is brittle
# (locale-sensitive regex, missing edge cases, BSD/GNU divergence). Using
# Python via subprocess delegates to the canonical with one fork+exec per
# validation; that's cheap enough for config-load-time validation, and the
# cross-runtime parity test asserts byte-equal output between Python direct
# and bash wrapper.
#
# Usage:
#   As library:
#     source .claude/scripts/lib/endpoint-validator.sh
#     endpoint_validator__check --json --allowlist <path> <url>
#   As filter:
#     bash .claude/scripts/lib/endpoint-validator.sh --json --allowlist X URL
#
# Hardening (cypherpunk MEDIUM 3 + 4):
#   - argv smuggling: any argument that LOOKS like a flag but follows the
#     designated URL slot is treated as opaque positional data via the
#     argparse `--` separator. Without this, an attacker URL value of
#     `--allowlist=/dev/stdin` would clobber the operator's allowlist arg.
#   - symlink swap: BASH_SOURCE-relative path resolution follows symlinks
#     by default, letting an attacker who controls a symlink target
#     redirect to a fake validator. We resolve with `realpath -e` and
#     bail if the resolved path is outside the project's lib directory.
# =============================================================================

set -euo pipefail

# Resolve the Python interpreter. Prefer the project's .venv (which has idna
# pinned at the version the canonical was tested against), else fall back to
# system python3. Operators should run `python3 -m pip install idna>=3.6`
# in their .venv before relying on this wrapper.
_endpoint_validator__python() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    local repo_root
    repo_root="$(cd "$script_dir/../../.." && pwd -P)"
    if [[ -x "$repo_root/.venv/bin/python" ]]; then
        printf '%s' "$repo_root/.venv/bin/python"
    elif command -v python3 >/dev/null 2>&1; then
        command -v python3
    else
        printf ''
    fi
}

# Resolve the canonical Python script path. Refuses symlinks: the resolved
# path MUST live under .claude/scripts/lib/ inside the same repo as this
# wrapper. Returns 0 + stdout on success, 1 on tamper detection.
_endpoint_validator__resolve_canonical() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    local resolved
    if command -v realpath >/dev/null 2>&1; then
        resolved="$(realpath -e "$script_dir/endpoint-validator.py" 2>/dev/null || true)"
    else
        resolved="$script_dir/endpoint-validator.py"
    fi
    if [[ -z "$resolved" ]] || [[ ! -f "$resolved" ]]; then
        printf '[ENDPOINT-VALIDATOR-MISSING] %s/endpoint-validator.py not found\n' \
            "$script_dir" >&2
        return 1
    fi
    # Guard: the resolved path MUST live under script_dir (same physical lib/).
    case "$resolved" in
        "$script_dir"/*) ;;
        *)
            printf '[ENDPOINT-VALIDATOR-SYMLINK-OUT-OF-TREE] %s\n' "$resolved" >&2
            return 1
            ;;
    esac
    printf '%s' "$resolved"
}

# Library entrypoint. Forwards argv to the Python canonical; preserves stdout,
# stderr, and exit code so callers see identical behavior to invoking the
# Python module directly.
#
# argv contract: callers MUST pass flags first and the URL last, e.g.
#   endpoint_validator__check --json --allowlist X URL
# We force a `--` separator before the URL so argparse can't be smuggled by
# an attacker URL that starts with `-`.
endpoint_validator__check() {
    local py
    py="$(_endpoint_validator__python)"
    if [[ -z "$py" ]]; then
        printf '[ENDPOINT-VALIDATOR-NO-PYTHON] python3 not found on PATH\n' >&2
        return 64  # EX_USAGE
    fi
    local validator
    if ! validator="$(_endpoint_validator__resolve_canonical)"; then
        return 64
    fi
    if [[ $# -lt 1 ]]; then
        # No argv at all → forward to Python so argparse emits its usage line.
        "$py" -I "$validator"
        return $?
    fi
    # Split argv: everything except the LAST argument is forwarded as flags,
    # the last argument is the URL slot and goes after `--` so argparse can
    # never reinterpret it as an option (cypherpunk M3).
    local last_idx=$(( $# - 1 ))
    local url="${!#}"
    local flags=("${@:1:$last_idx}")
    # `python -I` enables isolated mode (ignore PYTHON* env vars + user site-
    # packages) — defends against PYTHONPATH-injected interpreter modules.
    "$py" -I "$validator" "${flags[@]}" -- "$url"
}

# When invoked as a script (not sourced), forward all argv to the library
# entry. This lets `bash endpoint-validator.sh --json --allowlist X URL` work
# the same as `source endpoint-validator.sh; endpoint_validator__check ...`.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    endpoint_validator__check "$@"
fi
