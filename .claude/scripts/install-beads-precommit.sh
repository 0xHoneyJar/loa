#!/usr/bin/env bash
# =============================================================================
# install-beads-precommit.sh — install hardened pre-commit hook (Issue #661)
# =============================================================================
# Copies the source-of-truth template at .claude/scripts/git-hooks/pre-commit-beads
# into .git/hooks/pre-commit so the operator gets the structured diagnostic
# for the upstream beads_rust migration bug.
#
# Idempotent: backs up an existing hook to .git/hooks/pre-commit.pre-loa-bak
# unless that backup already exists.
#
# Usage:
#   .claude/scripts/install-beads-precommit.sh [--force]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/git-hooks/pre-commit-beads"

FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE=1; shift ;;
        -h|--help)
            cat <<EOF
Usage: install-beads-precommit.sh [--force]

Installs the hardened beads pre-commit hook (Issue #661) into
.git/hooks/pre-commit. With --force, overwrites without backup.
EOF
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [[ ! -f "$TEMPLATE" ]]; then
    echo "ERROR: template not found at $TEMPLATE" >&2
    exit 1
fi

GIT_DIR=$(git rev-parse --git-common-dir 2>/dev/null) || {
    echo "ERROR: not in a git repository" >&2
    exit 1
}
HOOK_PATH="${GIT_DIR}/hooks/pre-commit"
BACKUP_PATH="${HOOK_PATH}.pre-loa-bak"

if [[ -f "$HOOK_PATH" && "$FORCE" -ne 1 ]]; then
    if [[ ! -f "$BACKUP_PATH" ]]; then
        cp "$HOOK_PATH" "$BACKUP_PATH"
        echo "[install-beads-precommit] backed up existing hook to ${BACKUP_PATH}"
    else
        echo "[install-beads-precommit] backup already present at ${BACKUP_PATH}"
    fi
fi

cp "$TEMPLATE" "$HOOK_PATH"
chmod +x "$HOOK_PATH"
echo "[install-beads-precommit] installed hardened hook at ${HOOK_PATH}"
echo "[install-beads-precommit] template source: ${TEMPLATE}"
