#!/usr/bin/env bash
# final.sh <placebo|judge-sample|final> — Sprint 271 reads over every group's batches (c132-g{1,2,3}-{a1,a2,a3,b}); smoke excluded.
#   placebo      : the 200-shuffle placebo on the Phase 1 rows (PREREGISTRATION §8) → reports/ablation-2.0/c132-final/placebo-phase1.{md,json}
#   judge-sample : judge-sample.sh over the rows → reports/ablation-2.0/c132-judge/{key.json,packets/}; then blind-session.sh (Opus 5.5) over the
#                  packets with --spend-row evals/results/ablation-2.0/c132-phase0/rows.jsonl, then judge_agree.py → c132-judge/result.json
#   final        : reads-c132.py --final (+ --judge c132-judge/ when present; + --sensitivity-grades c132-sensitivity-grades/ when present, addendum 16) → reports/ablation-2.0/c132-final/final.{md,json}
# Registration (cycle-133 bd-o3a5h, Sprint 271 audit SEC-004): [--reg NAME] [--pin SHA] [--reg-sha HEX] [--registration-file F]
#   REG (a file name under the suite root, [A-Za-z0-9][A-Za-z0-9._-]*), PIN (40 hex) and REG_SHA (64 hex, must equal the
#   sha256 of the registration file) come from the flags; any flag left out is read from F (default
#   ~/.cache/loa/cycle-132/registration.txt) by whitelist — whitespace-separated REG=, PIN=, REG_SHA= tokens, '#' comment
#   lines; anything else refuses. The file is never sourced. The repository root is derived from this script's path, so
#   it runs from any cwd. Exit: 0 done; 1 a step failed; 2 usage or a refused registration (before any write).
set -euo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd -P)"; cd "$ROOT"
die() { echo "final.sh: $*" >&2; exit 2; }
what="${1:-}"; [ $# -gt 0 ] && shift
case "$what" in placebo|judge-sample|final) ;; *) die "what must be placebo|judge-sample|final";; esac
SUITE=grimoires/loa/evals/ablation-2.0-c132
REG="" PIN="" REG_SHA="" regfile="$HOME/.cache/loa/cycle-132/registration.txt"
while [ $# -gt 0 ]; do case "$1" in
  --reg) REG="${2:-}"; shift 2;; --pin) PIN="${2:-}"; shift 2;; --reg-sha) REG_SHA="${2:-}"; shift 2;;
  --registration-file) regfile="${2:-}"; shift 2;; *) die "unknown argument: $1";; esac; done
if [ -z "$REG" ] || [ -z "$PIN" ] || [ -z "$REG_SHA" ]; then
  [ -f "$regfile" ] && [ -r "$regfile" ] || die "registration values missing: pass --reg, --pin and --reg-sha, or a readable --registration-file (tried $regfile)"
  f_reg="" f_pin="" f_sha=""
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && continue
    read -r -a toks <<<"$line"
    for tok in "${toks[@]}"; do
      case "$tok" in
        REG=*) [ -z "$f_reg" ] || die "registration file $regfile: REG given twice"; f_reg="${tok#REG=}";;
        PIN=*) [ -z "$f_pin" ] || die "registration file $regfile: PIN given twice"; f_pin="${tok#PIN=}";;
        REG_SHA=*) [ -z "$f_sha" ] || die "registration file $regfile: REG_SHA given twice"; f_sha="${tok#REG_SHA=}";;
        *) die "registration file $regfile: refused token outside the whitelist (REG=, PIN=, REG_SHA=): ${tok:0:40}";;
      esac
    done
  done < "$regfile"
  [ -n "$REG" ] || REG="$f_reg"; [ -n "$PIN" ] || PIN="$f_pin"; [ -n "$REG_SHA" ] || REG_SHA="$f_sha"
fi
[[ "$REG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "registration name refused (want a file name under $SUITE): ${REG:0:60}"
[[ "$PIN" =~ ^[0-9a-f]{40}$ ]] || die "registration PIN refused (want 40 hex): ${PIN:0:60}"
[[ "$REG_SHA" =~ ^[0-9a-f]{64}$ ]] || die "registration REG_SHA refused (want 64 hex): ${REG_SHA:0:70}"
REGF=$SUITE/$REG
[ -f "$REGF" ] || die "registration file not found: $REGF"
got="$(python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$REGF")"
[ "$got" = "$REG_SHA" ] || die "registration sha256 $got of $REGF != REG_SHA $REG_SHA"
OUT=grimoires/loa/reports/ablation-2.0/c132-final; mkdir -p "$OUT"
rows=$OUT/rows.jsonl; : > "$rows"
# the runner rows every batch into the shared <results-root>/runs.jsonl; select every group batch by name (smoke excluded)
jq -c 'select(.batch | test("^c132-g[1-9]-(a1|a2|a3|b)$"))' evals/results/ablation-2.0/runs.jsonl >> "$rows"
echo "rows: $(wc -l < "$rows")"
python3 -I evals/analysis/c132/reads-c132.py --rows "$rows" --results-root evals/results/ablation-2.0 --make-inputs --out "$OUT" --pin "$PIN" --label-set v2 --suite-root "$SUITE"
case "$what" in
  placebo) python3 -I evals/analysis/c132/reads-c132.py --rows "$rows" --results-root evals/results/ablation-2.0 --inputs "$OUT/INPUTS.json" --registration "$REGF" --placebo --name placebo-phase1 --out "$OUT"; sed -n 1,20p "$OUT/placebo-phase1.md" ;;
  judge-sample) J=grimoires/loa/reports/ablation-2.0/c132-judge; mkdir -p "$J"; D=grimoires/loa/reports/ablation-2.0/c132-judge-inputs/defect-descriptions.json; [[ -f "$D" ]] || { echo "build $D first (defect-descriptions.py)" >&2; exit 2; }; bash evals/harness/judge-sample.sh --rows "$rows" --results-root evals/results/ablation-2.0 --out "$J" --seed 20261021 --per-stratum 10 --min-total 150 --descriptions "$D"; ls "$J" ;;
  final) J=grimoires/loa/reports/ablation-2.0/c132-judge/result.json; judge=(); [[ -f "$J" ]] && judge=(--judge "$(dirname "$J")"); SG=grimoires/loa/reports/ablation-2.0/c132-sensitivity-grades; sens=(); [[ -d "$SG" ]] && sens=(--sensitivity-grades "$SG"); python3 -I evals/analysis/c132/reads-c132.py --rows "$rows" --results-root evals/results/ablation-2.0 --inputs "$OUT/INPUTS.json" --registration "$REGF" --final --power grimoires/loa/reports/ablation-2.0/power-c132/power.json ${judge[@]+"${judge[@]}"} ${sens[@]+"${sens[@]}"} --name final --out "$OUT"; sed -n 1,60p "$OUT/final.md" ;;
esac
