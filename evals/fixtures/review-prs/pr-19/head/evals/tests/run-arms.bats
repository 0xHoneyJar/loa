#!/usr/bin/env bats
# =============================================================================
# evals/tests/run-arms.bats — cycle-129 Sprint 1 Task 1.6 (FR-2, SDD D-2.3)
#
# run-arms.sh drives control arms over a frozen fixture batch against a
# detached worktree pinned at --source-commit. The executor is the CLI stub
# (no model call); the source repo is a throwaway repo (LOA_ARMS_SOURCE_REPO)
# so no worktree is ever registered in the real repository; the results and
# the worktree live under the test's temp dir.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  RA="$REPO_ROOT/evals/harness/run-arms.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/ra.XXXXXX")"
  SRC="$T/src"
  mkdir -p "$SRC/.claude/loa" "$SRC/.claude/rules" "$SRC/.claude/skills/reviewing-code"
  printf '%s\n' "# Loa" "" "## Karpathy Principles" "" "k" "" "## Other" > "$SRC/.claude/loa/CLAUDE.loa.md"
  echo "# s" > "$SRC/.claude/rules/stash-safety.md"
  echo "# i" > "$SRC/.claude/rules/skill-invariants.md"
  printf '%s\n' "---" "name: reviewing-code" "---" "# Review" > "$SRC/.claude/skills/reviewing-code/SKILL.md"
  printf '%s\n' "flatline_protocol:" "  code_review:" "    enabled: true" > "$SRC/.loa.config.yaml"
  ( cd "$SRC" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m src )
  SHA="$(git -C "$SRC" rev-parse HEAD)"
  export LOA_ARMS_SOURCE_REPO="$SRC" LOA_ARMS_CACHE="$T/cache"
  export EVAL_CLAUDE_BIN="$TESTS_DIR/fixtures/claude-stub.sh"
  # the stub writes a review that cites all three pr-01 defect anchors
  export STUB_WRITE_1='review.md::# Review\nhead/.claude/hooks/safety/block-destructive-bash.sh:210 and head/.claude/scripts/lib/invoke-diagnostics.sh:50 and head/.claude/scripts/workflow-state.sh:72 and head/.claude/scripts/workflow-state.sh:400\n'
  RES="$T/results"
  unset STUB_FAIL_COUNTER LOA_EVAL_ARM LOA_EVAL_ARM_TOGGLES
}

teardown() {
  git -C "$SRC" worktree prune 2>/dev/null || true
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

@test "RA-1 --dry-run lists the interleaved plan and writes MANIFEST.json without a worktree or a CLI call" {
  export STUB_ARGV_FILE="$T/argv"
  run "$RA" --suite review-recall --arms baseline,no_rule_files --fixtures pr-01,pr-02 --trials 2 \
    --source-commit "$SHA" --results-dir "$RES" --dry-run
  [ "$status" -eq 0 ]
  grep -q 'planned trials: 8' <<<"$output"
  # trial-major, then fixture, then arm: arms alternate on consecutive lines
  [ "$(grep -E '^ +[0-9]+ ' <<<"$output" | awk '{print $2}' | head -4 | tr '\n' ,)" = "baseline,no_rule_files,baseline,no_rule_files," ]
  [ "$(grep -E '^ +[0-9]+ ' <<<"$output" | awk '{print $3}' | head -4 | tr '\n' ,)" = "pr-01,pr-01,pr-02,pr-02," ]
  M="$RES/review-recall/batch-pr-01-pr-02-n2/MANIFEST.json"
  [ -f "$M" ]
  [ "$(jq -r '.source_commit' "$M")" = "$SHA" ]
  [ "$(jq -r '.model_id' "$M")" = "claude-fable-5-1" ]
  [ "$(jq -r '.dry_run' "$M")" = "true" ]
  [ "$(jq -r '.trials_planned' "$M")" = "8" ]
  [ "$(jq -r '.corpus.sha256 | length' "$M")" = "64" ]
  jq -e '.harness_commit and .executor.cli_version and .environment.os and .environment.yq' "$M" >/dev/null
  [ ! -e "$T/cache/arms-src-${SHA:0:12}" ]
  [ ! -e "$T/argv" ]
}

@test "RA-2 a stubbed batch completes: rows carry arm, trial, source_commit, model_id and seed; STATUS is complete; artifacts are kept" {
  run "$RA" --suite review-recall --arms baseline,no_rule_files --fixtures pr-01 --trials 1 \
    --source-commit "$SHA" --results-dir "$RES" --concurrency 2 --retry-wait 0
  [ "$status" -eq 0 ]
  B="$RES/review-recall/batch-pr-01-pr-01-n1"
  [ "$(jq -r '.state' "$B/STATUS.json")" = "complete" ]
  [ "$(jq -r '.per_arm.baseline.trials_done' "$B/STATUS.json")" = "1" ]
  [ "$(jq -r '.per_arm.no_rule_files.trials_planned' "$B/STATUS.json")" = "1" ]
  [ "$(jq -r '.state' "$RES/review-recall/STATUS.json")" = "complete" ]
  [ "$(jq -r '.source_commit' "$RES/review-recall/STATUS.json")" = "$SHA" ]
  for a in baseline no_rule_files; do
    row="$(cat "$B/$a/results.jsonl")"
    [ "$(jq -r '.arm' <<<"$row")" = "$a" ]
    [ "$(jq -r '.trial' <<<"$row")" = "1" ]
    [ "$(jq -r '.status' <<<"$row")" = "completed" ]
    [ "$(jq -r '.source_commit' <<<"$row")" = "$SHA" ]
    [ "$(jq -r '.executor.source_commit' <<<"$row")" = "$SHA" ]
    [ "$(jq -r '.model_id' <<<"$row")" = "claude-sonnet-5-20260401" ]
    [ "$(jq -r '.seed' <<<"$row")" = "null" ]
    [ "$(jq -r '.graders[] | select(.name=="recall-vs-defects.sh") | .details.recall == 1' <<<"$row")" = "true" ]
    [ "$(jq -r '.graders[] | select(.name=="recall-vs-defects.sh") | .details.findings_refuted' <<<"$row")" = "1" ]
    [ -f "$B/$a/artifacts/review-pr-01/trial-1/review.md" ]
  done
  [ "$(jq -r '.executor.arm_evidence.rule_files' "$B/no_rule_files/results.jsonl")" = "removed: stash-safety.md skill-invariants.md" ]
  # the pinned worktree is at the source commit and untouched
  WT="$T/cache/arms-src-${SHA:0:12}"
  [ "$(git -C "$WT" rev-parse HEAD)" = "$SHA" ]
  [ -z "$(git -C "$WT" status --porcelain)" ]
  [ -f "$WT/.claude/rules/stash-safety.md" ]
  # compare.sh --ab accepts the two arms (one source, one model, distinct arm ids)
  # (exit 1, not 2: the gates run; pr-01 alone has no clean task for the false-positive gate)
  run "$REPO_ROOT/evals/harness/compare.sh" --ab --arm-a "$B/baseline" --arm-b "$B/no_rule_files" --metric recall --json
  [ "$status" -ne 2 ]
  [ "$(echo "$output" | jq -r '.valid')" = "true" ]
  [ "$(echo "$output" | jq -r '.gates[] | select(.name=="recall") | .pass')" = "true" ]
}

@test "RA-3 a transport failure is retried once; a second failure leaves the arm partial (exit 1, results kept)" {
  echo 1 > "$T/fails"
  export STUB_FAIL_COUNTER="$T/fails"
  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 1 \
    --source-commit "$SHA" --results-dir "$RES" --concurrency 1 --retry-wait 0
  [ "$status" -eq 0 ]
  B="$RES/review-recall/batch-pr-01-pr-01-n1"
  [ "$(jq -r '.attempts' "$B/baseline/results.jsonl")" = "2" ]
  [ "$(jq -r '.status' "$B/baseline/results.jsonl")" = "completed" ]
  [ -d "$B/baseline/artifacts/review-pr-01/trial-1-attempt1" ]
  # two failures in a row: trial 1 fails twice, trial 2 completes → partial
  echo 2 > "$T/fails"
  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 2 --batch twice \
    --source-commit "$SHA" --results-dir "$RES" --concurrency 1 --retry-wait 0
  [ "$status" -eq 1 ]
  B2="$RES/review-recall/twice"
  [ "$(jq -r '.state' "$B2/STATUS.json")" = "partial" ]
  [ "$(jq -r '.per_arm.baseline.trials_failed' "$B2/STATUS.json")" = "1" ]
  [ "$(jq -r '.per_arm.baseline.trials_done' "$B2/STATUS.json")" = "1" ]
  [ "$(head -1 "$B2/baseline/results.jsonl" | jq -r '.error.type')" = "transport_error" ]
  # the suite aggregate sees both batches and the worst state
  [ "$(jq -r '.state' "$RES/review-recall/STATUS.json")" = "partial" ]
  [ "$(jq -r '.per_arm.baseline.trials_planned' "$RES/review-recall/STATUS.json")" = "3" ]
  # every trial failing is `failed` (exit 3)
  echo 9 > "$T/fails"
  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 1 --batch never \
    --source-commit "$SHA" --results-dir "$RES" --concurrency 1 --retry-wait 0
  [ "$status" -eq 3 ]
  [ "$(jq -r '.state' "$RES/review-recall/never/STATUS.json")" = "failed" ]
  [ "$(jq -r '.state' "$RES/review-recall/STATUS.json")" = "failed" ]
}

@test "RA-4 usage refusals exit 2 before anything runs" {
  run "$RA" --suite review-recall --arms baseline,no_audit_delta --fixtures pr-01 --trials 1 --source-commit "$SHA" --results-dir "$RES"
  [ "$status" -eq 2 ]; grep -q 'not declared' <<<"$output"
  run "$RA" --suite nope --arms baseline --fixtures pr-01 --trials 1 --source-commit "$SHA" --results-dir "$RES"
  [ "$status" -eq 2 ]
  run "$RA" --suite review-recall --arms baseline --fixtures pr-99 --trials 1 --source-commit "$SHA" --results-dir "$RES"
  [ "$status" -eq 2 ]
  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 1 --source-commit deadbeef --results-dir "$RES"
  [ "$status" -eq 2 ]; grep -q 'not in this repository' <<<"$output"
  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 0 --source-commit "$SHA" --results-dir "$RES"
  [ "$status" -eq 2 ]
  [ ! -e "$RES/review-recall" ]
}

@test "RA-5 a batch holding results for another model refuses to mix (exit 2)" {
  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 1 --source-commit "$SHA" --results-dir "$RES" --retry-wait 0
  [ "$status" -eq 0 ]
  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 1 --source-commit "$SHA" --results-dir "$RES" --model other-model
  [ "$status" -eq 2 ]
  grep -q 'use another --batch' <<<"$output"
}
