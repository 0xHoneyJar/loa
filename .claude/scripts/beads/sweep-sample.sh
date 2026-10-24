#!/usr/bin/env bash
# =============================================================================
# sweep-sample.sh — the 10 % re-verification sample of the proposed closures (cycle-133 C-13, FR-13)
#
# Usage:
#   sweep-sample.sh --manifests DIR --out FILE [--seed 20261023] [--pct 10]
#   sweep-sample.sh --check SAMPLE VERIFIED [--manifests DIR]
#
#   draw:   collects every closure row (closed-implemented, closed-obsolete) across manifest-<k>.jsonl,
#           sorts them by id, shuffles with the seed (python's random.Random(seed).shuffle) and writes the
#           first ceil(pct %) rows to FILE as {id, category, evidence, batch} — deterministic for a seed
#   check:  VERIFIED holds the second Explore's rows {id, agree: true|false, evidence}; exit 0 when every
#           sampled id has a row and every row agrees (several rows for one id: any disagreement counts); else
#           lists the disagreements with their batches (the batch is re-swept before anything is applied) and
#           exits 1. With --manifests DIR the manifests' digest now must equal the one the sample carries
#           (manifests_sha256 on every row), so a sample drawn from older manifests cannot pass.
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
  # fail closed (review round 1 MEDIUM): both files must parse as JSON Lines and the sample must hold at least one row
  jq -e -s 'all(.[]; type == "object" and (.id | type) == "string")' "$SAMPLE" >/dev/null 2>&1 || { echo "sweep-sample: $SAMPLE does not parse as JSON Lines rows with ids" >&2; exit 1; }
  jq -e -s 'all(.[]; type == "object" and (.id | type) == "string")' "$VERIFIED" >/dev/null 2>&1 || { echo "sweep-sample: $VERIFIED does not parse as JSON Lines rows with ids" >&2; exit 1; }
  [[ "$(grep -c '^{' "$SAMPLE" || true)" -ge 1 ]] || { echo "sweep-sample: $SAMPLE holds no sampled closure — nothing was verified" >&2; exit 1; }
  bad=0
  # the draw must be current: when --manifests is given, the manifests' digest now must equal the one the sample carries
  if [[ -n "$MAN" ]]; then
    shopt -s nullglob; MF=("$MAN"/manifest-*.jsonl); shopt -u nullglob
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../compat-lib.sh"
    now="$(for f in "${MF[@]}"; do basename "$f"; sha256_portable "$f" | cut -d' ' -f1; done | sha256_portable | cut -d' ' -f1)"
    was="$(jq -r '.manifests_sha256 // empty' "$SAMPLE" | sort -u | head -1)"
    [[ -n "$was" && "$was" == "$now" ]] || { echo "sweep-sample: the manifests changed since this sample was drawn (sample $was, now $now) — re-draw" >&2; exit 1; }
  fi
  while IFS=$'\t' read -r id batch; do
    n_rows="$(jq -c --arg id "$id" 'select(.id == $id)' "$VERIFIED" | wc -l)"
    if [[ "$n_rows" -eq 0 ]]; then echo "sweep-sample: $id (batch $batch): no verification row" >&2; bad=$((bad + 1)); continue; fi
    # several rows for one id: any row that does not agree counts as a disagreement (a later re-check wins over a first look)
    if jq -e --arg id "$id" 'select(.id == $id) | select(.agree != true)' "$VERIFIED" >/dev/null 2>&1 && [[ -n "$(jq -c --arg id "$id" 'select(.id == $id) | select(.agree != true)' "$VERIFIED")" ]]; then
      echo "sweep-sample: $id (batch $batch): DISAGREES — $(jq -r --arg id "$id" 'select(.id == $id) | select(.agree != true) | .evidence // ""' "$VERIFIED" | head -1 | cut -c1-160)" >&2; bad=$((bad + 1))
    fi
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
# shellcheck source=../compat-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../compat-lib.sh"
MAN_DIGEST="$(for f in "${MFILES[@]}"; do basename "$f"; sha256_portable "$f" | cut -d' ' -f1; done | sha256_portable | cut -d' ' -f1)"
ALLF="$(mktemp)"; trap 'unlink "$ALLF" 2>/dev/null' EXIT
for f in "${MFILES[@]}"; do b="$(basename "$f" .jsonl)"; jq -c --arg b "$b" --arg d "$MAN_DIGEST" 'select((.category // "") | IN("closed-implemented","closed-obsolete")) | {id, category, evidence, batch: $b, manifests_sha256: $d}' "$f"; done > "$ALLF"
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
