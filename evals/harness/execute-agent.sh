#!/usr/bin/env bash
# =============================================================================
# execute-agent.sh — agent-execution step for Loa Eval Sandbox trials
#
# cycle-124 Sprint 3 (PRD FR-9 / SDD §3.6). Fills the slot at the top of the
# grading step in run-eval.sh: a task that declares `.agent.skill` runs the
# headless Claude CLI inside the sandbox before its graders; every other task
# takes the pre-existing path untouched.
#
# What it does, in order:
#   1. Gate: no `.agent.skill` in the task YAML → exit 3, nothing written.
#   2. Materialize the prompt surface from $EVAL_PROMPT_TREE into the sandbox:
#        <ws>/.claude/skills/<skill>/        (SKILL.md + resources/)
#        <ws>/.claude/loa/CLAUDE.loa.md      (+ .claude/rules/)
#        <ws>/CLAUDE.md                      → "@.claude/loa/CLAUDE.loa.md"
#        <ws>/.eval/skill-prompt.md          (SKILL.md body, frontmatter stripped)
#      The prompt tree is the ONLY thing that differs between A/B arms, so it
#      is recorded: prompt_tree_sha = `git rev-parse HEAD:.claude` of the tree,
#      prompt_tree_commit, and whether .claude/ had uncommitted changes.
#   3. Run:  claude -p "<task.prompt>" --output-format stream-json --verbose
#              --model $EVAL_MODEL [--effort <e>] --restricted --tools Read,Grep,Glob,Write
#              --permission-mode acceptEdits --append-system-prompt-file <skill-prompt>
#              --max-turns $EVAL_MAX_TURNS
#      --restricted --tools names the SDD's fixed tool set EXACTLY: it removes the
#      code-running tools, ignores the operator's user/project/local settings (their
#      Bash(...) allow rules leaked into the sprint-237 A/B arms under --allowed-tools,
#      which only adds rules) and confines Read/Grep/Glob/Write to the sandbox.
#      Edit/MultiEdit are therefore unavailable; the transcript extractor below still
#      records them defensively.
#      cwd = sandbox; env-isolated (LOA_MODELINV_LOG_PATH / LOA_COST_LEDGER_PATH and
#      TMPDIR into the sandbox; GH_TOKEN/GITHUB_TOKEN/OPENAI_API_KEY/AWS_* unset;
#      HOME and PATH stay so the CLI finds its own credentials and toolchain).
#   4. Record <ws>/.eval/events.jsonl (raw stream), agent-output.json (the
#      `result` event) and executor.json:
#        {schema_version, skill, model_requested, model_id (the id the CLI
#         echoed — the modelUsage entry with the most output tokens), effort,
#         prompt_tree_sha, prompt_tree_commit, prompt_tree_dirty, exit_code,
#         is_error, duration_ms, num_turns, total_cost_usd, usage{…},
#         tool_writes:[{seq,tool,path}] in transcript order}
#
# Exit codes:
#   0  agent ran (its own verdict is the graders' business)
#   1  the CLI exited non-zero or timed out (executor.json still written)
#   2  infrastructure error (CLI binary missing, prompt tree lacks the skill)
#   3  task declares no agent (caller should not have called us)
#
# Env:
#   EVAL_MODEL          model passed to --model            (default claude-sonnet-5)
#   EVAL_EFFORT         override effort                    (default: task/skill)
#   EVAL_PROMPT_TREE    repo whose .claude/ is materialized (default: this repo)
#   EVAL_CLAUDE_BIN     CLI executable                     (default: claude)
#   EVAL_MAX_TURNS      --max-turns                        (default 40)
#
# Control arms (cycle-129 FR-2, SDD D-2.1):
#   LOA_EVAL_ARM          arm id (default baseline). Setting it at all is "arm
#                         mode": the prompt tree's .loa.config.yaml is also
#                         materialised so every arm sees the same config.
#   LOA_EVAL_ARM_TOGGLES  JSON object {toggle: false, …}; when unset the arm is
#                         resolved from LOA_EVAL_SUITE_FILE, else from
#                         evals/suites/<task dir name>.yaml (`ab.arms[]`)
#   LOA_EVAL_SOURCE_COMMIT  recorded as source_commit (default: the prompt
#                         tree's HEAD)
#   Toggles are applied to the SANDBOX COPY only, after every materialisation
#   step and immediately before the executor starts; each is verified
#   afterwards and a toggle that cannot take effect is exit 2 (an arm never
#   silently runs as its baseline). Arms come from the suite's arms[] (cycle-130)
#   or ab.arms[] (cycle-129); an `absent: true` arm is exit 2:
#     companion_voice: false         flatline_protocol.{code_review,security_audit}.companion_voice=false
#                                    in <ws>/.loa.config.yaml (yq)
#     karpathy_block: false          '## Karpathy Principles' section out of
#                                    <ws>/.claude/loa/CLAUDE.loa.md; Karpathy rows
#                                    out of <ws>/.claude/data/constraints.json if present
#     rule_files: false              stash-safety.md, skill-invariants.md out of <ws>/.claude/rules/
#     audit_delta_instruction: false the paragraph containing "look for what the
#                                    review did not", else "Confirm the review's demotions
#                                    independently", out of the sandbox auditing-security/SKILL.md
#   cycle-130 toggles (Task 1.6; SDD D-4.2):
#     loa_mount: false               no .claude/, CLAUDE.md, .loa.config.yaml or skill prompt
#                                    in the sandbox; no --append-system-prompt-file; the task
#                                    prompt only; skill-frontmatter effort not read (a0_bare)
#     effort: <low|medium|high|xhigh|max>  --effort <v> on argv (wins over EVAL_EFFORT);
#                                    `effort:` stripped from every sandbox SKILL.md frontmatter;
#                                    sandbox model-config default_effort=<v>, .checksum refreshed
#     gates: false                   flatline_protocol.{code_review,security_audit}.enabled=false;
#                                    LOA_ADVERSARIAL_REVIEW_ENFORCE=false in the executor env
#     flatline: false                flatline_protocol.enabled=false
#     sprint_plan / context_resets   pipeline-run.sh only: exit 2 here (no phases to edit)
#   In every mode an inherited LOA_ADVERSARIAL_REVIEW_ENFORCE is unset before the
#   toggles (only gates: false sets it again; audit LOW-A3), and in arm mode the
#   sandbox .claude/checksums.json is regenerated after them
#   (arm_evidence.manifest_sha256). The materialisation and toggle code lives in
#   lib/sandbox-mount.sh (its header is the contract); an arm effort outside
#   low|medium|high|xhigh|max is exit 2 here as well (audit LOW-A1).
#   The appended skill prompt (.eval/skill-prompt.md) is derived from the
#   toggled sandbox SKILL.md. executor.json records arm, arm_toggles,
#   arm_evidence, source_commit and adversarial_review_enforce (the variable's
#   value in the executor environment at launch, or "unset").
#
# Tested by evals/tests/execute-agent.bats and evals/tests/arm-toggles.bats.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# eval.yml trust boundary: a literal in-tree path, no variable on the source line
pushd "$SCRIPT_DIR" >/dev/null
# shellcheck source=lib/sandbox-mount.sh
source ./lib/sandbox-mount.sh
popd >/dev/null

TASK_YAML=""
WORKSPACE=""
RUN_ID=""
TRIAL_ID=""
TIMEOUT_S=900

usage() {
  sed -n '2,/^# =====.*$/p' "$0" | sed -n '2,98p' | sed 's/^# \{0,1\}//' >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-yaml) TASK_YAML="$2"; shift 2 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --trial-id) TRIAL_ID="$2"; shift 2 ;;
    --timeout) TIMEOUT_S="$2"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$TASK_YAML" && -n "$WORKSPACE" ]] || { echo "ERROR: --task-yaml and --workspace are required" >&2; exit 2; }
[[ -f "$TASK_YAML" ]] || { echo "ERROR: task YAML not found: $TASK_YAML" >&2; exit 2; }
[[ -d "$WORKSPACE" ]] || { echo "ERROR: workspace not found: $WORKSPACE" >&2; exit 2; }
WORKSPACE="$(cd "$WORKSPACE" && pwd)"

# --- 1. gate ---------------------------------------------------------------
skill="$(yq -r '.agent.skill // ""' "$TASK_YAML")"
if [[ -z "$skill" || "$skill" == "null" ]]; then
  echo "execute-agent: task declares no .agent.skill — nothing to run" >&2
  exit 3
fi
case "$skill" in
  */*|.*|'') echo "ERROR: invalid skill name '$skill'" >&2; exit 2 ;;
esac

PROMPT_TREE="${EVAL_PROMPT_TREE:-$REPO_ROOT}"
PROMPT_TREE="$(cd "$PROMPT_TREE" && pwd)"
CLAUDE_BIN="${EVAL_CLAUDE_BIN:-claude}"
MODEL="${EVAL_MODEL:-claude-sonnet-5}"
MAX_TURNS="${EVAL_MAX_TURNS:-40}"

skill_src="$PROMPT_TREE/.claude/skills/$skill"
[[ -f "$skill_src/SKILL.md" ]] || { echo "ERROR: prompt tree $PROMPT_TREE has no .claude/skills/$skill/SKILL.md" >&2; exit 2; }
command -v "$CLAUDE_BIN" >/dev/null 2>&1 || [[ -x "$CLAUDE_BIN" ]] || { echo "ERROR: CLI not found: $CLAUDE_BIN (set EVAL_CLAUDE_BIN)" >&2; exit 2; }

# --- 2. materialize ----------------------------------------------------------
# The materialisation and toggle functions live in lib/sandbox-mount.sh (cycle-130
# Task 1.6, shared with pipeline-run.sh); the arm is resolved first because
# loa_mount: false skips the prompt surface entirely.
eval_dir="$WORKSPACE/.eval"
mkdir -p "$eval_dir"

# --- 2b. control arm (cycle-129 FR-2) -----------------------------------------
ARM_MODE=false
[[ -n "${LOA_EVAL_ARM+x}" ]] && ARM_MODE=true
ARM="${LOA_EVAL_ARM:-baseline}"
[[ "$ARM" =~ ^[a-z][a-z0-9_]{0,63}$ ]] || { echo "ERROR: invalid LOA_EVAL_ARM '$ARM'" >&2; exit 2; }

# The arm's toggles: explicit JSON, else the suite's arms[] / ab.arms[] entry.
resolve_toggles() {
  # audit r1 DISS-C-001: toggles exist only in arm mode (LOA_EVAL_ARM set); a stale
  # LOA_EVAL_ARM_TOGGLES in a non-arm environment is ignored, and the baseline arm
  # never carries toggles.
  if [[ "$ARM_MODE" != "true" ]]; then
    [[ -z "${LOA_EVAL_ARM_TOGGLES:-}" ]] || echo "WARN: LOA_EVAL_ARM_TOGGLES is set but LOA_EVAL_ARM is not: ignored (not an arm run)" >&2
    printf '{}'; return 0
  fi
  if [[ -n "${LOA_EVAL_ARM_TOGGLES:-}" ]]; then
    jq -ce 'if type == "object" then . else error("not an object") end' <<<"$LOA_EVAL_ARM_TOGGLES" 2>/dev/null \
      || { echo "ERROR: LOA_EVAL_ARM_TOGGLES is not a JSON object" >&2; return 2; }
    if [[ "$ARM" == "baseline" && "$(jq -c 'length' <<<"$LOA_EVAL_ARM_TOGGLES")" != "0" ]]; then
      echo "ERROR: the baseline arm takes no toggles (LOA_EVAL_ARM_TOGGLES=$LOA_EVAL_ARM_TOGGLES)" >&2; return 2
    fi
    return 0
  fi
  local suite_file="${LOA_EVAL_SUITE_FILE:-}"
  if [[ -z "$suite_file" ]]; then
    local tdir; tdir="$(basename "$(dirname "$TASK_YAML")")"
    [[ -f "$REPO_ROOT/evals/suites/$tdir.yaml" ]] && suite_file="$REPO_ROOT/evals/suites/$tdir.yaml"
  fi
  resolve_arm_toggles "$ARM" "$suite_file"
}
ARM_TOGGLES="$(resolve_toggles)" || exit 2

# cycle-130: sprint_plan and context_resets edit the phase set of the pipeline
# executor; the single-skill path has no phases, so they cannot take effect here.
for k in sprint_plan context_resets; do
  if [[ "$(K="$k" jq -r 'has(env.K)' <<<"$ARM_TOGGLES")" == "true" ]]; then
    echo "ERROR: arm '$ARM' toggle $k applies to the pipeline executor (pipeline-run.sh) only" >&2; exit 2
  fi
done
LOA_MOUNT=true
[[ "$(jq -r 'if has("loa_mount") then (.loa_mount | tostring) else "true" end' <<<"$ARM_TOGGLES")" == "false" ]] && LOA_MOUNT=false

skill_dst="$WORKSPACE/.claude/skills/$skill"
if [[ "$LOA_MOUNT" == "true" ]]; then
  ARM_EVIDENCE_FILE=/dev/null mount_prompt_surface "$WORKSPACE" "$PROMPT_TREE" "$skill" || exit 2
fi

# Toggles hit the sandbox copy only, after every materialisation step; each is
# verified and one that cannot take effect is exit 2 before the executor starts.
# An operator's gate override never reaches the executor, baseline or arm (audit LOW-A3):
# only the gates: false toggle (apply_arm_toggles) sets it again.
unset LOA_ADVERSARIAL_REVIEW_ENFORCE
arm_ev_file="$(mktemp "$eval_dir/.arm-evidence.XXXXXX")"
ARM_EVIDENCE_FILE="$arm_ev_file" apply_arm_toggles "$WORKSPACE" "$ARM_TOGGLES" "$ARM" || { rm -f "$arm_ev_file"; exit 2; }
# The sandbox manifest is regenerated after the toggles so no integrity reader
# inside it reports Tampered (DEC-0421); arm mode only, when a .claude/ exists.
if [[ "$ARM_MODE" == "true" && -d "$WORKSPACE/.claude" ]]; then
  ARM_EVIDENCE_FILE="$arm_ev_file" regen_sandbox_manifest "$WORKSPACE" || { rm -f "$arm_ev_file"; exit 2; }
fi
ARM_EVIDENCE="$(jq -Rn '[inputs | select(length > 0) | capture("^(?<k>[^=]+)=(?<v>.*)$") | {(.k): .v}] | add // {}' < "$arm_ev_file")"
# the gate-enforcement value the executor environment carries at launch (recorded in executor.json)
REVIEW_ENFORCE="unset"
[[ -n "${LOA_ADVERSARIAL_REVIEW_ENFORCE+x}" ]] && REVIEW_ENFORCE="$LOA_ADVERSARIAL_REVIEW_ENFORCE"
rm -f "$arm_ev_file"

# Skill body without the YAML frontmatter → the appended system prompt. Read
# from the (toggled) sandbox copy so an arm reaches the system prompt too.
if [[ "$LOA_MOUNT" == "true" ]]; then
  awk 'BEGIN{fm=0} NR==1 && $0=="---"{fm=1; next} fm==1 && $0=="---"{fm=2; next} fm!=1{print}' \
    "$skill_dst/SKILL.md" > "$eval_dir/skill-prompt.md"
fi

# Prompt-tree identity (what the A/B is actually varying).
prompt_tree_sha="$(git -C "$PROMPT_TREE" rev-parse HEAD:.claude 2>/dev/null || echo unknown)"
prompt_tree_commit="$(git -C "$PROMPT_TREE" rev-parse HEAD 2>/dev/null || echo unknown)"
# audit r1 DISS-C-009: a declared source commit is a hex id and, when the prompt tree's
# HEAD is known, the same commit — otherwise two trials from different trees could
# present one source_commit and pass compare.sh's skew check.
if [[ -n "${LOA_EVAL_SOURCE_COMMIT:-}" ]]; then
  [[ "$LOA_EVAL_SOURCE_COMMIT" =~ ^[0-9a-f]{7,40}$ ]] \
    || { echo "ERROR: LOA_EVAL_SOURCE_COMMIT is not a hex commit id" >&2; exit 2; }
  if [[ "$prompt_tree_commit" != "unknown" && "$prompt_tree_commit" != "$LOA_EVAL_SOURCE_COMMIT"* ]]; then
    echo "ERROR: LOA_EVAL_SOURCE_COMMIT ($LOA_EVAL_SOURCE_COMMIT) is not the prompt tree's HEAD ($prompt_tree_commit)" >&2; exit 2
  fi
fi
prompt_tree_dirty=false
if [[ -n "$(git -C "$PROMPT_TREE" status --porcelain -- .claude 2>/dev/null)" ]]; then
  prompt_tree_dirty=true
fi

# Effort: env > task > skill frontmatter > none; invalid → none.
resolve_effort() {
  local cand="${EVAL_EFFORT:-}"
  if [[ -z "$cand" ]]; then
    cand="$(yq -r '.agent.effort // ""' "$TASK_YAML")"
  fi
  if [[ ( -z "$cand" || "$cand" == "null" ) && "$LOA_MOUNT" == "true" ]]; then
    cand="$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}' "$skill_src/SKILL.md" \
      | yq -r '.effort // ""' 2>/dev/null || true)"
  fi
  case "$cand" in
    low|medium|high|xhigh|max) printf '%s' "$cand" ;;
    *) printf '' ;;
  esac
}
effort="$(resolve_effort)"
# cycle-130: an arm's effort toggle is the treatment and overrides every other source
arm_effort="$(jq -r '.effort // ""' <<<"$ARM_TOGGLES")"
# audit LOW-A1: the value reaches argv, so it is whitelisted here too (not only in the library)
case "$arm_effort" in ""|low|medium|high|xhigh|max) ;; *) echo "ERROR: arm '$ARM' toggle effort='$arm_effort' is not low|medium|high|xhigh|max" >&2; exit 2 ;; esac
[[ -n "$arm_effort" ]] && effort="$arm_effort"

prompt="$(yq -r '.prompt // ""' "$TASK_YAML")"
[[ -n "$prompt" && "$prompt" != "null" ]] || { echo "ERROR: task has no prompt" >&2; exit 2; }

# --- 3. run ------------------------------------------------------------------
argv=(
  "$CLAUDE_BIN" -p "$prompt"
  --output-format stream-json --verbose
  --model "$MODEL"
  --restricted --tools "Read,Grep,Glob,Write"
  --permission-mode acceptEdits
)
# loa_mount: false (cycle-130 a0_bare): the task prompt only, no appended skill prompt
[[ "$LOA_MOUNT" == "true" ]] && argv+=(--append-system-prompt-file "$eval_dir/skill-prompt.md")
argv+=(--max-turns "$MAX_TURNS")
[[ -n "$effort" ]] && argv+=(--effort "$effort")

events="$eval_dir/events.jsonl"
stderr_log="$eval_dir/agent-stderr.log"
start_ms="$(date +%s%N | cut -c1-13)"
rc=0
(
  cd "$WORKSPACE" || exit 2
  export LOA_MODELINV_LOG_PATH="$eval_dir/model-invoke.jsonl"
  export LOA_COST_LEDGER_PATH="$eval_dir/cost-ledger.jsonl"
  export EVAL_MODEL="$MODEL"
  # sprint-237 audit HIGH-001: the CLI keeps HOME (its own credentials live there)
  # and PATH (its toolchain); the operator's other credentials are not the agent
  # under test's business, and its temp files stay inside the sandbox.
  unset GH_TOKEN GITHUB_TOKEN OPENAI_API_KEY AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  # cycle-129: an executor started from inside a Claude Code session inherits
  # that session's coupling (child-session flag, session id, messaging socket,
  # agent teams) and its subagent model (the sprint-255 driver session carried
  # CLAUDE_CODE_SUBAGENT_MODEL=opus). Decouple the session and pin every
  # auxiliary model to the executor model. (A safeguard-refusal fallback to
  # another model is a separate CLI behaviour, recorded below as
  # refusal_fallbacks; no environment setting turns it off.)
  unset CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_SESSION_ID CLAUDE_CODE_MESSAGING_SOCKET \
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS CLAUDE_CODE_SESSION_ATTENDED
  export CLAUDE_CODE_SUBAGENT_MODEL="$MODEL"
  mkdir -p "$eval_dir/tmp" && export TMPDIR="$eval_dir/tmp"
  exec timeout --signal=TERM --kill-after=15 "$TIMEOUT_S" "${argv[@]}"
) > "$events" 2> "$stderr_log" || rc=$?
end_ms="$(date +%s%N | cut -c1-13)"
duration_ms=$(( end_ms - start_ms ))

# --- 4. record ---------------------------------------------------------------
# The last `result` event is the CLI's summary (absent on crash/timeout).
result_json="$(grep -E '^\{.*"type" *: *"result"' "$events" 2>/dev/null | tail -1 || true)"
if [[ -z "$result_json" ]] || ! jq -e . >/dev/null 2>&1 <<<"$result_json"; then
  result_json='{"type":"result","subtype":"missing","is_error":true}'
fi
printf '%s\n' "$result_json" > "$eval_dir/agent-output.json"

# Ordered tool writes from the transcript (Write/Edit/MultiEdit/NotebookEdit).
tool_writes="$(jq -c '
  select(.type=="assistant") | .message.content[]? |
  select(.type=="tool_use" and (.name=="Write" or .name=="Edit" or .name=="MultiEdit" or .name=="NotebookEdit")) |
  {tool:.name, path:(.input.file_path // .input.notebook_path // "")}
' "$events" 2>/dev/null | jq -sc 'to_entries | map({seq:(.key+1), tool:.value.tool, path:.value.path})' 2>/dev/null || echo '[]')"
[[ -n "$tool_writes" ]] || tool_writes='[]'

# cycle-129: a safeguard refusal makes the CLI retry the session on another
# model (system/model_refusal_fallback); the arm run must see it, because the
# output after it is not the requested executor's.
refusal_fallbacks="$(jq -c 'select(.type=="system" and .subtype=="model_refusal_fallback")
  | {from: (.original_model // null), to: (.fallback_model // null), category: (.api_refusal_category // null),
     scope: (.scope // null)}' "$events" 2>/dev/null | jq -sc '.' 2>/dev/null || echo '[]')"
[[ -n "$refusal_fallbacks" ]] || refusal_fallbacks='[]'

is_error="$(jq -r '.is_error // false' <<<"$result_json")"
[[ $rc -ne 0 ]] && is_error=true

jq -n \
  --arg skill "$skill" \
  --arg model_requested "$MODEL" \
  --arg effort "$effort" \
  --arg prompt_tree "$PROMPT_TREE" \
  --arg prompt_tree_sha "$prompt_tree_sha" \
  --arg prompt_tree_commit "$prompt_tree_commit" \
  --argjson prompt_tree_dirty "$prompt_tree_dirty" \
  --arg run_id "$RUN_ID" \
  --arg trial_id "$TRIAL_ID" \
  --argjson rc "$rc" \
  --argjson is_error "$is_error" \
  --argjson duration_ms "$duration_ms" \
  --argjson result "$result_json" \
  --argjson tool_writes "$tool_writes" \
  --arg arm "$ARM" \
  --argjson arm_toggles "$ARM_TOGGLES" \
  --argjson arm_evidence "$ARM_EVIDENCE" \
  --arg source_commit "${LOA_EVAL_SOURCE_COMMIT:-$prompt_tree_commit}" \
  --argjson refusal_fallbacks "$refusal_fallbacks" \
  --arg review_enforce "$REVIEW_ENFORCE" \
  '
  def norm_usage(u): {
    input_tokens: (u.input_tokens // u.inputTokens // 0),
    output_tokens: (u.output_tokens // u.outputTokens // 0),
    cache_creation_input_tokens: (u.cache_creation_input_tokens // u.cacheCreationInputTokens // 0),
    cache_read_input_tokens: (u.cache_read_input_tokens // u.cacheReadInputTokens // 0)
  };
  ($result.modelUsage // {}) as $mu |
  # the model that produced the output: the modelUsage entry with the most
  # output tokens (a haiku helper call must not be mis-attributed — the
  # framework-review 2026-09-17 rec 5 class), else the requested id.
  (if ($mu | length) > 0
     then ($mu | to_entries | max_by(.value.outputTokens // .value.output_tokens // 0) | .key)
     else $model_requested end) as $model_id |
  {
    schema_version: 1,
    skill: $skill,
    run_id: $run_id,
    trial_id: $trial_id,
    model_requested: $model_requested,
    model_id: $model_id,
    effort: $effort,
    prompt_tree: $prompt_tree,
    prompt_tree_sha: $prompt_tree_sha,
    prompt_tree_commit: $prompt_tree_commit,
    prompt_tree_dirty: $prompt_tree_dirty,
    exit_code: $rc,
    is_error: $is_error,
    duration_ms: $duration_ms,
    num_turns: ($result.num_turns // 0),
    total_cost_usd: ($result.total_cost_usd // 0),
    usage: norm_usage($result.usage // {}),
    models_used: ($mu | with_entries(.value = (.value.outputTokens // .value.output_tokens // 0))),
    refusal_fallbacks: $refusal_fallbacks,
    tool_writes: $tool_writes,
    arm: $arm,
    arm_toggles: $arm_toggles,
    arm_evidence: $arm_evidence,
    source_commit: $source_commit,
    adversarial_review_enforce: $review_enforce
  }' > "$eval_dir/executor.json"

if [[ $rc -ne 0 ]]; then
  echo "execute-agent: CLI exited $rc (see $stderr_log)" >&2
  exit 1
fi
exit 0
