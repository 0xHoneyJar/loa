#!/usr/bin/env bash
# =============================================================================
# sweep-inventory.sh — freeze the open beads for a sweep (cycle-133 C-13, FR-13; DEC-0850)
#
# Usage:
#   sweep-inventory.sh --out DIR [--exclude FILE] [--batch-size 40] [--force]
#
#   --out DIR        the sweep directory (grimoires/loa/a2a/sprint-<N>/sweep); refused when it already
#                    holds an inventory.jsonl (the snapshot is frozen) unless --force
#   --exclude FILE   one bead id per line left out of the inventory (the cycle's Tier 1 beads, which the
#                    sprint reports close with commit and test; blank lines and # comments ignored)
#   --batch-size N   beads per Explore batch (default 40; 1 … 100)
#
# Writes, in DIR:
#   inventory.jsonl      one row per open bead, sorted by id: {id, title, type, priority, labels,
#                        created, updated} — the frozen snapshot (no description: the inventory travels on the
#                        public record branch; agents read descriptions with `br show`)
#   inventory.sha256     the sha256 of inventory.jsonl (what the manifests are validated against)
#   batches/batch-<k>.jsonl   the inventory split in id order into batches of --batch-size
#   INVENTORY.md         the counts (beads, batches, excluded, by type) and the sha256
#
# Exit: 0 written · 2 usage or refusal (nothing written) · 1 br/jq failure.
# `br` is read-only here (br list --json); nothing in the tracker changes.
# =============================================================================
set -euo pipefail
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="" EXCLUDE="" BATCH=40 FORCE=false
usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="${2:-}"; shift 2 ;;
    --exclude) EXCLUDE="${2:-}"; shift 2 ;;
    --batch-size) BATCH="${2:-}"; shift 2 ;;
    --force) FORCE=true; shift ;;
    -h|--help) usage ;;
    *) echo "sweep-inventory: unknown argument $1" >&2; usage ;;
  esac
done
[[ -n "$OUT" ]] || { echo "sweep-inventory: --out DIR is required" >&2; exit 2; }
[[ "$BATCH" =~ ^[0-9]+$ && "$BATCH" -ge 1 && "$BATCH" -le 100 ]] || { echo "sweep-inventory: --batch-size must be 1 … 100" >&2; exit 2; }
if [[ -f "$OUT/inventory.jsonl" && "$FORCE" != true ]]; then
  echo "sweep-inventory: $OUT/inventory.jsonl exists — the snapshot is frozen (pass --force to re-freeze, which invalidates every manifest written against it)" >&2; exit 2
fi
command -v br >/dev/null 2>&1 || { echo "sweep-inventory: br (beads_rust) is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "sweep-inventory: jq is required" >&2; exit 1; }
EXJ='[]'
if [[ -n "$EXCLUDE" ]]; then
  [[ -f "$EXCLUDE" ]] || { echo "sweep-inventory: --exclude $EXCLUDE is not a file" >&2; exit 2; }
  # an exclusion file with no ids (comments and blanks only) is a valid, empty exclusion set (review round 1 MEDIUM)
  EXJ="$(awk '!/^[[:space:]]*(#|$)/ {print $1}' "$EXCLUDE" | jq -R -s -c 'split("\n") | map(select(length > 0))')"
fi
LIMIT=5000
BRERR="$(mktemp)"
RAW="$(br list --json --limit "$LIMIT" 2>"$BRERR")" || { echo "sweep-inventory: br list failed: $(head -c 300 "$BRERR")" >&2; unlink "$BRERR"; exit 1; }
unlink "$BRERR"
jq -e 'type == "object" or type == "array"' <<<"$RAW" >/dev/null 2>&1 || { echo "sweep-inventory: br list output did not parse" >&2; exit 1; }
RAW_N="$(jq -r 'if type == "object" then (.issues // []) else . end | length' <<<"$RAW")"
[[ "$RAW_N" -lt "$LIMIT" ]] || { echo "sweep-inventory: br list returned $RAW_N issues, the --limit $LIMIT — the inventory would be cut; raise LIMIT in the script" >&2; exit 1; }
ROWS="$(jq -c --argjson ex "$EXJ" '
  (if type == "object" then (.issues // []) else . end)
  | map(select((.status // "open") != "closed"))
  | map(select(.id as $i | ($ex | index($i)) == null))
  | sort_by(.id)
  | .[] | {id, title: (.title // ""), type: (.issue_type // .type // ""), priority: (.priority // null),
           labels: (.labels // []), created: (.created_at // .created // ""), updated: (.updated_at // "")}' <<<"$RAW")" || { echo "sweep-inventory: br list output did not parse" >&2; exit 1; }
N="$(printf '%s\n' "$ROWS" | grep -c '^{' || true)"
[[ "$N" -ge 1 ]] || { echo "sweep-inventory: no open bead to freeze" >&2; exit 2; }
# the snapshot is assembled in a temporary directory and moved into place at the end, so a failure never leaves a
# half-frozen sweep directory (review round 1 LOW); batches are cut with awk (no GNU split)
mkdir -p "$OUT"
TMP="$(mktemp -d "$OUT/.freeze.XXXXXX")"; trap 'find "$TMP" -depth -delete 2>/dev/null || true' EXIT
mkdir -p "$TMP/batches"
printf '%s\n' "$ROWS" > "$TMP/inventory.jsonl"
# shellcheck source=../compat-lib.sh
source "$SCRIPT_DIR/../compat-lib.sh"
SHA="$(sha256_portable "$TMP/inventory.jsonl" | cut -d' ' -f1)"
printf '%s  inventory.jsonl\n' "$SHA" > "$TMP/inventory.sha256"
awk -v n="$BATCH" -v dir="$TMP/batches" '{ k = int((NR - 1) / n); f = sprintf("%s/batch-%02d.jsonl", dir, k); print > f }' "$TMP/inventory.jsonl"
K="$(ls "$TMP"/batches/batch-*.jsonl | wc -l)"
NEX="$(jq -r 'length' <<<"$EXJ")"
{
  printf '# Sweep inventory (frozen)\n\n'
  printf -- '- beads: %s (open at freeze, minus %s excluded Tier 1 ids)\n- batches: %s of up to %s beads (id order)\n- inventory.jsonl sha256: `%s`\n- frozen at: %s\n\n' "$N" "$NEX" "$K" "$BATCH" "$SHA" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '| type | beads |\n|---|---|\n'
  jq -r '.type' "$TMP/inventory.jsonl" | sort | uniq -c | sort -rn | awk '{printf "| %s | %s |\n", $2, $1}'
  printf '\n| created (month) | beads |\n|---|---|\n'
  jq -r '.created[0:7]' "$TMP/inventory.jsonl" | sort | uniq -c | awk '{printf "| %s | %s |\n", $2, $1}'
} > "$TMP/INVENTORY.md"
if [[ -d "$OUT/batches" ]]; then find "$OUT/batches" -mindepth 1 -delete; rmdir "$OUT/batches"; fi
for f in inventory.jsonl inventory.sha256 INVENTORY.md; do [[ -e "$OUT/$f" ]] && unlink "$OUT/$f"; done
mv "$TMP/batches" "$OUT/batches"; mv "$TMP/inventory.jsonl" "$TMP/inventory.sha256" "$TMP/INVENTORY.md" "$OUT/"
echo "sweep-inventory: $N beads frozen into $K batch(es) under $OUT (sha256 ${SHA:0:12})"
