#!/usr/bin/env bash
# final.sh <placebo|judge-sample|final> — Sprint 271 reads over every group's batches (c132-g{1,2,3}-{a1,a2,a3,b}); smoke excluded.
#   placebo      : the 200-shuffle placebo on the Phase 1 rows (PREREGISTRATION §8) → reports/ablation-2.0/c132-final/placebo-phase1.{md,json}
#   judge-sample : judge-sample.sh over the rows → reports/ablation-2.0/c132-judge/{key.json,packets/}; then blind-session.sh (Opus 5.5) over the
#                  packets with --spend-row evals/results/ablation-2.0/c132-phase0/rows.jsonl, then judge_agree.py → c132-judge/result.json
#   final        : reads-c132.py --final (+ --judge c132-judge/result.json when present) → reports/ablation-2.0/c132-final/final.{md,json}
set -euo pipefail
cd /home/merlin/Documents/thj/code/loa
what="$1"; ROOT=grimoires/loa/evals/ablation-2.0-c132
source ~/.cache/loa/cycle-132/registration.txt   # REG_SHA, PIN, REG
REGF=$ROOT/$REG
OUT=grimoires/loa/reports/ablation-2.0/c132-final; mkdir -p "$OUT"
rows=$OUT/rows.jsonl; : > "$rows"
# the runner rows every batch into the shared <results-root>/runs.jsonl; select every group batch by name (smoke excluded)
jq -c 'select(.batch | test("^c132-g[1-9]-(a1|a2|a3|b)$"))' evals/results/ablation-2.0/runs.jsonl >> "$rows"
echo "rows: $(wc -l < "$rows")"
python3 -I evals/analysis/c132/reads-c132.py --rows "$rows" --results-root evals/results/ablation-2.0 --make-inputs --out "$OUT" --pin "$PIN" --label-set v2 --suite-root "$ROOT"
case "$what" in
  placebo) python3 -I evals/analysis/c132/reads-c132.py --rows "$rows" --results-root evals/results/ablation-2.0 --inputs "$OUT/INPUTS.json" --registration "$REGF" --placebo --name placebo-phase1 --out "$OUT"; sed -n 1,20p "$OUT/placebo-phase1.md" ;;
  judge-sample) J=grimoires/loa/reports/ablation-2.0/c132-judge; mkdir -p "$J"; D=grimoires/loa/reports/ablation-2.0/c132-judge-inputs/defect-descriptions.json; [[ -f "$D" ]] || { echo "build $D first (defect-descriptions.py)" >&2; exit 2; }; bash evals/harness/judge-sample.sh --rows "$rows" --results-root evals/results/ablation-2.0 --out "$J" --seed 20261021 --per-stratum 10 --min-total 150 --descriptions "$D"; ls "$J" ;;
  final) J=grimoires/loa/reports/ablation-2.0/c132-judge/result.json; judge=(); [[ -f "$J" ]] && judge=(--judge "$(dirname "$J")"); python3 -I evals/analysis/c132/reads-c132.py --rows "$rows" --results-root evals/results/ablation-2.0 --inputs "$OUT/INPUTS.json" --registration "$REGF" --final --power grimoires/loa/reports/ablation-2.0/power-c132/power.json ${judge[@]+"${judge[@]}"} --name final --out "$OUT"; sed -n 1,60p "$OUT/final.md" ;;
  *) echo "what must be placebo|judge-sample|final" >&2; exit 2 ;;
esac
