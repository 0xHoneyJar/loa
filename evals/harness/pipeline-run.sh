#!/usr/bin/env bash
# =============================================================================
# pipeline-run.sh — the cycle-130 ablation pipeline executor (SDD §1.4 D-4.1 … D-4.10, §5.6)
#
# Runs ONE task under ONE arm: materialises a sandbox repository (the task's
# fixture tree, or the review-catch PR under pr/, plus the Loa mount from the
# pinned --source-tree), then drives Loa's phases as separate `claude -p`
# sessions inside it, records every phase, enforces the per-run cap and writes
# meta/pipeline.json. One executor serves every task type (D-4.1):
#   review-catch                      REVIEW → AUDIT
#   bug-fix | refactor | feature-build PLAN → IMPLEMENT → REVIEW → FIX? → AUDIT → FIX?
# A FIX runs only when the gate before it wrote a CHANGES_REQUIRED LOA-VERDICT
# trailer (the last `<!-- LOA-VERDICT {…} -->` line of
# grimoires/loa/a2a/sprint-1/engineer-feedback.md resp. auditor-sprint-feedback.md);
# a FIX that does not run is recorded `skipped: true`.
# Arms edit the phase set (D-4.2): `sprint_plan: false` drops PLAN; `gates: false`
# ends after IMPLEMENT; `loa_mount: false` runs one BARE session (no mount);
# `flatline: false` keeps PLAN with the Flatline step off; `context_resets: false`
# runs PLAN, IMPLEMENT and FIX as ONE implementer session (`--resume <session_id>`
# from the first session's system/init event) while REVIEW and AUDIT stay separate.
# The suite's `phase_sets[<review-catch|build>]` and an arm's `phases` override the
# default phase list; the toggle edits above apply on top.
#
# Usage:
#   pipeline-run.sh --task-yaml F --arm ID --run-dir D --run-id R --trial N \
#                   --source-tree DIR --suite-file F [--max-run-usd 12] \
#                   [--executor container|host] [--image IMG] [--claude-bin B] \
#                   [--docker-bin D] [--phase-models JSON] [--phase-timeouts JSON]
#                   [--batch-context ID] [--dry-run]
#
# Options:
#   --task-yaml F       task.yaml (SDD §3.2); its directory holds TASK.md
#   --arm ID            arm id declared in the suite file (`arms[].id`)
#   --run-dir D         run directory to create (must not exist or be empty);
#                       alias --workspace
#   --run-id R          run id recorded in pipeline.json
#   --trial N           trial number
#   --source-tree DIR   the pinned Loa tree the mount is copied from
#   --suite-file F      evals/suites/ablation-2.0.yaml (read with yq -o=json)
#   --max-run-usd USD   per-run cap (default 12; config evals.ablation.run_cap_usd)
#   --executor MODE     container (default; DEC-0411) or host
#   --image IMG         container image (default loa-ablation:258)
#   --claude-bin B      host-mode CLI (default $EVAL_CLAUDE_BIN, else claude)
#   --docker-bin D      docker CLI (default $EVAL_DOCKER_BIN, else docker)
#   --phase-models JSON {"PLAN": "<model id>", …} override ($LOA_EVAL_PHASE_MODELS)
#   --phase-timeouts JSON {"IMPLEMENT": <seconds>, …} override
#   --batch-context ID  (cycle-132 bd-st02i) the evaluation batch this run belongs to
#                       (^[A-Za-z0-9._-]{1,200}$; run-ablation.sh passes its batch name); written
#                       to meta/arm-evidence.txt as batch_context=<id>; the eval_only gate below
#                       reads it (an argv flag, never inherited by a child process)
#   --dry-run           print the phase plan and exit 0; nothing is created. Lines:
#                       `plan: task … arm … phases <labels>`, one `phase <n> <label> model=…
#                       max_turns=… timeout_s=… effort=… session=…` per phase, `sandbox:
#                       mount=loa|none overlay=head|base|none(<why>) config_variant=eval|none
#                       config_edits=<key=value,…>|-` (the arm's sandbox .loa.config.yaml edits,
#                       derived from lib/sandbox-mount.sh print_toggle_vocabulary — its order, a
#                       repeated path once; bd-gdl5s), and `eval_only: true (batch context <id>)`
#                       for an eval_only arm
#
# Run directory layout (DEC-0413 — the grader never reads meta/):
#   sandbox/     the agent's tree (its own .git initialised at `base`)
#   snapshots/   <label>.bundle + index.json ({IMPLEMENT|FIX1|FIX2: commit}) after
#                IMPLEMENT and each FIX
#   transcripts/ events-<label>.jsonl (stream-json), stderr-<label>.log
#   eval/        model-invoke.jsonl, cost-ledger.jsonl (copied out of
#                sandbox/.eval/ after every phase), adversarial-{review,audit}.json:
#                the gate envelopes, copied once when the gate ends (REVIEW → review,
#                AUDIT → audit; never overwritten, a symlinked envelope is not copied;
#                the phase record carries envelope_copied and envelope_sha256, the
#                eval/ copy's sha256 or null). Later phases cannot rewrite them (audit MEDIUM-A1).
#   meta/        pipeline.json, phase-<label>.argv.json (argv + captured env),
#                prompt-<label>.md, arm, arm-evidence.txt, arm-env, refused.json,
#                home/ (container mode: the per-run HOME; deleted at exit)
#
# Session (D-4.3, DEC-0394 as amended, DEC-0412): `claude -p <prompt> --output-format
# stream-json --verbose --model <id> --permission-mode bypassPermissions
# --dangerously-skip-permissions --setting-sources project --tools <list>
# --max-turns <cap> [--effort <v>] [--resume <id>]`, cwd sandbox/, with exactly this
# environment: PATH HOME LANG LC_ALL TERM TMPDIR CLAUDE_CODE_USE_BEDROCK
# CLAUDE_CODE_SUBAGENT_MODEL LOA_MODELINV_LOG_PATH LOA_COST_LEDGER_PATH
# GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GH_CONFIG_DIR=<sandbox/.eval/gh-empty>,
# the Bedrock route's pass-through keys when set in the driver's environment
# (AWS_REGION AWS_DEFAULT_REGION AWS_PROFILE AWS_BEARER_TOKEN_BEDROCK
# ANTHROPIC_BEDROCK_REGION_PREFIX ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL), and the
# arm's LOA_* variables (LOA_ADVERSARIAL_REVIEW_ENFORCE=false for gates: false).
# A python3 -I exec shim closes every descriptor above 2 and keeps exactly those keys;
# values reach it through the environment, never argv, so AWS_BEARER_TOKEN_BEDROCK
# appears in no argv, capture or log (phase-<label>.argv.json records it as "<set>").
# `timeout --signal=TERM --kill-after=15` bounds the CLI.
# Container mode (D-4.9, DEC-0411 as amended) runs the same command inside
#   docker run --rm --name <n> --user <uid>:<gid> --network bridge --read-only
#     --tmpfs /tmp:rw,size=1g --pids-limit 512 --memory 4g --cpus 2
#     -v <run>/sandbox:/workspace:rw -v <run>/meta/home:/home/evaluser:rw
#     -w /workspace -e <KEY=value…> -e AWS_BEARER_TOKEN_BEDROCK <image> python3 -I -c <shim> … claude …
# Exactly two mounts. meta/home/ (mode 0700) holds a copy of $HOME/.codex/config.toml and
# a copy of $HOME/.codex/auth.json whose tokens.refresh_token is the placeholder
# "loa-ablation-no-refresh-token" (mode 0600; the real one is single-use and a container
# refresh burned the host's; the codex CLI treats a MISSING key as logged out, KF-048)
# when present, and empty .claude/ and .aws/; the CLI's session store
# lives there for the whole run, so A6's --resume works across phases. No ~/.claude
# file is ever copied. The directory is deleted at exit and on interrupt.
# image_digest = the image's RepoDigest or id (container), else the fingerprint (host).
# Versions: `fingerprint` is computed from the HOST toolchain; in container mode the
# toolchain that runs the phases is the image's (Claude Code 2.1.299, codex 0.162.1 by
# Dockerfile.ablation), so image_digest identifies the batch's versions. On 2026-10-15
# the host CLI was 2.1.300 while the image pins 2.1.299; every arm runs in the container.
#
# Cap and watchdog (D-4.6, D-4.10): while a phase runs the driver re-prices the
# stream's assistant-turn usage every $LOA_EVAL_WATCHDOG_POLL_S seconds (default 1)
# from per-token prices fetched once per model (pricing.py; $LOA_EVAL_PRICING_JSON
# overrides) and SIGTERMs the phase when spent + estimate ≥ the cap (cap_turn
# recorded). After each phase the result's total_cost_usd (authoritative) plus the
# sandbox cost-ledger rows written during the phase are added; ≥ cap → cap_failure.
# Metering fails closed (cycle-133 C-6, lib/session-exec.sh): before the first phase every
# planned phase model must have a valid price (an unknown id, a malformed
# $LOA_EVAL_PRICING_JSON or a null/negative/non-finite price → infrastructure_error, reason
# `metering_incomplete: …`, no phase runs); a phase stream that cannot be priced (an
# invalid token count, a completed turn without usage) stops the phase — SIGTERM while it
# runs — and the run (infrastructure_error, reason `metering_incomplete: <label> …`, the
# phase record carries metering: incomplete). Each phase record carries metering
# metered | incomplete | unmetered_attempt (the phase started, no usage event and no
# result cost: spend unknown, not zero).
#
# Exit codes:
#   0  finished (any verdict)                                   status completed
#   1  agent error: a phase exited non-zero or timed out        status agent_error
#   2  infrastructure: usage, refused arm/type, mount/toggle failure, CLI/docker
#      or image missing, fixture path rule, leak guard          status infrastructure_error
#   3  cap failure (run stopped at the cap)                     status cap_failure;
#      also (cycle-132 bd-56nn6) a refused launch on a broken mount: a mounted arm whose gates
#      run a dissent and whose mount_cheval probe reads broken — meta/refused.json {arm, task_id,
#      type, reason: "mount_cheval_broken", detail}, status infrastructure_error, no phase runs
#   4  interrupted (SIGTERM/SIGINT/SIGHUP to the driver, or a phase killed from
#      outside)                                                 status interrupted
# pipeline.json is written for every exit except usage errors and --dry-run; it is
# rewritten with status `running` after each phase so a SIGKILLed driver leaves a
# record (ablation-row.sh reads `running` as interrupted).
# Closed mount (cycle-131 FR-1, SDD §5.2, DEC-0613/DEC-0622): for a review-catch task with
# the Loa mount, every answer-bearing path of the PR fixture under .claude/ is overlaid with
# the PR's own version (lib overlay_answer_paths; mode from task.yaml
# review_catch.overlay_mode, head by default, base the per-task fallback) right after
# mount_prompt_surface; copy_source (the source tree's HEAD) must equal source_commit, else
# the trial is refused (infrastructure_error). Order: mount_prompt_surface → overlay_answer_paths
# → apply_arm_toggles → apply_eval_config_variant → write_sandbox_grimoire → init_sandbox_beads
# → regen_sandbox_manifest → check_mount_closed (clauses (a)-(d) of took-effect.sh
# oracle_closed on the surface about to launch; a failure is infrastructure_error naming
# the clause and path, and no phase runs). An arm whose toggles set oracle_open: true (the
# eval-only open-mount arm) skips the overlay and the check and records mount_overlay=none.
# Every mounted arm runs the cycle-131 eval config variant (both gates' budget_scale: diff,
# budget_cents_max 1200 since cycle-132 addendum 2; evidence config_variant=eval). Toggle bare_model: fable runs the BARE
# phase on global.anthropic.claude-fable-5-1 (it wins over --phase-models and the suite's
# phase_defaults for BARE). All evidence reaches meta/arm-evidence.txt before the first phase.
# Mount integrity (audit LOW-A2): after materialisation the sha256 of sandbox/CLAUDE.md
# and sandbox/.loa.config.yaml go to arm_evidence (claude_md_sha256, loa_config_sha256 =
# <hex>|absent); at finish both are recomputed into pipeline.json.mount_integrity =
# {claude_md, loa_config} each ok|changed|absent (loa_mount: false → both absent; null
# when the run stopped before materialisation). `.claude/` itself is covered by
# took-effect.sh integrity_clean.
#
# eval_only arms (cycle-131 FR-5): an arm declaring `eval_only: true` (a1_full_openmount), or whose
# toggles set `oracle_open: true`, is
# refused — exit 2, `refused: arm '<id>': eval_only arm outside an evaluation batch`, before the
# run directory exists, so no pipeline.json and no infrastructure_error is ever written — unless
# --batch-context <id> is given (cycle-132 bd-st02i: the argv flag replaced the inheritable
# LOA_ABLATION_BATCH_CONTEXT variable, which is read no more). run-ablation.sh passes it to every
# trial it launches (batch and smoke); --dry-run honours the same flag, so the operator dry-runs
# the open-mount arm with `pipeline-run.sh … --batch-context <id> --dry-run`.
#
# Arm-id leak guard (AC-4.2; cycle-132 round 5, PREREGISTRATION §12 addendum 1): before the first phase the running
# arm's id may appear nowhere in the sandbox, with one exception — an id the PR content itself names
# (arm_ids_pr_native=<sorted comma list>|none in arm-evidence: the suite's arm ids found under pr/) may appear in a
# PR-derived file: anything under pr/, grimoires/loa/a2a/<sprint>/reviewer.md (written from pr/PR.md), and each
# closed-mount overlay path (an overlay_sha256= line: the PR's own version of a .claude/ file). Anywhere else, or for
# an id the PR does not name, the launch is refused as before (exit 2, infrastructure_error). The task brief and every
# phase prompt stay fully strict: any arm id there is a leak (leak_scan). A PR that built the arms names them all, so
# its text says nothing about which arm runs.
#
# mount_cheval (cycle-132 bd-56nn6, KF-050): after materialisation and before the first phase of a
# mounted arm, `python3 -I -B -c 'import loa_cheval, loa_cheval.providers'` runs on the host with
# sandbox/.claude/adapters first on sys.path (no bytecode is written into the sandbox; the tree is
# the pinned source plus the PR's own .claude/ files and no agent has run yet) under timeout 60;
# evidence mount_cheval=ok | broken:<last stderr line, ≤ 200 characters> (broken:no
# .claude/adapters/loa_cheval when the package is absent); a loa_mount: false arm records
# mount_cheval=none. A broken probe on an arm whose gates run a dissent (an AUDIT phase, or a
# REVIEW phase without dissent: false; never with gates: false) refuses the launch (exit 3 above);
# on any other arm it is evidence only.
#
# Env: EVAL_CLAUDE_BIN, EVAL_DOCKER_BIN, LOA_EVAL_PHASE_MODELS, LOA_EVAL_PRICING_JSON,
# LOA_EVAL_WATCHDOG_POLL_S, LOA_EVAL_CREDS_HOME (where ~/.codex is read; default $HOME),
# LOA_EVAL_CONTAINER_CLAUDE_BIN (default claude), LOA_EVAL_EXECUTOR.
#
# Mount library: lib/sandbox-mount.sh beside this script, sourced by a literal path.
# Exported to it: ARM_EVIDENCE_FILE, ARM_ENV_FILE (meta/arm-env), LOA_EVAL_SUITE_FILE.
# Session library: lib/session-exec.sh beside this script, sourced by a literal path (the one
# copy of the exec shim, the pass-through/secret keys and the pricing; blind-session.sh
# shares it); its startup assertion assert_secret_keys failing is infrastructure_error.
#
# Tested by evals/tests/pipeline-run.bats (stub claude, stub docker, and a temporary
# copy of this harness whose lib/sandbox-mount.sh is the stub mount library and whose
# lib/session-exec.sh is the shipped one).
# =============================================================================
set -euo pipefail
export LC_ALL=C
shopt -u patsub_replacement 2>/dev/null || true   # bash 5.2: '&' in ${x//p/r} stays literal

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROMPTS_DIR="$SCRIPT_DIR/lib/phase-prompts"
# No .claude/ code is sourced (eval.yml "Validate grader trust boundary": the
# harness is the trusted copy and runs against a PR's .claude/).

TASK_YAML="" ARM="" RUN_DIR="" RUN_ID="" TRIAL="" SOURCE_TREE="" SUITE_FILE=""
MAX_RUN_USD="" EXECUTOR="${LOA_EVAL_EXECUTOR:-container}" IMAGE="loa-ablation:258"
CLAUDE_BIN="${EVAL_CLAUDE_BIN:-claude}" DOCKER_BIN="${EVAL_DOCKER_BIN:-docker}"
PHASE_MODELS_JSON="${LOA_EVAL_PHASE_MODELS:-}" PHASE_TIMEOUTS_JSON="" DRY_RUN=false BATCH_CONTEXT=""
SPRINT="sprint-1"
TOOLS_DEFAULT="Bash,Read,Grep,Glob,Write,Edit,Task,WebFetch"

die_usage() { echo "pipeline-run.sh: $*" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-yaml)      TASK_YAML="${2:-}"; shift 2 ;;
    --arm)            ARM="${2:-}"; shift 2 ;;
    --run-dir|--workspace) RUN_DIR="${2:-}"; shift 2 ;;
    --run-id)         RUN_ID="${2:-}"; shift 2 ;;
    --trial)          TRIAL="${2:-}"; shift 2 ;;
    --source-tree)    SOURCE_TREE="${2:-}"; shift 2 ;;
    --suite-file)     SUITE_FILE="${2:-}"; shift 2 ;;
    --max-run-usd)    MAX_RUN_USD="${2:-}"; shift 2 ;;
    --executor)       EXECUTOR="${2:-}"; shift 2 ;;
    --image)          IMAGE="${2:-}"; shift 2 ;;
    --claude-bin)     CLAUDE_BIN="${2:-}"; shift 2 ;;
    --docker-bin)     DOCKER_BIN="${2:-}"; shift 2 ;;
    --phase-models)   PHASE_MODELS_JSON="${2:-}"; shift 2 ;;
    --phase-timeouts) PHASE_TIMEOUTS_JSON="${2:-}"; shift 2 ;;
    --batch-context)  BATCH_CONTEXT="${2:-}"; [[ -n "$BATCH_CONTEXT" ]] || die_usage "--batch-context needs an id"; shift 2 ;;
    --dry-run)        DRY_RUN=true; shift ;;
    -h|--help)        sed -n "2,$(awk 'NR > 2 && /^# =====/ {print NR - 1; exit}' "$0")p" "$0"; exit 0 ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

for v in TASK_YAML ARM RUN_ID TRIAL SOURCE_TREE SUITE_FILE; do
  [[ -n "${!v}" ]] || die_usage "missing --$(echo "$v" | tr 'A-Z_' 'a-z-')"
done
[[ "$DRY_RUN" == true || -n "$RUN_DIR" ]] || die_usage "missing --run-dir"
[[ -f "$TASK_YAML" ]] || die_usage "task yaml not found: $TASK_YAML"
[[ -f "$SUITE_FILE" ]] || die_usage "suite file not found: $SUITE_FILE"
[[ -d "$SOURCE_TREE" ]] || die_usage "source tree not found: $SOURCE_TREE"
[[ "$TRIAL" =~ ^[0-9]+$ ]] || die_usage "--trial must be an integer"
[[ -z "$BATCH_CONTEXT" || "$BATCH_CONTEXT" =~ ^[A-Za-z0-9._-]{1,200}$ ]] || die_usage "--batch-context must match ^[A-Za-z0-9._-]{1,200}\$"
case "$EXECUTOR" in container|host) ;; *) die_usage "--executor must be container or host" ;; esac
for t in jq yq git timeout; do command -v "$t" >/dev/null 2>&1 || die_usage "required tool missing: $t"; done
[[ -z "$PHASE_MODELS_JSON" ]] || jq -e 'type == "object"' >/dev/null 2>&1 <<<"$PHASE_MODELS_JSON" || die_usage "--phase-models must be a JSON object"
[[ -z "$PHASE_TIMEOUTS_JSON" ]] || jq -e 'type == "object"' >/dev/null 2>&1 <<<"$PHASE_TIMEOUTS_JSON" || die_usage "--phase-timeouts must be a JSON object"
[[ -n "$PHASE_MODELS_JSON" ]] || PHASE_MODELS_JSON='{}'
[[ -n "$PHASE_TIMEOUTS_JSON" ]] || PHASE_TIMEOUTS_JSON='{}'

TASK_YAML="$(cd "$(dirname "$TASK_YAML")" && pwd)/$(basename "$TASK_YAML")"
TASK_DIR="$(dirname "$TASK_YAML")"
SUITE_ROOT="$(cd "$TASK_DIR/../.." && pwd)"
SOURCE_TREE="$(cd "$SOURCE_TREE" && pwd)"

TASK_JSON="$(yq -o=json '.' "$TASK_YAML")" || die_usage "task yaml does not parse: $TASK_YAML"
SUITE_JSON="$(yq -o=json '.' "$SUITE_FILE")" || die_usage "suite file does not parse: $SUITE_FILE"

if [[ -z "$MAX_RUN_USD" ]]; then
  MAX_RUN_USD="$(jq -r '.caps.run_usd // 12' <<<"$SUITE_JSON")"
  cfg_cap="$(yq -r '.evals.ablation.run_cap_usd // ""' "$REPO_ROOT/.loa.config.yaml" 2>/dev/null || true)"
  [[ -n "$cfg_cap" && "$cfg_cap" != "null" ]] && MAX_RUN_USD="$cfg_cap"
fi
[[ "$MAX_RUN_USD" =~ ^[0-9]+([.][0-9]+)?$ ]] || die_usage "--max-run-usd must be a number"
CAP_MICRO="$(jq -n --arg c "$MAX_RUN_USD" '($c|tonumber) * 1000000 | round')"

TASK_ID="$(jq -r '.id // ""' <<<"$TASK_JSON")"
TASK_TYPE="$(jq -r '.type // ""' <<<"$TASK_JSON")"
[[ -n "$TASK_ID" ]] || die_usage "task has no id"
case "$TASK_TYPE" in
  review-catch) KIND="review-catch" ;;
  bug-fix|refactor|feature-build) KIND="build" ;;
  *) die_usage "task type '$TASK_TYPE' is not one of feature-build|bug-fix|refactor|review-catch" ;;
esac

OVERLAY_MODE="$(jq -r '.review_catch.overlay_mode // "head"' <<<"$TASK_JSON")"
case "$OVERLAY_MODE" in head|base) ;; *) die_usage "task review_catch.overlay_mode must be head or base, got '$OVERLAY_MODE'" ;; esac

# --- arm and phase plan -------------------------------------------------------
ARM_DEF="$(jq -c --arg a "$ARM" '[.arms // [] | .[] | select(.id == $a)][0] // empty' <<<"$SUITE_JSON")"
ALL_ARM_IDS="$(jq -r '[.arms // [] | .[] | .id] | .[]' <<<"$SUITE_JSON")"
REFUSAL=""
if [[ -z "$ARM_DEF" ]]; then
  REFUSAL="arm '$ARM' is not declared in the suite"
elif [[ "$(jq -r '.absent // false' <<<"$ARM_DEF")" == "true" ]]; then
  REFUSAL="arm '$ARM' is declared absent: true"
elif ! jq -e --arg k "$KIND" --arg t "$TASK_TYPE" \
       '(.task_types // ["all"]) as $tt | ($tt | index("all")) or ($tt | index($k)) or ($tt | index($t))' \
       >/dev/null <<<"$ARM_DEF"; then
  REFUSAL="arm '$ARM' does not apply to task type '$TASK_TYPE' (task_types $(jq -c '.task_types' <<<"$ARM_DEF"))"
fi
[[ -n "$ARM_DEF" ]] || ARM_DEF='{}'
SUITE_TOGGLES="$(jq -c '.toggles // {}' <<<"$ARM_DEF")"
# eval_only (cycle-131 FR-5): refused before anything is created, dry run included, unless the
# runner marks the batch context; no pipeline.json, so no infrastructure_error row is possible
# eval_only is derived from the property it protects as well as from the flag (review r1 DISS-C-002): an arm whose
# toggles open the mount (oracle_open: true) is evaluation-only whatever the suite says; a present eval_only that is
# not a JSON boolean is refused rather than read as false
case "$(jq -r 'if has("eval_only") then (.eval_only | type) else "absent" end' <<<"$ARM_DEF")" in
  absent|boolean) ;;
  *) echo "pipeline-run.sh: refused: arm '$ARM': eval_only must be a JSON boolean (true|false)" >&2; exit 2 ;;
esac
# the toggle that opens the mount is held to the same type rule, so the strict `== true` below and the mount
# path's loose text read can never disagree on a quoted "true" (audit r1 DISS-C-001)
case "$(jq -r 'if (.toggles // {}) | has("oracle_open") then (.toggles.oracle_open | type) else "absent" end' <<<"$ARM_DEF")" in
  absent|boolean) ;;
  *) echo "pipeline-run.sh: refused: arm '$ARM': toggles.oracle_open must be a JSON boolean (true|false)" >&2; exit 2 ;;
esac
EVAL_ONLY=false
[[ "$(jq -r '(.eval_only == true) or (.toggles.oracle_open == true)' <<<"$ARM_DEF")" == true ]] && EVAL_ONLY=true
if [[ "$EVAL_ONLY" == true && -z "$BATCH_CONTEXT" ]]; then
  echo "pipeline-run.sh: refused: arm '$ARM': eval_only arm outside an evaluation batch (run-ablation.sh passes --batch-context <batch> to its trials)" >&2
  exit 2
fi

# plan_phases <toggles-json> → JSON array of {name,label}
plan_phases() {
  jq -c -n --argjson arm "$ARM_DEF" --argjson suite "$SUITE_JSON" --argjson tg "$1" --arg kind "$KIND" '
    ( if $kind == "review-catch" then ["REVIEW","AUDIT"] else ["PLAN","IMPLEMENT","REVIEW","FIX","AUDIT","FIX"] end ) as $dflt
    | ( $arm.phases // $suite.phase_sets[$kind] // $dflt ) as $p0
    | ( if ($tg.loa_mount == false) then ["BARE"] else $p0 end ) as $p1
    | ( if ($tg.sprint_plan == false) then ($p1 | map(select(. != "PLAN"))) else $p1 end ) as $p2
    | ( if ($tg.gates == false) and ($p2 | index("IMPLEMENT")) != null
          then $p2[0:(($p2 | index("IMPLEMENT")) + 1)] else $p2 end ) as $p3
    | reduce $p3[] as $n ({out: [], fix: 0};
        if $n == "FIX" then .fix += 1 | .out += [{name: "FIX", label: ("FIX" + (.fix | tostring))}]
        else .out += [{name: $n, label: $n}] end)
    | .out'
}

phase_skill() {  # the Loa skill a phase invokes (for effort_requested)
  case "$1" in
    PLAN) echo planning-sprints ;; IMPLEMENT|FIX) echo implementing-tasks ;;
    REVIEW) echo reviewing-code ;; AUDIT) echo auditing-security ;; *) echo "" ;;
  esac
}
builtin_model() { case "$1" in REVIEW|AUDIT) echo global.anthropic.claude-fable-5-1 ;; *) echo global.anthropic.claude-opus-5-5 ;; esac; }
builtin_turns() { case "$1" in PLAN) echo 30 ;; IMPLEMENT) echo 60 ;; REVIEW|FIX|AUDIT) echo 40 ;; BARE) echo 170 ;; *) echo 40 ;; esac; }
builtin_tmin()  { case "$1" in PLAN) echo 15 ;; IMPLEMENT) echo 25 ;; REVIEW|AUDIT) echo 20 ;; FIX) echo 15 ;; BARE) echo 70 ;; *) echo 20 ;; esac; }

BARE_FABLE_MODEL="global.anthropic.claude-fable-5-1"
BARE_MODEL_TOGGLE="$(jq -r '.bare_model // empty' <<<"$SUITE_TOGGLES")"   # re-read from the library's toggles below
phase_model() {  # bare_model: fable (cycle-131 D-5.1) decides BARE over every other source
  if [[ "$1" == BARE && "$BARE_MODEL_TOGGLE" == fable ]]; then printf '%s\n' "$BARE_FABLE_MODEL"; return 0; fi
  jq -r --arg n "$1" --arg d "$(builtin_model "$1")" --argjson o "$PHASE_MODELS_JSON" \
    '$o[$n] // .phase_defaults.models[$n] // $d' <<<"$SUITE_JSON"
}
phase_cap() {  # phase_cap <name> max_turns|timeout_min — task bounds > suite phase_defaults > built-in;
               # BARE without a declaration = PLAN + IMPLEMENT + 2 × FIX
  local n="$1" key="$2" v
  v="$(jq -r --arg n "$n" --arg k "$key" '.bounds[$k][$n] // empty' <<<"$TASK_JSON")"
  [[ -n "$v" ]] || v="$(jq -r --arg n "$n" --arg k "$key" '.phase_defaults[$k][$n] // empty' <<<"$SUITE_JSON")"
  if [[ -z "$v" && "$n" == "BARE" ]]; then
    v=$(( $(phase_cap PLAN "$key") + $(phase_cap IMPLEMENT "$key") + 2 * $(phase_cap FIX "$key") ))
  fi
  if [[ -z "$v" ]]; then
    if [[ "$key" == max_turns ]]; then v="$(builtin_turns "$n")"; else v="$(builtin_tmin "$n")"; fi
  fi
  printf '%s' "$v"
}
phase_timeout_s() {
  local o; o="$(jq -r --arg n "$1" '.[$n] // empty' <<<"$PHASE_TIMEOUTS_JSON")"
  if [[ -n "$o" ]]; then printf '%s' "$o"; else printf '%s' $(( $(phase_cap "$1" timeout_min) * 60 )); fi
}
TOOLS="$(jq -r --arg d "$TOOLS_DEFAULT" '.phase_defaults.tools // $d | if type == "array" then join(",") else . end' <<<"$SUITE_JSON")"
EFFORT_FLAG="$(jq -r '.effort // .toggles.effort // empty' <<<"$ARM_DEF")"
case "$EFFORT_FLAG" in ""|low|medium|high|xhigh|max) ;; *) die_usage "arm effort '$EFFORT_FLAG' is not low|medium|high|xhigh|max" ;; esac

if [[ "$DRY_RUN" == true ]]; then
  if [[ -n "$REFUSAL" ]]; then echo "pipeline-run.sh: refused: $REFUSAL" >&2; exit 2; fi
  plan="$(plan_phases "$SUITE_TOGGLES")"
  single="$(jq -r '.context_resets == false' <<<"$SUITE_TOGGLES")"
  echo "plan: task $TASK_ID type $TASK_TYPE arm $ARM executor $EXECUTOR cap USD $MAX_RUN_USD phases $(jq -r 'map(.label + (if .name == "FIX" then "?" else "" end)) | join(",")' <<<"$plan")"
  i=0
  while IFS=$'\t' read -r name label; do
    i=$((i + 1))
    sess=new
    if [[ "$single" == true ]]; then case "$name" in PLAN|IMPLEMENT|FIX) sess=implementer ;; esac; fi
    cond=""; [[ "$name" == FIX ]] && cond=" when=CHANGES_REQUIRED"
    printf 'phase %d %s model=%s max_turns=%s timeout_s=%s effort=%s session=%s%s\n' "$i" "$label" \
      "$(phase_model "$name")" "$(phase_cap "$name" max_turns)" "$(phase_timeout_s "$name")" \
      "${EFFORT_FLAG:--}" "$sess" "$cond"
  done < <(jq -r '.[] | [.name, .label] | @tsv' <<<"$plan")
  # the sandbox plan: the mount, the closed-mount overlay, the eval config variant and the
  # arm's config edits (the keys apply_arm_toggles sets in the sandbox .loa.config.yaml)
  if [[ "$(jq -r '.loa_mount' <<<"$SUITE_TOGGLES")" == false ]]; then
    sb_mount=none sb_overlay="none(no mount)" sb_variant=none sb_edits=-
  else
    sb_mount=loa sb_variant=eval
    if [[ "$KIND" != review-catch ]]; then sb_overlay="none(build)"
    elif [[ "$(jq -r '.oracle_open' <<<"$SUITE_TOGGLES")" == true ]]; then sb_overlay="none(oracle_open)"
    else sb_overlay="$OVERLAY_MODE"; fi
    # the edits come from the library's vocabulary (bd-gdl5s): every toggle the arm sets to a defined
    # value contributes its edits in vocabulary order, a path already listed once
    [[ -f "$SCRIPT_DIR/lib/sandbox-mount.sh" ]] || die_usage "mount library not found: $SCRIPT_DIR/lib/sandbox-mount.sh"
    vocab="$(cd "$SCRIPT_DIR" && source ./lib/sandbox-mount.sh && declare -F print_toggle_vocabulary >/dev/null && print_toggle_vocabulary)" \
      || die_usage "the mount library has no print_toggle_vocabulary"
    sb_edits="$(jq -r -R -n --argjson tg "$SUITE_TOGGLES" '
        [inputs | split("\t") | select(length >= 3)
         | .[0] as $k | .[1] as $vals | .[2] as $ed
         | select(($tg | has($k)) and (($vals | split("|")) | index($tg[$k] | tostring)) != null and $ed != "-")
         | $ed | split(",")[]]
        | reduce .[] as $e ([]; if index([$e]) == null then . + [$e] else . end)
        | if length == 0 then "-" else join(",") end' <<<"$vocab")"
  fi
  printf 'sandbox: mount=%s overlay=%s config_variant=%s config_edits=%s\n' "$sb_mount" "$sb_overlay" "$sb_variant" "$sb_edits"
  [[ "$EVAL_ONLY" == true ]] && echo "eval_only: true (batch context $BATCH_CONTEXT)"
  exit 0
fi

# --- run directory --------------------------------------------------------------
if [[ -e "$RUN_DIR" ]] && [[ -n "$(ls -A "$RUN_DIR" 2>/dev/null)" ]]; then
  die_usage "run dir exists and is not empty: $RUN_DIR"
fi
mkdir -p "$RUN_DIR"
RUN_DIR="$(cd "$RUN_DIR" && pwd)"
WS="$RUN_DIR/sandbox" META="$RUN_DIR/meta" SNAPS="$RUN_DIR/snapshots" TRANS="$RUN_DIR/transcripts" EVALD="$RUN_DIR/eval"
mkdir -p "$WS" "$META" "$SNAPS" "$TRANS" "$EVALD"
printf '%s\n' "$ARM" > "$META/arm"
PHASES_FILE="$META/phases.jsonl"; : > "$PHASES_FILE"
export ARM_EVIDENCE_FILE="$META/arm-evidence.txt"; : > "$ARM_EVIDENCE_FILE"
[[ -n "$BATCH_CONTEXT" ]] && printf 'batch_context=%s\n' "$BATCH_CONTEXT" >> "$ARM_EVIDENCE_FILE"
MOUNT_LOG="$META/mount.log"; : > "$MOUNT_LOG"

STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STATUS="running" CAP_PHASE="" CAP_TURN="null" REASON="" FINAL_WRITTEN=0
INTERRUPTED=0 CUR_PID="" CUR_CONTAINER=""
SPENT_MICRO=0 IMAGE_DIGEST="" FINGERPRINT="" SNAPSHOTS_JSON='{}' TOGGLES="$SUITE_TOGGLES"
MOUNT_SHA0_CLAUDE_MD="" MOUNT_SHA0_LOA_CONFIG="" MOUNT_INTEGRITY=null LOA_MOUNT=true
SOURCE_COMMIT="$(git -C "$SOURCE_TREE" rev-parse HEAD 2>/dev/null || echo unknown)"
SUITE_VERSION="$(jq -c --argjson t "$TASK_JSON" '$t.suite_version // .suite_version // .version // null' <<<"$SUITE_JSON")"
HOME_DIR="$META/home"   # container mode: the per-run writable HOME (deleted at exit)

now_ms() {  # epoch milliseconds; whole seconds × 1000 where date has no %N (BSD date)
  local t; t="$(date +%s%N)"
  case "$t" in *N) printf '%s000' "$(date +%s)" ;; *) printf '%s' "${t:0:13}" ;; esac
}
remove_tree() {  # remove_tree <dir> — permission-tolerant delete (credential copies)
  [[ -e "$1" ]] || return 0
  chmod -R u+rwx "$1" 2>/dev/null || true
  find "$1" -depth -delete 2>/dev/null || true
}

file_sha256() {  # file_sha256 <file> → hex (Python hashlib: no .claude/ code is sourced)
  python3 -I -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"
}
_mount_sha() {  # _mount_sha <file> → hex | absent | symlink (a symlink is never followed)
  if [[ -L "$1" ]]; then printf 'symlink'
  elif [[ -f "$1" ]]; then file_sha256 "$1" 2>/dev/null || printf 'unreadable'
  elif [[ -e "$1" ]]; then printf 'not-a-file'
  else printf 'absent'; fi
}
mount_state() {  # mount_state <baseline> <file> → ok | changed | absent
  local now; now="$(_mount_sha "$2")"
  if [[ "$1" == absent && "$now" == absent ]]; then printf 'absent'
  elif [[ "$now" == "$1" ]]; then printf 'ok'
  else printf 'changed'; fi
}
compute_mount_integrity() {  # sets MOUNT_INTEGRITY (stays null before materialisation)
  [[ -n "$MOUNT_SHA0_CLAUDE_MD" ]] || return 0
  if [[ "$LOA_MOUNT" == false ]]; then MOUNT_INTEGRITY='{"claude_md":"absent","loa_config":"absent"}'; return 0; fi
  MOUNT_INTEGRITY="$(jq -cn --arg c "$(mount_state "$MOUNT_SHA0_CLAUDE_MD" "$WS/CLAUDE.md")" \
    --arg l "$(mount_state "$MOUNT_SHA0_LOA_CONFIG" "$WS/.loa.config.yaml")" '{claude_md: $c, loa_config: $l}')"
}

evidence_json() {
  jq -Rn '[inputs | select(test("^[A-Za-z0-9_.:-]+=")) | capture("^(?<k>[^=]+)=(?<v>.*)$")]
          | reduce .[] as $e ({}; .[$e.k] = $e.v)' < "$ARM_EVIDENCE_FILE"
}

write_pipeline() {  # write_pipeline — (re)write meta/pipeline.json from the current state
  local phases ev finished
  phases="$(jq -sc '.' "$PHASES_FILE" 2>/dev/null || echo '[]')"
  ev="$(evidence_json 2>/dev/null || echo '{}')"
  finished=null
  [[ "$STATUS" != running ]] && finished="\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
  jq -n \
    --arg run_id "$RUN_ID" --arg arm "$ARM" --arg task_id "$TASK_ID" --arg task_type "$TASK_TYPE" \
    --argjson trial "$TRIAL" --arg source_commit "$SOURCE_COMMIT" --argjson suite_version "$SUITE_VERSION" \
    --argjson phases "$phases" --arg status "$STATUS" --arg cap_phase "$CAP_PHASE" --argjson cap_turn "$CAP_TURN" \
    --arg reason "$REASON" --argjson arm_evidence "$ev" --argjson toggles "$TOGGLES" --arg executor "$EXECUTOR" \
    --arg image_digest "$IMAGE_DIGEST" --arg fingerprint "$FINGERPRINT" --arg tools "$TOOLS" \
    --argjson snapshots "$SNAPSHOTS_JSON" --arg started "$STARTED" --argjson finished "$finished" \
    --argjson spent "$SPENT_MICRO" --arg cap "$MAX_RUN_USD" --arg effort "$EFFORT_FLAG" \
    --argjson mount_integrity "$MOUNT_INTEGRITY" '
    {schema_version: 1, run_id: $run_id, arm: $arm, task_id: $task_id, task_type: $task_type, trial: $trial,
     source_commit: $source_commit, suite_version: $suite_version, status: $status,
     cap_phase: (if $cap_phase == "" then null else $cap_phase end), cap_turn: $cap_turn,
     reason: (if $reason == "" then null else $reason end),
     max_run_usd: ($cap | tonumber), spent_usd: ($spent / 1000000),
     arm_toggles: $toggles, effort_flag: (if $effort == "" then null else $effort end), arm_evidence: $arm_evidence,
     executor_mode: $executor, image_digest: (if $image_digest == "" then null else $image_digest end),
     fingerprint: (if $fingerprint == "" then null else $fingerprint end), sandbox_fingerprint: (if $fingerprint == "" then null else $fingerprint end),
     tools: $tools, snapshots: $snapshots, phases: $phases, mount_integrity: $mount_integrity,
     started: $started, finished: $finished}' \
    > "$META/pipeline.json.tmp" && mv "$META/pipeline.json.tmp" "$META/pipeline.json"
}

finish() {  # finish <status> <exit> [reason]
  STATUS="$1"; [[ -n "${3:-}" ]] && REASON="$3"
  compute_mount_integrity || true
  write_pipeline
  FINAL_WRITTEN=1
  remove_tree "$HOME_DIR"
  [[ -n "$REASON" ]] && echo "pipeline-run.sh: $STATUS: $REASON" >&2
  exit "$2"
}
infra() { finish infrastructure_error 2 "$*"; }

on_exit() {
  local rc=$?
  remove_tree "$HOME_DIR"
  if [[ "$FINAL_WRITTEN" -eq 0 ]]; then
    STATUS=infrastructure_error; REASON="${REASON:-driver aborted (rc $rc)}"
    compute_mount_integrity 2>/dev/null || true
    write_pipeline 2>/dev/null || true
    exit 2
  fi
}
kill_phase() {
  [[ -n "$CUR_CONTAINER" ]] && "$DOCKER_BIN" kill --signal TERM "$CUR_CONTAINER" >/dev/null 2>&1 || true
  [[ -n "$CUR_PID" ]] && kill -TERM "$CUR_PID" 2>/dev/null || true
}
on_signal() { INTERRUPTED=1; kill_phase; }
trap on_exit EXIT
trap on_signal TERM INT HUP

if [[ -n "$REFUSAL" ]]; then
  jq -n --arg arm "$ARM" --arg task_id "$TASK_ID" --arg type "$TASK_TYPE" --arg reason "$REFUSAL" \
    --argjson tt "$(jq -c '.task_types // null' <<<"$ARM_DEF")" \
    '{arm: $arm, task_id: $task_id, type: $type, task_types: $tt, reason: $reason}' > "$META/refused.json"
  infra "refused: $REFUSAL"
fi

# --- mount library (implementer B's lib/sandbox-mount.sh) --------------------------------
# eval.yml trust boundary: a literal in-tree path, no variable on the source line.
# Tests run a temporary copy of this harness whose lib/sandbox-mount.sh is the stub
# (evals/tests/pipeline-run.bats make_harness); there is no environment override.
[[ -f "$SCRIPT_DIR/lib/sandbox-mount.sh" ]] || infra "mount library not found: $SCRIPT_DIR/lib/sandbox-mount.sh"
pushd "$SCRIPT_DIR" >/dev/null
# shellcheck source=lib/sandbox-mount.sh
source ./lib/sandbox-mount.sh || { popd >/dev/null; infra "mount library failed to load"; }
popd >/dev/null
for fn in mount_prompt_surface resolve_arm_toggles apply_arm_toggles regen_sandbox_manifest \
          check_fixture_path_rule write_sandbox_grimoire init_sandbox_beads \
          overlay_answer_paths check_mount_closed apply_eval_config_variant; do
  declare -F "$fn" >/dev/null || infra "mount library lacks $fn"
done
# --- session library (cycle-133 C-6): the exec shim, pass-through/secret keys, pricing ------
# eval.yml trust boundary: a literal in-tree path, no variable on the source line.
[[ -f "$SCRIPT_DIR/lib/session-exec.sh" ]] || infra "session library not found: $SCRIPT_DIR/lib/session-exec.sh"
pushd "$SCRIPT_DIR" >/dev/null
# shellcheck source=lib/session-exec.sh
source ./lib/session-exec.sh || { popd >/dev/null; infra "session library failed to load"; }
popd >/dev/null
# the library may set its own shell options or traps; the driver's stay as declared
set -euo pipefail
trap on_exit EXIT
trap on_signal TERM INT HUP
assert_secret_keys || infra "refused: a secret-shaped pass-through key is not in SECRET_KEYS (lib/session-exec.sh)"
# the library's contract: arm environment lines (gates: false → LOA_ADVERSARIAL_REVIEW_ENFORCE=false)
# land in ARM_ENV_FILE; write_sandbox_grimoire resolves sprint_plan from LOA_EVAL_SUITE_FILE
export ARM_ENV_FILE="$META/arm-env"; : > "$ARM_ENV_FILE"
export LOA_EVAL_SUITE_FILE="$SUITE_FILE"

lib_call() {  # lib_call <fn> <args…> — stdout appended to the evidence file; non-zero → infra
  local fn="$1" out rc=0 errf="$META/.lib-stderr" last; shift
  out="$("$fn" "$@" 2>"$errf")" || rc=$?
  cat "$errf" >> "$MOUNT_LOG" 2>/dev/null || true
  last="$(grep -v '^[[:space:]]*$' "$errf" 2>/dev/null | sed -n '$p' | cut -c1-300 || true)"
  rm -f "$errf"
  [[ -n "$out" ]] && printf '%s\n' "$out" >> "$ARM_EVIDENCE_FILE"
  [[ $rc -eq 0 ]] || infra "$fn exited $rc${last:+: $last} (see meta/mount.log)"
  LIB_OUT="$out"
}

LIB_OUT=""
lib_call resolve_arm_toggles "$ARM" "$SUITE_FILE"
TOGGLES="$(printf '%s\n' "$LIB_OUT" | sed -n '/^[[:space:]]*[{]/,$p')"
if [[ -z "$TOGGLES" ]] || ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$TOGGLES"; then
  infra "resolve_arm_toggles printed no toggles object"
fi
TOGGLES="$(jq -c '.' <<<"$TOGGLES")"
# the toggles object is evidence, not a key=value line: drop it from the evidence file
grep -E '^[A-Za-z0-9_.:-]+=' "$ARM_EVIDENCE_FILE" > "$ARM_EVIDENCE_FILE.tmp" || true
mv "$ARM_EVIDENCE_FILE.tmp" "$ARM_EVIDENCE_FILE"
PLAN_JSON="$(plan_phases "$TOGGLES")"
LOA_MOUNT=true; [[ "$(jq -r '.loa_mount' <<<"$TOGGLES")" == false ]] && LOA_MOUNT=false
SINGLE_SESSION=false; [[ "$(jq -r '.context_resets' <<<"$TOGGLES")" == false ]] && SINGLE_SESSION=true
GATES_OFF=false; [[ "$(jq -r '.gates' <<<"$TOGGLES")" == false ]] && GATES_OFF=true
FLATLINE=on; [[ "$(jq -r '.flatline' <<<"$TOGGLES")" == false ]] && FLATLINE=off
ORACLE_OPEN=false; [[ "$(jq -r '.oracle_open' <<<"$TOGGLES")" == true ]] && ORACLE_OPEN=true
BARE_MODEL_TOGGLE="$(jq -r '.bare_model // empty' <<<"$TOGGLES")"

# --- fingerprint / image ---------------------------------------------------------
if [[ "$EXECUTOR" == host ]]; then
  command -v "$CLAUDE_BIN" >/dev/null 2>&1 || [[ -x "$CLAUDE_BIN" ]] || infra "claude CLI not found: $CLAUDE_BIN"
fi
FINGERPRINT="$("$SCRIPT_DIR/fingerprint.sh" --source-tree "$SOURCE_TREE" --claude-bin "$CLAUDE_BIN" 2>/dev/null || echo "")"
if [[ "$EXECUTOR" == container ]]; then
  command -v "$DOCKER_BIN" >/dev/null 2>&1 || [[ -x "$DOCKER_BIN" ]] || infra "docker CLI not found: $DOCKER_BIN"
  IMAGE_DIGEST="$("$DOCKER_BIN" image inspect --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{else}}{{.Id}}{{end}}' "$IMAGE" 2>/dev/null || true)"
  [[ -n "$IMAGE_DIGEST" ]] || infra "container image not found: $IMAGE"
else
  IMAGE_DIGEST="$FINGERPRINT"
fi

# --- materialisation (D-4.5) -------------------------------------------------------
resolve_rel() {  # resolve_rel <relpath> → first existing dir among the candidate roots
  local rel="$1" c
  if [[ "$rel" == /* ]]; then [[ -d "$rel" ]] && { printf '%s' "$rel"; return 0; }; return 1; fi
  for c in "$TASK_DIR/$rel" "$SUITE_ROOT/$rel" "$REPO_ROOT/$rel" "$REPO_ROOT/evals/fixtures/$rel" "$SOURCE_TREE/evals/fixtures/$rel"; do
    [[ -d "$c" ]] && { (cd "$c" && pwd); return 0; }
  done
  return 1
}
sgit() {  # git on the sandbox repo, isolated from the operator's git config
  env -i PATH="$PATH" HOME="$META" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 LC_ALL=C \
    git -C "$WS" "$@"
}

if [[ "$KIND" == build ]]; then
  fx_rel="$(jq -r '.fixture // ""' <<<"$TASK_JSON")"
  [[ -n "$fx_rel" ]] || infra "build task has no fixture"
  FIXTURE_DIR="$(resolve_rel "$fx_rel")" || infra "fixture not found: $fx_rel"
  case "/$FIXTURE_DIR/" in */hidden/*) infra "fixture resolves inside a hidden directory: $fx_rel" ;; esac
  lib_call check_fixture_path_rule "$FIXTURE_DIR"
  cp -a "$FIXTURE_DIR/." "$WS/"
else
  fx_rel="$(jq -r '.review_catch.fixture // .fixture // ""' <<<"$TASK_JSON")"
  [[ -n "$fx_rel" ]] || infra "review-catch task has no review_catch.fixture"
  FIXTURE_DIR="$(resolve_rel "$fx_rel")" || infra "review-catch fixture not found: $fx_rel"
  mkdir -p "$WS/pr"
  for p in base head head.diff PR.md REVIEW-INSTRUCTIONS.md AUDIT-INSTRUCTIONS.md; do
    [[ -e "$FIXTURE_DIR/$p" ]] && cp -a "$FIXTURE_DIR/$p" "$WS/pr/"
  done
  [[ -f "$WS/pr/head.diff" ]] || infra "review-catch fixture has no head.diff: $fx_rel"
fi

# base commit: the fixture tree only; the mount paths are excluded so the gates'
# diff (base..HEAD) and the snapshots carry the agent's work, not the harness.
sgit init -q
sgit config user.name eval
sgit config user.email eval@loa
sgit config commit.gpgsign false
{
  printf '%s\n' '/.claude/' '/CLAUDE.md' '/.loa.config.yaml' '/grimoires/' '/.run/' '/.beads/' '/.eval/'
} >> "$WS/.git/info/exclude"
sgit add -A
sgit commit -q --allow-empty -m base
BASE_COMMIT="$(sgit rev-parse HEAD)"
printf 'base_commit=%s\n' "$BASE_COMMIT" >> "$ARM_EVIDENCE_FILE"

if [[ "$LOA_MOUNT" == true ]]; then
  lib_call mount_prompt_surface "$WS" "$SOURCE_TREE" -
fi
# closed mount (cycle-131 FR-1): the overlay before the toggles, the check after the manifest
CLOSED_MOUNT=false
if [[ "$KIND" == review-catch && "$LOA_MOUNT" == true ]]; then
  if [[ "$ORACLE_OPEN" == true ]]; then
    printf 'mount_overlay=none\n' >> "$ARM_EVIDENCE_FILE"
  else
    lib_call overlay_answer_paths "$WS" "$FIXTURE_DIR" "$OVERLAY_MODE" "$SOURCE_TREE" "$SOURCE_COMMIT"
    copy_source="$(sed -n 's/^copy_source=//p' "$ARM_EVIDENCE_FILE" | sed -n '$p')"
    [[ "$copy_source" == "$SOURCE_COMMIT" ]] || infra "copy_source ${copy_source:-<none>} differs from source_commit $SOURCE_COMMIT"
    grep -qE '^mount_overlay=(head|base):[0-9]+$' "$ARM_EVIDENCE_FILE" || infra "overlay_answer_paths printed no mount_overlay"
    CLOSED_MOUNT=true
  fi
fi
lib_call apply_arm_toggles "$WS" "$TOGGLES" "$ARM"
if [[ "$LOA_MOUNT" == true ]]; then
  lib_call apply_eval_config_variant "$WS"
  lib_call write_sandbox_grimoire "$WS" "$TASK_YAML" "$ARM" "$SPRINT"
  lib_call init_sandbox_beads "$WS" "$(jq -r '.title // .id' <<<"$TASK_JSON")"
  mkdir -p "$WS/.run"
  [[ -e "$WS/.run/zone-guard-authorization.json" ]] && infra "sandbox carries .run/zone-guard-authorization.json"
  lib_call regen_sandbox_manifest "$WS"
  grep -q '^manifest_sha256=' "$ARM_EVIDENCE_FILE" || infra "regen_sandbox_manifest printed no manifest_sha256"
  # the checked surface is the launched one: after the toggles, the config writes and the manifest
  if [[ "$CLOSED_MOUNT" == true ]]; then
    lib_call check_mount_closed "$WS" "$FIXTURE_DIR" "$SOURCE_TREE"
  fi
else
  [[ -e "$WS/.claude" || -e "$WS/CLAUDE.md" ]] && infra "loa_mount: false but the sandbox has .claude/ or CLAUDE.md"
  printf 'loa_mount=none\n' >> "$ARM_EVIDENCE_FILE"
fi
# mount integrity baseline (audit LOW-A2): Bash can rewrite CLAUDE.md or .loa.config.yaml
# without a Write/Edit tool input; finish() compares against these
MOUNT_SHA0_CLAUDE_MD="$(_mount_sha "$WS/CLAUDE.md")"
MOUNT_SHA0_LOA_CONFIG="$(_mount_sha "$WS/.loa.config.yaml")"
printf 'claude_md_sha256=%s\nloa_config_sha256=%s\n' "$MOUNT_SHA0_CLAUDE_MD" "$MOUNT_SHA0_LOA_CONFIG" >> "$ARM_EVIDENCE_FILE"

# --- mount_cheval (cycle-132 bd-56nn6, KF-050): the mounted adapters import before any spend ---------
# a dissent-enabled arm: its gates run the adversarial dissent through cheval (an AUDIT phase, or a REVIEW
# phase whose dissent is not turned off; gates: false turns both off)
DISSENT_ON=false
if [[ "$LOA_MOUNT" == true && "$GATES_OFF" != true ]]; then
  if jq -e 'map(.name) | index("AUDIT") != null' >/dev/null <<<"$PLAN_JSON" \
     || { jq -e 'map(.name) | index("REVIEW") != null' >/dev/null <<<"$PLAN_JSON" \
          && [[ "$(jq -r '.dissent' <<<"$TOGGLES")" != false ]]; }; then
    DISSENT_ON=true
  fi
fi
if [[ "$LOA_MOUNT" == true ]]; then
  if [[ ! -d "$WS/.claude/adapters/loa_cheval" || -L "$WS/.claude/adapters" || -L "$WS/.claude/adapters/loa_cheval" ]]; then
    MOUNT_CHEVAL="broken:no .claude/adapters/loa_cheval"
  else
    cheval_rc=0
    cheval_err="$(env -i PATH="$PATH" LC_ALL=C timeout 60 python3 -I -B -c \
      'import sys; sys.path.insert(0, sys.argv[1]); import loa_cheval, loa_cheval.providers' "$WS/.claude/adapters" 2>&1 >/dev/null)" \
      || cheval_rc=$?
    if [[ $cheval_rc -eq 0 ]]; then MOUNT_CHEVAL=ok
    else
      cheval_last="$(printf '%s\n' "$cheval_err" | grep -v '^[[:space:]]*$' | sed -n '$p' | tr -d '\r' | cut -c1-200)"
      MOUNT_CHEVAL="broken:${cheval_last:-exit $cheval_rc}"
    fi
  fi
else
  MOUNT_CHEVAL=none
fi
printf 'mount_cheval=%s\n' "$MOUNT_CHEVAL" >> "$ARM_EVIDENCE_FILE"
if [[ "$MOUNT_CHEVAL" == broken:* && "$DISSENT_ON" == true ]]; then
  jq -n --arg arm "$ARM" --arg task_id "$TASK_ID" --arg type "$TASK_TYPE" --arg detail "${MOUNT_CHEVAL#broken:}" \
    '{arm: $arm, task_id: $task_id, type: $type, reason: "mount_cheval_broken", detail: $detail}' > "$META/refused.json"
  finish infrastructure_error 3 "refused: mount_cheval_broken: ${MOUNT_CHEVAL#broken:} (a dissent-enabled arm on a mount whose cheval does not import; KF-050)"
fi
mkdir -p "$WS/.eval/tmp" "$WS/.eval/gh-empty"
: > "$WS/.eval/model-invoke.jsonl"
: > "$WS/.eval/cost-ledger.jsonl"

# --- leak guards (AC-4.2, AC-5.5) ----------------------------------------------------
hidden_hit="$(cd "$WS" && find . -path ./.git -prune -o -path ./.claude -prune -o \
  \( -iname hidden -o -iname 'hidden-tests' -o -iname 'hidden.*' \) -print | sed -n '1p')"
[[ -z "$hidden_hit" ]] || infra "sandbox contains a hidden path: ${hidden_hit#./}"
# cycle-132 round 5 (PREREGISTRATION §12 addendum 1): the arm ids the PR content itself names. A PR that built the
# ablation arms names them in its own diff and description; such text tells the agent nothing about which arm it is
# PR_NATIVE: every id of the suite that occurs in pr/ (PR.md, head.diff, base/, head/ — copied from the fixture,
# before any agent ran)
PR_NATIVE=""
if [[ -d "$WS/pr" ]]; then
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if grep -rIqF -e "$id" "$WS/pr" 2>/dev/null; then PR_NATIVE="$PR_NATIVE$id"$'\n'; fi
  done <<<"$ALL_ARM_IDS"
fi
pr_native_csv="$(printf '%s' "$PR_NATIVE" | sed '/^$/d' | LC_ALL=C sort -u | paste -sd, - || true)"
printf 'arm_ids_pr_native=%s\n' "${pr_native_csv:-none}" >> "$ARM_EVIDENCE_FILE"
# the PR-derived files: anything under pr/; the review skill's report the mount library writes from pr/PR.md
# (write_sandbox_grimoire: grimoires/loa/a2a/<sprint>/reviewer.md); the closed-mount overlay's answer paths
# (overlay_answer_paths: each path of an overlay_sha256= evidence line, the PR's own version of a .claude/ file).
# grimoires/loa/sprint.md is template text plus the task criterion (no PR text), so it is not PR-derived
OVERLAY_PATHS="$(sed -n 's/^overlay_sha256=\(.*\)=[^=]*$/\1/p' "$ARM_EVIDENCE_FILE")"
pr_derived() {  # pr_derived <path relative to the sandbox>
  case "$1" in pr/*|"grimoires/loa/a2a/$SPRINT/reviewer.md") return 0 ;; esac
  [[ -n "$OVERLAY_PATHS" ]] && grep -qxF -e "$1" <<<"$OVERLAY_PATHS"
}
ARM_PR_NATIVE=false
grep -qxF -e "$ARM" <<<"$PR_NATIVE" && ARM_PR_NATIVE=true
# the running arm's id in the sandbox refuses the launch, except a PR-native id in a PR-derived file
while IFS= read -r arm_hit; do
  [[ -n "$arm_hit" ]] || continue
  rel="${arm_hit#"$WS"/}"
  if [[ "$ARM_PR_NATIVE" == true ]] && pr_derived "$rel"; then continue; fi
  infra "arm id appears in the sandbox: $rel"
done < <(grep -rIl --exclude-dir=.git -F -e "$ARM" "$WS" 2>/dev/null | LC_ALL=C sort || true)

leak_scan() {  # leak_scan <file> — `hidden`, a defect key or any arm id → non-zero
  local f="$1" id
  grep -qi 'hidden' "$f" && { echo "the word hidden"; return 1; }
  grep -qE 'D[0-9]{2}-' "$f" && { echo "a defect key"; return 1; }
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    grep -qF -e "$id" "$f" && { echo "arm id $id"; return 1; }
  done <<<"$ALL_ARM_IDS"
  return 0
}
if [[ -f "$WS/grimoires/loa/context/task-brief.md" ]]; then
  why="$(leak_scan "$WS/grimoires/loa/context/task-brief.md")" || infra "task-brief.md leaks $why"
fi

# --- prompts (D-4.4) -----------------------------------------------------------------
subst() {  # subst <text> <key> <value>
  local text="$1" key="{{$2}}" val="$3"
  printf '%s' "${text//"$key"/$val}"
}
if [[ "$KIND" == review-catch ]]; then
  CHANGE_NOTE="The change under review is the pull request in \`pr/\`: \`pr/head.diff\` is the complete change (base to head), \`pr/base/\` and \`pr/head/\` hold every touched file before and after it, and \`pr/PR.md\` is its description (also carried as the implementation report). Cite findings as \`head/<path>:<line>\` with line numbers from the \`pr/head/\` files. When your skill runs the adversarial dissent, pass \`--diff-file pr/head.diff\`."
else
  CHANGE_NOTE="The change under review is the diff from the base commit \`$BASE_COMMIT\` to the current tree (\`git diff $BASE_COMMIT\`)."
fi
build_prompt() {  # build_prompt <name> <out-file>
  local name="$1" out="$2" tpl text contract tc
  tpl="$(cat "$PROMPTS_DIR/$name.md")"
  if [[ "$name" == BARE ]]; then
    if [[ -f "$TASK_DIR/TASK.md" ]]; then text="$(cat "$TASK_DIR/TASK.md")"
    elif [[ "$KIND" == review-catch && -f "$WS/pr/REVIEW-INSTRUCTIONS.md" ]]; then text="$(cat "$WS/pr/REVIEW-INSTRUCTIONS.md")"
    else text="$(jq -r '.criterion // ""' <<<"$TASK_JSON")"; fi
    if [[ "$KIND" == review-catch ]]; then
      contract="The pull request is under \`pr/\` (\`pr/PR.md\`, \`pr/head.diff\`, \`pr/base/\`, \`pr/head/\`). Write your findings to \`review.md\` at the repository root: one line per finding as \`head/<path>:<line> — <description>\` with line numbers from the \`pr/head/\` files, and a final line \`Verdict: APPROVED\` or \`Verdict: CHANGES_REQUIRED\`."
    else
      tc="$(jq -r '.test_command // [] | if type == "array" then join(" ") else . end' <<<"$TASK_JSON")"
      contract="Test command: \`$tc\`. Write your changes in place; run the tests; stop when they pass."
    fi
    tpl="$(subst "$tpl" TASK_TEXT "$text")"
    tpl="$(subst "$tpl" CONTRACT "$contract")"
  fi
  tpl="$(subst "$tpl" SPRINT "$SPRINT")"
  tpl="$(subst "$tpl" TASK_ID "$TASK_ID")"
  tpl="$(subst "$tpl" FLATLINE "$FLATLINE")"
  tpl="$(subst "$tpl" CHANGE_NOTE "$CHANGE_NOTE")"
  printf '%s\n' "$tpl" > "$out"
}

# --- per-run HOME (container mode; DEC-0411 as amended in Sprint 258) -------------------------
# One writable host directory mounted at /home/evaluser: the CLI's session store lives
# there for the whole run (A6 --resume continues across phases), and it holds only the
# codex CLI's own files: config.toml verbatim and auth.json with a PLACEHOLDER tokens.refresh_token
# (KF-048: the refresh token is single-use, so a container that refreshed with a verbatim
# copy invalidated the host's token and every later run's; an unreadable auth.json gives
# the run no codex credential and one WARN line). EXPOSURE (Sprint 261 audit DISS-C-001, bead
# bd-lfrkn): the copy carries tokens.access_token, id_token and account_id because the codex CLI
# needs all three (a copy without id_token gets 401 Missing bearer), and /home/evaluser is
# readable by the agent under evaluation, so the bearer is exposed to it for the token's lifetime
# (bounded by run-ablation.sh's pre-flight horizon). A long-lived OPENAI_API_KEY is never copied
# unless LOA_EVAL_CODEX_APIKEY_COPY=1 (API-key mode only; the run otherwise has no codex
# credential and says so). ~/.claude/.credentials.json and
# ~/.claude/settings.json are never copied: the Bedrock route authenticates from AWS_BEARER_TOKEN_BEDROCK in the environment,
# and --setting-sources project ignores user settings.
CREDS_HOME="${LOA_EVAL_CREDS_HOME:-$HOME}"
make_home() {
  mkdir -p "$HOME_DIR/.claude" "$HOME_DIR/.aws" "$HOME_DIR/.codex"
  # the sandbox project is pre-trusted so the mounted tree's project settings apply without the dialog
  # (the CLI otherwise ignores permissions.allow and warns; lead, Sprint 258 smoke)
  printf '{"projects":{"/workspace":{"hasTrustDialogAccepted":true}}}\n' > "$HOME_DIR/.claude.json"
  if [[ -f "$CREDS_HOME/.codex/config.toml" ]]; then cp "$CREDS_HOME/.codex/config.toml" "$HOME_DIR/.codex/config.toml"; fi
  # auth.json: a copy whose refresh token is a placeholder (KF-048). The real one is single-use; a
  # container that refreshed with a verbatim copy consumed the host's token and every later run and
  # the host failed with 401 refresh_token_reused. The key must stay: the codex CLI treats a missing
  # refresh_token as logged out and sends no bearer at all (401 Missing bearer; KF-048 recurrence 2),
  # so the value is a placeholder that can only fail to refresh. Paths only in argv; the host file is never written.
  if [[ -f "$CREDS_HOME/.codex/auth.json" ]]; then
    python3 -I -c '
import json, os, sys
src, dst = sys.argv[1], sys.argv[2]
try:
    with open(src, "rb") as fh:
        data = json.loads(fh.read().decode("utf-8"))
except Exception:
    data = None
if not isinstance(data, dict):
    sys.exit(3)
tok = data.get("tokens")
if isinstance(tok, dict):
    if "refresh_token" in tok:
        tok["refresh_token"] = "loa-ablation-no-refresh-token"
# OPENAI_API_KEY (Sprint 261 audit DISS-C-001): a long-lived key never reaches the agent-writable HOME
# unless the operator accepts the exposure with LOA_EVAL_CODEX_APIKEY_COPY=1 and the file is in API-key
# mode (no usable access token); in ChatGPT mode the key is unused by codex and is dropped.
has_at = isinstance(tok, dict) and isinstance(tok.get("access_token"), str) and bool(tok.get("access_token"))
key = data.get("OPENAI_API_KEY")
if isinstance(key, str) and key:
    if has_at or os.environ.get("LOA_EVAL_CODEX_APIKEY_COPY") != "1":
        data["OPENAI_API_KEY"] = None
        if not has_at:
            sys.stderr.write("pipeline-run: WARN codex auth.json is in API-key mode; the key is not copied into the "
                             "agent-writable HOME (set LOA_EVAL_CODEX_APIKEY_COPY=1 to accept the exposure); "
                             "the run has no codex credential\n")
fd = os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
os.fchmod(fd, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as out:
    json.dump(data, out)
    out.write("\n")
' "$CREDS_HOME/.codex/auth.json" "$HOME_DIR/.codex/auth.json" \
      || { rm -f "$HOME_DIR/.codex/auth.json"
           echo "pipeline-run: WARN codex auth.json unreadable; the run has no codex credential" >&2; }
  fi
  chmod 0700 "$HOME_DIR" "$HOME_DIR/.claude" "$HOME_DIR/.aws" "$HOME_DIR/.codex"
}
[[ "$EXECUTOR" == container ]] && make_home

# --- pricing: price_for / price_events / unmetered_tail come from lib/session-exec.sh (C-6) ---

# --- phase execution ----------------------------------------------------------------
IMPL_SESSION="" LAST_VERDICT="none" CUR_LABEL=""
in_container_path() { local p="$1"; printf '%s' "/workspace${p#"$WS"}"; }

# ENV_SHIM, PASS_KEYS and SECRET_KEYS come from lib/session-exec.sh: the shim is used on the
# host (host mode, and around the docker client) and inside the container.

run_phase() {  # run_phase <name> <label>
  local name="$1" label="$2" model turns tsec prompt_file events errf argv_file
  local -a cargv envkv full
  model="$(phase_model "$name")"
  turns="$(phase_cap "$name" max_turns)"
  tsec="$(phase_timeout_s "$name")"
  prompt_file="$META/prompt-$label.md"
  events="$TRANS/events-$label.jsonl"; errf="$TRANS/stderr-$label.log"
  argv_file="$META/phase-$label.argv.json"
  build_prompt "$name" "$prompt_file"
  local why; why="$(leak_scan "$prompt_file")" || infra "phase prompt $label leaks $why"

  local resume=""
  if [[ "$SINGLE_SESSION" == true && -n "$IMPL_SESSION" ]]; then
    case "$name" in PLAN|IMPLEMENT|FIX) resume="$IMPL_SESSION" ;; esac
  fi
  local cbin="$CLAUDE_BIN"; [[ "$EXECUTOR" == container ]] && cbin="${LOA_EVAL_CONTAINER_CLAUDE_BIN:-claude}"
  cargv=("$cbin" -p "$(cat "$prompt_file")" --output-format stream-json --verbose --model "$model"
         --permission-mode bypassPermissions --dangerously-skip-permissions --setting-sources project
         --tools "$TOOLS" --max-turns "$turns")
  [[ -n "$EFFORT_FLAG" ]] && cargv+=(--effort "$EFFORT_FLAG")
  [[ -n "$resume" ]] && cargv+=(--resume "$resume")

  local ev_ws="$WS" home_v="$HOME" path_v="$PATH"
  if [[ "$EXECUTOR" == container ]]; then
    ev_ws="/workspace"; home_v="/home/evaluser"; path_v="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  fi
  envkv=("PATH=$path_v" "HOME=$home_v" "LANG=${LANG:-C.UTF-8}" "LC_ALL=$LC_ALL" "TERM=${TERM:-dumb}"
         "TMPDIR=$ev_ws/.eval/tmp" "CLAUDE_CODE_USE_BEDROCK=${CLAUDE_CODE_USE_BEDROCK:-1}")
  local pk
  for pk in $PASS_KEYS; do
    if [[ -n "${!pk:-}" ]]; then envkv+=("$pk=${!pk}"); fi
  done
  envkv+=("CLAUDE_CODE_SUBAGENT_MODEL=$model"
          "LOA_MODELINV_LOG_PATH=$ev_ws/.eval/model-invoke.jsonl"
          "LOA_COST_LEDGER_PATH=$ev_ws/.eval/cost-ledger.jsonl"
          "GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1" "GH_CONFIG_DIR=$ev_ws/.eval/gh-empty")
  local kv_arm have_enforce=false
  while IFS= read -r kv_arm; do
    [[ "$kv_arm" =~ ^LOA_[A-Z0-9_]+= ]] || continue    # the arm's own variables only (never PATH, HOME, keys)
    envkv+=("$kv_arm"); [[ "$kv_arm" == LOA_ADVERSARIAL_REVIEW_ENFORCE=* ]] && have_enforce=true
  done < <(LC_ALL=C sort -u "$ARM_ENV_FILE" 2>/dev/null || true)
  [[ "$GATES_OFF" == true && "$have_enforce" == false ]] && envkv+=("LOA_ADVERSARIAL_REVIEW_ENFORCE=false")

  local cname="" keys="" kv k
  for kv in "${envkv[@]}"; do keys="$keys${keys:+,}${kv%%=*}"; done
  if [[ "$EXECUTOR" == container ]]; then
    cname="loa-abl-$(printf '%s-%s' "$RUN_ID" "$label" | tr -c 'A-Za-z0-9_.-' '-' | cut -c1-100)"
    # the docker client keeps only what it needs plus the secrets it forwards by name
    local hostkeys="PATH,HOME,DOCKER_HOST,DOCKER_CONFIG,XDG_RUNTIME_DIR"
    for k in $SECRET_KEYS; do if [[ -n "${!k:-}" ]]; then hostkeys="$hostkeys,$k"; fi; done
    # cycle-133 FR-9 (SDD C-9) the egress block. The arm's `egress` (arms[].egress, else the suite's
    # egress.arms.<id>, else egress.default, else blocked) and $LOA_EVAL_EGRESS_NETWORK (run-ablation.sh
    # exports it after checking the block is up): a blocked arm joins loa-egress-<batch> (internal, no route
    # out) with DNS sinkholed and the sidecar loa-proxy-<batch> as its only way out; otherwise --network bridge.
    # meta/egress.json records the decision; lib/egress-proxy.sh record-address (background) records the
    # container's address in meta/egress-addr.jsonl and its denials in meta/egress-denied.jsonl.
    local egress_mode egress_net="${LOA_EVAL_EGRESS_NETWORK:-}" egress_purl="" pv
    local -a netargs=(--network bridge)
    egress_mode="$(jq -r --arg a "$ARM" --argjson s "$SUITE_JSON" '.egress // ($s.egress // {} | .arms // {})[$a] // ($s.egress // {}).default // "blocked"' <<<"$ARM_DEF")"
    case "$egress_mode" in blocked|bridge) ;; *) infra "arm $ARM: egress '$egress_mode' is not blocked|bridge" ;; esac
    if [[ "$egress_mode" == blocked && -n "$egress_net" ]]; then
      [[ "$egress_net" =~ ^loa-egress-[A-Za-z0-9._-]{1,80}$ ]] || infra "LOA_EVAL_EGRESS_NETWORK '$egress_net' is not loa-egress-<batch>"
      egress_purl="http://loa-proxy-${egress_net#loa-egress-}:8888"
      netargs=(--network "$egress_net" --dns 0.0.0.1)
      for pv in HTTPS_PROXY https_proxy HTTP_PROXY http_proxy; do envkv+=("$pv=$egress_purl"); keys="$keys,$pv"; done
      envkv+=("NO_PROXY=" "no_proxy="); keys="$keys,NO_PROXY,no_proxy"
      LOA_EGRESS_ADDR_WAIT_S=30 "$SCRIPT_DIR/lib/egress-proxy.sh" record-address --network "$egress_net" --container "$cname" \
        --label "$label" --meta "$META" --event watch --max-s $((tsec + 120)) --parent-pid $$ --docker-bin "$DOCKER_BIN" \
        </dev/null >/dev/null 2>>"$META/egress-record.log" &
    fi
    jq -cn --arg m "$egress_mode" --arg n "${netargs[1]}" --arg p "$egress_purl" --arg l "$label" \
      '{label: $l, egress: $m, network: $n, proxy_url: (if $p == "" then null else $p end), enforced: ($p != ""),
        dns: (if $p == "" then null else "0.0.0.1" end)}' >> "$META/egress.jsonl"
    full=(python3 -I -c "$ENV_SHIM" "$hostkeys"
          "$DOCKER_BIN" run --rm --name "$cname" --user "$(id -u):$(id -g)"
          "${netargs[@]}" --read-only --tmpfs /tmp:rw,size=1g
          --pids-limit 512 --memory 4g --cpus 2
          -v "$WS:/workspace:rw"
          -v "$HOME_DIR:/home/evaluser:rw"
          -w /workspace)
    for kv in "${envkv[@]}"; do
      k="${kv%%=*}"
      if [[ "$SECRET_KEYS" == *" $k "* ]]; then full+=(-e "$k"); else full+=(-e "$kv"); fi
    done
    full+=("$IMAGE" python3 -I -c "$ENV_SHIM" "$keys" timeout --signal=TERM --kill-after=15 "$tsec" "${cargv[@]}")
  else
    full=(python3 -I -c "$ENV_SHIM" "$keys" timeout --signal=TERM --kill-after=15 "$tsec" "${cargv[@]}")
  fi

  # argv + environment capture (took-effect.sh reads it; the grader never does)
  jq -n --arg label "$label" --arg name "$name" --arg executor "$EXECUTOR" --arg cwd "$ev_ws" \
    --arg resume "$resume" --argjson tsec "$tsec" \
    --argjson argv "$(printf '%s\0' "${cargv[@]}" | jq -Rs 'split("\u0000") | .[:-1]')" \
    --argjson env "$(printf '%s\0' "${envkv[@]}" | jq -Rs --arg secret "$SECRET_KEYS" 'split("\u0000") | .[:-1]
        | map(capture("^(?<k>[^=]+)=(?<v>.*)$"; "s")) | map(.k as $k | {($k): (if ($secret | contains(" " + $k + " ")) then "<set>" else .v end)}) | add')" \
    --argjson launcher "$(printf '%s\0' "${full[@]}" | jq -Rs 'split("\u0000") | .[:-1]')" \
    '{label: $label, name: $name, executor: $executor, cwd: $cwd, timeout_s: $tsec,
      resume: (if $resume == "" then null else $resume end), argv: $argv, env: $env,
      launcher_argv: $launcher, container: ($executor == "container")}' > "$argv_file"

  local ledger_before=0 started_iso start_s end_s rc=0 prices killed=0 cap_turn=0 est="0 0 0" budget
  local metering=metered est_new="" um=""
  ledger_before="$(wc -l < "$WS/.eval/cost-ledger.jsonl" | tr -d ' ')"
  local minv_before minv_after
  minv_before="$(wc -l < "$WS/.eval/model-invoke.jsonl" | tr -d ' ')"
  started_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  start_s="$(now_ms)"
  prices=ERR
  if ! prices="$(price_for "$model")" || [[ "$prices" == ERR ]]; then
    finish infrastructure_error 2 "metering_incomplete: no valid price for model $model (phase $label)"
  fi
  budget=$(( CAP_MICRO - SPENT_MICRO ))
  CUR_LABEL="$label" CUR_CONTAINER="$cname"
  # the allowlist values enter the launcher's environment by export (never argv); the
  # shim then keeps exactly the allowlist (host) or the docker client's keys (container)
  ( cd "$WS" || exit 2
    if [[ "$EXECUTOR" == host ]]; then for kv in "${envkv[@]}"; do export "$kv"; done; fi
    exec "${full[@]}" ) < /dev/null > "$events" 2> "$errf" &
  CUR_PID=$!
  local poll="${LOA_EVAL_WATCHDOG_POLL_S:-1}"
  while kill -0 "$CUR_PID" 2>/dev/null; do
    sleep "$poll" || true
    [[ "$INTERRUPTED" -eq 1 ]] && break
    if ! est_new="$(price_events "$events" "$prices" "$budget")" || [[ "$est_new" == ERR ]]; then
      metering=incomplete
      echo "pipeline-run.sh: watchdog: $label metering_incomplete (the stream cannot be priced); SIGTERM" >&2
      kill_phase
      break
    fi
    est="$est_new"
    if [[ "${est##* }" -gt 0 ]]; then
      killed=1; cap_turn="${est##* }"
      echo "pipeline-run.sh: watchdog: $label estimate passes the cap at turn $cap_turn; SIGTERM" >&2
      kill_phase
      break
    fi
  done
  wait "$CUR_PID" 2>/dev/null || rc=$?
  # a trapped signal interrupts `wait` (status > 128, child still a job): wait for
  # the child to go, then reap its real status (127 = already reaped)
  if [[ $rc -gt 128 && "$INTERRUPTED" -eq 1 ]]; then
    while kill -0 "$CUR_PID" 2>/dev/null; do sleep 0.2; done
    local rc2=0; wait "$CUR_PID" 2>/dev/null || rc2=$?
    [[ $rc2 -ne 127 ]] && rc=$rc2
  fi
  end_s="$(now_ms)"
  CUR_PID="" CUR_CONTAINER=""
  if [[ "$metering" == metered ]]; then
    if ! est_new="$(price_events "$events" "$prices" "$budget")" || [[ "$est_new" == ERR ]]; then
      metering=incomplete
    else
      est="$est_new"
    fi
  fi

  # --- record ---
  local result init_sid sid ledger_rows ledger_micro rf timed_out=false elapsed_ms
  elapsed_ms=$(( end_s - start_s ))
  result="$(grep -E '^\{.*"type" *: *"result"' "$events" 2>/dev/null | sed -n '$p' || true)"
  if [[ -z "$result" ]] || ! jq -e . >/dev/null 2>&1 <<<"$result"; then
    result='{"type":"result","subtype":"missing","is_error":true}'
  fi
  init_sid="$(jq -R -r 'fromjson? | select(.type == "system" and .subtype == "init") | .session_id // empty' "$events" 2>/dev/null | sed -n '1p' || true)"
  sid="${init_sid:-$(jq -r '.session_id // empty' <<<"$result")}"
  # an attempt without any usage event and without a result cost is unmetered, never zero spend (C-6)
  if [[ "$metering" == metered ]] && ! jq -e '(.total_cost_usd | type) == "number"' >/dev/null 2>&1 <<<"$result"; then
    if ! um="$(unmetered_tail "$events")" || [[ "$um" == ERR ]]; then metering=incomplete
    elif [[ "$um" == true ]]; then metering=unmetered_attempt; fi
  fi
  if [[ "$SINGLE_SESSION" == true && -z "$IMPL_SESSION" && -n "$sid" ]]; then
    case "$name" in PLAN|IMPLEMENT|FIX) IMPL_SESSION="$sid" ;; esac
  fi
  rf="$(jq -R -c 'fromjson? | select(.type == "system" and .subtype == "model_refusal_fallback")
        | {from: (.original_model // null), to: (.fallback_model // null), category: (.api_refusal_category // null), scope: (.scope // null)}' \
        "$events" 2>/dev/null | jq -sc '.' 2>/dev/null || echo '[]')"
  [[ -n "$rf" ]] || rf='[]'
  ledger_rows="$(sed -n "$((ledger_before + 1)),\$p" "$WS/.eval/cost-ledger.jsonl" 2>/dev/null || true)"
  ledger_micro="$(printf '%s\n' "$ledger_rows" | jq -R -n '[inputs | fromjson? | select(type == "object")
        | (.cost_micro_usd // ((.cost_usd // 0) * 1000000))] | add // 0 | round' 2>/dev/null || echo 0)"
  minv_after="$(wc -l < "$WS/.eval/model-invoke.jsonl" | tr -d ' ')"
  cp "$WS/.eval/model-invoke.jsonl" "$EVALD/model-invoke.jsonl" 2>/dev/null || true
  cp "$WS/.eval/cost-ledger.jsonl" "$EVALD/cost-ledger.jsonl" 2>/dev/null || true
  # audit MEDIUM-A1: the gate's dissent envelope is copied to eval/ once, at the end of the
  # phase that produced it, and never overwritten: a later phase (FIX, AUDIT) that edits the
  # sandbox copy cannot change what ablation-row.sh and took-effect.sh read
  local env_gate="" env_copied=false env_sha="" env_src env_dst
  case "$name" in REVIEW) env_gate=review ;; AUDIT) env_gate=audit ;; esac
  if [[ -n "$env_gate" ]]; then
    env_src="$WS/grimoires/loa/a2a/$SPRINT/adversarial-$env_gate.json" env_dst="$EVALD/adversarial-$env_gate.json"
    [[ -e "$env_dst" || -L "$env_dst" || -L "$env_src" || ! -f "$env_src" ]] \
      || { cp "$env_src" "$env_dst" 2>/dev/null && env_copied=true; } || true
    if [[ -f "$env_dst" && ! -L "$env_dst" ]]; then env_sha="$(file_sha256 "$env_dst" 2>/dev/null || true)"; fi
  fi
  if [[ $rc -eq 124 ]] || { [[ $rc -eq 137 ]] && [[ $elapsed_ms -ge $(( tsec * 1000 )) ]]; }; then timed_out=true; fi

  local snap="" verdict=null skill effort_req
  if [[ "$INTERRUPTED" -eq 0 ]] && { [[ "$name" == IMPLEMENT ]] || [[ "$name" == FIX ]]; }; then
    sgit add -A >/dev/null 2>&1 || true
    sgit commit -q --allow-empty -m "snapshot $label" >/dev/null 2>&1 || true
    snap="$(sgit rev-parse HEAD 2>/dev/null || true)"
    if [[ -n "$snap" ]]; then
      sgit bundle create "$SNAPS/$label.bundle" HEAD >/dev/null 2>&1 || true
      SNAPSHOTS_JSON="$(jq -c --arg k "$(printf '%s' "$label" | tr 'A-Z' 'a-z')" --arg v "$snap" '.[$k] = $v' <<<"$SNAPSHOTS_JSON")"
      jq -n --argjson s "$SNAPSHOTS_JSON" --arg base "$BASE_COMMIT" '$s + {base: $base}' > "$SNAPS/index.json"
    fi
  fi
  case "$name" in
    REVIEW) verdict="$(gate_verdict "$WS/grimoires/loa/a2a/$SPRINT/engineer-feedback.md")" ;;
    AUDIT)  verdict="$(gate_verdict "$WS/grimoires/loa/a2a/$SPRINT/auditor-sprint-feedback.md")" ;;
  esac
  if [[ "$name" == REVIEW || "$name" == AUDIT ]]; then LAST_VERDICT="$verdict"; fi
  # Sprint 258 smoke (lead, DEC-0490): a gate that exhausted --max-turns AFTER writing its LOA-VERDICT
  # trailer has delivered its result; the extra turns were housekeeping. Count the phase as completed
  # with turn_cap_hit=true and keep the CLI's exit in cli_exit. Any other phase keeps the error.
  local subtype turn_cap_hit=false gate_recovered=false cli_exit="$rc"
  subtype="$(jq -r '.subtype // ""' <<<"$result")"
  [[ "$subtype" == error_max_turns ]] && turn_cap_hit=true
  if [[ "$turn_cap_hit" == true && $rc -ne 0 && "$INTERRUPTED" -eq 0 ]] && { [[ "$name" == REVIEW ]] || [[ "$name" == AUDIT ]]; } \
     && [[ -n "$verdict" && "$verdict" != none && "$verdict" != null ]]; then
    gate_recovered=true; rc=0
  fi
  skill="$(phase_skill "$name")"
  effort_req="$EFFORT_FLAG"
  if [[ -z "$effort_req" && -n "$skill" && -f "$WS/.claude/skills/$skill/SKILL.md" ]]; then
    effort_req="$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1 && /^effort:/{sub(/^effort:[[:space:]]*/,""); gsub(/["'\'' ]/,""); print; exit}' \
      "$WS/.claude/skills/$skill/SKILL.md")"
  fi

  local est_turns est_micro
  est_turns="$(printf '%s' "$est" | awk '{print $1}')"; est_micro="$(printf '%s' "$est" | awk '{print $2}')"
  jq -cn --arg name "$name" --arg label "$label" --arg sid "$sid" --arg model "$model" --arg effort "$effort_req" \
    --argjson result "$result" --argjson rf "$rf" --argjson rc "$rc" --argjson dur "$elapsed_ms" \
    --arg snap "$snap" --arg verdict "$verdict" --arg resume "$resume" --arg started "$started_iso" \
    --arg finished "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson ledger "$ledger_micro" --argjson timed_out "$timed_out" \
    --argjson killed "$killed" --argjson cap_turn "$cap_turn" --argjson est_turns "${est_turns:-0}" \
    --argjson est_micro "${est_micro:-0}" --argjson turns "$turns" --argjson tsec "$tsec" --arg priced "$prices" \
    --argjson minv_from "$((minv_before + 1))" --argjson minv_to "$minv_after" \
    --argjson ledger_from "$((ledger_before + 1))" --argjson turn_cap_hit "$turn_cap_hit" \
    --argjson gate_recovered "$gate_recovered" --argjson cli_exit "$cli_exit" \
    --arg env_gate "$env_gate" --argjson env_copied "$env_copied" --arg env_sha "$env_sha" --arg metering "$metering" '
    def u(k1; k2): ($result.usage[k1] // $result.usage[k2] // 0);
    {name: $name, label: $label, skipped: false,
     session_id: (if $sid == "" then null else $sid end),
     resumed_from: (if $resume == "" then null else $resume end),
     model_requested: $model,
     models_used: (($result.modelUsage // {}) | with_entries(.value = (.value.outputTokens // .value.output_tokens // 0))),
     effort_requested: (if $effort == "" then null else $effort end),
     tokens_in: u("input_tokens"; "inputTokens"), tokens_out: u("output_tokens"; "outputTokens"),
     cache_read_tokens: u("cache_read_input_tokens"; "cacheReadInputTokens"),
     cache_creation_tokens: u("cache_creation_input_tokens"; "cacheCreationInputTokens"),
     cost_usd: ($result.total_cost_usd // ($est_micro / 1000000)),
     cost_source: (if $result.total_cost_usd != null then "result" else "watchdog_estimate" end),
     ledger_cost_usd: ($ledger / 1000000),
     duration_ms: ($result.duration_ms // $dur), wall_ms: $dur,
     num_turns: ($result.num_turns // $est_turns), max_turns: $turns, timeout_s: $tsec,
     exit: $rc, cli_exit: $cli_exit, timed_out: $timed_out, is_error: (($result.is_error // false) or ($rc != 0)),
     result_subtype: ($result.subtype // null), turn_cap_hit: $turn_cap_hit, gate_recovered: $gate_recovered,
     refusal_fallbacks: $rf,
     modelinv_lines: {from: $minv_from, to: $minv_to},
     ledger_lines_from: $ledger_from,
     snapshot: (if $snap == "" then null else $snap end),
     verdict: (if $verdict == "null" or $verdict == "" then null else $verdict end),
     watchdog: {priced: ($priced != "null"), estimate_usd: ($est_micro / 1000000), turns_seen: $est_turns,
                killed: ($killed == 1), cap_turn: (if $killed == 1 then $cap_turn else null end)},
     metering: $metering,
     started: $started, finished: $finished}
    + (if $env_gate == "" then {} else {envelope_copied: $env_copied,
                                        envelope_sha256: (if $env_sha == "" then null else $env_sha end)} end)' >> "$PHASES_FILE"

  # --- account and decide ---
  local cost_micro
  cost_micro="$(jq -r --argjson e "${est_micro:-0}" '(.total_cost_usd // ($e / 1000000)) * 1000000 | round' <<<"$result")"
  SPENT_MICRO=$(( SPENT_MICRO + cost_micro + ledger_micro ))
  if [[ "$INTERRUPTED" -eq 1 ]]; then finish interrupted 4 "driver received a signal during $label"; fi
  if [[ "$metering" == incomplete ]]; then
    finish infrastructure_error 2 "metering_incomplete: phase $label: the stream cannot be priced (an invalid token count or a completed turn without usage)"
  fi
  if [[ "$killed" -eq 1 ]]; then CAP_PHASE="$label"; CAP_TURN="$cap_turn"; finish cap_failure 3 "watchdog stopped $label at turn $cap_turn"; fi
  if [[ "$timed_out" == false ]] && { [[ $rc -eq 143 ]] || [[ $rc -eq 137 ]] || [[ $rc -eq 129 ]] || [[ $rc -eq 130 ]]; }; then
    finish interrupted 4 "phase $label was killed from outside (exit $rc)"
  fi
  if [[ $rc -ne 0 ]]; then
    if [[ "$timed_out" == true ]]; then finish agent_error 1 "phase $label timed out after ${tsec}s"; fi
    finish agent_error 1 "phase $label exited $rc"
  fi
  if [[ $SPENT_MICRO -ge $CAP_MICRO ]]; then
    CAP_PHASE="$label"; finish cap_failure 3 "spend USD $(jq -n --argjson s "$SPENT_MICRO" '$s/1000000') reached the cap USD $MAX_RUN_USD after $label"
  fi
  write_pipeline
}

gate_verdict() {  # gate_verdict <feedback.md> → APPROVED | CHANGES_REQUIRED | none
  local f="$1" line v
  [[ -f "$f" ]] || { echo none; return 0; }
  line="$(awk '/<!-- LOA-VERDICT \{.*\} -->[[:space:]]*$/ {l=$0} END {print l}' "$f")"
  [[ -n "$line" ]] || { echo none; return 0; }
  line="${line#*<!-- LOA-VERDICT }"; line="${line% -->*}"
  v="$(jq -r '.verdict // "none"' <<<"$line" 2>/dev/null || echo none)"
  case "$v" in APPROVED|CHANGES_REQUIRED) echo "$v" ;; *) echo none ;; esac
}

record_skip() {  # record_skip <name> <label> <reason>
  jq -cn --arg name "$1" --arg label "$2" --arg why "$3" \
    '{name: $name, label: $label, skipped: true, reason: $why, session_id: null, exit: null, cost_usd: 0}' >> "$PHASES_FILE"
}

PLAN_NAMES=() PLAN_LABELS=()
while IFS=$'\t' read -r name label; do
  PLAN_NAMES+=("$name"); PLAN_LABELS+=("$label")
done < <(jq -r '.[] | [.name, .label] | @tsv' <<<"$PLAN_JSON")
[[ ${#PLAN_NAMES[@]} -gt 0 ]] || infra "the phase plan is empty"
for name in "${PLAN_NAMES[@]}"; do
  [[ -f "$PROMPTS_DIR/$name.md" ]] || infra "no phase prompt for $name"
done
# metering fails closed (C-6): every planned phase model is priced before the first launch
for name in "${PLAN_NAMES[@]}"; do
  pm="$(phase_model "$name")"; pp=ERR
  if ! pp="$(price_for "$pm")" || [[ "$pp" == ERR ]]; then
    finish infrastructure_error 2 "metering_incomplete: no valid price for model $pm (phase $name)"
  fi
done

write_pipeline
i=0
while [[ $i -lt ${#PLAN_NAMES[@]} ]]; do
  name="${PLAN_NAMES[$i]}" label="${PLAN_LABELS[$i]}"
  i=$((i + 1))
  [[ "$INTERRUPTED" -eq 1 ]] && finish interrupted 4 "driver received a signal before $label"
  if [[ "$name" == FIX && "$LAST_VERDICT" != CHANGES_REQUIRED ]]; then
    record_skip "$name" "$label" "preceding gate verdict $LAST_VERDICT"
    continue
  fi
  run_phase "$name" "$label"
done

finish completed 0
