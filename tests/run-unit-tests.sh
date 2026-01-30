#!/usr/bin/env bash
# Run unit tests for ck integration
# Requires bats-core: https://github.com/bats-core/bats-core

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Check if bats is installed
if ! command -v bats >/dev/null 2>&1; then
    echo "Error: bats not found. Please install bats-core:" >&2
    echo "  macOS: brew install bats-core" >&2
    echo "  Linux: apt install bats or see https://github.com/bats-core/bats-core" >&2
    exit 1
fi

cd "${PROJECT_ROOT}"

echo "Running unit tests..."
echo "===================="
echo

# Run tests
if [ -d "${SCRIPT_DIR}/unit" ]; then
    bats "${SCRIPT_DIR}/unit"/*.bats
else
    echo "No unit tests found in ${SCRIPT_DIR}/unit/" >&2
    exit 1
fi

echo
echo "===================="
echo "Unit tests complete"
