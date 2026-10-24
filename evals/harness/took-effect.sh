#!/usr/bin/env bash
# =============================================================================
# took-effect.sh — prove an arm's configuration took effect, from run artefacts
# (cycle-130 FR-3/FR-7, SDD §1.4 D-4.2, §5.10; DEC-0418)
#
# Evaluates the rule ids the suite file lists under the arm's `took_effect` against
# one run directory written by pipeline-run.sh (or every run under --batch-dir).
# Evidence is read from what the run produced — meta/pipeline.json, the
# meta/phase-<label>.argv.json captures (argv + environment), eval/model-invoke.jsonl,
# the dissent envelopes and the sandbox tree — never from what the agent said.
#
# Rules:
#   no_dot_claude              sandbox has no .claude/ and no CLAUDE.md
#   no_system_prompt           no argv carries --append-system-prompt-file
#   no_audit_rows              no sandbox/.run/audit.jsonl (no hook ran)
#   all_phases_present         the phase records equal the arm's phase set for the task
#                              type (skipped FIX rounds count as records); a run that
#                              stopped early (cap_failure, agent_error, interrupted)
#                              passes when its records are a prefix of the set
#   no_plan_phase              no PLAN record
#   one_voice_planned          both envelopes (review, audit) say companion_voice.planned false
#                              (eval/adversarial-<gate>.json, else the sandbox copy)
#   no_gate_phases             no REVIEW, AUDIT or FIX record
#   enforce_env_false          every captured phase env has LOA_ADVERSARIAL_REVIEW_ENFORCE=false
#   no_flatline_rows           no eval/ MODELINV row whose calling_primitive starts with
#                              flatline, and sandbox/grimoires/loa/sprint.md exists
#   implementer_single_session one non-null session_id across the executed PLAN, IMPLEMENT
#                              and FIX records, and every continuation's argv resumes it
#   gates_separate_sessions    REVIEW and AUDIT session ids are non-null, distinct from
#                              each other and from every implementer session id
#   effort_flag_medium         every argv carries --effort medium
#   skill_effort_stripped      no sandbox/.claude/skills/*/SKILL.md frontmatter has an ^effort:
#                              line (the block between the first two `---` lines; body lines
#                              are not frontmatter)
#   integrity_clean            arm_evidence.manifest_sha256 is present and every entry of
#                              sandbox/.claude/checksums.json hashes to its recorded value
#                              (Python hashlib walk); a loa_mount: false arm passes with
#                              "no mount"; a home-scope run (cycle-133 C-10) reads meta/home-integrity.json
#                              instead (the driver checks the HOME framework before it deletes the HOME):
#                              files > 0, 0 tampered, 0 missing, its manifest_sha256 = the evidence's
#   applicability_refused      a refusal record (meta/refused.json) names this arm and a task
#                              type outside its task_types; a run that was not refused passes
#                              when its task type is inside task_types (and fails otherwise)
#   oracle_closed              (cycle-131 FR-1, D-1.2) the closed mount held for the whole run.
#                              Inputs: the mode, the pre-run overlay_sha256 lines, base_commit and
#                              copy_source from meta/arm-evidence.txt (never the sandbox); the PR
#                              fixture from --task-yaml's review_catch.fixture resolved as the
#                              grader does (task dir, suite root, repository root,
#                              evals/fixtures/), else the evidence's overlay_fixture, never a path
#                              inside the run dir; the pinned versions from git at
#                              pipeline.json source_commit in --source-repo, else the evidence's
#                              overlay_source_tree, else this repository. FAIL when copy_source is
#                              not source_commit, else on the first violated clause and path:
#                              (a) every answer-bearing path under the mount is the mode's fixture
#                                  version (pr/head/ or pr/base/; `git show <head_commit>:X` for a
#                                  fix-commit path outside the PR) or absent where the mode says so;
#                              (b) no regular file in the sandbox outside pr/ and .git/ is byte-equal
#                                  to a later-only pinned version (`git show <source_commit>:X`);
#                              (c) each answer path's post-run state equals its pre-run
#                                  overlay_sha256 (else mount_mutated=<path>);
#                              (d) the sandbox .git holds exactly the base commit, no remote, no
#                                  alternates, nothing unreachable (git fsck --unreachable
#                                  --no-reflogs) and no later-only pinned blob.
#                              Cycle-132 addendum 9 (KF-050; addendum 5 had .claude/adapters/ only): the
#                              answer set leaves out every path under .claude/ (the overlay keeps the whole
#                              pinned runtime); the check requires overlay_excluded=<n>:<list, capped at 20
#                              then ",…"> to equal the computed value and each excluded path to be at its
#                              pinned version, and judges (a)-(d) on the other paths.
#                              The comparison is lib/sandbox-mount.sh's (_sm_oracle_py check), the
#                              same one pipeline-run.sh's pre-launch check_mount_closed runs.
#                              A build run (no PR fixture) and a loa_mount: false run with no
#                              .claude/ pass with that evidence.
#                              Cycle-133 C-10 (FR-10), when the evidence says mount_mode=home-scope:
#                              (e) (the library's check) every surface path absent at the root, the root
#                                  .claude/ holding only the PR's changed data paths at the PR's bytes;
#                              (f) a positive read: the transcript parser (transcript_schema
#                                  claude-stream-json/2.1.299, parser read-coverage/1) joins the Read results
#                                  per path (the "<n><TAB>" or "<n>→" gutter stripped, offset/limit windows
#                                  concatenated across phases, <system-reminder> blocks dropped, an errored
#                                  Read ignored); a changed .claude/ file with PR head bytes counts as read
#                                  when a Read of <path> or pr/head/<path> returned only the PR's lines (two
#                                  reads disagreeing on a line void it) covering >= 60 % of them, or the whole
#                                  file; Grep never counts (grep_only lists what it saw). pr_bytes_read must be
#                                  non-empty when the PR changes a .claude/ file, and cover every changed file
#                                  the review cites as <path>:<n>, head/<path>:<n> or pr/head/<path>:<n> in
#                                  sandbox/review.md or grimoires/loa/a2a/*/{engineer,auditor-sprint}-feedback*.md.
#                                  A Read, Bash or Grep result carrying a later-only line of a changed path's
#                                  pinned version (pinned at source_commit, >= 8 characters stripped, in
#                                  neither fixture side) FAILs as pinned_bytes_read (the HOME framework copy is
#                                  readable; reading it reopens the oracle). Evidence pr_bytes_read=[…],
#                                  cited=[…], grep_only=[…], pinned_bytes_read=[…].
#                              (g) nothing of the PR's executable surface loaded or ran: a process capture
#                                  meta/ps-<label>.txt per executed phase with at least one sample ("# sample" header lines, then
#                                  "<pid> <ppid> <args>"); no process and no Bash tool command executes a path
#                                  under the root .claude/ or pr/{head,base}/.claude/ (the command word, a
#                                  sourced file, an interpreter's script, bats/pytest files; sh -c and eval
#                                  bodies followed; a lower bound: a copy run from elsewhere is not seen); the
#                                  init event lists no MCP server outside home_mcp_servers, no plugin whose path
#                                  is in the workspace, and no skill, command, agent or output style name the
#                                  PR adds that the pin lacks; per transcript the hook_started count of each
#                                  event is within home_hook_counts=<event>:<n>,… (required evidence: the
#                                  mount declares the pinned user settings' hooks; 2.1.299 names no hook
#                                  command); no "Base directory for this skill:" under the workspace; and for
#                                  meta/canaries.tsv (optional: item, path, name, effect relative to the run
#                                  dir, token) no effect file exists and no token appears in a process sample
#                                  or a hook_response, and no canary name appears in init.

#   oracle_open_recorded       arm_evidence has mount_overlay=none and oracle_open=true (the
#                              eval-only open-mount arm; replaces oracle_closed there)
#   bare_model_fable           the BARE record's models_used has exactly one key starting
#                              global.anthropic.claude-fable and none starting
#                              global.anthropic.claude-opus, and effort_requested is high
#   review_only_phases         the phase records are exactly [REVIEW] and
#                              sandbox/grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md is absent
#   no_review_dissent_envelope no review envelope (eval/adversarial-review.json, nor the sandbox
#                              copy), the sandbox .loa.config.yaml has
#                              flatline_protocol.code_review.enabled false, and the audit envelope
#                              exists with verdict_quality.voices_succeeded >= 1
#   dissent_present            (cycle-132 PREREGISTRATION §12 addendum 2) every executed gate phase (a non-skipped
#                              REVIEW record, and AUDIT when it ran) has its dissent envelope at the harness copy
#                              eval/adversarial-<gate>.json (never the agent-writable sandbox copy) with
#                              verdict_quality.voices_succeeded >= 1 (or metadata.verdict_quality) and a status
#                              (metadata.status, else status) that is not budget_exceeded and names no refusal; a
#                              run with no gate phase FAILs (the rule is listed on arms whose gates are the task)
#   mount_cheval_ok            (cycle-132 bd-56nn6) arm_evidence has mount_cheval=ok: pipeline-run.sh's
#                              pre-launch probe imported the mounted loa_cheval (KF-050); listed on every
#                              mounted arm whose gates run a dissent
#   bare_sessions_matched      (cycle-132 FR-3, SDD D-3.1, D-7.3) on a matched CELL directory (one holding
#                              meta/cell.json, written by run-ablation.sh): k (cell.json k) equals the task's
#                              review_catch.bare_sessions_matched (an arm with bare_model: fable reads
#                              review_catch.bare_sessions_matched_fable when present; --task-yaml is
#                              required), cell.json lists exactly k sessions s1 … sk, exactly the k first-
#                              attempt directories sessions/s1 … sessions/sk exist (no s<k+1>), and every
#                              session cell.json marks valid passes no_dot_claude, no_system_prompt,
#                              no_audit_rows and integrity_clean on its final attempt's run dir (a
#                              run_dir inside sessions/). On a session's own run dir (its parent is
#                              sessions/) the rule reads OK "session of a matched cell" — the cell
#                              rule decides; anywhere else it FAILs.
# Matched cells (cycle-132): --run-dir on a cell directory (meta/cell.json, no meta/pipeline.json; the
# arm from meta/arm) evaluates bare_sessions_matched as above and every other listed rule on each valid
# session's final run dir (OK when every valid session passes; evidence names the first that fails).
# A refusal record is evaluated on applicability_refused alone.
#
# Usage:
#   took-effect.sh --run-dir D --suite-file F [--arm ID] [--json] [--json-out F] [--task-yaml F] [--source-repo DIR]
#   took-effect.sh --batch-dir D --suite-file F [--arm ID] [--json] [--source-repo DIR]
#   --task-yaml F     the run's task (oracle_closed's fixture; run-ablation.sh passes it)
#   --source-repo DIR a git repository holding the run's source_commit (oracle_closed)
#
# Output: `arm <id>: <rule> OK|FAIL <evidence>` per rule, then `arm <id>: OK` or
# `arm <id>: FAIL (<n> of <m> rules)`; --batch-dir adds `took-effect: <runs> runs, <k> failed`.
# --json prints one object per run ({run_dir, arm, ok, rules: [{rule, ok, evidence}]}).
# --json-out F (cycle-132, --run-dir only) also writes that object to F (the text output is unchanged);
# run-ablation.sh writes <run>/meta/took-effect.json with it, the record ablation-row.sh 1.5 rows as took_effect.
#
# Exit codes:
#   0  every rule OK
#   1  any rule FAIL
#   2  usage error (missing files, unknown arm)
#
# Tested by evals/tests/took-effect.bats (fixture runs under
# evals/tests/fixtures/ablation-runs/, and cycle-131 runs built in the test with the real
# mount library), evals/tests/pipeline-run.bats (oracle_closed on a real-library run) and
# evals/tests/sandbox-mount-home-scope.bats (clauses (e)-(g) on home-scope runs).
# =============================================================================
set -euo pipefail
export LC_ALL=C

# Hashing is Python hashlib: no harness script sources .claude/ code (eval.yml
# "Validate grader trust boundary").

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUN_DIR="" BATCH_DIR="" SUITE_FILE="" ARM_OPT="" JSON=false TASK_YAML_OPT="" SOURCE_REPO_OPT="" JSON_OUT=""
usage() { echo "took-effect.sh: $*" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)    RUN_DIR="${2:-}"; shift 2 ;;
    --batch-dir)  BATCH_DIR="${2:-}"; shift 2 ;;
    --suite-file) SUITE_FILE="${2:-}"; shift 2 ;;
    --arm)        ARM_OPT="${2:-}"; shift 2 ;;
    --json)       JSON=true; shift ;;
    --json-out)   JSON_OUT="${2:-}"; [[ -n "$JSON_OUT" ]] || usage "--json-out needs a file"; shift 2 ;;
    --task-yaml)  TASK_YAML_OPT="${2:-}"; shift 2 ;;
    --source-repo) SOURCE_REPO_OPT="${2:-}"; shift 2 ;;
    -h|--help)    sed -n "2,$(awk 'NR > 2 && /^# =====/ {print NR - 1; exit}' "$0")p" "$0"; exit 0 ;;
    *) usage "unknown argument: $1" ;;
  esac
done
[[ -n "$SUITE_FILE" && -f "$SUITE_FILE" ]] || usage "missing or unreadable --suite-file"
[[ -n "$RUN_DIR" || -n "$BATCH_DIR" ]] || usage "one of --run-dir or --batch-dir is required"
[[ -z "$RUN_DIR" || -z "$BATCH_DIR" ]] || usage "--run-dir and --batch-dir are exclusive"
SUITE_JSON="$(yq -o=json '.' "$SUITE_FILE")" || usage "suite file does not parse"
[[ -z "$TASK_YAML_OPT" || -f "$TASK_YAML_OPT" ]] || usage "task yaml not found: $TASK_YAML_OPT"
[[ -z "$TASK_YAML_OPT" || -z "$BATCH_DIR" ]] || usage "--task-yaml names one run's task (use it with --run-dir)"
[[ -z "$JSON_OUT" || -z "$BATCH_DIR" ]] || usage "--json-out writes one run's record (use it with --run-dir)"
[[ -z "$SOURCE_REPO_OPT" || -d "$SOURCE_REPO_OPT" ]] || usage "source repo not found: $SOURCE_REPO_OPT"

# the closed-mount comparison (oracle_closed) is the mount library's; a literal in-tree path
# (eval.yml trust boundary: no variable on the source line, no .claude/ code)
pushd "$SCRIPT_DIR" >/dev/null
# shellcheck source=lib/sandbox-mount.sh
source ./lib/sandbox-mount.sh
popd >/dev/null

# ---- rule helpers: each sets EVID and returns 0 (OK) / 1 (FAIL) --------------------
EVID=""
argv_files() { local f; for f in "$R/meta"/phase-*.argv.json; do [[ -f "$f" ]] && printf '%s\n' "$f"; done; return 0; }
envelope() {  # envelope <gate> → path or empty; eval/ (the harness copy taken when the gate
              # ended) first, the sandbox copy only when eval/ has none (audit MEDIUM-A1)
  local f="$R/eval/adversarial-$1.json"
  [[ -f "$f" ]] || f="$R/sandbox/grimoires/loa/a2a/sprint-1/adversarial-$1.json"
  [[ -f "$f" ]] && printf '%s' "$f"; return 0
}

expected_labels() {  # the arm's phase set for this run's task type (pipeline-run.sh's plan)
  local type kind
  type="$(jq -r '.task_type // ""' "$R/meta/pipeline.json")"
  if [[ "$type" == review-catch ]]; then kind=review-catch; else kind=build; fi
  jq -r -n --argjson arm "$ARM_DEF" --argjson suite "$SUITE_JSON" --arg kind "$kind" \
    --argjson tg "$(jq -c '.arm_toggles // {}' "$R/meta/pipeline.json")" '
    (if $kind == "review-catch" then ["REVIEW","AUDIT"] else ["PLAN","IMPLEMENT","REVIEW","FIX","AUDIT","FIX"] end) as $dflt
    | ($arm.phases // $suite.phase_sets[$kind] // $dflt) as $p0
    | (if ($tg.loa_mount == false) then ["BARE"] else $p0 end) as $p1
    | (if ($tg.sprint_plan == false) then ($p1 | map(select(. != "PLAN"))) else $p1 end) as $p2
    | (if ($tg.gates == false) and ($p2 | index("IMPLEMENT")) != null then $p2[0:(($p2 | index("IMPLEMENT")) + 1)] else $p2 end) as $p3
    | reduce $p3[] as $n ({out: [], fix: 0};
        if $n == "FIX" then .fix += 1 | .out += ["FIX" + (.fix | tostring)] else .out += [$n] end)
    | .out | join(",")'
}

rule_no_dot_claude() {
  if [[ -e "$R/sandbox/.claude" || -e "$R/sandbox/CLAUDE.md" ]]; then EVID="sandbox has .claude/ or CLAUDE.md"; return 1; fi
  EVID="sandbox has no .claude/ and no CLAUDE.md"
}
rule_no_system_prompt() {
  local f n=0 hit=""
  while IFS= read -r f; do
    n=$((n + 1))
    jq -e '(.argv // []) | index("--append-system-prompt-file") != null' "$f" >/dev/null 2>&1 && hit="$hit $(basename "$f")"
  done < <(argv_files)
  [[ $n -gt 0 ]] || { EVID="no phase argv captured"; return 1; }
  [[ -z "$hit" ]] || { EVID="--append-system-prompt-file in$hit"; return 1; }
  EVID="no --append-system-prompt-file in $n argv"
}
rule_no_audit_rows() {
  [[ -e "$R/sandbox/.run/audit.jsonl" ]] && { EVID="sandbox/.run/audit.jsonl exists"; return 1; }
  EVID="no sandbox/.run/audit.jsonl"
}
rule_all_phases_present() {
  local want got st
  want="$(expected_labels)"
  got="$(jq -r '[.phases // [] | .[] | .label] | join(",")' "$R/meta/pipeline.json")"
  st="$(jq -r '.status // ""' "$R/meta/pipeline.json")"
  if [[ "$got" == "$want" ]]; then EVID="phases $got"; return 0; fi
  case "$st" in
    cap_failure|agent_error|interrupted|running)
      if [[ -n "$got" && ",$want," == ",$got,"* ]]; then EVID="phases $got (run stopped: $st; set $want)"; return 0; fi ;;
  esac
  EVID="phases ${got:-none}, want $want (status $st)"; return 1
}
rule_no_plan_phase() {
  local n; n="$(jq '[.phases // [] | .[] | select(.name == "PLAN")] | length' "$R/meta/pipeline.json")"
  [[ "$n" -eq 0 ]] || { EVID="$n PLAN record(s)"; return 1; }
  EVID="no PLAN record"
}
rule_one_voice_planned() {
  local g f v bad="" ev=""
  for g in review audit; do
    f="$(envelope "$g")"
    if [[ -z "$f" ]]; then bad="$bad $g:missing"; continue; fi
    v="$(jq -r 'if (.metadata.companion_voice | type) == "object" then .metadata.companion_voice.planned
                elif (.companion_voice | type) == "object" then .companion_voice.planned else "absent" end | tostring' "$f" 2>/dev/null || echo unreadable)"
    ev="$ev $g:planned=$v"
    [[ "$v" == false ]] || bad="$bad $g:planned=$v"
  done
  [[ -z "$bad" ]] || { EVID="companion_voice${bad}"; return 1; }
  EVID="companion_voice${ev}"
}
rule_no_gate_phases() {
  local got; got="$(jq -r '[.phases // [] | .[] | select(.name == "REVIEW" or .name == "AUDIT" or .name == "FIX") | .label] | join(",")' "$R/meta/pipeline.json")"
  [[ -z "$got" ]] || { EVID="gate records $got"; return 1; }
  EVID="no REVIEW, AUDIT or FIX record"
}
rule_enforce_env_false() {
  local f n=0 bad=""
  while IFS= read -r f; do
    n=$((n + 1))
    [[ "$(jq -r '.env.LOA_ADVERSARIAL_REVIEW_ENFORCE // "unset"' "$f")" == false ]] || bad="$bad $(basename "$f" .argv.json)"
  done < <(argv_files)
  [[ $n -gt 0 ]] || { EVID="no phase argv captured"; return 1; }
  [[ -z "$bad" ]] || { EVID="LOA_ADVERSARIAL_REVIEW_ENFORCE not false in$bad"; return 1; }
  EVID="LOA_ADVERSARIAL_REVIEW_ENFORCE=false in $n/$n phase env"
}
rule_no_flatline_rows() {
  local n=0
  if [[ -f "$R/eval/model-invoke.jsonl" ]]; then
    n="$(jq -R -n '[inputs | fromjson? | select(type == "object")
           | (.payload.calling_primitive // .calling_primitive // .agent // "") | select(test("^flatline"))] | length' \
         "$R/eval/model-invoke.jsonl")"
  fi
  [[ "$n" -eq 0 ]] || { EVID="$n flatline MODELINV row(s)"; return 1; }
  [[ -f "$R/sandbox/grimoires/loa/sprint.md" ]] || { EVID="no flatline rows but no sandbox sprint.md"; return 1; }
  EVID="no flatline MODELINV rows; sprint.md present"
}
rule_implementer_single_session() {
  local ids n sid f bad=""
  ids="$(jq -r '[.phases // [] | .[] | select(.skipped != true and (.name == "PLAN" or .name == "IMPLEMENT" or .name == "FIX")) | .session_id]' "$R/meta/pipeline.json")"
  n="$(jq 'length' <<<"$ids")"
  [[ "$n" -gt 0 ]] || { EVID="no implementer record"; return 1; }
  [[ "$(jq '[.[] | select(. == null)] | length' <<<"$ids")" -eq 0 ]] || { EVID="an implementer record has no session_id"; return 1; }
  [[ "$(jq 'unique | length' <<<"$ids")" -eq 1 ]] || { EVID="implementer session ids $(jq -r 'unique | join(",")' <<<"$ids")"; return 1; }
  sid="$(jq -r '.[0]' <<<"$ids")"
  while IFS= read -r f; do
    case "$(jq -r '.name' "$f")" in PLAN|IMPLEMENT|FIX) ;; *) continue ;; esac
    jq -e '.resume == null' "$f" >/dev/null && continue
    jq -e --arg s "$sid" '.resume == $s and ((.argv | index("--resume")) as $i | $i != null and .argv[$i + 1] == $s)' "$f" >/dev/null \
      || bad="$bad $(jq -r '.label' "$f")"
  done < <(argv_files)
  [[ -z "$bad" ]] || { EVID="continuation argv does not resume $sid:$bad"; return 1; }
  EVID="one session $sid across $n implementer record(s)"
}
rule_gates_separate_sessions() {
  local r a impl
  r="$(jq -r '[.phases // [] | .[] | select(.name == "REVIEW" and .skipped != true) | .session_id][0] // "null"' "$R/meta/pipeline.json")"
  a="$(jq -r '[.phases // [] | .[] | select(.name == "AUDIT" and .skipped != true) | .session_id][0] // "null"' "$R/meta/pipeline.json")"
  impl="$(jq -c '[.phases // [] | .[] | select(.name == "PLAN" or .name == "IMPLEMENT" or .name == "FIX") | .session_id | select(. != null)] | unique' "$R/meta/pipeline.json")"
  [[ "$r" != null && "$a" != null ]] || { EVID="gate session ids review=$r audit=$a"; return 1; }
  [[ "$r" != "$a" ]] || { EVID="REVIEW and AUDIT share session $r"; return 1; }
  if jq -e --arg r "$r" --arg a "$a" 'index($r) != null or index($a) != null' <<<"$impl" >/dev/null; then
    EVID="a gate shares an implementer session"; return 1
  fi
  EVID="review $r, audit $a, implementer $(jq -r 'join(",")' <<<"$impl")"
}
rule_effort_flag_medium() {
  local f n=0 ok=0
  while IFS= read -r f; do
    n=$((n + 1))
    jq -e '(.argv // []) | (index("--effort")) as $i | $i != null and .[$i + 1] == "medium"' "$f" >/dev/null && ok=$((ok + 1))
  done < <(argv_files)
  [[ $n -gt 0 && $ok -eq $n ]] || { EVID="--effort medium on $ok/$n phases"; return 1; }
  EVID="--effort medium on $ok/$n phases"
}
rule_skill_effort_stripped() {
  local f n=0 hit=0
  for f in "$R"/sandbox/.claude/skills/*/SKILL.md; do
    [[ -f "$f" ]] || continue
    n=$((n + 1))
    # the YAML frontmatter only (first line `---` to the next `---`); a body line may say effort:
    awk 'NR == 1 && $0 != "---" {exit} NR > 1 && $0 == "---" {exit} NR > 1 && /^effort:/ {hit = 1; exit} END {exit !hit}' "$f" \
      && hit=$((hit + 1))
  done
  [[ $n -gt 0 ]] || { EVID="no sandbox SKILL.md"; return 1; }
  [[ $hit -eq 0 ]] || { EVID="$hit/$n SKILL.md still carry effort:"; return 1; }
  EVID="skill effort lines stripped $n/$n"
}
rule_integrity_clean() {
  local man="$R/sandbox/.claude/checksums.json" msha out
  if [[ "$(jq -r '.arm_toggles.loa_mount' "$R/meta/pipeline.json")" == false ]]; then
    [[ -e "$R/sandbox/.claude" ]] && { EVID="loa_mount: false but sandbox has .claude/"; return 1; }
    EVID="no mount (loa_mount: false)"; return 0
  fi
  msha="$(jq -r '.arm_evidence.manifest_sha256 // empty' "$R/meta/pipeline.json")"
  [[ -n "$msha" && "$msha" != none ]] || { EVID="no arm_evidence.manifest_sha256"; return 1; }
  if [[ "$(evidence_line mount_mode)" == home-scope ]]; then
    # cycle-133 C-10: the manifest covers the HOME framework copy, which the driver checks before it deletes the HOME
    local hi="$R/meta/home-integrity.json" hn hb hm hs hf
    [[ -f "$hi" && ! -L "$hi" ]] || { EVID="home-scope: no meta/home-integrity.json (the HOME framework was never checked)"; return 1; }
    hn="$(jq -r '.files // 0' "$hi")"; hb="$(jq -r '.tampered // -1' "$hi")"; hm="$(jq -r '.missing // -1' "$hi")"
    hs="$(jq -r '.manifest_sha256 // ""' "$hi")"; hf="$(jq -r '.first // "-"' "$hi")"
    [[ "$hn" =~ ^[0-9]+$ && "$hn" -gt 0 ]] || { EVID="home-scope: the HOME manifest lists no files"; return 1; }
    [[ "$hs" == "$msha" ]] || { EVID="home-scope: the checked HOME manifest ${hs:0:12} is not arm_evidence.manifest_sha256 ${msha:0:12}"; return 1; }
    if [[ "$hb" != 0 || "$hm" != 0 ]]; then EVID="home-scope: $hb tampered, $hm missing of $hn ($hf)"; return 1; fi
    EVID="home-scope: $hn HOME framework entries verified at finish; manifest_sha256 ${msha:0:12}"
    return 0
  fi

  [[ -f "$man" ]] && jq -e '.files | type == "object"' "$man" >/dev/null 2>&1 || { EVID="no sandbox .claude/checksums.json files map"; return 1; }
  # one hashlib walk over every manifest entry: "<n> <tampered> <missing> <file-sha> <first problem>"
  out="$(python3 -I -c '
import hashlib, json, os, sys
root, man = sys.argv[1], sys.argv[2]
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()
files = json.load(open(man)).get("files") or {}
bad = missing = 0; first = "-"
for rel, want in sorted(files.items()):
    p = os.path.join(root, rel)
    if not os.path.isfile(p):
        missing += 1; first = first if first != "-" else "missing " + rel
    elif sha(p) != want:
        bad += 1; first = first if first != "-" else "tampered " + rel
print(len(files), bad, missing, sha(man), first)' "$R/sandbox" "$man")" || { EVID="hash walk failed"; return 1; }
  local n bad missing filesha first
  read -r n bad missing filesha first <<<"$out"
  [[ "$n" -gt 0 ]] || { EVID="manifest lists no files"; return 1; }
  if [[ "$bad" -gt 0 || "$missing" -gt 0 ]]; then EVID="$bad tampered, $missing missing of $n ($first)"; return 1; fi
  EVID="$n manifest entries verified; manifest_sha256 ${msha:0:12}"
  [[ "$filesha" == "$msha" ]] && EVID="$EVID (matches checksums.json)"
  return 0
}
rule_applicability_refused() {
  local f="$R/meta/refused.json" a t
  if [[ ! -f "$f" ]]; then
    # a run that was not refused: its task type must be one the arm declares
    t="$(jq -r '.task_type // ""' "$R/meta/pipeline.json")"
    local k=build; [[ "$t" == review-catch ]] && k=review-catch
    if jq -e --arg k "$k" --arg t "$t" '(.task_types // ["all"]) as $tt | ($tt | index("all")) or ($tt | index($k)) or ($tt | index($t))' \
         <<<"$ARM_DEF" >/dev/null; then
      EVID="applicable: $t in task_types $(jq -c '.task_types // null' <<<"$ARM_DEF") (no refusal needed)"; return 0
    fi
    EVID="ran on $t outside task_types $(jq -c '.task_types // null' <<<"$ARM_DEF") without a refusal record"; return 1
  fi
  a="$(jq -r '.arm // ""' "$f")"; t="$(jq -r '.type // ""' "$f")"
  [[ "$a" == "$ARM" && -n "$t" ]] || { EVID="refusal record names arm '$a' type '$t'"; return 1; }
  local kind=build; [[ "$t" == review-catch ]] && kind=review-catch
  if jq -e --arg k "$kind" --arg t "$t" '(.task_types // ["all"]) as $tt | ($tt | index("all")) or ($tt | index($k)) or ($tt | index($t))' \
       <<<"$ARM_DEF" >/dev/null; then
    EVID="arm task_types $(jq -c '.task_types' <<<"$ARM_DEF") include $t, yet the run was refused"; return 1
  fi
  EVID="refused $t (task_types $(jq -c '.task_types // null' <<<"$ARM_DEF"))"
}

evidence_line() {  # evidence_line <key> → the first <key>= value in meta/arm-evidence.txt
  sed -n "s/^$1=//p" "$R/meta/arm-evidence.txt" 2>/dev/null | sed -n '1p'
}
resolve_fixture() {  # the run's PR fixture (realpath), from --task-yaml or the evidence
  local rel c cand="" ty="$TASK_YAML_OPT" td
  if [[ -n "$ty" ]]; then
    rel="$(yq -r '.review_catch.fixture // ""' "$ty" 2>/dev/null || true)"
    [[ -n "$rel" && "$rel" != null ]] || return 1
    td="$(cd "$(dirname "$ty")" && pwd)"
    if [[ "$rel" == /* ]]; then cand="$rel"
    else
      for c in "$td/$rel" "$td/../../$rel" "$REPO_ROOT/$rel" "$REPO_ROOT/evals/fixtures/$rel"; do
        [[ -d "$c" ]] && { cand="$c"; break; }
      done
    fi
  else
    cand="$(evidence_line overlay_fixture)"
  fi
  [[ -n "$cand" && -d "$cand" ]] || return 1
  cand="$(cd "$cand" && pwd -P)"
  case "$cand/" in "$(cd "$R" && pwd -P)"/*) return 1 ;; esac   # never the agent-writable pr/
  printf '%s' "$cand"
}
rule_oracle_closed() {
  local evf="$R/meta/arm-evidence.txt" fx sc cs repo c out rc=0
  if [[ "$(jq -r '.task_type // ""' "$R/meta/pipeline.json")" != review-catch ]]; then
    EVID="not a review-catch run (no PR fixture to close)"; return 0
  fi
  if [[ "$(jq -r '.arm_toggles.loa_mount' "$R/meta/pipeline.json")" == false ]]; then
    [[ ! -e "$R/sandbox/.claude" ]] || { EVID="loa_mount: false but the sandbox has .claude/"; return 1; }
    EVID="no mount (loa_mount: false)"; return 0
  fi
  [[ -f "$evf" ]] || { EVID="no meta/arm-evidence.txt"; return 1; }
  [[ "$(evidence_line mount_overlay)" != none ]] || { EVID="mount_overlay=none (an open mount)"; return 1; }
  # PR #1286 F001: a fix commit the overlay could not read leaves its paths unpinned; never a closed mount
  [[ "$(evidence_line overlay_fix_commit)" != unavailable ]] || { EVID="overlay_fix_commit=unavailable (the fix paths outside the PR were never pinned)"; return 1; }
  fx="$(resolve_fixture)" || { EVID="the PR fixture does not resolve (--task-yaml or overlay_fixture evidence)"; return 1; }
  sc="$(jq -r '.source_commit // ""' "$R/meta/pipeline.json")"
  cs="$(evidence_line copy_source)"
  [[ -n "$cs" && "$cs" == "$sc" ]] || { EVID="copy_source ${cs:-<none>} is not source_commit ${sc:-<none>}"; return 1; }
  repo=""
  for c in "$SOURCE_REPO_OPT" "$(evidence_line overlay_source_tree)" "$REPO_ROOT"; do
    [[ -n "$c" && -d "$c" ]] || continue
    if git -C "$c" cat-file -e "$sc^{commit}" 2>/dev/null; then repo="$c"; break; fi
  done
  [[ -n "$repo" ]] || { EVID="source_commit $sc is in no source repository (--source-repo)"; return 1; }
  out="$(_sm_oracle_py check "$R/sandbox" "$fx" "$evf" "$repo" "$sc" 2>/dev/null)" || rc=$?
  EVID="${out:-the check failed (exit $rc)}"
  [[ $rc -eq 0 ]] || return 1
  # cycle-133 C-10: a home-scope run also proves the reviewer read the PR's bytes (f) and nothing of the PR's
  # executable surface loaded or ran (g); the clauses read the transcripts, the process samples and the evidence
  [[ "$(evidence_line mount_mode)" == home-scope ]] || return 0
  local aset fg frc=0
  aset="$(_sm_oracle_py answer-set "$fx" "$repo" home-scope 2>/dev/null)" || { EVID="$EVID; the home-scope answer set did not compute"; return 1; }
  fg="$(_te_home_scope_py "$R" "$fx" <(printf '%s\n' "$aset") "$repo" "$sc" "$evf" 2>/dev/null)" || frc=$?
  if [[ $frc -ne 0 ]]; then EVID="${fg:-clauses (f)-(g) failed (exit $frc)}"; return 1; fi
  EVID="$EVID; ${fg#ok }"
}

# _te_home_scope_py <run-dir> <fixture> <answer-set-file> <source-repo> <source-commit> <evidence-file>
# clauses (f) and (g) of oracle_closed for a home-scope run (cycle-133 C-10). Prints "ok (f) … ; (g) …" (exit 0) or
# "FAIL (<f|g>) <path|->: <detail>[ (+<n> more)]" (exit 1). See the header for the clauses.
_te_home_scope_py() {
  python3 -I - "$@" <<'PY'
import hashlib, json, math, os, re, subprocess, sys

run, fixture, setfile, repo, commit, evfile = sys.argv[1:7]
SCHEMA = "claude-stream-json/2.1.299"   # the transcript shape read here: Claude Code 2.1.299 stream-json --verbose
PARSER = "read-coverage/1"
COVER = 0.6                             # a file counts as read at >= 60 % of its lines (or all of them)
TRUNC = 2000                            # Read truncates longer lines; a truncated line counts when it is a prefix
FILE_CAP, LINE_CAP, EVENT_CAP, CMD_CAP = 4 << 20, 20000, 8 << 20, 65536
ws_host = os.path.join(run, "sandbox")
fails = []

def fail(clause, path, detail):
    fails.append((clause, path, detail))

def git(*args):
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": "/nonexistent", "LC_ALL": "C",
           "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0"}
    try:
        p = subprocess.run(["git", "--no-pager", "--literal-pathspecs", "-c", "core.fsmonitor=false", "-c", "core.quotepath=off",
                            "-C", repo] + list(args), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, env=env, timeout=120)
    except Exception:
        return None
    return p.stdout if p.returncode == 0 else None

def pinned(p):
    out = git("ls-tree", "-z", commit, "--", p)
    if not out:
        return None
    m = re.match(r"^(\d+) blob ([0-9a-f]+)\t(.*)$", out.split(b"\0")[0].decode("utf-8", "surrogateescape"), re.S)
    if not m or m.group(3) != p or m.group(1) not in ("100644", "100755"):
        return None
    return git("cat-file", "blob", m.group(2))

def regular(root, p):
    """bytes of a regular file at root/p with no symlink component (bounded), else None"""
    cur = root
    if os.path.islink(cur) or not os.path.isdir(cur):
        return None
    for c in p.split("/"):
        cur = os.path.join(cur, c)
        if os.path.islink(cur):
            return None
    if not os.path.isfile(cur):
        return None
    with open(cur, "rb") as fh:
        return fh.read(FILE_CAP)

def text_lines(b):
    return [x[:-1] if x.endswith("\r") else x for x in b.decode("utf-8", "replace").split("\n")]

def evidence(key):
    try:
        for line in open(evfile, encoding="utf-8", errors="replace"):
            if line.startswith(key + "="):
                return line.rstrip("\n")[len(key) + 1:]
    except OSError:
        pass
    return None

def jl(xs):
    return json.dumps(sorted(xs), separators=(",", ":"))

# ---- the PR's changed .claude/ files (the answer set of the mount library, home-scope) -----------------------------
labels = {}
for line in open(setfile, encoding="utf-8", errors="surrogateescape"):
    line = line.rstrip("\n")
    if "\t" in line:
        lab, p = line.split("\t", 1)
        labels[p] = lab
changed = {}          # path -> the PR's head bytes (regular files only: deleted, renamed-away, symlinked paths have none)
for p, lab in sorted(labels.items()):
    if lab in ("pr", "surface") and p.startswith(".claude/"):
        b = regular(os.path.join(fixture, "head"), p)
        if b is not None:
            changed[p] = b
later = {}            # path -> later-only lines of the pinned version (stripped, >= 8 characters, in neither PR side)
for p in sorted(labels):
    if not p.startswith(".claude/"):
        continue
    pb = pinned(p)
    if not pb:
        continue
    known = set()
    for side in ("head", "base"):
        sb = regular(os.path.join(fixture, side), p)
        if sb is not None:
            known |= set(x.strip() for x in text_lines(sb))
    lo = set(x.strip() for x in text_lines(pb) if len(x.strip()) >= 8) - known
    if lo:
        later[p] = lo

# ---- the transcripts ------------------------------------------------------------------------------------------------
def result_text(blk):
    c = blk.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(x.get("text", "") for x in c if isinstance(x, dict) and isinstance(x.get("text"), str))
    return ""

inits, hook_counts, hook_texts, user_texts, results, bash_cmds = [], {}, [], [], [], []
tdir = os.path.join(run, "transcripts")
tfiles = sorted(n for n in (os.listdir(tdir) if os.path.isdir(tdir) else []) if re.match(r"^events-[A-Za-z0-9_-]+\.jsonl$", n))
for tn in tfiles:
    cwd, uses = "/workspace", {}
    path = os.path.join(tdir, tn)
    if os.path.islink(path):
        continue
    for line in open(path, encoding="utf-8", errors="replace"):
        if len(line) > EVENT_CAP:
            continue
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if not isinstance(ev, dict):
            continue
        t = ev.get("type")
        if t == "system":
            st = ev.get("subtype")
            if st == "init":
                if isinstance(ev.get("cwd"), str) and ev["cwd"].startswith("/"):
                    cwd = os.path.normpath(ev["cwd"])
                inits.append((tn, ev, cwd))
            elif st == "hook_started":
                k = (tn, str(ev.get("hook_event") or ""))
                hook_counts[k] = hook_counts.get(k, 0) + 1
            elif st == "hook_response":
                hook_texts.append((tn, " ".join(str(ev.get(k) or "") for k in ("output", "stdout", "stderr"))))
            continue
        msg = ev.get("message")
        content = msg.get("content") if isinstance(msg, dict) else None
        if t == "user" and isinstance(content, str):
            user_texts.append((tn, content))
            continue
        if not isinstance(content, list):
            continue
        for blk in content:
            if not isinstance(blk, dict):
                continue
            bt = blk.get("type")
            if t == "user" and bt == "text" and isinstance(blk.get("text"), str):
                user_texts.append((tn, blk["text"]))
            elif t == "assistant" and bt == "tool_use" and isinstance(blk.get("input"), dict) and isinstance(blk.get("id"), str):
                uses[blk["id"]] = (blk.get("name") or "", blk["input"], cwd)
                if blk.get("name") == "Bash" and isinstance(blk["input"].get("command"), str):
                    bash_cmds.append((tn, blk["id"], blk["input"]["command"], cwd))
            elif t == "user" and bt == "tool_result" and blk.get("tool_use_id") in uses:
                name, inp, ucwd = uses.pop(blk["tool_use_id"])
                results.append((tn, name, inp, ucwd, result_text(blk), blk.get("is_error") is True))

def rel_of(p, cwd):
    if not isinstance(p, str) or not p or p.startswith("~"):
        return None
    full = os.path.normpath(p if p.startswith("/") else os.path.join(cwd, p))
    base = cwd.rstrip("/")
    if not full.startswith(base + "/"):
        return None
    return full[len(base) + 1:]

# ---- clause (f): the reviewer read the PR's bytes -------------------------------------------------------------------
GUTTER = re.compile(r"^\s*(\d+)(?:\t|→)(.*)$")
REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
EXIT_LINE = re.compile(r"\AExit code \d+\n?")
reads, read_seen, grep_seen = {}, set(), set()
for tn, name, inp, ucwd, res, errored in results:
    if name == "Grep" and not errored:
        rel = rel_of(inp.get("path"), ucwd)
        for p in changed:
            if (rel is not None and (rel == p or rel == "pr/head/" + p)) or p in res:
                grep_seen.add(p)
        continue
    if name != "Read" or errored:
        continue
    rel = rel_of(inp.get("file_path"), ucwd)
    if rel is None:
        continue
    key = (rel[len("pr/head/"):], "pr/head") if rel.startswith("pr/head/") else (rel, "root")
    if key[0] not in changed:
        continue
    read_seen.add(key)
    m = reads.setdefault(key, {})
    for l in REMINDER.sub("", res).split("\n")[:LINE_CAP]:
        g = GUTTER.match(l)
        if not g:
            continue
        n, txt = int(g.group(1)), g.group(2)
        if n in m and m[n] != txt:
            m[n] = None                     # two reads disagree on the line: it proves nothing
        elif n not in m:
            m[n] = txt

def qualifies(p, m):
    lines = text_lines(changed[p])
    need = 0 if changed[p] == b"" else (len(lines) - 1 if len(lines) > 1 and lines[-1] == "" else len(lines))
    matched = 0
    for n, txt in m.items():
        if txt is None or n < 1 or n > len(lines):
            return False
        got = txt[:-1] if txt.endswith("\r") else txt
        want = lines[n - 1]
        if not (got == want or (len(got) >= TRUNC and want.startswith(got))):
            return False                    # a line that is not the PR's: never a read of the PR's bytes
        if n <= need:
            matched += 1
    return True if need == 0 else matched >= max(1, math.ceil(COVER * need))

pr_bytes_read = sorted(set(p for key, m in reads.items() for p in [key[0]] if qualifies(p, m)))
grep_only = sorted(p for p in grep_seen if p not in pr_bytes_read)
cited, ftext = [], []
fbroot = os.path.join(ws_host, "grimoires", "loa", "a2a")
fbfiles = [os.path.join(ws_host, "review.md")]
for d, dirs, files in os.walk(fbroot, followlinks=False):
    dirs.sort()
    fbfiles += [os.path.join(d, n) for n in sorted(files) if re.match(r"^(engineer-feedback|auditor-sprint-feedback).*\.md$", n)]
for f in fbfiles:
    if os.path.isfile(f) and not os.path.islink(f):
        with open(f, "rb") as fh:
            ftext.append(fh.read(2 << 20).decode("utf-8", "replace"))
ftext = "\n".join(ftext)
for p in changed:
    if re.search(r"(?<![A-Za-z0-9_./-])(?:pr/)?(?:head/)?" + re.escape(p) + r":\d", ftext):
        cited.append(p)
cited.sort()
pinned_hits = []
STRIP = re.compile(r"^(?:[<>+\-] ?|\S+?:\d+[:-])")
for tn, name, inp, ucwd, res, errored in results:
    if name not in ("Read", "Bash", "Grep"):
        continue
    if errored:
        res = EXIT_LINE.sub("", res, count=1)
    blob = json.dumps(inp)
    for p, lo in later.items():
        if name == "Read":
            fp = inp.get("file_path")
            if not (isinstance(fp, str) and (os.path.normpath(fp).endswith("/" + p) or fp == p)):
                continue
        elif p not in blob and p not in res:
            continue
        for l in res.split("\n")[:LINE_CAP]:
            g = GUTTER.match(l) if name == "Read" else None
            s = (g.group(2) if g else STRIP.sub("", l)).strip()
            if s in lo:
                where = "Read %s" % inp.get("file_path") if name == "Read" else name
                pinned_hits.append((p, "pinned_bytes_read: a later-only line of the pinned version in %s (%s)" % (where, tn)))
                break
for p, d in pinned_hits:
    fail("f", p, d)
if changed and not pr_bytes_read:
    fail("f", "-", "pr_bytes_read is empty (%d changed .claude/ file(s); no Read returned the PR's bytes for >= 60 %% of one)" % len(changed))
for p in cited:
    if p not in pr_bytes_read:
        fail("f", p, "cited by the review but its PR bytes were never read (Read of %s or pr/head/%s; Grep never counts)" % (p, p))
fev = "(f) transcript_schema=%s parser=%s pr_bytes_read=%s cited=%s grep_only=%s pinned_bytes_read=%s" % (
    SCHEMA, PARSER, jl(pr_bytes_read), jl(cited), jl(grep_only), jl(set(p for p, _ in pinned_hits)))

# ---- clause (g): nothing of the PR's executable surface loaded or ran -----------------------------------------------
try:
    pl = json.load(open(os.path.join(run, "meta", "pipeline.json"), encoding="utf-8"))
except (OSError, ValueError):
    pl = {}
labels_run = [ph.get("label") for ph in (pl.get("phases") or []) if isinstance(ph, dict) and ph.get("skipped") is not True
              and isinstance(ph.get("label"), str) and re.match(r"^[A-Za-z0-9_-]+$", ph["label"])]
for lab in labels_run:
    psf = os.path.join(run, "meta", "ps-%s.txt" % lab)
    if not os.path.isfile(psf) or os.path.islink(psf):
        fail("g", "-", "no process capture for %s (meta/ps-%s.txt)" % (lab, lab))
    elif not any(l.startswith("# sample") for l in open(psf, encoding="utf-8", errors="replace").read(FILE_CAP).split("\n")):
        fail("g", "-", "no process sample for %s (meta/ps-%s.txt holds none: the sampler never saw the container)" % (lab, lab))


ps_lines, samples = [], 0
for n in sorted(os.listdir(os.path.join(run, "meta"))) if os.path.isdir(os.path.join(run, "meta")) else []:
    if re.match(r"^ps-[A-Za-z0-9_-]+\.txt$", n) and not os.path.islink(os.path.join(run, "meta", n)):
        for line in open(os.path.join(run, "meta", n), encoding="utf-8", errors="replace").read(FILE_CAP).split("\n"):
            if line.startswith("#"):
                samples += 1
            elif line.strip():
                ps_lines.append(("meta/" + n, line))

# canaries (the spike and the bats plant them): item, path, name, effect (relative to the run dir), token
canaries = []
cf = os.path.join(run, "meta", "canaries.tsv")
if os.path.isfile(cf) and not os.path.islink(cf):
    for line in open(cf, encoding="utf-8", errors="replace"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) == 5 and parts[4]:
            canaries.append(parts)
for item, cpath, cname, effect, tok in canaries:
    e = os.path.normpath(effect)
    if not e.startswith("..") and not os.path.isabs(e) and os.path.lexists(os.path.join(run, e)):
        fail("g", cpath, "the canary for %s executed (%s exists)" % (item, effect))
    rx = re.compile(re.escape(tok) + r"(?![A-Za-z0-9_])")
    for src, line in ps_lines:
        if rx.search(line):
            fail("g", cpath, "the canary for %s executed (%s in %s)" % (item, tok, src)); break
    for tn, txt in hook_texts:
        if rx.search(txt):
            fail("g", cpath, "the canary for %s loaded (%s in a hook_response of %s)" % (item, tok, tn)); break

# executions of a PR .claude/ path: the process samples and the Bash tool commands
WRAP = {"env", "exec", "nohup", "timeout", "sudo", "command", "builtin", "time", "nice", "stdbuf", "ionice", "setsid",
        "xargs", "then", "do", "else", "elif", "if", "while", "until", "!", "{"}
SH = {"sh", "bash", "dash", "zsh", "ksh"}
INTERP = SH | {"python", "python3", "node", "perl", "ruby", "deno", "bun", "tsx", "ts-node"}
RUNNERS = {"bats", "pytest", "py.test"}

def segments(cmd):
    """the command's simple commands as word lists: quotes respected, an unquoted ; & | newline ( ) ` or $( ends one,
    redirections dropped; a word holding $( or ` is split again (bounded)"""
    segs, words, cur, i, n = [], [], None, 0, len(cmd)
    def end_word():
        nonlocal cur
        if cur is not None:
            words.append(cur)
            cur = None
    def end_seg():
        end_word()
        if words:
            segs.append(list(words))
            words.clear()
    while i < n:
        c = cmd[i]
        if c == "'":
            j = cmd.find("'", i + 1)
            j = n if j < 0 else j
            cur = (cur or "") + cmd[i + 1:j]; i = j + 1; continue
        if c == '"':
            j, buf = i + 1, []
            while j < n and cmd[j] != '"':
                if cmd[j] == "\\" and j + 1 < n:
                    buf.append(cmd[j + 1]); j += 2; continue
                buf.append(cmd[j]); j += 1
            cur = (cur or "") + "".join(buf); i = j + 1; continue
        if c == "\\" and i + 1 < n:
            cur = (cur or "") + cmd[i + 1]; i += 2; continue
        if c in " \t\r":
            end_word(); i += 1; continue
        if c in ";&|\n()`" or (c == "$" and i + 1 < n and cmd[i + 1] == "("):
            end_seg(); i += 2 if c == "$" else 1; continue
        if c in "<>":
            end_word(); j = i
            while j < n and cmd[j] in "<>&|":
                j += 1
            while j < n and cmd[j] in " \t":
                j += 1
            while j < n and cmd[j] not in " \t;&|\n()":
                j += 1
            i = j; continue
        cur = (cur or "") + c; i += 1
    end_seg()
    return segs

def executed(cmd, cwd, depth=0):
    """[(path, cwd)] a command line executes: the command word, a sourced file, an interpreter's script, a test
    runner's files; sh -c and eval bodies recursively; cd moves the cwd for the later commands (lower bound)"""
    out = []
    if depth > 4 or len(cmd) > CMD_CAP:
        return out
    for words in segments(cmd)[:512]:
        for w in words:
            if ("$(" in w or "`" in w) and w != cmd:
                out += executed(w, cwd, depth + 1)
        i = 0
        while i < len(words):
            w, b = words[i], os.path.basename(words[i])
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w):
                i += 1; continue
            if b in WRAP:
                i += 1
                while i < len(words) and (words[i].startswith("-") or (b == "timeout" and re.match(r"^\d+(\.\d+)?[smhd]?$", words[i]))
                                          or (b == "env" and "=" in words[i])):
                    i += 1
                continue
            break
        if i >= len(words):
            continue
        exe, rest = words[i], words[i + 1:]
        b = os.path.basename(exe)
        if b == "cd":
            if rest and not rest[0].startswith("-") and not rest[0].startswith("~"):
                cwd = os.path.normpath(rest[0] if rest[0].startswith("/") else os.path.join(cwd, rest[0]))
            continue
        if b in ("source", "."):
            out += [(rest[0], cwd)] if rest else []
        elif b == "eval":
            out += executed(" ".join(rest), cwd, depth + 1)
        elif b in INTERP:
            j = 0
            while j < len(rest):
                a = rest[j]
                if a == "--":
                    j += 1; break
                if a.startswith("-") and a != "-":
                    if b in SH and not a.startswith("--") and "c" in a[1:]:
                        out += executed(rest[j + 1], cwd, depth + 1) if j + 1 < len(rest) else []
                        j = len(rest) + 1; break
                    if (b.startswith("python") and a in ("-c", "-m")) or (b in ("node", "deno", "bun") and a in ("-e", "--eval", "-p", "--print")) \
                            or (b in ("perl", "ruby") and a == "-e"):
                        j = len(rest) + 1; break
                    j += 2 if a in ("-o", "-O", "-W", "-X") else 1
                    continue
                break
            if j < len(rest):
                out.append((rest[j], cwd))
        elif b in RUNNERS:
            out += [(a, cwd) for a in rest if not a.startswith("-")]
        else:
            out.append((exe, cwd))
    return out

def pr_claude(p, cwd, ws):
    """the PR .claude/ path a command executes (root .claude/ is the PR's data under home-scope), else None"""
    if p.startswith("~"):
        return None
    full = os.path.normpath(p if p.startswith("/") else os.path.join(cwd, p))
    base = ws.rstrip("/")
    if not full.startswith(base + "/"):
        return None
    rel = full[len(base) + 1:]
    return rel if re.match(r"^(?:pr/(?:head|base)/)?\.claude(?:/|$)", rel) else None

ws_c = inits[0][2] if inits else "/workspace"
for src, line in ps_lines:
    m = re.match(r"^\s*(\d+)\s+(\d+)\s+(.*)$", line)
    if not m:
        continue
    for p, c in executed(m.group(3), ws_c):
        r = pr_claude(p, c, ws_c)
        if r is not None:
            fail("g", r, "executed a PR .claude/ path (%s pid %s)" % (src, m.group(1))); break
for tn, tid, cmd, cwd in bash_cmds:
    for p, c in executed(cmd, cwd):
        r = pr_claude(p, c, cwd)
        if r is not None:
            fail("g", r, "executed a PR .claude/ path (Bash %s in %s)" % (tid, tn)); break

# the loaded surface the init event lists: MCP servers, plugins, skills / commands, agents, the output style
def surface_names(paths, read):
    names = {"skill": set(), "command": set(), "agent": set(), "output style": set(), "plugin": set()}
    for p in paths:
        m = re.match(r"^\.claude/skills/([^/]+)/SKILL\.md$", p)
        if m:
            names["skill"].add(m.group(1))
        for kind, rx in (("command", r"^\.claude/commands/(?:.+/)?([^/]+)\.md$"), ("agent", r"^\.claude/agents/(?:.+/)?([^/]+)\.md$"),
                         ("output style", r"^\.claude/output-styles/(?:.+/)?([^/]+)\.md$")):
            m = re.match(rx, p)
            if m:
                names[kind].add(m.group(1))
                b = read(p)
                fm = re.search(r"\A---\n(?:.*\n)*?name:\s*['\"]?([^'\"\n]+?)['\"]?\s*\n(?:.*\n)*?---", (b or b"")[:65536].decode("utf-8", "replace"))
                if fm:
                    names[kind].add(fm.group(1).strip())
        m = re.match(r"^\.claude/plugins/([^/]+)/", p)
        if m:
            names["plugin"].add(m.group(1))
    return names

def fixture_tree(side):
    root, out = os.path.join(fixture, side), []
    for d, dirs, files in os.walk(root, followlinks=False):
        out += [os.path.relpath(os.path.join(d, n), root).replace(os.sep, "/") for n in files]
    return out
pr_paths = fixture_tree("head") + fixture_tree("base")
def pr_read(p):
    return regular(os.path.join(fixture, "head"), p) or regular(os.path.join(fixture, "base"), p)
pr_names = surface_names(pr_paths, pr_read)
lst = git("ls-tree", "-r", "-z", "--name-only", commit, "--", ".claude/skills", ".claude/commands", ".claude/agents",
          ".claude/output-styles", ".claude/plugins") or b""
pin_names = surface_names([x for x in lst.decode("utf-8", "surrogateescape").split("\0") if x], pinned)
pr_only = dict((k, pr_names[k] - pin_names[k]) for k in pr_names)
allow_mcp = set(x for x in (evidence("home_mcp_servers") or "").split(",") if x)
canary_names = dict((c[2], c[0]) for c in canaries if c[2] and c[2] != "-")
for tn, ev, cwd in inits:
    for s in ev.get("mcp_servers") or []:
        nm = s.get("name") if isinstance(s, dict) else s
        if isinstance(nm, str) and nm not in allow_mcp:
            fail("g", "-", "MCP server %s loaded (%s init; home_mcp_servers declares %s)" % (nm, tn, ",".join(sorted(allow_mcp)) or "none"))
    for pg in ev.get("plugins") or []:
        if not isinstance(pg, dict):
            continue
        pp = pg.get("path")
        if isinstance(pp, str) and pp != "builtin" and (not pp.startswith("/") or pp.rstrip("/") == cwd.rstrip("/")
                                                        or pp.startswith(cwd.rstrip("/") + "/")):
            fail("g", "-", "plugin %s loaded from the project (%s; %s init)" % (pg.get("name"), pp, tn))
    listed = []
    for key in ("skills", "slash_commands", "agents"):
        listed += [(key, x) for x in (ev.get(key) or []) if isinstance(x, str)]
    if isinstance(ev.get("output_style"), str):
        listed.append(("output_style", ev["output_style"]))
    for key, nm in listed:
        kinds = {"skills": ("skill", "command"), "slash_commands": ("skill", "command"), "agents": ("agent",),
                 "output_style": ("output style",)}[key]
        hit = next((k for k in kinds if nm in pr_only[k]), None)
        if hit:
            fail("g", "-", "the PR-only %s %s was loaded (%s init)" % (hit, nm, tn))
        elif nm in canary_names:
            fail("g", "-", "the canary for %s loaded (name %s in %s init)" % (canary_names[nm], nm, tn))
decl_raw = evidence("home_hook_counts")
if decl_raw is None:
    fail("g", "-", "no home_hook_counts evidence (the mount declares the pinned user settings' hooks)")
    decl = {}
else:
    decl = {}
    for part in decl_raw.split(","):
        if ":" in part and part.split(":", 1)[1].isdigit():
            decl[part.split(":", 1)[0]] = int(part.split(":", 1)[1])
    for (tn, evn), cnt in sorted(hook_counts.items()):
        if cnt > decl.get(evn, 0):
            fail("g", "-", "%d %s hook(s) ran in %s; the pinned user settings declare %d (home_hook_counts)" % (cnt, evn or "<unnamed>", tn, decl.get(evn, 0)))
for tn, txt in user_texts:
    for m in re.finditer(r"Base directory for this skill:\s*(\S+)", txt[:1 << 20]):
        bd = os.path.normpath(m.group(1))
        cw = next((c for t2, _e, c in inits if t2 == tn), "/workspace").rstrip("/")
        if bd == cw or bd.startswith(cw + "/"):
            fail("g", "-", "a skill loaded from the workspace: %s (%s)" % (m.group(1), tn))

nexec = 0
gev = "(g) %d phase(s): %d PR .claude/ executions in %d process sample(s) and %d Bash command(s); hooks within home_hook_counts %s; " \
      "no project MCP server, plugin, skill, command, agent or output style; %s" % (
          len(labels_run), nexec, samples, len(bash_cmds), decl_raw or "-",
          ("%d canaries planted, none loaded or executed" % len(canaries)) if canaries else "no canary planted")
if fails:
    order = {"f": 0, "g": 1}
    fails.sort(key=lambda x: order[x[0]])
    c, p, d = fails[0]
    print("FAIL (%s) %s: %s%s" % (c, p, d, " (+%d more)" % (len(fails) - 1) if len(fails) > 1 else ""))
    sys.exit(1)
print("ok %s; %s" % (fev, gev))
PY
}
rule_oracle_open_recorded() {
  local f="$R/meta/arm-evidence.txt"
  grep -qx 'mount_overlay=none' "$f" 2>/dev/null || { EVID="no mount_overlay=none in arm_evidence (got $(evidence_line mount_overlay || true))"; return 1; }
  grep -qx 'oracle_open=true' "$f" 2>/dev/null || { EVID="no oracle_open=true in arm_evidence"; return 1; }
  EVID="mount_overlay=none, oracle_open=true"
}
rule_bare_model_fable() {
  local rec n fable opus eff keys
  rec="$(jq -c '[.phases // [] | .[] | select(.name == "BARE" and .skipped != true)]' "$R/meta/pipeline.json")"
  n="$(jq 'length' <<<"$rec")"
  [[ "$n" -eq 1 ]] || { EVID="$n BARE record(s)"; return 1; }
  keys="$(jq -r '.[0].models_used // {} | keys | join(",")' <<<"$rec")"
  fable="$(jq '[.[0].models_used // {} | keys[] | select(startswith("global.anthropic.claude-fable"))] | length' <<<"$rec")"
  opus="$(jq '[.[0].models_used // {} | keys[] | select(startswith("global.anthropic.claude-opus"))] | length' <<<"$rec")"
  eff="$(jq -r '.[0].effort_requested // "null"' <<<"$rec")"
  [[ "$fable" -eq 1 && "$opus" -eq 0 ]] || { EVID="BARE models_used ${keys:-<none>} (want exactly one global.anthropic.claude-fable* and no opus)"; return 1; }
  [[ "$eff" == high ]] || { EVID="BARE effort_requested $eff (want high)"; return 1; }
  EVID="BARE models_used $keys, effort_requested high"
}
rule_dissent_present() {
  local gate label f vs st ran="" bad=""
  for gate in review audit; do
    label=REVIEW; [[ "$gate" == audit ]] && label=AUDIT
    [[ "$(jq --arg l "$label" '[.phases // [] | .[] | select(.name == $l and .skipped != true)] | length' "$R/meta/pipeline.json")" -gt 0 ]] || continue
    ran="$ran $gate"
    f="$R/eval/adversarial-$gate.json"
    if [[ ! -f "$f" || -L "$f" ]] || ! jq -e 'type == "object"' "$f" >/dev/null 2>&1; then bad="$bad $gate:no-envelope"; continue; fi
    vs="$(jq -r '(.verdict_quality.voices_succeeded // .metadata.verdict_quality.voices_succeeded // 0) | tostring' "$f")"
    st="$(jq -r '(.metadata.status // .status // "") | tostring' "$f")"
    if [[ "$st" == budget_exceeded ]] || grep -qi 'refus' <<<"$st"; then bad="$bad $gate:status=$st"
    elif ! [[ "$vs" =~ ^[0-9]+$ && "$vs" -ge 1 ]]; then bad="$bad $gate:voices_succeeded=$vs"; fi
  done
  [[ -n "$ran" ]] || { EVID="no gate phase ran"; return 1; }
  [[ -z "$bad" ]] || { EVID="dissent missing:${bad}"; return 1; }
  EVID="dissent ran at${ran} (eval/ envelopes, voices_succeeded >= 1)"
}
rule_mount_cheval_ok() {
  local v; v="$(evidence_line mount_cheval)"
  [[ "$v" == ok ]] || { EVID="mount_cheval=${v:-<absent>} in arm_evidence (want ok; KF-050)"; return 1; }
  EVID="mount_cheval=ok"
}
# cell_sessions <cell-dir> → TSV lines <id> <valid> <run_dir> from meta/cell.json (run_dir realpath inside
# <cell>/sessions/, else "-"); exit 1 when cell.json is not a cell record
cell_sessions() {
  python3 -I - "$1" <<'PY'
import json, os, sys
cell = sys.argv[1]
try:
    c = json.load(open(os.path.join(cell, "meta", "cell.json"), encoding="utf-8"))
except (OSError, ValueError):
    sys.exit(1)
if not isinstance(c, dict) or not isinstance(c.get("sessions"), list):
    sys.exit(1)
base = os.path.realpath(os.path.join(cell, "sessions"))
for s in c["sessions"]:
    if not isinstance(s, dict):
        sys.exit(1)
    rd = s.get("run_dir")
    p = os.path.realpath(os.path.join(cell, rd)) if isinstance(rd, str) and rd else ""
    ok = p.startswith(base + os.sep) and os.path.isdir(p)
    print("%s\t%s\t%s" % (s.get("id"), "true" if s.get("valid") is True else "false", p if ok else "-"))
PY
}
rule_bare_sessions_matched() {
  local cj="$R/meta/cell.json" k want key n i id valid rd sub fails="" bad
  if [[ ! -f "$cj" ]]; then
    if [[ "$(basename "$(dirname "$R")")" == sessions && -f "$(dirname "$(dirname "$R")")/meta/arm" ]]; then
      EVID="session $(basename "$R") of a matched cell (the cell rule runs on the cell directory)"; return 0
    fi
    EVID="not a matched cell (no meta/cell.json) and not one of its sessions"; return 1
  fi
  k="$(jq -r '.k | if type == "number" and . >= 1 and . == floor then tostring else "" end' "$cj" 2>/dev/null || true)"
  [[ -n "$k" ]] || { EVID="meta/cell.json has no integer k"; return 1; }
  [[ -n "$TASK_YAML_OPT" ]] || { EVID="k $k unverified: --task-yaml names the task's review_catch.bare_sessions_matched"; return 1; }
  key=bare_sessions_matched
  if [[ "$(jq -r '.toggles.bare_model // ""' <<<"$ARM_DEF")" == fable ]]; then
    want="$(yq -r '.review_catch.bare_sessions_matched_fable // .review_catch.bare_sessions_matched // ""' "$TASK_YAML_OPT" 2>/dev/null || true)"
    key="bare_sessions_matched_fable|bare_sessions_matched"
  else
    want="$(yq -r '.review_catch.bare_sessions_matched // ""' "$TASK_YAML_OPT" 2>/dev/null || true)"
  fi
  [[ "$want" =~ ^[0-9]+$ ]] || { EVID="the task has no review_catch.$key"; return 1; }
  [[ "$k" -eq "$want" ]] || { EVID="cell k $k, the task's review_catch.$key is $want"; return 1; }
  n="$(jq '.sessions | length' "$cj")"
  [[ "$n" -eq "$k" ]] || { EVID="cell.json lists $n sessions, k $k"; return 1; }
  [[ "$(jq -r '[.sessions[].id] | join(",")' "$cj")" == "$(seq -s, -f 's%g' 1 "$k")" ]] \
    || { EVID="cell.json session ids $(jq -r '[.sessions[].id] | join(",")' "$cj"), want s1 … s$k"; return 1; }
  for i in $(seq 1 "$k"); do [[ -d "$R/sessions/s$i" ]] || { EVID="session s$i was never attempted (no sessions/s$i)"; return 1; }; done
  [[ ! -e "$R/sessions/s$((k + 1))" ]] || { EVID="sessions/s$((k + 1)) exists beyond k $k"; return 1; }
  local nvalid=0 save_r="$R" save_ev
  while IFS=$'\t' read -r id valid rd; do
    [[ "$valid" == true ]] || continue
    [[ "$rd" != - ]] || { R="$save_r"; EVID="valid session $id has no run dir inside sessions/"; return 1; }
    nvalid=$((nvalid + 1))
    for sub in no_dot_claude no_system_prompt no_audit_rows integrity_clean; do
      R="$rd"; EVID=""
      if ! "rule_$sub"; then fails="$fails $id:$sub(${EVID})"; fi
    done
  done < <(cell_sessions "$save_r" || echo "x	true	-")
  R="$save_r"
  [[ -z "$fails" ]] || { EVID="valid sessions failing:${fails}"; return 1; }
  EVID="k $k = the task's $key; s1 … s$k attempted; $nvalid valid session(s) pass no_dot_claude, no_system_prompt, no_audit_rows, integrity_clean"
}
rule_review_only_phases() {
  local got
  got="$(jq -r '[.phases // [] | .[] | .label] | join(",")' "$R/meta/pipeline.json")"
  [[ "$got" == REVIEW ]] || { EVID="phases ${got:-none}, want REVIEW"; return 1; }
  [[ ! -e "$R/sandbox/grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md" ]] || { EVID="auditor-sprint-feedback.md exists"; return 1; }
  EVID="phases REVIEW; no auditor-sprint-feedback.md"
}
rule_no_review_dissent_envelope() {
  local f en vs
  f="$(envelope review)"
  [[ -z "$f" ]] || { EVID="a review envelope exists (${f#"$R"/})"; return 1; }
  en="$(yq -r '.flatline_protocol.code_review.enabled' "$R/sandbox/.loa.config.yaml" 2>/dev/null || echo unreadable)"
  [[ "$en" == false ]] || { EVID="sandbox flatline_protocol.code_review.enabled is $en"; return 1; }
  f="$(envelope audit)"
  [[ -n "$f" ]] || { EVID="no audit envelope (the audit dissent must still run)"; return 1; }
  vs="$(jq -r '(.verdict_quality.voices_succeeded // .metadata.verdict_quality.voices_succeeded // 0) | tostring' "$f" 2>/dev/null || echo 0)"
  [[ "$vs" =~ ^[0-9]+$ && "$vs" -ge 1 ]] || { EVID="audit envelope voices_succeeded $vs"; return 1; }
  EVID="no review envelope; code_review.enabled false; audit voices_succeeded $vs"
}

cell_rule() {  # cell_rule <rule> — the rule on every valid session of the cell at $R
  local rule="$1" cell="$R" id valid rd n=0 first=""
  while IFS=$'\t' read -r id valid rd; do
    [[ "$valid" == true ]] || continue
    if [[ "$rd" == - ]]; then first="${first:-$id: no run dir inside sessions/}"; continue; fi
    n=$((n + 1)); R="$rd"; EVID=""
    "rule_$rule" || first="${first:-$id: $EVID}"
  done < <(cell_sessions "$cell" || echo "x	true	-")
  R="$cell"
  [[ -z "$first" ]] || { EVID="$first"; return 1; }
  EVID="$n valid session(s) pass"
}

# ---- one run ------------------------------------------------------------------------
check_run() {  # check_run <run-dir> → prints lines; returns 0/1; 2 on usage problems
  R="$1" CELL_MODE=false
  local arm rules rule fails=0 total=0 results='[]' ok
  if [[ -n "$ARM_OPT" ]]; then arm="$ARM_OPT"
  elif [[ -f "$R/meta/arm" ]]; then arm="$(sed -n '1p' "$R/meta/arm" | tr -d '[:space:]')"
  elif [[ -f "$R/meta/refused.json" ]]; then arm="$(jq -r '.arm // ""' "$R/meta/refused.json")"
  else arm="$(jq -r '.arm // ""' "$R/meta/pipeline.json" 2>/dev/null || true)"; fi
  [[ -n "$arm" ]] || { echo "took-effect.sh: no arm for $R" >&2; return 2; }
  ARM="$arm"
  ARM_DEF="$(jq -c --arg a "$arm" '[.arms // [] | .[] | select(.id == $a)][0] // empty' <<<"$SUITE_JSON")"
  [[ -n "$ARM_DEF" ]] || { echo "took-effect.sh: arm $arm is not declared in the suite" >&2; return 2; }
  if [[ "$(jq -r '.absent // false' <<<"$ARM_DEF")" == true ]]; then
    if [[ "$JSON" == true ]]; then jq -nc --arg d "$R" --arg arm "$arm" '{run_dir: $d, arm: $arm, ok: true, absent: true, rules: []}'
    else printf 'arm %s: absent (component-absent; no rules)\n' "$arm"; fi
    return 0
  fi
  if [[ -f "$R/meta/cell.json" && ! -f "$R/meta/pipeline.json" ]]; then
    rules="$(jq -r '(.took_effect // []) | .[]' <<<"$ARM_DEF")"
    [[ -n "$rules" ]] || { echo "took-effect.sh: arm $arm lists no took_effect rules" >&2; return 2; }
    CELL_MODE=true
  elif [[ -f "$R/meta/refused.json" ]]; then
    rules="applicability_refused"
  else
    [[ -f "$R/meta/pipeline.json" ]] || { echo "took-effect.sh: no meta/pipeline.json under $R" >&2; return 2; }
    rules="$(jq -r '(.took_effect // []) | .[]' <<<"$ARM_DEF")"
    [[ -n "$rules" ]] || { echo "took-effect.sh: arm $arm lists no took_effect rules" >&2; return 2; }
  fi
  while IFS= read -r rule; do
    [[ -n "$rule" ]] || continue
    total=$((total + 1)); EVID=""
    if ! declare -F "rule_$rule" >/dev/null; then
      ok=false; EVID="unknown rule id"
    elif [[ "$CELL_MODE" == true && "$rule" != bare_sessions_matched ]]; then
      # a cell: the rule holds on every valid session's final run dir
      if cell_rule "$rule"; then ok=true; else ok=false; fi
    elif "rule_$rule"; then ok=true; else ok=false; fi
    [[ "$ok" == true ]] || fails=$((fails + 1))
    if [[ "$JSON" == true || -n "$JSON_OUT" ]]; then
      results="$(jq -c --arg r "$rule" --argjson ok "$ok" --arg e "$EVID" '. + [{rule: $r, ok: $ok, evidence: $e}]' <<<"$results")"
    fi
    if [[ "$JSON" != true ]]; then
      printf 'arm %s: %s %s %s\n' "$arm" "$rule" "$([[ "$ok" == true ]] && echo OK || echo FAIL)" "$EVID"
    fi
  done <<<"$rules"
  if [[ -n "$JSON_OUT" ]]; then
    jq -nc --arg d "$R" --arg arm "$arm" --argjson rules "$results" --argjson ok "$([[ $fails -eq 0 ]] && echo true || echo false)" \
      '{run_dir: $d, arm: $arm, ok: $ok, rules: $rules}' > "$JSON_OUT.tmp" && mv "$JSON_OUT.tmp" "$JSON_OUT"
  fi
  if [[ "$JSON" == true ]]; then
    jq -nc --arg d "$R" --arg arm "$arm" --argjson rules "$results" --argjson ok "$([[ $fails -eq 0 ]] && echo true || echo false)" \
      '{run_dir: $d, arm: $arm, ok: $ok, rules: $rules}'
  elif [[ $fails -eq 0 ]]; then
    printf 'arm %s: OK\n' "$arm"
  else
    printf 'arm %s: FAIL (%d of %d rules)\n' "$arm" "$fails" "$total"
  fi
  [[ $fails -eq 0 ]]
}

if [[ -n "$RUN_DIR" ]]; then
  [[ -d "$RUN_DIR" ]] || usage "run dir not found: $RUN_DIR"
  rc=0; check_run "$RUN_DIR" || rc=$?
  exit "$rc"
fi

[[ -d "$BATCH_DIR" ]] || usage "batch dir not found: $BATCH_DIR"
runs=0 failed=0
while IFS= read -r d; do
  runs=$((runs + 1))
  rc=0; check_run "$d" || rc=$?
  [[ $rc -eq 2 ]] && exit 2
  [[ $rc -eq 0 ]] || failed=$((failed + 1))
done < <(find "$BATCH_DIR" -mindepth 2 -maxdepth 4 -type d -name meta \
           \( -exec test -f '{}/pipeline.json' \; -o -exec test -f '{}/refused.json' \; \) -print \
         | sed 's|/meta$||' | LC_ALL=C sort)
[[ $runs -gt 0 ]] || usage "no run directories under $BATCH_DIR"
[[ "$JSON" == true ]] || printf 'took-effect: %d runs, %d failed\n' "$runs" "$failed"
[[ $failed -eq 0 ]]
