#!/usr/bin/env bash
# =============================================================================
# sweep-apply.sh — validate the sweep manifests against the frozen inventory and apply them (cycle-133 C-13, FR-13)
#
# Usage:
#   sweep-apply.sh --inventory DIR --manifests DIR --validate
#   sweep-apply.sh --inventory DIR --manifests DIR --apply --sprint N --review-by YYYY-MM-DD [--label backlog-2026-10]
#                  [--applied FILE] [--br-bin BR] [--dry-run]
#
#   --inventory DIR  the sweep directory holding inventory.jsonl + inventory.sha256 (sweep-inventory.sh)
#   --manifests DIR  the Explore batches' manifest-<k>.jsonl files: one row per bead
#                    {id, category, evidence, confidence} with category one of
#                    closed-implemented | closed-obsolete | kept | pulled-in, evidence a string,
#                    confidence high | medium | low (optional batch, note)
#   --validate       check everything, mutate nothing (exit 0 valid · 1 invalid, every problem listed)
#   --apply          validate, then apply every row not yet in the applied log:
#                      closed-implemented → br close ID --reason "implemented: <evidence>"
#                      closed-obsolete    → br close ID --reason "obsolete: <evidence>"
#                      kept               → br label add ID <label>; br comments add ID "status: kept — <evidence>; review-by <date>"
#                      pulled-in          → br label add ID sprint:<N>; br comments add ID "pulled in: <evidence>"
#                    and append {id, category, action, reason, ts} to the applied log (append-only; a re-run
#                    skips applied ids, so the apply is idempotent; every mutation is reversible with `br reopen`
#                    or `br label remove` by hand, citing this log)
#   --applied FILE   the append-only log (default <inventory DIR>/applied.jsonl)
#   --dry-run        with --apply: print the br commands, mutate nothing, write no log
#
# Validation (all before any mutation):
#   - inventory.jsonl matches inventory.sha256 (the snapshot is the one the manifests were written against)
#   - every manifest row parses and has the four fields with legal values
#   - every id is in the inventory; every inventory id appears in exactly one manifest (duplicate, missing,
#     unknown or conflicting ids are listed and rejected) — the manifests form a complete partition
#   - a closure's evidence resolves: a 7–40 hex commit sha that exists in this repository, a PR number
#     (#NNN or PR NNN) that a merge commit or the repository's git log names, or a path that exists at HEAD;
#     several references may be separated by `;` or `,` — at least one must resolve
#   - a closure's bead is still open in the tracker (br list) — a bead closed meanwhile is reported, not re-closed
#
# Exit: 0 valid / applied · 1 invalid (nothing mutated) or a row not applied (the others are; re-run after fixing) · 2 usage.
#   A bead br refuses as blocked by open dependencies is force-closed only when every blocker is a closure of this sweep;
#   otherwise the row is logged as skipped-blocked and reported.
# =============================================================================
set -euo pipefail
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
INV="" MAN="" MODE="" SPRINT="" REVIEW_BY="" LABEL="backlog-2026-10" APPLIED="" BR="${BR_BIN:-br}" DRY=false
usage() { sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --inventory) INV="${2:-}"; shift 2 ;;
    --manifests) MAN="${2:-}"; shift 2 ;;
    --validate) MODE=validate; shift ;;
    --apply) MODE=apply; shift ;;
    --sprint) SPRINT="${2:-}"; shift 2 ;;
    --review-by) REVIEW_BY="${2:-}"; shift 2 ;;
    --label) LABEL="${2:-}"; shift 2 ;;
    --applied) APPLIED="${2:-}"; shift 2 ;;
    --br-bin) BR="${2:-}"; shift 2 ;;
    --dry-run) DRY=true; shift ;;
    -h|--help) usage ;;
    *) echo "sweep-apply: unknown argument $1" >&2; usage ;;
  esac
done
[[ -n "$INV" && -n "$MAN" && -n "$MODE" ]] || { echo "sweep-apply: --inventory, --manifests and --validate|--apply are required" >&2; exit 2; }
[[ -f "$INV/inventory.jsonl" && -f "$INV/inventory.sha256" ]] || { echo "sweep-apply: $INV holds no inventory.jsonl + inventory.sha256" >&2; exit 2; }
[[ -d "$MAN" ]] || { echo "sweep-apply: --manifests $MAN is not a directory" >&2; exit 2; }
if [[ "$MODE" == apply ]]; then
  [[ "$SPRINT" =~ ^[0-9]+$ ]] || { echo "sweep-apply: --apply needs --sprint N" >&2; exit 2; }
  [[ "$REVIEW_BY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "sweep-apply: --apply needs --review-by YYYY-MM-DD" >&2; exit 2; }
  [[ "$LABEL" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$ ]] || { echo "sweep-apply: --label is not a label" >&2; exit 2; }
fi
APPLIED="${APPLIED:-$INV/applied.jsonl}"
command -v jq >/dev/null 2>&1 || { echo "sweep-apply: jq is required" >&2; exit 1; }
# shellcheck source=../compat-lib.sh
source "$SCRIPT_DIR/../compat-lib.sh"

problems=()
p() { problems+=("$1"); }
# 1. the frozen snapshot
want="$(awk '{print $1}' "$INV/inventory.sha256")"
have="$(sha256_portable "$INV/inventory.jsonl" | cut -d' ' -f1)"
[[ "$want" == "$have" ]] || p "inventory.jsonl sha256 $have does not match inventory.sha256 $want — the snapshot moved under the manifests"
jq -e -s 'all(.[]; type == "object" and (.id | type) == "string")' "$INV/inventory.jsonl" >/dev/null 2>&1 || p "inventory.jsonl holds a row without an id"
# 2. the manifests
shopt -s nullglob
MFILES=("$MAN"/manifest-*.jsonl)
shopt -u nullglob
[[ ${#MFILES[@]} -ge 1 ]] || p "no manifest-<k>.jsonl under $MAN"
ROWS="$(mktemp)"; trap 'rm -f "$ROWS" "$ROWS.ids"' EXIT
: > "$ROWS"
for f in ${MFILES[@]+"${MFILES[@]}"}; do
  n=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1)); [[ -n "${line// /}" ]] || continue
    if ! jq -e 'type == "object"' <<<"$line" >/dev/null 2>&1; then p "$(basename "$f") line $n: not a JSON object"; continue; fi
    err="$(jq -r '
      [ (if (.id | type) != "string" or (.id | test("^[A-Za-z][A-Za-z0-9-]*-[a-z0-9]+$") | not) then "id" else empty end),
        (if (.category | type) != "string" or ((.category | IN("closed-implemented","closed-obsolete","kept","pulled-in")) | not) then "category" else empty end),
        (if (.evidence | type) != "string" or (.evidence | test("\\S") | not) then "evidence" else empty end),
        (if (.confidence | type) != "string" or ((.confidence | IN("high","medium","low")) | not) then "confidence" else empty end) ]
      | join(",")' <<<"$line")"
    if [[ -n "$err" ]]; then p "$(basename "$f") line $n: invalid field(s) $err"; continue; fi
    jq -c --arg src "$(basename "$f")" '. + {src: $src}' <<<"$line" >> "$ROWS"
  done < "$f"
done
# 3. the partition
jq -r '.id' "$INV/inventory.jsonl" | sort > "$ROWS.ids"
MIDS="$(jq -r '.id' "$ROWS" | sort)"
dups="$(printf '%s\n' "$MIDS" | uniq -d | tr '\n' ' ')"
[[ -z "$dups" ]] || p "ids in more than one manifest row (duplicate or conflicting): $dups"
unknown="$(comm -13 "$ROWS.ids" <(printf '%s\n' "$MIDS" | sort -u) | tr '\n' ' ')"
[[ -z "$unknown" ]] || p "ids not in the frozen inventory: $unknown"
missing="$(comm -23 "$ROWS.ids" <(printf '%s\n' "$MIDS" | sort -u) | tr '\n' ' ')"
[[ -z "$missing" ]] || p "inventory ids no manifest names (the partition is incomplete): $missing"
# 4. closure evidence resolves; the bead is still open
resolves() {  # resolves "<evidence>" → 0 when at least one reference resolves in this repository
  local ev="$1" ref ok=1
  while IFS= read -r ref || [[ -n "$ref" ]]; do
    ref="$(printf '%s' "$ref" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"; [[ -n "$ref" ]] || continue
    if [[ "$ref" =~ ^[0-9a-f]{7,40}$ ]]; then
      git -C "$REPO_ROOT" cat-file -e "$ref^{commit}" 2>/dev/null && { ok=0; break; }
    elif [[ "$ref" =~ ^(#|PR[[:space:]]*#?)([0-9]{1,6})$ ]]; then
      local num="${BASH_REMATCH[2]}"
      git -C "$REPO_ROOT" log --all --oneline -E --grep="(^|[^0-9])#${num}([^0-9]|$)" -n 1 2>/dev/null | grep -q . && { ok=0; break; }
    elif [[ "$ref" =~ ^[A-Za-z0-9_./-]+$ && "$ref" != *".."* ]]; then
      git -C "$REPO_ROOT" cat-file -e "HEAD:$ref" 2>/dev/null && { ok=0; break; }
    fi
  done < <(printf '%s' "$ev" | tr ';,' '\n\n')
  return $ok
}
OPEN_IDS=""
# rows this sweep already applied (append-only log): their beads are closed or labelled by the sweep itself, so the
# still-open check below does not apply to them and a re-run stays valid
DONE_IDS="$(jq -r '.id' "$APPLIED" 2>/dev/null || true)"
if [[ ${#problems[@]} -eq 0 ]]; then
  OPEN_IDS="$("$BR" list --json --limit 5000 2>/dev/null | jq -r '(if type == "object" then (.issues // []) else . end) | map(select((.status // "open") != "closed")) | .[].id' 2>/dev/null || true)"
  while IFS=$'\t' read -r id cat ev; do
    case "$cat" in closed-implemented|closed-obsolete)
      resolves "$ev" || p "$id ($cat): evidence does not resolve to a commit, a PR number or a path at HEAD: ${ev:0:120}"
      grep -qx -- "$id" <<<"$OPEN_IDS" || grep -qx -- "$id" <<<"$DONE_IDS" \
        || p "$id ($cat): not open in the tracker now (closed meanwhile?) — demote to kept or drop the row"
      ;;
    esac
  done < <(jq -r '[.id, .category, .evidence] | @tsv' "$ROWS")
fi
if [[ ${#problems[@]} -gt 0 ]]; then
  printf 'sweep-apply: INVALID (%d problem(s)); nothing mutated\n' "${#problems[@]}" >&2
  printf '  - %s\n' "${problems[@]}" >&2
  exit 1
fi
N="$(grep -c '^{' "$ROWS" || true)"
jq -r '.category' "$ROWS" | sort | uniq -c | awk '{printf "sweep-apply: %s %s\n", $2, $1}' >&2
echo "sweep-apply: VALID — $N rows over ${#MFILES[@]} manifest(s) form a complete partition of the frozen inventory (sha256 ${want:0:12})"
[[ "$MODE" == apply ]] || exit 0
# 5. apply (idempotent through the applied log)
touch "$APPLIED"
# run <cmd…>: one tracker call; its stderr is kept in $RUN_ERR, its exit code returned (never aborts the loop)
RUN_ERR=""
run() {
  if [[ "$DRY" == true ]]; then printf 'DRY: %s\n' "$*"; return 0; fi
  local out; out="$("$@" 2>&1)" && { RUN_ERR=""; return 0; }
  RUN_ERR="$out"; return 1
}
CLOSURE_IDS="$(jq -r 'select(.category | startswith("closed")) | .id' "$ROWS")"
# close_bead <id> <reason>: a bead that br refuses as "blocked by" open dependencies is force-closed only when every
# blocker is itself a closure of this sweep (the partition closes them together); otherwise the row is logged skipped
close_bead() {
  local id="$1" reason="$2" blockers b
  run "$BR" close "$id" --reason "$reason" && return 0
  blockers="$(grep -oE 'blocked by: *[A-Za-z0-9, -]+' <<<"$RUN_ERR" | head -1 | sed -E 's/blocked by: *//' | tr ',' ' ')"
  [[ -n "$blockers" ]] || return 1
  for b in $blockers; do grep -qx -- "$b" <<<"$CLOSURE_IDS" || { RUN_ERR="blocked by $b, which this sweep keeps open"; return 2; }; done
  run "$BR" close "$id" --reason "$reason (blockers $blockers close in the same sweep)" --force
}
applied=0 skipped=0 failed=0
while IFS=$'\t' read -r id cat ev; do
  if grep -qx -- "$id" <<<"$DONE_IDS"; then skipped=$((skipped + 1)); continue; fi
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; ok=0
  case "$cat" in
    closed-implemented) reason="implemented: $ev"; close_bead "$id" "$reason" || ok=$?; action=close ;;
    closed-obsolete)    reason="obsolete: $ev";    close_bead "$id" "$reason" || ok=$?; action=close ;;
    kept)  reason="status: kept — $ev; review-by $REVIEW_BY (sweep sprint-$SPRINT)"; action="label $LABEL"
           { run "$BR" label add "$id" "$LABEL" && run "$BR" comments add "$id" "$reason"; } || ok=$? ;;
    pulled-in) reason="pulled in: $ev (sweep sprint-$SPRINT)"; action="label sprint:$SPRINT"
           { run "$BR" label add "$id" "sprint:$SPRINT" && run "$BR" comments add "$id" "$reason"; } || ok=$? ;;
  esac
  if [[ "$ok" -ne 0 ]]; then
    failed=$((failed + 1)); action="$( [[ "$ok" -eq 2 ]] && echo skipped-blocked || echo failed)"
    echo "sweep-apply: $id ($cat): $action — $(head -c 160 <<<"$RUN_ERR" | tr '\n' ' ')" >&2
    reason="$action: $(head -c 300 <<<"$RUN_ERR" | tr '\n' ' ')"
  else
    applied=$((applied + 1))
  fi
  if [[ "$DRY" != true && ( "$ok" -eq 0 || "$ok" -eq 2 ) ]]; then
    jq -n -c --arg id "$id" --arg cat "$cat" --arg action "$action" --arg reason "$reason" --arg ts "$ts" \
      '{id: $id, category: $cat, action: $action, reason: $reason, ts: $ts}' >> "$APPLIED"
  fi
done < <(jq -r '[.id, .category, .evidence] | @tsv' "$ROWS")
echo "sweep-apply: applied $applied row(s), skipped $skipped already in $(basename "$APPLIED"), $failed not applied$( [[ "$DRY" == true ]] && printf ' (dry run: nothing mutated, nothing logged)')"
[[ "$failed" -eq 0 ]] || exit 1
