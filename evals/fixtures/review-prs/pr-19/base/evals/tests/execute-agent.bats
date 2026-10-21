#!/usr/bin/env bats
# =============================================================================
# evals/tests/execute-agent.bats — cycle-124 Sprint 3 Task 3.2 (FR-9 / SDD §3.6)
#
# evals/harness/execute-agent.sh is the agent-execution step at the
# run-eval.sh:379 slot. It is gated on a task's `.agent.skill`; it
# materializes the prompt surface (skill body without frontmatter, CLAUDE.md
# → CLAUDE.loa.md, rules) from $EVAL_PROMPT_TREE into the sandbox, runs the
# headless CLI with a fixed tool set, and records executor.json (model id the
# CLI echoed, usage, prompt_tree_sha, ordered tool writes). The CLI is
# replaced by evals/tests/fixtures/claude-stub.sh here.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  EXEC="$REPO_ROOT/evals/harness/execute-agent.sh"
  STUB="$TESTS_DIR/fixtures/claude-stub.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/ea.XXXXXX")"
  WS="$T/ws"
  mkdir -p "$WS"
  ( cd "$WS" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )
  export EVAL_CLAUDE_BIN="$STUB"
  export EVAL_MODEL="claude-sonnet-5"
  export EVAL_PROMPT_TREE="$REPO_ROOT"
  export STUB_ARGV_FILE="$T/argv"
  export STUB_ENV_FILE="$T/env"
  unset EVAL_EFFORT
  # A task that declares an agent (the executor's gate).
  cat > "$T/task.yaml" <<'YAML'
id: ea-task
schema_version: 1
skill: reviewing-code
category: skill-quality
fixture: hello-world-ts
description: "executor test task"
prompt: "Read REVIEW-INSTRUCTIONS.md and carry it out."
agent:
  skill: reviewing-code
  artifacts: [review.md]
graders:
  - type: code
    script: file-exists.sh
    args: ["review.md"]
YAML
  # The same task without an agent block.
  grep -v -E '^(agent:|  skill: reviewing-code$|  artifacts:)' "$T/task.yaml" > "$T/task-noagent.yaml"
}

teardown() {
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

# Build a throwaway prompt tree with one skill carrying the given frontmatter.
make_tree() {  # make_tree <dir> <effort-line-or-empty>
  local d="$1" eff="$2"
  local sk="$d/.claude/skills/fake-skill"
  mkdir -p "$sk" "$d/.claude/loa" "$d/.claude/rules"
  {
    echo "---"
    echo "name: fake"
    [[ -n "$eff" ]] && echo "$eff"
    echo "---"
    echo "# Fake skill body"
    echo "Do fake things."
  } > "$sk/SKILL.md"
  echo "# loa" > "$d/.claude/loa/CLAUDE.loa.md"
  echo "rule" > "$d/.claude/rules/r.md"
  ( cd "$d" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m tree )
}

@test "EA-1 task without .agent.skill exits 3 and writes nothing" {
  run "$EXEC" --task-yaml "$T/task-noagent.yaml" --workspace "$WS"
  [ "$status" -eq 3 ]
  [ ! -e "$WS/.eval/executor.json" ]
  [ ! -e "$STUB_ARGV_FILE" ]
}

@test "EA-2 materializes the skill body without frontmatter, CLAUDE.md and CLAUDE.loa.md from the prompt tree" {
  run "$EXEC" --task-yaml "$T/task.yaml" --workspace "$WS"
  [ "$status" -eq 0 ]
  [ -f "$WS/.eval/skill-prompt.md" ]
  # frontmatter stripped: body == SKILL.md after the closing '---'
  awk 'BEGIN{fm=0} NR==1 && $0=="---"{fm=1; next} fm==1 && $0=="---"{fm=2; next} fm!=1{print}' \
    "$REPO_ROOT/.claude/skills/reviewing-code/SKILL.md" > "$T/expected-body.md"
  cmp -s "$T/expected-body.md" "$WS/.eval/skill-prompt.md"
  ! grep -q '^name: review-sprint' "$WS/.eval/skill-prompt.md"
  grep -qF '@.claude/loa/CLAUDE.loa.md' "$WS/CLAUDE.md"
  cmp -s "$REPO_ROOT/.claude/loa/CLAUDE.loa.md" "$WS/.claude/loa/CLAUDE.loa.md"
  [ -f "$WS/.claude/skills/reviewing-code/SKILL.md" ]
}

@test "EA-3 argv carries the confined fixed tool set (--restricted --tools), permission mode, model, stream-json and the system-prompt file" {
  run "$EXEC" --task-yaml "$T/task.yaml" --workspace "$WS"
  [ "$status" -eq 0 ]
  local joined; joined="$(cat "$STUB_ARGV_FILE")"
  grep -qx -- '--model' <<<"$joined"
  grep -qx -- 'claude-sonnet-5' <<<"$joined"
  # sprint-237 audit HIGH-001: --allowed-tools only ADDS allow rules on top of the
  # operator's ~/.claude settings (user Bash(...) rules leaked into the A/B arms) and
  # leaves the file tools unconfined; --restricted --tools names the set exactly,
  # ignores user/project settings and confines Read/Grep/Glob/Write to the sandbox.
  grep -qx -- '--restricted' <<<"$joined"
  grep -qx -- '--tools' <<<"$joined"
  grep -qx -- 'Read,Grep,Glob,Write' <<<"$joined"
  ! grep -qx -- '--allowed-tools' <<<"$joined"
  grep -qx -- '--permission-mode' <<<"$joined"
  grep -qx -- 'acceptEdits' <<<"$joined"
  grep -qx -- '--output-format' <<<"$joined"
  grep -qx -- 'stream-json' <<<"$joined"
  grep -qx -- '--append-system-prompt-file' <<<"$joined"
  grep -q -- '/.eval/skill-prompt.md$' <<<"$joined"
  grep -qx -- '-p' <<<"$joined"
  grep -qxF -- 'Read REVIEW-INSTRUCTIONS.md and carry it out.' <<<"$joined"
  # the CLI ran with cwd = workspace
  grep -q "^PWD=$WS\$" "$STUB_ENV_FILE"
}

@test "EA-10 env hygiene: non-CLI credentials are absent and TMPDIR sits under the sandbox; HOME stays (the CLI reads its own credentials there)" {
  export GH_TOKEN=leak-gh GITHUB_TOKEN=leak-github OPENAI_API_KEY=leak-openai AWS_SECRET_ACCESS_KEY=leak-aws
  run "$EXEC" --task-yaml "$T/task.yaml" --workspace "$WS"
  [ "$status" -eq 0 ]
  grep -q '^GH_TOKEN=$' "$STUB_ENV_FILE"
  grep -q '^GITHUB_TOKEN=$' "$STUB_ENV_FILE"
  grep -q '^OPENAI_API_KEY=$' "$STUB_ENV_FILE"
  grep -q '^AWS_SECRET_ACCESS_KEY=$' "$STUB_ENV_FILE"
  grep -q "^TMPDIR=$WS/.eval/tmp\$" "$STUB_ENV_FILE"
  [ -d "$WS/.eval/tmp" ]
  grep -q "^HOME=$HOME\$" "$STUB_ENV_FILE"
}

@test "EA-4 effort: skill frontmatter forwarded, EVAL_EFFORT overrides, absent or invalid yields no flag" {
  local tree="$T/tree"
  make_tree "$tree" "effort: xhigh"
  sed -i 's/reviewing-code/fake-skill/g' "$T/task.yaml"
  export EVAL_PROMPT_TREE="$tree"

  run "$EXEC" --task-yaml "$T/task.yaml" --workspace "$WS"
  [ "$status" -eq 0 ]
  grep -qx -- '--effort' "$STUB_ARGV_FILE"
  grep -qx -- 'xhigh' "$STUB_ARGV_FILE"
  [ "$(jq -r '.effort' "$WS/.eval/executor.json")" = "xhigh" ]

  EVAL_EFFORT=low run "$EXEC" --task-yaml "$T/task.yaml" --workspace "$WS"
  [ "$status" -eq 0 ]
  grep -qx -- 'low' "$STUB_ARGV_FILE"
  ! grep -qx -- 'xhigh' "$STUB_ARGV_FILE"

  local tree2="$T/tree2"
  make_tree "$tree2" "effort: bogus"
  EVAL_PROMPT_TREE="$tree2" run "$EXEC" --task-yaml "$T/task.yaml" --workspace "$WS"
  [ "$status" -eq 0 ]
  ! grep -qx -- '--effort' "$STUB_ARGV_FILE"
  [ "$(jq -r '.effort' "$WS/.eval/executor.json")" = "" ]

  local tree3="$T/tree3"
  make_tree "$tree3" ""
  EVAL_PROMPT_TREE="$tree3" run "$EXEC" --task-yaml "$T/task.yaml" --workspace "$WS"
  [ "$status" -eq 0 ]
  ! grep -qx -- '--effort' "$STUB_ARGV_FILE"
}

@test "EA-5 executor.json records the CLI-echoed model id, usage, prompt_tree_sha and ordered tool writes" {
  local tree="$T/tree"
  make_tree "$tree" ""
  sed -i 's/reviewing-code/fake-skill/g' "$T/task.yaml"
  EVAL_PROMPT_TREE="$tree" run "$EXEC" --task-yaml "$T/task.yaml" --workspace "$WS"
  [ "$status" -eq 0 ]
  local j="$WS/.eval/executor.json"
  [ "$(jq -r '.model_requested' "$j")" = "claude-sonnet-5" ]
  [ "$(jq -r '.model_id' "$j")" = "claude-sonnet-5-20260401" ]
  [ "$(jq -r '.usage.output_tokens' "$j")" = "42" ]
  [ "$(jq -r '.usage.input_tokens' "$j")" = "100" ]
  [ "$(jq -r '.num_turns' "$j")" = "3" ]
  [ "$(jq -r '.is_error' "$j")" = "false" ]
  [ "$(jq -r '.exit_code' "$j")" = "0" ]
  [ "$(jq -c '[.tool_writes[].path]' "$j")" = '["tests/test_x.py","src/x.py"]' ]
  local want; want="$(git -C "$tree" rev-parse HEAD:.claude)"
  [ "$(jq -r '.prompt_tree_sha' "$j")" = "$want" ]
  [ "$(jq -r '.prompt_tree_commit' "$j")" = "$(git -C "$tree" rev-parse HEAD)" ]
  [ "$(jq -r '.prompt_tree_dirty' "$j")" = "false" ]
  [ -f "$WS/.eval/agent-output.json" ]
  [ "$(jq -r '.type' "$WS/.eval/agent-output.json")" = "result" ]
}

@test "EA-6 env isolation: both ledger paths point inside the workspace" {
  run "$EXEC" --task-yaml "$T/task.yaml" --workspace "$WS"
  [ "$status" -eq 0 ]
  grep -q "^LOA_MODELINV_LOG_PATH=$WS/.eval/" "$STUB_ENV_FILE"
  grep -q "^LOA_COST_LEDGER_PATH=$WS/.eval/" "$STUB_ENV_FILE"
}

@test "EA-7 CLI failure: exit 1 and executor.json carries is_error + exit_code" {
  STUB_EXIT=7 run "$EXEC" --task-yaml "$T/task.yaml" --workspace "$WS"
  [ "$status" -eq 1 ]
  [ "$(jq -r '.exit_code' "$WS/.eval/executor.json")" = "7" ]
  [ "$(jq -r '.is_error' "$WS/.eval/executor.json")" = "true" ]
}

@test "EA-8 run-eval.sh: an agent task row carries executor + model_version and keeps the review artifact" {
  export STUB_WRITE_1='review.md::All good\n\n## Overall Assessment\n\nClean.\n\n<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-0","ts":"2026-01-01T00:00:00Z"} -->\n'
  run "$REPO_ROOT/evals/harness/run-eval.sh" --task review-pr-09 --trusted --json
  [ "$status" -eq 0 ]
  local run_id; run_id="$(echo "$output" | jq -r '.meta.run_id')"
  local row; row="$(head -1 "$REPO_ROOT/evals/results/$run_id/results.jsonl")"
  [ "$(echo "$row" | jq -r '.executor.model_id')" = "claude-sonnet-5-20260401" ]
  [ "$(echo "$row" | jq -r '.model_version')" = "claude-sonnet-5-20260401" ]
  [ "$(echo "$row" | jq -r '.status')" = "completed" ]
  [ -f "$REPO_ROOT/evals/results/$run_id/artifacts/review-pr-09/trial-1/review.md" ]
  [ -f "$REPO_ROOT/evals/results/$run_id/artifacts/review-pr-09/trial-1/executor.json" ]
  find "$REPO_ROOT/evals/results/$run_id" -mindepth 1 -delete; rmdir "$REPO_ROOT/evals/results/$run_id"
}

@test "EA-9 run-eval.sh: a task without .agent takes today's exact path (executor never invoked)" {
  run "$REPO_ROOT/evals/harness/run-eval.sh" --task constraint-proc-001-enforced --trusted --json
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  [ ! -e "$STUB_ARGV_FILE" ]
  local run_id; run_id="$(echo "$output" | jq -r '.meta.run_id')"
  [ "$(head -1 "$REPO_ROOT/evals/results/$run_id/results.jsonl" | jq -r '.executor // "absent"')" = "absent" ]
  find "$REPO_ROOT/evals/results/$run_id" -mindepth 1 -delete; rmdir "$REPO_ROOT/evals/results/$run_id"
}
