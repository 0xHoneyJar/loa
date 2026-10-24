#!/usr/bin/env bash
# reproduce.sh — cycle-132 FR-10: reproduce every grade, row and read from a fresh clone of the stage-1 record commit
# (PREREGISTRATION §13; DEC-0811 sandbox-lite record; DEC-0812 live-rerun sample; analysis addendum 17).
# Version: cycle-133 (sdd.md C-7; beads bd-jat0z, bd-161zz) — the worktree attestation and the live-sample gate. This
# copy is the next pipeline version: the cycle-132 record keeps its own copy, and cycle-132 is reproduced from the
# record clone (whose pipeline tree is the pin fbd36a0c's), never with this file (its own analysis tree is not the
# registered one, so the attestation below refuses it there by design). See REPRODUCE.md § 0.
#
# Run from the clone root (`git clone --branch record/cycle-132-conclusive-review-catch --single-branch <url> <empty dir>`):
#   evals/analysis/c132/reproduce.sh [--scratch DIR] [--jobs N] [--batches CSV] [--steps reconstruct,grade,rows,reads,report]
#                                    [--report F] [--no-env-check] [--live-sample] [--max-usd USD] [--dry-run]
#                                    [--pin SHA] [--analysis-pin SHA] [--registration F]
# Steps:
#   0. environment — refused (exit 2, before any write) unless every clause holds; --no-env-check records each clause
#      in environment.json (env_check "skipped") and continues; a clause that is false stays false:
#      - pipeline_tree_identical_to_pin: the WORKING TREE's evals/harness, evals/suites, evals/fixtures, the suite
#        root's tasks/ and MANIFEST.sha256 equal the pin (git diff --quiet <pin> -- <paths>); judge-sample.sh and
#        defect-descriptions.py are analysis-side tooling (addendum 12) and are compared in the next clause instead;
#      - analysis_tree_identical_to_pin: the working tree's evals/analysis/c132 and those two tools equal the analysis
#        pin (default 6f01e57d, the analysis_tree of REGISTRATION-17.json, the last registration of the chain);
#      - worktree_clean: git status --porcelain --untracked-files=all over every compared path is empty (bytecode
#        caches __pycache__/, *.pyc, .pytest_cache/ excepted: the engine itself writes them);
#      - pinned_trees_identical_to_worktree = the three above; image_matches: loa-ablation:258's digest equals the
#        registration's image_digest; lite_tree_present: evals/results/ablation-2.0/c132-lite/INDEX.json (a build
#        --only writes INDEX-only.json, which does not count); environment_matches = all of them.
#      environment.json also records git_describe (git describe --always --dirty), python, jq, bash, host and the
#      registration's sha256.
#   1–5. record_lite.py reproduce: reconstruct every recorded run directory (recorded meta/transcripts/eval/grading + the sandbox-lite set
#      + the fixture's pr/ files, sha-checked against sandbox-manifest.json), re-grade every session and cell (container executor, the
#      batch MANIFEST's tasks_dir and allow_partial; --union per matched cell), re-row every tracked row (ablation-row.sh as run-ablation.sh
#      calls it), re-run the reads (--make-inputs, --final with --judge and --sensitivity-grades, --placebo) under the registration the
#      tracked reads were taken under (REGISTRATION-15), and compare every artefact's sha256 with the record; write the report.
#   6. --live-sample: only when step 1–5 exited 0 and environment_matches is true (otherwise a "not run" section naming
#      the reasons is appended and the exit is 3); run-ablation.sh at the pin for the DEC-0812 sample — review-r24 in
#      a1_full, a0_bare_matched and a1_review_only, one trial — into <scratch>/live with the tracked image self-check log
#      (grimoires/loa/reports/ablation-2.0/self-check-c132.txt, the runner's DEC-0435 gate; the batch driver passed the
#      same) and --pre-registration-ref naming the --registration file and its sha256 (needs the operator's model
#      credentials; recorded cost USD 50, the runner's conservative estimate USD 104; --max-usd default 110). The report
#      gains the rerun grade per arm against the range of the VALID recorded review-r24 rows (common.py's validity
#      filter on the row and its recorded grade.json), the invalid rows left out named, and the environment verdicts.
#   --pin / --analysis-pin / --registration override the cycle-132 defaults (a later record, or a test).
# Exit (sdd.md § 5.4): 0 every artefact reproduced (and the live sample, when requested, ran for every arm; a rerun
#   grade outside the recorded range is a named discrepancy in the report, not a failure); 1 a reproduction difference
#   or an engine failure, named in the report; 2 usage, or the environment refused (nothing written); 3 the live sample
#   was requested but not run, or ran incompletely (engine failure, environment mismatch, runner exit, an arm without a
#   completed row), the reason in the report.
set -euo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"; cd "$ROOT"
PIN=fbd36a0c9880b244af08133013f3b6959b085c94
ANALYSIS_PIN=6f01e57d9d0b11eca1fd8620264ef3d4487debe1   # REGISTRATION-17.json analysis_tree (= the record's analysis tree)
SUITE=grimoires/loa/evals/ablation-2.0-c132
REG=$SUITE/REGISTRATION-15.json
ROWS=grimoires/loa/reports/review-catch-c132/rows.jsonl
FINAL=grimoires/loa/reports/ablation-2.0/c132-final
JUDGE=grimoires/loa/reports/ablation-2.0/c132-judge
SENS=grimoires/loa/reports/ablation-2.0/c132-sensitivity-grades
POWER=grimoires/loa/reports/ablation-2.0/power-c132/power.json
LITE=evals/results/ablation-2.0/c132-lite
RESULTS=evals/results/ablation-2.0
scratch="${REPRO_SCRATCH:-$ROOT/.repro-scratch}"; jobs=4; batches=""; steps=reconstruct,grade,rows,reads,report; report=grimoires/loa/a2a/sprint-271/reproduction/report.md
envcheck=1; live=0; maxusd=110; dry=0
usage_err() { echo "reproduce.sh: $1 (see --help)" >&2; exit 2; }
while (( $# )); do case "$1" in
  --scratch) scratch="${2:?}"; shift 2;; --jobs) jobs="${2:?}"; shift 2;; --batches) batches="${2:?}"; shift 2;; --steps) steps="${2:?}"; shift 2;;
  --report) report="${2:?}"; shift 2;; --no-env-check) envcheck=0; shift;; --live-sample) live=1; shift;; --max-usd) maxusd="${2:?}"; shift 2;;
  --pin) PIN="${2:?}"; shift 2;; --analysis-pin) ANALYSIS_PIN="${2:?}"; shift 2;; --registration) REG="${2:?}"; shift 2;;
  --dry-run) dry=1; shift;; -h|--help) awk 'NR > 1 && !/^#/ { exit } NR > 1' "$0"; exit 0;; *) usage_err "unknown argument: $1";; esac; done
for p in "$PIN" "$ANALYSIS_PIN"; do
  [[ "$p" =~ ^[0-9a-f]{7,40}$ ]] && git rev-parse --verify --quiet "$p^{commit}" >/dev/null \
    || usage_err "not a commit of this repository: $p"
done
[[ -f "$REG" && -r "$REG" ]] || usage_err "registration unreadable: $REG"
want_img="$(jq -er .image_digest "$REG")" || usage_err "registration has no image_digest: $REG"

PIPELINE=(evals/harness evals/suites evals/fixtures "$SUITE/tasks" "$SUITE/MANIFEST.sha256"
          ':(exclude)evals/harness/judge-sample.sh' ':(exclude)evals/harness/defect-descriptions.py')
ANALYSIS=(evals/analysis/c132 evals/harness/judge-sample.sh evals/harness/defect-descriptions.py)
NOISE=(':(exclude,glob)**/__pycache__/**' ':(exclude,glob)**/*.pyc' ':(exclude,glob)**/.pytest_cache/**')
head_sha="$(git rev-parse HEAD)"
describe="$(git describe --always --dirty)"
img="$(docker image inspect loa-ablation:258 --format '{{.Id}}' 2>/dev/null || echo missing)"
reg_sha="$(python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$REG")"
pipe_same=1; git diff --quiet "$PIN" -- "${PIPELINE[@]}" "${NOISE[@]}" || pipe_same=0
ana_same=1; git diff --quiet "$ANALYSIS_PIN" -- "${ANALYSIS[@]}" "${NOISE[@]}" || ana_same=0
dirty="$(git status --porcelain --untracked-files=all -- evals/harness evals/suites evals/fixtures "$SUITE/tasks" \
  "$SUITE/MANIFEST.sha256" evals/analysis/c132 "${NOISE[@]}")"
clean=1; [ -z "$dirty" ] || clean=0
lite_ok=0; [ -f "$LITE/INDEX.json" ] && lite_ok=1
img_ok=0; [ "$img" = "$want_img" ] && img_ok=1
trees_ok=$(( pipe_same && ana_same && clean ))
env_ok=$(( trees_ok && img_ok && lite_ok ))
env_doc="$(jq -n --arg head "$head_sha" --arg describe "$describe" --arg pin "$PIN" --arg apin "$ANALYSIS_PIN" --arg img "$img" \
  --arg want "$want_img" --argjson pipe "$pipe_same" --argjson ana "$ana_same" --argjson clean "$clean" --argjson trees "$trees_ok" \
  --argjson lite "$lite_ok" --argjson envok "$env_ok" --arg check "$( (( envcheck )) && echo passed || echo skipped)" \
  --arg py "$(python3 --version 2>&1)" --arg jq "$(jq --version 2>&1)" --arg bash "$BASH_VERSION" --arg reg "$reg_sha" \
  --arg regpath "$REG" --arg host "$(uname -srm)" \
  '{clone_head: $head, git_describe: $describe, pipeline_pin: $pin, analysis_pin: $apin,
    pipeline_tree_identical_to_pin: ($pipe == 1), analysis_tree_identical_to_pin: ($ana == 1), worktree_clean: ($clean == 1),
    pinned_trees_identical_to_worktree: ($trees == 1), image_digest: $img, image_digest_registered: $want,
    image_matches: ($img == $want), lite_tree_present: ($lite == 1), environment_matches: ($envok == 1), env_check: $check,
    registration: $regpath, registration_sha256: $reg, python: $py, jq: $jq, bash: $bash, host: $host}')"
echo "reproduce.sh: environment"; jq -c . <<<"$env_doc"
mismatch="$(jq -r '[("image_matches","pipeline_tree_identical_to_pin","analysis_tree_identical_to_pin","worktree_clean","lite_tree_present")
  as $k | select(.[$k] != true) | "\($k) false"] | join(", ")' <<<"$env_doc")"
if (( envcheck )) && (( ! env_ok )); then
  why=()
  (( img_ok )) || why+=("image digest $img != registered $want_img")
  (( pipe_same )) || why+=("pipeline tree differs from the pin $PIN")
  (( ana_same )) || why+=("analysis tree differs from the analysis pin $ANALYSIS_PIN")
  (( clean )) || why+=("worktree not clean under the compared paths ($(head -3 <<<"$dirty" | tr '\n' ' ' | sed 's/ *$//'))")
  (( lite_ok )) || why+=("no lite tree at $LITE/INDEX.json")
  msg="$(printf '%s; ' "${why[@]}")"
  echo "reproduce.sh: environment refused: ${msg%; } — run from a clean worktree of the record (REPRODUCE.md § 0), or pass --no-env-check to record the mismatch and continue" >&2
  exit 2
fi
mkdir -p "$scratch"
env_json="$scratch/environment.json"
jq . <<<"$env_doc" > "$env_json"
echo "reproduce.sh: environment → $env_json"
args=(reproduce --record-root "$ROOT" --scratch "$scratch" --jobs "$jobs" --steps "$steps" --rows "$ROWS" --inputs "$FINAL/INPUTS.json"
      --tracked-reads "$FINAL" --registration "$REG" --power "$POWER" --judge "$JUDGE" --sensitivity-grades "$SENS" --pin "$PIN"
      --env-json "$env_json" --report "$report")
[ -n "$batches" ] && args+=(--batches "$batches"); (( dry )) && args+=(--dry-run)
erc=0; python3 -I evals/analysis/c132/record_lite.py "${args[@]}" || erc=$?
echo "reproduce.sh: record_lite.py reproduce exit $erc; report $report"
rc=0; (( erc == 0 )) || rc=1
(( live )) || exit "$rc"
if (( dry )); then echo "reproduce.sh: --dry-run: the live sample is not run"; exit "$rc"; fi
not_run=()
(( erc == 0 )) || not_run+=("engine exit $erc")
(( env_ok )) || not_run+=("environment did not match: $mismatch")
if (( ${#not_run[@]} )); then
  msg="$(printf '%s; ' "${not_run[@]}")"
  printf '\n## Sampled live rerun (DEC-0812) — not run\n\nRequested with --live-sample and not run: %s. env_check %s; git_describe %s.\n' \
    "${msg%; }" "$( (( envcheck )) && echo passed || echo skipped)" "$describe" >> "$report"
  echo "reproduce.sh: live sample not run: ${msg%; }" >&2
  exit 3
fi
L="$scratch/live"; mkdir -p "$L"
echo "reproduce.sh: live sample (DEC-0812) — review-r24 × a1_full,a0_bare_matched,a1_review_only × 1 trial at the pin, cap USD $maxusd"
rrc=0
bash evals/harness/run-ablation.sh --source-commit "$PIN" --registration "$REG" --arms a1_full,a0_bare_matched,a1_review_only --tasks review-r24 \
  --trials-review 1 --concurrency 3 --run-cap 45 --batch c132-repro-live --results-root "$L" --suite-root "$SUITE" --allow-partial \
  --batch-context c132-repro-live --max-usd "$maxusd" --self-check-log grimoires/loa/reports/ablation-2.0/self-check-c132.txt \
  --pre-registration-ref "REPRODUCE.md: DEC-0812 live sample under $(basename "$REG") sha256 $reg_sha pin $PIN" || rrc=$?
echo "reproduce.sh: run-ablation.sh exit $rrc"
lrc=0
python3 -I - "$ROOT" "$ROWS" "$L/runs.jsonl" "$report" "$env_json" "$erc" "$rrc" "$RESULTS" <<'PY' || lrc=$?
import json, os, sys
root, rows_p, live_p, report_p, env_p, erc, rrc, results = sys.argv[1:9]
sys.path.insert(0, os.path.join(root, "evals", "analysis"))
from c132 import common  # noqa: E402  (the reads' validity filter)
def load(p):
    try: return [json.loads(l) for l in open(p, encoding="utf-8") if l.strip()]
    except FileNotFoundError: return []
env = json.load(open(env_p, encoding="utf-8"))
def f4(v): return "%.4f" % v if isinstance(v, (int, float)) and not isinstance(v, bool) else str(v)
rec = [r for r in load(rows_p) if r.get("task_id") == "review-r24"]
live = [r for r in load(live_p) if r.get("task_id") == "review-r24"]
L = ["", "## Sampled live rerun (DEC-0812: review-r24, one trial per arm, at the pin)", "",
     "environment: env_check %s; image_matches %s; pinned_trees_identical_to_worktree %s; git_describe %s; engine exit %s; "
     "runner exit %s" % (env.get("env_check"), str(env.get("image_matches")).lower(),
                         str(env.get("pinned_trees_identical_to_worktree")).lower(), env.get("git_describe"), erc, rrc), "",
     "| arm | recorded recall_pm3 (valid trials) | recorded range | rerun recall_pm3 | status | inside range |", "|---|---|---|---|---|---|"]
complete, notes = int(rrc) == 0, []
for arm in ("a1_full", "a0_bare_matched", "a1_review_only"):
    vals, dropped = [], []
    for r in sorted((r for r in rec if r.get("arm") == arm), key=lambda r: r.get("trial") or 0):
        g, _gp = common.load_grade(common.run_dir_for(r, [os.path.join(root, results)]))
        c = common.build_cell(r, g)
        v = r.get("defect_catch_rate_pm3")
        if c["valid"] and isinstance(v, (int, float)):
            vals.append(v)
        else:
            dropped.append("trial %s (%s)" % (r.get("trial"), ", ".join(c["reasons"]) or "no recall_pm3"))
    lo, hi = (min(vals), max(vals)) if vals else (None, None)
    lv = [r for r in live if r.get("arm") == arm]
    got = lv[0].get("defect_catch_rate_pm3") if lv else None
    st = lv[0].get("status") if lv else "not run"
    complete = complete and st == "completed" and isinstance(got, (int, float))
    inside = isinstance(got, (int, float)) and lo is not None and lo <= got <= hi
    L.append("| %s | %s | [%s, %s] | %s | %s | %s |" % (arm, ", ".join(f4(v) for v in vals), f4(lo), f4(hi), f4(got), st,
                                                      "yes" if inside else "NO"))
    if dropped:
        notes.append("%s: %d invalid recorded row(s) left out of the range: %s." % (arm, len(dropped), "; ".join(dropped)))
L += [""] + notes + (["", "A rerun grade inside the recorded arm range confirms the apparatus; one outside is a named discrepancy, "
                          "not a failure. Spend: see runs.jsonl under the live scratch."])
if not complete:
    L += ["", "The live sample did not complete for every arm (exit 3)."]
with open(report_p, "a", encoding="utf-8") as f: f.write("\n".join(L) + "\n")
sys.exit(0 if complete else 3)
PY
(( rrc == 0 && lrc == 0 )) || exit 3
exit "$rc"
