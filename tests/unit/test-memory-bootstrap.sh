#!/usr/bin/env bash
# test-memory-bootstrap.sh - Unit tests for memory-bootstrap.sh
# Part of: cycle-038 Sprint 5 (global sprint-61)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOTSTRAP_SCRIPT="$PROJECT_ROOT/.claude/scripts/memory-bootstrap.sh"
REDACT_SCRIPT="$PROJECT_ROOT/.claude/scripts/redact-export.sh"

# Test counter (file-based for subshell propagation)
TEST_RESULTS=$(mktemp)
echo "0 0 0" > "$TEST_RESULTS"

TEST_TMPDIR=$(mktemp -d)

cleanup() {
  rm -rf "$TEST_TMPDIR" "$TEST_RESULTS"
}
trap cleanup EXIT

# === Test Helpers ===

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  local counts
  counts=$(cat "$TEST_RESULTS")
  local total pass fail
  total=$(echo "$counts" | awk '{print $1}')
  pass=$(echo "$counts" | awk '{print $2}')
  fail=$(echo "$counts" | awk '{print $3}')
  total=$((total + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $desc"
    pass=$((pass + 1))
  else
    echo "  FAIL: $desc"
    echo "    Expected: $expected"
    echo "    Actual:   $actual"
    fail=$((fail + 1))
  fi
  echo "$total $pass $fail" > "$TEST_RESULTS"
}

record_pass() {
  local desc="$1"
  local counts
  counts=$(cat "$TEST_RESULTS")
  local total pass fail
  total=$(echo "$counts" | awk '{print $1}')
  pass=$(echo "$counts" | awk '{print $2}')
  fail=$(echo "$counts" | awk '{print $3}')
  echo "$((total + 1)) $((pass + 1)) $fail" > "$TEST_RESULTS"
  echo "  PASS: $desc"
}

record_fail() {
  local desc="$1" msg="${2:-}"
  local counts
  counts=$(cat "$TEST_RESULTS")
  local total pass fail
  total=$(echo "$counts" | awk '{print $1}')
  pass=$(echo "$counts" | awk '{print $2}')
  fail=$(echo "$counts" | awk '{print $3}')
  echo "$((total + 1)) $pass $((fail + 1))" > "$TEST_RESULTS"
  echo "  FAIL: $desc"
  [[ -n "$msg" ]] && echo "    $msg"
}

# Setup a minimal test environment
setup_env() {
  local env_dir="$TEST_TMPDIR/env-$$-$RANDOM"
  mkdir -p "$env_dir/.loa-state/memory" \
           "$env_dir/.loa-state/trajectory/current" \
           "$env_dir/.loa-state/trajectory/archive" \
           "$env_dir/.loa-state/run/bridge-reviews" \
           "$env_dir/grimoires/loa/a2a/flatline" \
           "$env_dir/grimoires/loa/a2a/sprint-1"
  # Don't cd — use env vars for isolation
  echo "$env_dir"
}

run_bootstrap() {
  local env_dir="$1"; shift
  LOA_STATE_DIR="$env_dir/.loa-state" \
  LOA_GRIMOIRE_DIR="$env_dir/grimoires/loa" \
  LOA_ALLOW_ABSOLUTE_STATE=1 \
  bash "$BOOTSTRAP_SCRIPT" "$@" 2>&1
}

# === Test: Trajectory extraction picks only cite/learning phases ===
echo ""
echo "=== Trajectory Extraction ==="

ENV=$(setup_env)
# Create trajectory with mixed phases
cat > "$ENV/.loa-state/trajectory/current/test.jsonl" <<'TRAJ'
{"ts":"2026-02-24T10:00:00Z","agent":"impl","phase":"implementation","action":"wrote some code here"}
{"ts":"2026-02-24T10:01:00Z","agent":"impl","phase":"cite","action":"The three-zone model ensures separation of concerns"}
{"ts":"2026-02-24T10:02:00Z","agent":"impl","phase":"learning","action":"Fail-closed redaction prevents secret leakage in exports"}
{"ts":"2026-02-24T10:03:00Z","agent":"impl","phase":"review","action":"reviewed the implementation thoroughly"}
TRAJ

OUTPUT=$(run_bootstrap "$ENV" --source trajectory)
STAGED="$ENV/.loa-state/memory/observations-staged.jsonl"

if [[ -f "$STAGED" ]]; then
  STAGED_COUNT=$(wc -l < "$STAGED")
  assert_eq "Trajectory: only cite/learning extracted (2 of 4)" "2" "$STAGED_COUNT"

  # Verify content
  if grep -q "three-zone model" "$STAGED" && grep -q "Fail-closed redaction" "$STAGED"; then
    record_pass "Trajectory: correct entries extracted"
  else
    record_fail "Trajectory: correct entries extracted"
  fi
else
  record_fail "Trajectory: staged file created"
  record_fail "Trajectory: correct entries extracted"
fi


# === Test: Flatline extraction picks only high_consensus ===
echo ""
echo "=== Flatline Extraction ==="

ENV=$(setup_env)
cat > "$ENV/grimoires/loa/a2a/flatline/prd-review.json" <<'FLAT'
{
  "high_consensus": [
    {"description": "Add rate limiting to the API gateway endpoint"},
    {"description": "Implement circuit breaker for external service calls"}
  ],
  "disputed": [
    {"description": "This should not be extracted because it is disputed"}
  ],
  "low_value": [
    {"description": "Low value items are skipped entirely"}
  ]
}
FLAT

run_bootstrap "$ENV" --source flatline >/dev/null 2>&1
STAGED="$ENV/.loa-state/memory/observations-staged.jsonl"

if [[ -f "$STAGED" ]]; then
  STAGED_COUNT=$(wc -l < "$STAGED")
  assert_eq "Flatline: only high_consensus extracted (2)" "2" "$STAGED_COUNT"

  if grep -q "rate limiting" "$STAGED" && ! grep -q "disputed" "$STAGED"; then
    record_pass "Flatline: correct items extracted, disputed excluded"
  else
    record_fail "Flatline: correct items extracted, disputed excluded"
  fi
else
  record_fail "Flatline: staged file created"
  record_fail "Flatline: correct items extracted"
fi


# === Test: Quality gate rejects low-confidence entries ===
echo ""
echo "=== Quality Gates ==="

ENV=$(setup_env)
# Create trajectory with explicit low confidence
cat > "$ENV/.loa-state/trajectory/current/test.jsonl" <<'QGATE'
{"ts":"2026-02-24T10:00:00Z","agent":"impl","phase":"learning","action":"High confidence learning about architecture patterns","outcome":{"confidence":0.9}}
{"ts":"2026-02-24T10:01:00Z","agent":"impl","phase":"learning","action":"Low confidence guess about something maybe","outcome":{"confidence":0.3}}
QGATE

run_bootstrap "$ENV" --source trajectory >/dev/null 2>&1
STAGED="$ENV/.loa-state/memory/observations-staged.jsonl"

if [[ -f "$STAGED" ]]; then
  STAGED_COUNT=$(wc -l < "$STAGED")
  assert_eq "Quality gate: low confidence rejected (1 of 2 staged)" "1" "$STAGED_COUNT"
else
  record_fail "Quality gate: staged file exists"
fi


# === Test: Content hash dedup prevents duplicates ===
echo ""
echo "=== Deduplication ==="

ENV=$(setup_env)
cat > "$ENV/.loa-state/trajectory/current/test.jsonl" <<'DEDUP'
{"ts":"2026-02-24T10:00:00Z","agent":"impl","phase":"learning","action":"The three-zone model ensures separation of concerns"}
{"ts":"2026-02-24T10:01:00Z","agent":"impl","phase":"learning","action":"The three-zone model ensures separation of concerns"}
{"ts":"2026-02-24T10:02:00Z","agent":"impl","phase":"learning","action":"A completely different unique observation about testing"}
DEDUP

run_bootstrap "$ENV" --source trajectory >/dev/null 2>&1
STAGED="$ENV/.loa-state/memory/observations-staged.jsonl"

if [[ -f "$STAGED" ]]; then
  STAGED_COUNT=$(wc -l < "$STAGED")
  assert_eq "Dedup: duplicate removed (2 of 3 staged)" "2" "$STAGED_COUNT"
else
  record_fail "Dedup: staged file exists"
fi


# === Test: --import runs redaction and appends to observations.jsonl ===
echo ""
echo "=== Import with Redaction ==="

ENV=$(setup_env)
cat > "$ENV/.loa-state/trajectory/current/test.jsonl" <<'IMPORT'
{"ts":"2026-02-24T10:00:00Z","agent":"impl","phase":"learning","action":"Clean observation about architectural patterns in the codebase"}
IMPORT

run_bootstrap "$ENV" --source trajectory --import >/dev/null 2>&1
RC=$?
OBS="$ENV/.loa-state/memory/observations.jsonl"

assert_eq "Import: exits 0 (clean content)" "0" "$RC"
if [[ -f "$OBS" ]]; then
  OBS_COUNT=$(wc -l < "$OBS")
  if [[ "$OBS_COUNT" -ge 1 ]]; then
    record_pass "Import: appended to observations.jsonl ($OBS_COUNT entries)"
  else
    record_fail "Import: appended to observations.jsonl" "File exists but empty"
  fi
else
  record_fail "Import: observations.jsonl created"
fi


# === Test: Blocked content prevents import (fail-closed) ===
echo ""
echo "=== Import Blocked Content ==="

ENV=$(setup_env)
cat > "$ENV/.loa-state/trajectory/current/test.jsonl" <<'BLOCKED'
{"ts":"2026-02-24T10:00:00Z","agent":"impl","phase":"learning","action":"Found AWS key AKIAIOSFODNN7EXAMPLE in the config"}
BLOCKED

run_bootstrap "$ENV" --source trajectory --import >/dev/null 2>&1
RC=$?
OBS="$ENV/.loa-state/memory/observations.jsonl"

assert_eq "Blocked: import exits 1 (secrets found)" "1" "$RC"
if [[ ! -f "$OBS" || ! -s "$OBS" ]]; then
  record_pass "Blocked: observations.jsonl NOT populated"
else
  OBS_COUNT=$(wc -l < "$OBS")
  if [[ "$OBS_COUNT" -eq 0 ]]; then
    record_pass "Blocked: observations.jsonl empty"
  else
    record_fail "Blocked: observations.jsonl NOT populated" "Has $OBS_COUNT entries"
  fi
fi


# === Summary ===
echo ""
echo "============================================="
echo "  MEMORY-BOOTSTRAP TEST RESULTS"
echo "============================================="
FINAL=$(cat "$TEST_RESULTS")
TOTAL=$(echo "$FINAL" | awk '{print $1}')
PASS=$(echo "$FINAL" | awk '{print $2}')
FAIL=$(echo "$FINAL" | awk '{print $3}')
echo "  Total: $TOTAL | Pass: $PASS | Fail: $FAIL"
echo "============================================="
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo "RESULT: FAIL ($FAIL failures)"
  exit 1
else
  echo "RESULT: ALL PASS"
  exit 0
fi
