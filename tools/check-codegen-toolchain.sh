#!/usr/bin/env bash
# =============================================================================
# check-codegen-toolchain.sh — verify pinned toolchain (cycle-099 sprint-1C)
# =============================================================================
# Verifies that the cycle-099 codegen toolchain is installed and at supported
# versions. Source of truth: grimoires/loa/runbooks/codegen-toolchain.md
#
# Exit codes:
#   0 — all pinned tools present and within supported version range
#   1 — one or more tools missing or below pinned minimum
#   2 — invocation error (no args expected)
#
# Usage:
#   bash tools/check-codegen-toolchain.sh
#
# CI uses this from .github/workflows/model-registry-drift.yml when the
# runbook or this script is touched, so version drift across the pin sites
# surfaces in CI rather than at codegen-time.

set -euo pipefail

if [ "$#" -ne 0 ]; then
    echo "[check-codegen-toolchain] error: no arguments expected" >&2
    exit 2
fi

errors=0

# Compare two semver-ish version strings using `sort -V`.
# Returns 0 when $1 >= $2, 1 when $1 < $2.
# Both arguments must be normalized to digit-dot-digit-dot-digit form
# (or compatible — sort -V tolerates suffixes like "5.2.37(1)-release").
_version_ge() {
    local current="$1" required="$2"
    local lowest
    lowest="$(printf '%s\n%s\n' "$current" "$required" | sort -V | head -1)"
    [ "$lowest" = "$required" ]
}

# IMPORTANT: callers MUST pass static literals to check_version (eval is
# scoped to hardcoded version-extraction expressions only — see BB iter-1
# F4). Do not parameterize the cmd argument from env vars or argv.
check_version() {
    local name="$1"      # display name
    local cmd="$2"       # version-extracting shell expression (LITERAL)
    local min="$3"       # minimum required version (e.g., "5.0", "1.7", "20.0")
    local actual
    # shellcheck disable=SC2086
    actual="$(eval "$cmd" 2>/dev/null || true)"
    if [ -z "$actual" ] || [ "$actual" = "MISSING" ]; then
        printf 'FAIL  %-12s missing (need %s+)\n' "$name" "$min"
        errors=$((errors + 1))
        return
    fi
    if _version_ge "$actual" "$min"; then
        printf 'OK    %-12s %s (need %s+)\n' "$name" "$actual" "$min"
    else
        printf 'FAIL  %-12s %s is below %s+\n' "$name" "$actual" "$min"
        errors=$((errors + 1))
    fi
}

echo "Cycle-099 codegen toolchain check"
echo "================================="

# bash >= 5.0 — associative arrays are load-bearing (declare -A in
# generated-model-maps.sh). macOS ships bash 3.2 by default; install via brew.
# Strip the "(N)-release" suffix bash --version emits on some distros so
# sort -V handles the digit-dot-digit form.
check_version 'bash' \
    'bash --version | head -1 | awk "{print \$4}" | grep -oE "^[0-9]+(\.[0-9]+)+"' \
    '5.0'

# jq >= 1.7 — flatline-orchestrator.sh + gen-adapter-maps.sh
check_version 'jq' \
    'jq --version | sed "s/^jq-//"' \
    '1.7'

# yq (mikefarah) v4.52.4 minimum (pinned to match workflows). BB iter-1 F6
# noted yq's --version format has shifted across versions; use a targeted
# grep for the digit-dot-digit-dot-digit pattern instead of trusting the
# last whitespace-separated field.
check_version 'yq' \
    'yq --version 2>&1 | grep -oE "v?[0-9]+\.[0-9]+\.[0-9]+" | head -1 | tr -d v' \
    '4.52.4'

# node >= 20 — required by BB skill package.json:engines.node
check_version 'node' \
    'node --version | tr -d v' \
    '20.0.0'

# python >= 3.11 — cheval requirement
check_version 'python' \
    'python3 --version | awk "{print \$2}"' \
    '3.11.0'

echo "================================="
if [ "$errors" -gt 0 ]; then
    echo "FAIL: $errors tool(s) missing or below pinned minimum"
    echo "See: grimoires/loa/runbooks/codegen-toolchain.md"
    exit 1
fi
echo "OK: all pinned tools present"
exit 0
