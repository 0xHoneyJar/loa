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
#   step and immediately before the executor starts; each is verified absent
#   afterwards and a toggle that cannot take effect is exit 2 (an arm never
#   silently runs as its baseline):
#     companion_voice: false         flatline_protocol.{code_review,security_audit}.companion_voice=false
#                                    in <ws>/.loa.config.yaml (yq)
#     karpathy_block: false          '## Karpathy Principles' section out of
#                                    <ws>/.claude/loa/CLAUDE.loa.md; Karpathy rows
#                                    out of <ws>/.claude/data/constraints.json if present
#     rule_files: false              stash-safety.md, skill-invariants.md out of <ws>/.claude/rules/
#     audit_delta_instruction: false the paragraph containing "look for what the
#                                    review did not", else "Confirm the review's demotions
#                                    independently", out of the sandbox auditing-security/SKILL.md
#   The appended skill prompt (.eval/skill-prompt.md) is derived from the
#   toggled sandbox SKILL.md. executor.json records arm, arm_toggles,
#   arm_evidence and source_commit.
#
# Tested by evals/tests/execute-agent.bats and evals/tests/arm-toggles.bats.
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

# --- 2b. control arm (cycle-129 FR-2) -----------------------------------------
ARM_MODE=false
[[ -n "${LOA_EVAL_ARM+x}" ]] && ARM_MODE=true
ARM="${LOA_EVAL_ARM:-baseline}"
[[ "$ARM" =~ ^[a-z][a-z0-9_]{0,63}$ ]] || { echo "ERROR: invalid LOA_EVAL_ARM '$ARM'" >&2; exit 2; }
if [[ "$ARM_MODE" == "true" && -f "$PROMPT_TREE/.loa.config.yaml" ]]; then
  cp "$PROMPT_TREE/.loa.config.yaml" "$WORKSPACE/.loa.config.yaml"
fi

# The arm's toggles: explicit JSON, else the suite's ab.arms[] entry.
resolve_toggles() {
  if [[ -n "${LOA_EVAL_ARM_TOGGLES:-}" ]]; then
    jq -ce 'if type == "object" then . else error("not an object") end' <<<"$LOA_EVAL_ARM_TOGGLES" 2>/dev/null \
      || { echo "ERROR: LOA_EVAL_ARM_TOGGLES is not a JSON object" >&2; return 2; }
    return 0
  fi
  local suite_file="${LOA_EVAL_SUITE_FILE:-}"
  if [[ -z "$suite_file" ]]; then
    local tdir; tdir="$(basename "$(dirname "$TASK_YAML")")"
    [[ -f "$REPO_ROOT/evals/suites/$tdir.yaml" ]] && suite_file="$REPO_ROOT/evals/suites/$tdir.yaml"
  fi
  local t="" found=0
  if [[ -n "$suite_file" && -f "$suite_file" ]]; then
    found="$(ARM="$ARM" yq '[.ab.arms[]? | select(.id == strenv(ARM))] | length' "$suite_file" 2>/dev/null || echo 0)"
    [[ "$found" =~ ^[0-9]+$ ]] || found=0
    if [[ "$found" -gt 0 ]]; then
      t="$(ARM="$ARM" yq -o=json -I=0 '[.ab.arms[] | select(.id == strenv(ARM))][0].toggles // {}' "$suite_file" 2>/dev/null)"
    fi
  fi
  if [[ "$found" -eq 0 || -z "$t" || "$t" == "null" ]]; then
    [[ "$ARM" == "baseline" ]] && { printf '{}'; return 0; }
    echo "ERROR: arm '$ARM' is not declared in ${suite_file:-any suite} (ab.arms[])" >&2
    return 2
  fi
  printf '%s' "$t"
}
ARM_TOGGLES="$(resolve_toggles)" || exit 2

# Remove the markdown section that starts at the exact heading line $2 (up to
# the next level-2 heading) from file $1. Prints the number of lines removed.
_drop_md_section() {
  local f="$1" heading="$2" tmp
  tmp="$(mktemp "$eval_dir/.arm.XXXXXX")"
  awk -v h="$heading" '
    $0 == h { skip = 1; n++; next }
    skip && /^## / { skip = 0 }
    skip { n++; next }
    { print }
    END { print n + 0 > "/dev/stderr" }' "$f" > "$tmp" 2> "$tmp.n"
  mv "$tmp" "$f"
  cat "$tmp.n"; rm -f "$tmp.n"
}

# Remove the first blank-line-delimited paragraph of $1 that contains one of
# the needles (tried in order, case-insensitive). Writes the removed text to
# $2; exit 1 when no needle matches.
_drop_paragraph() {
  python3 -I - "$1" "$2" "look for what the review did not" "Confirm the review's demotions independently" <<'PY'
import re, sys
path, out = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
paras = re.split(r"(\n[ \t]*\n)", text)
for needle in sys.argv[3:]:
    for i in range(0, len(paras), 2):
        if needle.lower() in paras[i].lower():
            removed = paras[i]
            # drop the paragraph and the separator that follows it
            del paras[i:i + 2]
            open(path, "w", encoding="utf-8").write("".join(paras))
            open(out, "w", encoding="utf-8").write(removed + "\n")
            sys.exit(0)
sys.exit(1)
PY
}

ARM_EVIDENCE='{}'
_evidence() { ARM_EVIDENCE="$(jq -c --arg k "$1" --arg v "$2" '. + {($k): $v}' <<<"$ARM_EVIDENCE")"; }

apply_toggles() {
  local key val
  while IFS=$'\t' read -r key val; do
    [[ -n "$key" ]] || continue
    if [[ "$val" != "false" ]]; then
      echo "ERROR: arm '$ARM' toggle $key=$val (only false is defined)" >&2; return 2
    fi
    case "$key" in
      companion_voice)
        local cfg="$WORKSPACE/.loa.config.yaml"
        [[ -f "$cfg" ]] || : > "$cfg"
        yq -i '.flatline_protocol.code_review.companion_voice = false | .flatline_protocol.security_audit.companion_voice = false' "$cfg" \
          || { echo "ERROR: companion_voice toggle: yq failed on the sandbox config" >&2; return 2; }
        [[ "$(yq -r '.flatline_protocol.code_review.companion_voice' "$cfg")" == "false" ]] \
          || { echo "ERROR: companion_voice toggle did not take effect" >&2; return 2; }
        _evidence companion_voice "flatline_protocol.{code_review,security_audit}.companion_voice=false"
        ;;
      karpathy_block)
        local k="$WORKSPACE/.claude/loa/CLAUDE.loa.md" n
        [[ -f "$k" ]] || { echo "ERROR: karpathy_block toggle: no sandbox CLAUDE.loa.md" >&2; return 2; }
        n="$(_drop_md_section "$k" '## Karpathy Principles')"
        if [[ "${n:-0}" -eq 0 ]] || grep -q '^## Karpathy Principles' "$k"; then
          echo "ERROR: karpathy_block toggle: no '## Karpathy Principles' section removed" >&2; return 2
        fi
        local cj="$WORKSPACE/.claude/data/constraints.json"
        if [[ -f "$cj" ]]; then
          jq '(.constraints // []) |= map(select((tostring | test("karpathy"; "i")) | not))' "$cj" > "$cj.tmp" && mv "$cj.tmp" "$cj"
        fi
        _evidence karpathy_block "removed ${n} lines from CLAUDE.loa.md"
        ;;
      rule_files)
        local r gone=""
        for r in stash-safety.md skill-invariants.md; do
          if [[ -e "$WORKSPACE/.claude/rules/$r" ]]; then rm -f "$WORKSPACE/.claude/rules/$r"; gone="$gone $r"; fi
          [[ ! -e "$WORKSPACE/.claude/rules/$r" ]] || { echo "ERROR: rule_files toggle: $r still present" >&2; return 2; }
        done
        _evidence rule_files "removed:${gone:- none present}"
        ;;
      audit_delta_instruction)
        local s="$WORKSPACE/.claude/skills/auditing-security/SKILL.md"
        [[ -f "$s" ]] || { echo "ERROR: audit_delta_instruction toggle: no sandbox auditing-security/SKILL.md" >&2; return 2; }
        _drop_paragraph "$s" "$eval_dir/arm-removed.txt" \
          || { echo "ERROR: audit_delta_instruction toggle: no delta paragraph found in the sandbox SKILL.md" >&2; return 2; }
        _evidence audit_delta_instruction "removed $(wc -c < "$eval_dir/arm-removed.txt" | tr -d ' ') bytes (.eval/arm-removed.txt)"
        ;;
      *) echo "ERROR: arm '$ARM' declares unknown toggle '$key'" >&2; return 2 ;;
    esac
  done < <(jq -r 'to_entries[] | [.key, (.value | tostring)] | @tsv' <<<"$ARM_TOGGLES")
  return 0
}
apply_toggles || exit 2

# Skill body without the YAML frontmatter → the appended system prompt. Read
# from the (toggled) sandbox copy so an arm reaches the system prompt too.
awk 'BEGIN{fm=0} NR==1 && $0=="---"{fm=1; next} fm==1 && $0=="---"{fm=2; next} fm!=1{print}' \
  "$skill_dst/SKILL.md" > "$eval_dir/skill-prompt.md"

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
  --restricted --tools "Read,Grep,Glob,Write"
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
    source_commit: $source_commit
  }' > "$eval_dir/executor.json"

if [[ $rc -ne 0 ]]; then
  echo "execute-agent: CLI exited $rc (see $stderr_log)" >&2
  exit 1
fi
exit 0
