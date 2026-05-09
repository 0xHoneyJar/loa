#!/usr/bin/env bash
# =============================================================================
# validate-model-error.sh — cycle-102 Sprint 1 (T1.1) bash wrapper.
#
# Thin shell wrapper around .claude/scripts/lib/validate-model-error.py for
# callers that prefer not to invoke Python directly. Mirrors the cycle-099
# validate-model-aliases-extra.sh pattern (Python canonical + bash twin).
#
# Usage:
#   validate-model-error.sh [--input <path> | --stdin] [--json] [--quiet]
#
# Exit codes:
#   0    valid
#   78   validation failed
#   64   usage / IO error
#   2    Python interpreter not found
# =============================================================================

set -euo pipefail

_script_dir() {
    cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P
}

_repo_root() {
    cd "$(_script_dir)/../../.." && pwd -P
}

_resolve_python() {
    local repo_root
    repo_root="$(_repo_root)"
    if [[ -x "$repo_root/.venv/bin/python" ]]; then
        printf '%s' "$repo_root/.venv/bin/python"
        return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        command -v python3
        return 0
    fi
    return 2
}

_PY="$(_resolve_python)" || {
    printf 'validate-model-error.sh: no python3 interpreter found\n' >&2
    printf 'Hint: install Python 3.11+ or activate the cheval venv at .venv/\n' >&2
    exit 2
}

_TOOL="$(_script_dir)/validate-model-error.py"
if [[ ! -f "$_TOOL" ]]; then
    printf 'validate-model-error.sh: canonical Python tool missing at %q\n' "$_TOOL" >&2
    exit 2
fi

# `python -I` (isolated mode) defends against PYTHONPATH / user-site
# injection. Mirrors the cycle-099 endpoint-validator.sh hardening pattern.
exec "$_PY" -I "$_TOOL" "$@"
