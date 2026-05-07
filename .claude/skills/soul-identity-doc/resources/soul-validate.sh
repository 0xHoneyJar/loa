#!/usr/bin/env bash
# =============================================================================
# soul-validate.sh — CLI wrapper for L7 operator-time validation.
#
# cycle-098 Sprint 7C. Per SDD §5.9.2: `/loa soul validate <path>`. No audit
# log emission (operator-time check; can be re-run idempotently).
#
# Usage:
#   soul-validate.sh <path> [--strict|--warn]
#
# Exit codes:
#   0 — valid (or warn-mode pass with markers on stdout)
#   2 — invalid (schema / sections / prescriptive hit / control byte)
#   7 — configuration (no path supplied; lib missing)
# =============================================================================

set -uo pipefail

usage() {
    cat <<'USAGE'
soul-validate — operator-time L7 SOUL.md validator (no audit log)

Usage:
  soul-validate <path> [--strict|--warn]

Options:
  --strict    Reject doc on any schema or section issue (default).
  --warn      Emit [SCHEMA-WARNING] markers, exit 0.
  -h, --help  Show this help.

Exit codes:
  0 — valid
  2 — invalid (schema / required sections missing / prescriptive hit /
              control byte in scalar)
  7 — config (lib missing or no path supplied)
USAGE
}

if [[ $# -eq 0 ]]; then
    usage >&2
    exit 7
fi

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# resources → soul-identity-doc → skills → .claude → REPO_ROOT
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
LIB="${REPO_ROOT}/.claude/scripts/lib/soul-identity-lib.sh"
if [[ ! -f "$LIB" ]]; then
    echo "soul-validate: lib not found at $LIB" >&2
    exit 7
fi

# shellcheck source=/dev/null
source "$LIB"
soul_validate "$@"
