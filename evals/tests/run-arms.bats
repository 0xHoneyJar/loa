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
  [ "$(jq -r '.model_id' "$M")" = "global.anthropic.claude-opus-5-5" ]   # the DEC-0172 default
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

# --- cycle-130 Sprint 258 Task 1.4: --max-usd and --screen (PRD AC-2.1, AC-2.4) ---
# The executor stub reports USD 5 per trial (STUB_COST_USD) through the result
# event, so every row's executor.total_cost_usd is 5.

@test "RA-6 --max-usd 12 at USD 5 per trial: two launch (0+5, 5+5 <= 12), the third is cut (10+5=15 > 12); STATUS carries cut and cut_reason; exit 1" {
  export EVAL_CLAUDE_BIN="$TESTS_DIR/fixtures/ablation/claude-ablation-stub.sh" STUB_COST_USD=5
  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 3 --concurrency 1 \
    --source-commit "$SHA" --results-dir "$RES" --retry-wait 0 --max-usd 12
  [ "$status" -eq 1 ]
  B="$RES/review-recall/batch-pr-01-pr-01-n1"
  [ "$(grep -c . "$B/baseline/results.jsonl")" -eq 2 ]
  [ "$(jq -s -r 'map(.executor.total_cost_usd) | add' "$B/baseline/results.jsonl")" = "10" ]
  S="$B/STATUS.json"
  [ "$(jq -r '.state' "$S")" = "partial" ]
  [ "$(jq -r '.cut_reason' "$S")" = "max_usd" ]
  [ "$(jq -r '.cut.reason' "$S")" = "max_usd" ]
  [ "$(jq -r '.cut.spent' "$S")" = "10" ]
  [ "$(jq -r '.cut.in_flight_reserved' "$S")" = "0" ]
  [ "$(jq -r '.cut.max' "$S")" = "12" ]
  [ "$(jq -r '.cut.trials_launched' "$S")" = "2" ]
  [ "$(jq -r '.cut.at_trial' "$S")" = "3" ]
  [ "$(jq -r '.cut.est_next' "$S")" = "5" ]
  [ "$(jq -r '.spend.spent_usd' "$S")" = "10" ]
  [ "$(jq -r '.per_arm.baseline.trials_done' "$S")" = "2" ]
  [ "$(jq -r '.per_arm.baseline.trials_planned' "$S")" = "3" ]
  [ "$(jq -r '.spend.max_usd' "$B/MANIFEST.json")" = "12" ]
  [ "$(jq -r '.spend.run_cap_usd' "$B/MANIFEST.json")" = "12" ]
  grep -q 'cut: max_usd 12 reached after 2 trials' "$B/run.log"
  # the suite aggregate lists the cut
  [ "$(jq -r '.cuts[0].reason + " " + .cuts[0].batch' "$RES/review-recall/STATUS.json")" = "max_usd batch-pr-01-pr-01-n1" ]
}

@test "RA-7 without --max-usd the same USD 5 trials all run: exit 0, no cut, no spend block (behaviour unchanged)" {
  export EVAL_CLAUDE_BIN="$TESTS_DIR/fixtures/ablation/claude-ablation-stub.sh" STUB_COST_USD=5
  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 3 --concurrency 1 \
    --source-commit "$SHA" --results-dir "$RES" --retry-wait 0
  [ "$status" -eq 0 ]
  S="$RES/review-recall/batch-pr-01-pr-01-n1/STATUS.json"
  [ "$(jq -r '.state' "$S")" = "complete" ]
  [ "$(jq -r '.per_arm.baseline.trials_done' "$S")" = "3" ]
  [ "$(jq -r 'has("cut") or has("cut_reason") or has("spend")' "$S")" = "false" ]
  [ "$(jq -r '.spend.max_usd' "$RES/review-recall/batch-pr-01-pr-01-n1/MANIFEST.json")" = "null" ]
  [ "$(jq -c '.cuts' "$RES/review-recall/STATUS.json")" = "[]" ]
}

@test "RA-8 --screen runs one trial of the first 2 fixtures per arm into screen-<ts>/, prints the per-arm table and writes no suite STATUS.json" {
  export EVAL_CLAUDE_BIN="$TESTS_DIR/fixtures/ablation/claude-ablation-stub.sh" STUB_COST_USD=5
  run "$RA" --suite review-recall --arms baseline,no_rule_files --fixtures pr-01,pr-02,pr-03 --trials 3 --screen \
    --source-commit "$SHA" --results-dir "$RES" --retry-wait 0 --concurrency 2
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  [ ! -e "$RES/review-recall/STATUS.json" ]
  SB="$(ls -d "$RES"/review-recall/screen-*)"
  [ -d "$SB" ]
  [ -f "$SB/MANIFEST.json" ] && [ -f "$SB/STATUS.json" ]
  [ "$(jq -r '.screen' "$SB/STATUS.json")" = "true" ]
  [ "$(jq -r '.trials_planned' "$SB/MANIFEST.json")" = "4" ]
  [ "$(jq -c '.fixtures' "$SB/MANIFEST.json")" = '["pr-01","pr-02"]' ]
  [ "$(cat "$SB"/*/results.jsonl | jq -r '.fixture' | sort -u | tr '\n' ,)" = "pr-01,pr-02," ]
  grep -qE '^arm +trials +mean_usd +mean_recall$' <<<"$output"
  grep -qE '^baseline +2 +5 ' <<<"$output"
  grep -qE '^no_rule_files +2 +5 ' <<<"$output"
  # a later regular batch: the suite aggregate never reads the screen batch
  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 1 \
    --source-commit "$SHA" --results-dir "$RES" --retry-wait 0
  [ "$status" -eq 0 ]
  [ "$(jq -r '.per_arm.baseline.trials_planned' "$RES/review-recall/STATUS.json")" = "1" ]
  [ "$(jq -r '[.batches[].batch] | join(",")' "$RES/review-recall/STATUS.json")" = "batch-pr-01-pr-01-n1" ]
}

@test "RA-9 in-flight reservation: concurrency 2, max 15, USD 5 each: 0+1x12+5=17>15 holds trial 2 until trial 1 ends (5+0+5=10), trial 3 likewise (10+5=15), trial 4 cut (15+5=20>15); never two at once" {
  export EVAL_CLAUDE_BIN="$TESTS_DIR/fixtures/ablation/claude-ablation-stub.sh" STUB_COST_USD=5
  export STUB_CONC_DIR="$T/conc" STUB_SLEEP=2
  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 4 --concurrency 2 \
    --source-commit "$SHA" --results-dir "$RES" --retry-wait 0 --max-usd 15
  [ "$status" -eq 1 ]
  S="$RES/review-recall/batch-pr-01-pr-01-n1/STATUS.json"
  [ "$(jq -r '.cut.trials_launched' "$S")" = "3" ]
  [ "$(jq -r '.cut.at_trial' "$S")" = "4" ]
  [ "$(jq -r '.cut.spent' "$S")" = "15" ]
  [ "$(grep -c . "$T/conc.log")" -eq 3 ]
  [ "$(sort -n "$T/conc.log" | tail -1)" = "1" ]
  # the probe does see overlap when no cap reserves the slot
  export STUB_CONC_DIR="$T/conc2"
  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 2 --concurrency 2 --batch overlap \
    --source-commit "$SHA" --results-dir "$RES" --retry-wait 0
  [ "$status" -eq 0 ]
  [ "$(sort -n "$T/conc2.log" | tail -1)" = "2" ]
}

@test "RA-10 --max-usd and --screen-tasks refuse malformed values (exit 2)" {
  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 1 --source-commit "$SHA" --results-dir "$RES" --max-usd abc
  [ "$status" -eq 2 ]
  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 1 --source-commit "$SHA" --results-dir "$RES" --max-usd 0
  [ "$status" -eq 2 ]
  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 1 --source-commit "$SHA" --results-dir "$RES" --screen --screen-tasks 0
  [ "$status" -eq 2 ]
  [ ! -e "$RES/review-recall" ]
}

@test "RA-11 the suite aggregate excludes screen batches by the STATUS marker, not the directory name" {
  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 1 \
    --source-commit "$SHA" --results-dir "$RES" --retry-wait 0
  [ "$status" -eq 0 ]
  local suite="$RES/review-recall" one="$RES/review-recall/batch-pr-01-pr-01-n1/STATUS.json"
  # a regular batch whose directory happens to start with screen-
  mkdir -p "$suite/screen-foo" "$suite/batch-x"
  jq '.batch = "screen-foo" | .screen = false' "$one" > "$suite/screen-foo/STATUS.json"
  # a screen batch (marker true, with a cut) in a directory that does not say so
  jq '.batch = "batch-x" | .screen = true | .cut = {reason: "max_usd"}' "$one" > "$suite/batch-x/STATUS.json"
  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 1 --batch second \
    --source-commit "$SHA" --results-dir "$RES" --retry-wait 0
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.batches[].batch] | join(",")' "$suite/STATUS.json")" = "batch-pr-01-pr-01-n1,screen-foo,second" ]
  [ "$(jq -r '.per_arm.baseline.trials_planned' "$suite/STATUS.json")" = "3" ]
  [ "$(jq -c '.cuts' "$suite/STATUS.json")" = "[]" ]
}

@test "RA-12 --batch screen-<name> without --screen is refused (exit 2) and writes nothing" {
  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 1 --batch screen-foo \
    --source-commit "$SHA" --results-dir "$RES" --retry-wait 0
  [ "$status" -eq 2 ]
  [[ "$output" == *"screen- prefix is reserved"* ]]
  [ ! -e "$RES/review-recall/screen-foo" ]
}
