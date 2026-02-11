#!/usr/bin/env bash
# test-compare.sh — Tests for compare.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPARE="$HARNESS_DIR/compare.sh"
TEST_DIR="$(mktemp -d /tmp/loa-test-compare-XXXXXX)"

passed=0
failed=0
total=0

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  total=$((total + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $desc"
    passed=$((passed + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    failed=$((failed + 1))
  fi
}

echo "=== compare.sh Tests ==="

# --- Setup: Create results JSONL ---
cat > "$TEST_DIR/results.jsonl" <<'JSONL'
{"run_id":"test-run","task_id":"task-a","trial":1,"timestamp":"2026-01-01T00:00:00Z","duration_ms":100,"model_version":"none","status":"completed","graders":[],"composite":{"strategy":"all_must_pass","pass":true,"score":100},"error":null,"schema_version":1}
{"run_id":"test-run","task_id":"task-b","trial":1,"timestamp":"2026-01-01T00:00:00Z","duration_ms":100,"model_version":"none","status":"completed","graders":[],"composite":{"strategy":"all_must_pass","pass":false,"score":0},"error":null,"schema_version":1}
{"run_id":"test-run","task_id":"task-c","trial":1,"timestamp":"2026-01-01T00:00:00Z","duration_ms":100,"model_version":"none","status":"completed","graders":[],"composite":{"strategy":"all_must_pass","pass":true,"score":100},"error":null,"schema_version":1}
JSONL

# --- Test 1: No baseline → all "new" ---
output="$("$COMPARE" --results "$TEST_DIR/results.jsonl" --json 2>/dev/null)" || true
new_count="$(echo "$output" | jq '.summary.new')"
assert_eq "No baseline: all tasks are 'new'" "3" "$new_count"

# --- Setup: Create baseline ---
mkdir -p "$TEST_DIR/baselines"
cat > "$TEST_DIR/baselines/test.baseline.yaml" <<'YAML'
version: 1
suite: test
model_version: "none"
recorded_at: "2026-01-01"
tasks:
  task-a:
    pass_rate: 1.0
    trials: 1
    mean_score: 100
    status: active
  task-b:
    pass_rate: 1.0
    trials: 1
    mean_score: 100
    status: active
  task-d:
    pass_rate: 1.0
    trials: 1
    mean_score: 100
    status: active
YAML

# --- Test 2: Regression detected ---
output="$("$COMPARE" --results "$TEST_DIR/results.jsonl" --baseline "$TEST_DIR/baselines/test.baseline.yaml" --json 2>/dev/null)" || true
regressions="$(echo "$output" | jq '.summary.regressions')"
assert_eq "Regression detected for task-b" "1" "$regressions"

# --- Test 3: Pass detected ---
passes="$(echo "$output" | jq '.summary.passes')"
assert_eq "Pass detected for task-a" "1" "$passes"

# --- Test 4: New task detected ---
new_count="$(echo "$output" | jq '.summary.new')"
assert_eq "New task detected for task-c" "1" "$new_count"

# --- Test 5: Missing task detected ---
missing="$(echo "$output" | jq '.summary.missing')"
assert_eq "Missing task detected for task-d" "1" "$missing"

# --- Test 6: Exit code 1 on regressions ---
"$COMPARE" --results "$TEST_DIR/results.jsonl" --baseline "$TEST_DIR/baselines/test.baseline.yaml" --quiet 2>/dev/null && exit_code=0 || exit_code=$?
assert_eq "Exit code 1 on regression" "1" "$exit_code"

# --- Test 7: Exit code 0 when no regressions ---
# Create results where all pass
cat > "$TEST_DIR/pass-results.jsonl" <<'JSONL'
{"run_id":"test-run","task_id":"task-a","trial":1,"timestamp":"2026-01-01T00:00:00Z","duration_ms":100,"model_version":"none","status":"completed","graders":[],"composite":{"strategy":"all_must_pass","pass":true,"score":100},"error":null,"schema_version":1}
JSONL

# Baseline where task-a passes
cat > "$TEST_DIR/baselines/pass.baseline.yaml" <<'YAML'
version: 1
suite: test
model_version: "none"
recorded_at: "2026-01-01"
tasks:
  task-a:
    pass_rate: 1.0
    trials: 1
    mean_score: 100
    status: active
YAML

"$COMPARE" --results "$TEST_DIR/pass-results.jsonl" --baseline "$TEST_DIR/baselines/pass.baseline.yaml" --quiet 2>/dev/null && exit_code=0 || exit_code=$?
assert_eq "Exit code 0 when no regressions" "0" "$exit_code"

# --- Test 8: Update baseline requires --reason ---
"$COMPARE" --results "$TEST_DIR/results.jsonl" --suite test --update-baseline 2>/dev/null && exit_code=0 || exit_code=$?
assert_eq "Update baseline without --reason fails" "2" "$exit_code"

# --- Test 9: Early stopping function ---
echo ""
echo "--- can_early_stop ---"

# Extract and source only the can_early_stop function from compare.sh
eval "$(sed -n '/^can_early_stop()/,/^}/p' "$COMPARE")"

# 0 passes, 3 failures, 0 remaining, baseline 1.0, threshold 0.10 → should stop (trivially true, 0 total)
result="$(can_early_stop 0 3 0 1.0 0.10)"
assert_eq "Early stop: 0/3 done, 0 remaining" "true" "$result"

# 0 passes, 1 failure, 2 remaining, baseline 1.0, threshold 0.10 → best case 2/3=0.67, Wilson lower ~0.35 < 0.90
result="$(can_early_stop 0 1 2 1.0 0.10)"
assert_eq "Early stop: 0/1 done, 2 remaining, bl=1.0" "true" "$result"

# 3 passes, 0 failures, 2 remaining, baseline 1.0, threshold 0.10 → best case 5/5=1.0, should NOT stop
result="$(can_early_stop 3 0 2 1.0 0.10)"
assert_eq "No early stop: 3/3 done, 2 remaining, bl=1.0" "false" "$result"

# 1 pass, 0 failures, 4 remaining, baseline 0.5, threshold 0.10 → best case 5/5, should NOT stop
result="$(can_early_stop 1 0 4 0.5 0.10)"
assert_eq "No early stop: 1/1 done, 4 remaining, bl=0.5" "false" "$result"

echo ""
echo "Results: $passed/$total passed, $failed failed"
[[ $failed -gt 0 ]] && exit 1
exit 0
