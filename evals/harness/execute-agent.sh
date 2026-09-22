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
#              --model $EVAL_MODEL [--effort <e>] --allowed-tools Read,Grep,Glob,Write
#              (--permission-mode acceptEdits also admits Edit/MultiEdit, which is why the
#              transcript extractor below records them; the tool list is the SDD's fixed set)
#              --permission-mode acceptEdits --append-system-prompt-file <skill-prompt>
#              --max-turns $EVAL_MAX_TURNS
#      cwd = sandbox; env-isolated (LOA_MODELINV_LOG_PATH / LOA_COST_LEDGER_PATH
#      point into <ws>/.eval/, FR-6); wall-clock bounded by --timeout.
#      Effort resolution: EVAL_EFFORT > `.agent.effort` > the skill's
#      frontmatter `effort:` in the prompt tree > none. An invalid level is
#      dropped (no flag), mirroring model-adapter.sh resolve_effort().
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
# Tested by evals/tests/execute-agent.bats.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TASK_YAML=""
WORKSPACE=""
RUN_ID=""
TRIAL_ID=""
TIMEOUT_S=900

usage() {
  sed -n '2,/^# =====.*$/p' "$0" | sed -n '2,60p' | sed 's/^# \{0,1\}//' >&2
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
eval_dir="$WORKSPACE/.eval"
mkdir -p "$eval_dir" "$WORKSPACE/.claude/skills" "$WORKSPACE/.claude/loa"

# Whole skill dir (resources included) so guarded reads inside the skill resolve.
skill_dst="$WORKSPACE/.claude/skills/$skill"
mkdir -p "$skill_dst"
cp -a "$skill_src/." "$skill_dst/"
if [[ -f "$PROMPT_TREE/.claude/loa/CLAUDE.loa.md" ]]; then
  cp "$PROMPT_TREE/.claude/loa/CLAUDE.loa.md" "$WORKSPACE/.claude/loa/CLAUDE.loa.md"
fi
if [[ -d "$PROMPT_TREE/.claude/rules" ]]; then
  mkdir -p "$WORKSPACE/.claude/rules"
  cp -a "$PROMPT_TREE/.claude/rules/." "$WORKSPACE/.claude/rules/"
fi
printf '@.claude/loa/CLAUDE.loa.md\n' > "$WORKSPACE/CLAUDE.md"

# Skill body without the YAML frontmatter → the appended system prompt.
awk 'BEGIN{fm=0} NR==1 && $0=="---"{fm=1; next} fm==1 && $0=="---"{fm=2; next} fm!=1{print}' \
  "$skill_src/SKILL.md" > "$eval_dir/skill-prompt.md"

# Prompt-tree identity (what the A/B is actually varying).
prompt_tree_sha="$(git -C "$PROMPT_TREE" rev-parse HEAD:.claude 2>/dev/null || echo unknown)"
prompt_tree_commit="$(git -C "$PROMPT_TREE" rev-parse HEAD 2>/dev/null || echo unknown)"
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
  if [[ -z "$cand" || "$cand" == "null" ]]; then
    cand="$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}' "$skill_src/SKILL.md" \
      | yq -r '.effort // ""' 2>/dev/null || true)"
  fi
  case "$cand" in
    low|medium|high|xhigh|max) printf '%s' "$cand" ;;
    *) printf '' ;;
  esac
}
effort="$(resolve_effort)"

prompt="$(yq -r '.prompt // ""' "$TASK_YAML")"
[[ -n "$prompt" && "$prompt" != "null" ]] || { echo "ERROR: task has no prompt" >&2; exit 2; }

# --- 3. run ------------------------------------------------------------------
argv=(
  "$CLAUDE_BIN" -p "$prompt"
  --output-format stream-json --verbose
  --model "$MODEL"
  --allowed-tools "Read,Grep,Glob,Write"
  --permission-mode acceptEdits
  --append-system-prompt-file "$eval_dir/skill-prompt.md"
  --max-turns "$MAX_TURNS"
)
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
    tool_writes: $tool_writes
  }' > "$eval_dir/executor.json"

if [[ $rc -ne 0 ]]; then
  echo "execute-agent: CLI exited $rc (see $stderr_log)" >&2
  exit 1
fi
exit 0
