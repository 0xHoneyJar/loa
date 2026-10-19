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
#                              "no mount"
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
#                              The comparison is lib/sandbox-mount.sh's (_sm_oracle_py check), the
#                              same one pipeline-run.sh's pre-launch check_mount_closed runs.
#                              A build run (no PR fixture) and a loa_mount: false run with no
#                              .claude/ pass with that evidence.
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
# A refusal record is evaluated on applicability_refused alone.
#
# Usage:
#   took-effect.sh --run-dir D --suite-file F [--arm ID] [--json] [--task-yaml F] [--source-repo DIR]
#   took-effect.sh --batch-dir D --suite-file F [--arm ID] [--json] [--source-repo DIR]
#   --task-yaml F     the run's task (oracle_closed's fixture; run-ablation.sh passes it)
#   --source-repo DIR a git repository holding the run's source_commit (oracle_closed)
#
# Output: `arm <id>: <rule> OK|FAIL <evidence>` per rule, then `arm <id>: OK` or
# `arm <id>: FAIL (<n> of <m> rules)`; --batch-dir adds `took-effect: <runs> runs, <k> failed`.
# --json prints one object per run ({run_dir, arm, ok, rules: [{rule, ok, evidence}]}).
#
# Exit codes:
#   0  every rule OK
#   1  any rule FAIL
#   2  usage error (missing files, unknown arm)
#
# Tested by evals/tests/took-effect.bats (fixture runs under
# evals/tests/fixtures/ablation-runs/, and cycle-131 runs built in the test with the real
# mount library) and evals/tests/pipeline-run.bats (oracle_closed on a real-library run).
# =============================================================================
set -euo pipefail
export LC_ALL=C

# Hashing is Python hashlib: no harness script sources .claude/ code (eval.yml
# "Validate grader trust boundary").

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUN_DIR="" BATCH_DIR="" SUITE_FILE="" ARM_OPT="" JSON=false TASK_YAML_OPT="" SOURCE_REPO_OPT=""
usage() { echo "took-effect.sh: $*" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)    RUN_DIR="${2:-}"; shift 2 ;;
    --batch-dir)  BATCH_DIR="${2:-}"; shift 2 ;;
    --suite-file) SUITE_FILE="${2:-}"; shift 2 ;;
    --arm)        ARM_OPT="${2:-}"; shift 2 ;;
    --json)       JSON=true; shift ;;
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
  [[ $rc -eq 0 ]]
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

# ---- one run ------------------------------------------------------------------------
check_run() {  # check_run <run-dir> → prints lines; returns 0/1; 2 on usage problems
  R="$1"
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
  if [[ -f "$R/meta/refused.json" ]]; then
    rules="applicability_refused"
  else
    [[ -f "$R/meta/pipeline.json" ]] || { echo "took-effect.sh: no meta/pipeline.json under $R" >&2; return 2; }
    rules="$(jq -r '(.took_effect // []) | .[]' <<<"$ARM_DEF")"
    [[ -n "$rules" ]] || { echo "took-effect.sh: arm $arm lists no took_effect rules" >&2; return 2; }
  fi
  while IFS= read -r rule; do
    [[ -n "$rule" ]] || continue
    total=$((total + 1)); EVID=""
    if declare -F "rule_$rule" >/dev/null; then
      if "rule_$rule"; then ok=true; else ok=false; fi
    else
      ok=false; EVID="unknown rule id"
    fi
    [[ "$ok" == true ]] || fails=$((fails + 1))
    if [[ "$JSON" == true ]]; then
      results="$(jq -c --arg r "$rule" --argjson ok "$ok" --arg e "$EVID" '. + [{rule: $r, ok: $ok, evidence: $e}]' <<<"$results")"
    else
      printf 'arm %s: %s %s %s\n' "$arm" "$rule" "$([[ "$ok" == true ]] && echo OK || echo FAIL)" "$EVID"
    fi
  done <<<"$rules"
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
