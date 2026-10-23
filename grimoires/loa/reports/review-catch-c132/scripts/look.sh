#!/usr/bin/env bash
# look.sh <k> [name] — (name defaults to look-<k>; e.g. look-1-amended for a §12 re-read) the pre-registered look k over the completed groups 1..k (batches c132-g<g>-{a1,a2,a3,b}); smoke rows excluded
# (they decide nothing). Writes grimoires/loa/reports/ablation-2.0/c132-looks/look-<k>/{rows.jsonl,INPUTS.json,look-<k>.md,look-<k>.json}.
set -euo pipefail
cd /home/merlin/Documents/thj/code/loa
k="$1"; NAME="${2:-look-$1}"; ROOT=grimoires/loa/evals/ablation-2.0-c132; REG=$ROOT/REGISTRATION-13.json
source ~/.cache/loa/cycle-132/registration.txt   # REG_SHA, PIN, REG (bare file name)
REG="$ROOT/${REG##*/}"   # the binding registration: REGISTRATION-8.json (addendum 9)
OUT=grimoires/loa/reports/ablation-2.0/c132-looks/$NAME; mkdir -p "$OUT"
rows=$OUT/rows.jsonl; : > "$rows"
# the runner rows every batch into the shared <results-root>/runs.jsonl; select the completed groups 1..k by batch name
jq -c --argjson k "$k" 'select(.batch | test("^c132-g[1-9]-(a1|a2|a3|b)$")) | select((.batch | capture("^c132-g(?<g>[0-9])").g | tonumber) <= $k)' evals/results/ablation-2.0/runs.jsonl >> "$rows"
echo "rows: $(wc -l < "$rows")"
python3 -I evals/analysis/c132/reads-c132.py --rows "$rows" --results-root evals/results/ablation-2.0 --make-inputs --out "$OUT" --pin "$PIN" --label-set v2 --suite-root "$ROOT"
python3 -I evals/analysis/c132/reads-c132.py --rows "$rows" --results-root evals/results/ablation-2.0 --inputs "$OUT/INPUTS.json" --registration "$REG" --look "$k" --power grimoires/loa/reports/ablation-2.0/power-c132/power.json --name "$NAME" --out "$OUT"
sed -n 1,40p "$OUT/$NAME.md"
