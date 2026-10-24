#!/usr/bin/env bash
# =============================================================================
# sweep-sample.sh — the 10 % re-verification sample of the proposed closures (cycle-133 C-13, FR-13)
#
# Usage:
#   sweep-sample.sh --manifests DIR --out FILE [--seed 20261023] [--pct 10]
#   sweep-sample.sh --check SAMPLE VERIFIED
#
#   draw:   collects every closure row (closed-implemented, closed-obsolete) across manifest-<k>.jsonl,
#           sorts them by id, shuffles with the seed (python's random.Random(seed).shuffle) and writes the
#           first ceil(pct %) rows to FILE as {id, category, evidence, batch} — deterministic for a seed
#   check:  VERIFIED holds the second Explore's rows {id, agree: true|false, evidence}; exit 0 when every
#           sampled id has a row and every row agrees; else lists the disagreements with their batches
#           (the batch is re-swept before anything is applied) and exits 1
#
# Exit: 0 · 1 disagreement or missing verification · 2 usage.
# =============================================================================
set -euo pipefail
export LC_ALL=C
MAN="" OUT="" SEED=20261023 PCT=10 CHECK=false SAMPLE="" VERIFIED=""
usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifests) MAN="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --seed) SEED="${2:-}"; shift 2 ;;
    --pct) PCT="${2:-}"; shift 2 ;;
    --check) CHECK=true; SAMPLE="${2:-}"; VERIFIED="${3:-}"; shift 3 ;;
    -h|--help) usage ;;
    *) echo "sweep-sample: unknown argument $1" >&2; usage ;;
  esac
done
command -v jq >/dev/null 2>&1 || { echo "sweep-sample: jq is required" >&2; exit 1; }
if [[ "$CHECK" == true ]]; then
  [[ -f "$SAMPLE" && -f "$VERIFIED" ]] || { echo "sweep-sample: --check needs SAMPLE and VERIFIED files" >&2; exit 2; }
  bad=0
  while IFS=$'\t' read -r id batch; do
    v="$(jq -c --arg id "$id" 'select(.id == $id)' "$VERIFIED" | head -1)"
    if [[ -z "$v" ]]; then echo "sweep-sample: $id (batch $batch): no verification row" >&2; bad=$((bad + 1)); continue; fi
    if [[ "$(jq -r '.agree' <<<"$v")" != true ]]; then echo "sweep-sample: $id (batch $batch): DISAGREES — $(jq -r '.evidence // ""' <<<"$v" | cut -c1-160)" >&2; bad=$((bad + 1)); fi
  done < <(jq -r '[.id, (.batch // "?")] | @tsv' "$SAMPLE")
  n="$(grep -c '^{' "$SAMPLE" || true)"
  if [[ "$bad" -gt 0 ]]; then
    echo "sweep-sample: $bad of $n sampled closure(s) not confirmed — re-sweep the named batch(es) before applying" >&2; exit 1
  fi
  echo "sweep-sample: all $n sampled closures confirmed by the second pass"; exit 0
fi
[[ -n "$MAN" && -n "$OUT" ]] || { echo "sweep-sample: --manifests DIR and --out FILE are required" >&2; exit 2; }
[[ "$SEED" =~ ^[0-9]+$ ]] || { echo "sweep-sample: --seed must be an integer" >&2; exit 2; }
[[ "$PCT" =~ ^[0-9]+$ && "$PCT" -ge 1 && "$PCT" -le 100 ]] || { echo "sweep-sample: --pct must be 1 … 100" >&2; exit 2; }
shopt -s nullglob; MFILES=("$MAN"/manifest-*.jsonl); shopt -u nullglob
[[ ${#MFILES[@]} -ge 1 ]] || { echo "sweep-sample: no manifest-<k>.jsonl under $MAN" >&2; exit 2; }
ALLF="$(mktemp)"; trap 'rm -f "$ALLF"' EXIT
for f in "${MFILES[@]}"; do b="$(basename "$f" .jsonl)"; jq -c --arg b "$b" 'select((.category // "") | IN("closed-implemented","closed-obsolete")) | {id, category, evidence, batch: $b}' "$f"; done > "$ALLF"
python3 -I - "$SEED" "$PCT" "$OUT" "$ALLF" <<'PY'
import json, math, random, sys
seed, pct, out, src = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3], sys.argv[4]
rows = [json.loads(l) for l in open(src, encoding="utf-8").read().splitlines() if l.strip()]
rows.sort(key=lambda r: r["id"])
if not rows:
    print("sweep-sample: no proposed closure to sample", file=sys.stderr); sys.exit(2)
random.Random(seed).shuffle(rows)
k = math.ceil(len(rows) * pct / 100)
with open(out, "w", encoding="utf-8") as f:
    for r in sorted(rows[:k], key=lambda r: r["id"]):
        f.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n")
print(f"sweep-sample: {k} of {len(rows)} proposed closures sampled (seed {seed}, {pct} %) -> {out}")
PY
