#!/usr/bin/env bash
# install-audit-prepush.sh — install the opt-in audit pre-push hook into this clone.
#
# Copies .claude/scripts/git-hooks/pre-push-audit → <hooks>/pre-push (respecting
# core.hooksPath). The hook's ledger-hygiene gate is ALWAYS ON (cycle-124 FR-6, hook
# v2 — re-run this installer on a v1 install to pick it up); its audit-chain
# attestation is DEFAULT-OFF (enforces only when LOA_AUDIT_VERIFY_FOR_MERGE=1).
# A pre-existing NON-loa pre-push hook is BACKED UP to <hooks>/pre-push.pre-loa-bak
# (never silently destroyed); a v1 loa hook is replaced in place.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/git-hooks/pre-push-audit"
SENTINEL='# loa:pre-push-audit:v'
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
echo "  ledger-hygiene gate active; export LOA_AUDIT_VERIFY_FOR_MERGE=1 to also enforce the audit-chain attestation."
