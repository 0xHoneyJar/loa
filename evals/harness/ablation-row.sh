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
# Row writer version: 1.3 (1.0 Sprint 258; 1.1 the Sprint 258 audit round 1 fields —
# envelope_mismatch, bash_mount_refs, mount_changed; 1.2 defects_missed and
# regressions_final_green, Sprint 262; 1.3 the defects_missed id rules, Sprint 262 audit).
#
# Usage:
#   ablation-row.sh --run-dir D --task-yaml F [--grade grade.json] [--manifest MANIFEST.json]
#                   [--status S] [--attempts N] [--retry-reason R] [--out runs.jsonl]
#   ablation-row.sh --validate runs.jsonl [--allow-ungraded]
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
#   --out F            append the row to F (flock when available); default stdout
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

RUN_DIR="" TASK_YAML="" GRADE="" MANIFEST="" STATUS_OVERRIDE="" ATTEMPTS=1 RETRY_REASON="" OUT=""
VALIDATE="" ALLOW_UNGRADED=false
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
    --out)            OUT="${2:-}"; shift 2 ;;
    --validate)       VALIDATE="${2:-}"; shift 2 ;;
    --allow-ungraded) ALLOW_UNGRADED=true; shift ;;
    -h|--help)        sed -n '2,108p' "$0"; exit 0 ;;
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
    else empty end;'

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
[[ -f "$PIPE" ]] || usage "no meta/pipeline.json under $RUN_DIR"
jq -e 'type == "object"' "$PIPE" >/dev/null 2>&1 || usage "meta/pipeline.json does not parse"
[[ "$ATTEMPTS" =~ ^[0-9]+$ ]] || usage "--attempts must be an integer"
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
echo '{}' > "$WORK/manifest.json"
if [[ -n "$MANIFEST" ]]; then
  [[ -f "$MANIFEST" ]] || usage "manifest not found: $MANIFEST"
  jq -c '.' "$MANIFEST" > "$WORK/manifest.json" || usage "manifest does not parse: $MANIFEST"
fi
yq -o=json '.' "$TASK_YAML" > "$WORK/task.json" || usage "task yaml does not parse"
jq -c '.' "$PIPE" > "$WORK/pipe.json" || usage "meta/pipeline.json does not parse"
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

# Each --slurpfile binds an array of the file's values; [0] is the one value.
ROW="$(jq -n -c \
  --slurpfile p_f "$WORK/pipe.json" --slurpfile task_f "$WORK/task.json" --slurpfile g_f "$WORK/grade.json" \
  --slurpfile m_f "$WORK/manifest.json" --slurpfile minv_f "$WORK/minv.json" \
  --slurpfile er_f "$WORK/env-review.json" --slurpfile ea_f "$WORK/env-audit.json" --slurpfile dot_f "$WORK/dot.json" \
  --slurpfile bash_f "$WORK/bashref.json" --slurpfile mm_f "$WORK/mismatch.json" \
  --arg arm "$ARM" --arg status_override "$STATUS_OVERRIDE" --argjson attempts "$ATTEMPTS" \
  --arg retry_reason "$RETRY_REASON" "$MISSED_RULES"'
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
  $p_f[0] as $p | $task_f[0] as $task | $g_f[0] as $g | $m_f[0] as $m | $minv_f[0] as $minv
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
  | ( [ $phases[] | .label as $l
        | .model_requested as $req
        | ( .model_missing[] | "\($l): requested \($req) absent from models_used (\(.))" ),
          ( if (.refusal_fallbacks | length) > 0 then "\($l): refusal fallback" else empty end ),
          ( .effort_mismatches[] | "\($l): MODELINV \(.)" ) ]
      + [ (["review", $er], ["audit", $ea]) | (.) as [$gate, $e] | select($e != null)
          | voices($e) as $v
          | ( if $v.quality == "DEGRADED" then "\($gate) envelope verdict_quality DEGRADED" else empty end ),
            ( if ($v.planned != null and $v.completed != null and $v.completed < $v.planned)
                then "\($gate) envelope \($v.completed) of \($v.planned) voices completed" else empty end ) ]
    ) as $why
  | ($p.status // "infrastructure_error" | if . == "running" then "interrupted" else . end) as $pst
  | (if $status_override != "" then $status_override
     elif ($g != null and ($g.contaminated // null) != null) then "contaminated"
     else $pst end) as $status
  | ($g.hidden_tests // null | if type == "object" then {passed: (.passed // 0), total: (.total // 0)} else null end) as $ht
  | ($g.recall // null) as $rc
  | (if $rc == null then null else ($rc.defects_seeded // $rc.seeded // $rc.total // null) end) as $seeded
  | (if $rc == null then null else ($rc.defects_caught // $rc.caught // null) end) as $caught
  | ms($p.started) as $t0 | ms($p.finished) as $t1
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
      image_digest: ($m.image_digest // $p.image_digest // null),
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
      diff_lines: ($g.diff_lines // null),
      files_changed: ($g.files_changed // null),
      cost_usd: ([$phases[] | (.cost_usd // 0) + (.ledger_cost_usd // 0)] | add // 0),
      wall_clock_ms: (if $t0 != null and $t1 != null then ($t1 - $t0)
                      else ([$phases[] | .wall_ms // .duration_ms // 0] | add // 0) end),
      tokens_in: ([$phases[] | .tokens_in // 0] | add // 0),
      tokens_out: ([$phases[] | .tokens_out // 0] | add // 0),
      stalls: ([$phases[] | select(.timed_out == true)] | length),
      attempts: $attempts,
      retry_reason: (if $retry_reason == "" then null else $retry_reason end),
      degraded: (($why | length) > 0),
      degraded_reason: (if ($why | length) == 0 then null else ($why | join("; ")) end),
      status: $status,
      cap_phase: ($p.cap_phase // null),
      snapshots: {implement: ($p.snapshots.implement // null), fix1: ($p.snapshots.fix1 // null), fix2: ($p.snapshots.fix2 // null)},
      contaminated: ($g.contaminated // null | if type == "object" then {phase: (.phase // null), pattern: (.pattern // null)} else null end),
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
