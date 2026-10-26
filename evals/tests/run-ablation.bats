#!/usr/bin/env bats
# =============================================================================
# evals/tests/run-ablation.bats — cycle-130 Sprint 260 Task 3.2 (SDD §5.9, §3.4;
# AC-3.2, AC-3.5, AC-3.7; DEC-0405, DEC-0407, DEC-0417, DEC-0418, DEC-0429, DEC-0435)
#
# run-ablation.sh against stubs only: the pipeline is fixtures/ablation-pipeline-stub.sh,
# the grader fixtures/ablation-grade-stub.sh, docker fixtures/ablation-docker-stub.sh
# (also first on PATH, so fingerprint.sh never reaches a real docker); ablation-row.sh,
# took-effect.sh, freeze.sh and validate-suite.sh are the real ones. The pinned source is
# a throwaway git tree (LOA_ABLATION_SOURCE_TREE); the suite is the frozen one, read only
# (cases that break the hard gate work on a copy). No model call, no docker.
# =============================================================================

setup() {
  # cycle-133 FR-9 (SDD C-9): these suites drive run-ablation.sh with a stub docker and no egress block; the
  # test-mode escape (LOA_EGRESS_TEST_MODE=1 AND BATS_TEST_FILENAME) records enforced: false instead of refusing.
  export LOA_EGRESS_TEST_MODE=1
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  RA="$REPO_ROOT/evals/harness/run-ablation.sh"
  FX="$TESTS_DIR/fixtures"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/rab.XXXXXX")"
  mkdir -p "$T/bin" "$T/src/.claude"
  cp "$FX/ablation-docker-stub.sh" "$T/bin/docker"
  cp "$FX/docker-stub.sh" "$T/bin/docker-stub.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "2.1.300 (Claude Code)"' > "$T/bin/claude"
  chmod +x "$T/bin/docker" "$T/bin/docker-stub.sh" "$T/bin/claude"
  echo "# loa" > "$T/src/.claude/CLAUDE.loa.md"
  ( cd "$T/src" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m src )
  SHA="$(git -C "$T/src" rev-parse HEAD)"
  for i in $(seq 1 36); do echo "self-check base task-$i: PASS hidden 1/1"; done > "$T/self-check.log"
  export PATH="$T/bin:$PATH" EVAL_CLAUDE_BIN="$T/bin/claude" LOA_ABLATION_SOURCE_TREE="$T/src"
  export LOA_ABLATION_RETRY_WAIT_S=0 LOA_ABLATION_POLL_S=0.2 STUB_LOG="$T/stub.log" STUB_GRADE_LOG="$T/grade.log"
  unset STUB_ENV_LOG LOA_ABLATION_BATCH_CONTEXT STUB_ARGV_LOG STUB_RULES STUB_HANG STUB_CLI STUB_COST STUB_GRADE_FAIL STUB_GRADE_HANG LOA_ABLATION_GRADE_TIMEOUT_S LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S LOA_ABLATION_WATCHDOG_S LOA_ABLATION_WATCHDOG_GRACE_S DOCKER_STUB_NO_IMAGE LOA_ABLATION_OUTAGE_BREAKER
  RES="$T/res"
  # hermetic codex credentials (KF-048 pre-flight): an empty directory unless a case writes one
  mkdir -p "$T/creds/.codex"; export LOA_EVAL_CREDS_HOME="$T/creds"
}

teardown() {
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

# ra <args…> — the runner with the stubs and the test locations
ra() {
  run "$RA" --source-commit "$SHA" --results-root "$RES" --self-check-log "$T/self-check.log" \
    --pipeline-bin "$FX/ablation-pipeline-stub.sh" --grade-bin "$FX/ablation-grade-stub.sh" --docker-bin "$T/bin/docker" "$@"
}
rules() { printf '%s\n' "$@" > "$T/rules"; export STUB_RULES="$T/rules"; }
row() { jq -c --arg r "$1" 'select(.run_id == $r)' "$RES/runs.jsonl"; }

@test "RAB-1 --dry-run: plan shape (arms x applicable tasks x trials), one refused line per inapplicable pair, trial-major order, MANIFEST.json with every §3.4 field, no run dir and no pipeline call" {
  ra --arms a0_bare,a1_full,a4_no_gates --tasks bugfix-v2-02,review-01 --trials-build 2 --trials-review 1 --batch b1 \
     --max-usd 100 --pre-registration-ref "NOTES ## Pre-registration 2026-10-15T08:00:00Z" --dry-run
  [ "$status" -eq 0 ]
  grep -q '^plan: 3 arms, 2 tasks, 8 trials, shuffle seed 20261015' <<<"$output"
  [ "$(grep -c '^refused: ' <<<"$output")" -eq 1 ]
  grep -q '^refused: a4_no_gates review-01 review-catch (task_types \["build"\]) DEC-0405$' <<<"$output"
  # one line per trial: arm task type trial run_id; trial 1 block (5 pairs) before trial 2 (3 build pairs)
  lines="$(grep -E '^a[0-9]_[a-z_]+ ' <<<"$output")"
  [ "$(wc -l <<<"$lines")" -eq 8 ]
  [ "$(awk '{print $4}' <<<"$lines" | tr '\n' ,)" = "1,1,1,1,1,2,2,2," ]
  [ "$(awk '$4 == 2 {print $3}' <<<"$lines" | sort -u)" = "bug-fix" ]
  ! grep -q '^a4_no_gates review-01' <<<"$lines" || false
  while read -r a t ty n rid; do [ "$rid" = "b1-$a-$t-t$n" ]; done <<<"$lines"
  M="$RES/b1/MANIFEST.json"
  [ -f "$M" ]
  [ "$(ls -A "$RES/b1")" = "MANIFEST.json" ]
  [ ! -e "$T/stub.log" ]
  for k in arm_map shuffle_seed plan fingerprint image_digest executor_mode tools trials_per_type caps pre_registration_ref \
           suite_manifest_sha256 suite_version source_commit source_commit_dot_claude_delta cli_version phase_models gate \
           agy_opt_in schema_version created arms tasks trials_planned dry_run; do
    jq -e --arg k "$k" 'has($k)' "$M" >/dev/null || { echo "missing $k"; false; }
  done
  [ "$(jq -r '.dry_run' "$M")" = true ]
  [ "$(jq -r '.source_commit' "$M")" = "$SHA" ]
  [ "$(jq -r '.agy_opt_in' "$M")" = false ]
  [ "$(jq -r '.schema_version' "$M")" = 1 ]
  [ "$(jq -r '.shuffle_seed' "$M")" = 20261015 ]
  [ "$(jq -r '.trials_planned' "$M")" = 8 ]
  [ "$(jq -r '.arm_map | length' "$M")" = 8 ]
  [ "$(jq -r '.arm_map["b1-a1_full-review-01-t1"]' "$M")" = a1_full ]
  [ "$(jq -c '.trials_per_type' "$M")" = '{"build":2,"review-catch":1}' ]
  # Sprint 261 (DEC-0567): caps gains run_usd_by_type, the effective per-kind caps
  [ "$(jq -c '.caps' "$M")" = '{"cycle_usd":1500,"run_usd":12,"reserve_usd":250,"max_usd":100,"run_usd_by_type":{"build":15,"review-catch":20}}' ]
  [ "$(jq -r '.executor_mode' "$M")" = container ]
  [ "$(jq -r '.image_digest' "$M")" = "sha256:feedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedface" ]
  [ "$(jq -r '.cli_version' "$M")" = "2.1.299" ]   # the image's CLI, not the host's 2.1.300
  [ "$(jq -r '.fingerprint' "$M" | cut -c1-3)" = "fp:" ]
  [ "$(jq -r '.tools' "$M")" = "Bash,Read,Grep,Glob,Write,Edit,Task,WebFetch" ]
  [ "$(jq -r '.phase_models.REVIEW' "$M")" = "global.anthropic.claude-fable-5-1" ]
  [ "$(jq -r '.pre_registration_ref' "$M")" = "NOTES ## Pre-registration 2026-10-15T08:00:00Z" ]
  [ "$(jq -r '.suite_manifest_sha256' "$M")" = "$(python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$REPO_ROOT/grimoires/loa/evals/ablation-2.0/MANIFEST.sha256")" ]
  [ "$(jq -r '.refused | length' "$M")" = 1 ]
  # the watchdog deadline is twice the phase-sum timeout. Suite v2 build tasks carry bounds
  # timeout_min {IMPLEMENT: 35}: A1 build 15 + 35 + 30 + 15 + 30 + 15 = 140 min, A4 build 15 + 35 = 50,
  # A1 review-catch (no bounds) 60. A0 BARE on a v2 build task is 80 min: the task's bounds (DEC-0580)
  # override the suite's phase_defaults BARE 70, as pipeline-run.sh's PLAN + IMPLEMENT + 2 x FIX derivation does
  [ "$(jq -r '[.plan[] | select(.arm == "a0_bare" and .type == "bug-fix")][0].watchdog_s' "$M")" = 9600 ]   # BARE = 15 + 35 + 2 x 15 on a v2 task (per-task bounds, DEC-0580)
  [ "$(jq -r '[.plan[] | select(.arm == "a1_full" and .type == "bug-fix")][0].watchdog_s' "$M")" = 16800 ]
  [ "$(jq -r '[.plan[] | select(.arm == "a1_full" and .type == "bug-fix")][0].phase_sum_min' "$M")" = 140 ]
  [ "$(jq -r '[.plan[] | select(.arm == "a1_full" and .type == "review-catch")][0].phase_sum_min' "$M")" = 60 ]
  [ "$(jq -r '[.plan[] | select(.arm == "a4_no_gates")][0].phase_sum_min' "$M")" = 50 ]
}

@test "RAB-27 --types filters the plan by task type (Sprint 261 calibration dry run): build keeps the twelve build tasks, review-catch the four; the a0 BARE budget on a v2 task is 80 min" {
  ra --arms a0_bare --types build --trials-build 2 --batch ty1 --dry-run
  [ "$status" -eq 0 ]
  [ "$(jq -r '.tasks | length' "$RES/ty1/MANIFEST.json")" = 12 ]
  [ "$(jq -r '[.tasks[].type] | unique | join(",")' "$RES/ty1/MANIFEST.json")" = "bug-fix,feature-build,refactor" ]
  [ "$(jq -r '.trials_planned' "$RES/ty1/MANIFEST.json")" = 24 ]
  [ "$(jq -r '[.plan[] | select(.arm == "a0_bare")][0].phase_sum_min' "$RES/ty1/MANIFEST.json")" = 80 ]
  ra --arms a1_full --types review-catch --trials-review 1 --batch ty2 --dry-run
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.tasks[].id] | join(",")' "$RES/ty2/MANIFEST.json")" = "review-01,review-02,review-03,review-04" ]
  ra --arms a1_full --types nope --batch ty3 --dry-run
  [ "$status" -eq 2 ]
}

@test "RAB-2 the shuffle is a seeded Fisher-Yates per trial block: reproducible for a seed (and equal to random.Random(seed).shuffle), different for another seed" {
  ra --arms a0_bare,a1_full,a3_one_voice --tasks bugfix-v2-02,refactor-v2-05,review-01 --trials-build 2 --trials-review 2 --batch s1 --dry-run
  [ "$status" -eq 0 ]
  first="$(jq -r '[.plan[] | "\(.arm)/\(.task_id)/\(.trial)"] | join(",")' "$RES/s1/MANIFEST.json")"
  ra --arms a0_bare,a1_full,a3_one_voice --tasks bugfix-v2-02,refactor-v2-05,review-01 --trials-build 2 --trials-review 2 --batch s2 --dry-run
  [ "$(jq -r '[.plan[] | "\(.arm)/\(.task_id)/\(.trial)"] | join(",")' "$RES/s2/MANIFEST.json")" = "$first" ]
  # an independent re-derivation: arm-major blocks, tasks by id, one generator, blocks in trial order
  want="$(python3 -I -c '
import random
rng = random.Random(20261015); out = []
for t in (1, 2):
    b = [(a, k) for a in ("a0_bare", "a1_full", "a3_one_voice") for k in ("bugfix-v2-02", "refactor-v2-05", "review-01")]
    rng.shuffle(b); out += ["%s/%s/%d" % (a, k, t) for a, k in b]
print(",".join(out))')"
  [ "$first" = "$want" ]
  ra --arms a0_bare,a1_full,a3_one_voice --tasks bugfix-v2-02,refactor-v2-05,review-01 --trials-build 2 --trials-review 2 --batch s3 --seed 7 --dry-run
  [ "$status" -eq 0 ]
  other="$(jq -r '[.plan[] | "\(.arm)/\(.task_id)/\(.trial)"] | join(",")' "$RES/s3/MANIFEST.json")"
  [ "$other" != "$first" ]
  [ "$(jq -r '.shuffle_seed' "$RES/s3/MANIFEST.json")" = 7 ]
  # the same multiset of trials, still trial-major
  [ "$(tr , '\n' <<<"$other" | sort)" = "$(tr , '\n' <<<"$first" | sort)" ]
  [ "$(jq -r '[.plan[].trial] | join(",")' "$RES/s3/MANIFEST.json")" = "1,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2,2" ]
}

@test "RAB-3 hard gate (DEC-0435): a non-smoke batch without MANIFEST.sha256, without the self-check log, or with a task lacking REVIEW.md is refused (exit 2, REFUSED.txt only); with all three their hashes land in MANIFEST.json gate" {
  S="$T/suite"; cp -r "$REPO_ROOT/grimoires/loa/evals/ablation-2.0" "$S"
  ra --arms a1_full --tasks bugfix-v2-02 --suite-root "$S" --batch g0 --dry-run
  [ "$status" -eq 0 ]
  G="$RES/g0/MANIFEST.json"
  [ "$(jq -r '.gate.review_md | length' "$G")" = 16 ]
  [ "$(jq -r '.gate.self_check_pass_lines' "$G")" = 36 ]
  [ "$(jq -r '.gate.manifest_sha256' "$G")" = "$(jq -r '.suite_manifest_sha256' "$G")" ]
  [ "$(jq -r '.gate.self_check_log_sha256' "$G")" = "$(python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$T/self-check.log")" ]
  [ "$(jq -r '.gate.review_md["review-03"]' "$G")" = "$(python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$S/tasks/review-03/REVIEW.md")" ]
  # 1. the self-check log missing
  run "$RA" --source-commit "$SHA" --results-root "$RES" --self-check-log "$T/nope.log" --docker-bin "$T/bin/docker" \
    --arms a1_full --tasks bugfix-v2-02 --suite-root "$S" --batch g1 --dry-run
  [ "$status" -eq 2 ]
  [ "$(ls -A "$RES/g1")" = "REFUSED.txt" ]
  grep -q 'self-check log .* is missing' "$RES/g1/REFUSED.txt"
  # a log with a FAIL line, or too few PASS lines
  { cat "$T/self-check.log"; echo "self-check base x: FAIL hidden 0/1"; } > "$T/fail.log"
  run "$RA" --source-commit "$SHA" --results-root "$RES" --self-check-log "$T/fail.log" --docker-bin "$T/bin/docker" \
    --arms a1_full --tasks bugfix-v2-02 --suite-root "$S" --batch g1b --dry-run
  [ "$status" -eq 2 ]; grep -q '1 FAIL line' "$RES/g1b/REFUSED.txt"
  head -35 "$T/self-check.log" > "$T/short.log"
  run "$RA" --source-commit "$SHA" --results-root "$RES" --self-check-log "$T/short.log" --docker-bin "$T/bin/docker" \
    --arms a1_full --tasks bugfix-v2-02 --suite-root "$S" --batch g1c --dry-run
  [ "$status" -eq 2 ]; grep -q '35 PASS lines, want 36' "$RES/g1c/REFUSED.txt"
  # 2. a task without REVIEW.md (the suite re-frozen so only the gate can refuse)
  rm "$S/tasks/review-02/REVIEW.md"
  "$REPO_ROOT/evals/harness/freeze.sh" --smoke --root "$S" >/dev/null
  ra --arms a1_full --tasks bugfix-v2-02 --suite-root "$S" --batch g2 --dry-run
  [ "$status" -eq 2 ]
  grep -q 'no REVIEW.md in tasks/{review-02}' "$RES/g2/REFUSED.txt"
  [ ! -e "$RES/g2/MANIFEST.json" ]
  # 3. no MANIFEST.sha256
  rm "$S/MANIFEST.sha256"
  ra --arms a1_full --tasks bugfix-v2-02 --suite-root "$S" --batch g3 --dry-run
  [ "$status" -eq 2 ]
  grep -q 'MANIFEST.sha256 is missing' "$RES/g3/REFUSED.txt"
  [ "$(ls -A "$RES/g3")" = "REFUSED.txt" ]
}

@test "RAB-4 --smoke skips the hard gate but still requires the freeze; smoke rows go to the batch's rows.jsonl, graded with --tasks-dir smoke" {
  S="$T/suite"; cp -r "$REPO_ROOT/grimoires/loa/evals/ablation-2.0" "$S"
  rm "$S/tasks/review-02/REVIEW.md"; "$REPO_ROOT/evals/harness/freeze.sh" --smoke --root "$S" >/dev/null
  run "$RA" --source-commit "$SHA" --results-root "$RES" --self-check-log "$T/nope.log" --suite-root "$S" \
    --pipeline-bin "$FX/ablation-pipeline-stub.sh" --grade-bin "$FX/ablation-grade-stub.sh" --docker-bin "$T/bin/docker" \
    --smoke --arms a0_bare,a1_full,a4_no_gates --batch smoke-t1 --max-usd 100
  [ "$status" -eq 0 ]
  B="$RES/smoke-t1"
  [ "$(jq -r '.gate' "$B/MANIFEST.json")" = null ]
  [ "$(jq -r '.smoke' "$B/MANIFEST.json")" = true ]
  [ "$(jq -r '.tasks_dir' "$B/MANIFEST.json")" = smoke ]
  [ "$(jq -c '.trials_per_type' "$B/MANIFEST.json")" = '{"build":1,"review-catch":1}' ]
  # the smoke set grows by cycle (cycle-133 added smoke-review-c133 and -c133b): 3 arms x every smoke task,
  # minus a4_no_gates (build only), which refuses each review-catch smoke task (DEC-0405)
  nsmoke=$(ls -d "$S"/smoke/*/ | wc -l); nreview=$(grep -l '^type: review-catch' "$S"/smoke/*/task.yaml | wc -l)
  expect=$(( 3 * nsmoke - nreview )); [ "$expect" -ge 5 ]
  [ "$(wc -l < "$B/rows.jsonl")" -eq "$expect" ]
  [ ! -e "$RES/runs.jsonl" ]
  [ ! -e "$B/.gitignore" ]
  "$REPO_ROOT/evals/harness/ablation-row.sh" --validate "$B/rows.jsonl" --allow-ungraded
  [ "$(grep -c -- '--tasks-dir smoke' "$T/grade.log")" -eq "$expect" ]
  # the batch's suite file reaches every grader call (suite v3: the freeze check needs the version the tasks carry)
  [ "$(grep -c -- '--suite-file ablation-2.0.yaml' "$T/grade.log")" -eq "$expect" ]
  [ "$(jq -r '.state' "$B/STATUS.json")" = complete ]
  grep -q 'cycle spend USD' "$B/spend.txt"
  grep -q "^.* batch smoke-t1 spend USD $(awk -v n="$expect" 'BEGIN{printf "%g", n * 2.5}')" "$B/spend.txt"   # the stub bills USD 2.5 a trial
  # a drifted smoke file is refused by the freeze
  echo "drift" >> "$S/smoke/smoke-review-01/TASK.md"
  run "$RA" --source-commit "$SHA" --results-root "$RES" --suite-root "$S" --docker-bin "$T/bin/docker" \
    --smoke --arms a1_full --batch smoke-t2 --dry-run
  [ "$status" -eq 2 ]
  grep -q 'freeze.sh --check' "$RES/smoke-t2/REFUSED.txt"
}

@test "RAB-5 dispatch and rows: completed rows validate; agent_error is never retried (not even when the agent writes 'rate limit'); a transport failure is retried once (attempts 2, retry_reason, one row) and twice is transport_error; a cap failure charges run_cap; a grade exit 2 rows infrastructure_error" {
  rules '*-bugfix-v2-05-* agent_error' '*-refactor-v2-05-* transport_once' '*-refactor-v2-06-* transport' '*-feature-v2-01-* cap_failure' '*-feature-v2-05-* ok'
  export STUB_GRADE_FAIL='*-feature-v2-05-*'
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05,refactor-v2-05,refactor-v2-06,feature-v2-01,feature-v2-05,review-01 --trials-build 1 --trials-review 1 \
     --batch d1 --concurrency 2
  [ "$status" -eq 1 ]   # partial: the transport_error and infrastructure_error rows are excluded
  B="$RES/d1"
  "$REPO_ROOT/evals/harness/ablation-row.sh" --validate "$RES/runs.jsonl"
  [ "$(wc -l < "$RES/runs.jsonl")" -eq 7 ]
  [ "$(jq -r '.run_id' "$RES/runs.jsonl" | sort -u | wc -l)" -eq 7 ]
  [ "$(row d1-a1_full-bugfix-v2-02-t1 | jq -r '.status, .attempts, .retry_reason, .arm, .batch' | tr '\n' ' ')" = "completed 1 null a1_full d1 " ]
  [ "$(row d1-a1_full-review-01-t1 | jq -r '.defect_catch_rate')" = "0.5" ]
  [ "$(row d1-a1_full-bugfix-v2-05-t1 | jq -r '.status, .attempts' | tr '\n' ' ')" = "agent_error 1 " ]
  [ "$(grep -c 'd1-a1_full-bugfix-v2-05-t1 ' "$T/stub.log")" -eq 1 ]
  [ "$(grep -c 'd1-a1_full-refactor-v2-05-t1 ' "$T/stub.log")" -eq 2 ]
  grep -q 'd1-a1_full-refactor-v2-05-t1 a1_full refactor-v2-05 1 refactor-v2-05-t1-r2$' "$T/stub.log"
  [ "$(row d1-a1_full-refactor-v2-05-t1 | jq -r '.status, .attempts' | tr '\n' ' ')" = "completed 2 " ]
  [ "$(row d1-a1_full-refactor-v2-05-t1 | jq -r '.retry_reason')" = "transport: stderr in phase FIX2" ]
  [ -d "$B/a1_full/refactor-v2-05-t1" ] && [ -d "$B/a1_full/refactor-v2-05-t1-r2" ]
  [ "$(row d1-a1_full-refactor-v2-06-t1 | jq -r '.status, .attempts' | tr '\n' ' ')" = "transport_error 2 " ]
  [ "$(row d1-a1_full-feature-v2-01-t1 | jq -r '.status')" = cap_failure ]
  [ "$(row d1-a1_full-feature-v2-05-t1 | jq -r '.status')" = infrastructure_error ]
  grep -q 'grade exit 2' "$B/a1_full/feature-v2-05-t1.log"
  S="$B/STATUS.json"
  [ "$(jq -r '.state' "$S")" = partial ]
  [ "$(jq -c '.per_arm.a1_full' "$S")" = '{"trials_planned":7,"launched":7,"completed":3,"failed":1,"excluded":2,"cap_failures":1,"degraded":0,"skipped_paused":0}' ]
  [ "$(jq -r '.retries | length' "$S")" = 2 ]
  [ "$(jq -r '.retries[] | select(.run_id == "d1-a1_full-refactor-v2-05-t1") | .first_attempt_usd' "$S")" = 2.5 ]
  # rows 7 x 2.5 = 17.5; first attempts 2 x 2.5; the build cap failure (2.5 < 15, the build
  # cap since DEC-0567; 12 before) is charged 15: 17.5 - 2.5 + 15 + 5 = 35
  [ "$(jq -r '.spend.rows_usd' "$S")" = 17.5 ]
  [ "$(jq -r '.spend.ledger_usd' "$S")" = 5 ]
  [ "$(jq -r '.spend.assumed_cap_trials' "$S")" = 1 ]
  [ "$(jq -r '.spend.spent_usd' "$S")" = 35 ]
  [ "$(jq -r '.resume_cursor' "$S")" = 7 ]
  jq -e '.finished != null and .drift == null and .paused_arms == {} and .cuts == []' "$S" >/dev/null
}

@test "RAB-6 took-effect pause (DEC-0418): a run whose evidence fails rows infrastructure_error and pauses the arm, later trials of that arm do not launch; --resume --clear-arm continues them" {
  rules '*-a1_full-bugfix-v2-02-t1 bad_evidence'
  ra --arms a0_bare,a1_full --tasks bugfix-v2-02,bugfix-v2-05 --trials-build 2 --batch p1 --concurrency 1
  [ "$status" -eq 1 ]
  B="$RES/p1" S="$RES/p1/STATUS.json"
  [ "$(row p1-a1_full-bugfix-v2-02-t1 | jq -r '.status')" = infrastructure_error ]
  jq -e '.paused_arms.a1_full | test("p1-a1_full-bugfix-v2-02-t1: took-effect exit 1: arm a1_full: integrity_clean FAIL")' "$S" >/dev/null
  # every a1_full entry after the failing one in plan order never reached the pipeline
  after="$(jq -r '.plan | (map(.run_id) | index("p1-a1_full-bugfix-v2-02-t1")) as $k | .[$k + 1:][] | select(.arm == "a1_full") | .run_id' "$B/MANIFEST.json")"
  [ -n "$after" ]
  for r in $after; do ! grep -q "^$r " "$T/stub.log" || false; done
  [ "$(grep -c ' a0_bare ' "$T/stub.log")" -eq 4 ]
  [ "$(jq -r '.per_arm.a1_full.skipped_paused' "$S")" -eq "$(wc -w <<<"$after")" ]
  [ "$(jq -r '.state' "$S")" = partial ]
  grep -q 'PAUSED arm a1_full' "$B/run.log"
  # --clear-arm needs --resume
  ra --arms a1_full --batch p1 --clear-arm a1_full
  [ "$status" -eq 2 ]
  unset STUB_RULES
  : > "$T/stub.log"
  ra --batch p1 --resume --clear-arm a1_full
  [ "$status" -eq 1 ]   # the paused trial's infrastructure_error row stays excluded
  for r in $after; do grep -q "^$r " "$T/stub.log"; done
  [ "$(wc -l < "$T/stub.log")" -eq "$(wc -w <<<"$after")" ]
  [ "$(jq -r '.paused_arms' "$S")" = "{}" ]
  [ "$(wc -l < "$RES/runs.jsonl")" -eq 8 ]
  [ "$(jq -r '.run_id' "$RES/runs.jsonl" | sort -u | wc -l)" -eq 8 ]
  [ "$(jq -r '.per_arm.a1_full.completed' "$S")" -eq 3 ]
  [ "$(jq -r '.resume_cursor' "$S")" -eq 8 ]
}

@test "RAB-7 drift guard (DEC-0407): an init claude_code_version other than MANIFEST cli_version fails the batch (state failed, drift populated, nothing more launches); a foreign model id does too" {
  rules '* drift_cli'
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05,bugfix-v2-06 --trials-build 1 --batch dr1 --concurrency 1
  [ "$status" -eq 3 ]
  S="$RES/dr1/STATUS.json"
  [ "$(jq -r '.state' "$S")" = failed ]
  [ "$(jq -r '.drift.field, .drift.expected, .drift.got' "$S" | tr '\n' ' ')" = "cli_version 2.1.299 9.9.9 " ]
  [ "$(wc -l < "$T/stub.log")" -eq 1 ]
  [ "$(jq -r '.drift.run_id' "$S")" = "$(awk '{print $1}' "$T/stub.log")" ]
  [ "$(jq -r '.status' "$RES/runs.jsonl")" = infrastructure_error ]
  # a resume of a drifted batch is refused
  ra --batch dr1 --resume
  [ "$status" -eq 2 ]
  rules '* drift_model'
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch dr2
  [ "$status" -eq 3 ]
  jq -e '.drift.field | startswith("models_used.")' "$RES/dr2/STATUS.json" >/dev/null
  # DEC-0545: the requested model is absent; got is the sorted models_used keys, expected the manifest model
  [ "$(jq -c '[.drift.field, .drift.expected, .drift.got]' "$RES/dr2/STATUS.json")" = '["models_used.PLAN","claude-opus-5-5",["global.anthropic.claude-haiku-9-9"]]' ]
}

@test "RAB-8 watchdog (DEC-0429): a pipeline that hangs past the deadline (with a running record, or with none) is SIGTERMed and rowed interrupted" {
  rules '*-bugfix-v2-02-* hang' '*-bugfix-v2-05-* hang_norecord'
  export LOA_ABLATION_WATCHDOG_S=2 LOA_ABLATION_WATCHDOG_GRACE_S=2
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05 --trials-build 1 --batch w1 --concurrency 2
  [ "$status" -eq 3 ]   # no trial completed
  [ "$(row w1-a1_full-bugfix-v2-02-t1 | jq -r '.status')" = interrupted ]
  [ "$(row w1-a1_full-bugfix-v2-05-t1 | jq -r '.status')" = interrupted ]
  [ "$(jq -r '.synthesized_by' "$RES/w1/a1_full/bugfix-v2-05-t1/meta/pipeline.json")" = run-ablation.sh ]
  [ "$(grep -c 'watchdog: .* SIGTERM' "$RES/w1/run.log")" -eq 2 ]
  [ "$(jq -r '.per_arm.a1_full.excluded' "$RES/w1/STATUS.json")" = 2 ]
  # every interrupted trial without a reported cost is charged the run cap
  [ "$(jq -r '.spend.assumed_cap_trials' "$RES/w1/STATUS.json")" = 2 ]
}

@test "RAB-9 --max-usd: USD 5 per trial under max 12 launches two (0+7 hint, 5+5) and cuts the third (10+5 > 12) with cuts[] populated; exit 1" {
  export STUB_COST=5
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05,bugfix-v2-06,bugfix-v2-07 --trials-build 1 --batch c1 --concurrency 1 --max-usd 12
  [ "$status" -eq 1 ]
  S="$RES/c1/STATUS.json"
  [ "$(wc -l < "$T/stub.log")" -eq 2 ]
  [ "$(jq -c '.cuts' "$S")" = '[{"reason":"max_usd","spent":10,"in_flight_reserved":0,"max":12,"est_next":5,"trials_launched":2,"at_trial":3}]' ]
  [ "$(jq -r '.state' "$S")" = partial ]
  [ "$(jq -r '.spend.spent_usd, .spend.max_usd' "$S" | tr '\n' ' ')" = "10 12 " ]
  [ "$(jq -r '.resume_cursor' "$S")" = 2 ]
  grep -q 'cut: max_usd 12 reached after 2 trials' "$RES/c1/run.log"
}

@test "RAB-10 --resume: an interrupted batch (STATUS mid-plan, two rows, one stale run dir) resumes without duplicate run_ids and finishes" {
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05,bugfix-v2-06,bugfix-v2-07 --trials-build 1 --batch r1 --concurrency 1
  [ "$status" -eq 0 ]
  B="$RES/r1"
  mapfile -t ids < <(jq -r '.plan[].run_id' "$B/MANIFEST.json")
  # the driver "died" after two rows: the third trial left a run dir, the fourth never started
  head -2 "$RES/runs.jsonl" > "$T/rows" && mv "$T/rows" "$RES/runs.jsonl"
  third="$(jq -r --arg r "${ids[2]}" '.plan[] | select(.run_id == $r) | .run_dir' "$B/MANIFEST.json")"
  fourth="$(jq -r --arg r "${ids[3]}" '.plan[] | select(.run_id == $r) | .run_dir' "$B/MANIFEST.json")"
  rm -rf "${B:?}/$fourth"
  jq '.state = "running" | .finished = null | .resume_cursor = 2' "$B/STATUS.json" > "$T/st" && mv "$T/st" "$B/STATUS.json"
  : > "$T/stub.log"
  ra --batch r1 --resume
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$T/stub.log")" -eq 2 ]
  grep -q "^${ids[2]} .* $(basename "$third")-r2$" "$T/stub.log"
  grep -q "^${ids[3]} .* $(basename "$fourth")$" "$T/stub.log"
  [ -d "$B/$third" ] && [ -d "$B/$third-r2" ]
  [ "$(wc -l < "$RES/runs.jsonl")" -eq 4 ]
  [ "$(jq -r '.run_id' "$RES/runs.jsonl" | sort -u | wc -l)" -eq 4 ]
  "$REPO_ROOT/evals/harness/ablation-row.sh" --validate "$RES/runs.jsonl"
  [ "$(jq -r '.state, .resume_cursor, .per_arm.a1_full.completed, .per_arm.a1_full.launched' "$B/STATUS.json" | tr '\n' ' ')" = "complete 4 4 4 " ]
  [ "$(jq -r '.spend.rows_usd' "$B/STATUS.json")" = 10 ]
  # a completed batch resumes to a no-op, and a fresh run into it is refused
  : > "$T/stub.log"
  ra --batch r1 --resume
  [ "$status" -eq 0 ]; [ ! -s "$T/stub.log" ]
  ra --arms a1_full --tasks bugfix-v2-02 --batch r1
  [ "$status" -eq 2 ]; grep -q 'use --resume' <<<"$output"
}

@test "RAB-11 --detach re-execs in a new session, prints the batch dir and pid, and the batch completes in the background" {
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch dt1 --detach
  [ "$status" -eq 0 ]
  grep -q "^detached: batch $RES/dt1 pid [0-9]*" <<<"$output"
  pid="$(sed -n 's/.* pid \([0-9]*\).*/\1/p' <<<"$output")"
  for _ in $(seq 1 150); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
  ! kill -0 "$pid" 2>/dev/null || false
  [ "$(jq -r '.state' "$RES/dt1/STATUS.json")" = complete ]
  grep -q 'complete: 1 trials rowed' "$RES/dt1/driver.log"
}

@test "RAB-12 usage and pre-flight refusals exit 2: unknown or absent arm, smoke- batch without --smoke, resume without a batch, a missing image (REFUSED.txt), a source tree not at the commit" {
  ra --arms a9_nope --batch u1 --dry-run
  [ "$status" -eq 2 ]; grep -q "not declared" <<<"$output"
  ra --arms a8_no_ceremonies --batch u2 --dry-run
  [ "$status" -eq 2 ]; grep -q "absent: true" <<<"$output"
  ra --arms a1_full --batch smoke-x --dry-run
  [ "$status" -eq 2 ]; grep -q "reserved for --smoke" <<<"$output"
  ra --resume --batch nope
  [ "$status" -eq 2 ]
  ra --arms a1_full --tasks nope-01 --batch u3 --dry-run
  [ "$status" -eq 2 ]
  DOCKER_STUB_NO_IMAGE=1 ra --arms a1_full --tasks bugfix-v2-02 --batch u4 --dry-run
  [ "$status" -eq 2 ]; grep -q 'image loa-ablation:259 not found' "$RES/u4/REFUSED.txt"
  echo y > "$T/src/.claude/new" && git -C "$T/src" add -A && git -C "$T/src" -c user.email=t@t -c user.name=t commit -q -m two
  ra --arms a1_full --tasks bugfix-v2-02 --batch u5 --dry-run
  [ "$status" -eq 2 ]; grep -q "is not at" "$RES/u5/REFUSED.txt"
  # the default arm list is the suite's priority minus absent arms
  ra --source-commit "$(git -C "$T/src" rev-parse HEAD)" --tasks bugfix-v2-02 --batch u6 --dry-run
  [ "$status" -eq 0 ]
  [ "$(jq -r '.arms | join(",")' "$RES/u6/MANIFEST.json")" = "a0_bare,a1_full,a2_no_sprint_plan,a3_one_voice,a4_no_gates,a7_effort_medium,a5_no_flatline,a6_one_window" ]
}

@test "RAB-13 a signalled driver marks the batch partial, terminates its running pipelines by process group, and --resume reruns the unrowed trial into a fresh run dir" {
  export STUB_HANG=1
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch sg1 --detach
  [ "$status" -eq 0 ]
  pid="$(sed -n 's/.* pid \([0-9]*\).*/\1/p' <<<"$output")"
  pg=""
  for _ in $(seq 1 100); do
    f="$(ls "$RES/sg1/.jobs/"*.pgid 2>/dev/null | head -1 || true)"
    [ -n "$f" ] && { read -r pg _ < "$f"; break; }
    sleep 0.2
  done
  [ -n "$pg" ]
  kill -0 -- "-$pg"
  kill -TERM "$pid"
  for _ in $(seq 1 100); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
  ! kill -0 "$pid" 2>/dev/null || false
  for _ in $(seq 1 50); do kill -0 -- "-$pg" 2>/dev/null || break; sleep 0.2; done
  ! kill -0 -- "-$pg" 2>/dev/null || false
  [ "$(jq -r '.state, .signalled' "$RES/sg1/STATUS.json" | tr '\n' ' ')" = "partial true " ]
  [ ! -e "$RES/sg1/.lock" ]
  [ ! -s "$RES/runs.jsonl" ]
  unset STUB_HANG
  ra --batch sg1 --resume
  [ "$status" -eq 0 ]
  [ -d "$RES/sg1/a1_full/bugfix-v2-02-t1-r2" ]
  [ "$(jq -r '.status' "$RES/runs.jsonl")" = completed ]
  [ "$(jq -r '.state' "$RES/sg1/STATUS.json")" = complete ]
}

@test "RAB-14 is_pipeline_transport_failure: only an agent_error whose failing phase shows a CLI transport signature (stderr, api_error_status, an is_error result) counts; the agent's own text, a non-failing phase and a completed run never do" {
  source "$REPO_ROOT/evals/harness/lib/arms-common.sh"
  mk() {  # mk <dir> <status> <failing-label> — PLAN exit 0, then <label> exit 1
    mkdir -p "$1/meta" "$1/transcripts"
    jq -n --arg s "$2" --arg l "$3" '{status: $s, phases: [{label: "PLAN", exit: 0}, {label: $l, exit: (if $s == "completed" then 0 else 1 end)}]}' > "$1/meta/pipeline.json"
    : > "$1/transcripts/stderr-$3.log"; : > "$1/transcripts/events-$3.jsonl"
  }
  mk "$T/d1" agent_error IMPLEMENT; echo "Error: socket hang up" > "$T/d1/transcripts/stderr-IMPLEMENT.log"
  run is_pipeline_transport_failure "$T/d1"; [ "$status" -eq 0 ]; [ "$output" = "stderr IMPLEMENT" ]
  mk "$T/d2" agent_error REVIEW; echo '{"type":"result","is_error":true,"api_error_status":529}' > "$T/d2/transcripts/events-REVIEW.jsonl"
  run is_pipeline_transport_failure "$T/d2"; [ "$status" -eq 0 ]; [ "$output" = "api_error_status REVIEW" ]
  mk "$T/d3" agent_error AUDIT; echo '{"type":"result","is_error":true,"result":"Claude AI usage limit reached|1760000000"}' > "$T/d3/transcripts/events-AUDIT.jsonl"
  run is_pipeline_transport_failure "$T/d3"; [ "$status" -eq 0 ]; [ "$output" = "api_error_result AUDIT" ]
  # the agent's words: an assistant message and a non-error result naming a rate limit
  mk "$T/d4" agent_error IMPLEMENT
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"HTTP 503 rate limit overloaded"}]}}' \
    '{"type":"result","is_error":false,"result":"API Error: I hit a rate limit"}' > "$T/d4/transcripts/events-IMPLEMENT.jsonl"
  echo "the agent gave up" > "$T/d4/transcripts/stderr-IMPLEMENT.log"
  run is_pipeline_transport_failure "$T/d4"; [ "$status" -eq 1 ]
  # a signature in a phase that did not fail
  mk "$T/d5" agent_error IMPLEMENT; echo "overloaded" > "$T/d5/transcripts/stderr-PLAN.log"
  run is_pipeline_transport_failure "$T/d5"; [ "$status" -eq 1 ]
  # a completed run is never a transport failure
  mk "$T/d6" completed AUDIT; echo "overloaded" > "$T/d6/transcripts/stderr-AUDIT.log"
  run is_pipeline_transport_failure "$T/d6"; [ "$status" -eq 1 ]
}

@test "RAB-15 a start is refused while a process group recorded by an earlier (SIGKILLed) driver still runs" {
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch k1
  [ "$status" -eq 0 ]
  mkdir -p "$RES/k1/.jobs"
  setsid sleep 60 & sp=$!
  sleep 0.3
  printf '%s 0 0\n' "$sp" > "$RES/k1/.jobs/j0001.pgid"
  ra --batch k1 --resume
  [ "$status" -eq 2 ]; grep -q "still runs (process group $sp" <<<"$output"
  [ ! -e "$RES/k1/.lock" ]
  kill -TERM -- "-$sp" 2>/dev/null || kill "$sp"; wait "$sp" 2>/dev/null || true
  ra --batch k1 --resume
  [ "$status" -eq 0 ]
}

@test "RAB-16 an extra model beside the requested one (a WebFetch summariser, DEC-0545) is not drift: the trial completes and grades, the trial log names it, STATUS.json extra_models counts it, the row is not degraded" {
  rules '*-bugfix-v2-02-* extra_model'
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05 --trials-build 1 --batch x1 --concurrency 1
  [ "$status" -eq 0 ]
  S="$RES/x1/STATUS.json"
  jq -e '.drift == null and .state == "complete" and .drift_cleared == [] and .rerowed == []' "$S" >/dev/null
  [ "$(jq -c '.extra_models' "$S")" = '{"global.anthropic.claude-haiku-4-5-20251001-v1:0":{"runs":1,"output_tokens":516}}' ]
  [ "$(jq -c '.extra_models_by_run | keys' "$S")" = '["x1-a1_full-bugfix-v2-02-t1"]' ]
  grep -qF 'run-ablation: extra model global.anthropic.claude-haiku-4-5-20251001-v1:0 in FIX2 (516 output tokens; a WebFetch summariser or built-in subagent, not drift' "$RES/x1/a1_full/bugfix-v2-02-t1.log"
  ! grep -q 'extra model' "$RES/x1/a1_full/bugfix-v2-05-t1.log" || false
  [ "$(row x1-a1_full-bugfix-v2-02-t1 | jq -r '.status + " " + (.degraded | tostring) + " " + (.hidden_test_pass_rate | tostring)')" = "completed false 0.75" ]
  [ "$(wc -l < "$T/grade.log")" -eq 2 ]
  # a batch without one carries an empty object
  unset STUB_RULES
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch x0
  [ "$status" -eq 0 ]
  [ "$(jq -c '.extra_models' "$RES/x0/STATUS.json")" = '{}' ]
}

@test "RAB-17 --clear-drift: a drift recorded under the old rule on an extra-model run is re-read clean (drift null, drift_cleared[], the rest of the plan runs); a real substitution is still a drift (exit 2, STATUS.json unchanged); --clear-drift needs --resume" {
  rules '*-bugfix-v2-02-* extra_model'
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05,bugfix-v2-06 --trials-build 1 --batch cd1 --concurrency 1
  [ "$status" -eq 0 ]
  B="$RES/cd1" x=cd1-a1_full-bugfix-v2-02-t1
  # the old rule's stop: the drift recorded on the extra-model run, no other row
  jq -c --arg r "$x" 'select(.run_id == $r)' "$RES/runs.jsonl" > "$T/rows" && mv "$T/rows" "$RES/runs.jsonl"
  jq --arg r "$x" '.state = "failed" | .drift = {run_id: $r, field: "models_used.FIX2", expected: ["claude-fable-5-1", "claude-opus-5-5"],
                    got: "global.anthropic.claude-haiku-4-5-20251001-v1:0"}' "$B/STATUS.json" > "$T/st" && mv "$T/st" "$B/STATUS.json"
  cp "$B/STATUS.json" "$T/st.before"
  ra --batch cd1 --resume
  [ "$status" -eq 2 ]; grep -q 'failed on drift' <<<"$output"
  cmp "$B/STATUS.json" "$T/st.before"
  ra --arms a1_full --batch cd1 --clear-drift
  [ "$status" -eq 2 ]; grep -q -- '--clear-drift needs --resume' <<<"$output"
  : > "$T/stub.log"
  ra --batch cd1 --resume --clear-drift
  [ "$status" -eq 0 ]
  S="$B/STATUS.json"
  [ "$(jq -r '.state' "$S")" = complete ]
  jq -e '.drift == null' "$S" >/dev/null
  [ "$(jq -r '.drift_cleared | length' "$S")" = 1 ]
  [ "$(jq -r '.drift_cleared[0].run_id' "$S")" = "$x" ]
  [ "$(jq -r '.drift_cleared[0].previous.field' "$S")" = models_used.FIX2 ]
  [ "$(jq -r '.drift_cleared[0].harness_commit' "$S")" != "" ]
  jq -e '.drift_cleared[0].cleared_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' "$S" >/dev/null
  grep -qF "resume: --clear-drift $x (previous drift re-read under the current rule: none)" "$B/run.log"
  [ "$(wc -l < "$T/stub.log")" -eq 2 ]
  ! grep -q "^$x " "$T/stub.log" || false
  [ "$(wc -l < "$RES/runs.jsonl")" -eq 3 ]
  # a real substitution (the requested model absent) stays a drift
  rules '*-bugfix-v2-02-* drift_model'
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05 --trials-build 1 --batch cd2 --concurrency 1
  [ "$status" -eq 3 ]
  cp "$RES/cd2/STATUS.json" "$T/st2.before"; cp "$RES/runs.jsonl" "$T/rows2.before"
  [ "$(jq -r '.drift.run_id' "$RES/cd2/STATUS.json")" = cd2-a1_full-bugfix-v2-02-t1 ]
  ra --batch cd2 --resume --clear-drift
  [ "$status" -eq 2 ]; grep -q 'still drifts under the current rule' <<<"$output"
  cmp "$RES/cd2/STATUS.json" "$T/st2.before"
  cmp "$RES/runs.jsonl" "$T/rows2.before"
  [ ! -e "$RES/cd2/.lock" ]
}

@test "RAB-18 --rerow: an infrastructure_error row left by the old drift rule on an extra-model run is rowed again (one row, completed, rerowed[], spend counts it once, no pipeline call); an unknown id, another batch's id, a duplicated row, an interrupted row and a rerow without --resume are refused with the rows file byte-identical" {
  rules '*-bugfix-v2-02-* extra_model'
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05,bugfix-v2-06 --trials-build 1 --batch rr1 --concurrency 1
  [ "$status" -eq 0 ]
  unset STUB_RULES
  B="$RES/rr1" x=rr1-a1_full-bugfix-v2-02-t1 y=rr1-a1_full-bugfix-v2-06-t1
  xd="$B/a1_full/bugfix-v2-02-t1"
  # x's row as the old rule left it: drift, never graded, --status infrastructure_error, in its place
  rm "$xd/grade.json"
  "$REPO_ROOT/evals/harness/ablation-row.sh" --run-dir "$xd" --manifest "$B/MANIFEST.json" --status infrastructure_error \
    --task-yaml "$(jq -r --arg r "$x" '.plan[] | select(.run_id == $r) | .task_yaml' "$B/MANIFEST.json")" --out "$T/old.row"
  pos="$(jq -r '.run_id' "$RES/runs.jsonl" | grep -nxF "$x" | cut -d: -f1)"
  jq -c --arg r "$x" --slurpfile o "$T/old.row" 'if .run_id == $r then $o[0] else . end' "$RES/runs.jsonl" > "$T/rows" && mv "$T/rows" "$RES/runs.jsonl"
  jq --arg r "$x" '.state = "failed" | .drift = {run_id: $r, field: "models_used.FIX2", expected: ["claude-fable-5-1", "claude-opus-5-5"],
                    got: "global.anthropic.claude-haiku-4-5-20251001-v1:0"}' "$B/STATUS.json" > "$T/st" && mv "$T/st" "$B/STATUS.json"
  [ "$(row "$x" | jq -r '.status')" = infrastructure_error ]
  cp "$RES/runs.jsonl" "$T/rows.before"
  # refusals: exit 2, the rows file byte-identical
  ra --arms a1_full --batch rr1 --rerow "$x"
  [ "$status" -eq 2 ]; grep -q -- '--rerow needs --resume' <<<"$output"; cmp "$RES/runs.jsonl" "$T/rows.before"
  ra --batch rr1 --resume --rerow "$x"
  [ "$status" -eq 2 ]; grep -q 'failed on drift' <<<"$output"; cmp "$RES/runs.jsonl" "$T/rows.before"
  ra --batch rr1 --resume --clear-drift --rerow rr1-a1_full-nope-01-t1
  [ "$status" -eq 2 ]; grep -q 'not in the batch' <<<"$output"; cmp "$RES/runs.jsonl" "$T/rows.before"
  ra --batch rr1 --resume --clear-drift --rerow other-a1_full-bugfix-v2-02-t1
  [ "$status" -eq 2 ]; grep -q 'not a run of batch rr1' <<<"$output"; cmp "$RES/runs.jsonl" "$T/rows.before"
  { cat "$T/rows.before"; jq -c --arg r "$x" 'select(.run_id == $r)' "$T/rows.before"; } > "$RES/runs.jsonl"; cp "$RES/runs.jsonl" "$T/rows.dup"
  ra --batch rr1 --resume --clear-drift --rerow "$x"
  [ "$status" -eq 2 ]; grep -q '2 rows in' <<<"$output"; cmp "$RES/runs.jsonl" "$T/rows.dup"
  jq -c --arg r "$y" 'if .run_id == $r then .status = "interrupted" else . end' "$T/rows.before" > "$RES/runs.jsonl"; cp "$RES/runs.jsonl" "$T/rows.int"
  ra --batch rr1 --resume --clear-drift --rerow "$y"
  [ "$status" -eq 2 ]; grep -q 'the row is interrupted' <<<"$output"; cmp "$RES/runs.jsonl" "$T/rows.int"
  cp "$T/rows.before" "$RES/runs.jsonl"
  [ ! -e "$B/.lock" ]
  # the rerow
  : > "$T/stub.log"; : > "$T/grade.log"
  ra --batch rr1 --resume --clear-drift --rerow "$x"
  [ "$status" -eq 0 ]
  [ ! -s "$T/stub.log" ]
  [ "$(wc -l < "$T/grade.log")" -eq 1 ]
  [ "$(jq -r '.run_id' "$RES/runs.jsonl" | grep -cxF "$x")" -eq 1 ]
  [ "$(jq -r '.run_id' "$RES/runs.jsonl" | grep -nxF "$x" | cut -d: -f1)" = "$pos" ]
  [ "$(wc -l < "$RES/runs.jsonl")" -eq 3 ]
  [ "$(row "$x" | jq -r '.status + " " + (.degraded | tostring) + " " + (.attempts | tostring)')" = "completed false 1" ]
  "$REPO_ROOT/evals/harness/ablation-row.sh" --validate "$RES/runs.jsonl"
  # the other rows are untouched
  [ "$(grep -vF "\"run_id\":\"$x\"" "$RES/runs.jsonl")" = "$(grep -vF "\"run_id\":\"$x\"" "$T/rows.before")" ]
  S="$B/STATUS.json"
  [ "$(jq -c '.rerowed | map({run_id, from, to})' "$S")" = "[{\"run_id\":\"$x\",\"from\":\"infrastructure_error\",\"to\":\"completed\"}]" ]
  [ "$(jq -r '.state' "$S")" = complete ]
  [ "$(jq -r '.spend.rows_usd, .per_arm.a1_full.completed, .per_arm.a1_full.excluded, .per_arm.a1_full.launched' "$S" | tr '\n' ' ')" = "7.5 3 0 3 " ]
  [ "$(jq -c '.extra_models' "$S")" = '{"global.anthropic.claude-haiku-4-5-20251001-v1:0":{"runs":1,"output_tokens":516}}' ]
  grep -qF "rerow $x: infrastructure_error → completed" "$B/run.log"
  grep -q "rerow $x run_dir $xd (was infrastructure_error)" "$B/a1_full/bugfix-v2-02-t1.log"
  ! ls "$RES"/runs.jsonl.rerow.* >/dev/null 2>&1 || false   # no temp file left beside the rows file
}

@test "RAB-19 --rerun-status transport_error (DEC-0553): a finished batch's two transport rows are launched again into -r3 dirs and replaced in place (one row per run_id, rerun[], no assumed charge left, spent = rows + ledger); --rerun of a completed row, --rerun-status completed, --rerun without --resume and an id given to both --rerun and --rerow are refused with the rows file byte-identical" {
  export LOA_ABLATION_OUTAGE_BREAKER=0
  rules '*-bugfix-v2-05-* transport' '*-bugfix-v2-07-* transport'
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05,bugfix-v2-06,bugfix-v2-07 --trials-build 1 --batch rn1 --concurrency 1
  [ "$status" -eq 1 ]
  B="$RES/rn1" S="$RES/rn1/STATUS.json" x=rn1-a1_full-bugfix-v2-05-t1 y=rn1-a1_full-bugfix-v2-07-t1
  [ "$(row "$x" | jq -r '.status + " " + (.attempts | tostring)')" = "transport_error 2" ]
  [ "$(row "$y" | jq -r '.status')" = transport_error ]
  [ -d "$B/a1_full/bugfix-v2-05-t1-r2" ] && [ ! -e "$B/a1_full/bugfix-v2-05-t1-r3" ]
  # the P1 shape: a transport row reports no cost, so reconciliation would charge it the run cap
  jq -c --arg x "$x" --arg y "$y" 'if .run_id == $x or .run_id == $y then .cost_usd = 0 else . end' "$RES/runs.jsonl" > "$T/rows" && mv "$T/rows" "$RES/runs.jsonl"
  order="$(jq -r '.run_id' "$RES/runs.jsonl")"
  cp "$RES/runs.jsonl" "$T/rows.before"
  # refusals: exit 2, the rows file byte-identical, no lock left
  ra --arms a1_full --batch rn1 --rerun "$x"
  [ "$status" -eq 2 ]; grep -q -- '--rerun needs --resume' <<<"$output"; cmp "$RES/runs.jsonl" "$T/rows.before"
  ra --batch rn1 --resume --rerun-status completed
  [ "$status" -eq 2 ]; grep -q -- '--rerun-status must be transport_error, interrupted or infrastructure_error' <<<"$output"
  ra --batch rn1 --resume --rerun rn1-a1_full-bugfix-v2-02-t1
  [ "$status" -eq 2 ]; grep -q 'the row is completed; only transport_error' <<<"$output"; cmp "$RES/runs.jsonl" "$T/rows.before"
  ra --batch rn1 --resume --rerun "$x" --rerow "$x"
  [ "$status" -eq 2 ]; grep -q 'is also a --rerow' <<<"$output"; cmp "$RES/runs.jsonl" "$T/rows.before"
  [ ! -e "$B/.lock" ]
  # the rerun
  unset STUB_RULES
  : > "$T/stub.log"
  ra --batch rn1 --resume --rerun-status transport_error
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$T/stub.log")" -eq 2 ]
  grep -q "^$x a1_full bugfix-v2-05 1 bugfix-v2-05-t1-r3$" "$T/stub.log"
  grep -q "^$y a1_full bugfix-v2-07 1 bugfix-v2-07-t1-r3$" "$T/stub.log"
  # one row per run_id, in the old file order, every one completed; cycle-132 D-7.3: the replacement counts the old
  # row's 2 attempts and its own (3, the attempt limit)
  [ "$(jq -r '.run_id' "$RES/runs.jsonl")" = "$order" ]
  [ "$(jq -r '.status' "$RES/runs.jsonl" | sort -u)" = completed ]
  [ "$(row "$x" | jq -r '(.attempts | tostring) + " " + (.retry_reason | tostring)')" = "3 null" ]
  "$REPO_ROOT/evals/harness/ablation-row.sh" --validate "$RES/runs.jsonl"
  [ "$(jq -c '.rerun | map({run_id, from, to, old_cost_usd}) | sort_by(.run_id)' "$S")" = \
    "[{\"run_id\":\"$x\",\"from\":\"transport_error\",\"to\":\"completed\",\"old_cost_usd\":0},{\"run_id\":\"$y\",\"from\":\"transport_error\",\"to\":\"completed\",\"old_cost_usd\":0}]" ]
  jq -e '.rerun | all(.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T"))' "$S" >/dev/null
  # rows 4 x 2.5; ledger = the two first attempts 2 x 2.5 (+ the replaced rows' reported 0); no assumed charge
  [ "$(jq -r '.spend.rows_usd, .spend.ledger_usd, .spend.spent_usd, .spend.assumed_cap_trials' "$S" | tr '\n' ' ')" = "10 5 15 0 " ]
  jq -e '.spend.spent_usd == .spend.rows_usd + .spend.ledger_usd' "$S" >/dev/null
  [ "$(jq -r '.state, .trials_planned, .resume_cursor, (.rerun_pending | length)' "$S" | tr '\n' ' ')" = "complete 4 4 0 " ]
  [ "$(jq -c '.per_arm.a1_full | {launched, completed, excluded}' "$S")" = '{"launched":4,"completed":4,"excluded":0}' ]
  [ "$(jq -r '.retries | length' "$S")" = 2 ]   # the first run's retries are kept
  grep -qF "rerun $x: transport_error → completed (row replaced in place)" "$B/run.log"
  grep -q 'resume: 2 trial(s) flagged for a rerun' "$B/run.log"
  ! ls "$RES"/runs.jsonl.rerow.* >/dev/null 2>&1 || false
  # cycle-132 D-7.3: the row is at 3 attempts — a further --rerun is refused (the rows file unchanged)
  export STUB_RULES="$T/rules"; printf '%s\n' "$x transport" > "$T/rules"
  jq -c --arg x "$x" 'if .run_id == $x then .status = "interrupted" else . end' "$RES/runs.jsonl" > "$T/rows" && mv "$T/rows" "$RES/runs.jsonl"
  cp "$RES/runs.jsonl" "$T/rows.before"
  ra --batch rn1 --resume --rerun "$x"
  [ "$status" -eq 2 ]
  grep -q "the row is at 3 attempts; the attempt limit is 3" <<<"$output"
  cmp "$RES/runs.jsonl" "$T/rows.before"
  [ ! -e "$B/a1_full/bugfix-v2-05-t1-r4" ]
}

@test "RAB-19b --rerow and --rerun in one resume: an infrastructure_error row left by the old drift rule is rowed again and a transport row is launched again; each lands in its own STATUS array" {
  export LOA_ABLATION_OUTAGE_BREAKER=0
  rules '*-bugfix-v2-02-* extra_model' '*-bugfix-v2-06-* transport'
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05,bugfix-v2-06 --trials-build 1 --batch rn2 --concurrency 1
  [ "$status" -eq 1 ]
  unset STUB_RULES
  B="$RES/rn2" x=rn2-a1_full-bugfix-v2-02-t1 y=rn2-a1_full-bugfix-v2-06-t1
  xd="$B/a1_full/bugfix-v2-02-t1"
  rm "$xd/grade.json"
  "$REPO_ROOT/evals/harness/ablation-row.sh" --run-dir "$xd" --manifest "$B/MANIFEST.json" --status infrastructure_error \
    --task-yaml "$(jq -r --arg r "$x" '.plan[] | select(.run_id == $r) | .task_yaml' "$B/MANIFEST.json")" --out "$T/old.row"
  jq -c --arg r "$x" --slurpfile o "$T/old.row" 'if .run_id == $r then $o[0] else . end' "$RES/runs.jsonl" > "$T/rows" && mv "$T/rows" "$RES/runs.jsonl"
  order="$(jq -r '.run_id' "$RES/runs.jsonl")"
  : > "$T/stub.log"; : > "$T/grade.log"
  # infrastructure_error too: the status selection reads the rows after the rerows, so x is not launched
  ra --batch rn2 --resume --rerow "$x" --rerun-status transport_error --rerun-status infrastructure_error
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$T/stub.log")" -eq 1 ]
  grep -q "^$y a1_full bugfix-v2-06 1 bugfix-v2-06-t1-r3$" "$T/stub.log"
  [ "$(wc -l < "$T/grade.log")" -eq 2 ]
  [ "$(jq -r '.run_id' "$RES/runs.jsonl")" = "$order" ]
  [ "$(jq -r '.status' "$RES/runs.jsonl" | sort -u)" = completed ]
  S="$B/STATUS.json"
  [ "$(jq -c '.rerowed | map([.run_id, .from, .to])' "$S")" = "[[\"$x\",\"infrastructure_error\",\"completed\"]]" ]
  [ "$(jq -c '.rerun | map([.run_id, .from, .to])' "$S")" = "[[\"$y\",\"transport_error\",\"completed\"]]" ]
  [ "$(jq -r '.state, .spend.rows_usd, .spend.assumed_cap_trials, .per_arm.a1_full.completed' "$S" | tr '\n' ' ')" = "complete 7.5 0 3 " ]
}

@test "RAB-20 outage breaker (DEC-0554): three consecutive transport_error collections stop launches (partial, STATUS.outage, the message in run.log); a non-transport collection resets the count; --resume --rerun-status transport_error completes the batch and moves outage to outage_history; LOA_ABLATION_OUTAGE_BREAKER=0 runs to the end" {
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05,bugfix-v2-06,bugfix-v2-07,feature-v2-01,feature-v2-05,feature-v2-07 --trials-build 1 --batch ob1 --dry-run
  [ "$status" -eq 0 ]
  mapfile -t ids < <(jq -r '.plan[].run_id' "$RES/ob1/MANIFEST.json")
  [ "${#ids[@]}" -eq 7 ]
  # plan order: T T ok T T T | x — the ok at the third resets the count, the sixth trips it
  rules "${ids[0]} transport" "${ids[1]} transport" "${ids[2]} ok" "${ids[3]} transport" "${ids[4]} transport" "${ids[5]} transport" "${ids[6]} ok"
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05,bugfix-v2-06,bugfix-v2-07,feature-v2-01,feature-v2-05,feature-v2-07 --trials-build 1 --batch ob1 --concurrency 1
  [ "$status" -eq 1 ]
  S="$RES/ob1/STATUS.json"
  [ "$(jq -r '.state' "$S")" = partial ]
  [ "$(jq -r '.outage.consecutive, .outage.last_run_id' "$S" | tr '\n' ' ')" = "3 ${ids[5]} " ]
  jq -e '.outage.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' "$S" >/dev/null
  [ "$(jq -r '.per_arm.a1_full.launched' "$S")" -eq 6 ]
  ! grep -q "^${ids[6]} " "$T/stub.log" || false
  grep -q 'partial (outage breaker): 3 consecutive transport failures; --resume --rerun-status transport_error after the network is back' "$RES/ob1/run.log"
  grep -q 'partial (outage breaker): 3 consecutive' <<<"$output"
  jq -e '.cuts == [] and .drift == null' "$S" >/dev/null
  # the network is back
  unset STUB_RULES
  : > "$T/stub.log"
  ra --batch ob1 --resume --rerun-status transport_error
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$T/stub.log")" -eq 6 ]
  [ "$(wc -l < "$RES/runs.jsonl")" -eq 7 ]
  [ "$(jq -r '.run_id' "$RES/runs.jsonl" | sort -u | wc -l)" -eq 7 ]
  [ "$(jq -r '.status' "$RES/runs.jsonl" | sort -u)" = completed ]
  [ "$(jq -r '.state, .outage, (.outage_history | length), .outage_history[0].consecutive, (.rerun | length)' "$S" | tr '\n' ' ')" = "complete null 1 3 5 " ]
  grep -q 'resume: the outage breaker record .* is cleared' "$RES/ob1/run.log"
  # breaker off: the same plan runs to the end, every row transport_error, no outage recorded
  export LOA_ABLATION_OUTAGE_BREAKER=0
  rules '* transport'
  : > "$T/stub.log"
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05,bugfix-v2-06,bugfix-v2-07,feature-v2-01,feature-v2-05,feature-v2-07 --trials-build 1 --batch ob2 --concurrency 1
  [ "$status" -eq 3 ]   # no trial completed
  [ "$(wc -l < "$T/stub.log")" -eq 14 ]
  [ "$(jq -r 'select(.batch == "ob2") | .status' "$RES/runs.jsonl" | sort | uniq -c | awk '{print $1, $2}')" = "7 transport_error" ]
  jq -e '.outage == null and .outage_history == []' "$RES/ob2/STATUS.json" >/dev/null
  # a breaker value that is not a whole number is a usage error
  export LOA_ABLATION_OUTAGE_BREAKER=x
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch ob3
  [ "$status" -eq 2 ]; grep -q 'LOA_ABLATION_OUTAGE_BREAKER must be a whole number' <<<"$output"
}

@test "RAB-21 post-run deadlines (Sprint 260 LOW-4): a grade that hangs past LOA_ABLATION_GRADE_TIMEOUT_S rows infrastructure_error and the batch finishes; a hung took-effect too, without pausing the arm; MANIFEST watchdog records both; a non-integer value is a usage error" {
  export STUB_GRADE_HANG='*-bugfix-v2-02-*' LOA_ABLATION_GRADE_TIMEOUT_S=2
  SECONDS=0
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05,review-01 --trials-build 1 --trials-review 1 --batch gt1 --concurrency 2
  [ "$status" -eq 1 ]   # partial: the timed-out row is excluded
  [ "$SECONDS" -lt 120 ]
  B="$RES/gt1"
  [ "$(wc -l < "$RES/runs.jsonl")" -eq 3 ]
  [ "$(row gt1-a1_full-bugfix-v2-02-t1 | jq -r '.status')" = infrastructure_error ]
  [ "$(row gt1-a1_full-bugfix-v2-05-t1 | jq -r '.status')" = completed ]
  [ "$(row gt1-a1_full-review-01-t1 | jq -r '.status')" = completed ]
  grep -q 'run-ablation: grade timed out after 2s' "$B/a1_full/bugfix-v2-02-t1.log"
  ! grep -q 'grade timed out' "$B/a1_full/bugfix-v2-05-t1.log" || false
  [ "$(jq -r '.state' "$B/STATUS.json")" = partial ]
  [ "$(jq -r '.per_arm.a1_full.excluded' "$B/STATUS.json")" = 1 ]
  [ "$(jq -c '.watchdog | [.grade_timeout_s, .took_effect_timeout_s]' "$B/MANIFEST.json")" = '[2,300]' ]
  ! pgrep -f "ablation-grade-stub.sh $B" >/dev/null 2>&1 || false   # the hung grader was killed
  # a took-effect that hangs: infrastructure_error, the arm is not paused, the next trial runs
  unset STUB_GRADE_HANG
  printf '%s\n' '#!/usr/bin/env bash' 'sleep 600' > "$T/te-hang"; chmod +x "$T/te-hang"
  export LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S=1
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05 --trials-build 1 --batch gt2 --concurrency 1 --took-effect-bin "$T/te-hang"
  [ "$status" -eq 3 ]   # failed: no trial completed — but both launched (no pause after the first)
  [ "$(row gt2-a1_full-bugfix-v2-02-t1 | jq -r '.status')" = infrastructure_error ]
  [ "$(row gt2-a1_full-bugfix-v2-05-t1 | jq -r '.status')" = infrastructure_error ]
  grep -q 'run-ablation: took-effect timed out after 1s' "$RES/gt2/a1_full/bugfix-v2-02-t1.log"
  [ "$(jq -c '.paused_arms' "$RES/gt2/STATUS.json")" = '{}' ]
  [ "$(jq -r '.watchdog.took_effect_timeout_s' "$RES/gt2/MANIFEST.json")" = 1 ]
  # a deadline that is not a positive whole number is a usage error
  for v in x 0 1.5 1234567; do
    LOA_ABLATION_GRADE_TIMEOUT_S="$v" ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch gt3 --dry-run
    [ "$status" -eq 2 ]; grep -q 'LOA_ABLATION_GRADE_TIMEOUT_S must be positive whole seconds' <<<"$output"
  done
  LOA_ABLATION_GRADE_TIMEOUT_S=5 LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S=abc ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch gt4 --dry-run
  [ "$status" -eq 2 ]; grep -q 'LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S must be positive whole seconds' <<<"$output"
}

# --- Sprint 261 Task 4.2: per-task-type run caps (DEC-0559, DEC-0567) -------------------
# line <pattern> → the first run.log line number matching it (launch/done order checks)
logline() { grep -n -E "$1" "$2" | head -1 | cut -d: -f1; }

@test "RAB-22 per-kind caps in the plan and the manifest (DEC-0567): the suite's run_usd_by_type lands in MANIFEST caps; --run-cap 9 overrides both kinds; a suite without run_usd_by_type falls back to run_usd per kind; a malformed entry is a usage error" {
  ra --arms a1_full,a4_no_gates --tasks bugfix-v2-02,review-01 --trials-build 1 --trials-review 1 --batch k1 --dry-run
  [ "$status" -eq 0 ]
  grep -q 'run caps build 15 review-catch 20, in-flight reserve 20 per trial' <<<"$output"
  [ "$(jq -c '.caps.run_usd_by_type' "$RES/k1/MANIFEST.json")" = '{"build":15,"review-catch":20}' ]
  [ "$(jq -r '.caps.run_usd' "$RES/k1/MANIFEST.json")" = 12 ]
  # the single-cap override
  ra --arms a1_full --tasks bugfix-v2-02,review-01 --trials-build 1 --trials-review 1 --batch k2 --run-cap 9 --dry-run
  [ "$status" -eq 0 ]
  [ "$(jq -c '.caps | {run_usd, run_usd_by_type}' "$RES/k2/MANIFEST.json")" = '{"run_usd":9,"run_usd_by_type":{"build":9,"review-catch":9}}' ]
  grep -q 'run caps build 9 review-catch 9, in-flight reserve 9 per trial' <<<"$output"
  # a build-only plan reserves the build cap
  ra --arms a1_full --tasks bugfix-v2-02,refactor-v2-05 --trials-build 1 --batch k3 --dry-run
  [ "$status" -eq 0 ]
  grep -q 'in-flight reserve 15 per trial' <<<"$output"
  # suite v1 shape: no run_usd_by_type, both kinds take run_usd; one kind missing falls back alone
  cp "$REPO_ROOT/evals/suites/ablation-2.0.yaml" "$T/v1.yaml"
  yq -i 'del(.caps.run_usd_by_type)' "$T/v1.yaml"
  ra --arms a1_full --tasks bugfix-v2-02,review-01 --trials-build 1 --trials-review 1 --batch k4 --suite-file "$T/v1.yaml" --dry-run
  [ "$status" -eq 0 ]
  [ "$(jq -c '.caps.run_usd_by_type' "$RES/k4/MANIFEST.json")" = '{"build":12,"review-catch":12}' ]
  cp "$REPO_ROOT/evals/suites/ablation-2.0.yaml" "$T/half.yaml"
  yq -i 'del(.caps.run_usd_by_type["review-catch"])' "$T/half.yaml"
  ra --arms a1_full --tasks bugfix-v2-02,review-01 --trials-build 1 --trials-review 1 --batch k5 --suite-file "$T/half.yaml" --dry-run
  [ "$status" -eq 0 ]
  [ "$(jq -c '.caps.run_usd_by_type' "$RES/k5/MANIFEST.json")" = '{"build":15,"review-catch":12}' ]
  # a present but malformed entry, or a run_usd_by_type that is not a map: refused, never skipped
  cp "$REPO_ROOT/evals/suites/ablation-2.0.yaml" "$T/bad.yaml"
  yq -i '.caps.run_usd_by_type.build = "fifteen"' "$T/bad.yaml"
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch k6 --suite-file "$T/bad.yaml" --dry-run
  [ "$status" -eq 2 ]
  grep -q 'caps.run_usd_by_type.build is not an amount in USD: fifteen' <<<"$output"
  [ ! -e "$RES/k6/MANIFEST.json" ]
  yq -i '.caps.run_usd_by_type = [15, 20]' "$T/bad.yaml"
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch k7 --suite-file "$T/bad.yaml" --dry-run
  [ "$status" -eq 2 ]
  grep -q 'caps.run_usd_by_type must be a map' <<<"$output"
}

@test "RAB-23 dispatch passes the trial kind's cap to pipeline-run.sh --max-run-usd (build 15, review-catch 20); --run-cap 9 passes 9 to both" {
  export STUB_ARGV_LOG="$T/argv.log"
  ra --arms a1_full --tasks bugfix-v2-02,review-01 --trials-build 1 --trials-review 1 --batch k8 --concurrency 2
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$T/argv.log")" -eq 2 ]
  grep -qx 'k8-a1_full-bugfix-v2-02-t1 max-run-usd 15' "$T/argv.log"
  grep -qx 'k8-a1_full-review-01-t1 max-run-usd 20' "$T/argv.log"
  : > "$T/argv.log"
  ra --arms a1_full --tasks bugfix-v2-02,review-01 --trials-build 1 --trials-review 1 --batch k9 --concurrency 2 --run-cap 9
  [ "$status" -eq 0 ]
  grep -qx 'k9-a1_full-bugfix-v2-02-t1 max-run-usd 9' "$T/argv.log"
  grep -qx 'k9-a1_full-review-01-t1 max-run-usd 9' "$T/argv.log"
}

@test "RAB-24 assumed charges per kind (DEC-0567): a review-catch cap_failure is charged 20 and a costless failed build trial 15; a completed build trial its cost" {
  rules '*-review-01-* cap_failure' '*-bugfix-v2-02-* agent_error_nocost' '*-bugfix-v2-05-* ok'
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05,review-01 --trials-build 1 --trials-review 1 --batch ka --concurrency 2
  [ "$status" -eq 0 ]
  [ "$(row ka-a1_full-review-01-t1 | jq -r '.status, .cost_usd' | tr '\n' ' ')" = "cap_failure 2.5 " ]
  [ "$(row ka-a1_full-bugfix-v2-02-t1 | jq -r '.status, .cost_usd' | tr '\n' ' ')" = "agent_error 0 " ]
  S="$RES/ka/STATUS.json"
  # rows 2.5 + 0 + 2.5; spent = 20 (review-catch cap, not 12 or 15) + 15 (build cap) + 2.5
  [ "$(jq -r '.spend.rows_usd, .spend.spent_usd, .spend.assumed_cap_trials' "$S" | tr '\n' ' ')" = "5 37.5 2 " ]
  grep -q 'assumed cap: ka-a1_full-review-01-t1 ended cap_failure at USD 2.5; USD 20 (review-catch cap) charged to spent' "$RES/ka/run.log"
  grep -q 'assumed cap: ka-a1_full-bugfix-v2-02-t1 ended agent_error with no reported cost; USD 15 charged to spent' "$RES/ka/run.log"
}

@test "RAB-25 in-flight reservation = running trials x the largest cap among the plan's kinds (DEC-0567): a build trial running in a plan with review-catch reserves 20 (max 27.99 waits, 28 launches); a build-only plan reserves 15 (21.99 waits, 22 launches)" {
  export STUB_COST=1
  # seed 5 puts the build trial first; the second gate sees one build trial running and the
  # review-catch hint 8: 0 + 1 x 20 + 8 = 28 (a per-own-kind rule would give 23, the old cap 20)
  ra --arms a1_full --tasks bugfix-v2-02,review-01 --trials-build 1 --trials-review 1 --batch kb --concurrency 2 --seed 5 --max-usd 27.99
  [ "$status" -eq 0 ]
  [ "$(jq -r '.plan[0].task_id' "$RES/kb/MANIFEST.json")" = bugfix-v2-02 ]
  L="$RES/kb/run.log"
  [ "$(logline 'done kb-a1_full-bugfix-v2-02-t1 ' "$L")" -lt "$(logline 'launch kb-a1_full-review-01-t1 ' "$L")" ]
  ra --arms a1_full --tasks bugfix-v2-02,review-01 --trials-build 1 --trials-review 1 --batch kc --concurrency 2 --seed 5 --max-usd 28
  [ "$status" -eq 0 ]
  L="$RES/kc/run.log"
  [ "$(logline 'launch kc-a1_full-review-01-t1 ' "$L")" -lt "$(logline 'done kc-a1_full-bugfix-v2-02-t1 ' "$L")" ]
  # build only: 0 + 1 x 15 + 7 = 22
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05 --trials-build 1 --batch kd --concurrency 2 --max-usd 21.99
  [ "$status" -eq 0 ]
  first="$(jq -r '.plan[0].run_id' "$RES/kd/MANIFEST.json")" second="$(jq -r '.plan[1].run_id' "$RES/kd/MANIFEST.json")"
  L="$RES/kd/run.log"
  [ "$(logline "done $first " "$L")" -lt "$(logline "launch $second " "$L")" ]
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05 --trials-build 1 --batch ke --concurrency 2 --max-usd 22
  [ "$status" -eq 0 ]
  first="$(jq -r '.plan[0].run_id' "$RES/ke/MANIFEST.json")" second="$(jq -r '.plan[1].run_id' "$RES/ke/MANIFEST.json")"
  L="$RES/ke/run.log"
  [ "$(logline "launch $second " "$L")" -lt "$(logline "done $first " "$L")" ]
}

@test "RAB-26 --resume keeps the batch's recorded caps: the suite file's caps edited after the start (and a --run-cap on the resume) change neither the dispatch caps nor MANIFEST caps" {
  cp "$REPO_ROOT/evals/suites/ablation-2.0.yaml" "$T/suite.yaml"
  export STUB_ARGV_LOG="$T/argv.log"
  ra --arms a1_full --tasks bugfix-v2-02,review-01 --trials-build 1 --trials-review 1 --batch kf --concurrency 2 --suite-file "$T/suite.yaml"
  [ "$status" -eq 0 ]
  B="$RES/kf"
  before="$(jq -c '.caps' "$B/MANIFEST.json")"
  [ "$(jq -c '.caps.run_usd_by_type' "$B/MANIFEST.json")" = '{"build":15,"review-catch":20}' ]
  yq -i '.caps.run_usd = 50 | .caps.run_usd_by_type = {"build": 30, "review-catch": 40}' "$T/suite.yaml"
  # the driver "died" before either row landed
  : > "$RES/runs.jsonl"
  jq '.state = "running" | .finished = null | .resume_cursor = 0' "$B/STATUS.json" > "$T/st" && mv "$T/st" "$B/STATUS.json"
  : > "$T/argv.log"
  ra --batch kf --resume --run-cap 9
  [ "$status" -eq 0 ]
  grep -q -- '--run-cap 9 ignored on --resume' <<<"$output"
  grep -qx 'kf-a1_full-bugfix-v2-02-t1 max-run-usd 15' "$T/argv.log"
  grep -qx 'kf-a1_full-review-01-t1 max-run-usd 20' "$T/argv.log"
  [ "$(jq -c '.caps' "$B/MANIFEST.json")" = "$before" ]
  [ "$(wc -l < "$RES/runs.jsonl")" -eq 2 ]
}

# --- KF-048: the codex access-token freshness pre-flight (Sprint 261) ------------------------
# codex_auth <exp offset s> — a crafted auth.json whose access token is h.<base64url({"exp": now+offset})>.s;
# prints the exp instant (ISO 8601 UTC)
codex_auth() {
  python3 -I - "$T/creds/.codex/auth.json" "$1" <<'PY'
import base64, json, sys, time
exp = int(time.time()) + int(sys.argv[2])
pl = base64.urlsafe_b64encode(json.dumps({"exp": exp}).encode()).decode().rstrip("=")
json.dump({"auth_mode": "chatgpt", "tokens": {"access_token": "h.%s.s" % pl, "refresh_token": "R", "account_id": "a"}},
          open(sys.argv[1], "w"))
print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(exp)))
PY
}

@test "RAB-28 KF-048 pre-flight: an expired codex access token with a1_full planned refuses a fresh batch (exit 2, REFUSED.txt names codex and KF-048, no MANIFEST.json)" {
  codex_auth -60 >/dev/null
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf1 --max-usd 100
  [ "$status" -eq 2 ]
  grep -q 'codex access token expires .*Z, before the batch.s required horizon .*Z (now + 2 x max(summed watchdog of 1 trial(s) / concurrency, longest watchdog); KF-048) — run codex login on the host' "$RES/kf1/REFUSED.txt"
  [ ! -e "$RES/kf1/MANIFEST.json" ]
  [ ! -e "$T/stub.log" ]
  # no token material in the refusal
  ! grep -qE 'h\.[A-Za-z0-9_-]+\.s|"R"' "$RES/kf1/REFUSED.txt" || false
  ! grep -q 'refresh' <<<"$output"
}

@test "RAB-29 KF-048 pre-flight: a token that expires inside the horizon (now + 60 s; 2 x summed watchdog / concurrency is hours) is refused" {
  codex_auth 60 >/dev/null
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf2 --dry-run
  [ "$status" -eq 2 ]
  grep -q 'KF-048' "$RES/kf2/REFUSED.txt"
}

@test "RAB-30 KF-048 pre-flight: a fresh token (now + 10 days) is accepted; MANIFEST.json records codex_token_exp at second precision and codex_preflight" {
  local exp; exp="$(codex_auth 864000)"
  ra --arms a0_bare,a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf3 --dry-run
  [ "$status" -eq 0 ]
  M="$RES/kf3/MANIFEST.json"
  [ "$(jq -r '.codex_token_exp' "$M")" = "$exp" ]
  [ "$(jq -c '.codex_preflight | keys' "$M")" = '["auth_file_present","auth_mode","checked","codex_arms","horizon_source","required_until","token_exp","trials_counted"]' ]
  [ "$(jq -r '.codex_preflight.checked' "$M")" = true ]
  [ "$(jq -r '.codex_preflight.auth_file_present' "$M")" = true ]
  [ "$(jq -c '.codex_preflight.codex_arms' "$M")" = '["a1_full"]' ]
  [ "$(jq -r '.codex_preflight.token_exp' "$M")" = "$exp" ]
  [ "$(jq -r '.codex_preflight.auth_mode, .codex_preflight.trials_counted, .codex_preflight.horizon_source' "$M" | tr '\n' ' ')" = "chatgpt 2 plan " ]
  # required_until = now + 2 x max((9600 + 16800) / 3, 16800) s = now + 33600 s (DISS-C-001: the longest
  # watchdog bounds the horizon from below; the summed share alone, 17600 s, was shorter than one trial)
  jq -e '.codex_preflight.required_until | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$M"
  local ru; ru="$(jq -r '.codex_preflight.required_until' "$M")"
  python3 -I -c '
import calendar, sys, time
ru = calendar.timegm(time.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")); d = ru - time.time()
sys.exit(0 if 33600 - 120 < d < 33600 + 5 else 1)' "$ru"
  ! grep -q 'WARN no codex auth.json' <<<"$output" || false
}

@test "RAB-31 KF-048 pre-flight: an expired token with only a0_bare planned is not refused; checked false, codex_arms []" {
  codex_auth -60 >/dev/null
  ra --arms a0_bare --tasks bugfix-v2-02 --trials-build 1 --batch kf4 --dry-run
  [ "$status" -eq 0 ]
  M="$RES/kf4/MANIFEST.json"
  [ "$(jq -r '.codex_preflight.checked' "$M")" = false ]
  [ "$(jq -c '.codex_preflight.codex_arms' "$M")" = '[]' ]
  [ "$(jq -r '.codex_token_exp' "$M")" = null ]
  [ ! -e "$RES/kf4/REFUSED.txt" ]
}

@test "RAB-32 KF-048 pre-flight: no auth.json is not a refusal; one WARN line, codex_token_exp null" {
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf5 --dry-run
  [ "$status" -eq 0 ]
  [ "$(grep -c "^run-ablation: WARN no codex auth.json under $T/creds/.codex; codex-using arms will run without the OpenAI voice\$" <<<"$output")" -eq 1 ]
  M="$RES/kf5/MANIFEST.json"
  [ "$(jq -r '.codex_token_exp' "$M")" = null ]
  [ "$(jq -c '.codex_preflight' "$M")" = '{"auth_file_present":false,"auth_mode":null,"checked":false,"codex_arms":["a1_full"],"horizon_source":null,"required_until":null,"token_exp":null,"trials_counted":null}' ]
}

@test "RAB-33 KF-048 pre-flight: --smoke skips the check (an expired token is not refused)" {
  codex_auth -60 >/dev/null
  ra --smoke --arms a1_full --batch smoke-kf6 --dry-run
  [ "$status" -eq 0 ]
  [ ! -e "$RES/smoke-kf6/REFUSED.txt" ]
  [ "$(jq -r '.codex_preflight.checked' "$RES/smoke-kf6/MANIFEST.json")" = false ]
}

@test "RAB-34 KF-048 pre-flight: --dry-run with an expired token is refused (the dry run is where the operator sees it first); a malformed access token is refused too" {
  codex_auth -60 >/dev/null
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf7 --dry-run
  [ "$status" -eq 2 ]
  grep -q 'codex access token expires' "$RES/kf7/REFUSED.txt"
  [ ! -e "$RES/kf7/MANIFEST.json" ]
  echo '{"tokens": {"access_token": "not-a-jwt"}}' > "$T/creds/.codex/auth.json"
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf8 --dry-run
  [ "$status" -eq 2 ]
  grep -q 'not a three-part JWT (KF-048)' "$RES/kf8/REFUSED.txt"
  echo '{"tokens": {"access_token": "h.e30.s"}}' > "$T/creds/.codex/auth.json"   # payload {}
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf9 --dry-run
  [ "$status" -eq 2 ]
  grep -q 'no numeric exp claim (KF-048)' "$RES/kf9/REFUSED.txt"
  echo 'nope' > "$T/creds/.codex/auth.json"
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf10 --dry-run
  [ "$status" -eq 2 ]
  grep -q 'is not JSON (KF-048)' "$RES/kf10/REFUSED.txt"
}

@test "RAB-35 KF-048 pre-flight (DISS-C-003): an API-key auth.json is not refused; auth_mode apikey, checked false, one stderr note, the key never printed, MANIFEST.json written" {
  echo '{"OPENAI_API_KEY": "sk-test-dummy", "auth_mode": "apikey"}' > "$T/creds/.codex/auth.json"
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf11 --dry-run
  [ "$status" -eq 0 ]
  M="$RES/kf11/MANIFEST.json"
  [ -f "$M" ]; [ ! -e "$RES/kf11/REFUSED.txt" ]
  [ "$(grep -c '^run-ablation: codex auth.json is in API-key mode; no token horizon applies (KF-048 concerns the ChatGPT refresh token only)$' <<<"$output")" -eq 1 ]
  [ "$(jq -r '.codex_preflight.auth_mode' "$M")" = apikey ]
  [ "$(jq -r '.codex_preflight.checked' "$M")" = false ]
  [ "$(jq -r '.codex_preflight.token_exp, .codex_token_exp' "$M" | tr '\n' ' ')" = "null null " ]
  jq -e '.codex_preflight.required_until | test("^[0-9-]{10}T[0-9:]{8}Z$")' "$M"
  ! grep -rq 'sk-test-dummy' "$RES" || false
  ! grep -q 'sk-test-dummy' <<<"$output" || false
  # tokens present but empty, the key set: still API-key mode
  echo '{"OPENAI_API_KEY": "sk-test-dummy", "tokens": null}' > "$T/creds/.codex/auth.json"
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf12 --dry-run
  [ "$status" -eq 0 ]
  [ "$(jq -r '.codex_preflight.auth_mode' "$RES/kf12/MANIFEST.json")" = apikey ]
}

@test "RAB-36 KF-048 pre-flight (DISS-C-003): an auth.json with neither a tokens.access_token nor an OPENAI_API_KEY is refused, and the reason names both remedies" {
  echo '{"OPENAI_API_KEY": "", "tokens": {"refresh_token": "R"}}' > "$T/creds/.codex/auth.json"
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf13 --dry-run
  [ "$status" -eq 2 ]
  grep -q 'has neither a tokens.access_token nor an OPENAI_API_KEY (KF-048) — run codex login on the host, or set OPENAI_API_KEY in auth.json' "$RES/kf13/REFUSED.txt"
  [ ! -e "$RES/kf13/MANIFEST.json" ]
  ! grep -q '"R"' "$RES/kf13/REFUSED.txt" || false
}

@test "RAB-37 KF-048 pre-flight (DISS-C-004): --resume counts only the trials without a row; a token that outlives one trial's horizon but not the whole plan's is not refused; trials_counted 1 in STATUS.json" {
  codex_auth 864000 >/dev/null
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05,bugfix-v2-06,bugfix-v2-07 --trials-build 1 --batch kr1 --concurrency 1
  [ "$status" -eq 0 ]
  B="$RES/kr1"
  [ "$(jq -r '.codex_preflight.trials_counted' "$B/MANIFEST.json")" = 4 ]
  [ "$(jq -r '.codex_preflight.trials_counted' "$B/STATUS.json")" = 4 ]
  # one trial's horizon is 2 x its watchdog; the whole plan's is the sum of four
  one="$(jq -r '.plan[3].watchdog_s' "$B/MANIFEST.json")"; all="$(jq -r '[.plan[].watchdog_s] | add' "$B/MANIFEST.json")"
  off=$(( (2 * one + 2 * all) / 2 ))
  [ "$off" -gt $(( 2 * one + 600 )) ]; [ "$off" -lt $(( 2 * all - 600 )) ]
  head -3 "$RES/runs.jsonl" > "$T/rows" && mv "$T/rows" "$RES/runs.jsonl"
  jq '.state = "running" | .finished = null | .resume_cursor = 3' "$B/STATUS.json" > "$T/st" && mv "$T/st" "$B/STATUS.json"
  # the same token is refused for a fresh batch of that plan (the whole plan counts)
  codex_auth "$off" >/dev/null
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05,bugfix-v2-06,bugfix-v2-07 --trials-build 1 --batch kr2 --concurrency 1 --dry-run
  [ "$status" -eq 2 ]; grep -q 'summed watchdog of 4 trial(s)' "$RES/kr2/REFUSED.txt"
  : > "$T/stub.log"
  ra --batch kr1 --resume --concurrency 1
  [ "$status" -eq 0 ]
  [ ! -e "$B/REFUSED.txt" ]
  [ "$(wc -l < "$T/stub.log")" -eq 1 ]
  [ "$(jq -r '.codex_preflight.trials_counted, .codex_preflight.horizon_source, .codex_preflight.checked' "$B/STATUS.json" | tr '\n' ' ')" = "1 plan true " ]
  [ "$(jq -r '.codex_preflight.trials_counted' "$B/MANIFEST.json")" = 4 ]   # the start's record is kept
  [ "$(jq -r '.state' "$B/STATUS.json")" = complete ]
  # --rerun-status brings a rowed trial back into the count
  jq -c 'if .run_id == "'"$(jq -r '.plan[0].run_id' "$B/MANIFEST.json")"'" then .status = "transport_error" else . end' "$RES/runs.jsonl" > "$T/rows" && mv "$T/rows" "$RES/runs.jsonl"
  codex_auth 864000 >/dev/null
  ra --batch kr1 --resume --concurrency 1 --rerun-status transport_error
  [ "$status" -eq 0 ]
  [ "$(jq -r '.codex_preflight.trials_counted' "$B/STATUS.json")" = 1 ]
}

@test "RAB-38 KF-048 pre-flight (DISS-C-004): LOA_ABLATION_CODEX_HORIZON_S replaces the computed horizon (60 s against a token of 120 s, a plan of hours: not refused, horizon_source override); a non-numeric or zero value is a usage error" {
  codex_auth 120 >/dev/null
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf14 --dry-run
  [ "$status" -eq 2 ]   # the computed horizon (hours) refuses it
  LOA_ABLATION_CODEX_HORIZON_S=60 ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf15 --dry-run
  [ "$status" -eq 0 ]
  M="$RES/kf15/MANIFEST.json"
  [ "$(jq -r '.codex_preflight.horizon_source, .codex_preflight.checked, .codex_preflight.trials_counted' "$M" | tr '\n' ' ')" = "override true 1 " ]
  local ru; ru="$(jq -r '.codex_preflight.required_until' "$M")"
  python3 -I -c '
import calendar, sys, time
d = calendar.timegm(time.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")) - time.time()
sys.exit(0 if 0 < d < 62 else 1)' "$ru"
  # an override that the token does not outlive is refused, and the reason names the override
  LOA_ABLATION_CODEX_HORIZON_S=600 ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf16 --dry-run
  [ "$status" -eq 2 ]; grep -q 'now + LOA_ABLATION_CODEX_HORIZON_S; KF-048' "$RES/kf16/REFUSED.txt"
  for v in abc 0 -5 1.5; do
    LOA_ABLATION_CODEX_HORIZON_S="$v" ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf17 --dry-run
    [ "$status" -eq 2 ]
    grep -q 'LOA_ABLATION_CODEX_HORIZON_S must be positive whole seconds' <<<"$output"
    [ ! -e "$RES/kf17" ]
  done
}

@test "RAB-39 KF-048 pre-flight (DISS-C-001): the horizon is never below one trial's own watchdog; one trial (16,800 s) at concurrency 3 with a token between 2 x w / 3 and 2 x w is refused, one past 2 x w passes" {
  codex_auth 22400 >/dev/null   # 2 x 16800 / 3 = 11200 < 22400 < 33600 = 2 x 16800
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kh1 --concurrency 3 --dry-run
  [ "$status" -eq 2 ]
  grep -q '(now + 2 x max(summed watchdog of 1 trial(s) / concurrency, longest watchdog); KF-048) — run codex login on the host' "$RES/kh1/REFUSED.txt"
  [ ! -e "$RES/kh1/MANIFEST.json" ]
  codex_auth 34200 >/dev/null
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kh2 --concurrency 3 --dry-run
  [ "$status" -eq 0 ]
  M="$RES/kh2/MANIFEST.json"
  [ "$(jq -r '.plan[0].watchdog_s, .codex_preflight.trials_counted, .codex_preflight.checked' "$M" | tr '\n' ' ')" = "16800 1 true " ]
  python3 -I -c '
import calendar, sys, time
d = calendar.timegm(time.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")) - time.time()
sys.exit(0 if 33600 - 120 < d < 33600 + 5 else 1)' "$(jq -r '.codex_preflight.required_until' "$M")"
}

@test "RAB-40 KF-048 pre-flight (DISS-C-002): STATUS.json is written without the scratch dir: a driver signalled after its \$WORK is gone still records state partial with the pre-flight record (valid JSON, codex_preflight equal to MANIFEST's)" {
  codex_auth 864000 >/dev/null
  export STUB_HANG=1 TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch ks1 --detach
  [ "$status" -eq 0 ]
  pid="$(sed -n 's/.* pid \([0-9]*\).*/\1/p' <<<"$output")"
  [ -n "$pid" ]
  for _ in $(seq 1 100); do ls "$RES/ks1/.jobs/"*.pgid >/dev/null 2>&1 && break; sleep 0.2; done
  ls "$RES/ks1/.jobs/"*.pgid >/dev/null
  [ "$(jq -r '.state' "$RES/ks1/STATUS.json")" = running ]
  # the scratch dir disappears under the driver (a tmp reaper, or cleanup ahead of a late write_status)
  ls -d "$TMPDIR"/run-ablation.* >/dev/null
  find "$TMPDIR" -mindepth 1 -delete
  kill -TERM "$pid"
  for _ in $(seq 1 100); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
  ! kill -0 "$pid" 2>/dev/null || false
  unset STUB_HANG TMPDIR
  jq -e . "$RES/ks1/STATUS.json" >/dev/null
  [ "$(jq -r '.state, .signalled' "$RES/ks1/STATUS.json" | tr '\n' ' ')" = "partial true " ]
  [ "$(jq -c '.codex_preflight' "$RES/ks1/STATUS.json")" = "$(jq -c '.codex_preflight' "$RES/ks1/MANIFEST.json")" ]
  [ "$(jq -r '.codex_preflight.checked' "$RES/ks1/STATUS.json")" = true ]
  [ ! -e "$RES/ks1/STATUS.json.tmp" ]
}

@test "RAB-41 KF-048 pre-flight (DISS-C-003): --resume counts STATUS.json rerun_pending (a flagged trial with its old row, no replacement yet); a --rerow of that id takes it out again" {
  codex_auth 864000 >/dev/null
  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05 --trials-build 1 --batch kp1 --concurrency 1
  [ "$status" -eq 0 ]
  B="$RES/kp1"
  r0="$(jq -r '.plan[0].run_id' "$B/MANIFEST.json")"
  plant() { jq --arg r "$r0" '.state = "running" | .finished = null | .rerun_pending = [$r]' "$B/STATUS.json" > "$T/st" && mv "$T/st" "$B/STATUS.json"; }
  plant
  ra --batch kp1 --resume --concurrency 1
  [ "$status" -eq 0 ]
  [ "$(jq -r '.codex_preflight.trials_counted' "$B/STATUS.json")" = 1 ]
  # the planted id is not flagged again on this invocation, so the launcher keeps its row (the documented superset)
  [ "$(jq -c '.rerun_pending' "$B/STATUS.json")" = '[]' ]
  [ "$(wc -l < "$RES/runs.jsonl")" -eq 2 ]
  plant
  ra --batch kp1 --resume --concurrency 1 --rerow "$r0"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.codex_preflight.trials_counted' "$B/STATUS.json")" = 0 ]
  # a malformed rerun_pending is ignored, not fatal
  jq '.state = "running" | .finished = null | .rerun_pending = {"x": 1}' "$B/STATUS.json" > "$T/st" && mv "$T/st" "$B/STATUS.json"
  ra --batch kp1 --resume --concurrency 1
  [ "$status" -eq 0 ]
  [ "$(jq -r '.codex_preflight.trials_counted' "$B/STATUS.json")" = 0 ]
}

# --- cycle-131 Sprint 263 Task 1.7: --allow-partial (PRD FR-3 AC 1; SDD D-3.1) -----------------

@test "RAB-c131-1 --allow-partial: the two-task replication root passes the pre-flight with the flag and is refused without it; MANIFEST.json records allow_partial" {
  local R="$REPO_ROOT/grimoires/loa/evals/ablation-2.0-replication"
  ra --suite-root "$R" --arms a1_full --trials-review 1 --batch ap1 --dry-run
  [ "$status" -eq 2 ]
  grep -q 'refused: freeze.sh --check --root .*ablation-2.0-replication .* failed' <<<"$output"
  ra --suite-root "$R" --arms a1_full --trials-review 1 --batch ap2 --dry-run --allow-partial
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '^plan: 1 arms, 2 tasks, 2 trials' <<<"$output"
  [ "$(jq -r '.allow_partial' "$RES/ap2/MANIFEST.json")" = true ]
  [ "$(jq -r '[.tasks[].id] | join(",")' "$RES/ap2/MANIFEST.json")" = "review-r17,review-r18" ]
  # the default (full) root without the flag records false
  ra --arms a1_full --tasks review-01 --trials-review 1 --batch ap3 --dry-run
  [ "$status" -eq 0 ]
  [ "$(jq -r '.allow_partial' "$RES/ap3/MANIFEST.json")" = false ]
}

@test "RAB-c131-2 --allow-partial reaches every grader argv; --resume keeps the MANIFEST value and refuses a conflicting flag" {
  local R="$REPO_ROOT/grimoires/loa/evals/ablation-2.0-replication"
  ra --suite-root "$R" --arms a1_full --trials-review 1 --batch ap4 --concurrency 1 --allow-partial
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(wc -l < "$T/grade.log")" -eq 2 ]
  [ "$(grep -c -- '--allow-partial' "$T/grade.log")" -eq 2 ]
  [ "$(jq -r '.allow_partial' "$RES/ap4/MANIFEST.json")" = true ]
  # a resume without the flag takes it from the manifest (the freeze check still passes)
  ra --resume --batch ap4
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # a batch started without the flag cannot gain it on resume
  ra --arms a1_full --tasks review-01 --trials-review 1 --batch ap5 --concurrency 1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  ! grep -q -- '--allow-partial' <(grep 'ap5-' "$T/grade.log") || false
  ra --resume --batch ap5 --allow-partial
  [ "$status" -eq 2 ]
  grep -q "allow-partial conflicts with batch ap5's MANIFEST.json allow_partial false" <<<"$output"
}

@test "RAB-c131-3 oracle_closed on a1_full (cycle-131 FR-1): took-effect gets --task-yaml and passes on an overlaid review-catch run; a run without the overlay pauses the arm" {
  ra --arms a1_full --tasks review-01 --trials-review 1 --batch oc1 --concurrency 1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q 'arm a1_full: oracle_closed OK ok head:' "$RES/oc1/a1_full/review-01-t1.log"
  rules 'oc2-a1_full-review-01-t1 bad_overlay'
  ra --arms a1_full --tasks review-01,review-02 --trials-review 1 --batch oc2 --concurrency 1
  [ "$status" -ne 0 ]
  [ "$(row oc2-a1_full-review-01-t1 | jq -r '.status')" = infrastructure_error ]
  jq -e '.paused_arms.a1_full | test("oracle_closed FAIL")' "$RES/oc2/STATUS.json" >/dev/null
}

@test "RAB-c131-4 bare_model: fable (cycle-131 D-5.1): a BARE phase on Fable 5.1 is not drift, and bare_model_fable passes; another model in that BARE record is drift" {
  cp "$REPO_ROOT/evals/suites/ablation-2.0.yaml" "$T/suite.yaml"
  yq -i '.arms += [{"id": "a0_bare_fable", "label": "A0F", "task_types": ["review-catch"], "toggles": {"loa_mount": false, "bare_model": "fable"},
                    "phases": ["BARE"], "effort": "high", "took_effect": ["no_dot_claude", "bare_model_fable"]}]' "$T/suite.yaml"
  ra --suite-file "$T/suite.yaml" --arms a0_bare_fable --tasks review-01 --trials-review 1 --batch bf1 --concurrency 1
  [ "$status" -eq 0 ] || { echo "$output"; cat "$RES/bf1/a0_bare_fable/review-01-t1.log"; false; }
  [ "$(jq -r '.drift' "$RES/bf1/STATUS.json")" = null ]
  grep -q 'arm a0_bare_fable: bare_model_fable OK BARE models_used global.anthropic.claude-fable-5-1, effort_requested high' "$RES/bf1/a0_bare_fable/review-01-t1.log"
  rules 'bf2-* drift_model'
  ra --suite-file "$T/suite.yaml" --arms a0_bare_fable --tasks review-01 --trials-review 1 --batch bf2 --concurrency 1
  [ "$status" -eq 3 ]
  [ "$(jq -r '.drift.field' "$RES/bf2/STATUS.json")" = models_used.BARE ]
  [ "$(jq -r '.drift.expected' "$RES/bf2/STATUS.json")" = claude-fable-5-1 ]
}

# --- cycle-131 Sprint 264 Task 2.1: the eval_only batch context ---------------------------------

@test "RAB-c131-5 every trial a batch or a smoke launches gets --batch-context <batch> (the eval_only arms' context; cycle-132 bd-st02i: an argv flag, the variable is never set); the runner's own environment is unchanged" {
  export STUB_ENV_LOG="$T/env.log"
  [ -z "${LOA_ABLATION_BATCH_CONTEXT+x}" ]
  ra --arms a1_full --tasks review-01,review-02 --trials-review 1 --batch bc1 --concurrency 2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(wc -l < "$T/env.log")" -eq 2 ]
  [ "$(grep -c ' LOA_ABLATION_BATCH_CONTEXT=<unset> batch_context=bc1$' "$T/env.log")" -eq 2 ]
  S="$T/suite"; cp -r "$REPO_ROOT/grimoires/loa/evals/ablation-2.0" "$S"
  : > "$T/env.log"
  run "$RA" --source-commit "$SHA" --results-root "$RES" --self-check-log "$T/nope.log" --suite-root "$S" \
    --pipeline-bin "$FX/ablation-pipeline-stub.sh" --grade-bin "$FX/ablation-grade-stub.sh" --docker-bin "$T/bin/docker" \
    --smoke --arms a1_full --batch smoke-bc2 --max-usd 100
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  nsmoke=$(ls -d "$S"/smoke/*/ | wc -l); [ "$nsmoke" -ge 2 ]   # a1_full runs every smoke task (the set grows by cycle)
  [ "$(wc -l < "$T/env.log")" -eq "$nsmoke" ]
  [ "$(grep -c ' LOA_ABLATION_BATCH_CONTEXT=<unset> batch_context=smoke-bc2$' "$T/env.log")" -eq "$nsmoke" ]
  # the stub reports an absent variable as <unset> (the assertion above is not vacuous)
  : > "$T/env.log"
  "$FX/ablation-pipeline-stub.sh" --task-yaml "$S/tasks/review-01/task.yaml" --arm a1_full --run-dir "$T/manual" \
    --run-id manual-1 --trial 1 --source-tree "$T/src" --suite-file "$REPO_ROOT/evals/suites/ablation-2.0.yaml" >/dev/null 2>&1 || true
  grep -qx 'manual-1 LOA_ABLATION_BATCH_CONTEXT=<unset> batch_context=<none>' "$T/env.log"
}

# --- cycle-132 Sprint 269 Tasks 1.7a / 1.7c: matched cells, the attempt limit, --batch-context, --registration, the spend gate

# msuite — a copy of the frozen suite root whose review-01 carries k 3 (the Fable arm's k 2), refrozen; review-02 has none
msuite() {
  MS="$T/suite-m"
  cp -r "$REPO_ROOT/grimoires/loa/evals/ablation-2.0" "$MS"
  yq -i '.review_catch.bare_sessions_matched = 3 | .review_catch.bare_sessions_matched_fable = 2' "$MS/tasks/review-01/task.yaml"
  "$REPO_ROOT/evals/harness/freeze.sh" --root "$MS" --smoke >/dev/null
}
ram() { ra --suite-root "$MS" "$@"; }
sha_of() { python3 -I -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }
CELL_OF() { printf '%s/%s/a0_bare_matched/review-01-t1' "$RES" "$1"; }

@test "RAB-c132-1 dry run of the matched arms: one line per cell with sessions k, the plan line counts the session units, MANIFEST bare_sessions_by_task, overshoot_bound_usd and batch_context; a matched arm on a task without k is refused" {
  msuite
  ram --arms a0_bare_matched,a0_bare_fable_matched,a1_full --tasks review-01 --trials-review 2 --batch md1 --concurrency 3 --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '^plan: 3 arms, 1 tasks, 6 trials (10 session units in 4 matched cells), shuffle seed 20261015' <<<"$output"
  grep -qx 'a0_bare_matched review-01 review-catch 1 md1-a0_bare_matched-review-01-t1 sessions 3' <<<"$output"
  grep -qx 'a0_bare_fable_matched review-01 review-catch 2 md1-a0_bare_fable_matched-review-01-t2 sessions 2' <<<"$output"
  grep -qx 'a1_full review-01 review-catch 1 md1-a1_full-review-01-t1' <<<"$output"   # an ordinary trial's line is unchanged
  M="$RES/md1/MANIFEST.json"
  [ "$(jq -c '.bare_sessions_by_task' "$M")" = '{"a0_bare_fable_matched":{"review-01":2},"a0_bare_matched":{"review-01":3}}' ]
  [ "$(jq -r '.overshoot_bound_usd, .batch_context, .registration_sha256, .spend_gate' "$M" | tr '\n' ' ')" = "60 md1 null null " ]
  [ "$(jq -r '[.plan[] | select(.arm == "a0_bare_matched")][0] | "\(.bare_sessions) \(.watchdog_s)"' "$M")" = "3 8400" ]
  ram --arms a0_bare_matched --tasks review-01,review-02 --trials-review 1 --batch md2 --dry-run
  [ "$status" -eq 2 ]
  grep -q 'matched arm a0_bare_matched needs review_catch.bare_sessions_matched (an integer 2 … 30) on task review-02' <<<"$output"
}

@test "RAB-c132-2 a matched cell with k = 3 under the stub CLI: three session dirs and transcripts, every session with --batch-context, one cell.json, one union grade, one validated row with the summed cost" {
  msuite
  export STUB_ENV_LOG="$T/env.log"
  ram --arms a0_bare_matched --tasks review-01 --trials-review 1 --batch mk --concurrency 3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  C="$(CELL_OF mk)"
  for i in 1 2 3; do
    [ -f "$C/sessions/s$i/transcripts/events-BARE.jsonl" ] && [ -f "$C/sessions/s$i/grade.json" ] && [ -f "$C/meta/sessions/s$i.json" ]
  done
  [ ! -e "$C/sessions/s4" ]
  [ "$(grep -c 'mk-a0_bare_matched-review-01-t1-s[123] a0_bare_matched review-01 1 s[123]$' "$T/stub.log")" -eq 3 ]
  [ "$(grep -c ' LOA_ABLATION_BATCH_CONTEXT=<unset> batch_context=mk$' "$T/env.log")" -eq 3 ]
  [ "$(grep -c '^union review-01-t1 review-01 --tasks-dir tasks$' "$T/grade.log")" -eq 1 ]
  [ "$(jq -r '"\(.k) \(.sessions_valid) \(.sessions_attempted) \([.sessions[].id] | join(","))"' "$C/meta/cell.json")" = "3 3 3 s1,s2,s3" ]
  ! jq -e 'tostring | test("a0_bare_matched")' "$C/meta/cell.json" >/dev/null || false   # the grader reads it: no arm id
  [ "$(wc -l < "$RES/runs.jsonl")" -eq 1 ]
  "$REPO_ROOT/evals/harness/ablation-row.sh" --validate "$RES/runs.jsonl"
  r="$(row mk-a0_bare_matched-review-01-t1)"
  [ "$(jq -r '"\(.status) \(.degraded) \(.bare_sessions) \(.sessions_valid) \(.cost_usd) \(.all_spend_usd) \(.batch_context)"' <<<"$r")" = "completed false 3 3 7.5 7.5 mk" ]
  [ "$(jq -r '[.phases[].label] | join(",")' <<<"$r")" = "BARE-s1,BARE-s2,BARE-s3" ]
  # round 1: the cell row carries the cell's took-effect record
  [ "$(jq -c '.took_effect' <<<"$r")" = '{"no_dot_claude":true,"no_system_prompt":true,"no_audit_rows":true,"integrity_clean":true,"bare_sessions_matched":true}' ]
  [ -f "$C/sessions/s1/meta/took-effect.json" ]
  S="$RES/mk/STATUS.json"
  [ "$(jq -r '.state, .spend.spent_usd, .spend.sessions_usd, .per_arm.a0_bare_matched.launched, .per_arm.a0_bare_matched.completed' "$S" | tr '\n' ' ')" = "complete 7.5 7.5 1 1 " ]
}

@test "RAB-c132-3 --resume of a cell with one interrupted session re-runs only that session (its interrupted attempt counts), rows the cell once, and recomputes spent from the session records" {
  msuite
  ram --arms a0_bare_matched --tasks review-01 --trials-review 1 --batch mr --concurrency 3
  [ "$status" -eq 0 ]
  C="$(CELL_OF mr)"
  # the state a killed driver leaves: s3 still running, no record, no cell row
  : > "$RES/runs.jsonl"; rm -f "$C/meta/sessions/s3.json" "$C/meta/cell.json" "$C/grade.json"
  jq '.status = "running"' "$C/sessions/s3/meta/pipeline.json" > "$T/p" && mv "$T/p" "$C/sessions/s3/meta/pipeline.json"
  jq '.state = "partial"' "$RES/mr/STATUS.json" > "$T/s" && mv "$T/s" "$RES/mr/STATUS.json"
  : > "$T/stub.log"
  ram --batch mr --resume
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$T/stub.log")" = "mr-a0_bare_matched-review-01-t1-s3 a0_bare_matched review-01 1 s3-r2" ]
  [ "$(jq -r '"\(.attempts) \(.attempt_statuses | join(",")) \(.valid)"' "$C/meta/sessions/s3.json")" = "2 interrupted,completed true" ]
  [ "$(wc -l < "$RES/runs.jsonl")" -eq 1 ]
  r="$(row mr-a0_bare_matched-review-01-t1)"
  [ "$(jq -r '"\(.cost_usd) \(.all_spend_usd) \(.attempts)"' <<<"$r")" = "7.5 10 2" ] || { echo "$r"; false; }
  [ "$(jq -r '.sessions[2].run_dir' "$C/meta/cell.json")" = sessions/s3-r2 ]
  # spent: s1 2.5 + s2 2.5 (their records) + s3's interrupted attempt 2.5 + its re-run 2.5
  [ "$(jq -r '.spend.spent_usd, .state' "$RES/mr/STATUS.json" | tr '\n' ' ')" = "10 complete " ]
}

@test "RAB-c132-4 the attempt limit: a session failing on infrastructure every time ends after 3 attempts (s2, s2-r2, s2-r3), is kept invalid, every attempt is charged; the cell follows sessions_valid (2 of 3 completed; 1 of 3 degraded)" {
  msuite
  rules '*-t1-s2 transport'
  ram --arms a0_bare_matched --tasks review-01 --trials-review 1 --batch ma --concurrency 3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  C="$(CELL_OF ma)"
  [ -d "$C/sessions/s2-r3" ] && [ ! -e "$C/sessions/s2-r4" ]
  [ "$(grep -c -- '-s2 ' "$T/stub.log")" -eq 3 ]
  [ "$(jq -r '"\(.status) \(.valid) \(.attempts) \(.attempt_statuses | join(","))"' "$C/meta/sessions/s2.json")" = "transport_error false 3 transport_error,transport_error,transport_error" ]
  r="$(row ma-a0_bare_matched-review-01-t1)"
  [ "$(jq -r '"\(.status) \(.degraded) \(.sessions_valid) \(.cost_usd) \(.all_spend_usd)"' <<<"$r")" = "completed false 2 5 12.5" ]  || { echo "$r"; false; }
  [ "$(jq -r '.spend.spent_usd' "$RES/ma/STATUS.json")" = 12.5 ]
  rules '*-t1-s2 transport' '*-t1-s3 cap_failure'
  ram --arms a0_bare_matched --tasks review-01 --trials-review 1 --batch mb --concurrency 3
  C="$(CELL_OF mb)"
  [ -d "$C/sessions/s3-r3" ] && [ ! -e "$C/sessions/s3-r4" ]
  r="$(row mb-a0_bare_matched-review-01-t1)"
  [ "$(jq -r '"\(.status) \(.degraded) \(.degraded_reason) \(.sessions_valid)"' <<<"$r")" = "completed true sessions_valid < k/2 (1 of 3) 1" ]
  # the cap failures are charged max(cost, the review-catch cap 20) each
  [ "$(jq -r '.spend.spent_usd' "$RES/mb/STATUS.json")" = 70 ]
}

@test "RAB-c132-5 a refusal-fallback session and a contaminated session are kept invalid and never re-run; the session-1 figures go null when s1 is the invalid one" {
  msuite
  rules '*-t1-s1 refusal'
  export STUB_GRADE_CONTAM='*-t1-s2'
  ram --arms a0_bare_matched --tasks review-01 --trials-review 1 --batch mf --concurrency 3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  C="$(CELL_OF mf)"
  [ ! -e "$C/sessions/s1-r2" ] && [ ! -e "$C/sessions/s2-r2" ]
  [ "$(jq -r '"\(.valid) \(.attempts) \(.invalid_reason)"' "$C/meta/sessions/s1.json")" = "false 1 refusal fallback (KF-051)" ]
  [ "$(jq -r '"\(.status) \(.valid) \(.invalid_reason)"' "$C/meta/sessions/s2.json")" = "contaminated false contaminated: network_egress" ]
  r="$(row mf-a0_bare_matched-review-01-t1)"
  [ "$(jq -r '"\(.sessions_valid) \(.degraded) \(.recall_session1) \(.cost_usd)"' <<<"$r")" = "1 true null 2.5" ]
}

@test "RAB-c132-6 --batch-context (bd-st02i): every trial gets the batch name as an argv flag (the variable is never set); a given id is passed and kept on --resume; another id on --resume is refused" {
  export STUB_ENV_LOG="$T/env.log"
  ra --arms a1_full --tasks review-01 --trials-review 1 --batch bx1
  [ "$status" -eq 0 ]
  grep -qx 'bx1-a1_full-review-01-t1 LOA_ABLATION_BATCH_CONTEXT=<unset> batch_context=bx1' "$T/env.log"
  grep -qx 'batch_context=bx1' "$RES/bx1/a1_full/review-01-t1/meta/arm-evidence.txt"
  [ "$(row bx1-a1_full-review-01-t1 | jq -r '.batch_context')" = bx1 ]
  rules '*-review-02-* transport'
  ra --arms a1_full --tasks review-01,review-02 --trials-review 1 --batch bx2 --batch-context c132-g1 --concurrency 1
  [ "$(jq -r '.batch_context' "$RES/bx2/MANIFEST.json")" = c132-g1 ]
  [ "$(grep -c 'batch_context=c132-g1$' "$T/env.log")" -ge 3 ]
  ra --batch bx2 --resume --batch-context other
  [ "$status" -eq 2 ]; grep -q -- '--batch-context other differs from the batch'"'"'s c132-g1' <<<"$output"
  unset STUB_RULES; : > "$T/env.log"
  ra --batch bx2 --resume --rerun-status transport_error
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q 'batch_context=c132-g1$' "$T/env.log"
}

@test "RAB-c132-7 mount_cheval (bd-56nn6): a mounted run whose probe reads broken fails took-effect mount_cheval_ok — the row is infrastructure_error and the arm pauses" {
  rules '*-a1_full-review-01-* cheval_broken'
  ra --arms a1_full --tasks review-01,review-02 --trials-review 1 --batch mc --concurrency 1 --seed 3
  [ "$status" -eq 1 ]
  [ "$(row mc-a1_full-review-01-t1 | jq -r '.status, .mount_cheval' | tr '\n' ' ')" = "infrastructure_error broken:ImportError: cannot import name 'x' " ]
  jq -e '.paused_arms.a1_full | test("mount_cheval_ok")' "$RES/mc/STATUS.json" >/dev/null
  # round 1: the row records the FAIL rule false (the analysis filter reads it)
  [ "$(row mc-a1_full-review-01-t1 | jq -r '.took_effect.mount_cheval_ok, .took_effect.integrity_clean' | tr '\n' ' ')" = "false true " ]
}

# a registration matching the batch's inputs (the shape registration.py writes; jq here, the module has its own tests)
make_reg() {
  jq -n --arg s "$(sha_of "$REPO_ROOT/grimoires/loa/evals/ablation-2.0/MANIFEST.sha256")" \
        --arg c "$(sha_of "$REPO_ROOT/evals/fixtures/review-prs/SHA256SUMS")" --arg p "$SHA" \
    '{schema_version: 1, cycle: "cycle-132", preregistration_path: "x/PREREGISTRATION.md", preregistration_sha256: ("e" * 64),
      corpus_sha256sums_sha256: $c, suite_root: "x", suite_manifest_sha256: $s, analysis_tree_sha256: ("f" * 40), pin: $p,
      label_set: "v2", seed: 1, arms: [], groups: [], looks: [], boundary_constant: 1, cap_usd: 2500,
      kickoff: "2026-10-21T00:23:00Z", addenda: []}' > "$T/REGISTRATION.json"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "{\"total_usd\": ${STUB_SPEND_TOTAL:-100}, \"complete\": ${STUB_SPEND_COMPLETE:-true}}"; [[ "${STUB_SPEND_COMPLETE:-true}" == true ]]' > "$T/bin/spend"
  chmod +x "$T/bin/spend"
}

@test "RAB-c132-8 --registration: the dry run records the sha256, path and bound hashes; the spend gate derives --max-usd from the registered cap minus the cycle meter; a mismatched binding, a failed meter and an exhausted cap are refused" {
  make_reg
  ra --arms a1_full --tasks review-01 --trials-review 1 --batch rg1 --registration "$T/REGISTRATION.json" --spend-bin "$T/bin/spend" --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  M="$RES/rg1/MANIFEST.json"
  [ "$(jq -r .registration_sha256 "$M")" = "$(sha_of "$T/REGISTRATION.json")" ]
  [ "$(jq -r .registration_path "$M")" = "$T/REGISTRATION.json" ]
  [ "$(jq -r .preregistration_sha256 "$M")" = "$(printf 'e%.0s' $(seq 1 64))" ]
  [ "$(jq -r '.registration | "\(.pin) \(.cap_usd) \(.kickoff)"' "$M")" = "$SHA 2500 2026-10-21T00:23:00Z" ]
  [ "$(jq -c '.spend_gate' "$M")" = '{"cap_usd":2500,"since":"2026-10-21T00:23:00Z","cycle_spent_usd":100,"derived_max_usd":2400,"max_usd_given":null,"max_usd":2400}' ] || { jq -c .spend_gate "$M"; false; }
  [ "$(jq -r '.caps.max_usd' "$M")" = 2400 ]
  grep -q 'spend gate: registered cap USD 2500 − cycle spend USD 100 since 2026-10-21T00:23:00Z = USD 2400; batch --max-usd 2400' <<<"$output"
  # a smaller --max-usd wins; --spend-since overrides the kickoff
  ra --arms a1_full --tasks review-01 --trials-review 1 --batch rg2 --registration "$T/REGISTRATION.json" --spend-bin "$T/bin/spend" --max-usd 50 --spend-since 2026-10-22T00:00:00Z --dry-run
  [ "$(jq -c '.spend_gate | [.since, .max_usd_given, .max_usd]' "$RES/rg2/MANIFEST.json")" = '["2026-10-22T00:00:00Z",50,50]' ]
  # refusals
  STUB_SPEND_COMPLETE=false ra --arms a1_full --tasks review-01 --trials-review 1 --batch rg3 --registration "$T/REGISTRATION.json" --spend-bin "$T/bin/spend" --dry-run
  [ "$status" -eq 2 ]; grep -q 'did not give a complete total' "$RES/rg3/REFUSED.txt"
  STUB_SPEND_TOTAL=2600 ra --arms a1_full --tasks review-01 --trials-review 1 --batch rg4 --registration "$T/REGISTRATION.json" --spend-bin "$T/bin/spend" --dry-run
  [ "$status" -eq 2 ]; grep -q 'leaves USD -100: no batch budget' "$RES/rg4/REFUSED.txt"
  jq '.suite_manifest_sha256 = ("0" * 64)' "$T/REGISTRATION.json" > "$T/bad.json"
  ra --arms a1_full --tasks review-01 --trials-review 1 --batch rg5 --registration "$T/bad.json" --spend-bin "$T/bin/spend" --dry-run
  [ "$status" -eq 2 ]; grep -q 'registration binds suite_manifest_sha256 0000' "$RES/rg5/REFUSED.txt"
  jq '.pin = "abcdef1"' "$T/REGISTRATION.json" > "$T/bad.json"
  ra --arms a1_full --tasks review-01 --trials-review 1 --batch rg6 --registration "$T/bad.json" --spend-bin "$T/bin/spend" --dry-run
  [ "$status" -eq 2 ]; grep -q 'registration binds pin abcdef1' "$RES/rg6/REFUSED.txt"
  ra --arms a1_full --tasks review-01 --trials-review 1 --batch rg7 --spend-since 2026-10-21T00:23:00Z --dry-run
  [ "$status" -eq 2 ]; grep -q -- '--spend-since goes with --registration' <<<"$output"
}

@test "RAB-c132-9 --resume is bound to the registration: an edited file is refused (registration changed: old ≠ new), so is a removed one, another --registration, or one given to a batch that started without" {
  make_reg
  rules '*-review-02-* transport'
  ra --arms a1_full --tasks review-01,review-02 --trials-review 1 --batch rr1 --concurrency 1 --registration "$T/REGISTRATION.json" --spend-bin "$T/bin/spend"
  [ "$status" -eq 1 ]
  old="$(sha_of "$T/REGISTRATION.json")"
  unset STUB_RULES
  jq '.seed = 2' "$T/REGISTRATION.json" > "$T/r2" && mv "$T/r2" "$T/REGISTRATION.json"
  ra --batch rr1 --resume --rerun-status transport_error
  [ "$status" -eq 2 ]
  grep -q "registration changed: $old ≠ $(sha_of "$T/REGISTRATION.json")" <<<"$output"
  cp "$T/REGISTRATION.json" "$T/other.json"
  ra --batch rr1 --resume --registration "$T/other.json"
  [ "$status" -eq 2 ]; grep -q 'differs from the batch' <<<"$output"
  rm "$T/REGISTRATION.json"
  ra --batch rr1 --resume
  [ "$status" -eq 2 ]; grep -q 'registration changed: .* (.* is gone)' <<<"$output"
  ra --arms a1_full --tasks review-01 --trials-review 1 --batch rr2
  [ "$status" -eq 0 ]
  make_reg
  ra --batch rr2 --resume --registration "$T/REGISTRATION.json"
  [ "$status" -eq 2 ]; grep -q 'started without a registration' <<<"$output"
  # the rows carry the registration they ran under
  [ "$(row rr1-a1_full-review-01-t1 | jq -r '.registration_sha256')" = "$old" ]
}

@test "RAB-c132-10 the reservation rule over session units (SKP-003b): k = 3 sessions at concurrency 3 reserve 20 each — max 47.99 holds the third session until one ends, 48 launches it at once; the session spend lands in spent" {
  msuite
  export STUB_COST=1
  # third gate: spent 0 + 2 running x 20 + the review-catch hint 8 = 48
  ram --arms a0_bare_matched --tasks review-01 --trials-review 1 --batch mv1 --concurrency 3 --max-usd 47.99
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  L="$RES/mv1/run.log"
  [ "$(logline 'done mv1-a0_bare_matched-review-01-t1-s1 ' "$L")" -lt "$(logline 'launch mv1-a0_bare_matched-review-01-t1-s3 ' "$L")" ]
  ram --arms a0_bare_matched --tasks review-01 --trials-review 1 --batch mv2 --concurrency 3 --max-usd 48
  [ "$status" -eq 0 ]
  L="$RES/mv2/run.log"
  [ "$(logline 'launch mv2-a0_bare_matched-review-01-t1-s3 ' "$L")" -lt "$(logline 'done mv2-a0_bare_matched-review-01-t1-s1 ' "$L")" ]
  [ "$(jq -r '.spend.spent_usd, .spend.sessions_usd' "$RES/mv2/STATUS.json" | tr '\n' ' ')" = "3 3 " ]
  # a cut: max 5 lets s1 launch (0 + 0 + 8 > 5 cuts at once? no: the first gate cuts when spent + est > max)
  ram --arms a0_bare_matched --tasks review-01 --trials-review 1 --batch mv3 --concurrency 3 --max-usd 7
  [ "$status" -eq 1 ]
  [ "$(jq -r '.cuts | length' "$RES/mv3/STATUS.json")" = 1 ]
  [ ! -e "$(CELL_OF mv3)/meta/cell.json" ]
}

@test "RAB-c132-11 the attempt limit on reruns (D-7.3): a replacement row counts the old row's attempts; a row at 3 attempts is refused by --rerun and skipped by --rerun-status; a matched cell is never rerun or rerowed" {
  export LOA_ABLATION_OUTAGE_BREAKER=0
  rules '*-review-01-* transport'
  ra --arms a1_full --tasks review-01 --trials-review 1 --batch at1
  x=at1-a1_full-review-01-t1
  [ "$(row "$x" | jq -r '.attempts')" = 2 ]
  ra --batch at1 --resume --rerun-status transport_error
  [ "$(row "$x" | jq -r '"\(.status) \(.attempts)"')" = "transport_error 3" ]   # one more attempt, no in-line retry past 3
  [ "$(grep -c "^$x " "$T/stub.log")" -eq 3 ]
  ra --batch at1 --resume --rerun "$x"
  [ "$status" -eq 2 ]; grep -q 'the row is at 3 attempts; the attempt limit is 3' <<<"$output"
  ra --batch at1 --resume --rerun-status transport_error
  grep -q "resume: --rerun-status transport_error skips $x (at 3 attempts, the limit of 3)" "$RES/at1/run.log"
  [ "$(grep -c "^$x " "$T/stub.log")" -eq 3 ]
  msuite
  unset STUB_RULES
  ram --arms a0_bare_matched --tasks review-01 --trials-review 1 --batch at2
  jq -c 'if .run_id == "at2-a0_bare_matched-review-01-t1" then .status = "infrastructure_error" else . end' "$RES/runs.jsonl" > "$T/r" && mv "$T/r" "$RES/runs.jsonl"
  ram --batch at2 --resume --rerun at2-a0_bare_matched-review-01-t1
  [ "$status" -eq 2 ]; grep -q 'a matched cell is never rerun as a whole' <<<"$output"
  ram --batch at2 --resume --rerow at2-a0_bare_matched-review-01-t1
  [ "$status" -eq 2 ]; grep -q 'never rowed again' <<<"$output"
}

@test "RAB-c132-12 (addendum 2) an a1_full run whose gates skipped the dissent on budget fails took-effect dissent_present: the row is infrastructure_error with took_effect.dissent_present false and the arm pauses" {
  rules '*-a1_full-review-01-* dissent_budget'
  ra --arms a1_full --tasks review-01,review-02 --trials-review 1 --batch db --concurrency 1 --seed 3
  [ "$status" -eq 1 ]
  [ "$(row db-a1_full-review-01-t1 | jq -r '.status, .took_effect.dissent_present, .took_effect.mount_cheval_ok' | tr '\n' ' ')" = "infrastructure_error false true " ]
  jq -e '.paused_arms.a1_full | test("dissent_present")' "$RES/db/STATUS.json" >/dev/null
}
