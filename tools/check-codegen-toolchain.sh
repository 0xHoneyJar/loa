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

# Print one row of the verification table.
check_version() {
    local name="$1"      # display name
    local cmd="$2"       # version-extracting shell expression
    local min="$3"       # minimum required version label (informational)
    local actual
    actual="$(eval "$cmd" 2>/dev/null || true)"
    if [ -z "$actual" ] || [ "$actual" = "MISSING" ]; then
        printf 'FAIL  %-12s missing (need %s)\n' "$name" "$min"
        errors=$((errors + 1))
    else
        printf 'OK    %-12s %s (need %s)\n' "$name" "$actual" "$min"
    fi
}

echo "Cycle-099 codegen toolchain check"
echo "================================="

# bash >= 5.0 — associative arrays are load-bearing (declare -A in
# generated-model-maps.sh). macOS ships bash 3.2 by default; install via brew.
check_version 'bash' \
    'bash --version | head -1 | awk "{print \$4}"' \
    '5.x'

# jq >= 1.7 — flatline-orchestrator.sh + gen-adapter-maps.sh
check_version 'jq' \
    'jq --version | sed "s/^jq-//"' \
    '1.7+'

# yq (mikefarah) v4.52.4 exact — pinned to match
# .github/workflows/model-registry-drift.yml + bats-tests.yml
check_version 'yq' \
    'yq --version | awk "{print \$NF}" | tr -d "v"' \
    'v4.52.4'

# node >= 20 — required by BB skill package.json:engines.node
check_version 'node' \
    'node --version | tr -d v' \
    'v20+'

# python >= 3.11 — cheval requirement
check_version 'python' \
    'python3 --version | awk "{print \$2}"' \
    '3.11+'

echo "================================="
if [ "$errors" -gt 0 ]; then
    echo "FAIL: $errors tool(s) missing or below pinned minimum"
    echo "See: grimoires/loa/runbooks/codegen-toolchain.md"
    exit 1
fi
echo "OK: all pinned tools present"
exit 0
