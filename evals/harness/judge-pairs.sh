#!/usr/bin/env bash
# =============================================================================
# judge-pairs.sh — rater-confirmed credit for ONE review-catch grade (loa-smol REPORT.md §1–2; judge-v2 result;
# grader 1.5.0 --judge-verdicts). Every credited (finding, defect) pair of a run — or of a matched cell's union — is
# put to blind raters as a packet; their verdicts become the grader's verdicts file; the grade is re-read with
# recall_judged beside recall_pm3.
#
# Why: the grader credits a defect when a citation lands within ±3 lines of a site (pm3). Two blind rater families
# agree with each other (κ 0.85–0.88) and not with the grader (κ 0.24 on the cut packets, 0.36 with the citing bullet
# shown): 53–72 % of pm3 credits were judged not to describe the defect (loa-smol runs/judge-v2/result{,-full}/RESULTS.md).
# The rule under test: a credit needs the pm3 anchor AND a blind-rater majority `describes`; pm3 alone is a sensitivity.
#
# Usage:
#   judge-pairs.sh <run-dir> [--union] [--task-id T] [--suite-root DIR] [--repo-root DIR] [--out DIR]
#                  [--raters codex,claude] [--max-usd 6] [--session-usd 6] [--chunk 64] [--dry-run]
#                  [--descriptions FILE] [--claude-model ID] [--codex-model ID] [--codex-bin B] [--blind-session B]
#                  [--executor container|host] [--claude-bin B] [--docker-bin D] [--image loa-ablation:259]
#                  [--rater-timeout-min 40] [--codex-retries 0] [--run-id ID] [--grade-out FILE] [--allow-partial] [--allow-unfrozen]
#                  [--ledger FILE] [--trace-prefix P] [--forbid TOKEN …]
#
# <run-dir>  a pipeline-run.sh run directory (<root>/<batch>/<arm>/<task>-t<n>[-r<k>]); with --union a matched cell
#            (meta/cell.json, sessions/s<i>/), graded as ablation-grade.sh --union does
# Options:
#   --task-id T        the task (default: the directory name without its -t<n>[-r<k>] suffix)
#   --suite-root DIR   the suite holding tasks/<task>/task.yaml (default: the unique such root under
#                      <repo>/grimoires/loa/evals/*/; ablation-2.0 first)
#   --repo-root DIR    the repository (default: this one); fixtures and manifests resolve under it
#   --out DIR          the working directory (default <run-dir>/judge-pairs; never under grading/, which the grader
#                      recreates on every grade)
#   --raters LIST      codex, claude or codex,claude (default; the order is the rows' order)
#   --max-usd N        the Claude lane's total cap (default 6; codex runs on a subscription, cost 0)
#   --session-usd N    one blind session's cap (default 6, never above what remains of --max-usd)
#   --chunk N          packets per rater call, 1–64 (default 64; blind-session.sh's limit)
#   --dry-run          enumerate, write the packets, prompts and key; no rater, no regrade
#   --descriptions F   defect-descriptions.py's output for the blind descriptions (default
#                      <repo>/grimoires/loa/reports/ablation-2.0/c132-judge-inputs/defect-descriptions.json when present)
#   --claude-model ID  the Claude rater (default global.anthropic.claude-opus-5-5, through blind-session.sh)
#   --codex-model ID   the id recorded for the codex rater when its session rollout names none (default codex-headless);
#                      the rollout's model (~/.codex/sessions, by thread id) wins when found
#   --codex-bin B      the codex CLI (default codex); non-default models are not requested (the CLI refuses them)
#   --blind-session B  the Claude session runner (default blind-session.sh beside this script)
#   --executor, --claude-bin, --docker-bin, --image   passed to blind-session.sh (tests: host + a stub CLI)
#   --rater-timeout-min M   a codex call's deadline (default 40; a Claude session keeps blind-session.sh's 60)
#   --codex-retries N  retry a codex chunk up to N more times (default 0) when the call failed transiently — no final
#                      message, no turn.completed event, not the deadline (exit 124/137): the CLI's "model is at capacity",
#                      a timed-out model refresh, a dropped connection — pausing $LOA_JUDGE_CODEX_RETRY_S × attempt seconds
#                      (default 60) between tries; the failed try's events and stderr are kept as <chunk>.events.try<k>.jsonl /
#                      <chunk>.err.try<k>, and every try is one ledger row (the trace id gains -try<k> from the second).
#                      The Claude lane is untouched: a transient codex failure no longer discards a paid Claude session
#   --run-id ID        the grader's --run-id (default: the directory's name — what the verdict rows must name)
#   --grade-out FILE   where the regrade goes (default <run-dir>/grade.json; the previous grade.json is kept at
#                      <out>/grade.before-judge.json)
#   --allow-partial, --allow-unfrozen   passed to both grader calls (the cycle-132 suites need --allow-partial)
#   --ledger FILE      append one cost-ledger row per rater call (the .run/cost-ledger.jsonl schema: ts, trace_id,
#                      request_id, agent, provider, model, tokens_*, latency_ms, cost_micro_usd, usage_source,
#                      pricing_source, pricing_mode, phase_id, sprint_id, attempt, interaction_id, transport)
#   --trace-prefix P   the ledger rows' trace_id prefix (default judge-pairs-); the id is P<run id>-<rater>-<chunk>
#                      (a retried codex call: P<run id>-codex-<chunk>-try<k>)
#   --forbid TOKEN     a further token the packets must not carry (repeatable)
#
# Steps:
#   (a) enumerate: ablation-grade.sh <run> <task> --judge-verdicts <empty file> --out <out>/pairs-grade.json lists the
#       credited pairs {finding_id, finding_sha256, defect_key} with fixture_sha256 and the grader version — the
#       grader's own hashes, never re-derived here. Each finding id is bound to its citation through the grader's
#       grading/gates-combined.md (F-<6 hex of sha256("<file>:<line>:")>; the file without head/ or base/).
#   (b) packets: one per pair, P0001.md … in the grader's order (defect, then finding id): the finding prose located
#       as judge-sample.sh locates it (lib/judge_packets.py: the first paragraph citing the file at the region's
#       start or end line; over 1,500 chars the citing bullet(s) under the list note; cap 6,000), the cited head
#       lines ±5, the labelled defect's file, anchor lines, description (the annotators' text from --descriptions,
#       else the manifest's description, else the defect id) and head line (must_match). Never the arm, batch,
#       run id, task id, trial or grader decision: a packet carrying one refuses the run (exit 1, nothing written)
#       unless the task's PR itself carries the token (judge-sample.sh's PR-native exemption; the run id and the
#       batch name are never exempt). <out>/key.json maps packet ids to pairs — outside the packets.
#   (c) raters, each over chunks of ≤ --chunk packets. codex: the packets on stdin ("===== P0001.md =====" + the
#       file, like loa-smol runs/judge-v2), `codex exec --skip-git-repo-check -C <chunk> --sandbox read-only --json
#       -o <out>/codex/cNN.last.txt <prompt>`; the last message is the JSON object of verdicts. claude:
#       blind-session.sh --packets <chunk> --prompt <out>/prompt-claude.md --model <id> --max-usd <cap>
#       --spend-row <out>/claude-spend.jsonl → <out>/claude/cNN/labels.json. The two lanes run side by side,
#       each lane one chunk at a time (one container at a time). The prompt is judge-pairs-prompt.md (the
#       cycle-132 judge prompt's pair-item wording) with {{INPUT}} and {{DELIVERY}} filled per rater; the
#       materialised prompts and their sha256 go to <out>/prompt-{codex,claude}.md and <out>/prompts.sha256.
#   (d) verdicts: <out>/judge-verdicts.jsonl in the grader's exact row schema {run_id, finding_id, finding_sha256,
#       defect_key, fixture_sha256, grader_version, verdict, judge_model, judge_prompt_sha256, blind: true, ts} —
#       per pair one row per rater (judge_model = the rater's model id; judge_prompt_sha256 = sha256 of the prompt
#       file that rater received; verdict strict: `describes` → describes, `partially` or `does-not-describe` →
#       does_not_describe), chained through `supersedes` (each row names the sha256 of the pair's previous row),
#       then with two or more raters the majority row (judge_model "majority:<id>+<id>", judge_prompt_sha256 =
#       sha256 of judge-pairs-prompt.md): describes only when more than half the raters said describes — with
#       two raters, both; a tie is does_not_describe. The conservative rule: a credit stands only on agreement.
#       The effective verdict the grader binds is the last row of the chain; the rater rows stay as superseded
#       rows (judge.rows_superseded). A pair any configured rater left without a valid verdict gets no row and
#       stays unjudged (counted in the grade's unjudged_pairs and named in <out>/report.json).
#   (e) regrade: ablation-grade.sh … --judge-verdicts <out>/judge-verdicts.jsonl --out <grade-out>, then the file is
#       copied to <run-dir>/grading/judge-verdicts.jsonl (after the regrade: the grader recreates grading/ first; a
#       later regrade must read the copy under <out>). Prints recall_pm3 against recall_judged, the judged and
#       unjudged pair counts, each rater's describes count and spend; <out>/report.json holds the same.
#
# Exit: 0 every pair judged and the grade written; 1 a step failed (the grader refused, a packet would carry
#       provenance, no rater produced a verdict); 2 usage; 3 the grade is written but pairs stay unjudged (a rater
#       failed on a chunk, the Claude cap stopped the lane) — the report names them.
# Tested by evals/tests/judge-pairs.bats (stub codex, stub claude through blind-session.sh in host mode; no model call).
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GRADER="$SCRIPT_DIR/ablation-grade.sh"
PROMPT_TEMPLATE="$SCRIPT_DIR/judge-pairs-prompt.md"

usage() { sed -n '/^# Usage:/,/^# <run-dir>/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' >&2; exit 2; }
die() { printf 'judge-pairs: %s\n' "$*" >&2; exit "${2:-1}"; }
log() { printf 'judge-pairs: %s\n' "$*"; }

RUN="" UNION=0 TASK="" SUITE="" REPO="$REPO_ROOT" OUT="" RATERS="codex,claude" MAX_USD=6 SESSION_USD=6 CHUNK=64 DRY=0
DESCS="" CLAUDE_MODEL="global.anthropic.claude-opus-5-5" CODEX_MODEL="codex-headless" CODEX_BIN="codex" BLIND_SESSION="$SCRIPT_DIR/blind-session.sh"
EXECUTOR="" CLAUDE_BIN="" DOCKER_BIN="" IMAGE="" RATER_TIMEOUT=40 CODEX_RETRIES=0 RUN_ID="" GRADE_OUT="" LEDGER="" TRACE_PREFIX="judge-pairs-"
GRADER_FLAGS=() FORBID=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --union) UNION=1; shift ;;
    --task-id) TASK="${2:-}"; shift 2 ;;
    --suite-root) SUITE="${2:-}"; shift 2 ;;
    --repo-root) REPO="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --raters) RATERS="${2:-}"; shift 2 ;;
    --max-usd) MAX_USD="${2:-}"; shift 2 ;;
    --session-usd) SESSION_USD="${2:-}"; shift 2 ;;
    --chunk) CHUNK="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --descriptions) DESCS="${2:-}"; [[ -n "$DESCS" ]] || usage; shift 2 ;;
    --claude-model) CLAUDE_MODEL="${2:-}"; shift 2 ;;
    --codex-model) CODEX_MODEL="${2:-}"; shift 2 ;;
    --codex-bin) CODEX_BIN="${2:-}"; shift 2 ;;
    --blind-session) BLIND_SESSION="${2:-}"; shift 2 ;;
    --executor) EXECUTOR="${2:-}"; shift 2 ;;
    --claude-bin) CLAUDE_BIN="${2:-}"; shift 2 ;;
    --docker-bin) DOCKER_BIN="${2:-}"; shift 2 ;;
    --image) IMAGE="${2:-}"; shift 2 ;;
    --rater-timeout-min) RATER_TIMEOUT="${2:-}"; shift 2 ;;
    --codex-retries) CODEX_RETRIES="${2:-}"; shift 2 ;;
    --run-id) RUN_ID="${2:-}"; shift 2 ;;
    --grade-out) GRADE_OUT="${2:-}"; shift 2 ;;
    --allow-partial|--allow-unfrozen) GRADER_FLAGS+=("$1"); shift ;;
    --ledger) LEDGER="${2:-}"; shift 2 ;;
    --trace-prefix) TRACE_PREFIX="${2:-}"; shift 2 ;;
    --forbid) [[ -n "${2:-}" ]] || usage; FORBID+=("$2"); shift 2 ;;
    -h|--help) usage ;;
    -*) printf 'judge-pairs: unknown argument %s\n' "$1" >&2; usage ;;
    *) [[ -z "$RUN" ]] || usage; RUN="$1"; shift ;;
  esac
done
[[ -n "$RUN" ]] || usage
[[ -d "$RUN" && ! -L "$RUN" ]] || die "run directory not found: $RUN"
[[ "$RATERS" =~ ^(codex|claude)(,(codex|claude))?$ && ! "$RATERS" =~ ^(codex,codex|claude,claude)$ ]] || die "--raters must be codex, claude or codex,claude" 2
[[ "$MAX_USD" =~ ^[0-9]+([.][0-9]+)?$ && "$SESSION_USD" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "--max-usd and --session-usd must be numbers" 2
[[ "$CHUNK" =~ ^[1-9][0-9]?$ && "$CHUNK" -le 64 ]] || die "--chunk must be 1-64" 2
[[ "$RATER_TIMEOUT" =~ ^[1-9][0-9]{0,2}$ ]] || die "--rater-timeout-min must be an integer 1-999" 2
[[ "$CODEX_RETRIES" =~ ^[0-9]$ ]] || die "--codex-retries must be an integer 0-9" 2
[[ "${LOA_JUDGE_CODEX_RETRY_S:-60}" =~ ^[0-9]{1,4}$ ]] || die "LOA_JUDGE_CODEX_RETRY_S must be an integer 0-9999" 2
[[ -z "$RUN_ID" || "$RUN_ID" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || die "--run-id must match [A-Za-z0-9._-]{1,128}" 2
[[ "$CLAUDE_MODEL" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]*$ ]] || die "--claude-model is not a model id" 2
[[ "$CODEX_MODEL" =~ ^[A-Za-z0-9._:/@+-]{1,200}$ ]] || die "--codex-model is not a model id" 2
[[ -z "$DESCS" || -f "$DESCS" ]] || die "descriptions file not found: $DESCS"
[[ -d "$REPO" ]] || die "repo root not found: $REPO"
[[ -f "$GRADER" && -f "$PROMPT_TEMPLATE" ]] || die "ablation-grade.sh or judge-pairs-prompt.md missing beside this script"
for t in jq python3 timeout sha256sum; do command -v "$t" >/dev/null 2>&1 || die "required tool missing: $t" 2; done
RUN="$(cd "$RUN" && pwd)"
NAME="$(basename "$RUN")"
[[ -n "$TASK" ]] || TASK="$(printf '%s' "$NAME" | sed -E 's/-t[0-9]+(-r[0-9]+)?$//')"
[[ "$TASK" =~ ^[A-Za-z0-9._-]+$ ]] || die "cannot read a task id from $NAME (pass --task-id)"
if [[ -z "$SUITE" ]]; then
  for d in "$REPO/grimoires/loa/evals/ablation-2.0" "$REPO"/grimoires/loa/evals/*/; do
    d="${d%/}"
    if [[ -f "$d/tasks/$TASK/task.yaml" ]]; then SUITE="$d"; break; fi
  done
  [[ -n "$SUITE" ]] || die "no suite root under $REPO/grimoires/loa/evals/ holds tasks/$TASK/task.yaml (pass --suite-root)"
fi
[[ -f "$SUITE/tasks/$TASK/task.yaml" ]] || die "task not found: $SUITE/tasks/$TASK/task.yaml"
[[ -n "$OUT" ]] || OUT="$RUN/judge-pairs"
[[ -n "$GRADE_OUT" ]] || GRADE_OUT="$RUN/grade.json"
if [[ -z "$DESCS" ]]; then
  d="$REPO/grimoires/loa/reports/ablation-2.0/c132-judge-inputs/defect-descriptions.json"
  [[ -f "$d" ]] && DESCS="$d"
fi
[[ -n "$RUN_ID" ]] || RUN_ID="$NAME"
[[ "$RUN_ID" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || die "the directory name $NAME is not a run id the grader accepts (pass --run-id)"
if [[ -z "$LEDGER" ]]; then :; elif [[ -d "$LEDGER" ]]; then die "--ledger is a directory: $LEDGER" 2; else case "$LEDGER" in /*) ;; *) LEDGER="$PWD/$LEDGER" ;; esac; fi
if [[ "$RATERS" == *claude* ]]; then
  [[ -f "$BLIND_SESSION" ]] || die "blind-session.sh not found: $BLIND_SESSION"
fi
if [[ "$RATERS" == *codex* && $DRY -eq 0 ]]; then
  command -v "$CODEX_BIN" >/dev/null 2>&1 || [[ -x "$CODEX_BIN" ]] || die "codex CLI not found: $CODEX_BIN" 2
fi
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
case "$OUT" in "$RUN/grading"|"$RUN/grading/"*) die "--out must not lie under $RUN/grading (the grader recreates it)" 2 ;; esac

# --- (a) enumerate the credited pairs with the grader itself ---------------------------------------------------
: > "$OUT/empty-verdicts.jsonl"
grader_args=()
if [[ $UNION -eq 1 ]]; then grader_args+=(--union "$RUN" --task-id "$TASK"); else grader_args+=("$RUN" "$TASK"); fi
grader_args+=(--suite-root "$SUITE" ${GRADER_FLAGS[@]+"${GRADER_FLAGS[@]}"} --run-id "$RUN_ID")
if ! "$GRADER" "${grader_args[@]}" --judge-verdicts "$OUT/empty-verdicts.jsonl" --out "$OUT/pairs-grade.json" > "$OUT/grader-enumerate.log" 2>&1; then
  tail -5 "$OUT/grader-enumerate.log" >&2
  die "ablation-grade.sh refused the enumeration (see $OUT/grader-enumerate.log)"
fi

# --- (b) the packets ----------------------------------------------------------------------------------------
forbid_json="$(printf '%s\n' ${FORBID[@]+"${FORBID[@]}"} | jq -R 'select(length > 0)' | jq -s -c .)"
python3 -I - "$SCRIPT_DIR/lib" "$RUN" "$OUT" "$SUITE" "$TASK" "$REPO" "$DESCS" "$CHUNK" "$RUN_ID" "$forbid_json" "$REPO/evals/suites/ablation-2.0.yaml" <<'PY'
import hashlib, json, os, re, shutil, sys

lib_dir, run, out, suite, task, repo, descs_path, chunk, run_id, forbid_json, suite_yaml = sys.argv[1:12]
chunk = int(chunk)
sys.path.insert(0, lib_dir)
from judge_packets import (CTX, ProvenanceError, cited_section, citations, defect_section, defect_sites, describe,  # noqa: E402
                           finding_section, finding_text, load_descriptions, path_matches, provenance_scan, sources, strip_side)


def die(msg):
    sys.stderr.write("judge-pairs: %s\n" % msg)
    sys.exit(1)


with open(os.path.join(out, "pairs-grade.json"), encoding="utf-8") as f:
    grade = json.load(f)
pairs = grade.get("credited_pairs")
if not isinstance(pairs, list):
    die("pairs-grade.json lists no credited_pairs (not a review-catch grade with --judge-verdicts?)")
fixture_sha, grader_version = grade.get("fixture_sha256"), grade.get("grader_version")
seeded = (grade.get("recall") or {}).get("defects_seeded")
recall_pm3 = (grade.get("recall") or {}).get("recall_pm3")

# the task's manifest and PR fixture, read as judge-sample.sh reads them
fx = mf = None
with open(os.path.join(suite, "tasks", task, "task.yaml"), encoding="utf-8") as f:
    for line in f:
        if line.startswith("review_catch:"):
            a = re.search(r"fixture:\s*([A-Za-z0-9_./-]+)", line); b = re.search(r"manifest:\s*([A-Za-z0-9_./-]+)", line)
            fx, mf = (a.group(1).rstrip(",}") if a else None), (b.group(1).rstrip(",}") if b else None)
            break
if not fx or not mf:
    die("task.yaml has no review_catch.{fixture,manifest}: %s" % task)
# resolved in the grader's order (ablation-grade.sh load_task / resolve_pr_fixture), so the packet reads the key and
# the head tree the grade was computed from
task_dir = os.path.join(suite, "tasks", task)
mpath = next((os.path.abspath(c) for c in (os.path.join(repo, mf), os.path.join(suite, mf), os.path.join(task_dir, mf))
              if os.path.isfile(c)), None)
if not mpath:
    die("manifest not found: %s" % mf)
with open(mpath, encoding="utf-8") as f:
    man = json.load(f)
defects = man.get("defects") or []
fixture_name = str(man.get("fixture") or os.path.basename(fx.rstrip("/")))
fixture_dir = next((os.path.abspath(c) for c in (os.path.join(task_dir, fx), os.path.join(suite, fx), os.path.join(repo, fx),
                                                 os.path.join(repo, "evals", "fixtures", fx)) if os.path.isdir(c)), None)
try:
    descriptions = load_descriptions(descs_path)
except ValueError as e:
    die(str(e))

# the grader's citations → finding ids (the C-11 derivation: F-<6 hex of sha256("<file>:<line>:")>)
cites = citations(os.path.join(run, "grading", "gates-combined.md"))
if cites is None:
    die("the grader left no grading/gates-combined.md under %s" % run)
by_id = {}
for p, a, b in cites:
    f = strip_side(p)
    fid = "F-" + hashlib.sha256(("%s:%d:" % (f, a)).encode("utf-8")).hexdigest()[:6]
    by_id.setdefault(fid, []).append((p, a, b))


def credits(c, d):
    """the grader's pm3 rule: the citation's file is the defect's and its lines reach within ±3 of a site"""
    return path_matches(c[0], d.get("file", "")) and any(not (c[2] < s - 3 or c[1] > s + 3) for s in defect_sites(d))


jcs = lambda o: json.dumps(o, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
paras = sources(run)

# the forbidden tokens: the directory's name, the run id, the task id, meta/pipeline.json's run_id and arm, every arm id
# of the suite, the batch/arm directory names when they are arm ids, --forbid; strict (never PR-native exempt): the
# directory's name, the run ids and the batch name
arm_ids = set()
if os.path.isfile(suite_yaml):
    with open(suite_yaml, encoding="utf-8") as f:
        arm_ids = set(re.findall(r"-\s*\{id:\s*([A-Za-z0-9_]+)", f.read()))
forbidden, strict = set(json.loads(forbid_json)), set()
name = os.path.basename(run)
forbidden |= {name, run_id, task}
strict |= {name, run_id}
pj = os.path.join(run, "meta", "pipeline.json")
if os.path.isfile(pj) and not os.path.islink(pj):
    try:
        with open(pj, encoding="utf-8") as f:
            meta = json.load(f)
    except ValueError:
        meta = {}
    for k in ("run_id", "arm", "batch"):
        v = meta.get(k) if isinstance(meta, dict) else None
        if isinstance(v, str) and v:
            forbidden.add(v)
            if k != "arm":
                strict.add(v)
parent, grand = os.path.basename(os.path.dirname(run)), os.path.basename(os.path.dirname(os.path.dirname(run)))
if parent in arm_ids:
    forbidden |= {parent, grand}
    strict.add(grand)
forbidden |= arm_ids
forbidden.discard("")

items, bodies, exempt_all, chunks = {}, {}, [], {}
order = sorted(pairs, key=lambda x: (int(x["defect_key"][1:]), x["finding_id"]))
for j, pr in enumerate(order, 1):
    pid = "P%04d" % j
    fid, dk = pr["finding_id"], pr["defect_key"]
    if fid not in by_id:
        die("credited pair (%s, %s) has no citation in grading/gates-combined.md" % (fid, dk))
    di = int(dk[1:]) - 1
    if not 0 <= di < len(defects):
        die("defect %s is not in the manifest" % dk)
    d = defects[di]
    # one finding id covers every citation of one file and start line (a bare line and a range, say); the pair's
    # reference is the first of them that credits this defect — the grader's credited_pairs rule
    region = next((c for c in by_id[fid] if credits(c, d)), by_id[fid][0])
    f = strip_side(region[0])
    ref = {"file": f, "anchor_line": region[1], "id": fid}
    if region[2] > region[1]:
        ref["anchor_line_end"] = region[2]
    if hashlib.sha256(jcs(ref).encode("utf-8")).hexdigest() != pr["finding_sha256"]:
        die("finding_sha256 of %s is not the hash of its citation %s:%d-%d" % (fid, f, region[1], region[2]))
    L = ["# Judge item %s\n\n" % pid,
         "Does the finding describe the labelled defect? `describes`, `partially`, or `does-not-describe`.\n\n"]
    quoted = []
    L.append(finding_section(finding_text(paras, region)))
    text, hl, resolution = cited_section(fixture_dir, list(region), d.get("file"), CTX)
    L.append(text)
    if hl is not None:
        quoted.append(hl)
    desc, dsource = describe(d, descriptions, fixture_name)
    text, q = defect_section(d, desc)
    L.append(text)
    if q is not None:
        quoted.append(q)
    body = "".join(L)
    try:
        exempt = provenance_scan(body, quoted, fixture_dir, forbidden, strict)
    except ProvenanceError as e:
        die("packet %s would carry a provenance field (%s); nothing written" % (pid, e))
    exempt_all += [{"item": pid, "token": t, "reason": "pr_native"} for t in exempt]
    bodies[pid] = body
    items[pid] = {"finding_id": fid, "finding_sha256": pr["finding_sha256"], "defect_key": dk, "region": list(region),
                  "cited_path_resolution": resolution, "description_source": dsource,
                  "finding_located": finding_text(paras, region) is not None}
ids = sorted(items)
for i in range(0, len(ids), chunk):
    chunks["c%02d" % (i // chunk + 1)] = ids[i:i + chunk]
for sub in ("packets", "chunks"):
    p = os.path.join(out, sub)
    if os.path.isdir(p):
        shutil.rmtree(p)
    os.makedirs(p)
for pid, body in bodies.items():
    with open(os.path.join(out, "packets", pid + ".md"), "w", encoding="utf-8") as f:
        f.write(body)
for c, cids in chunks.items():
    os.makedirs(os.path.join(out, "chunks", c))
    for pid in cids:
        shutil.copyfile(os.path.join(out, "packets", pid + ".md"), os.path.join(out, "chunks", c, pid + ".md"))
key = {"schema_version": 1, "run_id": run_id, "task": task, "grader_version": grader_version, "fixture_sha256": fixture_sha,
       "defects_seeded": seeded, "recall_pm3": recall_pm3, "credited_pairs": len(order),
       "findings": len({p["finding_id"] for p in order}), "defects_credited": len({p["defect_key"] for p in order}),
       "items": items, "chunks": chunks, "provenance_exempt": sorted(exempt_all, key=lambda e: (e["item"], e["token"]))}
with open(os.path.join(out, "key.json"), "w", encoding="utf-8") as f:
    f.write(json.dumps(key, sort_keys=True, indent=1) + "\n")
print("judge-pairs: run %s task %s (%s defects): %d credited pairs (%d findings, %d defects) -> %d packets in %d chunk(s); "
      "prose located for %d; descriptions %s; provenance exemptions %d" % (
          run_id, task, seeded, len(order), key["findings"], key["defects_credited"], len(order), len(chunks),
          sum(1 for it in items.values() if it["finding_located"]),
          " ".join("%s=%d" % (k, sum(1 for it in items.values() if it["description_source"] == k)) for k in ("annotators", "manifest", "id_fallback")),
          len(exempt_all)))
PY

# the prompts: the template with the per-rater input and delivery paragraphs
mk_prompt() {  # mk_prompt <rater> <file>
  python3 -I - "$PROMPT_TEMPLATE" "$1" "$2" <<'PY'
import sys
tpl, rater, dest = sys.argv[1:4]
INPUT = {"codex": "The input below (after this prompt) holds judge item files named `P0001.md`, `P0002.md`, …, each introduced by "
                  "a line `===== <file> =====`. Each item states its own question. Do not use any tools and do not read any "
                  "files: everything you need is in the input.",
         "claude": "Your working directory holds only judge item files named `P0001.md`, `P0002.md`, … — read every one of "
                   "them (use Glob to list them, then Read each). Each file is one item and states its own question."}
SHAPE = '{"P0001": {"verdict": "describes", "note": "…"}, "P0002": {"verdict": "does-not-describe", "note": "…"}}'
DELIVERY = {"codex": "Output all your verdicts as ONE JSON object as your final message — nothing before it, nothing after it, "
                     "no code fence — keyed by item id, every item in the input present exactly once:\n\n" + SHAPE +
                     "\n\nItems take only `describes`, `partially` or `does-not-describe`. Output valid JSON and nothing else.",
            "claude": "Write all your verdicts as one JSON object to `{{LABELS_PATH}}` with the Write tool, keyed by item id, every "
                      "item in the directory present exactly once:\n\n" + SHAPE +
                      "\n\nItems take only `describes`, `partially` or `does-not-describe`. Write valid JSON and nothing else. When "
                      "the file is written, stop."}
with open(tpl, encoding="utf-8") as f:
    t = f.read()
if "{{INPUT}}" not in t or "{{DELIVERY}}" not in t:
    sys.exit("judge-pairs-prompt.md lacks the {{INPUT}} or {{DELIVERY}} placeholder")
with open(dest, "w", encoding="utf-8") as f:
    f.write(t.replace("{{INPUT}}", INPUT[rater]).replace("{{DELIVERY}}", DELIVERY[rater]))
PY
}
IFS=, read -r -a RATER_LIST <<<"$RATERS"
: > "$OUT/prompts.sha256"
for r in "${RATER_LIST[@]}"; do mk_prompt "$r" "$OUT/prompt-$r.md"; (cd "$OUT" && sha256sum "prompt-$r.md") >> "$OUT/prompts.sha256"; done
TEMPLATE_SHA="$(sha256sum "$PROMPT_TEMPLATE" | cut -c1-64)"
printf '%s  judge-pairs-prompt.md (template; the majority row)\n' "$TEMPLATE_SHA" >> "$OUT/prompts.sha256"
N_PAIRS="$(jq -r '.credited_pairs' "$OUT/key.json")"
if [[ $DRY -eq 1 ]]; then
  log "dry run: packets under $OUT/packets, chunks under $OUT/chunks, key $OUT/key.json; no rater ran"
  exit 0
fi
if [[ "$N_PAIRS" -eq 0 ]]; then
  log "no credited pair: nothing to judge (recall_pm3 $(jq -r '.recall_pm3' "$OUT/key.json"))"
  exit 0
fi

# --- (c) the raters -------------------------------------------------------------------------------------------
mapfile -t CHUNKS < <(jq -r '.chunks | keys[]' "$OUT/key.json")
stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_ms() { date +%s%3N; }
ledger_row() {  # ledger_row <trace suffix> <agent> <provider> <model> <tokens json> <latency ms> <cost micro> <usage src> <pricing src> <interaction id> <transport> [resolved model]
  [[ -n "$LEDGER" ]] || return 0
  python3 -I - "$LEDGER" "$TRACE_PREFIX$RUN_ID-$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12:-}" <<'PY'
import fcntl, hashlib, json, os, sys, time
path, trace, agent, provider, model, tokens, latency, cost, usage_src, pricing_src, iid, transport, resolved = sys.argv[1:14]
ts = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()) + ".%03dZ" % int((time.time() % 1) * 1000)
tk = json.loads(tokens)
row = {"ts": ts, "trace_id": trace, "request_id": "req-" + hashlib.sha256((trace + ts).encode()).hexdigest()[:12],
       "agent": agent, "provider": provider, "model": model, "tokens_in": tk.get("in", 0), "tokens_out": tk.get("out", 0),
       "tokens_reasoning": tk.get("reasoning", 0), "tokens_cache_read": tk.get("cache_read", 0),
       "tokens_cache_creation": tk.get("cache_creation", 0), "latency_ms": int(latency), "cost_micro_usd": int(cost),
       "usage_source": usage_src, "pricing_source": pricing_src, "pricing_mode": "token", "phase_id": None, "sprint_id": None,
       "attempt": 1, "interaction_id": iid or None, "transport": transport}
if resolved:
    row["resolved_model"] = resolved
os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)
with open(path, "a", encoding="utf-8") as f:
    try:
        fcntl.flock(f, fcntl.LOCK_EX)
    except OSError:
        pass
    f.write(json.dumps(row) + "\n")
PY
}
feed() { local f; for f in "$OUT/chunks/$1"/*.md; do printf '===== %s =====\n' "$(basename "$f")"; cat "$f"; printf '\n'; done; }
codex_model_of() {  # codex_model_of <events file> → the model the session rollout names, else --codex-model
  local tid rf m
  tid="$(jq -r 'select(.type == "thread.started") | .thread_id // empty' "$1" 2>/dev/null | head -1)"
  if [[ -n "$tid" ]]; then
    rf="$(find "${CODEX_HOME:-$HOME/.codex}/sessions" -name "rollout-*-$tid.jsonl" 2>/dev/null | head -1)"
    if [[ -n "$rf" ]]; then
      m="$(grep -o -m1 '"model":"[^"]*"' "$rf" | head -1 | sed 's/"model":"//; s/"$//')"
      [[ "$m" =~ ^[A-Za-z0-9._:/@+-]{1,200}$ ]] && { printf '%s' "$m"; return; }
    fi
  fi
  printf '%s' "$CODEX_MODEL"
}
codex_lane() {
  mkdir -p "$OUT/codex"
  local c rc t0 t1 usage tid model try suffix
  for c in "${CHUNKS[@]}"; do
    for ((try = 1; try <= CODEX_RETRIES + 1; try++)); do
      rc=0; t0="$(now_ms)"; suffix=""; [[ $try -gt 1 ]] && suffix="-try$try"
      rm -f "$OUT/codex/$c.last.txt"
      printf '%s codex %s start (try %s of %s)\n' "$(stamp)" "$c" "$try" "$((CODEX_RETRIES + 1))" >> "$OUT/lanes.log"
      feed "$c" | timeout --signal=TERM --kill-after=30 "$((RATER_TIMEOUT * 60))" "$CODEX_BIN" exec --skip-git-repo-check -C "$OUT/chunks/$c" \
        --sandbox read-only --json -o "$OUT/codex/$c.last.txt" "$(cat "$OUT/prompt-codex.md")" > "$OUT/codex/$c.events.jsonl" 2> "$OUT/codex/$c.err" || rc=$?
      t1="$(now_ms)"
      printf '%s codex %s exit %s (try %s)\n' "$(stamp)" "$c" "$rc" "$try" >> "$OUT/lanes.log"
      usage="$(jq -c 'select(.type == "turn.completed") | .usage | {in: (.input_tokens // 0), out: (.output_tokens // 0), reasoning: (.reasoning_output_tokens // 0), cache_read: (.cached_input_tokens // 0)}' "$OUT/codex/$c.events.jsonl" 2>/dev/null | tail -1)"
      tid="$(jq -r 'select(.type == "thread.started") | .thread_id // empty' "$OUT/codex/$c.events.jsonl" 2>/dev/null | head -1)"
      model="$(codex_model_of "$OUT/codex/$c.events.jsonl")"
      ledger_row "codex-$c$suffix" codex-headless openai "$model" "${usage:-{\}}" "$((t1 - t0))" 0 "$([[ -n "$usage" ]] && echo actual || echo unknown)" unknown "$tid" cli:codex "$model"
      # a transient failure (no final message, no completed turn, not the deadline) is retried after a pause
      if [[ ! -s "$OUT/codex/$c.last.txt" && -z "$usage" && $rc -ne 124 && $rc -ne 137 && $try -le $CODEX_RETRIES ]]; then
        cp "$OUT/codex/$c.events.jsonl" "$OUT/codex/$c.events.try$try.jsonl" 2>/dev/null || true
        cp "$OUT/codex/$c.err" "$OUT/codex/$c.err.try$try" 2>/dev/null || true
        printf '%s codex %s transient failure (exit %s, no verdicts): retry %s of %s after %s s\n' "$(stamp)" "$c" "$rc" "$try" "$CODEX_RETRIES" \
          "$(( ${LOA_JUDGE_CODEX_RETRY_S:-60} * try ))" >> "$OUT/lanes.log"
        sleep "$(( ${LOA_JUDGE_CODEX_RETRY_S:-60} * try ))"
        continue
      fi
      break
    done
    stamp > "$OUT/codex/$c.finished"
    printf '%s\n' "$model" > "$OUT/codex/$c.model"
  done
}
claude_lane() {
  mkdir -p "$OUT/claude"
  local c rc t0 t1 spent=0 remaining cap cost usage sid args=()
  [[ -n "$EXECUTOR" ]] && args+=(--executor "$EXECUTOR")
  [[ -n "$CLAUDE_BIN" ]] && args+=(--claude-bin "$CLAUDE_BIN")
  [[ -n "$DOCKER_BIN" ]] && args+=(--docker-bin "$DOCKER_BIN")
  [[ -n "$IMAGE" ]] && args+=(--image "$IMAGE")
  for c in "${CHUNKS[@]}"; do
    remaining="$(python3 -I -c 'import sys; print("%.4f" % max(0.0, float(sys.argv[1]) - float(sys.argv[2])))' "$MAX_USD" "$spent")"
    if python3 -I -c 'import sys; sys.exit(0 if float(sys.argv[1]) < 0.01 else 1)' "$remaining"; then
      printf '%s claude %s skipped: the cap (USD %s) is spent (USD %s)\n' "$(stamp)" "$c" "$MAX_USD" "$spent" >> "$OUT/lanes.log"
      printf 'cap\n' > "$OUT/claude/$c.skipped"
      continue
    fi
    cap="$(python3 -I -c 'import sys; print("%.4f" % min(float(sys.argv[1]), float(sys.argv[2])))' "$SESSION_USD" "$remaining")"
    rc=0; t0="$(now_ms)"
    rm -rf "$OUT/claude/$c"
    printf '%s claude %s start (cap USD %s)\n' "$(stamp)" "$c" "$cap" >> "$OUT/lanes.log"
    "$BLIND_SESSION" --packets "$OUT/chunks/$c" --prompt "$OUT/prompt-claude.md" --model "$CLAUDE_MODEL" --out "$OUT/claude/$c" \
      --max-usd "$cap" --spend-row "$OUT/claude-spend.jsonl" ${args[@]+"${args[@]}"} > "$OUT/claude/$c.log" 2>&1 || rc=$?
    t1="$(now_ms)"
    printf '%s claude %s exit %s\n' "$(stamp)" "$c" "$rc" >> "$OUT/lanes.log"
    stamp > "$OUT/claude/$c.finished"
    cost="$(jq -r '.total_cost_usd // empty' "$OUT/claude/$c/cost.json" 2>/dev/null || true)"
    [[ "$cost" =~ ^[0-9]+([.][0-9]+)?$ ]] || cost="$cap"     # no readable cost: the cap is charged (the session library's rule)
    spent="$(python3 -I -c 'import sys; print("%.6f" % (float(sys.argv[1]) + float(sys.argv[2])))' "$spent" "$cost")"
    usage="$(jq -c 'select(.type == "result") | .usage // {} | {in: (.input_tokens // 0), out: (.output_tokens // 0), cache_read: (.cache_read_input_tokens // 0), cache_creation: (.cache_creation_input_tokens // 0)}' "$OUT/claude/$c/transcript.jsonl" 2>/dev/null | tail -1)"
    sid="$(jq -r 'select(.type == "system" and .subtype == "init") | .session_id // empty' "$OUT/claude/$c/transcript.jsonl" 2>/dev/null | head -1)"
    ledger_row "claude-$c" claude-headless anthropic "$CLAUDE_MODEL" "${usage:-{\}}" "$((t1 - t0))" \
      "$(python3 -I -c 'import sys; print(int(round(float(sys.argv[1]) * 1e6)))' "$cost")" "$([[ -n "$usage" ]] && echo actual || echo unknown)" \
      "$(jq -r 'if .cost_source == "result" then "cli_reported" else (.cost_source // "unknown") end' "$OUT/claude/$c/cost.json" 2>/dev/null || echo cap_unmetered)" \
      "$sid" cli:claude
  done
  printf '%s\n' "$spent" > "$OUT/claude/spent.usd"
}
: > "$OUT/lanes.log"
pids=()
for r in "${RATER_LIST[@]}"; do
  case "$r" in codex) codex_lane & pids+=($!) ;; claude) claude_lane & pids+=($!) ;; esac
done
for p in "${pids[@]}"; do wait "$p" || true; done
printf '%s lanes done\n' "$(stamp)" >> "$OUT/lanes.log"

# --- (d) the verdict rows -------------------------------------------------------------------------------------
rc=0
python3 -I - "$OUT" "$RATERS" "$RUN_ID" "$CLAUDE_MODEL" "$TEMPLATE_SHA" <<'PY' || rc=$?
import hashlib, json, os, re, sys

out, raters, run_id, claude_model, template_sha = sys.argv[1:6]
raters = raters.split(",")
with open(os.path.join(out, "key.json"), encoding="utf-8") as f:
    key = json.load(f)
items, chunks = key["items"], key["chunks"]
VALID = {"describes", "partially", "does-not-describe", "does_not_describe"}


def jcs(o):
    return json.dumps(o, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha(s):
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def load_json_text(t):
    t = t.strip()
    t = re.sub(r"^```(?:json)?\s*", "", t)
    t = re.sub(r"\s*```$", "", t)
    i, j = t.find("{"), t.rfind("}")
    return json.loads(t[i:j + 1])


def read_verdicts(path):
    """{item id: verdict} from a rater's JSON object (invalid or missing values dropped)"""
    try:
        with open(path, encoding="utf-8") as f:
            doc = load_json_text(f.read())
    except (OSError, ValueError):
        return {}
    got = {}
    if isinstance(doc, dict):
        for k, v in doc.items():
            verdict = v.get("verdict") if isinstance(v, dict) else v
            if isinstance(verdict, str) and verdict.strip().lower().replace("_", "-") in {"describes", "partially", "does-not-describe"}:
                got[k] = verdict.strip().lower().replace("_", "-")
    return got


def file_text(path, default=""):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return default


with open(os.path.join(out, "prompts.sha256"), encoding="utf-8") as f:
    prompt_sha = {ln.split("  ", 1)[1].strip(): ln.split("  ", 1)[0] for ln in f if "  " in ln}
rater_info, verdicts = {}, {}
for r in raters:
    per, ts_by, model = {}, {}, None
    for c in chunks:
        if r == "codex":
            got = read_verdicts(os.path.join(out, "codex", c + ".last.txt"))
            ts = file_text(os.path.join(out, "codex", c + ".finished"))
            model = model or file_text(os.path.join(out, "codex", c + ".model")) or None
        else:
            got = read_verdicts(os.path.join(out, "claude", c, "labels.json"))
            ts = file_text(os.path.join(out, "claude", c + ".finished"))
            model = claude_model
        for pid in chunks[c]:
            if pid in got:
                per[pid] = got[pid]
                ts_by[pid] = ts or None
    verdicts[r] = (per, ts_by)
    rater_info[r] = {"model": model or ("codex-headless" if r == "codex" else claude_model),
                     "prompt_sha256": prompt_sha.get("prompt-%s.md" % r), "rated": len(per),
                     "describes": sum(1 for v in per.values() if v == "describes"),
                     "partially": sum(1 for v in per.values() if v == "partially")}
strict = lambda v: "describes" if v == "describes" else "does_not_describe"
rows, judged, unjudged, majority_describes = [], [], [], 0
fallback_ts = None
for pid in sorted(items):
    it = items[pid]
    missing = [r for r in raters if pid not in verdicts[r][0]]
    if missing:
        unjudged.append({"item": pid, "finding_id": it["finding_id"], "defect_key": it["defect_key"], "missing": missing})
        continue
    prev = None
    base = {"run_id": run_id, "finding_id": it["finding_id"], "finding_sha256": it["finding_sha256"], "defect_key": it["defect_key"],
            "fixture_sha256": key["fixture_sha256"], "grader_version": key["grader_version"], "blind": True}
    ts_last = None
    for r in raters:
        v, ts = verdicts[r][0][pid], verdicts[r][1][pid]
        ts_last = ts or ts_last
        row = dict(base, verdict=strict(v), judge_model=rater_info[r]["model"], judge_prompt_sha256=rater_info[r]["prompt_sha256"],
                   ts=ts or "1970-01-01T00:00:00Z")
        if prev is not None:
            row["supersedes"] = prev
        rows.append(row)
        prev = sha(jcs(row))
    if len(raters) >= 2:
        yes = sum(1 for r in raters if strict(verdicts[r][0][pid]) == "describes")
        v = "describes" if 2 * yes > len(raters) else "does_not_describe"
        row = dict(base, verdict=v, judge_model="majority:" + "+".join(rater_info[r]["model"] for r in raters),
                   judge_prompt_sha256=template_sha, ts=ts_last or "1970-01-01T00:00:00Z", supersedes=prev)
        rows.append(row)
        majority_describes += v == "describes"
    judged.append(pid)
with open(os.path.join(out, "judge-verdicts.jsonl"), "w", encoding="utf-8") as f:
    for row in rows:
        f.write(json.dumps(row, sort_keys=True) + "\n")
rep = {"schema_version": 1, "run_id": run_id, "task": key["task"], "raters": rater_info, "credited_pairs": key["credited_pairs"],
       "judged_pairs": len(judged), "unjudged_pairs": unjudged, "rows": len(rows),
       "majority_rule": ("describes needs more than half the raters (two raters: both); a tie is does_not_describe"
                         if len(raters) >= 2 else "one rater: its strict verdict (partially counts as does_not_describe)"),
       "majority_describes": majority_describes if len(raters) >= 2 else None}
with open(os.path.join(out, "rows-report.json"), "w", encoding="utf-8") as f:
    f.write(json.dumps(rep, sort_keys=True, indent=1) + "\n")
print("judge-pairs: rows %d for %d of %d pairs (%d unjudged); %s" % (
    len(rows), len(judged), key["credited_pairs"], len(unjudged),
    "; ".join("%s %s: %d/%d rated, describes %d, partially %d" % (r, rater_info[r]["model"], rater_info[r]["rated"], key["credited_pairs"],
                                                                rater_info[r]["describes"], rater_info[r]["partially"]) for r in raters)))
if not judged:
    sys.exit(1)
PY
if [[ $rc -ne 0 ]]; then
  die "no pair received a verdict from every rater (see $OUT/lanes.log, $OUT/codex/*.err, $OUT/claude/*.log)"
fi

# --- (e) the regrade ------------------------------------------------------------------------------------------
if [[ -f "$GRADE_OUT" && ! -L "$GRADE_OUT" ]]; then cp "$GRADE_OUT" "$OUT/grade.before-judge.json"; fi
if ! "$GRADER" "${grader_args[@]}" --judge-verdicts "$OUT/judge-verdicts.jsonl" --out "$GRADE_OUT" > "$OUT/grader-regrade.log" 2>&1; then
  tail -5 "$OUT/grader-regrade.log" >&2
  die "ablation-grade.sh refused the regrade (see $OUT/grader-regrade.log)"
fi
mkdir -p "$RUN/grading"
cp "$OUT/judge-verdicts.jsonl" "$RUN/grading/judge-verdicts.jsonl"
CLAUDE_USD="$(cat "$OUT/claude/spent.usd" 2>/dev/null || echo 0)"
rc=0
python3 -I - "$OUT" "$GRADE_OUT" "$CLAUDE_USD" "$RATERS" "$RUN/grading/judge-verdicts.jsonl" <<'PY' || rc=$?
import json, os, sys
out, grade_path, claude_usd, raters, verdicts_copy = sys.argv[1:6]
with open(grade_path, encoding="utf-8") as f:
    g = json.load(f)
with open(os.path.join(out, "rows-report.json"), encoding="utf-8") as f:
    rep = json.load(f)
rec = g.get("recall") or {}
rep.update(recall_pm3=rec.get("recall_pm3"), recall_judged=g.get("recall_judged"), defects_seeded=rec.get("defects_seeded"),
           grader_judged_pairs=g.get("judged_pairs"), grader_unjudged_pairs=g.get("unjudged_pairs"),
           judge_models=(g.get("judge") or {}).get("judge_models"), verdicts_sha256=(g.get("judge") or {}).get("verdicts_sha256"),
           rows_superseded=(g.get("judge") or {}).get("rows_superseded"), grade_out=os.path.basename(grade_path),
           spend_usd={"claude": float(claude_usd), "codex": 0.0 if "codex" in raters.split(",") else None})
with open(os.path.join(out, "report.json"), "w", encoding="utf-8") as f:
    f.write(json.dumps(rep, sort_keys=True, indent=1) + "\n")
print("judge-pairs: recall_pm3 %s -> recall_judged %s (defects %s; judged pairs %s, unjudged %s; majority describes %s on %s pairs); "
      "claude USD %.4f, codex USD 0 (subscription); grade %s; verdicts %s (copy %s)" % (
          rec.get("recall_pm3"), g.get("recall_judged"), rec.get("defects_seeded"), g.get("judged_pairs"), g.get("unjudged_pairs"),
          rep.get("majority_describes"), rep["judged_pairs"], float(claude_usd), grade_path,
          os.path.join(out, "judge-verdicts.jsonl"), verdicts_copy))
sys.exit(3 if rep["unjudged_pairs"] else 0)
PY
exit "$rc"
