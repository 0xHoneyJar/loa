#!/usr/bin/env bash
# reproduce.sh — cycle-132 FR-10: reproduce every grade, row and read from a fresh clone of the stage-1 record commit
# (PREREGISTRATION §13; DEC-0811 sandbox-lite record; DEC-0812 live-rerun sample; analysis addendum 17).
#
# Run from the clone root (`git clone --branch record/cycle-132-conclusive-review-catch --single-branch <url> <empty dir>`):
#   evals/analysis/c132/reproduce.sh [--scratch DIR] [--jobs N] [--batches CSV] [--steps reconstruct,grade,rows,reads,report]
#                                    [--report F] [--no-env-check] [--live-sample] [--max-usd USD] [--dry-run]
# Steps:
#   0. environment — the Docker image loa-ablation:258 digest equals the registration's image_digest; the pinned pipeline tree
#      (evals/harness, evals/suites, evals/fixtures, the suite root's tasks/ and MANIFEST.sha256; judge-sample.sh and
#      defect-descriptions.py excepted as analysis-side tooling, addendum 12) is byte-identical between the pin fbd36a0c and HEAD;
#      python3, jq, bash, docker present; the lite tree evals/results/ablation-2.0/c132-lite/INDEX.json present. --no-env-check records
#      the mismatch instead of stopping (exit 2 otherwise).
#   1–5. record_lite.py reproduce: reconstruct every recorded run directory (recorded meta/transcripts/eval/grading + the sandbox-lite set
#      + the fixture's pr/ files, sha-checked against sandbox-manifest.json), re-grade every session and cell (container executor, the
#      batch MANIFEST's tasks_dir and allow_partial; --union per matched cell), re-row every tracked row (ablation-row.sh as run-ablation.sh
#      calls it), re-run the reads (--make-inputs, --final with --judge and --sensitivity-grades, --placebo) under the registration the
#      tracked reads were taken under (REGISTRATION-15), and compare every artefact's sha256 with the record; write the report.
#   6. --live-sample: run-ablation.sh at the pin for the DEC-0812 sample — review-r24 in a1_full, a0_bare_matched and a1_review_only,
#      one trial — into <scratch>/live with the tracked image self-check log (grimoires/loa/reports/ablation-2.0/self-check-c132.txt, the
#      runner's DEC-0435 gate; the batch driver passed the same) (needs the operator's model credentials; recorded cost USD 50, the runner's conservative estimate USD 104; --max-usd default 110), then the rerun grades
#      against the recorded arm range on review-r24 are appended to the report.
# Exit: 0 everything reproduced (and the live sample inside range when run); 1 a difference, named in the report; 2 environment or usage.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"; cd "$ROOT"
PIN=fbd36a0c9880b244af08133013f3b6959b085c94
SUITE=grimoires/loa/evals/ablation-2.0-c132
REG=$SUITE/REGISTRATION-15.json
ROWS=grimoires/loa/reports/review-catch-c132/rows.jsonl
FINAL=grimoires/loa/reports/ablation-2.0/c132-final
JUDGE=grimoires/loa/reports/ablation-2.0/c132-judge
SENS=grimoires/loa/reports/ablation-2.0/c132-sensitivity-grades
POWER=grimoires/loa/reports/ablation-2.0/power-c132/power.json
LITE=evals/results/ablation-2.0/c132-lite
scratch="${REPRO_SCRATCH:-$ROOT/.repro-scratch}"; jobs=4; batches=""; steps=reconstruct,grade,rows,reads,report; report=grimoires/loa/a2a/sprint-271/reproduction/report.md
envcheck=1; live=0; maxusd=110; dry=0
while (( $# )); do case "$1" in
  --scratch) scratch="$2"; shift 2;; --jobs) jobs="$2"; shift 2;; --batches) batches="$2"; shift 2;; --steps) steps="$2"; shift 2;;
  --report) report="$2"; shift 2;; --no-env-check) envcheck=0; shift;; --live-sample) live=1; shift;; --max-usd) maxusd="$2"; shift 2;;
  --dry-run) dry=1; shift;; -h|--help) sed -n '2,24p' "$0"; exit 0;; *) echo "unknown argument: $1" >&2; exit 2;; esac; done
mkdir -p "$scratch"
env_json="$scratch/environment.json"
head_sha="$(git rev-parse HEAD)"
img="$(docker image inspect loa-ablation:258 --format '{{.Id}}' 2>/dev/null || echo missing)"
want_img="$(jq -r .image_digest "$REG")"
pin_same=1; git diff --quiet "$PIN" HEAD -- evals/harness evals/suites evals/fixtures "$SUITE/tasks" "$SUITE/MANIFEST.sha256" \
  ':(exclude)evals/harness/judge-sample.sh' ':(exclude)evals/harness/defect-descriptions.py' || pin_same=0
lite_ok=0; [ -f "$LITE/INDEX.json" ] && lite_ok=1
jq -n --arg head "$head_sha" --arg pin "$PIN" --arg img "$img" --arg want "$want_img" --argjson pin_same "$pin_same" --argjson lite "$lite_ok" \
  --arg py "$(python3 --version 2>&1)" --arg jq "$(jq --version 2>&1)" --arg bash "$BASH_VERSION" --arg reg "$(sha256sum "$REG" | cut -d' ' -f1)" \
  --arg host "$(uname -srm)" '{clone_head: $head, pipeline_pin: $pin, pin_tree_identical_to_head: ($pin_same == 1), image_digest: $img,
    image_digest_registered: $want, image_matches: ($img == $want), lite_tree_present: ($lite == 1), registration_sha256: $reg,
    python: $py, jq: $jq, bash: $bash, host: $host}' > "$env_json"
echo "reproduce.sh: environment → $env_json"; jq -c . "$env_json"
if (( envcheck )); then
  [ "$img" = "$want_img" ] || { echo "image digest $img != registered $want_img (use --no-env-check to record and continue)" >&2; exit 2; }
  (( pin_same )) || { echo "pipeline tree differs between the pin $PIN and HEAD $head_sha" >&2; exit 2; }
  (( lite_ok )) || { echo "no lite tree at $LITE" >&2; exit 2; }
fi
args=(reproduce --record-root "$ROOT" --scratch "$scratch" --jobs "$jobs" --steps "$steps" --rows "$ROWS" --inputs "$FINAL/INPUTS.json"
      --tracked-reads "$FINAL" --registration "$REG" --power "$POWER" --judge "$JUDGE" --sensitivity-grades "$SENS" --pin "$PIN"
      --env-json "$env_json" --report "$report")
[ -n "$batches" ] && args+=(--batches "$batches"); (( dry )) && args+=(--dry-run)
rc=0; python3 -I evals/analysis/c132/record_lite.py "${args[@]}" || rc=$?
echo "reproduce.sh: record_lite.py reproduce exit $rc; report $report"
if (( live )) && (( ! dry )); then
  L="$scratch/live"; mkdir -p "$L"
  echo "reproduce.sh: live sample (DEC-0812) — review-r24 × a1_full,a0_bare_matched,a1_review_only × 1 trial at the pin, cap USD $maxusd"
  bash evals/harness/run-ablation.sh --source-commit "$PIN" --registration "$REG" --arms a1_full,a0_bare_matched,a1_review_only --tasks review-r24 \
    --trials-review 1 --concurrency 3 --run-cap 45 --batch c132-repro-live --results-root "$L" --suite-root "$SUITE" --allow-partial \
    --batch-context c132-repro-live --max-usd "$maxusd" --self-check-log grimoires/loa/reports/ablation-2.0/self-check-c132.txt \
    --pre-registration-ref "REPRODUCE.md: DEC-0812 live sample under REGISTRATION-15 sha256 $(jq -r .supersedes "$SUITE/REGISTRATION-16.json") pin $PIN" \
    || echo "reproduce.sh: run-ablation.sh exit $? (recorded in the report)"
  python3 -I - "$ROWS" "$L/runs.jsonl" "$report" <<'PY'
import json, sys
rows_p, live_p, report_p = sys.argv[1:4]
def load(p):
    try: return [json.loads(l) for l in open(p, encoding="utf-8") if l.strip()]
    except FileNotFoundError: return []
rec = [r for r in load(rows_p) if r.get("task_id") == "review-r24"]
live = [r for r in load(live_p) if r.get("task_id") == "review-r24"]
L = ["", "## Sampled live rerun (DEC-0812: review-r24, one trial per arm, at the pin)", "",
     "| arm | recorded recall_pm3 (trials 1, 2) | recorded range | rerun recall_pm3 | status | inside range |", "|---|---|---|---|---|---|"]
ok = True
for arm in ("a1_full", "a0_bare_matched", "a1_review_only"):
    rr = sorted((r.get("defect_catch_rate_pm3") for r in rec if r.get("arm") == arm), key=lambda x: (x is None, x))
    vals = [v for v in rr if isinstance(v, (int, float))]
    lo, hi = (min(vals), max(vals)) if vals else (None, None)
    lv = [r for r in live if r.get("arm") == arm]
    got = lv[0].get("defect_catch_rate_pm3") if lv else None; st = lv[0].get("status") if lv else "not run"
    inside = isinstance(got, (int, float)) and lo is not None and lo <= got <= hi
    ok = ok and inside
    L.append("| %s | %s | [%s, %s] | %s | %s | %s |" % (arm, ", ".join("%.4f" % v for v in vals), lo, hi, got, st, "yes" if inside else "NO"))
L += ["", "A rerun grade inside the recorded arm range confirms the apparatus; one outside is a named discrepancy. Spend: see runs.jsonl under the live scratch."]
with open(report_p, "a", encoding="utf-8") as f: f.write("\n".join(L) + "\n")
sys.exit(0 if ok else 1)
PY
  lrc=$?; (( lrc == 0 )) || rc=1
fi
exit "$rc"
