#!/usr/bin/env bash
# =============================================================================
# model-probe-cache.sh — cycle-102 Sprint 1 (T1.3) bash twin.
#
# Per SDD section 4.2.3 Option B (per-runtime cache files), the bash twin
# maintains its OWN cache (`.run/model-probe-cache/bash-<provider>.json`)
# distinct from the Python canonical's cache. This is intentional —
# duplicating ≤ 3× probes/min/provider across runtimes is cheaper than the
# cross-runtime locking complexity Option A would require.
#
# However, for Sprint 1 the bash twin DELEGATES to the Python canonical via
# subprocess, with the runtime sentinel set to `bash` so cache writes go to
# `bash-<provider>.json`. This keeps the lock + stale-while-revalidate +
# probe-classification logic single-source-of-truth in Python while the
# wrapper exposes a bash-friendly CLI.
#
# Sprint 1 wrapper subcommands:
#   probe --provider P --model M [--ttl N] [--timeout F] [--skip-local-network-check]
#   invalidate --provider P
#   detect-local-network [--host H] [--port N] [--timeout F]
#
# Exit codes (mirror the Python CLI):
#   0   AVAILABLE / DEGRADED outcome (caller proceeds, may need WARN)
#   1   FAIL outcome (caller fail-fasts)
#   2   Python interpreter not found
#   64  usage error
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
    printf 'model-probe-cache.sh: no python3 interpreter found\n' >&2
    printf 'Hint: install Python 3.11+ or activate the cheval venv at .venv/\n' >&2
    exit 2
}

_TOOL="$(_script_dir)/model-probe-cache.py"
if [[ ! -f "$_TOOL" ]]; then
    printf 'model-probe-cache.sh: canonical Python tool missing at %q\n' "$_TOOL" >&2
    exit 2
fi

# `python -I` (isolated mode) defends against PYTHONPATH / user-site
# injection. Mirrors the cycle-099 endpoint-validator.sh hardening pattern.
#
# LOA_PROBE_RUNTIME=bash is consumed by the Python canonical to namespace
# cache writes: cache file becomes `.run/model-probe-cache/bash-<provider>.json`
# instead of `python-<provider>.json`.
LOA_PROBE_RUNTIME="${LOA_PROBE_RUNTIME:-bash}" exec "$_PY" -I "$_TOOL" "$@"
