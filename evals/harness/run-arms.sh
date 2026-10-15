#!/usr/bin/env bash
# =============================================================================
# run-arms.sh — cycle-129 FR-2 control-arm driver (SDD D-2.3, DEC-0164, DEC-0171)
#
# Runs the declared control arms of one recall suite on a frozen fixture batch
# against a detached git worktree pinned at --source-commit (never the live
# tree), interleaving trials across arms so provider drift spreads evenly.
#
# Usage:
#   run-arms.sh --suite review-recall|audit-recall --arms a,b,c
#               --fixtures pr-01,pr-02,… --trials 3 --source-commit <sha>
#               [--model <id>] [--concurrency 2] [--batch <name>]
#               [--results-dir evals/results/arms] [--retry-wait <s>]
#               [--allow-unapproved] [--dry-run]
#               [--max-usd <usd> [--run-cap <usd>]] [--screen [--screen-tasks N]]
#
# Spend cap (cycle-130 FR-2, SDD §5.5): --max-usd stops launching before the
#   next trial when spent + in_flight × run_cap + est_next > max, where spent =
#   the executor-reported total_cost_usd of this invocation's completed and
#   failed rows, run_cap = --run-cap (default evals.ablation.run_cap_usd in
#   .loa.config.yaml, else 12) reserved per running trial, and est_next = the
#   mean cost of this arm's completed trials (one task type per recall suite),
#   else the pooled mean, else the suite's ab.cost_hint (or cost_hint), else 5.0.
#   While the reservation alone blocks the launch it waits for a running trial;
#   when spent + est_next > max it cuts: no further launches, running trials
#   finish, STATUS.json gets cut_reason: max_usd and cut = {reason, spent,
#   in_flight_reserved, max, trials_launched, at_trial}, state partial, exit 1.
# Screen (bd-j4lwr): --screen runs one trial of the first N fixtures (default
#   2) per arm into <results-dir>/<suite>/screen-<UTC ts>/ (its own MANIFEST,
#   STATUS, rows), prints a per-arm table (trials, mean USD, mean recall) on
#   stdout, and never writes the suite-level STATUS.json; the suite aggregate
#   skips every batch whose STATUS.json says screen: true (the marker, not the
#   directory name). --batch and --trials are ignored under --screen; without
#   --screen a --batch name starting with screen- is refused (exit 2).
#
# Per trial (fixture × arm × trial), in this order:
#   1. the fixture's SHA256SUMS entries (its files, hidden manifest and labels)
#      are verified; a drift stops the batch (state failed, exit 3). The whole
#      corpus is verified once at batch start (digest in MANIFEST.json); each
#      row records the SHA256SUMS digest seen at its trial, so approving another
#      fixture's labels mid-batch is visible and harmless
#   2. evals/harness/sandbox.sh creates the sandbox from the frozen fixture
#   3. execute-agent.sh runs the executor with EVAL_PROMPT_TREE = the pinned
#      worktree, LOA_EVAL_ARM = the arm (toggles hit the sandbox copy only),
#      LOA_EVAL_SOURCE_COMMIT, EVAL_MODEL
#   4. grade.sh grades it; the row goes to <batch>/<arm>/results.jsonl with
#      arm, trial, source_commit, model_id, seed (null: the CLI route takes
#      none) and run_date; the artifacts go under <batch>/<arm>/artifacts/
#   A trial whose executor fails for a transport reason (timeout, no result
#   event, API error, rate or session limit) is retried once after
#   --retry-wait seconds; a second failure records an error row and the arm
#   ends `partial`. Other executor failures are recorded, not retried.
#
# Layout: <results-dir>/<suite>/<batch>/{MANIFEST.json,STATUS.json,run.log,
#   <arm>/results.jsonl,<arm>/artifacts/…}; <results-dir>/<suite>/STATUS.json
#   aggregates every batch of the suite (the Sprint 2 gate and report.sh
#   --arms read it). STATUS.json: {state: running|complete|partial|failed,
#   per_arm: {<arm>: {trials_done, trials_failed, trials_planned}},
#   source_commit, model_id, started, finished}.
#
# Exit: 0 complete, 1 partial (some trial failed twice; results kept),
#       2 usage / refused before starting, 3 failed (no trial completed, or
#       the corpus drifted mid-run)
#
# Executor: Opus 5.5 (DEC-0172, amending D33/DEC-0164): the cycle-129 proof
# trial on claude-fable-5-1 was refused by a safeguard and the CLI fell back to
# Opus mid-session, so a Fable run is not homogeneous; the default --model is
# the homogeneous id. The arms therefore carry a model-transfer assumption
# (measured on Opus 5.5, the production gates run on Fable 5.1), stated in the
# report header and next to every change the arms clear.
# Tested by evals/tests/run-arms.bats (stubbed CLI; no model call).
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EVALS_DIR="$REPO_ROOT/evals"
CORPUS_DIR="$EVALS_DIR/fixtures/review-prs"
DEFAULT_MODEL="global.anthropic.claude-opus-5-5"
CACHE_ROOT="${LOA_ARMS_CACHE:-$HOME/.cache/loa/cycle-129}"
# the repository the pinned source worktree is cut from (tests point it at a
# throwaway repo so they never register a worktree in the real one)
SOURCE_REPO="${LOA_ARMS_SOURCE_REPO:-$REPO_ROOT}"

SUITE="" ARMS_CSV="" FIXTURES_CSV="" TRIALS="" SOURCE_COMMIT="" MODEL="$DEFAULT_MODEL"
CONCURRENCY=2 BATCH="" RESULTS_ROOT="$EVALS_DIR/results/arms" RETRY_WAIT=300
DRY_RUN=false ALLOW_UNAPPROVED=false
MAX_USD="" RUN_CAP="" SCREEN=false SCREEN_TASKS=2

usage() { sed -n '2,/^# =====.*$/p' "$0" | sed -n '2,68p' | sed 's/^# \{0,1\}//' >&2; exit 2; }
die() { echo "run-arms: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite) SUITE="${2:-}"; shift 2 ;;
    --arms) ARMS_CSV="${2:-}"; shift 2 ;;
    --fixtures) FIXTURES_CSV="${2:-}"; shift 2 ;;
    --trials) TRIALS="${2:-}"; shift 2 ;;
    --source-commit) SOURCE_COMMIT="${2:-}"; shift 2 ;;
    --model) MODEL="${2:-}"; shift 2 ;;
    --concurrency) CONCURRENCY="${2:-}"; shift 2 ;;
    --batch) BATCH="${2:-}"; shift 2 ;;
    --results-dir) RESULTS_ROOT="${2:-}"; shift 2 ;;
    --retry-wait) RETRY_WAIT="${2:-}"; shift 2 ;;
    --allow-unapproved) ALLOW_UNAPPROVED=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --max-usd) MAX_USD="${2:-}"; shift 2 ;;
    --run-cap) RUN_CAP="${2:-}"; shift 2 ;;
    --screen) SCREEN=true; shift ;;
    --screen-tasks) SCREEN_TASKS="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

# --- validate arguments ------------------------------------------------------
case "$SUITE" in review-recall|audit-recall) ;; *) die "--suite must be review-recall or audit-recall" ;; esac
[[ "$SCREEN" == "true" ]] && TRIALS=1
[[ "$TRIALS" =~ ^[1-9][0-9]?$ ]] || die "--trials must be an integer 1-99"
[[ "$SCREEN_TASKS" =~ ^[1-9][0-9]?$ ]] || die "--screen-tasks must be an integer 1-99"
usd_ok() { [[ "$1" =~ ^[0-9]{1,6}(\.[0-9]{1,4})?$ ]]; }
if [[ -n "$MAX_USD" ]]; then usd_ok "$MAX_USD" && [[ "$MAX_USD" != "0" ]] || die "--max-usd must be a positive amount in USD"; fi
if [[ -z "$RUN_CAP" ]]; then
  RUN_CAP="$(yq -r '.evals.ablation.run_cap_usd // ""' "$REPO_ROOT/.loa.config.yaml" 2>/dev/null || true)"
  usd_ok "$RUN_CAP" || RUN_CAP=12
fi
usd_ok "$RUN_CAP" || die "--run-cap must be an amount in USD"
[[ "$CONCURRENCY" =~ ^[1-9]$ ]] || die "--concurrency must be 1-9"
[[ "$RETRY_WAIT" =~ ^[0-9]{1,5}$ ]] || die "--retry-wait must be whole seconds"
[[ "$MODEL" =~ ^[A-Za-z0-9._:/-]+$ ]] || die "--model has unexpected characters"
[[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{7,40}$ ]] || die "--source-commit must be a hex commit id"
for tool in git jq yq python3; do command -v "$tool" >/dev/null 2>&1 || die "missing tool: $tool"; done

SUITE_FILE="$EVALS_DIR/suites/$SUITE.yaml"
[[ -f "$SUITE_FILE" ]] || die "suite file not found: $SUITE_FILE"
TASK_PREFIX="review"; [[ "$SUITE" == "audit-recall" ]] && TASK_PREFIX="audit"

IFS=',' read -r -a ARMS <<<"$ARMS_CSV"
IFS=',' read -r -a FIXTURES <<<"$FIXTURES_CSV"
if [[ "$SCREEN" == "true" && ${#FIXTURES[@]} -gt $SCREEN_TASKS ]]; then
  FIXTURES=("${FIXTURES[@]:0:$SCREEN_TASKS}")
fi
[[ ${#ARMS[@]} -gt 0 && -n "${ARMS[0]}" ]] || die "--arms is required"
[[ ${#FIXTURES[@]} -gt 0 && -n "${FIXTURES[0]}" ]] || die "--fixtures is required"
for a in "${ARMS[@]}"; do
  [[ "$a" =~ ^[a-z][a-z0-9_]{0,63}$ ]] || die "invalid arm id '$a'"
  [[ "$(A="$a" yq '[.ab.arms[]? | select(.id == strenv(A))] | length' "$SUITE_FILE")" -gt 0 ]] \
    || die "arm '$a' is not declared in $SUITE_FILE (ab.arms[])"
done
for f in "${FIXTURES[@]}"; do
  [[ "$f" =~ ^pr-[0-9]{2}$ ]] || die "invalid fixture id '$f' (want pr-NN)"
  [[ -d "$CORPUS_DIR/$f" ]] || die "fixture not found: $CORPUS_DIR/$f"
  [[ -f "$CORPUS_DIR/manifests/$f.json" ]] || die "hidden manifest not found for $f"
  [[ -f "$EVALS_DIR/tasks/$SUITE/$TASK_PREFIX-$f.yaml" ]] || die "task not found: tasks/$SUITE/$TASK_PREFIX-$f.yaml"
  if [[ "$(jq -r 'if has("approved") then .approved else true end' "$CORPUS_DIR/manifests/$f.json")" != "true" \
        && "$ALLOW_UNAPPROVED" != "true" ]]; then
    die "$f: labels.tsv is not approved yet (seed-corpus-from-record.sh --approve $f --by '<who> <date>'), or pass --allow-unapproved"
  fi
done

SRC_FULL="$(git -C "$SOURCE_REPO" rev-parse --verify --quiet "${SOURCE_COMMIT}^{commit}" 2>/dev/null)" \
  || die "source commit $SOURCE_COMMIT is not in this repository"
SRC12="${SRC_FULL:0:12}"
WORKTREE="$CACHE_ROOT/arms-src-$SRC12"

if [[ "$SCREEN" != "true" && "$BATCH" == screen-* ]]; then
  die "invalid --batch '$BATCH': the screen- prefix is reserved for --screen batches"
fi
[[ -n "$BATCH" ]] || BATCH="batch-${FIXTURES[0]}-${FIXTURES[${#FIXTURES[@]}-1]}-n${#FIXTURES[@]}"
[[ "$SCREEN" == "true" ]] && BATCH="screen-$(date -u +%Y%m%dT%H%M%SZ)"
[[ "$BATCH" =~ ^[A-Za-z0-9._-]{1,80}$ ]] || die "invalid --batch '$BATCH'"
case "$BATCH" in .|..) die "invalid --batch '$BATCH' (a batch is one child directory)" ;; esac   # audit r1 DISS-C-004
SUITE_DIR="$RESULTS_ROOT/$SUITE"
BATCH_DIR="$SUITE_DIR/$BATCH"

# est_next fallback before any actual exists: the suite's cost hint (a number,
# or a per-task-type map read at review-catch), else USD 5.0
COST_HINT="$(yq -r '(.ab.cost_hint // .cost_hint // "") | tag' "$SUITE_FILE" 2>/dev/null || true)"
if [[ "$COST_HINT" == "!!map" ]]; then
  COST_HINT="$(yq -r '(.ab.cost_hint // .cost_hint)["review-catch"] // ""' "$SUITE_FILE" 2>/dev/null || true)"
else
  COST_HINT="$(yq -r '.ab.cost_hint // .cost_hint // ""' "$SUITE_FILE" 2>/dev/null || true)"
fi
usd_ok "${COST_HINT:-x}" || COST_HINT=5.0

# --- corpus freeze ------------------------------------------------------------
# verify_corpus [<fixture>] — every SHA256SUMS entry (or one fixture's entries
# and its manifest) hashes as recorded. Prints the SHA256SUMS digest.
verify_corpus() {
  python3 -I - "$CORPUS_DIR" "${1:-}" <<'PY'
import hashlib, os, sys
corpus, only = sys.argv[1], sys.argv[2]
sums = os.path.join(corpus, "SHA256SUMS")
raw = open(sums, "rb").read()
bad = []
for line in raw.decode("utf-8").splitlines():
    if not line.strip():
        continue
    digest, rel = line.split("  ", 1)
    if only and not (rel.startswith(only + "/") or rel == f"manifests/{only}.json" or rel == "corpus.tsv"
                     or rel.startswith(f"labels/{only}.")):
        continue
    p = os.path.join(corpus, rel)
    if not os.path.isfile(p) or hashlib.sha256(open(p, "rb").read()).hexdigest() != digest:
        bad.append(rel)
# audit r1 DISS-C-002: a file present on disk but absent from SHA256SUMS is drift too
# (the seed's --check already says so; the runner must agree), else an added file
# would reach the sandbox under an unchanged corpus digest.
listed = {l.split("  ", 1)[1] for l in raw.decode("utf-8").splitlines() if l.strip()}
walk_root = os.path.join(corpus, only) if only else corpus
for root, _d, files in os.walk(walk_root):
    for f in files:
        rel = os.path.relpath(os.path.join(root, f), corpus)
        if rel == "SHA256SUMS" or rel in listed:
            continue
        if only and not (rel.startswith(only + "/")):
            continue
        bad.append(rel + " (not listed)")
if only:
    for extra in (f"manifests/{only}.json", "corpus.tsv"):
        if os.path.isfile(os.path.join(corpus, extra)) and extra not in listed:
            bad.append(extra + " (not listed)")
    ldir = os.path.join(corpus, "labels")
    if os.path.isdir(ldir):
        for f in os.listdir(ldir):
            rel = f"labels/{f}"
            if f.startswith(only + ".") and rel not in listed:
                bad.append(rel + " (not listed)")
if bad:
    print("corpus drift: " + ", ".join(bad[:10]), file=sys.stderr)
    sys.exit(1)
print(hashlib.sha256(raw).hexdigest())
PY
}
CORPUS_DIGEST="$(verify_corpus)" || die "fixture corpus does not match SHA256SUMS (run build/seed with --check first)"

# --- the planned trials (interleaved: trial-major, then fixture, then arm) ----
PLAN=()
for t in $(seq 1 "$TRIALS"); do
  for f in "${FIXTURES[@]}"; do
    for a in "${ARMS[@]}"; do PLAN+=("$a|$f|$t"); done
  done
done

json_array() { printf '%s\n' "$@" | jq -R . | jq -sc .; }

write_manifest() {  # write_manifest <path> <dry_run>
  local out="$1" dry="$2" claude_bin="${EVAL_CLAUDE_BIN:-claude}" cli_version
  cli_version="$("$claude_bin" --version 2>/dev/null | head -1 || echo unknown)"
  local harness_commit harness_dirty=false
  harness_commit="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
  [[ -n "$(git -C "$REPO_ROOT" status --porcelain -- evals/harness evals/graders evals/suites evals/tasks 2>/dev/null)" ]] && harness_dirty=true
  local per_trial
  per_trial="$(yq -r '.timeout.per_trial // 1500' "$EVALS_DIR/tasks/$SUITE/$TASK_PREFIX-${FIXTURES[0]}.yaml")"
  mkdir -p "$(dirname "$out")"
  jq -n \
    --arg suite "$SUITE" --arg batch "$BATCH" \
    --arg source_commit "$SRC_FULL" --arg source_worktree "$WORKTREE" \
    --arg harness_commit "$harness_commit" --argjson harness_dirty "$harness_dirty" \
    --arg model_id "$MODEL" --arg cli "$claude_bin" --arg cli_version "$cli_version" \
    --argjson trials "$TRIALS" --argjson concurrency "$CONCURRENCY" --argjson retry_wait "$RETRY_WAIT" \
    --argjson per_trial "$per_trial" --arg max_turns "${EVAL_MAX_TURNS:-40}" \
    --argjson arms "$(json_array "${ARMS[@]}")" --argjson fixtures "$(json_array "${FIXTURES[@]}")" \
    --argjson planned "${#PLAN[@]}" --arg digest "$CORPUS_DIGEST" \
    --arg os "$(uname -srm)" --arg bash_v "$BASH_VERSION" \
    --arg jq_v "$(jq --version 2>/dev/null)" --arg yq_v "$(yq --version 2>/dev/null)" \
    --arg py_v "$(python3 --version 2>/dev/null)" --arg git_v "$(git --version 2>/dev/null)" \
    --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson dry "$dry" \
    --arg suite_file "evals/suites/$SUITE.yaml" \
    --argjson screen "$SCREEN" --arg max_usd "$MAX_USD" --arg run_cap "$RUN_CAP" --arg cost_hint "$COST_HINT" \
    '{schema_version: 1, suite: $suite, batch: $batch, dry_run: $dry, created: $created,
      source_commit: $source_commit, source_worktree: $source_worktree,
      harness_commit: $harness_commit, harness_dirty: $harness_dirty, suite_file: $suite_file,
      model_id: $model_id,
      executor: {cli: $cli, cli_version: $cli_version, tools: "Read,Grep,Glob,Write", restricted: true,
                 permission_mode: "acceptEdits", max_turns: ($max_turns | tonumber), effort: "task/skill default",
                 timeout_per_trial_s: $per_trial, concurrency: $concurrency, retry: {transport_retries: 1, wait_s: $retry_wait},
                 subagent_model: "pinned to model_id (CLAUDE_CODE_SUBAGENT_MODEL); parent-session coupling unset",
                 seed: null},
      arms: $arms, fixtures: $fixtures, trials: $trials, trials_planned: $planned, screen: $screen,
      spend: {max_usd: (if $max_usd == "" then null else ($max_usd | tonumber) end),
              run_cap_usd: ($run_cap | tonumber), cost_hint_usd: ($cost_hint | tonumber)},
      corpus: {manifest: "evals/fixtures/review-prs/SHA256SUMS", sha256: $digest,
               verified: "every entry before the batch; the fixture'"'"'s entries before each trial"},
      environment: {os: $os, bash: $bash_v, jq: $jq_v, yq: $yq_v, python: $py_v, git: $git_v}}' > "$out.tmp"
  mv "$out.tmp" "$out"
}

if [[ "$DRY_RUN" == "true" ]]; then
  mpath="$BATCH_DIR/MANIFEST.json"
  [[ -f "$BATCH_DIR/STATUS.json" ]] && mpath="$BATCH_DIR/MANIFEST.dry-run.json"
  write_manifest "$mpath" true
  echo "run-arms (dry run): suite=$SUITE batch=$BATCH source=$SRC12 model=$MODEL worktree=$WORKTREE"
  echo "planned trials: ${#PLAN[@]} (${#FIXTURES[@]} fixtures x ${#ARMS[@]} arms x $TRIALS trials, concurrency $CONCURRENCY)"
  i=0
  for p in "${PLAN[@]}"; do
    i=$((i + 1)); IFS='|' read -r a f t <<<"$p"
    printf '%4d  %-16s %-6s trial %s  task %s-%s\n' "$i" "$a" "$f" "$t" "$TASK_PREFIX" "$f"
  done
  echo "manifest: $mpath"
  exit 0
fi

CLAUDE_BIN="${EVAL_CLAUDE_BIN:-claude}"
command -v "$CLAUDE_BIN" >/dev/null 2>&1 || [[ -x "$CLAUDE_BIN" ]] || die "executor CLI not found: $CLAUDE_BIN"

# --- the pinned source worktree -------------------------------------------------
mkdir -p "$CACHE_ROOT"
if [[ -e "$WORKTREE" ]]; then
  [[ "$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null)" == "$SRC_FULL" ]] \
    || die "$WORKTREE exists but is not at $SRC_FULL; remove it with git worktree remove"
  # audit r1 DISS-C-006: ignored files count too — an earlier run's .loa.config.yaml or
  # .run/ in the worktree would be copied into every sandbox under one recorded commit
  [[ -z "$(git -C "$WORKTREE" status --porcelain --ignored 2>/dev/null)" ]] \
    || die "$WORKTREE has local or ignored files; the pinned source must be pristine (git -C $WORKTREE status --ignored)"
else
  git -C "$SOURCE_REPO" worktree add --detach "$WORKTREE" "$SRC_FULL" >/dev/null 2>&1 \
    || die "could not create the source worktree at $WORKTREE"
fi

# --- batch directory and lock --------------------------------------------------
mkdir -p "$BATCH_DIR"
LOCK="$BATCH_DIR/.lock"
mkdir "$LOCK" 2>/dev/null || die "batch $BATCH is locked ($LOCK): another run-arms is using it"
JOBS_DIR="$BATCH_DIR/.jobs"
mkdir -p "$JOBS_DIR"
cleanup() {
  local p
  for p in $(jobs -p 2>/dev/null); do kill "$p" 2>/dev/null || true; done
  rm -rf "$JOBS_DIR" "$LOCK" 2>/dev/null || true
}
trap cleanup EXIT

if [[ -f "$BATCH_DIR/MANIFEST.json" ]] && [[ "$(jq -r '.dry_run' "$BATCH_DIR/MANIFEST.json")" == "false" ]]; then
  prev_src="$(jq -r '.source_commit' "$BATCH_DIR/MANIFEST.json")"
  prev_model="$(jq -r '.model_id' "$BATCH_DIR/MANIFEST.json")"
  [[ "$prev_src" == "$SRC_FULL" && "$prev_model" == "$MODEL" ]] \
    || die "batch $BATCH already holds results for source $prev_src / model $prev_model; use another --batch"
fi
write_manifest "$BATCH_DIR/MANIFEST.json" false
LOG="$BATCH_DIR/run.log"
log() { printf '%s %s\n' "$(date -u +%H:%M:%SZ)" "$*" | tee -a "$LOG" >&2; }

STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STATE="running"
# per-arm counters (indexed arrays parallel to ARMS — bash 3.2 has no maps)
DONE=() FAILED=() PLANNED=()
for i in "${!ARMS[@]}"; do DONE[$i]=0; FAILED[$i]=0; PLANNED[$i]=$(( ${#FIXTURES[@]} * TRIALS )); done
# spend accounting (--max-usd): batch spend, per-arm and pooled completed-cost sums
SPENT=0 CUT_JSON=null POOL_SUM=0 POOL_N=0
ARM_SUM=() ARM_N=()
for i in "${!ARMS[@]}"; do ARM_SUM[$i]=0; ARM_N[$i]=0; done
fadd() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.10g", a + b }'; }
arm_index() { local i; for i in "${!ARMS[@]}"; do [[ "${ARMS[$i]}" == "$1" ]] && { echo "$i"; return; }; done; echo -1; }

write_status() {
  local per='{}' i finished=null
  for i in "${!ARMS[@]}"; do
    per="$(jq -c --arg a "${ARMS[$i]}" --argjson d "${DONE[$i]}" --argjson f "${FAILED[$i]}" --argjson p "${PLANNED[$i]}" \
      '. + {($a): {trials_done: $d, trials_failed: $f, trials_planned: $p}}' <<<"$per")"
  done
  [[ "$STATE" != "running" ]] && finished="\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
  jq -n --arg state "$STATE" --argjson per "$per" --arg src "$SRC_FULL" --arg model "$MODEL" \
    --arg started "$STARTED" --argjson finished "$finished" --arg batch "$BATCH" --arg suite "$SUITE" \
    --argjson cut "$CUT_JSON" --argjson screen "$SCREEN" --arg spent "$SPENT" --arg max_usd "$MAX_USD" \
    '{schema_version: 1, suite: $suite, batch: $batch, state: $state, per_arm: $per,
      source_commit: $src, model_id: $model, started: $started, finished: $finished}
     + (if $max_usd == "" then {} else {spend: {spent_usd: ($spent | tonumber), max_usd: ($max_usd | tonumber)}} end)
     + (if $cut == null then {} else {cut_reason: $cut.reason, cut: $cut} end)
     + (if $screen then {screen: true} else {} end)' > "$BATCH_DIR/STATUS.json.tmp"
  mv "$BATCH_DIR/STATUS.json.tmp" "$BATCH_DIR/STATUS.json"
  # a screening batch never touches the suite-level aggregate (bd-j4lwr)
  [[ "$SCREEN" == "true" ]] || aggregate_status
}

# The suite-level STATUS.json merges every batch: counters add per arm; the
# state is failed > running > partial > complete; source/model must agree.
# Screen batches are excluded by their STATUS.json marker (screen: true), whatever
# their directory is called.
aggregate_status() {
  local agg="$SUITE_DIR/STATUS.json" lockd="$SUITE_DIR/.status.lock" n=0
  until mkdir "$lockd" 2>/dev/null; do n=$((n + 1)); [[ $n -gt 50 ]] && return 0; sleep 0.1; done
  # shellcheck disable=SC2046
  jq -s --arg suite "$SUITE" '
    map(select(.screen != true)) |
    def rank: {"failed": 4, "running": 3, "partial": 2, "complete": 1}[.] // 4;
    (map(.state) | max_by(rank)) as $state |
    {schema_version: 1, suite: $suite, state: $state,
     batches: map({batch, state, started, finished}),
     cuts: [.[] | select(.cut != null) | .cut + {batch}],
     per_arm: (reduce (.[] | .per_arm | to_entries[]) as $e ({};
        .[$e.key] |= {trials_done: ((.trials_done // 0) + $e.value.trials_done),
                      trials_failed: ((.trials_failed // 0) + $e.value.trials_failed),
                      trials_planned: ((.trials_planned // 0) + $e.value.trials_planned)})),
     source_commit: (map(.source_commit) | unique | if length == 1 then .[0] else "MIXED" end),
     model_id: (map(.model_id) | unique | if length == 1 then .[0] else "MIXED" end),
     started: (map(.started) | min), finished: (if $state == "running" then null else (map(.finished) | max) end)}' \
    $(find "$SUITE_DIR" -mindepth 2 -maxdepth 2 -name STATUS.json | sort) > "$agg.tmp" 2>/dev/null \
    && mv "$agg.tmp" "$agg"
  rmdir "$lockd" 2>/dev/null || true
}
set_state() { STATE="$1"; write_status; }

# --- one trial (runs in a background job; writes its row to $JOBS_DIR/<id>.row)
is_transport_failure() {  # is_transport_failure <sandbox-ws>
  local ws="$1" out="$1/.eval/agent-output.json" err="$1/.eval/agent-stderr.log" rc
  rc="$(jq -r '.exit_code // 0' "$ws/.eval/executor.json" 2>/dev/null || echo 0)"
  case "$rc" in 124|137|143) return 0 ;; esac
  [[ "$(jq -r '.subtype // ""' "$out" 2>/dev/null)" == "missing" ]] && return 0
  [[ -n "$(jq -r '.api_error_status // empty' "$out" 2>/dev/null)" ]] && return 0
  # audit r1 DISS-C-005: classify on the CLI's stderr only, never on the agent's own
  # output, so the agent under test cannot earn itself a retry by mentioning a network
  # error; the patterns are the CLI's transport messages, not free text.
  grep -qiE 'rate.?limit|overloaded|session limit|usage limit|out of extra usage|ECONNRESET|ETIMEDOUT|socket hang up|^(fetch|request) failed|HTTP 5[0-9][0-9]' \
    "$err" 2>/dev/null && return 0
  return 1
}

run_trial() {  # run_trial <job-id> <arm> <fixture> <trial>
  local jid="$1" arm="$2" fx="$3" trial="$4"
  local task="$EVALS_DIR/tasks/$SUITE/$TASK_PREFIX-$fx.yaml" task_id="$TASK_PREFIX-$fx"
  local run_id="arms-$SUITE-$BATCH" attempt=0 ws="" trial_id status="error" err_json='null'
  local graders='[]' composite='{"strategy":"all_must_pass","pass":false,"score":0}' executor='null'
  local start_ms end_ms per_trial ex_rc
  per_trial="$(yq -r '.timeout.per_trial // 1500' "$task")"
  start_ms="$(date +%s%N | cut -c1-13)"
  if ! verify_corpus "$fx" >"$JOBS_DIR/$jid.digest" 2>"$JOBS_DIR/$jid.drift"; then
    printf 'DRIFT\n' > "$JOBS_DIR/$jid.flag"; return 0
  fi
  while [[ $attempt -lt 2 ]]; do
    attempt=$((attempt + 1))
    trial_id="$run_id-$arm-$fx-t$trial-a$attempt-$jid"
    ws="$("$SCRIPT_DIR/sandbox.sh" create --fixture "review-prs/$fx" --run-id "$run_id" --trial-id "$trial_id" 2>/dev/null)" \
      || { err_json='{"type":"infrastructure_error","message":"sandbox creation failed"}'; break; }
    ex_rc=0
    # audit r1 DISS-C-001: the arm's toggles come from the suite declaration only; a
    # LOA_EVAL_ARM_TOGGLES inherited from the parent environment never reaches a trial
    env -u LOA_EVAL_ARM_TOGGLES \
      EVAL_PROMPT_TREE="$WORKTREE" EVAL_MODEL="$MODEL" LOA_EVAL_ARM="$arm" LOA_EVAL_SUITE_FILE="$SUITE_FILE" \
      LOA_EVAL_SOURCE_COMMIT="$SRC_FULL" LOA_AUDIT_REPLAY=1 \
      "$SCRIPT_DIR/execute-agent.sh" --task-yaml "$task" --workspace "$ws" \
        --run-id "$run_id" --trial-id "$trial_id" --timeout "$per_trial" \
        >/dev/null 2>"$JOBS_DIR/$jid.exec.log" || ex_rc=$?
    [[ -f "$ws/.eval/executor.json" ]] && executor="$(cat "$ws/.eval/executor.json")"
    if [[ $ex_rc -eq 0 ]]; then
      local gout gexit=0
      gout="$("$SCRIPT_DIR/grade.sh" --task-yaml "$task" --workspace "$ws" \
        --timeout "$(yq -r '.timeout.per_grader // 60' "$task")" 2>/dev/null)" || gexit=$?
      if jq -e . >/dev/null 2>&1 <<<"$gout"; then
        graders="$(jq -c '.graders' <<<"$gout")"; composite="$(jq -c '.composite' <<<"$gout")"
      fi
      if [[ $gexit -le 1 ]]; then status="completed"; err_json='null'
      else err_json='{"type":"infrastructure_error","message":"grader error"}'; fi
      break
    fi
    if [[ $ex_rc -eq 1 ]] && is_transport_failure "$ws"; then
      err_json="$(jq -cn --argjson a "$attempt" '{type:"transport_error",message:"executor transport failure",attempt:$a}')"
      if [[ $attempt -lt 2 ]]; then
        keep_artifacts "$ws" "$arm" "$task_id" "$trial" "-attempt1"
        "$SCRIPT_DIR/sandbox.sh" destroy --trial-id "$trial_id" >/dev/null 2>&1 || true
        ws=""; executor='null'
        sleep "$RETRY_WAIT"; continue
      fi
    else
      err_json="$(jq -cn --argjson rc "$ex_rc" '{type:(if $rc == 2 then "infrastructure_error" else "agent_error" end),message:("execute-agent exit " + ($rc|tostring))}')"
    fi
    break
  done
  end_ms="$(date +%s%N | cut -c1-13)"
  if [[ -n "$ws" && -d "$ws" ]]; then
    keep_artifacts "$ws" "$arm" "$task_id" "$trial" ""
    "$SCRIPT_DIR/sandbox.sh" destroy --trial-id "$trial_id" >/dev/null 2>&1 || true
  fi
  jq -cn --arg run_id "$run_id" --arg batch "$BATCH" --arg suite "$SUITE" --arg task_id "$task_id" \
    --arg fixture "$fx" --arg arm "$arm" --argjson trial "$trial" --argjson attempts "$attempt" \
    --arg status "$status" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg run_date "$(date -u +%Y-%m-%d)" \
    --argjson duration_ms "$(( end_ms - start_ms ))" --arg src "$SRC_FULL" --arg model_req "$MODEL" \
    --argjson executor "$executor" --argjson graders "$graders" --argjson composite "$composite" \
    --argjson error "$err_json" --arg digest "$CORPUS_DIGEST" --arg digest_now "$(cat "$JOBS_DIR/$jid.digest" 2>/dev/null)" \
    '{schema_version: 1, run_id: $run_id, batch: $batch, suite: $suite, task_id: $task_id, fixture: $fixture,
      arm: $arm, trial: $trial, attempts: $attempts, status: $status, timestamp: $ts, run_date: $run_date,
      duration_ms: $duration_ms, source_commit: $src, model_requested: $model_req,
      model_id: ($executor.model_id? // null), model_version: ($executor.model_id? // "none"), seed: null,
      corpus_sha256: $digest, corpus_sha256_at_trial: $digest_now, fixture_verified: true, graders: $graders, composite: $composite, error: $error}
     + (if $executor == null then {} else {executor: $executor} end)' > "$JOBS_DIR/$jid.row.tmp"
  mv "$JOBS_DIR/$jid.row.tmp" "$JOBS_DIR/$jid.row"
}

keep_artifacts() {  # keep_artifacts <ws> <arm> <task_id> <trial> <suffix>
  local ws="$1" dest="$BATCH_DIR/$2/artifacts/$3/trial-$4$5" f
  mkdir -p "$dest"
  for f in executor.json agent-output.json agent-stderr.log arm-removed.txt; do
    [[ -f "$ws/.eval/$f" ]] && cp "$ws/.eval/$f" "$dest/$f"
  done
  for f in review.md audit.md; do [[ -f "$ws/$f" ]] && cp "$ws/$f" "$dest/$f"; done
  # the raw transcript only on request (it embeds every tool result)
  [[ "${EVAL_KEEP_EVENTS:-0}" == "1" && -f "$ws/.eval/events.jsonl" ]] && cp "$ws/.eval/events.jsonl" "$dest/events.jsonl"
  return 0
}

# Parent-side: append a finished job's row and update the counters.
collect() {  # collect <job-id> <arm>
  local jid="$1" arm="$2" i
  i="$(arm_index "$arm")"
  if [[ -f "$JOBS_DIR/$jid.flag" ]]; then
    log "corpus drift before $jid: $(cat "$JOBS_DIR/$jid.drift" 2>/dev/null)"
    set_state failed; exit 3
  fi
  if [[ -f "$JOBS_DIR/$jid.row" ]]; then
    mkdir -p "$BATCH_DIR/$arm"
    cat "$JOBS_DIR/$jid.row" >> "$BATCH_DIR/$arm/results.jsonl"
    local cost
    cost="$(jq -r '(.executor.total_cost_usd // 0) | tonumber? // 0' "$JOBS_DIR/$jid.row" 2>/dev/null || echo 0)"
    [[ "$cost" =~ ^[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$ ]] || cost=0
    SPENT="$(fadd "$SPENT" "$cost")"
    if [[ "$(jq -r '.status' "$JOBS_DIR/$jid.row")" == "completed" ]]; then
      ARM_SUM[$i]="$(fadd "${ARM_SUM[$i]}" "$cost")"; ARM_N[$i]=$(( ${ARM_N[$i]} + 1 ))
      POOL_SUM="$(fadd "$POOL_SUM" "$cost")"; POOL_N=$((POOL_N + 1))
    fi
    if [[ "$(jq -r '.status' "$JOBS_DIR/$jid.row")" == "completed" ]]; then
      DONE[$i]=$(( ${DONE[$i]} + 1 ))
      log "done $jid ($(jq -r '"\(.arm) \(.fixture) t\(.trial) recall=\(([.graders[]? | select(.name=="recall-vs-defects.sh") | .details.recall][0]) // "n/a") \(.duration_ms/1000|floor)s"' "$JOBS_DIR/$jid.row"))"
    else
      FAILED[$i]=$(( ${FAILED[$i]} + 1 ))
      log "FAILED $jid ($(jq -c '.error' "$JOBS_DIR/$jid.row"))"
    fi
    rm -f "$JOBS_DIR/$jid".*
  else
    FAILED[$i]=$(( ${FAILED[$i]} + 1 ))
    log "FAILED $jid (no row written; see $JOBS_DIR/$jid.exec.log)"
  fi
  write_status
}

log "start suite=$SUITE batch=$BATCH source=$SRC12 model=$MODEL trials=${#PLAN[@]} concurrency=$CONCURRENCY worktree=$WORKTREE"
write_status
trap 'log "interrupted"; set_state failed; exit 3' INT TERM HUP

PIDS=() PJOB=() PARM=()
reap() {  # reap until fewer than $1 jobs run
  local i
  while [[ ${#PIDS[@]} -ge $1 ]]; do
    for i in "${!PIDS[@]}"; do
      if ! kill -0 "${PIDS[$i]}" 2>/dev/null; then
        wait "${PIDS[$i]}" 2>/dev/null || true
        collect "${PJOB[$i]}" "${PARM[$i]}"
        unset 'PIDS[i]' 'PJOB[i]' 'PARM[i]'
        PIDS=("${PIDS[@]+"${PIDS[@]}"}"); PJOB=("${PJOB[@]+"${PJOB[@]}"}"); PARM=("${PARM[@]+"${PARM[@]}"}")
        break
      fi
    done
    [[ ${#PIDS[@]} -ge $1 ]] && sleep 1
  done
  return 0
}

# est_next <arm> — the next trial's expected cost (see the header)
est_next() {
  local i; i="$(arm_index "$1")"
  if [[ "${ARM_N[$i]}" -gt 0 ]]; then awk -v s="${ARM_SUM[$i]}" -v n="${ARM_N[$i]}" 'BEGIN { printf "%.10g", s / n }'
  elif [[ "$POOL_N" -gt 0 ]]; then awk -v s="$POOL_SUM" -v n="$POOL_N" 'BEGIN { printf "%.10g", s / n }'
  else printf '%s' "$COST_HINT"; fi
}
# budget_gate <arm> <trial-number> — 0 launch; 1 cut (CUT_JSON set). Waits for a
# running trial while only the in-flight reservation blocks the launch.
budget_gate() {
  local arm="$1" at="$2" est inflight reserved
  while true; do
    est="$(est_next "$arm")"; inflight=${#PIDS[@]}
    reserved="$(awk -v k="$inflight" -v c="$RUN_CAP" 'BEGIN { printf "%.10g", k * c }')"
    if awk -v s="$SPENT" -v e="$est" -v m="$MAX_USD" 'BEGIN { exit !(s + e > m) }'; then
      CUT_JSON="$(jq -cn --arg s "$SPENT" --arg r "$reserved" --arg m "$MAX_USD" --arg e "$est" \
        --argjson launched "$LAUNCHED" --argjson at "$at" \
        '{reason: "max_usd", spent: ($s | tonumber), in_flight_reserved: ($r | tonumber), max: ($m | tonumber),
          est_next: ($e | tonumber), trials_launched: $launched, at_trial: $at}')"
      log "cut: max_usd $MAX_USD reached after $LAUNCHED trials (spent $SPENT, in-flight reserved $reserved, next est $est; trial $at not launched; reason recorded in STATUS.json)"
      return 1
    fi
    if awk -v s="$SPENT" -v r="$reserved" -v e="$est" -v m="$MAX_USD" 'BEGIN { exit !(s + r + e > m) }'; then
      reap "$inflight"; continue
    fi
    return 0
  done
}

n=0 LAUNCHED=0
for p in "${PLAN[@]}"; do
  IFS='|' read -r a f t <<<"$p"
  n=$((n + 1)); jid="$(printf 'j%04d' "$n")"
  reap "$CONCURRENCY"
  if [[ -n "$MAX_USD" ]] && ! budget_gate "$a" "$n"; then break; fi
  run_trial "$jid" "$a" "$f" "$t" &
  PIDS+=("$!"); PJOB+=("$jid"); PARM+=("$a")
  LAUNCHED=$((LAUNCHED + 1))
done
reap 1

# --screen: the per-arm table on stdout (from this batch's rows)
print_screen_table() {
  printf '%-24s %6s %9s %11s\n' arm trials mean_usd mean_recall
  local a
  for a in "${ARMS[@]}"; do
    if [[ -f "$BATCH_DIR/$a/results.jsonl" ]]; then
      jq -rs --arg a "$a" '
        def mean: if length == 0 then null else (add / length) end;
        [ .[] | (.executor.total_cost_usd // 0) ] as $c |
        [ .[] | select(.status == "completed") | ([.graders[]? | select(.name == "recall-vs-defects.sh") | .details.recall][0]) | select(. != null) ] as $r |
        [$a, (length | tostring), (($c | mean) // 0 | . * 100 | round / 100 | tostring),
         (($r | mean) as $m | if $m == null then "n/a" else ($m * 1000 | round / 1000 | tostring) end)] | @tsv' \
        "$BATCH_DIR/$a/results.jsonl" | awk -F'\t' '{ printf "%-24s %6s %9s %11s\n", $1, $2, $3, $4 }'
    else
      printf '%-24s %6s %9s %11s\n' "$a" 0 0 n/a
    fi
  done
}
finish() {  # finish <state> <exit> <message>
  set_state "$1"; log "$3"
  if [[ "$SCREEN" == "true" ]]; then
    echo "screen: suite=$SUITE fixtures=$(IFS=,; echo "${FIXTURES[*]}") (1 trial each) batch=$BATCH_DIR"
    print_screen_table
  fi
  exit "$2"
}

total_done=0 total_failed=0
for i in "${!ARMS[@]}"; do total_done=$(( total_done + ${DONE[$i]} )); total_failed=$(( total_failed + ${FAILED[$i]} )); done
if [[ "$CUT_JSON" != "null" ]]; then
  finish partial 1 "partial (cut max_usd): $total_done done, $total_failed failed, $LAUNCHED of ${#PLAN[@]} launched, spent $SPENT"
elif [[ $total_failed -eq 0 ]]; then
  finish complete 0 "complete: $total_done trials"
elif [[ $total_done -eq 0 ]]; then
  finish failed 3 "failed: no trial completed ($total_failed failed)"
else
  finish partial 1 "partial: $total_done done, $total_failed failed"
fi
