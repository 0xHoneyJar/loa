#!/usr/bin/env bats
# =============================================================================
# evals/tests/arms-report.bats — cycle-129 Sprint 1 Task 1.4 (FR-2, SDD D-2.3)
#
# report.sh --arms over a fixture results tree (the layout run-arms.sh
# writes): the pre-registered verdicts, the bootstrap interval, refuted share,
# missed labels, the refusal while STATUS.json is not complete and the
# --partial header. Thresholds come from the real review-recall suite.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  REPORT="$REPO_ROOT/evals/harness/report.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/ar.XXXXXX")"
  R="$T/arms"; S="$R/review-recall"; B="$S/b1"
  mkdir -p "$B"
  jq -n '{schema_version:1, suite:"review-recall", batch:"b1", dry_run:false, source_commit:"864069f2f31c57dd00cd4e29e862d6c16d17c457",
          model_id:"claude-fable-5-1", arms:["baseline","no_companion","no_karpathy","no_rule_files"], fixtures:["pr-01","pr-02","pr-03"], trials:3}' \
    > "$B/MANIFEST.json"
  status_file complete
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

status_file() {  # status_file <state>
  jq -n --arg s "$1" '{schema_version:1, suite:"review-recall", state:$s, batches:[{batch:"b1", state:$s}],
                       source_commit:"864069f2f31c57dd00cd4e29e862d6c16d17c457", model_id:"claude-fable-5-1"}' > "$S/STATUS.json"
}

# row <arm> <fixture> <trial> <recall> <missed-csv> [<cited> <refuted> <model> <source>]
row() {
  local arm="$1" fx="$2" t="$3" rc="$4" missed="$5" cited="${6:-4}" ref="${7:-1}"
  local model="${8:-claude-fable-5-1}" src="${9:-864069f2f31c57dd00cd4e29e862d6c16d17c457}"
  mkdir -p "$B/$arm"
  jq -cn --arg arm "$arm" --arg fx "$fx" --argjson t "$t" --argjson rc "$rc" --arg missed "$missed" \
    --argjson cited "$cited" --argjson ref "$ref" --arg model "$model" --arg src "$src" \
    '{status:"completed", arm:$arm, fixture:$fx, task_id:("review-" + $fx), trial:$t, model_id:$model, source_commit:$src,
      executor:{model_id:$model, usage:{input_tokens:100, cache_read_input_tokens:900, output_tokens:0, cache_creation_input_tokens:0}},
      graders:[{name:"recall-vs-defects.sh", details:{recall:$rc, planted:3,
        detected:[], missed:($missed | split(",") | map(select(length > 0))),
        findings_cited:$cited, findings_refuted:$ref}}]}' >> "$B/$arm/results.jsonl"
}

full_arm() {  # full_arm <arm> <recall> [<missed>] [<refuted>]
  local fx t
  for fx in pr-01 pr-02 pr-03; do for t in 1 2 3; do row "$1" "$fx" "$t" "$2" "${3:-}" 4 "${4:-1}"; done; done
}

@test "AR-1 complete run: equal recall reads no recall loss, a large drop reads recall loss, the informational arm says so" {
  full_arm baseline 1
  full_arm no_rule_files 1
  full_arm no_karpathy 0.3333 "L2,L3" 1
  full_arm no_companion 1
  run "$REPORT" --arms --suite review-recall --results-dir "$R" --out "$T/r.md" --date 2026-10-14
  [ "$status" -eq 0 ]
  grep -E '^\| `no_rule_files` ' "$T/r.md" | grep -q '\*\*no recall loss\*\*'
  grep -E '^\| `no_karpathy` ' "$T/r.md" | grep -q '\*\*recall loss\*\*'
  grep -E '^\| `no_companion` ' "$T/r.md" | grep -q 'informational: yield only'
  grep -E '^\| `baseline` ' "$T/r.md" | grep -q '(reference)'
  # the interval of the drop and the missed labels are printed
  grep -E '^\| `no_karpathy` ' "$T/r.md" | grep -q '\[0.667, 0.667\]'
  grep -q 'no_karpathy`: pr-01:L2 (3/3)' "$T/r.md"
  grep -q '^# Control-arm report — 2026-10-14' "$T/r.md"
  ! grep -q 'PARTIAL REPORT' "$T/r.md"
}

@test "AR-2 a refuted-share rise beyond the threshold is a recall loss even with equal recall" {
  full_arm baseline 1 "" 0
  full_arm no_rule_files 1 "" 3
  run "$REPORT" --arms --suite review-recall --results-dir "$R" --out "$T/r.md"
  [ "$status" -eq 0 ]
  grep -E '^\| `no_rule_files` ' "$T/r.md" | grep -q '\*\*recall loss\*\*'
  grep -q 'refuted share 0.750 > baseline 0.000' "$T/r.md"
}

@test "AR-3 a missing trial or fixture is inconclusive; model or source skew is inconclusive" {
  full_arm baseline 1
  for fx in pr-01 pr-02; do for t in 1 2 3; do row no_rule_files "$fx" "$t" 1 ""; done; done
  row no_rule_files pr-03 1 1 ""
  for fx in pr-01 pr-02 pr-03; do for t in 1 2 3; do row no_karpathy "$fx" "$t" 1 "" 4 1 claude-opus-5-5; done; done
  for fx in pr-01 pr-02 pr-03; do for t in 1 2 3; do row no_companion "$fx" "$t" 1 "" 4 1 claude-fable-5-1 ffd25258; done; done
  run "$REPORT" --arms --suite review-recall --results-dir "$R" --out "$T/r.md"
  [ "$status" -eq 0 ]
  grep -E '^\| `no_rule_files` ' "$T/r.md" | grep -q '\*\*inconclusive\*\*'
  grep -q 'coverage: pr-03 1/3' "$T/r.md"
  grep -E '^\| `no_karpathy` ' "$T/r.md" | grep -q '\*\*inconclusive\*\*'
  grep -q 'model skew' "$T/r.md"
  grep -q 'source skew' "$T/r.md"
}

@test "AR-4 a rule violation within the baseline's own trial-to-trial spread names no change (inconclusive)" {
  # baseline trial means 1.0, 0.6, 1.0 (spread 0.4); the arm sits 0.2 lower on every fixture
  local fx
  for fx in pr-01 pr-02 pr-03; do row baseline "$fx" 1 1 ""; row baseline "$fx" 2 0.6 ""; row baseline "$fx" 3 1 ""; done
  for fx in pr-01 pr-02 pr-03; do row no_rule_files "$fx" 1 0.8 ""; row no_rule_files "$fx" 2 0.4 ""; row no_rule_files "$fx" 3 0.8 ""; done
  run "$REPORT" --arms --suite review-recall --results-dir "$R" --out "$T/r.md"
  [ "$status" -eq 0 ]
  grep -E '^\| `no_rule_files` ' "$T/r.md" | grep -q '\*\*inconclusive\*\*'
  grep -q 'no change can be named' "$T/r.md"
}

@test "AR-5 STATUS.json not complete: refused (exit 1); --partial writes, says so, and every verdict is inconclusive" {
  full_arm baseline 1
  full_arm no_rule_files 1
  status_file running
  run "$REPORT" --arms --suite review-recall --results-dir "$R" --out "$T/r.md"
  [ "$status" -eq 1 ]
  grep -q "not 'complete'" <<<"$output"
  [ ! -e "$T/r.md" ]
  run "$REPORT" --arms --suite review-recall --results-dir "$R" --out "$T/r.md" --partial
  [ "$status" -eq 0 ]
  grep -q 'PARTIAL REPORT' "$T/r.md"
  grep -E '^\| `no_rule_files` ' "$T/r.md" | grep -q '\*\*inconclusive\*\*'
  ! grep -q '\*\*no recall loss\*\*' "$T/r.md"
}

@test "AR-7 a safeguard-refusal fallback to another model is skew: the arm is inconclusive and the fallback is named" {
  full_arm baseline 1
  full_arm no_rule_files 1
  # one no_rule_files trial moved to Opus on a refusal (models_used + refusal_fallbacks, as execute-agent records them)
  jq -c 'if .trial == 1 and .fixture == "pr-01" then .executor.models_used = {"claude-fable-5-1": 10, "global.anthropic.claude-opus-5-5": 90}
         | .executor.refusal_fallbacks = [{"from":"claude-fable-5-1","to":"global.anthropic.claude-opus-5-5","category":"cyber"}] else . end' \
    "$B/no_rule_files/results.jsonl" > "$B/x" && mv "$B/x" "$B/no_rule_files/results.jsonl"
  run "$REPORT" --arms --suite review-recall --results-dir "$R" --out "$T/r.md"
  [ "$status" -eq 0 ]
  grep -E '^\| `no_rule_files` ' "$T/r.md" | grep -q '\*\*inconclusive\*\*'
  grep -q 'model skew' "$T/r.md"
  grep -q '1/9 trial(s) fell back to another model on a safeguard refusal' "$T/r.md"
}

@test "AR-6 the default output path is evals/results/arms-report-<date>.md under the results root's repo; bad args exit 2" {
  run "$REPORT" --arms --suite nope --results-dir "$R"
  [ "$status" -eq 2 ]
  run "$REPORT" --arms --suite review-recall --results-dir "$T/missing" --out "$T/r.md"
  [ "$status" -eq 2 ]
  run "$REPORT" --arms --date 14-10-2026 --results-dir "$R" --out "$T/r.md"
  [ "$status" -eq 2 ]
}
