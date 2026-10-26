#!/usr/bin/env bash
# =============================================================================
# ablation-row.sh — one runs.jsonl row per ablation run (cycle-130 FR-6, SDD §3.1, §5.8)
#
# Joins a run directory's meta/pipeline.json (pipeline-run.sh), its eval/ MODELINV
# and cost ledgers, the dissent envelopes eval/adversarial-{review,audit}.json (the
# harness copies taken when each gate ended; sandbox/grimoires/loa/a2a/sprint-1/ only
# when eval/ has none, for legacy runs — audit MEDIUM-A1), the transcripts' tool
# inputs, grade.json (Sprint 259's grader; optional) and the batch MANIFEST.json
# (optional) into one SDD §3.1 row, or validates a runs.jsonl file.
#
# The arm comes from the batch manifest's `arm_map[run_id]`, else from meta/arm,
# else from meta/pipeline.json — never from sandbox/ (DEC-0413). A manifest arm that
# disagrees with meta/arm is refused (exit 2), and so is an arm outside the grammar
# ^[a-z][a-z0-9_]{0,63}$ that execute-agent.sh and the mount library enforce (exit 2).
#
# Derived fields:
#   status          pipeline status (completed | agent_error | cap_failure | interrupted |
#                   infrastructure_error; a `running` record — driver killed — reads
#                   interrupted); grade.json `contaminated` non-null → contaminated;
#                   --status overrides (transport_error is the batch runner's call)
#   effort_effective per phase: the distinct MODELINV `payload.effort_effective` values of
#                   the rows the phase wrote (its `modelinv_lines` range), comma-joined;
#                   null when no cheval hop ran (DEC-0419)
#   degraded        true when, for any executed phase, (1) the requested model is absent
#                   from a non-empty models_used (ids compared without the Bedrock region
#                   prefix and the -vN:M suffix); another model beside the requested one (a
#                   WebFetch summariser, a built-in subagent) is telemetry, not a
#                   degradation (DEC-0545), (2) refusal_fallbacks is non-empty, (3) a MODELINV row's
#                   effort_effective differs from the effort it requested (`payload.effort`,
#                   else the phase's effort_requested), or (4) a dissent envelope's
#                   verdict_quality.status is DEGRADED or its completed voices are fewer
#                   than planned; degraded_reason lists every cause ("; "-joined)
#   voices_run      {review, audit} from the envelopes ({planned, completed, quality});
#                   null when neither envelope exists (A0, A4)
#   zone_violations {dot_claude_writes: [{phase, tool, path}]} from Write/Edit/MultiEdit/
#                   NotebookEdit tool inputs under .claude/ in transcripts/events-*.jsonl;
#                   bash_mount_refs: [{phase, excerpt}] write-shaped Bash tool_use commands
#                   naming the mount (excerpt = the first 160 characters): a redirect whose
#                   target is a mount path, or a mount path (\.claude/ | CLAUDE\.md |
#                   \.loa\.config\.yaml) plus a write-capable command at a command position
#                   (sed -i, cp, mv, rm, ln, tee, truncate, install, patch, chmod, chown,
#                   git checkout|apply|restore, yq -i, python, perl); reads (cat, ls, grep,
#                   sed -n, …) never match. A heuristic that obfuscation can evade: the
#                   authoritative after-the-fact checks are pipeline.json mount_integrity
#                   and took-effect.sh integrity_clean; mount_changed: the pipeline.json mount_integrity keys that
#                   read `changed` (claude_md, loa_config; audit LOW-A2); envelope_mismatch:
#                   the gates (review, audit) whose eval/ envelope and sandbox envelope both
#                   exist and differ byte for byte (audit MEDIUM-A1)
#   cost_usd        Σ phase cost_usd (result.total_cost_usd) + Σ phase ledger_cost_usd
#   stalls          number of phases that timed out
#   defects_missed  grade.json `recall.missed` (the seeded defect ids the review did not
#                   catch, e.g. ["d2","d5"]; [] when every defect was caught) on a
#                   review-catch row; null on a build row, with no grade.json, when
#                   `recall` is null or absent, or when `missed` is not a list of
#                   non-empty strings (row writer 1.2, bd-yz1rd), or when the list breaks
#                   an id rule below (row writer 1.3: null, every other field unchanged)
#   regressions_final_green  grade.json `regressions.final_green` (boolean: the task's
#                   own regression suite was green on the final tree); null when
#                   `regressions` is null or absent (review-catch rows, ungraded rows)
#                   or `final_green` is not a boolean (row writer 1.2, bd-m0hw7)
#   Both are optional for --validate (rows written before 1.2 lack them); when present
#   defects_missed is a list of non-empty strings or null and regressions_final_green
#   is a boolean or null. schema_version stays 1: the fields are additive and
#   ablation-report.py refuses any other schema_version.
#   defects_missed id rules (row writer 1.3; checked by --validate on a review-catch row with
#   a non-null list, and by the row program, which writes null instead of a violating list):
#   every id matches ^d[1-9][0-9]*$; the ids are unique; at most defects_seeded ids and each
#   id within d1 … d<defects_seeded> when defects_seeded is a number; defects_seeded − the
#   number of ids == defects_caught when both are numbers. --validate names the rule:
#   "defects_missed [...] violates the rule: <rule>".
#
# Row writer 1.4 fields (cycle-131 Sprint 263 Task 1.6, SDD §3.2; additive — schema_version stays 1):
#   row_writer_version  "1.4"; --validate requires every 1.4 field on a row that carries it
#   defect_catch_rate   unchanged expression: grade.json recall.recall, which grader 1.3 computes under
#                       the rule grader_rule names ("pm3_or_same_function")
#   defect_catch_rate_pm3 / defect_catch_rate_pm3_v1  recall.recall_pm3 / recall.recall_pm3_v1 (null
#                       when the grade has none: a 1.2.x grade)
#   defects_missed_pm3 / defects_missed_pm3_v1  recall.missed_pm3 / recall.missed_pm3_v1 (the id grammar,
#                       unique, at most defects_seeded, within d1 … d<defects_seeded>; else null)
#   credits_function_only  recall.credits_function_only (positions; null without it)
#   oracle_exposed_defects / oracle_exposed_unknown  grade.json's (positions; null without them)
#   grader_rule         recall.rule; "pm3" for a graded review-catch row whose grade names no rule (1.2.x);
#                       null on build and ungraded rows
#   grader_version, corpus_sha256  grade.json's (null when absent)
#   dissent_absent_reason {review, audit}  per gate that ran (a non-skipped REVIEW / AUDIT phase; null for a
#                       gate that did not run): disabled (1.4: the sandbox .loa.config.yaml sets
#                       flatline_protocol.enabled, or the gate's code_review / security_audit .enabled,
#                       false, or meta/arm-evidence.txt says dissent=false for the review gate; 1.5, bd-jszcp:
#                       the harness evidence lines only, see the 1.5 fields) > budget
#                       (envelope metadata.status budget_exceeded) > preflight (a status naming preflight, or
#                       a record-fallback whose reason names it) > error (status failed, any other
#                       record-fallback, or no envelope although the gate ran) > none (the dissent ran)
#   dissent_absent_gates  the gates whose reason is disabled, budget, preflight or error (planned absence —
#                       disabled — included; the report never excludes it)
#   config_variant      meta/arm-evidence.txt config_variant= (default shipped)
#   overlay_mode        the prefix of mount_overlay= (head | base | none; null when absent or another value)
#   oracle_open         true when the evidence says oracle_open=true, else false
#   gate_scripts_at_pr_version  the comma list of gate_scripts_at_pr_version= ([] when absent)
#
# Row writer 1.5 fields (cycle-132 Sprint 269 Task 1.7b, SDD §3.2 "Entity: rows.jsonl"; additive — schema_version
# stays 1; --validate requires every 1.5 field on a row whose row_writer_version is "1.5"):
#   bare_sessions, sessions_valid, sessions_attempted  a matched cell's k, valid and attempted session counts; null
#                       on an ordinary row
#   session_costs       a cell: [{session, status, valid, attempts, attempt_costs: [USD per attempt], cost_usd (the
#                       final attempt's)}] from meta/cell.json; null on an ordinary row
#   all_spend_usd       every dollar of every attempt: a cell, Σ attempt_costs over all sessions; an ordinary row,
#                       cost_usd + --prior-spend (the runner's earlier attempts of the trial)
#   cost_usd            a cell: Σ cost_usd of the VALID sessions (ordinary rows unchanged)
#   dollar_match        null (filled by the analysis: |cost matched − cost full| ≤ 0.25 × cost full, D-7.9)
#   recall_session1, recall_pm3_session1, precision_session1  the union grade's session-1 figures; null otherwise
#   label_set           grade.json label_set (null when absent)
#   batch_context       meta/arm-evidence.txt batch_context= (a cell: its first session's), else null
#   mount_cheval        meta/arm-evidence.txt mount_cheval= (ok | none | broken:<reason>), else null
#   registration_sha256 the batch MANIFEST.json registration_sha256, else null
#   contaminated        {phase, pattern} as before; a network_egress hit (grader 1.3.6, round 10) adds repo_named
#                       (boolean|null), host and url (string|null) from grade.json — --validate checks those types
#   took_effect         {<rule>: true|false, …} from <run-dir>/meta/took-effect.json (the took-effect.sh --json-out
#                       record run-ablation.sh writes for the run or the cell); null when took-effect did not run
#                       (no record: a smoke or override path, a timeout); a record that is empty, does not parse or
#                       is not an object (dissent DISS-003) reads {took_effect_record: false}, so a validity filter
#                       fails it rather than passing it
#   sessions_meta_unreadable  a cell: the ids of sessions whose final meta/pipeline.json is missing, does not parse or
#                       holds no BARE record ([] when none); null on an ordinary row. Validity is cell.json's alone
#                       (the runner decides it, the union grade reads the same flags; dissent DISS-C-007): such a
#                       session stays valid and counted, and only its BARE record is missing from phases[]
#   attempts            1 … 3 on a 1.5 row (the attempt limit: 2 re-runs, D-7.3); a cell, its sessions' maximum
#   dissent_absent_reason  bd-jszcp: "disabled" comes from harness-owned evidence only — meta/arm-evidence.txt
#                       dissent=false (the review gate), gates= or flatline= (both gates), the lines the mount library
#                       writes when it applies those toggles — never from the agent-writable sandbox .loa.config.yaml
# A matched CELL (--run-dir on a directory holding meta/cell.json and no meta/pipeline.json, written by
# run-ablation.sh): the row joins meta/cell.json, meta/arm, each session's final attempt
# (sessions/<s>/meta/pipeline.json, its transcripts and arm evidence) and the cell's union grade.json; phases[] are
# the k sessions' BARE records labelled BARE-s<i>; status completed when at least one session is valid (the union
# is graded), else contaminated when a session was, else infrastructure_error; degraded when sessions_valid <
# ⌈k/2⌉ (reason "sessions_valid < k/2 (<n> of <k>)") or when a VALID session's record degrades (an invalid
# session's refusal fallback is the reason it is invalid, not a degradation of the cell).
#
# Row writer 1.6 fields (cycle-133 Sprint 273 Task 2.3, SDD C-8, PRD FR-8, bd-r9abp; additive — schema_version stays 1;
# --validate requires every 1.6 field on a row whose row_writer_version is "1.6", and the 1.5 checks apply to it):
#   refusal_policy_applied  the arm's suite refusal_policy, exclude | keep | rerun-once: --refusal-policy, else the batch
#                       MANIFEST.json refusal_policy[<arm>] (run-ablation.sh records it before execution), else exclude
#   attempt             1, or 2 for the rerun-once relaunch of a refused trial (--refusal-attempt); not `attempts`, which
#                       counts transport retries and re-runs (D-7.3)
#   refusal_attempts    [] or, on attempt 2, [{attempt: 1, run_dir (basename), status, cost_usd, refusal_fallbacks:
#                       [{label, refusal_fallbacks: [{from, to, category, scope}]}]}] from --refused-attempt's
#                       meta/pipeline.json (the refused attempt, kept untouched); its spend reaches all_spend_usd through
#                       --prior-spend
#   refusal_outcome     none (no refusal fallback in the row's run) | excluded (exclude) | kept (keep) | rerun_not_run
#                       (rerun-once, the relaunch was not possible: the attempt limit) | rerun_clean | rerun_refused |
#                       rerun_failed (attempt 2: no fallback; a fallback again; transport_error, infrastructure_error or
#                       interrupted) | sessions_excluded (a matched cell with a refused session: that session is invalid,
#                       the cell is judged by its sessions_valid rule)
#   refusal_denominator the refusal policy's verdict on the row (every other exclusion rule still applies): excluded
#                       for excluded, rerun_not_run, rerun_refused and rerun_failed; included otherwise. The rules: exclude
#                       — a row with a fallback is invalid (degraded, cycle-132 behaviour) and leaves the denominator; keep
#                       — the row stays valid (its refusal fallback is not a degraded cause) and flagged, and counts;
#                       rerun-once — the second attempt's row is the cell when it has no fallback, else the cell is invalid
#                       with both attempts recorded (evals/harness/README.md § Refusal policy mirrors this)
#   refusal_flagged     true on a kept row (keep with a fallback), else false
#   metering_unmetered  true when pipeline.json says an attempt ran unmetered (reason `unmetered_attempt: <label>`, or a
#                       phase with metering unmetered_attempt; such a run is infrastructure_error, already invalid), else
#                       false — additive, not required by --validate (cycle-133 review r1 DISS-001; spend.sh counts it)
# --refusal-rate F (a mode beside --validate): per arm, rows, refused (refusal_outcome other than none, else for a row
# before 1.6 any phases[].refusal_fallbacks entry), refusal_rate = refused / rows (6 decimals) and flagged when the rate
# is above 0.2: one JSON object {threshold: 0.2, arms: {<arm>: {rows, refused, refusal_rate, flagged}}} on stdout and one
# "refusal_rate <arm> <rate> (<refused> of <rows>) FLAGGED" line per flagged arm on stderr; exit 0, 2 when unreadable.
#
# Row writer version: 1.6 (1.0 Sprint 258; 1.1 the Sprint 258 audit round 1 fields —
# envelope_mismatch, bash_mount_refs, mount_changed; 1.2 defects_missed and
# regressions_final_green, Sprint 262; 1.3 the defects_missed id rules, Sprint 262 audit;
# 1.4 the cycle-131 fields above; 1.5 the cycle-132 fields above; 1.6 the cycle-133 refusal fields above).
#
# Usage:
#   ablation-row.sh --run-dir D --task-yaml F [--grade grade.json] [--manifest MANIFEST.json]
#                   [--status S] [--attempts N] [--retry-reason R] [--prior-spend USD] [--out runs.jsonl]
#                   [--refusal-policy P] [--refusal-attempt 1|2] [--refused-attempt DIR]
#   ablation-row.sh --validate runs.jsonl [--allow-ungraded]
#   ablation-row.sh --refusal-rate runs.jsonl
#
# Options:
#   --run-dir D        the run directory (meta/, sandbox/, transcripts/, eval/)
#   --task-yaml F      the task's task.yaml (id, type)
#   --grade F          grade.json (default <run-dir>/grade.json when present; absent →
#                      every grade field null, a smoke row)
#   --manifest F       batch MANIFEST.json (arm_map, batch, fingerprint, image_digest,
#                      suite_manifest_sha256, suite_version, agy_opt_in)
#   --status S         override the derived status (one of the seven)
#   --attempts N       attempts including transport retries (default 1)
#   --retry-reason R   the retry's reason (default null)
#   --prior-spend USD  the spend of the trial's earlier attempts (default 0; all_spend_usd = cost_usd + it)
#   --out F            append the row to F (flock when available); default stdout
#   --refusal-policy P exclude | keep | rerun-once (default: the manifest's refusal_policy[<arm>], else exclude)
#   --refusal-attempt N 1 (default) or 2: the rerun-once relaunch (needs --refused-attempt)
#   --refused-attempt DIR  the refused first attempt's run dir (its meta/pipeline.json; with --refusal-attempt 2 only)
#   --validate F       check every row's fields, types and enums (the arm grammar, the
#                      four zone_violations arrays); exit 1 on the first bad row naming
#                      its line number
#   --allow-ungraded   with --validate: accept rows whose grade fields are all null
#
# Exit codes:
#   0  row written / file valid
#   1  --validate found a bad row
#   2  usage error, unreadable input, arm mismatch, or "row build failed for <run_id>"
#      (the row program aborted on an input shape it does not handle; no row written)
#
# Inputs that scale with the run (pipeline.json, MODELINV, grade.json, the manifest,
# the envelopes, the transcript write list) reach jq as files under a mktemp -d work
# directory (--slurpfile), never as argv strings, so a long run cannot hit the
# per-argument limit (MAX_ARG_STRLEN, 128 KiB on Linux). The directory is removed at exit.
#
# Tested by evals/tests/ablation-row.bats (fixture runs under
# evals/tests/fixtures/ablation-runs/).
# =============================================================================
set -euo pipefail
export LC_ALL=C

RUN_DIR="" TASK_YAML="" GRADE="" MANIFEST="" STATUS_OVERRIDE="" ATTEMPTS=1 RETRY_REASON="" OUT="" PRIOR_SPEND=0
VALIDATE="" ALLOW_UNGRADED=false REFUSAL_POLICY="" REFUSAL_ATTEMPT=1 REFUSED_ATTEMPT="" REFUSAL_RATE=""
usage() { echo "ablation-row.sh: $*" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)        RUN_DIR="${2:-}"; shift 2 ;;
    --task-yaml)      TASK_YAML="${2:-}"; shift 2 ;;
    --grade)          GRADE="${2:-}"; shift 2 ;;
    --manifest)       MANIFEST="${2:-}"; shift 2 ;;
    --status)         STATUS_OVERRIDE="${2:-}"; shift 2 ;;
    --attempts)       ATTEMPTS="${2:-}"; shift 2 ;;
    --retry-reason)   RETRY_REASON="${2:-}"; shift 2 ;;
    --prior-spend)    PRIOR_SPEND="${2:-}"; shift 2 ;;
    --out)            OUT="${2:-}"; shift 2 ;;
    --validate)       VALIDATE="${2:-}"; shift 2 ;;
    --allow-ungraded) ALLOW_UNGRADED=true; shift ;;
    --refusal-policy) REFUSAL_POLICY="${2:-}"; shift 2 ;;
    --refusal-attempt) REFUSAL_ATTEMPT="${2:-}"; shift 2 ;;
    --refused-attempt) REFUSED_ATTEMPT="${2:-}"; shift 2 ;;
    --refusal-rate)   REFUSAL_RATE="${2:-}"; shift 2 ;;
    -h|--help)        sed -n '2,/^# ====/p' "$0"; exit 0 ;;
    *) usage "unknown argument: $1" ;;
  esac
done

STATUSES='["completed","cap_failure","agent_error","transport_error","infrastructure_error","interrupted","contaminated"]'

# The defects_missed id rules (row writer 1.3, Sprint 262 audit DISS-C-001): one jq definition
# prepended to both the --validate program and the row program, so the writer never emits a list
# --validate rejects. Input: the id list (an array of strings); $s defects_seeded, $c defects_caught.
# Emits the first violated rule's name, nothing when the list is consistent.
MISSED_RULES='
  def missed_rule($s; $c):
    if any(.[]; (type != "string") or (test("^d[1-9][0-9]*$") | not)) then "id grammar ^d[1-9][0-9]*$"
    elif length != (unique | length) then "unique ids"
    elif ($s | type) == "number" and length > $s then "at most defects_seeded ids"
    elif ($s | type) == "number" and any(.[]; (.[1:] | tonumber) > $s) then "ids within d1 … d<defects_seeded>"
    elif ($s | type) == "number" and ($c | type) == "number" and ($s - length) != $c
      then "defects_seeded − ids == defects_caught"
    else empty end;
  def positions_rule($s): missed_rule($s; null);'

# --- refusal rate (row writer 1.6, SDD C-8) -------------------------------------------------------------------------
if [[ -n "$REFUSAL_RATE" ]]; then
  [[ -f "$REFUSAL_RATE" && -r "$REFUSAL_RATE" ]] || usage "cannot read $REFUSAL_RATE"
  rate_out="$(jq -s -c '
    def refused: if has("refusal_outcome") then .refusal_outcome != "none"
                 else any(.phases // [] | .[]; ((.refusal_fallbacks // []) | length) > 0) end;
    {threshold: 0.2,
     arms: (group_by(.arm) | map({key: .[0].arm,
              value: (length as $n | (map(select(refused)) | length) as $r
                      | ((($r / $n) * 1000000 | round) / 1000000) as $rate
                      | {rows: $n, refused: $r, refusal_rate: $rate, flagged: ($rate > 0.2)})}) | from_entries)}' "$REFUSAL_RATE")" \
    || usage "$REFUSAL_RATE is not a JSONL rows file"
  jq -r '.arms | to_entries[] | select(.value.flagged)
         | "ablation-row.sh: refusal_rate \(.key) \(.value.refusal_rate) (\(.value.refused) of \(.value.rows)) FLAGGED (above 0.2)"' <<<"$rate_out" >&2
  printf '%s\n' "$rate_out"
  exit 0
fi

# --- validate ----------------------------------------------------------------------
if [[ -n "$VALIDATE" ]]; then
  [[ -f "$VALIDATE" && -r "$VALIDATE" ]] || usage "cannot read $VALIDATE"
  n=0 bad=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    [[ -n "${line//[[:space:]]/}" ]] || continue
    err="$(jq -r --argjson st "$STATUSES" --argjson ungraded "$ALLOW_UNGRADED" "$MISSED_RULES"'
      def t(v; ts): (v | type) as $ty | (ts | index($ty)) != null;
      def need(k; ts): if has(k) | not then "missing field \(k)"
                       elif t(.[k]; ts) | not then "field \(k) has type \(.[k] | type), want \(ts | join("|"))"
                       else empty end;
      def num: ["number"]; def numn: ["number","null"]; def str: ["string"]; def strn: ["string","null"];
      def objn: ["object","null"]; def booln: ["boolean","null"];
      if type != "object" then "row is not a JSON object" else (.) as $row |
      [ need("schema_version"; num), need("run_id"; str), need("batch"; str), need("arm"; str),
        need("task_id"; str), need("task_type"; str), need("trial"; num), need("source_commit"; str),
        need("suite_manifest_sha256"; strn), need("suite_version"; ["number","string","null"]),
        need("host_fingerprint"; strn), need("image_digest"; strn), need("agy_opt_in"; ["boolean"]),
        need("started"; str), need("finished"; strn), need("phases"; ["array"]),
        need("voices_run"; objn), need("hidden_tests"; objn), need("hidden_test_pass_rate"; numn),
        need("defects_seeded"; numn), need("defects_caught"; numn), need("defect_catch_rate"; numn),
        need("flags"; numn), need("false_positives"; numn), need("verdict"; strn),
        need("verdict_accuracy"; booln), need("verdict_accuracy_review"; booln), need("verdict_accuracy_audit"; booln),
        need("regressions"; numn), need("diff_lines"; numn), need("files_changed"; numn),
        need("cost_usd"; num), need("wall_clock_ms"; num), need("tokens_in"; num), need("tokens_out"; num),
        need("stalls"; num), need("attempts"; num), need("retry_reason"; strn),
        need("degraded"; ["boolean"]), need("degraded_reason"; strn), need("status"; str),
        need("snapshots"; ["object"]), need("contaminated"; objn), need("zone_violations"; ["object"]) ][0]
      // (if (["feature-build","bug-fix","refactor","review-catch"] | index($row.task_type)) == null
           then "task_type \(.task_type) is not one of feature-build|bug-fix|refactor|review-catch" else empty end)
      // (if ($st | index($row.status)) == null then "status \(.status) is not one of \($st | join("|"))" else empty end)
      // (if ($row.arm | test("^[a-z][a-z0-9_]{0,63}$")) | not then "arm \(.arm) does not match the arm grammar" else empty end)
      // ([("dot_claude_writes", "bash_mount_refs", "mount_changed", "envelope_mismatch") as $k
           | select((($row.zone_violations | objects)[$k] | type) != "array") | "zone_violations.\($k) is not an array"][0])
      // (if has("defects_missed") and .defects_missed != null
             and ((.defects_missed | type) != "array"
                  or any(.defects_missed[]; (type != "string") or (length == 0)))
           then "field defects_missed has type \(.defects_missed | type), want a list of non-empty strings|null" else empty end)
      // (if .task_type == "review-catch" and (.defects_missed | type) == "array"
           then ([.defects_missed | missed_rule($row.defects_seeded; $row.defects_caught)][0]
                 | if . == null then empty else "defects_missed \($row.defects_missed | tojson) violates the rule: \(.)" end)
           else empty end)
      // (if has("regressions_final_green") and ((.regressions_final_green | type) as $ty | ["boolean","null"] | index($ty)) == null
           then "field regressions_final_green has type \(.regressions_final_green | type), want boolean|null" else empty end)
      // (if (.row_writer_version // null) != null then
            [ need("defect_catch_rate_pm3"; numn), need("defect_catch_rate_pm3_v1"; numn),
              need("defects_missed_pm3"; ["array","null"]), need("defects_missed_pm3_v1"; ["array","null"]),
              need("credits_function_only"; ["array","null"]), need("oracle_exposed_defects"; ["array","null"]),
              need("oracle_exposed_unknown"; ["array","null"]), need("dissent_absent_gates"; ["array"]),
              need("dissent_absent_reason"; ["object"]), need("grader_rule"; strn), need("grader_version"; strn),
              need("corpus_sha256"; strn), need("config_variant"; str), need("overlay_mode"; strn),
              need("oracle_open"; ["boolean"]), need("gate_scripts_at_pr_version"; ["array"]) ][0]
          else empty end)
      // ([("defects_missed_pm3", "defects_missed_pm3_v1", "credits_function_only", "oracle_exposed_defects",
            "oracle_exposed_unknown") as $k | select(has($k) and (.[$k] | type) == "array")
           | (.[$k] | positions_rule($row.defects_seeded)) as $why | "\($k) \($row[$k] | tojson) violates the rule: \($why)"][0])
      // (if has("dissent_absent_reason") and (.dissent_absent_reason | type) == "object" then
            ([.dissent_absent_reason | to_entries[] | .key as $k | .value as $v
              | select((["review","audit"] | index($k)) == null
                       or ($v != null and ((["disabled","budget","preflight","error","none"] | index($v)) == null)))
              | "dissent_absent_reason.\($k) = \($v | tojson) is not one of disabled|budget|preflight|error|none|null"][0])
          else empty end)
      // (if has("dissent_absent_gates") and (.dissent_absent_gates | type) == "array"
             and any(.dissent_absent_gates[]; (. == "review" or . == "audit") | not)
           then "dissent_absent_gates \(.dissent_absent_gates | tojson) names a gate other than review|audit" else empty end)
      // (if has("config_variant") and ((["shipped","eval"] | index($row.config_variant)) == null)
           then "config_variant \(.config_variant | tojson) is not shipped|eval" else empty end)
      // (if has("overlay_mode") and .overlay_mode != null and ((["head","base","none"] | index($row.overlay_mode)) == null)
           then "overlay_mode \(.overlay_mode | tojson) is not head|base|none|null" else empty end)
      // (if has("gate_scripts_at_pr_version") and (.gate_scripts_at_pr_version | type) == "array"
             and any(.gate_scripts_at_pr_version[]; type != "string" or length == 0)
           then "gate_scripts_at_pr_version must be a list of non-empty strings" else empty end)
      // (if ((["1.5", "1.6"] | index($row.row_writer_version // null)) != null) then
            [ need("bare_sessions"; numn), need("sessions_valid"; numn), need("sessions_attempted"; numn),
              need("session_costs"; ["array","null"]), need("all_spend_usd"; num), need("dollar_match"; booln),
              need("recall_session1"; numn), need("recall_pm3_session1"; numn), need("precision_session1"; numn),
              need("label_set"; strn), need("batch_context"; strn), need("mount_cheval"; strn),
              need("registration_sha256"; strn), need("took_effect"; objn) ][0]
          else empty end)
      // (if has("sessions_meta_unreadable") and ((.sessions_meta_unreadable | type) as $ty | ["array","null"] | index($ty)) == null
           then "field sessions_meta_unreadable has type \(.sessions_meta_unreadable | type), want array|null" else empty end)
      // (if (.contaminated | type) == "object" and (
             ((.contaminated | has("repo_named")) and ((.contaminated.repo_named | type) as $ty | ["boolean","null"] | index($ty)) == null)
             or any(("host", "url") as $k | .contaminated | select(has($k)) | .[$k] | type; . != "string" and . != "null"))
           then "contaminated.repo_named must be boolean|null and contaminated.host/url string|null" else empty end)
      // (if ((["1.5", "1.6"] | index($row.row_writer_version // null)) != null) and (.took_effect | type) == "object"
             and any(.took_effect[]; type != "boolean")
           then "took_effect values must be booleans" else empty end)
      // (if ((["1.5", "1.6"] | index($row.row_writer_version // null)) != null) and ((.attempts | type) != "number" or .attempts < 1 or .attempts > 3 or .attempts != (.attempts | floor))
           then "attempts \(.attempts | tojson) is not 1 … 3 (the attempt limit: 2 re-runs, D-7.3)" else empty end)
      // (if ((["1.5", "1.6"] | index($row.row_writer_version // null)) != null) and (.bare_sessions != null) and
             ((.bare_sessions | type) != "number" or (.sessions_valid | type) != "number" or (.sessions_attempted | type) != "number"
              or (.session_costs | type) != "array" or .sessions_valid > .sessions_attempted or .sessions_attempted > .bare_sessions
              or (.session_costs | length) != .bare_sessions)
           then "matched cell fields inconsistent: bare_sessions \(.bare_sessions | tojson), sessions_valid \(.sessions_valid | tojson), sessions_attempted \(.sessions_attempted | tojson), session_costs \(.session_costs | if type == "array" then length else . end | tojson)" else empty end)
      // (if ((["1.5", "1.6"] | index($row.row_writer_version // null)) != null) and (.registration_sha256 != null) and ((.registration_sha256 | test("^[0-9a-f]{64}$")) | not)
           then "registration_sha256 is not 64 lowercase hex" else empty end)
      // (if (.row_writer_version // null) == "1.6" then
            ([ need("refusal_policy_applied"; str), need("attempt"; num), need("refusal_attempts"; ["array"]),
               need("refusal_outcome"; str), need("refusal_denominator"; str), need("refusal_flagged"; ["boolean"]) ][0])
            // (if (["exclude","keep","rerun-once"] | index($row.refusal_policy_applied)) == null
                 then "refusal_policy_applied \(.refusal_policy_applied | tojson) is not exclude|keep|rerun-once" else empty end)
            // (if (["none","excluded","kept","rerun_not_run","rerun_clean","rerun_refused","rerun_failed","sessions_excluded"]
                    | index($row.refusal_outcome)) == null
                 then "refusal_outcome \(.refusal_outcome | tojson) is not none|excluded|kept|rerun_not_run|rerun_clean|rerun_refused|rerun_failed|sessions_excluded" else empty end)
            // (if (["included","excluded"] | index($row.refusal_denominator)) == null
                 then "refusal_denominator \(.refusal_denominator | tojson) is not included|excluded" else empty end)
            // (if (.attempt != 1 and .attempt != 2) or ((.attempt == 2) != ((.refusal_attempts | length) == 1))
                    or (.attempt == 2 and .refusal_policy_applied != "rerun-once") or (.refusal_attempts | length) > 1
                 then "attempt \(.attempt | tojson) is inconsistent with refusal_attempts (\(.refusal_attempts | length)) under \(.refusal_policy_applied)" else empty end)
            // (if ((.refusal_outcome | startswith("rerun_")) and .refusal_policy_applied != "rerun-once")
                    or ((.refusal_outcome == "rerun_clean" or .refusal_outcome == "rerun_refused" or .refusal_outcome == "rerun_failed") != (.attempt == 2))
                    or (.refusal_outcome == "excluded" and .refusal_policy_applied != "exclude")
                    or (.refusal_outcome == "kept" and .refusal_policy_applied != "keep")
                    or ((["excluded","rerun_not_run","rerun_refused","rerun_failed"] | index($row.refusal_outcome) != null)
                        != (.refusal_denominator == "excluded"))
                    or (.refusal_flagged != (.refusal_outcome == "kept"))
                 then "refusal_outcome \(.refusal_outcome) is inconsistent with refusal_policy_applied \(.refusal_policy_applied), attempt \(.attempt), refusal_denominator \(.refusal_denominator) or refusal_flagged \(.refusal_flagged)" else empty end)
          else empty end)
      // (if (.degraded == true) and (.degraded_reason == null) then "degraded without degraded_reason" else empty end)
      // (if .verdict != null and ((["APPROVED","CHANGES_REQUIRED"] | index($row.verdict)) == null)
           then "verdict \(.verdict) is not APPROVED|CHANGES_REQUIRED" else empty end)
      // ([.snapshots | to_entries[] | select((.value | type) != "string" and (.value | type) != "null")
           | "snapshots.\(.key) is not a string"][0])
      // ([.phases | to_entries[] | .key as $i | .value as $p
           | ( if ($p | type) != "object" then "phases[\($i)] is not an object" else
               ([ ($p | need("name"; str)), ($p | need("session_id"; strn)), ($p | need("model_requested"; str)),
                  ($p | need("models_used"; ["object"])), ($p | need("effort_requested"; strn)),
                  ($p | need("effort_effective"; strn)), ($p | need("tokens_in"; num)), ($p | need("tokens_out"; num)),
                  ($p | need("cache_read_tokens"; num)), ($p | need("cache_creation_tokens"; num)),
                  ($p | need("cost_usd"; num)), ($p | need("duration_ms"; num)), ($p | need("num_turns"; num)),
                  ($p | need("exit"; num)), ($p | need("refusal_fallbacks"; ["array"])) ][0]
                | if . then "phases[\($i)]: \(.)" else empty end) end )][0])
      // (if $ungraded then empty
          elif (["completed","cap_failure","agent_error","contaminated"] | index($row.status)) == null then empty
          elif .task_type == "review-catch" then
            (if (.defect_catch_rate | type) != "number" then "graded review-catch row has no defect_catch_rate (use --allow-ungraded for smoke rows)" else empty end)
          else
            (if (.hidden_tests | type) != "object" or (.hidden_test_pass_rate | type) != "number"
               then "graded build row has no hidden_tests (use --allow-ungraded for smoke rows)" else empty end)
          end)
      // empty
      end' 2>/dev/null <<<"$line")" || err="line is not valid JSON"
    if [[ -n "$err" ]]; then
      echo "ablation-row.sh: $VALIDATE:$n: $err" >&2
      exit 1
    fi
  done < "$VALIDATE"
  echo "ablation-row.sh: $VALIDATE: $n rows valid"
  exit 0
fi

# --- build a row -------------------------------------------------------------------------
[[ -n "$RUN_DIR" ]] || usage "missing --run-dir (or --validate)"
[[ -n "$TASK_YAML" ]] || usage "missing --task-yaml"
[[ -f "$TASK_YAML" ]] || usage "task yaml not found: $TASK_YAML"
PIPE="$RUN_DIR/meta/pipeline.json"
CELL=false   # a matched cell (row writer 1.5): meta/cell.json, no meta/pipeline.json
[[ -f "$RUN_DIR/meta/cell.json" && ! -f "$PIPE" ]] && CELL=true
if [[ "$CELL" != true ]]; then
  [[ -f "$PIPE" ]] || usage "no meta/pipeline.json under $RUN_DIR"
  jq -e 'type == "object"' "$PIPE" >/dev/null 2>&1 || usage "meta/pipeline.json does not parse"
fi
[[ "$ATTEMPTS" =~ ^[0-9]+$ ]] || usage "--attempts must be an integer"
[[ "$PRIOR_SPEND" =~ ^[0-9]+(\.[0-9]+)?$ ]] || usage "--prior-spend must be an amount in USD"
case "$REFUSAL_POLICY" in ""|exclude|keep|rerun-once) ;; *) usage "--refusal-policy must be exclude, keep or rerun-once" ;; esac
case "$REFUSAL_ATTEMPT" in 1|2) ;; *) usage "--refusal-attempt must be 1 or 2" ;; esac
if [[ "$REFUSAL_ATTEMPT" == 2 ]]; then
  [[ -n "$REFUSED_ATTEMPT" && -f "$REFUSED_ATTEMPT/meta/pipeline.json" ]] || usage "--refusal-attempt 2 needs --refused-attempt DIR with meta/pipeline.json"
  [[ "$CELL" != true ]] || usage "--refusal-attempt 2 is a trial's relaunch; a matched cell has none"
else
  [[ -z "$REFUSED_ATTEMPT" ]] || usage "--refused-attempt goes with --refusal-attempt 2"
fi
if [[ -n "$STATUS_OVERRIDE" ]] && ! jq -e --arg s "$STATUS_OVERRIDE" 'index($s) != null' <<<"$STATUSES" >/dev/null; then
  usage "--status must be one of $(jq -r 'join("|")' <<<"$STATUSES")"
fi

# Every input that scales with the run reaches jq as a file (--slurpfile), never as an
# argv string: one argument is capped at MAX_ARG_STRLEN (128 KiB on Linux), and the
# MODELINV ledger of a long run passes it. Scalars stay --arg.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ablation-row.XXXXXX")" || usage "cannot create a work directory"
cleanup() { find "$WORK" -mindepth 1 -delete 2>/dev/null || true; rmdir "$WORK" 2>/dev/null || true; }
trap cleanup EXIT

[[ -n "$GRADE" ]] || { [[ -f "$RUN_DIR/grade.json" ]] && GRADE="$RUN_DIR/grade.json"; } || true
echo null > "$WORK/grade.json"
if [[ -n "$GRADE" ]]; then
  [[ -f "$GRADE" ]] || usage "grade file not found: $GRADE"
  jq -c '.' "$GRADE" > "$WORK/grade.json" || usage "grade file does not parse: $GRADE"
fi
# row writer 1.5: the took-effect record of this run (or cell), {rule: ok}; null without one
echo null > "$WORK/took.json"
if [[ -f "$RUN_DIR/meta/took-effect.json" && ! -L "$RUN_DIR/meta/took-effect.json" ]]; then
  jq -c 'if type == "object" and (.rules | type) == "array" and all(.rules[]; (.rule | type) == "string" and (.ok | type) == "boolean")
         then (reduce .rules[] as $r ({}; .[$r.rule] = $r.ok)) else {took_effect_record: false} end' "$RUN_DIR/meta/took-effect.json" > "$WORK/took.tmp" 2>/dev/null \
    && jq -e 'type == "object"' "$WORK/took.tmp" >/dev/null 2>&1 \
    && mv "$WORK/took.tmp" "$WORK/took.json" \
    || echo '{"took_effect_record": false}' > "$WORK/took.json"   # check-no-swallowed-jq: ok — an unreadable record fails the filter, never passes
fi
echo '{}' > "$WORK/manifest.json"
if [[ -n "$MANIFEST" ]]; then
  [[ -f "$MANIFEST" ]] || usage "manifest not found: $MANIFEST"
  jq -c '.' "$MANIFEST" > "$WORK/manifest.json" || usage "manifest does not parse: $MANIFEST"
fi
yq -o=json '.' "$TASK_YAML" > "$WORK/task.json" || usage "task yaml does not parse"
echo null > "$WORK/cellx.json"
if [[ "$CELL" == true ]]; then
  # the cell's record: a synthesized pipeline record (phases = the k sessions' BARE records, BARE-s<i>), the
  # cell extras, its first session's arm evidence, and the sessions' transcripts under the BARE-s<i> labels
  mkdir -p "$WORK/transcripts"
  python3 -I - "$RUN_DIR" "$WORK" <<'PY' || usage "meta/cell.json under $RUN_DIR is not a matched cell record"
import json, math, os, re, shutil, sys
cell, work = sys.argv[1], sys.argv[2]
c = json.load(open(os.path.join(cell, "meta", "cell.json"), encoding="utf-8"))
k, sess = c["k"], c["sessions"]
assert isinstance(k, int) and not isinstance(k, bool) and k >= 1 and isinstance(sess, list) and len(sess) == k
base = os.path.realpath(os.path.join(cell, "sessions"))
num = lambda v: v if isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) else 0
def tidy(x):   # 7.5 stays 7.5, 10.0 is written 10 (the shape jq writes for an integral sum)
    x = round(x, 6)
    return int(x) if float(x).is_integer() else x
phases, valid_labels, costs, starts, fins, first, evid, unreadable = [], [], [], [], [], None, "", []
all_spend = cost_valid = 0.0
attempted, max_att, statuses = 0, 1, []
for i, s in enumerate(sess, 1):
    assert isinstance(s, dict) and s.get("id") == f"s{i}"
    label, valid = f"BARE-s{i}", s.get("valid") is True
    att = s.get("attempts") if isinstance(s.get("attempts"), int) and not isinstance(s.get("attempts"), bool) else 0
    acs = [num(x) for x in (s.get("attempt_costs") or [])] if isinstance(s.get("attempt_costs"), list) else []
    attempted += 1 if att >= 1 else 0
    max_att = max(max_att, att)
    all_spend += sum(acs)
    cost_valid += num(s.get("cost_usd")) if valid else 0
    statuses.append(s.get("status"))
    costs.append({"session": s["id"], "status": s.get("status"), "valid": valid, "attempts": att,
                  "attempt_costs": acs, "cost_usd": num(s.get("cost_usd"))})
    rd = os.path.realpath(os.path.join(cell, s.get("run_dir") or ""))
    p = None
    if rd.startswith(base + os.sep) and os.path.isfile(os.path.join(rd, "meta", "pipeline.json")):
        try:
            p = json.load(open(os.path.join(rd, "meta", "pipeline.json"), encoding="utf-8"))
        except ValueError:
            p = None
    if valid:
        valid_labels.append(label)   # cell.json decides validity (the union grade reads the same flags)
    if not isinstance(p, dict):
        unreadable.append(s["id"])
        continue
    if first is None:
        first = p
        ef = os.path.join(rd, "meta", "arm-evidence.txt")
        if os.path.isfile(ef) and not os.path.islink(ef):
            evid = open(ef, encoding="utf-8", errors="replace").read()
    bare = [ph for ph in p.get("phases") or [] if isinstance(ph, dict) and ph.get("name") == "BARE"]
    if bare:
        phases.append(dict(bare[0], label=label))
    else:
        unreadable.append(s["id"])
    for t in (p.get("started"), ):
        if isinstance(t, str) and t:
            starts.append(t)
    if isinstance(p.get("finished"), str) and p["finished"]:
        fins.append(p["finished"])
    tr = os.path.join(rd, "transcripts", "events-BARE.jsonl")
    if os.path.isfile(tr) and not os.path.islink(tr):
        shutil.copyfile(tr, os.path.join(work, "transcripts", f"events-{label}.jsonl"))
n_valid = len(valid_labels)
status = "completed" if n_valid >= 1 else ("contaminated" if "contaminated" in statuses else "infrastructure_error")
first = first or {}
# the cell's run_id: cell.json names no arm (the grader reads it), so it comes from the first readable session's
# run id, <batch>-<arm>-<task>-t<n>-s<i>, without the session suffix
srid = str(first.get("run_id") or "")
pipe = {"run_id": c.get("run_id") or re.sub(r"-s[0-9]+$", "", srid), "task_id": c.get("task_id") or first.get("task_id"),
        "task_type": first.get("task_type") or "review-catch", "trial": c.get("trial") or first.get("trial") or 0,
        "source_commit": first.get("source_commit") or "", "suite_version": first.get("suite_version"),
        "fingerprint": first.get("fingerprint"), "image_digest": first.get("image_digest"),
        "executor_mode": first.get("executor_mode"), "status": status, "phases": phases,
        "started": min(starts) if starts else "", "finished": max(fins) if fins else None,
        "snapshots": {}, "mount_integrity": None, "cap_phase": None}
cx = {"bare_sessions": k, "sessions_valid": n_valid, "sessions_attempted": attempted, "session_costs": costs,
      "all_spend_usd": tidy(all_spend), "cost_usd": tidy(cost_valid), "valid_labels": valid_labels,
      "half": (k + 1) // 2, "attempts": min(max(max_att, 1), 99), "sessions_meta_unreadable": unreadable}
json.dump(pipe, open(os.path.join(work, "pipe.json"), "w"))
json.dump(cx, open(os.path.join(work, "cellx.json"), "w"))
open(os.path.join(work, "cell-evidence.txt"), "w", encoding="utf-8").write(evid)
PY
else
  jq -c '.' "$PIPE" > "$WORK/pipe.json" || usage "meta/pipeline.json does not parse"
fi
RUN_ID="$(jq -r '.run_id // ""' "$WORK/pipe.json")"

# arm: manifest arm_map > meta/arm > pipeline.json; never sandbox/
META_ARM=""
[[ -f "$RUN_DIR/meta/arm" ]] && META_ARM="$(sed -n '1p' "$RUN_DIR/meta/arm" | tr -d '[:space:]')"
MAN_ARM="$(jq -r --arg r "$RUN_ID" '.arm_map[$r] // empty' "$WORK/manifest.json")"
if [[ -n "$MAN_ARM" && -n "$META_ARM" && "$MAN_ARM" != "$META_ARM" ]]; then
  usage "arm mismatch for $RUN_ID: manifest arm_map says $MAN_ARM, meta/arm says $META_ARM"
fi
ARM="${MAN_ARM:-${META_ARM:-$(jq -r '.arm // ""' "$WORK/pipe.json")}}"
[[ -n "$ARM" ]] || usage "no arm for $RUN_ID (manifest arm_map, meta/arm, pipeline.json)"
[[ "$ARM" =~ ^[a-z][a-z0-9_]{0,63}$ ]] || usage "arm '$ARM' does not match ^[a-z][a-z0-9_]{0,63}$"

# MODELINV rows as an array with their 1-based line numbers
echo '[]' > "$WORK/minv.json"
if [[ -f "$RUN_DIR/eval/model-invoke.jsonl" ]]; then
  awk '{print NR "\t" $0}' "$RUN_DIR/eval/model-invoke.jsonl" \
    | jq -R -n -c '[inputs | split("\t") | {line: (.[0] | tonumber), row: (.[1:] | join("\t") | fromjson? // null)}
                   | select(.row != null)]' > "$WORK/minv.json"
fi

# the dissent envelopes: eval/ (copied by the harness when the gate ended) first; the
# sandbox copy (the agent's tree) only when eval/ has none (audit MEDIUM-A1)
envelope() {  # envelope <gate> → JSON or null
  local f="$RUN_DIR/eval/adversarial-$1.json"
  [[ -f "$f" ]] || f="$RUN_DIR/sandbox/grimoires/loa/a2a/sprint-1/adversarial-$1.json"
  if [[ -f "$f" ]] && jq -e 'type == "object"' "$f" >/dev/null 2>&1; then jq -c '.' "$f"; else echo null; fi
}
envelope review > "$WORK/env-review.json"
envelope audit > "$WORK/env-audit.json"
mismatch=()
for g in review audit; do
  e="$RUN_DIR/eval/adversarial-$g.json" sb="$RUN_DIR/sandbox/grimoires/loa/a2a/sprint-1/adversarial-$g.json"
  if [[ -f "$e" && -f "$sb" ]] && ! cmp -s "$e" "$sb"; then mismatch+=("$g"); fi
done
printf '%s\n' ${mismatch[@]+"${mismatch[@]}"} | jq -R -s -c 'split("\n") | map(select(length > 0))' > "$WORK/mismatch.json"

# Write/Edit tool inputs under .claude/ from every transcript
echo '[]' > "$WORK/dot.json"
shopt -s nullglob
ev_files=("$RUN_DIR"/transcripts/events-*.jsonl)
[[ "$CELL" == true ]] && ev_files=("$WORK"/transcripts/events-*.jsonl)
shopt -u nullglob
if [[ ${#ev_files[@]} -gt 0 ]]; then
  for f in "${ev_files[@]}"; do
      lab="$(basename "$f" .jsonl)"; lab="${lab#events-}"
      jq -R -c --arg ph "$lab" 'fromjson? | select(type == "object" and .type == "assistant") | .message.content[]?
        | select(type == "object" and .type == "tool_use"
                 and (.name == "Write" or .name == "Edit" or .name == "MultiEdit" or .name == "NotebookEdit"))
        | {phase: $ph, tool: .name, path: (.input.file_path // .input.notebook_path // "")}
        | select(.path | test("(^|/)\\.claude/"))' "$f" 2>/dev/null || true
    done | jq -s -c '.' > "$WORK/dot.json"
fi
# Write-shaped Bash commands toward the mount (audit LOW-A2): sed -i, cp or a redirect into
# .claude/, CLAUDE.md or .loa.config.yaml leaves no Write/Edit input. Reads of the mount are
# normal skill operation and are not listed (prong 1: a redirect to a mount path; prong 2: a
# mount path plus a write-capable command token at a command position).
echo '[]' > "$WORK/bashref.json"
if [[ ${#ev_files[@]} -gt 0 ]]; then
  for f in "${ev_files[@]}"; do
      lab="$(basename "$f" .jsonl)"; lab="${lab#events-}"
      jq -R -c --arg ph "$lab" 'fromjson? | select(type == "object" and .type == "assistant") | .message.content[]?
        | select(type == "object" and .type == "tool_use" and .name == "Bash")
        | (.input | objects | .command) | strings
        | select(test(">>?[[:space:]]*[^[:space:];&|]*(\\.claude/|CLAUDE\\.md|\\.loa\\.config\\.yaml)")
                 or (test("\\.claude/|CLAUDE\\.md|\\.loa\\.config\\.yaml")
                     and test("(^|[;&|(][[:space:]]*|\\bthen[[:space:]]+|\\bdo[[:space:]]+)(sed[[:space:]]+-[a-zA-Z]*i|cp|mv|rm|ln|tee|truncate|install|patch|chmod|chown|git[[:space:]]+(checkout|apply|restore)|yq[[:space:]]+-i|python3?|perl)\\b")))
        | {phase: $ph, excerpt: .[0:160]}' "$f" 2>/dev/null || true
    done | jq -s -c '.' > "$WORK/bashref.json"
fi

# row writer 1.4: the arm evidence lines (meta/arm-evidence.txt, key=value; a cell: its first session's).
# 1.5 (bd-jszcp): the sandbox .loa.config.yaml is no longer read — the agent can write it; the planned dissent
# absence comes from the harness-written evidence lines alone
: > "$WORK/evidence.txt"
if [[ "$CELL" == true ]]; then cp "$WORK/cell-evidence.txt" "$WORK/evidence.txt"
elif [[ -f "$RUN_DIR/meta/arm-evidence.txt" ]]; then cp "$RUN_DIR/meta/arm-evidence.txt" "$WORK/evidence.txt"; fi

# row writer 1.6: the refused first attempt of a rerun-once trial (--refused-attempt), null otherwise
echo null > "$WORK/refused.json"
if [[ "$REFUSAL_ATTEMPT" == 2 ]]; then
  jq -c --arg rd "$(basename "$REFUSED_ATTEMPT")" '{attempt: 1, run_dir: $rd, status: (.status // null),
      cost_usd: (.spent_usd // 0 | tonumber? // 0),
      refusal_fallbacks: [.phases // [] | .[] | select((.refusal_fallbacks // []) | length > 0)
                          | {label: (.label // .name // null), refusal_fallbacks}]}' "$REFUSED_ATTEMPT/meta/pipeline.json" > "$WORK/refused.json" \
    || usage "--refused-attempt meta/pipeline.json does not parse"
fi

# Each --slurpfile binds an array of the file's values; [0] is the one value.
ROW="$(jq -n -c \
  --slurpfile p_f "$WORK/pipe.json" --slurpfile task_f "$WORK/task.json" --slurpfile g_f "$WORK/grade.json" \
  --slurpfile m_f "$WORK/manifest.json" --slurpfile minv_f "$WORK/minv.json" \
  --slurpfile er_f "$WORK/env-review.json" --slurpfile ea_f "$WORK/env-audit.json" --slurpfile dot_f "$WORK/dot.json" \
  --slurpfile bash_f "$WORK/bashref.json" --slurpfile mm_f "$WORK/mismatch.json" \
  --slurpfile cx_f "$WORK/cellx.json" --rawfile ev_raw "$WORK/evidence.txt" --arg prior "$PRIOR_SPEND" --slurpfile te_f "$WORK/took.json" \
  --arg arm "$ARM" --arg status_override "$STATUS_OVERRIDE" --argjson attempts "$ATTEMPTS" \
  --arg retry_reason "$RETRY_REASON" --arg rpol_arg "$REFUSAL_POLICY" --argjson rattempt "$REFUSAL_ATTEMPT" \
  --slurpfile refx_f "$WORK/refused.json" "$MISSED_RULES"'
  def norm_model: tostring | sub("^([a-z]+\\.)?anthropic\\."; "") | sub("-v[0-9]+(:[0-9]+)?$"; "");
  # an unparseable timestamp (empty, an offset other than Z, not a string) is null, never an abort
  def ms(ts): if ts == null or ts == "" then null
              else (try (ts | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 * 1000) catch null) end;
  def obj: if type == "object" then . else {} end;
  def boolish: if type == "boolean" then . else null end;
  def voices(e): if e == null then null else
      (e.verdict_quality | obj) as $vq
      | {planned: ($vq.voices_planned // e.voices_planned // null),
         completed: ($vq.voices_succeeded // e.voices_succeeded // null),
         quality: ($vq.status // e.status // null),
         companion_planned: first((e.metadata | objects | .companion_voice | objects | .planned), null)} end;
  def evkv($k): [$ev_raw | split("\n")[] | select(startswith($k + "="))] | last
                | if . == null then null else .[($k | length) + 1:] | sub("\\s+$"; "") end;
  def poslist($v; $s): if ($v | type) == "array" and all($v[]; type == "string" and length > 0)
                          and ([$v | positions_rule($s)] | length) == 0 then $v else null end;
  $p_f[0] as $p | $task_f[0] as $task | $g_f[0] as $g | $m_f[0] as $m | $minv_f[0] as $minv
  | $cx_f[0] as $cx
  | $er_f[0] as $er | $ea_f[0] as $ea | $dot_f[0] as $dot | $bash_f[0] as $bashref | $mm_f[0] as $mismatch
  | ($p.phases // [] | map(select(.skipped != true))) as $ran
  | [ $ran[] as $ph
      | ($minv | map(select(.line >= ($ph.modelinv_lines.from // 1e18) and .line <= ($ph.modelinv_lines.to // -1)) | .row)) as $rows
      | ([$rows[] | .payload.effort_effective // .effort_effective // empty] | unique) as $eff
      | $ph + {
          effort_effective: (if ($eff | length) == 0 then null else ($eff | join(",")) end),
          voice_cost_usd: (([$rows[] | .payload.cost_micro_usd // .cost_micro_usd // 0] | add // 0) / 1000000),
          effort_mismatches: [ $rows[] | (.payload // .) as $r
                               | ($r.effort // $ph.effort_requested // null) as $want
                               | select($r.effort_effective != null and $want != null and $r.effort_effective != $want)
                               | "\($r.calling_primitive // "hop") effort \($want)->\($r.effort_effective)" ],
          # DEC-0545: a substitution (the requested model absent from a non-empty models_used)
          # degrades; an extra model beside the requested one is telemetry
          model_missing: ( ($ph.models_used // {} | objects // {}) as $mu
                           | if ($mu | length) > 0 and ($ph.model_requested | type) == "string" and $ph.model_requested != ""
                                and ([$mu | keys[] | norm_model] | any(. == ($ph.model_requested | norm_model)) | not)
                             then [$mu | keys | join(", ")] else [] end )
        } ] as $phases
  | ( [ $phases[] | select($cx == null or ((.label as $l | $cx.valid_labels | index($l)) != null))
        | .label as $l
        | .model_requested as $req
        | ( .model_missing[] | "\($l): requested \($req) absent from models_used (\(.))" ),
          ( if (.refusal_fallbacks | length) > 0 then "\($l): refusal fallback" else empty end ),
          ( .effort_mismatches[] | "\($l): MODELINV \(.)" ) ]
      + [ (["review", $er], ["audit", $ea]) | (.) as [$gate, $e] | select($e != null)
          | voices($e) as $v
          | ( if $v.quality == "DEGRADED" then "\($gate) envelope verdict_quality DEGRADED" else empty end ),
            ( if ($v.planned != null and $v.completed != null and $v.completed < $v.planned)
                then "\($gate) envelope \($v.completed) of \($v.planned) voices completed" else empty end ) ]
      + (if $cx != null and $cx.sessions_valid < $cx.half
           then ["sessions_valid < k/2 (\($cx.sessions_valid) of \($cx.bare_sessions))"] else [] end)
    ) as $why
  | (if $rpol_arg != "" then $rpol_arg else (($m.refusal_policy // {}) | objects | .[$arm]) // "exclude" end) as $rpol
  | (if $rpol == "keep" and $cx == null then ($why | map(select(endswith(": refusal fallback") | not))) else $why end) as $why
  | ($p.status // "infrastructure_error" | if . == "running" then "interrupted" else . end) as $pst
  | (if $status_override != "" then $status_override
     elif ($g != null and ($g.contaminated // null) != null) then "contaminated"
     else $pst end) as $status
  | ([$phases[] | select((.refusal_fallbacks // []) | length > 0)] | length > 0) as $fb   # a cell: any session
  | (if $cx != null then (if $fb then "sessions_excluded" else "none" end)
     elif $rattempt == 2 then (if $fb then "rerun_refused"
                               elif (["transport_error","infrastructure_error","interrupted"] | index($status)) != null then "rerun_failed"
                               else "rerun_clean" end)
     elif ($fb | not) then "none"
     elif $rpol == "exclude" then "excluded" elif $rpol == "keep" then "kept" else "rerun_not_run" end) as $rout
  | ($g.hidden_tests // null | if type == "object" then {passed: (.passed // 0), total: (.total // 0)} else null end) as $ht
  | ($g.recall // null) as $rc
  | (if $rc == null then null else ($rc.defects_seeded // $rc.seeded // $rc.total // null) end) as $seeded
  | (if $rc == null then null else ($rc.defects_caught // $rc.caught // null) end) as $caught
  | ms($p.started) as $t0 | ms($p.finished) as $t1
  | ([$ran[] | .label // .name] ) as $labels
  | (evkv("gates") != null or evkv("flatline") != null) as $both_off   # bd-jszcp: harness-written lines only
  | ($both_off or evkv("dissent") == "false") as $rev_off
  | $both_off as $aud_off
  | def reason($e; $ranq; $off):
      if ($ranq | not) then null
      elif $off then "disabled"
      elif $e == null then "error"
      else (($e.metadata // {}) | if type == "object" then . else {} end) as $md
        | (($md.status // $e.status // "") | tostring) as $st
        | (($md.recorded_by // "") | tostring) as $rb
        | if $st == "budget_exceeded" then "budget"
          elif ($st | test("preflight"; "i")) or ($rb == "record-fallback" and (($md.reason // "") | tostring | test("preflight"; "i")))
            then "preflight"
          elif $st == "failed" or $rb == "record-fallback" then "error"
          else "none" end end;
    {review: reason($er; ($labels | index("REVIEW")) != null; $rev_off),
     audit: reason($ea; ($labels | index("AUDIT")) != null; $aud_off)} as $dar
  | {
      schema_version: 1,
      run_id: ($p.run_id // ""),
      batch: ($m.batch // $m.batch_name // "unbatched"),
      arm: $arm,
      task_id: ($task.id // $p.task_id // ""),
      task_type: ($task.type // $p.task_type // ""),
      trial: ($p.trial // 0),
      source_commit: ($p.source_commit // $m.source_commit // ""),
      suite_manifest_sha256: ($m.suite_manifest_sha256 // null),
      suite_version: ($m.suite_version // $p.suite_version // $task.suite_version // null),
      host_fingerprint: ($m.fingerprint // $p.fingerprint // null),
      image_digest: (if (($p.arm_evidence // {}).runtime_image // "") != "" then ($p.image_digest // $m.image_digest // null)
                     else ($m.image_digest // $p.image_digest // null) end),   # a task-declared image (runtime.image): the digest of the image the run used
      executor_mode: ($m.executor_mode // $p.executor_mode // null),
      agy_opt_in: ($m.agy_opt_in // false),
      started: ($p.started // ""),
      finished: ($p.finished // null),
      phases: [ $phases[] | {name: (.name // .label // ""), label, session_id,
                             model_requested: (.model_requested // ""), models_used: (.models_used // {} | obj),
                             effort_requested, effort_effective,
                             tokens_in: (.tokens_in // 0), tokens_out: (.tokens_out // 0),
                             cache_read_tokens: (.cache_read_tokens // 0), cache_creation_tokens: (.cache_creation_tokens // 0),
                             cost_usd: (.cost_usd // 0), voice_cost_usd, ledger_cost_usd: (.ledger_cost_usd // 0),
                             duration_ms: (.duration_ms // 0), num_turns: (.num_turns // 0), exit: (.exit // -1),
                             timed_out: (.timed_out // false), refusal_fallbacks: (.refusal_fallbacks // []),
                             snapshot: (.snapshot // null), verdict: (.verdict // null)} ],
      voices_run: (if $er == null and $ea == null then null else {review: voices($er), audit: voices($ea)} end),
      hidden_tests: $ht,
      hidden_test_pass_rate: (if $ht == null or $ht.total == 0 then null else ($ht.passed / $ht.total) end),
      defects_seeded: $seeded,
      defects_caught: $caught,
      defect_catch_rate: (if $rc == null then null
                          else ($rc.recall // $rc.rate // $rc.defect_catch_rate
                                // (if $seeded != null and $seeded > 0 and $caught != null then $caught / $seeded else null end)) end),
      flags: ($rc.flags // $g.flags // null),
      false_positives: ($g.false_positives // null | if type == "array" then length else . end),
      verdict: ($g.verdict | if type == "object" then .value else . end // null),
      verdict_accuracy: ($g.verdict_accuracy | if type == "object" then .value else . end | boolish),
      verdict_accuracy_review: (if ($g.verdict_accuracy_review | type) == "boolean" then $g.verdict_accuracy_review
                                else first(($g.verdict_accuracy_per_gate | objects | .review), null) | boolish end),
      verdict_accuracy_audit: (if ($g.verdict_accuracy_audit | type) == "boolean" then $g.verdict_accuracy_audit
                               else first(($g.verdict_accuracy_per_gate | objects | .audit), null) | boolish end),
      regressions: ($g.regressions // null | if type == "object" then ((.newly_failing // []) | length)
                                            elif type == "array" then length else . end),
      defects_missed: (if ($task.type // $p.task_type // "") != "review-catch" or $rc == null then null
                       else first(($rc | objects | .missed), null) as $ms
                       | if ($ms | type) == "array" and all($ms[]; type == "string" and length > 0)
                            and ([$ms | missed_rule($seeded; $caught)] | length) == 0 then $ms
                         else null end end),
      regressions_final_green: first(($g.regressions | objects | .final_green | boolish), null),
      row_writer_version: "1.6",
      refusal_policy_applied: $rpol,
      attempt: $rattempt,
      refusal_attempts: (if $refx_f[0] == null then [] else [$refx_f[0]] end),
      refusal_outcome: $rout,
      refusal_denominator: (if (["excluded","rerun_not_run","rerun_refused","rerun_failed"] | index($rout)) != null
                            then "excluded" else "included" end),
      refusal_flagged: ($rout == "kept"),
      metering_unmetered: (((($p.reason // "") | tostring) | startswith("unmetered_attempt"))
                           or ([($p.phases // [])[]? | objects | .metering] | index("unmetered_attempt") != null)),
      defect_catch_rate_pm3: (if $rc == null then null else ($rc.recall_pm3 // null) end),
      defect_catch_rate_pm3_v1: (if $rc == null then null else ($rc.recall_pm3_v1 // null) end),
      defects_missed_pm3: (if $rc == null then null else poslist($rc.missed_pm3; $seeded) end),
      defects_missed_pm3_v1: (if $rc == null then null else poslist($rc.missed_pm3_v1; $seeded) end),
      credits_function_only: (if $rc == null then null else poslist($rc.credits_function_only; $seeded) end),
      oracle_exposed_defects: (if $g == null then null else poslist($g.oracle_exposed_defects; $seeded) end),
      oracle_exposed_unknown: (if $g == null then null else poslist($g.oracle_exposed_unknown; $seeded) end),
      grader_rule: (if ($task.type // $p.task_type // "") != "review-catch" or $rc == null then null
                    else ($rc.rule // "pm3") end),
      grader_version: (if $g == null then null else ($g.grader_version // null | if type == "string" then . else null end) end),
      corpus_sha256: (if $g == null then null else ($g.corpus_sha256 // null | if type == "string" then . else null end) end),
      dissent_absent_reason: $dar,
      dissent_absent_gates: [ ("review", "audit") as $k | select(($dar[$k] // "none") != "none") | $k ],
      config_variant: (evkv("config_variant") as $v | if $v == "eval" then "eval" else "shipped" end),
      overlay_mode: (evkv("mount_overlay") as $v | if $v == null then null
                     else ($v | capture("^(?<m>head|base|none)") // {m: null} | .m) end),
      oracle_open: (evkv("oracle_open") == "true"),
      gate_scripts_at_pr_version: (evkv("gate_scripts_at_pr_version") as $v
                                   | if $v == null or $v == "" then [] else [$v | split(",")[] | select(length > 0)] end),
      bare_sessions: ($cx.bare_sessions // null),
      sessions_valid: (if $cx == null then null else $cx.sessions_valid end),
      sessions_attempted: (if $cx == null then null else $cx.sessions_attempted end),
      session_costs: (if $cx == null then null else $cx.session_costs end),
      sessions_meta_unreadable: (if $cx == null then null else $cx.sessions_meta_unreadable end),
      all_spend_usd: (if $cx != null then $cx.all_spend_usd
                      else (([$phases[] | (.cost_usd // 0) + (.ledger_cost_usd // 0)] | add // 0) + ($prior | tonumber)) end),
      dollar_match: null,
      recall_session1: (if $g == null then null else ($g.recall_session1 // null | if type == "number" then . else null end) end),
      recall_pm3_session1: (if $g == null then null else ($g.recall_pm3_session1 // null | if type == "number" then . else null end) end),
      precision_session1: (if $g == null then null else ($g.precision_session1 // null | if type == "number" then . else null end) end),
      label_set: (if $g == null then null else ($g.label_set // null | if type == "string" then . else null end) end),
      batch_context: evkv("batch_context"),
      mount_cheval: evkv("mount_cheval"),
      registration_sha256: ($m.registration_sha256 // null | if type == "string" then . else null end),
      took_effect: $te_f[0],
      diff_lines: ($g.diff_lines // null),
      files_changed: ($g.files_changed // null),
      cost_usd: (if $cx != null then $cx.cost_usd else ([$phases[] | (.cost_usd // 0) + (.ledger_cost_usd // 0)] | add // 0) end),
      wall_clock_ms: (if $t0 != null and $t1 != null then ($t1 - $t0)
                      else ([$phases[] | .wall_ms // .duration_ms // 0] | add // 0) end),
      tokens_in: ([$phases[] | .tokens_in // 0] | add // 0),
      tokens_out: ([$phases[] | .tokens_out // 0] | add // 0),
      stalls: ([$phases[] | select(.timed_out == true)] | length),
      attempts: (if $cx != null then $cx.attempts else $attempts end),
      retry_reason: (if $retry_reason == "" then null else $retry_reason end),
      degraded: (($why | length) > 0),
      degraded_reason: (if ($why | length) == 0 then null else ($why | join("; ")) end),
      status: $status,
      cap_phase: ($p.cap_phase // null),
      snapshots: {implement: ($p.snapshots.implement // null), fix1: ($p.snapshots.fix1 // null), fix2: ($p.snapshots.fix2 // null)},
      contaminated: ($g.contaminated // null | if type == "object" then {phase: (.phase // null), pattern: (.pattern // null)}
                       + (if .pattern == "network_egress" then {repo_named: (.repo_named | if type == "boolean" then . else null end),   # not `// null`: false must survive
                            host: (.host // null | if type == "string" then . else null end),
                            url: (.url // null | if type == "string" then .[0:200] else null end)} else {} end)
                     else null end),
      zone_violations: {dot_claude_writes: $dot, bash_mount_refs: $bashref,
                        mount_changed: [($p.mount_integrity | obj) | to_entries[] | select(.value == "changed") | .key],
                        envelope_mismatch: $mismatch}
    }')" || usage "row build failed for $RUN_ID"

if [[ -n "$OUT" ]]; then
  mkdir -p "$(dirname "$OUT")"
  if command -v flock >/dev/null 2>&1; then
    { flock -x 9; printf '%s\n' "$ROW" >> "$OUT"; } 9>>"$OUT.lock"
  else
    printf '%s\n' "$ROW" >> "$OUT"
  fi
else
  printf '%s\n' "$ROW"
fi
