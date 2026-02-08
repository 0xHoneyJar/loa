#!/usr/bin/env bash
# Bridgebuilder Autonomous PR Review — Loa skill entry point
# Invoked by Loa when user runs /bridgebuilder

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Bash 4.0+ version guard
source "${SKILL_DIR}/../../scripts/bash-version-guard.sh"

# Run compiled TypeScript via Node (no npx tsx — SKP-002)
exec node "${SKILL_DIR}/dist/main.js" "$@"
