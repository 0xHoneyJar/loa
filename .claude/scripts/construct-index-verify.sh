#!/usr/bin/env bash
# construct-index-verify.sh — coherence guard for the construct index.
#
# Asserts that every installed, schema-bearing pack (manifest.json OR construct.yaml)
# appears in the generated index. Catches the regression class where the generator
# silently drops packs — e.g. gating inclusion on a schema file it should no longer
# require (the bug that hid v4 construct.yaml-only packs from construct-resolve). The
# generator reports success while the index goes blind; this gate makes that LOUD.
#
# Companion to construct-index-gen.sh. Run after regeneration / as a CI check in any
# consumer that installs packs.
#
#   exit 0 = coherent (or no packs to check)
#   exit 1 = DRIFT: installed schema-bearing pack(s) missing from the index
#   exit 3 = environment error (no yq / no index)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PACKS_DIR="${LOA_PACKS_DIR:-$PROJECT_ROOT/.claude/constructs/packs}"
INDEX_PATH="${CONSTRUCT_INDEX_PATH:-$PROJECT_ROOT/.run/construct-index.yaml}"
QUIET=false; [[ "${1:-}" == "--quiet" ]] && QUIET=true
log() { $QUIET || echo "$@"; }

command -v yq >/dev/null 2>&1 || { echo "FATAL: yq required" >&2; exit 3; }
[[ -f "$INDEX_PATH" ]] || { echo "FATAL: index not found: $INDEX_PATH" >&2; exit 3; }
[[ -d "$PACKS_DIR" ]] || { log "construct-index-verify: no packs dir ($PACKS_DIR) — nothing to verify"; exit 0; }

indexed="$(yq -r '.constructs[].slug' "$INDEX_PATH" 2>/dev/null | sort -u)"

blind=()
for pack in "$PACKS_DIR"/*/; do
  [[ -d "$pack" ]] || continue
  name="$(basename "$pack")"
  if [[ -f "$pack/manifest.json" || -f "$pack/construct.yaml" ]]; then
    grep -qx "$name" <<<"$indexed" || blind+=("$name")
  fi
done

if (( ${#blind[@]} > 0 )); then
  echo "construct-index: DRIFT — ${#blind[@]} installed schema-bearing pack(s) missing from the index:" >&2
  printf '  - %s\n' "${blind[@]}" >&2
  echo "  → regenerate: $SCRIPT_DIR/construct-index-gen.sh" >&2
  exit 1
fi
log "construct-index: coherent — every installed pack is indexed ($(echo "$indexed" | grep -c .) constructs)"
exit 0
