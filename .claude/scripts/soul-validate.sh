#!/usr/bin/env bash
# =============================================================================
# soul-validate.sh — discoverable CLI entry for L7 SOUL.md validation.
#
# cycle-098 follow-up #776 (optimist LOW-3 closure): the canonical operator
# CLI ships at .claude/skills/soul-identity-doc/resources/soul-validate.sh
# but that path is deeply nested. This shim is the discoverable alias —
# invoke it from a top-level scripts directory that operators routinely
# add to PATH.
#
# Usage:
#   .claude/scripts/soul-validate.sh <path> [--strict|--warn]
#   .claude/scripts/soul-validate.sh --help
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# scripts → .claude → REPO_ROOT
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TARGET="${REPO_ROOT}/.claude/skills/soul-identity-doc/resources/soul-validate.sh"

if [[ ! -f "$TARGET" ]]; then
    echo "soul-validate: canonical CLI not found at $TARGET" >&2
    exit 7
fi

exec "$TARGET" "$@"
