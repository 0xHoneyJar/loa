#!/usr/bin/env bats
# =============================================================================
# evals/tests/ablation-row.bats — cycle-130 Sprint 258 Task 1.8 (SDD §3.1, §5.8; AC-1.8, PRD AC-6.3)
#
# evals/harness/ablation-row.sh joins a run directory (meta/pipeline.json, eval/
# MODELINV and cost ledgers, dissent envelopes, transcripts), grade.json and the
# batch MANIFEST.json into one runs.jsonl row, and --validate checks rows. The run
# directories are the fixtures under evals/tests/fixtures/ablation-runs/runs/
# (real pipeline-run.sh runs against the stub CLI; rebuilt by regen.sh); each test
# works on a copy.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  ROW="$REPO_ROOT/evals/harness/ablation-row.sh"
  FX="$TESTS_DIR/fixtures/ablation-runs"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/ar.XXXXXX")"
  cp -a "$FX/runs" "$T/runs"
  cp "$FX/MANIFEST.json" "$T/MANIFEST.json"
  BUILD_TASK="$FX/tasks/bf-01/task.yaml" REVIEW_TASK="$FX/tasks/rc-01/task.yaml"
}

teardown() {
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

row() {  # row <run> <task-yaml> [extra args…] → $T/rows.jsonl (appended)
  local run="$1" task="$2"; shift 2
  "$ROW" --run-dir "$T/runs/$run" --task-yaml "$task" --manifest "$T/MANIFEST.json" --out "$T/rows.jsonl" "$@"
}
last() { sed -n '$p' "$T/rows.jsonl"; }
edit_pipe() {  # edit_pipe <run> <jq filter>
  jq "$2" "$T/runs/$1/meta/pipeline.json" > "$T/p.json" && mv "$T/p.json" "$T/runs/$1/meta/pipeline.json"
}

@test "a full graded A1 build row validates and carries the joined fields" {
  row a1-build "$BUILD_TASK"
  run "$ROW" --validate "$T/rows.jsonl"
  [ "$status" -eq 0 ]
  local r; r="$(last)"
  [ "$(jq -r '.arm + " " + .batch + " " + .task_type' <<<"$r")" = "a1_full fixture-batch bug-fix" ]
  [ "$(jq -r '.hidden_test_pass_rate' <<<"$r")" = 0.875 ]
  [ "$(jq -r '.verdict' <<<"$r")" = APPROVED ]
  # a false accuracy stays false (never null)
  [ "$(jq -r '"\(.verdict_accuracy) \(.verdict_accuracy_review) \(.verdict_accuracy_audit)"' <<<"$r")" = "false true false" ]
  [ "$(jq -r '.image_digest + " " + .host_fingerprint' <<<"$r")" = "sha256:fixture-image fp:fixture" ]
  [ "$(jq -r '[.phases[].label] | join(",")' <<<"$r")" = "PLAN,IMPLEMENT,REVIEW,FIX1,AUDIT" ]
  [[ "$(jq -r '.snapshots.implement' <<<"$r")" =~ ^[0-9a-f]{40}$ ]]
  [[ "$(jq -r '.snapshots.fix1' <<<"$r")" =~ ^[0-9a-f]{40}$ ]]
  [ "$(jq -r '.snapshots.fix2' <<<"$r")" = null ]
  [ "$(jq -r '.suite_version' <<<"$r")" = 1 ]
  [ "$(jq -r '.status + " " + (.degraded | tostring)' <<<"$r")" = "completed false" ]
}

@test "effort_effective per phase comes from the sandbox MODELINV rows the phase wrote" {
  row a1-build "$BUILD_TASK"
  local r; r="$(last)"
  [ "$(jq -r '[.phases[] | "\(.label)=\(.effort_effective)"] | join(" ")' <<<"$r")" = "PLAN=null IMPLEMENT=null REVIEW=xhigh FIX1=null AUDIT=xhigh" ]
  [ "$(jq -r '[.phases[] | select(.label == "REVIEW")][0].voice_cost_usd' <<<"$r")" = 0.4 ]
  # cost = Σ result cost (5 phases × 0.5) + Σ ledger (0.4 + 0.3)
  [ "$(jq -r '.cost_usd' <<<"$r")" = 3.2 ]
}

@test "voices_run comes from the dissent envelopes; null for A0 and A4" {
  row a1-build "$BUILD_TASK"
  [ "$(jq -c '.voices_run.review | {planned, completed, quality}' <<<"$(last)")" = '{"planned":2,"completed":2,"quality":"APPROVED"}' ]
  row a3-review "$REVIEW_TASK"
  [ "$(jq -r '"\(.voices_run.review.planned) \(.voices_run.audit.companion_planned)"' <<<"$(last)")" = "1 false" ]
  row a0-build "$BUILD_TASK"
  [ "$(jq -r '.voices_run' <<<"$(last)")" = null ]
  row a4-build "$BUILD_TASK"
  [ "$(jq -r '.voices_run' <<<"$(last)")" = null ]
}

@test "review-catch rows fill the defect fields and leave hidden_tests null" {
  row a3-review "$REVIEW_TASK"
  run "$ROW" --validate "$T/rows.jsonl"
  [ "$status" -eq 0 ]
  local r; r="$(last)"
  [ "$(jq -r '"\(.defects_seeded) \(.defects_caught) \(.defect_catch_rate) \(.flags) \(.false_positives) \(.hidden_tests)"' <<<"$r")" = "3 2 0.6667 4 1 null" ]
}

@test "--validate rejects a row missing any §3.1 field (each field in turn)" {
  row a1-build "$BUILD_TASK"
  local good f fields
  good="$(last)"
  fields="schema_version run_id batch arm task_id task_type trial source_commit suite_manifest_sha256 suite_version host_fingerprint image_digest agy_opt_in started finished phases voices_run hidden_tests hidden_test_pass_rate defects_seeded defects_caught defect_catch_rate flags false_positives verdict verdict_accuracy verdict_accuracy_review verdict_accuracy_audit regressions diff_lines files_changed cost_usd wall_clock_ms tokens_in tokens_out stalls attempts retry_reason degraded degraded_reason status snapshots contaminated zone_violations"
  for f in $fields; do
    jq -c --arg f "$f" 'del(.[$f])' <<<"$good" > "$T/one.jsonl"
    run "$ROW" --validate "$T/one.jsonl" --allow-ungraded
    [ "$status" -eq 1 ] || { echo "field $f: status $status"; return 1; }
    [[ "$output" == *"missing field $f"* ]] || { echo "field $f: $output"; return 1; }
  done
  for f in name session_id model_requested models_used effort_requested effort_effective tokens_in tokens_out cache_read_tokens cache_creation_tokens cost_usd duration_ms num_turns exit refusal_fallbacks; do
    jq -c --arg f "$f" '.phases[0] |= del(.[$f])' <<<"$good" > "$T/one.jsonl"
    run "$ROW" --validate "$T/one.jsonl" --allow-ungraded
    [ "$status" -eq 1 ] && [[ "$output" == *"phases[0]: missing field $f"* ]] || { echo "phase field $f: $output"; return 1; }
  done
}

@test "--validate rejects wrong types and bad enums and names the line number" {
  row a1-build "$BUILD_TASK"
  local good; good="$(last)"
  { echo "$good"; jq -c '.cost_usd = "3.2"' <<<"$good"; } > "$T/two.jsonl"
  run "$ROW" --validate "$T/two.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"two.jsonl:2: field cost_usd has type string"* ]]
  jq -c '.status = "done"' <<<"$good" > "$T/one.jsonl"
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 1 ] && [[ "$output" == *"status done is not one of"* ]]
  jq -c '.task_type = "build"' <<<"$good" > "$T/one.jsonl"
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 1 ] && [[ "$output" == *"task_type build"* ]]
  jq -c '.degraded = true' <<<"$good" > "$T/one.jsonl"
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 1 ] && [[ "$output" == *"degraded without degraded_reason"* ]]
  echo 'not json' > "$T/one.jsonl"
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 1 ]
}

@test "--validate accepts each of the seven status values" {
  row a1-build "$BUILD_TASK"
  local good s; good="$(last)"
  : > "$T/seven.jsonl"
  for s in completed cap_failure agent_error transport_error infrastructure_error interrupted contaminated; do
    jq -c --arg s "$s" '.status = $s' <<<"$good" >> "$T/seven.jsonl"
  done
  run "$ROW" --validate "$T/seven.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"7 rows valid"* ]]
}

@test "an ungraded smoke row has null grade fields; --validate needs --allow-ungraded for it" {
  row a5-build "$BUILD_TASK"
  [ "$(jq -r '"\(.hidden_tests) \(.hidden_test_pass_rate) \(.verdict)"' <<<"$(last)")" = "null null null" ]
  run "$ROW" --validate "$T/rows.jsonl"
  [ "$status" -eq 1 ] && [[ "$output" == *"graded build row has no hidden_tests"* ]]
  run "$ROW" --validate "$T/rows.jsonl" --allow-ungraded
  [ "$status" -eq 0 ]
}

@test "degraded: a model other than the requested one in models_used" {
  edit_pipe a1-build '(.phases[] | select(.label == "IMPLEMENT") | .models_used) = {"global.anthropic.claude-opus-5-5": 10, "claude-sonnet-5": 90}'
  row a1-build "$BUILD_TASK"
  [ "$(jq -r '.degraded' <<<"$(last)")" = true ]
  [[ "$(jq -r '.degraded_reason' <<<"$(last)")" == *"IMPLEMENT: model claude-sonnet-5 used, global.anthropic.claude-opus-5-5 requested"* ]]
}

@test "degraded: the Bedrock region prefix alone is not a different model" {
  edit_pipe a1-build '(.phases[] | select(.label == "IMPLEMENT") | .models_used) = {"us.anthropic.claude-opus-5-5": 90}'
  row a1-build "$BUILD_TASK"
  [ "$(jq -r '.degraded' <<<"$(last)")" = false ]
}

@test "degraded: a refusal fallback" {
  edit_pipe a1-build '(.phases[] | select(.label == "REVIEW") | .refusal_fallbacks) = [{"from": "global.anthropic.claude-fable-5-1", "to": "x"}]'
  row a1-build "$BUILD_TASK"
  [[ "$(jq -r '.degraded_reason' <<<"$(last)")" == *"REVIEW: refusal fallback"* ]]
}

@test "degraded: a MODELINV effort_effective that differs from the effort the hop requested" {
  jq -c '(select(.payload.calling_primitive == "adversarial-review") | .payload.effort_effective) |= "low"' \
    "$T/runs/a1-build/eval/model-invoke.jsonl" > "$T/m" && mv "$T/m" "$T/runs/a1-build/eval/model-invoke.jsonl"
  row a1-build "$BUILD_TASK"
  [ "$(jq -r '.degraded' <<<"$(last)")" = true ]
  [[ "$(jq -r '.degraded_reason' <<<"$(last)")" == *"REVIEW: MODELINV adversarial-review effort xhigh->low"* ]]
  [ "$(jq -r '[.phases[] | select(.label == "REVIEW")][0].effort_effective' <<<"$(last)")" = low ]
}

@test "degraded: a DEGRADED envelope, and an envelope with fewer completed voices than planned" {
  local e="$T/runs/a1-build/sandbox/grimoires/loa/a2a/sprint-1"
  jq '.verdict_quality.status = "DEGRADED"' "$e/adversarial-review.json" > "$T/x" && mv "$T/x" "$e/adversarial-review.json"
  jq '.verdict_quality.voices_succeeded = 1' "$e/adversarial-audit.json" > "$T/x" && mv "$T/x" "$e/adversarial-audit.json"
  row a1-build "$BUILD_TASK"
  [[ "$(jq -r '.degraded_reason' <<<"$(last)")" == *"review envelope verdict_quality DEGRADED"* ]]
  [[ "$(jq -r '.degraded_reason' <<<"$(last)")" == *"audit envelope 1 of 2 voices completed"* ]]
}

@test "arm: from the manifest arm_map or meta/arm, never from sandbox/" {
  # the sandbox claims another arm in every place an agent could write
  echo "a0_bare" > "$T/runs/a1-build/sandbox/arm"
  echo '{"arm": "a0_bare"}' > "$T/runs/a1-build/sandbox/pipeline.json"
  mkdir -p "$T/runs/a1-build/sandbox/.eval" && echo '{"arm": "a0_bare"}' > "$T/runs/a1-build/sandbox/.eval/pipeline.json"
  row a1-build "$BUILD_TASK"
  [ "$(jq -r '.arm' <<<"$(last)")" = a1_full ]
  # without the manifest the arm is meta/arm
  "$ROW" --run-dir "$T/runs/a1-build" --task-yaml "$BUILD_TASK" --out "$T/rows.jsonl"
  [ "$(jq -r '.arm + " " + .batch' <<<"$(last)")" = "a1_full unbatched" ]
  # a manifest that disagrees with meta/arm is refused
  jq '.arm_map["abl-fixture-a1_full-bf-01-t1"] = "a7_effort_medium"' "$T/MANIFEST.json" > "$T/m.json"
  run "$ROW" --run-dir "$T/runs/a1-build" --task-yaml "$BUILD_TASK" --manifest "$T/m.json"
  [ "$status" -eq 2 ] && [[ "$output" == *"arm mismatch"* ]]
}

@test "status: a running record reads interrupted; grade.json contaminated reads contaminated; --status overrides" {
  edit_pipe a5-build '.status = "running" | .finished = null'
  row a5-build "$BUILD_TASK"
  [ "$(jq -r '.status' <<<"$(last)")" = interrupted ]
  jq '.contaminated = {"phase": "IMPLEMENT", "pattern": "hidden", "excerpt_id": 3}' "$T/runs/a1-build/grade.json" > "$T/g" && mv "$T/g" "$T/runs/a1-build/grade.json"
  row a1-build "$BUILD_TASK"
  [ "$(jq -c '[.status, .contaminated]' <<<"$(last)")" = '["contaminated",{"phase":"IMPLEMENT","pattern":"hidden"}]' ]
  row a0-build "$BUILD_TASK" --status transport_error --attempts 2 --retry-reason "socket hang up"
  [ "$(jq -c '[.status, .attempts, .retry_reason]' <<<"$(last)")" = '["transport_error",2,"socket hang up"]' ]
  run "$ROW" --run-dir "$T/runs/a0-build" --task-yaml "$BUILD_TASK" --status finished
  [ "$status" -eq 2 ]
}

@test "zone_violations lists transcript Write/Edit inputs under .claude/" {
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/workspace/.claude/skills/x/SKILL.md"}},{"type":"tool_use","name":"Write","input":{"file_path":"src/app.py"}}]}}' \
    >> "$T/runs/a1-build/transcripts/events-IMPLEMENT.jsonl"
  row a1-build "$BUILD_TASK"
  [ "$(jq -c '.zone_violations.dot_claude_writes' <<<"$(last)")" = '[{"phase":"IMPLEMENT","tool":"Edit","path":"/workspace/.claude/skills/x/SKILL.md"}]' ]
  row a5-build "$BUILD_TASK"
  [ "$(jq -c '.zone_violations.dot_claude_writes' <<<"$(last)")" = '[]' ]
}

@test "--out appends one row per run; every fixture run yields a valid ungraded-or-graded row" {
  local d t
  for d in "$T"/runs/*; do
    case "$(basename "$d")" in *review*) t="$REVIEW_TASK" ;; *) t="$BUILD_TASK" ;; esac
    "$ROW" --run-dir "$d" --task-yaml "$t" --manifest "$T/MANIFEST.json" --out "$T/all.jsonl"
  done
  [ "$(wc -l < "$T/all.jsonl" | tr -d ' ')" -eq 10 ]
  run "$ROW" --validate "$T/all.jsonl" --allow-ungraded
  [ "$status" -eq 0 ]
  [ "$(jq -r 'select(.run_id == "abl-fixture-a4_no_gates-rc-01-t1") | .status' "$T/all.jsonl")" = infrastructure_error ]
}

@test "usage: missing inputs exit 2" {
  run "$ROW" --run-dir "$T/runs/none" --task-yaml "$BUILD_TASK"
  [ "$status" -eq 2 ]
  run "$ROW" --validate "$T/nope.jsonl"
  [ "$status" -eq 2 ]
  run "$ROW" --bogus
  [ "$status" -eq 2 ]
}
