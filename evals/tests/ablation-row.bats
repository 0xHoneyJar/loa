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

@test "degraded: the requested model absent from models_used (a substitution, DEC-0545)" {
  edit_pipe a1-build '(.phases[] | select(.label == "IMPLEMENT") | .models_used) = {"claude-sonnet-5": 90}'
  row a1-build "$BUILD_TASK"
  [ "$(jq -r '.degraded' <<<"$(last)")" = true ]
  [[ "$(jq -r '.degraded_reason' <<<"$(last)")" == *"IMPLEMENT: requested global.anthropic.claude-opus-5-5 absent from models_used (claude-sonnet-5)"* ]]
}

@test "not degraded: an extra model beside the requested one (a WebFetch summariser, DEC-0545)" {
  edit_pipe a1-build '(.phases[] | select(.label == "IMPLEMENT") | .models_used) = {"global.anthropic.claude-opus-5-5": 6000, "global.anthropic.claude-haiku-4-5-20251001-v1:0": 516}'
  row a1-build "$BUILD_TASK"
  [ "$(jq -r '.degraded' <<<"$(last)")" = false ]
  [ "$(jq -r '.degraded_reason' <<<"$(last)")" = null ]
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
  # the harness copies under eval/ are what the row reads
  local e="$T/runs/a1-build/eval"
  jq '.verdict_quality.status = "DEGRADED"' "$e/adversarial-review.json" > "$T/x" && mv "$T/x" "$e/adversarial-review.json"
  jq '.verdict_quality.voices_succeeded = 1' "$e/adversarial-audit.json" > "$T/x" && mv "$T/x" "$e/adversarial-audit.json"
  row a1-build "$BUILD_TASK"
  [[ "$(jq -r '.degraded_reason' <<<"$(last)")" == *"review envelope verdict_quality DEGRADED"* ]]
  [[ "$(jq -r '.degraded_reason' <<<"$(last)")" == *"audit envelope 1 of 2 voices completed"* ]]
  # a legacy run without eval/ copies falls back to the sandbox envelope
  local s="$T/runs/a5-build/sandbox/grimoires/loa/a2a/sprint-1"
  rm "$T/runs/a5-build/eval/adversarial-review.json"
  jq '.verdict_quality.status = "DEGRADED"' "$s/adversarial-review.json" > "$T/x" && mv "$T/x" "$s/adversarial-review.json"
  row a5-build "$BUILD_TASK"
  [[ "$(jq -r '.degraded_reason' <<<"$(last)")" == *"review envelope verdict_quality DEGRADED"* ]]
  [ "$(jq -c '.zone_violations.envelope_mismatch' <<<"$(last)")" = '[]' ]
}

@test "envelopes: eval/ first; a sandbox envelope tampered after the gate leaves the row on the eval/ values and envelope_mismatch names the gate (audit MEDIUM-A1)" {
  row a1-build "$BUILD_TASK"
  [ "$(jq -c '.zone_violations.envelope_mismatch' <<<"$(last)")" = '[]' ]
  local s="$T/runs/a1-build/sandbox/grimoires/loa/a2a/sprint-1"
  jq '.verdict_quality.status = "DEGRADED" | .verdict_quality.voices_planned = 1 | .verdict_quality.voices_succeeded = 1' \
    "$s/adversarial-review.json" > "$T/x" && mv "$T/x" "$s/adversarial-review.json"
  row a1-build "$BUILD_TASK"
  local r; r="$(last)"
  [ "$(jq -c '.voices_run.review | {planned, completed, quality}' <<<"$r")" = '{"planned":2,"completed":2,"quality":"APPROVED"}' ]
  [ "$(jq -r '"\(.degraded) \(.degraded_reason)"' <<<"$r")" = "false null" ]
  [ "$(jq -c '.zone_violations.envelope_mismatch' <<<"$r")" = '["review"]' ]
  # both gates tampered → both listed, in gate order
  echo '{}' > "$s/adversarial-audit.json"
  row a1-build "$BUILD_TASK"
  [ "$(jq -c '.zone_violations.envelope_mismatch' <<<"$(last)")" = '["review","audit"]' ]
  run "$ROW" --validate "$T/rows.jsonl"
  [ "$status" -eq 0 ]
}

@test "zone_violations.bash_mount_refs: write-shaped Bash commands toward .claude/, CLAUDE.md or .loa.config.yaml only; reads never match; excerpt cut at 160 characters (audit LOW-A2)" {
  local long; long="echo $(printf 'x%.0s' $(seq 1 200)) >> CLAUDE.md"
  jq -cn --arg long "$long" '{type: "assistant", message: {content: [
      {type: "tool_use", name: "Bash", input: {command: "sed -i s/x/y/ .claude/rules/a.md"}},
      {type: "tool_use", name: "Bash", input: {command: "cat .claude/skills/auditing-security/SKILL.md"}},
      {type: "tool_use", name: "Bash", input: {command: "ls .claude/skills/ | grep -i audit"}},
      {type: "tool_use", name: "Bash", input: {command: "sed -n '"'"'95,400p'"'"' .claude/scripts/a.sh | head -40"}},
      {type: "tool_use", name: "Bash", input: {command: "cat .claude/rules/a.md > /tmp/y"}},
      {type: "tool_use", name: "Bash", input: {command: "grep -rn integrity .loa.config.yaml"}},
      {type: "tool_use", name: "Bash", input: {command: "ls src && pytest -q"}},
      {type: "tool_use", name: "Bash", input: {command: $long}},
      {type: "tool_use", name: "Bash", input: {command: "yq -i '"'"'.flatline_protocol.enabled = true'"'"' .loa.config.yaml"}},
      {type: "tool_use", name: "Bash", input: {command: "tee -a CLAUDE.md <<< x"}},
      {type: "tool_use", name: "Read", input: {file_path: ".loa.config.yaml"}}]}}' >> "$T/runs/a1-build/transcripts/events-FIX1.jsonl"
  row a1-build "$BUILD_TASK"
  local r; r="$(last)"
  [ "$(jq -r '.zone_violations.bash_mount_refs | length' <<<"$r")" = 4 ]
  [ "$(jq -c '.zone_violations.bash_mount_refs[0]' <<<"$r")" = '{"phase":"FIX1","excerpt":"sed -i s/x/y/ .claude/rules/a.md"}' ]
  [ "$(jq -r '.zone_violations.bash_mount_refs[1].excerpt | length' <<<"$r")" = 160 ]
  [[ "$(jq -r '.zone_violations.bash_mount_refs[1].excerpt' <<<"$r")" == "echo xxx"* ]]
  [ "$(jq -r '.zone_violations.bash_mount_refs[2].excerpt' <<<"$r")" = "yq -i '.flatline_protocol.enabled = true' .loa.config.yaml" ]
  [ "$(jq -r '.zone_violations.bash_mount_refs[3].excerpt' <<<"$r")" = "tee -a CLAUDE.md <<< x" ]
  # none of the reads is listed
  [ "$(jq -r '[.zone_violations.bash_mount_refs[].excerpt | select(test("^(cat|ls|grep|sed -n)"))] | length' <<<"$r")" = 0 ]
  [ "$(jq -c '.zone_violations.dot_claude_writes' <<<"$r")" = '[]' ]
  row a5-build "$BUILD_TASK"
  [ "$(jq -c '.zone_violations.bash_mount_refs' <<<"$(last)")" = '[]' ]
}

@test "zone_violations.mount_changed: the pipeline.json mount_integrity keys that read changed (audit LOW-A2)" {
  edit_pipe a1-build '.mount_integrity = {"claude_md": "changed", "loa_config": "ok"}'
  row a1-build "$BUILD_TASK"
  [ "$(jq -c '.zone_violations.mount_changed' <<<"$(last)")" = '["claude_md"]' ]
  edit_pipe a1-build '.mount_integrity = {"claude_md": "changed", "loa_config": "changed"}'
  row a1-build "$BUILD_TASK"
  [ "$(jq -c '.zone_violations.mount_changed' <<<"$(last)")" = '["claude_md","loa_config"]' ]
  # a record without mount_integrity (legacy, or stopped before materialisation) → none
  row a5-build "$BUILD_TASK"
  [ "$(jq -c '.zone_violations.mount_changed' <<<"$(last)")" = '[]' ]
  run "$ROW" --validate "$T/rows.jsonl" --allow-ungraded
  [ "$status" -eq 0 ]
}

@test "--validate requires the four zone_violations arrays (audit MEDIUM-A1, LOW-A2)" {
  row a1-build "$BUILD_TASK"
  local good k; good="$(last)"
  for k in dot_claude_writes bash_mount_refs mount_changed envelope_mismatch; do
    jq -c --arg k "$k" '.zone_violations |= del(.[$k])' <<<"$good" > "$T/one.jsonl"
    run "$ROW" --validate "$T/one.jsonl"
    [ "$status" -eq 1 ] && [[ "$output" == *"zone_violations.$k is not an array"* ]] || { echo "$k: $output"; return 1; }
    jq -c --arg k "$k" '.zone_violations[$k] = "x"' <<<"$good" > "$T/one.jsonl"
    run "$ROW" --validate "$T/one.jsonl"
    [ "$status" -eq 1 ] || { echo "$k string: $output"; return 1; }
  done
}

@test "arm grammar: the writer refuses an arm outside ^[a-z][a-z0-9_]{0,63}$ (exit 2); --validate names the line (audit LOW-A5)" {
  printf 'A1 Full!\n' > "$T/runs/a1-build/meta/arm"
  run "$ROW" --run-dir "$T/runs/a1-build" --task-yaml "$BUILD_TASK"
  [ "$status" -eq 2 ] && [[ "$output" == *"does not match ^[a-z][a-z0-9_]{0,63}$"* ]]
  # a manifest arm_map value is held to the same grammar
  rm "$T/runs/a1-build/meta/arm"
  jq '.arm_map["abl-fixture-a1_full-bf-01-t1"] = "A1"' "$T/MANIFEST.json" > "$T/m.json"
  run "$ROW" --run-dir "$T/runs/a1-build" --task-yaml "$BUILD_TASK" --manifest "$T/m.json"
  [ "$status" -eq 2 ] && [[ "$output" == *"arm 'A1' does not match"* ]]
  # --validate: line 2 carries "arm":"A1"
  row a5-build "$BUILD_TASK"
  { last; jq -c '.arm = "A1"' <<<"$(last)"; } > "$T/two.jsonl"
  run "$ROW" --validate "$T/two.jsonl" --allow-ungraded
  [ "$status" -eq 1 ]
  [[ "$output" == *"two.jsonl:2: arm A1 does not match the arm grammar"* ]]
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

@test "a MODELINV ledger over 200 KB reaches jq as a file: the row is written and validates" {
  local m="$T/runs/a1-build/eval/model-invoke.jsonl" pad i
  pad="$(printf '%0600d' 0)"
  for i in $(seq 1 400); do
    printf '{"schema_version":"1.1.0","primitive_id":"MODELINV","event_type":"model.invoke.complete","payload":{"calling_primitive":"bulk-%s","cost_micro_usd":1000,"pad":"%s"}}\n' "$i" "$pad"
  done >> "$m"
  [ "$(wc -c < "$m" | tr -d ' ')" -gt 204800 ]
  # the REVIEW phase owns lines 1-402 (its own hop, the audit hop, 400 bulk rows), so
  # every bulk row is read, not only loaded: 0.4 + 0.3 + 400 x 0.001
  edit_pipe a1-build '(.phases[] | select(.label == "REVIEW") | .modelinv_lines.to) = 402'
  run row a1-build "$BUILD_TASK"
  [ "$status" -eq 0 ]
  run "$ROW" --validate "$T/rows.jsonl" --allow-ungraded
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.phases[] | select(.label == "REVIEW")][0].voice_cost_usd' <<<"$(last)")" = 1.1 ]
  # the work directory is removed at exit
  [ -z "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'ablation-row.*' -newer "$m" 2>/dev/null)" ]
}

@test "an empty finished timestamp and a boolean companion_voice still yield a valid row" {
  local e="$T/runs/a1-build/eval" sum   # the envelope copy the row reads
  edit_pipe a1-build '.finished = ""'
  jq '.metadata.companion_voice = false' "$e/adversarial-review.json" > "$T/x" && mv "$T/x" "$e/adversarial-review.json"
  run row a1-build "$BUILD_TASK"
  [ "$status" -eq 0 ]
  run "$ROW" --validate "$T/rows.jsonl" --allow-ungraded
  [ "$status" -eq 0 ]
  sum="$(jq '[.phases[] | select(.skipped != true) | .wall_ms // .duration_ms // 0] | add' "$T/runs/a1-build/meta/pipeline.json")"
  [ "$(jq -r '.wall_clock_ms' <<<"$(last)")" = "$sum" ]
  [ "$(jq -r '.voices_run.review.companion_planned' <<<"$(last)")" = null ]
}

@test "odd field shapes: an offset timestamp, an array models_used, a string verdict_accuracy, no name or model_requested" {
  edit_pipe a1-build '.started = "2026-10-14T22:42:11+00:00"
    | (.phases[] | select(.label == "IMPLEMENT")) |= (.models_used = ["claude-opus-5-5"] | del(.name) | del(.model_requested))'
  jq '.verdict_accuracy = "yes" | .verdict_accuracy_per_gate = "n/a" | del(.verdict_accuracy_review) | del(.verdict_accuracy_audit)' \
    "$T/runs/a1-build/grade.json" > "$T/g" && mv "$T/g" "$T/runs/a1-build/grade.json"
  run row a1-build "$BUILD_TASK"
  [ "$status" -eq 0 ]
  run "$ROW" --validate "$T/rows.jsonl"
  [ "$status" -eq 0 ]
  local r; r="$(last)"
  [ "$(jq -c '[.phases[] | select(.label == "IMPLEMENT")][0] | [.name, .model_requested, .models_used]' <<<"$r")" = '["IMPLEMENT","",{}]' ]
  [ "$(jq -c '[.verdict_accuracy, .verdict_accuracy_review, .verdict_accuracy_audit]' <<<"$r")" = '[null,null,null]' ]
  [[ "$(jq -r '.degraded_reason // ""' <<<"$r")" != *"model claude-opus-5-5 used"* ]]
}

@test "a row program abort exits 2 naming the run (never a bare jq exit)" {
  edit_pipe a1-build '.phases = [1, 2]'
  run row a1-build "$BUILD_TASK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"row build failed for abl-fixture-a1_full-bf-01-t1"* ]]
  [ ! -s "$T/rows.jsonl" ]
}

# --- row writer 1.2: defects_missed (bd-yz1rd) and regressions_final_green (bd-m0hw7) ---
edit_grade() {  # edit_grade <run> <jq filter>
  jq "$2" "$T/runs/$1/grade.json" > "$T/g.json" && mv "$T/g.json" "$T/runs/$1/grade.json"
}

@test "defects_missed: a review-catch row copies recall.missed; regressions_final_green is null" {
  # row writer 1.3: the list must agree with the counts (8 seeded − 2 missed = 6 caught)
  edit_grade a3-review '.recall.defects_seeded = 8 | .recall.defects_caught = 6 | .recall.missed = ["d2","d5"]'
  row a3-review "$REVIEW_TASK"
  run "$ROW" --validate "$T/rows.jsonl"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.defects_missed, .regressions_final_green]' <<<"$(last)")" = '[["d2","d5"],null]' ]
}

@test "defects_missed: an empty recall.missed is [], an absent one or a null recall is null" {
  edit_grade a3-review '.recall.defects_caught = 3 | .recall.missed = []'
  row a3-review "$REVIEW_TASK"
  [ "$(jq -c '.defects_missed' <<<"$(last)")" = '[]' ]
  edit_grade a3-review 'del(.recall.missed)'
  row a3-review "$REVIEW_TASK"
  [ "$(jq -c '.defects_missed' <<<"$(last)")" = 'null' ]
  edit_grade a3-review '.recall = null'
  row a3-review "$REVIEW_TASK"
  [ "$(jq -c '.defects_missed' <<<"$(last)")" = 'null' ]
  edit_grade a3-review '.recall = {defects_seeded: 3, missed: "d2"}'
  row a3-review "$REVIEW_TASK"
  [ "$(jq -c '.defects_missed' <<<"$(last)")" = 'null' ]
}

@test "regressions_final_green: a build row copies regressions.final_green (true, false); defects_missed is null" {
  edit_grade a1-build '.regressions.final_green = true | .recall = {missed: ["d1"]}'
  row a1-build "$BUILD_TASK"
  run "$ROW" --validate "$T/rows.jsonl"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.regressions_final_green, .defects_missed]' <<<"$(last)")" = '[true,null]' ]
  edit_grade a1-build '.regressions.final_green = false'
  row a1-build "$BUILD_TASK"
  [ "$(jq -c '[.regressions_final_green, .defects_missed]' <<<"$(last)")" = '[false,null]' ]
  edit_grade a1-build '.regressions.final_green = "yes"'
  row a1-build "$BUILD_TASK"
  [ "$(jq -c '.regressions_final_green' <<<"$(last)")" = 'null' ]
  edit_grade a1-build '.regressions = null'
  row a1-build "$BUILD_TASK"
  [ "$(jq -c '.regressions_final_green' <<<"$(last)")" = 'null' ]
  run "$ROW" --validate "$T/rows.jsonl"
  [ "$status" -eq 0 ]
}

@test "an ungraded run has defects_missed and regressions_final_green null" {
  [ ! -f "$T/runs/a1-review/grade.json" ]
  row a1-review "$REVIEW_TASK"
  row a5-build "$BUILD_TASK"
  run "$ROW" --validate "$T/rows.jsonl" --allow-ungraded
  [ "$status" -eq 0 ]
  [ "$(jq -s -c 'map([has("defects_missed"), .defects_missed, has("regressions_final_green"), .regressions_final_green])' "$T/rows.jsonl")" = '[[true,null,true,null],[true,null,true,null]]' ]
}

@test "--validate: defects_missed must be a list of non-empty strings or null, regressions_final_green a boolean or null; a legacy row lacking both keys validates" {
  edit_grade a3-review '.recall.missed = ["d2"]'
  row a3-review "$REVIEW_TASK"
  local good; good="$(last)"
  jq -c '.defects_missed = "d2"' <<<"$good" > "$T/one.jsonl"
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 1 ] && [[ "$output" == *"one.jsonl:1: field defects_missed has type string"* ]]
  jq -c '.defects_missed = ["d2", 3]' <<<"$good" > "$T/one.jsonl"
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 1 ] && [[ "$output" == *"field defects_missed has type array"* ]]
  jq -c '.defects_missed = [""]' <<<"$good" > "$T/one.jsonl"
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 1 ]
  jq -c '.regressions_final_green = "yes"' <<<"$good" > "$T/one.jsonl"
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 1 ] && [[ "$output" == *"field regressions_final_green has type string, want boolean|null"* ]]
  { jq -c '.defects_missed = null | .regressions_final_green = true' <<<"$good"
    jq -c 'del(.defects_missed) | del(.regressions_final_green)' <<<"$good"; } > "$T/two.jsonl"
  run "$ROW" --validate "$T/two.jsonl"
  [ "$status" -eq 0 ] && [[ "$output" == *"2 rows valid"* ]]
}

# --- row writer 1.3: the defects_missed id rules (Sprint 262 audit DISS-C-001) ---
vrow() {  # vrow <missed json> <seeded> <caught> → $T/one.jsonl: the a3-review row with those fields
  jq -c --argjson ms "$1" --argjson s "$2" --argjson c "$3" \
    '.defects_missed = $ms | .defects_seeded = $s | .defects_caught = $c' <<<"$GOOD" > "$T/one.jsonl"
}

@test "--validate rejects defects_missed outside the id rules, naming the rule and the line" {
  edit_grade a3-review '.recall.missed = ["d2"]'
  row a3-review "$REVIEW_TASK"
  GOOD="$(last)"
  vrow '["x1"]' 3 2
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 1 ] && [[ "$output" == *'one.jsonl:1: defects_missed ["x1"] violates the rule: id grammar ^d[1-9][0-9]*$'* ]]
  vrow '["d2","d2"]' 3 1
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 1 ] && [[ "$output" == *'one.jsonl:1: defects_missed ["d2","d2"] violates the rule: unique ids'* ]]
  vrow '["d1","d2","d3","d4"]' 3 0
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 1 ] && [[ "$output" == *'one.jsonl:1: defects_missed ["d1","d2","d3","d4"] violates the rule: at most defects_seeded ids'* ]]
  vrow '["d2"]' 3 1
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 1 ] && [[ "$output" == *'one.jsonl:1: defects_missed ["d2"] violates the rule: defects_seeded − ids == defects_caught'* ]]
  vrow '["d4"]' 3 2
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 1 ] && [[ "$output" == *'violates the rule: ids within d1 … d<defects_seeded>'* ]]
  vrow '["d0"]' 3 2
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 1 ] && [[ "$output" == *'violates the rule: id grammar'* ]]
  # the line number is the bad row's: a good row first, the bad one second
  { printf '%s\n' "$GOOD"; cat "$T/one.jsonl"; } > "$T/two.jsonl"
  run "$ROW" --validate "$T/two.jsonl"
  [ "$status" -eq 1 ] && [[ "$output" == *"two.jsonl:2: defects_missed"* ]]
}

@test "--validate accepts consistent defects_missed: [d2,d5] on 8 seeded with 6 caught, [] with caught == seeded, null counts unchecked" {
  edit_grade a3-review '.recall.missed = ["d2"]'
  row a3-review "$REVIEW_TASK"
  GOOD="$(last)"
  vrow '["d2","d5"]' 8 6
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 0 ]
  vrow '[]' 3 3
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 0 ]
  vrow '["d2"]' null null
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 0 ]
  # the rules apply to review-catch rows only: a build row is not checked
  jq -c '.task_type = "bug-fix" | .defects_missed = ["x1"]' <<<"$GOOD" > "$T/one.jsonl"
  run "$ROW" --validate "$T/one.jsonl" --allow-ungraded
  [ "$status" -eq 0 ]
}

@test "the row program writes defects_missed null for an inconsistent recall.missed, every other field unchanged" {
  edit_grade a3-review '.recall.missed = ["d2"]'
  row a3-review "$REVIEW_TASK"
  local good; good="$(last)"
  [ "$(jq -c .defects_missed <<<"$good")" = '["d2"]' ]
  for ms in '["x1"]' '["d2","d2"]' '["d1","d2","d3","d4"]' '["d1","d2"]' '["d4"]'; do
    edit_grade a3-review ".recall.missed = $ms"
    row a3-review "$REVIEW_TASK"
    [ "$(jq -c .defects_missed <<<"$(last)")" = null ]
    [ "$(jq -c 'del(.defects_missed, .started, .finished, .wall_clock_ms)' <<<"$(last)")" = "$(jq -c 'del(.defects_missed, .started, .finished, .wall_clock_ms)' <<<"$good")" ]
  done
  run "$ROW" --validate "$T/rows.jsonl"
  [ "$status" -eq 0 ]
}

@test "the 165 tracked runs.jsonl rows still validate under row writer 1.3 (read-only copy)" {
  local real="$REPO_ROOT/grimoires/loa/reports/ablation-2.0/runs.jsonl"
  [ -f "$real" ] || skip "no tracked runs.jsonl"
  cp "$real" "$T/real.jsonl"
  run "$ROW" --validate "$T/real.jsonl"
  [ "$status" -eq 0 ] && [[ "$output" == *"real.jsonl: 165 rows valid"* ]]
}

# --- row writer 1.4 (cycle-131 Sprint 263 Task 1.6, SDD §3.2) ---------------------------------------------------
# g13 <run>: a grader 1.3.0 grade.json for the review-catch fixture run (3 seeded, 2 caught under the new rule)
g13() {
  jq '.grader_version = "1.3.0" | .corpus_sha256 = "c0ffee"
      | .recall += {missed: ["d3"], recall_pm3: 0.3333, missed_pm3: ["d2", "d3"], recall_pm3_v1: 0.3333,
                    missed_pm3_v1: ["d2", "d3"], v1_manifest: true, credits_function_only: ["d2"], rule: "pm3_or_same_function"}
      | .oracle_exposed_defects = ["d1"] | .oracle_exposed_unknown = []' \
    "$T/runs/$1/grade.json" > "$T/g.json" && mv "$T/g.json" "$T/runs/$1/grade.json"
}
envset() {  # envset <run> <gate> <jq filter on the envelope>
  jq "$3" "$T/runs/$1/eval/adversarial-$2.json" > "$T/e.json" && mv "$T/e.json" "$T/runs/$1/eval/adversarial-$2.json"
}

@test "RW14-1 a grader 1.3 review-catch row carries the three rates, the missed lists, credits_function_only, the oracle lists, grader_rule/version and corpus_sha256; it validates" {
  g13 a3-review
  row a3-review "$REVIEW_TASK"
  run "$ROW" --validate "$T/rows.jsonl"
  [ "$status" -eq 0 ]
  local r; r="$(last)"
  [ "$(jq -r '"\(.row_writer_version) \(.defect_catch_rate) \(.defect_catch_rate_pm3) \(.defect_catch_rate_pm3_v1)"' <<<"$r")" = "1.5 0.6667 0.3333 0.3333" ]   # cycle-132: row writer 1.5 (additive)
  [ "$(jq -c '[.defects_missed, .defects_missed_pm3, .defects_missed_pm3_v1, .credits_function_only, .oracle_exposed_defects, .oracle_exposed_unknown]' <<<"$r")" = '[["d3"],["d2","d3"],["d2","d3"],["d2"],["d1"],[]]' ]
  [ "$(jq -r '"\(.grader_rule) \(.grader_version) \(.corpus_sha256)"' <<<"$r")" = "pm3_or_same_function 1.3.0 c0ffee" ]
  # a 1.2.x grade names no rule: grader_rule pm3, the new rates null
  row a3-review "$REVIEW_TASK" --grade "$FX/runs/a3-review/grade.json"
  r="$(last)"
  [ "$(jq -r '"\(.grader_rule) \(.defect_catch_rate_pm3) \(.credits_function_only) \(.oracle_exposed_defects)"' <<<"$r")" = "pm3 null null null" ]
  # a build row: rule null; a position list outside the id rules is written null
  row a1-build "$BUILD_TASK"
  [ "$(jq -r '.grader_rule' <<<"$(last)")" = null ]
  jq '.recall.credits_function_only = ["d9"] | .oracle_exposed_defects = ["x1"]' "$T/runs/a3-review/grade.json" > "$T/bad.json"
  row a3-review "$REVIEW_TASK" --grade "$T/bad.json"
  [ "$(jq -c '[.credits_function_only, .oracle_exposed_defects, .defect_catch_rate]' <<<"$(last)")" = '[null,null,0.6667]' ]
}

@test "RW14-2 arm evidence: config_variant, overlay_mode, oracle_open and gate_scripts_at_pr_version; defaults shipped / null / false / []" {
  row a3-review "$REVIEW_TASK"
  [ "$(jq -c '[.config_variant, .overlay_mode, .oracle_open, .gate_scripts_at_pr_version]' <<<"$(last)")" = '["shipped",null,false,[]]' ]
  printf 'config_variant=eval\nmount_overlay=head 7 paths\ngate_scripts_at_pr_version=\noverlay_sha256=.claude/x.sh=ab\ngate_scripts_at_pr_version=.claude/scripts/adversarial-review.sh,.claude/skills/reviewing-code/SKILL.md\n' \
    >> "$T/runs/a3-review/meta/arm-evidence.txt"
  row a3-review "$REVIEW_TASK"
  [ "$(jq -c '[.config_variant, .overlay_mode, .oracle_open, .gate_scripts_at_pr_version]' <<<"$(last)")" = '["eval","head",false,[".claude/scripts/adversarial-review.sh",".claude/skills/reviewing-code/SKILL.md"]]' ]
  printf 'mount_overlay=none\noracle_open=true\nconfig_variant=bogus\n' >> "$T/runs/a3-review/meta/arm-evidence.txt"
  row a3-review "$REVIEW_TASK"
  [ "$(jq -c '[.config_variant, .overlay_mode, .oracle_open]' <<<"$(last)")" = '["shipped","none",true]' ]
}

@test "RW14-3 dissent_absent_reason per gate: none, budget, error (failed, record-fallback, absent envelope), preflight, disabled (config or dissent=false); a gate that did not run is null" {
  row a3-review "$REVIEW_TASK"
  [ "$(jq -c '[.dissent_absent_reason, .dissent_absent_gates]' <<<"$(last)")" = '[{"review":"none","audit":"none"},[]]' ]
  envset a3-review review '.metadata = {status: "budget_exceeded", recorded_by: "record-fallback", reason: "ERROR: Estimated cost (366c) exceeds budget (200c)"}'
  envset a3-review audit '.metadata = {status: "failed", recorded_by: "record-fallback"}'
  row a3-review "$REVIEW_TASK"
  [ "$(jq -c '[.dissent_absent_reason, .dissent_absent_gates]' <<<"$(last)")" = '[{"review":"budget","audit":"error"},["review","audit"]]' ]
  envset a3-review review '.metadata = {status: "preflight_failed"}'
  envset a3-review audit '.metadata = {status: "reviewed", recorded_by: "record-fallback", reason: "voice preflight: no credential"}'
  row a3-review "$REVIEW_TASK"
  [ "$(jq -c '.dissent_absent_reason' <<<"$(last)")" = '{"review":"preflight","audit":"preflight"}' ]
  rm -f "$T/runs/a3-review/eval/adversarial-audit.json" "$T/runs/a3-review/sandbox/grimoires/loa/a2a/sprint-1/adversarial-audit.json"
  printf 'flatline_protocol:\n  enabled: false\n  code_review:\n    enabled: false\n' > "$T/runs/a3-review/sandbox/.loa.config.yaml"
  row a3-review "$REVIEW_TASK"
  # row writer 1.5 (bd-jszcp): the agent-writable sandbox config never reads "disabled"; the envelopes decide
  [ "$(jq -c '[.dissent_absent_reason, .dissent_absent_gates]' <<<"$(last)")" = '[{"review":"preflight","audit":"error"},["review","audit"]]' ]
  rm "$T/runs/a3-review/sandbox/.loa.config.yaml"; echo 'dissent=false' >> "$T/runs/a3-review/meta/arm-evidence.txt"
  row a3-review "$REVIEW_TASK"
  [ "$(jq -r '.dissent_absent_reason.review' <<<"$(last)")" = disabled ]
  edit_pipe a3-review '.phases |= map(if .label == "AUDIT" then .skipped = true else . end)'
  row a3-review "$REVIEW_TASK"
  [ "$(jq -c '[.dissent_absent_reason, .dissent_absent_gates]' <<<"$(last)")" = '[{"review":"disabled","audit":null},["review"]]' ]
  # the harness lines for gates: false / flatline: false disable both gates' dissent
  edit_pipe a3-review '.phases |= map(.skipped = false)'
  echo 'gates=flatline_protocol.{code_review,security_audit}.enabled=false' >> "$T/runs/a3-review/meta/arm-evidence.txt"
  row a3-review "$REVIEW_TASK"
  [ "$(jq -c '.dissent_absent_reason' <<<"$(last)")" = '{"review":"disabled","audit":"disabled"}' ]
  run "$ROW" --validate "$T/rows.jsonl"
  [ "$status" -eq 0 ]
}

@test "RW14-4 --validate: a 1.4 row needs every 1.4 field and the enums; a legacy row without them still validates" {
  g13 a3-review
  row a3-review "$REVIEW_TASK"
  local good f; good="$(last)"
  for f in defect_catch_rate_pm3 defect_catch_rate_pm3_v1 defects_missed_pm3 defects_missed_pm3_v1 credits_function_only \
           oracle_exposed_defects oracle_exposed_unknown dissent_absent_gates dissent_absent_reason grader_rule grader_version \
           corpus_sha256 config_variant overlay_mode oracle_open gate_scripts_at_pr_version; do
    jq -c --arg f "$f" 'del(.[$f])' <<<"$good" > "$T/one.jsonl"
    run "$ROW" --validate "$T/one.jsonl"
    [ "$status" -eq 1 ] || { echo "field $f: status $status"; return 1; }
    [[ "$output" == *"missing field $f"* ]] || { echo "field $f: $output"; return 1; }
  done
  local bad want
  while IFS=$'\t' read -r bad want; do
    jq -c "$bad" <<<"$good" > "$T/one.jsonl"
    run "$ROW" --validate "$T/one.jsonl"
    [ "$status" -eq 1 ] && [[ "$output" == *"$want"* ]] || { echo "$bad: $output"; return 1; }
  done <<'CASES'
.config_variant = "x"	config_variant "x" is not shipped|eval
.overlay_mode = "both"	overlay_mode "both" is not head|base|none|null
.dissent_absent_reason.review = "maybe"	dissent_absent_reason.review = "maybe" is not one of
.dissent_absent_reason.gate3 = null	dissent_absent_reason.gate3 = null is not one of
.dissent_absent_gates = ["fix"]	names a gate other than review|audit
.credits_function_only = ["d7"]	credits_function_only ["d7"] violates the rule: ids within d1
.oracle_exposed_defects = ["d1", "d1"]	oracle_exposed_defects ["d1","d1"] violates the rule: unique ids
.gate_scripts_at_pr_version = [""]	gate_scripts_at_pr_version must be a list of non-empty strings
.oracle_open = "true"	field oracle_open has type string
CASES
  # a legacy (1.3) row lacking every 1.4 field validates
  jq -c 'del(.row_writer_version, .defect_catch_rate_pm3, .defect_catch_rate_pm3_v1, .defects_missed_pm3, .defects_missed_pm3_v1,
             .credits_function_only, .oracle_exposed_defects, .oracle_exposed_unknown, .dissent_absent_gates, .dissent_absent_reason,
             .grader_rule, .grader_version, .corpus_sha256, .config_variant, .overlay_mode, .oracle_open, .gate_scripts_at_pr_version)' \
    <<<"$good" > "$T/legacy.jsonl"
  run "$ROW" --validate "$T/legacy.jsonl"
  [ "$status" -eq 0 ]
}

# --- cycle-132 Sprint 269 Task 1.7b: row writer 1.5 (matched cells, all_spend_usd, the cycle-132 provenance fields) ---

# make_cell_rows <cell> <s1-valid:status:cost:attempt-costs> … — sessions/<s>/meta/pipeline.json with one BARE record
# (an invalid session's record carries a refusal fallback), meta/cell.json, meta/arm and a union grade.json
make_cell_rows() {
  local c="$1" spec i=0 id valid st cost acs att fb; shift
  mkdir -p "$c/meta"; echo a0_bare_matched > "$c/meta/arm"
  local sessions='[]'
  for spec in "$@"; do
    i=$((i + 1)); id="s$i"; IFS=: read -r valid st cost acs <<<"$spec"
    mkdir -p "$c/sessions/$id/meta" "$c/sessions/$id/transcripts"
    fb='[]'; [[ "$valid" == true ]] || fb='[{"from":"global.anthropic.claude-opus-5-5","to":"x","category":"cyber","scope":"session"}]'
    jq -n --arg id "$id" --arg st "$st" --argjson c "$cost" --argjson fb "$fb" '
      {schema_version: 1, run_id: ("cellb-a0_bare_matched-rc-01-t1-" + $id), arm: "a0_bare_matched", task_id: "rc-01",
       task_type: "review-catch", trial: 1, source_commit: "abc123", suite_version: 2, status: $st, spent_usd: $c,
       fingerprint: "fp:cell", image_digest: "sha256:cell", started: "2026-10-21T01:00:00Z", finished: "2026-10-21T01:05:00Z",
       phases: [{name: "BARE", label: "BARE", skipped: false, session_id: ("sess-" + $id),
                 model_requested: "global.anthropic.claude-opus-5-5", models_used: {"global.anthropic.claude-opus-5-5": 100},
                 effort_requested: "high", tokens_in: 10, tokens_out: 100, cache_read_tokens: 0, cache_creation_tokens: 0,
                 cost_usd: $c, ledger_cost_usd: 0, duration_ms: 1000, num_turns: 2, exit: 0, timed_out: false,
                 refusal_fallbacks: $fb, modelinv_lines: {from: 1, to: 0}}]}' > "$c/sessions/$id/meta/pipeline.json"
    printf 'loa_mount=none\nbatch_context=cellb\nmount_cheval=none\nbare_sessions=matched\n' > "$c/sessions/$id/meta/arm-evidence.txt"
    echo '{"type":"system","subtype":"init"}' > "$c/sessions/$id/transcripts/events-BARE.jsonl"
    att="$(tr ',' '\n' <<<"$acs" | grep -c .)"
    sessions="$(jq -c --arg id "$id" --argjson v "$valid" --arg st "$st" --argjson c "$cost" --argjson att "$att" \
      --argjson acs "[$acs]" '. + [{id: $id, valid: $v, status: $st, cost_usd: $c, attempts: $att, attempt_costs: $acs, run_dir: ("sessions/" + $id)}]' <<<"$sessions")"
  done
  jq -n --argjson s "$sessions" --argjson k "$i" '{schema_version: 1, run_id: "cellb-a0_bare_matched-rc-01-t1", task_id: "rc-01", trial: 1,
     k: $k, sessions: $s, sessions_valid: ([$s[] | select(.valid)] | length)}' > "$c/meta/cell.json"
  jq -n --argjson k "$i" '{grader_version: "1.3.2", union: true, bare_sessions: $k, label_set: "v2",
     recall: {defects_seeded: 2, defects_caught: 1, recall: 0.5, recall_pm3: 0.5, missed: ["d2"], missed_pm3: ["d2"], rule: "pm3_or_same_function"},
     false_positives: 1, false_positive_rule: "pm3", recall_session1: 0.5, recall_pm3_session1: 0.5, precision_session1: 0.5,
     verdict: null, contaminated: null, oracle_exposed_defects: [], oracle_exposed_unknown: []}' > "$c/grade.json"
}

@test "RW15-1 an ordinary row carries the 1.5 fields: all_spend_usd = cost_usd + --prior-spend, batch_context and mount_cheval from the evidence, registration_sha256 from the manifest, label_set from the grade; it validates" {
  printf 'batch_context=batch-x\nmount_cheval=ok\n' >> "$T/runs/a3-review/meta/arm-evidence.txt"
  jq '.registration_sha256 = "'"$(printf 'a%.0s' $(seq 1 64))"'"' "$T/MANIFEST.json" > "$T/m.json" && mv "$T/m.json" "$T/MANIFEST.json"
  jq '.label_set = "v2"' "$T/runs/a3-review/grade.json" > "$T/g.json" && mv "$T/g.json" "$T/runs/a3-review/grade.json"
  row a3-review "$REVIEW_TASK" --prior-spend 2.25 --attempts 2
  run "$ROW" --validate "$T/rows.jsonl"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local r; r="$(last)"
  [ "$(jq -r .row_writer_version <<<"$r")" = 1.5 ]
  [ "$(jq -r '[.bare_sessions, .sessions_valid, .sessions_attempted, .session_costs, .dollar_match, .recall_session1] | map(tostring) | join(" ")' <<<"$r")" = "null null null null null null" ]
  [ "$(jq -r '(.all_spend_usd - .cost_usd) * 100 | round' <<<"$r")" = 225 ]
  [ "$(jq -r '"\(.batch_context) \(.mount_cheval) \(.label_set) \(.attempts)"' <<<"$r")" = "batch-x ok v2 2" ]
  [ "$(jq -r '.registration_sha256 | length' <<<"$r")" = 64 ]
  run "$ROW" --run-dir "$T/runs/a3-review" --task-yaml "$REVIEW_TASK" --prior-spend x
  [ "$status" -eq 2 ]
}

@test "RW15-2 a matched cell row: k BARE records, cost_usd over the valid sessions, all_spend_usd over every attempt, session_costs, the union's session-1 figures; an invalid session's refusal fallback does not degrade the cell" {
  C="$T/runs/cell1"
  make_cell_rows "$C" true:completed:1.5:1.5 true:completed:2:0.75,2 false:completed:1.25:1.25
  "$ROW" --run-dir "$C" --task-yaml "$REVIEW_TASK" --manifest "$T/MANIFEST.json" --out "$T/rows.jsonl"
  run "$ROW" --validate "$T/rows.jsonl"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local r; r="$(last)"
  [ "$(jq -r '"\(.run_id) \(.arm) \(.status) \(.degraded)"' <<<"$r")" = "cellb-a0_bare_matched-rc-01-t1 a0_bare_matched completed false" ]
  [ "$(jq -r '[.phases[].label] | join(",")' <<<"$r")" = "BARE-s1,BARE-s2,BARE-s3" ]
  [ "$(jq -r '"\(.bare_sessions) \(.sessions_valid) \(.sessions_attempted) \(.attempts)"' <<<"$r")" = "3 2 3 2" ]
  [ "$(jq -r '.cost_usd' <<<"$r")" = 3.5 ]
  [ "$(jq -r '.all_spend_usd' <<<"$r")" = 5.5 ]
  [ "$(jq -c '[.session_costs[] | [.session, .valid, .attempts, .attempt_costs]]' <<<"$r")" = '[["s1",true,1,[1.5]],["s2",true,2,[0.75,2]],["s3",false,1,[1.25]]]' ]
  [ "$(jq -r '"\(.recall_session1) \(.precision_session1) \(.defect_catch_rate) \(.label_set) \(.batch_context) \(.mount_cheval)"' <<<"$r")" = "0.5 0.5 0.5 v2 cellb none" ]
  [ "$(jq -r '.dollar_match' <<<"$r")" = null ]
}

@test "RW15-3 a matched cell under ⌈k/2⌉ valid sessions is degraded with the reason; none valid is infrastructure_error (contaminated when a session was)" {
  C="$T/runs/cell2"
  make_cell_rows "$C" true:completed:1:1 false:transport_error:0:0,0,0 false:completed:1:1
  "$ROW" --run-dir "$C" --task-yaml "$REVIEW_TASK" --manifest "$T/MANIFEST.json" --out "$T/rows.jsonl"
  [ "$(jq -r '"\(.status) \(.degraded) \(.degraded_reason)"' <<<"$(last)")" = "completed true sessions_valid < k/2 (1 of 3)" ]
  [ "$(jq -r '.attempts' <<<"$(last)")" = 3 ]
  C="$T/runs/cell3"
  make_cell_rows "$C" false:transport_error:0:0 false:interrupted:0:0
  "$ROW" --run-dir "$C" --task-yaml "$REVIEW_TASK" --manifest "$T/MANIFEST.json" --out "$T/rows.jsonl"
  [ "$(jq -r '.status' <<<"$(last)")" = infrastructure_error ]
  C="$T/runs/cell4"
  make_cell_rows "$C" false:contaminated:1:1 false:transport_error:0:0
  "$ROW" --run-dir "$C" --task-yaml "$REVIEW_TASK" --manifest "$T/MANIFEST.json" --out "$T/rows.jsonl"
  [ "$(jq -r '.status' <<<"$(last)")" = contaminated ]
  run "$ROW" --validate "$T/rows.jsonl" --allow-ungraded
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "RW15-4 --validate on 1.5 rows: every 1.5 field, attempts 1 … 3, consistent cell counts, a 64-hex registration_sha256" {
  C="$T/runs/cell1"
  make_cell_rows "$C" true:completed:1:1 true:completed:1:1
  "$ROW" --run-dir "$C" --task-yaml "$REVIEW_TASK" --manifest "$T/MANIFEST.json" --out "$T/rows.jsonl"
  local good f; good="$(last)"
  for f in bare_sessions sessions_valid sessions_attempted session_costs all_spend_usd dollar_match recall_session1 \
           recall_pm3_session1 precision_session1 label_set batch_context mount_cheval registration_sha256; do
    jq -c --arg f "$f" 'del(.[$f])' <<<"$good" > "$T/one.jsonl"
    run "$ROW" --validate "$T/one.jsonl"
    [ "$status" -eq 1 ] || { echo "field $f: status $status"; return 1; }
    [[ "$output" == *"missing field $f"* ]] || { echo "field $f: $output"; return 1; }
  done
  jq -c '.attempts = 4' <<<"$good" > "$T/one.jsonl"
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 1 ]; [[ "$output" == *"attempts 4 is not 1 … 3"* ]]
  jq -c '.sessions_valid = 3' <<<"$good" > "$T/one.jsonl"
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 1 ]; [[ "$output" == *"matched cell fields inconsistent"* ]]
  jq -c '.registration_sha256 = "abc"' <<<"$good" > "$T/one.jsonl"
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 1 ]; [[ "$output" == *"registration_sha256 is not 64 lowercase hex"* ]]
  # a 1.4 row (no 1.5 fields, attempts unbounded) still validates
  jq -c '.row_writer_version = "1.4" | del(.bare_sessions, .sessions_valid, .sessions_attempted, .session_costs, .all_spend_usd,
         .dollar_match, .recall_session1, .recall_pm3_session1, .precision_session1, .label_set, .batch_context, .mount_cheval,
         .registration_sha256)' <<<"$good" > "$T/one.jsonl"
  run "$ROW" --validate "$T/one.jsonl"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
