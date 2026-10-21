#!/usr/bin/env bash
# ablation-pipeline-stub.sh — stand-in for pipeline-run.sh in evals/tests/run-ablation.bats.
# Takes pipeline-run.sh's flags and writes a run directory that took-effect.sh,
# ablation-row.sh and run-ablation.sh read: meta/{arm, arm-evidence.txt, pipeline.json,
# phase-<label>.argv.json}, transcripts/{events,stderr}-<label>.jsonl|log (a system/init
# event with claude_code_version, a result event), sandbox/.claude/checksums.json (a
# mounted arm) and, for review-catch, the two dissent envelopes under eval/. No model call.
#   STUB_LOG       append "<run_id> <arm> <task> <trial> <run-dir basename>" per invocation
#   STUB_ARGV_LOG  append "<run_id> max-run-usd <amount|none>" per invocation (DEC-0567 cases)
#   STUB_ENV_LOG   append "<run_id> LOA_ABLATION_BATCH_CONTEXT=<value|<unset>> batch_context=<id|<none>>" per
#                  invocation (cycle-132 bd-st02i: the --batch-context argv flag run-ablation.sh passes; the
#                  variable is logged to show it is no longer set)
#   (cycle-132) --batch-context ID is accepted and written as batch_context=ID to meta/arm-evidence.txt; a
#                  mounted arm records mount_cheval=ok, an unmounted one mount_cheval=none (pipeline-run.sh's
#                  pre-launch probe), a bare_sessions: matched arm bare_sessions=matched
#   STUB_COST      USD per run (default 2.5), on the first phase record
#   STUB_CLI       the init event's claude_code_version (default 2.1.299)
#   STUB_RULES     file of "<run_id glob> <mode>" lines; the first match wins. Modes:
#                  ok | agent_error (no transport signature on stderr or in the result
#                  event; the transcript carries an assistant message naming a rate limit) | transport (agent_error with
#                  "overloaded" on the phase stderr, every attempt) | transport_once (only
#                  in a run dir without an -r<k> suffix) | cap_failure | bad_evidence
#                  (checksums.json lists a file with the wrong hash: integrity_clean FAILs)
#                  | drift_cli (init version 9.9.9) | drift_model (models_used names
#                  another model instead of the requested one) | extra_model (the last
#                  phase's models_used holds the requested model and, beside it,
#                  global.anthropic.claude-haiku-4-5-20251001-v1:0 with 516 output tokens:
#                  a WebFetch summariser, DEC-0545) | hang (pipeline.json `running`, then sleeps) |
#                  hang_norecord (sleeps before writing anything) | zero_cost (cost 0) |
#                  agent_error_nocost (agent_error as above, reporting cost 0)
#                  | bad_overlay (an oracle_closed arm's review-catch run gets no overlay:
#                  took-effect.sh oracle_closed FAILs) | refusal (cycle-132: the phase records carry a
#                  refusal fallback, KF-051) | crash (cycle-132: pipeline.json interrupted, exit 4, at once)
#                  | cheval_broken (cycle-132: mount_cheval=broken:ImportError … in the evidence)
#   STUB_HANG=1    every run hangs (mode hang)
# A review-catch run of an arm whose took_effect lists oracle_closed (cycle-131) gets the real
# lib/sandbox-mount.sh overlay over its corpus fixture and a one-commit sandbox repository.
set -euo pipefail
export LC_ALL=C
TASK_YAML="" ARM="" RUN_DIR="" RUN_ID="" TRIAL="" SOURCE_TREE="" SUITE_FILE="" DOCKER_BIN=docker EXECUTOR=container IMAGE="" MAX_RUN_USD=none BATCH_CONTEXT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-yaml) TASK_YAML="$2"; shift 2 ;;
    --arm) ARM="$2"; shift 2 ;;
    --run-dir) RUN_DIR="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --trial) TRIAL="$2"; shift 2 ;;
    --source-tree) SOURCE_TREE="$2"; shift 2 ;;
    --suite-file) SUITE_FILE="$2"; shift 2 ;;
    --docker-bin) DOCKER_BIN="$2"; shift 2 ;;
    --executor) EXECUTOR="$2"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    --max-run-usd) MAX_RUN_USD="$2"; shift 2 ;;
    --batch-context) BATCH_CONTEXT="$2"; shift 2 ;;
    *) echo "stub: unknown flag $1" >&2; exit 2 ;;
  esac
done
[[ -e "$RUN_DIR" && -n "$(ls -A "$RUN_DIR" 2>/dev/null)" ]] && { echo "stub: run dir not empty: $RUN_DIR" >&2; exit 2; }
TASK_ID="$(yq -r '.id' "$TASK_YAML")" TYPE="$(yq -r '.type' "$TASK_YAML")"
[[ -n "${STUB_LOG:-}" ]] && printf '%s %s %s %s %s\n' "$RUN_ID" "$ARM" "$TASK_ID" "$TRIAL" "$(basename "$RUN_DIR")" >> "$STUB_LOG"
[[ -n "${STUB_ARGV_LOG:-}" ]] && printf '%s max-run-usd %s\n' "$RUN_ID" "$MAX_RUN_USD" >> "$STUB_ARGV_LOG"
[[ -n "${STUB_ENV_LOG:-}" ]] && printf '%s LOA_ABLATION_BATCH_CONTEXT=%s batch_context=%s\n' "$RUN_ID" "${LOA_ABLATION_BATCH_CONTEXT-<unset>}" "${BATCH_CONTEXT:-<none>}" >> "$STUB_ENV_LOG"

MODE=ok
if [[ -n "${STUB_RULES:-}" && -f "${STUB_RULES:-}" ]]; then
  while read -r glob m; do
    [[ -n "$glob" ]] || continue
    # shellcheck disable=SC2254
    case "$RUN_ID" in $glob) MODE="$m"; break ;; esac
  done < "$STUB_RULES"
fi
[[ "${STUB_HANG:-0}" == 1 ]] && MODE=hang
if [[ "$MODE" == transport_once ]]; then
  if [[ "$(basename "$RUN_DIR")" =~ -r[0-9]+$ ]]; then MODE=ok; else MODE=transport; fi
fi
[[ "$MODE" == hang_norecord ]] && exec sleep 600
NOCOST=0; [[ "$MODE" == agent_error_nocost ]] && { MODE=agent_error; NOCOST=1; }

mkdir -p "$RUN_DIR"/{meta,sandbox,transcripts,eval,snapshots}
printf '%s\n' "$ARM" > "$RUN_DIR/meta/arm"
S="$(yq -o=json '.' "$SUITE_FILE")"
DEF="$(jq -c --arg a "$ARM" '[.arms[] | select(.id == $a)][0]' <<<"$S")"
KIND=build; [[ "$TYPE" == review-catch ]] && KIND=review-catch
PHASES="$(jq -c -n --argjson arm "$DEF" --argjson suite "$S" --arg kind "$KIND" '
  ($arm.toggles // {}) as $tg
  | ($arm.phases // $suite.phase_sets[$kind]) as $p0
  | (if $tg.loa_mount == false then ["BARE"] else $p0 end) as $p1
  | (if $tg.sprint_plan == false then ($p1 | map(select(. != "PLAN"))) else $p1 end) as $p2
  | (if $tg.gates == false and ($p2 | index("IMPLEMENT")) != null then $p2[0:(($p2 | index("IMPLEMENT")) + 1)] else $p2 end) as $p3
  | reduce $p3[] as $n ({out: [], fix: 0}; if $n == "FIX" then .fix += 1 | .out += [{name: "FIX", label: ("FIX" + (.fix | tostring))}]
                                        else .out += [{name: $n, label: $n}] end) | .out')"
NPH="$(jq 'length' <<<"$PHASES")"
COST="${STUB_COST:-2.5}"; [[ "$MODE" == zero_cost || $NOCOST -eq 1 ]] && COST=0
# the whole cost sits on the first phase (exact sums in the tests)
CLI="${STUB_CLI:-2.1.299}"; [[ "$MODE" == drift_cli ]] && CLI="9.9.9"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

EVIDENCE='{}'
if [[ "$(jq -r '.toggles.loa_mount' <<<"$DEF")" != false ]]; then
  mkdir -p "$RUN_DIR/sandbox/.claude/skills/x"
  printf 'mounted\n' > "$RUN_DIR/sandbox/.claude/x.txt"
  printf '%s\n' '---' 'name: x' '---' '# x' > "$RUN_DIR/sandbox/.claude/skills/x/SKILL.md"
  h="$(python3 -I -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$RUN_DIR/sandbox/.claude/x.txt")"
  [[ "$MODE" == bad_evidence ]] && h="0000000000000000000000000000000000000000000000000000000000000000"
  jq -n --arg h "$h" '{generated: "stub", algorithm: "sha256", files: {".claude/x.txt": $h}}' > "$RUN_DIR/sandbox/.claude/checksums.json"
  msha="$(python3 -I -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$RUN_DIR/sandbox/.claude/checksums.json")"
  EVIDENCE="$(jq -cn --arg m "$msha" '{mount: "whole_tree", manifest_sha256: $m}')"
  mkdir -p "$RUN_DIR/sandbox/grimoires/loa"; echo "# sprint" > "$RUN_DIR/sandbox/grimoires/loa/sprint.md"
fi
printf 'mount=stub\n' > "$RUN_DIR/meta/arm-evidence.txt"
[[ -n "$BATCH_CONTEXT" ]] && printf 'batch_context=%s\n' "$BATCH_CONTEXT" >> "$RUN_DIR/meta/arm-evidence.txt"
if [[ "$(jq -r '.toggles.loa_mount' <<<"$DEF")" == false ]]; then printf 'mount_cheval=none\n' >> "$RUN_DIR/meta/arm-evidence.txt"
elif [[ "$MODE" == cheval_broken ]]; then printf "mount_cheval=broken:ImportError: cannot import name 'x'\n" >> "$RUN_DIR/meta/arm-evidence.txt"
else printf 'mount_cheval=ok\n' >> "$RUN_DIR/meta/arm-evidence.txt"; fi
[[ "$(jq -r '.toggles.bare_sessions // ""' <<<"$DEF")" == matched ]] && printf 'bare_sessions=matched\n' >> "$RUN_DIR/meta/arm-evidence.txt"
# cycle-131 closed mount: a review-catch arm whose took_effect lists oracle_closed gets the real
# overlay (lib/sandbox-mount.sh) over the corpus fixture and a one-commit sandbox repository, as
# pipeline-run.sh materialises it, so took-effect.sh oracle_closed reads a genuine run
if [[ "$KIND" == review-catch && "$(jq -r '.toggles.loa_mount' <<<"$DEF")" != false ]] \
   && jq -e '(.took_effect // []) | index("oracle_closed") != null' >/dev/null <<<"$DEF" \
   && [[ "$MODE" != bad_overlay ]]; then
  STUB_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  fx="$STUB_REPO/evals/fixtures/$(yq -r '.review_catch.fixture' "$TASK_YAML")"
  # the throwaway source tree holds none of the corpus commits, so a fixture's fix_commit cannot be pinned from it and
  # the real overlay refuses (PR #1286 F001); the stub overlays from a copy without that line, kept outside the run dir
  # (took-effect.sh never resolves a fixture inside it); with --task-yaml the real fixture resolves to the same PR-only set
  fc="$(sed -nE 's/^fix_commit: *"?([0-9a-f]+)"?.*/\1/p' "$fx/fixture.yaml" 2>/dev/null | head -1)"
  if [[ -n "$fc" ]] && ! git -C "$SOURCE_TREE" cat-file -e "$fc^{commit}" 2>/dev/null; then
    sfx="$(mktemp -d "${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/stub-fixture.XXXXXX")"
    cp -a "$fx/." "$sfx/"; sed -i '/^fix_commit:/d' "$sfx/fixture.yaml"; fx="$sfx"
  fi
  W="$RUN_DIR/sandbox"; mkdir -p "$W/pr"
  for p in base head head.diff PR.md; do [[ -e "$fx/$p" ]] && cp -a "$fx/$p" "$W/pr/"; done
  sg() { env -i PATH="$PATH" HOME="$RUN_DIR/meta" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$W" "$@"; }
  sg init -q; printf '%s\n' '/.claude/' '/grimoires/' >> "$W/.git/info/exclude"
  sg add -A; sg -c user.name=s -c user.email=s@s -c commit.gpgsign=false commit -qm base
  printf 'base_commit=%s\n' "$(sg rev-parse HEAD)" >> "$RUN_DIR/meta/arm-evidence.txt"
  ARM_EVIDENCE_FILE="$RUN_DIR/meta/arm-evidence.txt" bash -c 'source "$1"; overlay_answer_paths "$2" "$3" head "$4" "$5"' _ \
    "$STUB_REPO/evals/harness/lib/sandbox-mount.sh" "$W" "$fx" "$SOURCE_TREE" "$(git -C "$SOURCE_TREE" rev-parse HEAD)" 2>/dev/null \
    || { echo "stub: overlay failed" >&2; exit 2; }
fi
DIGEST=""
[[ "$EXECUTOR" == container ]] && DIGEST="$("$DOCKER_BIN" image inspect --format x "$IMAGE" 2>/dev/null || true)"

records='[]' i=0
while IFS=$'\t' read -r name label; do
  i=$((i + 1))
  model="$(jq -r --arg n "$name" '.phase_defaults.models[$n]' <<<"$S")"
  # cycle-131 D-5.1: bare_model: fable maps BARE to Fable 5.1, at the arm's effort (as pipeline-run.sh does)
  EFF=null
  if [[ "$name" == BARE && "$(jq -r '.toggles.bare_model // ""' <<<"$DEF")" == fable ]]; then
    model=global.anthropic.claude-fable-5-1; EFF="$(jq -c '.effort // null' <<<"$DEF")"
  fi
  PCOST=0; [[ $i -eq 1 ]] && PCOST="$COST"
  used="$model"; [[ "$MODE" == drift_model ]] && used="global.anthropic.claude-haiku-9-9"
  mu="$(jq -cn --arg u "$used" '{($u): 100}')"
  [[ "$MODE" == extra_model && $i -eq $NPH ]] && mu="$(jq -cn --arg u "$used" '{($u): 100, "global.anthropic.claude-haiku-4-5-20251001-v1:0": 516}')"
  sid="sess-$label-$RANDOM"
  ex=0; [[ $i -eq $NPH ]] && case "$MODE" in agent_error|transport) ex=1 ;; esac
  printf '%s\n' "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"$sid\",\"model\":\"$model\",\"claude_code_version\":\"$CLI\"}" \
    "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"total_cost_usd\":$PCOST,\"num_turns\":2}" \
    > "$RUN_DIR/transcripts/events-$label.jsonl"
  : > "$RUN_DIR/transcripts/stderr-$label.log"
  [[ $ex -ne 0 && "$MODE" == transport ]] && echo "API Error: 529 overloaded" > "$RUN_DIR/transcripts/stderr-$label.log"
  [[ $ex -ne 0 && "$MODE" == agent_error ]] && echo "the agent gave up" > "$RUN_DIR/transcripts/stderr-$label.log"
  # the agent's own words never earn a retry (DISS-C-005): an assistant message naming a rate limit
  [[ $ex -ne 0 && "$MODE" == agent_error ]] \
    && echo '{"type":"assistant","message":{"content":[{"type":"text","text":"HTTP 503 rate limit, overloaded, ECONNRESET"}]}}' >> "$RUN_DIR/transcripts/events-$label.jsonl"
  env='{}'; [[ "$(jq -r '.toggles.gates' <<<"$DEF")" == false ]] && env='{"LOA_ADVERSARIAL_REVIEW_ENFORCE":"false"}'
  jq -n --arg n "$name" --arg l "$label" --arg m "$model" --argjson env "$env" \
    '{name: $n, label: $l, argv: ["claude", "-p", "x", "--model", $m], env: $env, resume: null}' > "$RUN_DIR/meta/phase-$label.argv.json"
  RFB='[]'; [[ "$MODE" == refusal ]] && RFB='[{"from":"global.anthropic.claude-opus-5-5","to":"global.anthropic.claude-opus-5-5","category":"cyber","scope":"session"}]'
  records="$(jq -c --arg n "$name" --arg l "$label" --arg sid "$sid" --arg m "$model" --argjson mu "$mu" --argjson c "$PCOST" --argjson ex "$ex" --argjson eff "$EFF" --argjson rfb "$RFB" \
    '. + [{name: $n, label: $l, skipped: false, session_id: $sid, model_requested: $m, models_used: $mu,
           effort_requested: $eff, tokens_in: 10, tokens_out: 100, cache_read_tokens: 0, cache_creation_tokens: 0,
           cost_usd: $c, ledger_cost_usd: 0, duration_ms: 1000, num_turns: 2, exit: $ex, timed_out: false,
           refusal_fallbacks: $rfb, modelinv_lines: {from: 1, to: 0}}]' <<<"$records")"
done < <(jq -r '.[] | [.name, .label] | @tsv' <<<"$PHASES")

if [[ "$KIND" == review-catch && "$(jq -r '.toggles.loa_mount' <<<"$DEF")" != false ]]; then
  cv=true; [[ "$(jq -r '.toggles.companion_voice' <<<"$DEF")" == false ]] && cv=false
  for g in review audit; do
    jq -n --argjson cv "$cv" '{metadata: {companion_voice: {planned: $cv}}, verdict_quality: {status: "OK", voices_planned: 1, voices_succeeded: 1}}' \
      > "$RUN_DIR/eval/adversarial-$g.json"
  done
fi

status=completed rc=0
case "$MODE" in agent_error|transport) status=agent_error rc=1 ;; cap_failure) status=cap_failure rc=3 ;; hang) status=running ;; crash) status=interrupted rc=4 ;; esac
write_pipe() {
  jq -n --arg r "$RUN_ID" --arg a "$ARM" --arg t "$TASK_ID" --arg ty "$TYPE" --argjson n "$TRIAL" \
    --arg src "$(git -C "$SOURCE_TREE" rev-parse HEAD)" --arg st "$1" --argjson ph "$2" --argjson ev "$EVIDENCE" \
    --argjson tg "$(jq -c '.toggles // {}' <<<"$DEF")" --arg c "$COST" --arg dg "$DIGEST" --arg mode "$EXECUTOR" --arg now "$NOW" \
    '{schema_version: 1, run_id: $r, arm: $a, task_id: $t, task_type: $ty, trial: $n, source_commit: $src, suite_version: 1,
      status: $st, cap_phase: (if $st == "cap_failure" then ($ph | last | .label) else null end), spent_usd: ($c | tonumber),
      arm_toggles: $tg, arm_evidence: $ev, executor_mode: $mode, image_digest: (if $dg == "" then null else $dg end),
      fingerprint: "fp:stub", phases: $ph, snapshots: {}, started: $now, finished: $now}' > "$RUN_DIR/meta/pipeline.json"
}
if [[ "$MODE" == hang ]]; then
  write_pipe running '[]'
  exec sleep 600
fi
write_pipe "$status" "$records"
exit "$rc"
