#!/usr/bin/env bash
# install-audit-prepush.sh — install the opt-in audit pre-push hook into this clone.
#
# Copies .claude/scripts/git-hooks/pre-push-audit → <hooks>/pre-push (respecting
# core.hooksPath). DEFAULT-OFF (enforces only when LOA_AUDIT_VERIFY_FOR_MERGE=1), so
# installing it is inert until you opt in. A pre-existing NON-loa pre-push hook is
# BACKED UP to <hooks>/pre-push.pre-loa-bak (never silently destroyed).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/git-hooks/pre-push-audit"
SENTINEL='# loa:pre-push-audit:v1'
[[ -f "$SRC" ]] || { echo "install-audit-prepush: template missing: $SRC" >&2; exit 1; }
HOOKS_DIR="$(git rev-parse --git-path hooks 2>/dev/null)" || { echo "not a git repo" >&2; exit 1; }
mkdir -p "$HOOKS_DIR"; DEST="${HOOKS_DIR}/pre-push"
if [[ -f "$DEST" ]] && ! grep -qF "$SENTINEL" "$DEST" 2>/dev/null; then
  bak="${DEST}.pre-loa-bak"
  cp -p "$DEST" "$bak"
  echo "install-audit-prepush: backed up existing non-loa pre-push hook → $bak"
fi
cp "$SRC" "$DEST"; chmod +x "$DEST"
echo "installed pre-push-audit → $DEST"
echo "  inert until you opt in: export LOA_AUDIT_VERIFY_FOR_MERGE=1 to enforce on push."
