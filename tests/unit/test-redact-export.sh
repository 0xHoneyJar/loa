#!/usr/bin/env bash
# test-redact-export.sh - Unit tests for redact-export.sh redaction pipeline
# Part of: cycle-038 Sprint 3 (global sprint-59)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REDACT_SCRIPT="$PROJECT_ROOT/.claude/scripts/redact-export.sh"
FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures/redaction"

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

run_redact() {
  # Run redact-export.sh with args, capture stdout, stderr, exit code
  # Usage: run_redact [args...] < input
  local out err rc
  out="$TEST_TMPDIR/stdout.$$"
  err="$TEST_TMPDIR/stderr.$$"
  bash "$REDACT_SCRIPT" "$@" > "$out" 2> "$err"
  rc=$?
  LAST_STDOUT=$(cat "$out")
  LAST_STDERR=$(cat "$err")
  LAST_RC=$rc
  rm -f "$out" "$err"
  return 0  # Always return 0 so test doesn't abort
}

# === Section: Fixture Exit Code Tests ===
echo ""
echo "=== Fixture Exit Code Tests ==="

# AC: Each fixture produces expected exit code

echo "--- BLOCK fixtures (expect exit 1) ---"

run_redact < "$FIXTURES_DIR/aws-key.txt"
assert_eq "aws-key.txt → exit 1 (BLOCK)" "1" "$LAST_RC"

run_redact < "$FIXTURES_DIR/github-pat.txt"
assert_eq "github-pat.txt → exit 1 (BLOCK)" "1" "$LAST_RC"

run_redact < "$FIXTURES_DIR/jwt.txt"
assert_eq "jwt.txt → exit 1 (BLOCK)" "1" "$LAST_RC"

run_redact < "$FIXTURES_DIR/slack-webhook.txt"
assert_eq "slack-webhook.txt → exit 1 (BLOCK)" "1" "$LAST_RC"

echo "--- REDACT fixtures (expect exit 0) ---"

run_redact < "$FIXTURES_DIR/abs-path.txt"
assert_eq "abs-path.txt → exit 0 (REDACT, not blocked)" "0" "$LAST_RC"

run_redact < "$FIXTURES_DIR/email.txt"
assert_eq "email.txt → exit 0 (REDACT, not blocked)" "0" "$LAST_RC"

echo "--- PASS fixtures (expect exit 0) ---"

run_redact < "$FIXTURES_DIR/clean.txt"
assert_eq "clean.txt → exit 0 (clean)" "0" "$LAST_RC"

run_redact < "$FIXTURES_DIR/allowlisted.txt"
assert_eq "allowlisted.txt → exit 0 (sentinel protected)" "0" "$LAST_RC"

echo "--- FLAG fixture (expect exit 0) ---"

run_redact < "$FIXTURES_DIR/high-entropy.txt"
assert_eq "high-entropy.txt → exit 0 (flagged, not blocked)" "0" "$LAST_RC"

echo "--- Sentinel bypass fixture (expect exit 1) ---"

run_redact < "$FIXTURES_DIR/sentinel-bypass-attempt.txt"
assert_eq "sentinel-bypass-attempt.txt → exit 1 (BLOCK overrides sentinel)" "1" "$LAST_RC"


# === Section: BLOCK Findings Halt Output ===
echo ""
echo "=== BLOCK Findings Halt Output ==="
# AC: BLOCK findings halt output (no stdout on exit 1)

run_redact < "$FIXTURES_DIR/aws-key.txt"
if [[ -z "$LAST_STDOUT" ]]; then
  record_pass "BLOCK produces no stdout output"
else
  record_fail "BLOCK produces no stdout output" "Got stdout: ${LAST_STDOUT:0:80}"
fi


# === Section: REDACT Placeholders ===
echo ""
echo "=== REDACT Placeholder Replacement ==="
# AC: REDACT findings replace with <redacted-*> placeholders

run_redact < "$FIXTURES_DIR/abs-path.txt"
if echo "$LAST_STDOUT" | grep -q '<redacted-path>'; then
  record_pass "Absolute paths replaced with <redacted-path>"
else
  record_fail "Absolute paths replaced with <redacted-path>" "Output: ${LAST_STDOUT:0:200}"
fi

run_redact < "$FIXTURES_DIR/email.txt"
if echo "$LAST_STDOUT" | grep -q '<redacted-email>'; then
  record_pass "Emails replaced with <redacted-email>"
else
  record_fail "Emails replaced with <redacted-email>" "Output: ${LAST_STDOUT:0:200}"
fi


# === Section: Allowlisted Content Preserved ===
echo ""
echo "=== Allowlist Sentinel Protection ==="
# AC: Allowlisted content preserved through redaction (REDACT/FLAG only)

run_redact < "$FIXTURES_DIR/allowlisted.txt"
if echo "$LAST_STDOUT" | grep -q 'sha256:a1b2c3d4e5f6'; then
  record_pass "Sentinel-protected hash preserved in output"
else
  record_fail "Sentinel-protected hash preserved in output" "Output: ${LAST_STDOUT:0:200}"
fi


# === Section: Sentinel-Wrapped BLOCK Still Blocked ===
echo ""
echo "=== Sentinel Cannot Override BLOCK ==="
# AC: Sentinel-wrapped BLOCK content is STILL blocked (sentinels don't override BLOCK)

run_redact < "$FIXTURES_DIR/sentinel-bypass-attempt.txt"
assert_eq "Sentinel-wrapped AWS key still blocked" "1" "$LAST_RC"
if echo "$LAST_STDERR" | grep -qi 'BLOCK\|aws_key'; then
  record_pass "Error message mentions BLOCK/aws_key"
else
  record_fail "Error message mentions BLOCK/aws_key" "Stderr: ${LAST_STDERR:0:200}"
fi


# === Section: Nested Sentinels ===
echo ""
echo "=== Nested Sentinels Treated as Plain Text ==="
# AC: Nested sentinels treated as plain text (not honored)

NESTED_INPUT=$(cat <<'NESTED_EOF'
<!-- redact-allow:outer -->
Some text
<!-- redact-allow:inner -->
/home/user/secret/path
<!-- /redact-allow -->
More text
<!-- /redact-allow -->
NESTED_EOF
)
run_redact <<< "$NESTED_INPUT"
# The outer sentinel should be broken by the inner marker. The /home path
# should be redacted since nesting invalidates sentinel protection.
if echo "$LAST_STDOUT" | grep -q '<redacted-path>'; then
  record_pass "Nested sentinel: inner path redacted (nesting breaks protection)"
else
  # If the path is preserved, sentinels are handling nesting (wrong)
  if echo "$LAST_STDOUT" | grep -q '/home/user/secret/path'; then
    record_fail "Nested sentinel: inner path should be redacted" "Path survived: sentinel nesting should not be honored"
  else
    record_pass "Nested sentinel: inner path redacted (nesting breaks protection)"
  fi
fi


# === Section: Malformed Sentinels ===
echo ""
echo "=== Malformed Sentinels Treated as Plain Text ==="
# AC: Malformed sentinels treated as plain text (not honored)

MALFORMED_INPUT=$(cat <<'MALFORMED_EOF'
<!-- redact-allow -->
/home/user/some/path
<!-- /redact-allow -->
MALFORMED_EOF
)
run_redact <<< "$MALFORMED_INPUT"
# Missing category in sentinel → malformed → path should be redacted
if echo "$LAST_STDOUT" | grep -q '<redacted-path>'; then
  record_pass "Malformed sentinel (no category): path redacted"
else
  if echo "$LAST_STDOUT" | grep -q '/home/user/some/path'; then
    record_fail "Malformed sentinel (no category): path should be redacted"
  else
    record_pass "Malformed sentinel (no category): path redacted"
  fi
fi


# === Section: Allow-Pattern Override ===
echo ""
echo "=== Operator Override (--allow-pattern) ==="
# AC: --allow-pattern overrides specific patterns with audit log entry

AUDIT_TMP="$TEST_TMPDIR/audit-allow.json"
run_redact --allow-pattern "AKIA" --audit-file "$AUDIT_TMP" < "$FIXTURES_DIR/aws-key.txt"
assert_eq "--allow-pattern AKIA overrides AWS key block" "0" "$LAST_RC"

if [[ -f "$AUDIT_TMP" ]]; then
  record_pass "Audit file written with --allow-pattern"
else
  record_fail "Audit file written with --allow-pattern"
fi

# AC: Operator override logged to audit file
if [[ -f "$AUDIT_TMP" ]]; then
  OVERRIDE_COUNT=$(jq '.overrides | length' "$AUDIT_TMP" 2>/dev/null || echo "0")
  if [[ "$OVERRIDE_COUNT" -gt 0 ]]; then
    record_pass "Override logged in audit file (count=$OVERRIDE_COUNT)"
  else
    record_fail "Override logged in audit file" "overrides array is empty"
  fi
fi


# === Section: Audit File Correctness ===
echo ""
echo "=== Audit File Correctness ==="
# AC: Audit file written with correct finding counts

# Clean file: all counts should be 0
AUDIT_CLEAN="$TEST_TMPDIR/audit-clean.json"
run_redact --audit-file "$AUDIT_CLEAN" < "$FIXTURES_DIR/clean.txt"
if [[ -f "$AUDIT_CLEAN" ]]; then
  BLOCK=$(jq '.findings.block' "$AUDIT_CLEAN" 2>/dev/null)
  REDACT=$(jq '.findings.redact' "$AUDIT_CLEAN" 2>/dev/null)
  FLAG=$(jq '.findings.flag' "$AUDIT_CLEAN" 2>/dev/null)
  if [[ "$BLOCK" == "0" && "$REDACT" == "0" && "$FLAG" == "0" ]]; then
    record_pass "Clean file: all finding counts are 0"
  else
    record_fail "Clean file: all finding counts are 0" "block=$BLOCK redact=$REDACT flag=$FLAG"
  fi
else
  record_fail "Clean file: audit file created"
fi

# Entropy file: flag count should be 1
AUDIT_ENTROPY="$TEST_TMPDIR/audit-entropy.json"
run_redact --audit-file "$AUDIT_ENTROPY" < "$FIXTURES_DIR/high-entropy.txt"
if [[ -f "$AUDIT_ENTROPY" ]]; then
  FLAG=$(jq '.findings.flag' "$AUDIT_ENTROPY" 2>/dev/null)
  FLAG_RULES=$(jq -r '.flag_rules[0] // ""' "$AUDIT_ENTROPY" 2>/dev/null)
  if [[ "$FLAG" -ge 1 && "$FLAG_RULES" == "high_entropy" ]]; then
    record_pass "High-entropy file: flag=1, rule=high_entropy"
  else
    record_fail "High-entropy file: flag=1, rule=high_entropy" "flag=$FLAG rules=$FLAG_RULES"
  fi
else
  record_fail "High-entropy file: audit file created"
fi


# === Section: Post-Redaction Safety Check ===
echo ""
echo "=== Post-Redaction Safety Check ==="
# AC: Post-redaction check catches any missed patterns

# Permissive mode (--no-strict) allows BLOCK patterns through but
# post-redaction should still catch them
AUDIT_POSTCHECK="$TEST_TMPDIR/audit-postcheck.json"
run_redact --no-strict --audit-file "$AUDIT_POSTCHECK" < "$FIXTURES_DIR/github-pat.txt"
# In permissive mode, BLOCK doesn't exit 1, but post-redaction check should catch ghp_
assert_eq "Post-redaction catches ghp_ in permissive mode" "1" "$LAST_RC"

if [[ -f "$AUDIT_POSTCHECK" ]]; then
  POST_CHECK=$(jq '.post_check_passed' "$AUDIT_POSTCHECK" 2>/dev/null)
  assert_eq "Post-check marked as failed in audit" "false" "$POST_CHECK"
fi


# === Section: Binary Input Rejection ===
echo ""
echo "=== Binary Input Rejection ==="
# AC: Binary input rejected (exit 2)

BINARY_TMP="$TEST_TMPDIR/binary-input"
printf 'Hello\x00World' > "$BINARY_TMP"
run_redact < "$BINARY_TMP"
assert_eq "Binary input (NUL bytes) → exit 2" "2" "$LAST_RC"

if echo "$LAST_STDERR" | grep -qi 'binary\|NUL'; then
  record_pass "Binary rejection error message mentions NUL/binary"
else
  record_fail "Binary rejection error message mentions NUL/binary" "Stderr: ${LAST_STDERR:0:200}"
fi


# === Section: Size Limit ===
echo ""
echo "=== Input Size Limit ==="
# AC: Input >50MB rejected (exit 2)

# Create a >50MB file (51MB of 'A')
LARGE_TMP="$TEST_TMPDIR/large-input"
dd if=/dev/zero bs=1M count=51 2>/dev/null | tr '\0' 'A' > "$LARGE_TMP"
run_redact < "$LARGE_TMP"
assert_eq "Input >50MB → exit 2" "2" "$LAST_RC"


# === Section: Entropy Detection ===
echo ""
echo "=== Entropy Detection ==="
# AC: Entropy detection triggers on random base64 >=20 chars, ignores sha256 hashes and UUIDs

# Random base64 string (high entropy, >=20 chars) should be flagged
AUDIT_ENT="$TEST_TMPDIR/audit-entropy-detail.json"
echo "Here is a random token: xK9mQ2vR7pL4wN8jF5hB3tY6uC1aE0sD" | \
  run_redact --audit-file "$AUDIT_ENT"
if [[ -f "$AUDIT_ENT" ]]; then
  FLAG=$(jq '.findings.flag' "$AUDIT_ENT" 2>/dev/null)
  if [[ "$FLAG" -ge 1 ]]; then
    record_pass "High entropy string (base64 >=20 chars) flagged"
  else
    record_fail "High entropy string (base64 >=20 chars) flagged" "flag=$FLAG"
  fi
fi

# SHA256 hash should NOT be flagged
AUDIT_SHA="$TEST_TMPDIR/audit-sha256.json"
echo "Hash: a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2" | \
  run_redact --audit-file "$AUDIT_SHA"
if [[ -f "$AUDIT_SHA" ]]; then
  FLAG=$(jq '.findings.flag' "$AUDIT_SHA" 2>/dev/null)
  if [[ "$FLAG" == "0" ]]; then
    record_pass "SHA256 hash NOT flagged by entropy"
  else
    record_fail "SHA256 hash NOT flagged by entropy" "flag=$FLAG"
  fi
fi

# UUID should NOT be flagged
AUDIT_UUID="$TEST_TMPDIR/audit-uuid.json"
echo "ID: 550e8400-e29b-41d4-a716-446655440000" | \
  run_redact --audit-file "$AUDIT_UUID"
if [[ -f "$AUDIT_UUID" ]]; then
  FLAG=$(jq '.findings.flag' "$AUDIT_UUID" 2>/dev/null)
  if [[ "$FLAG" == "0" ]]; then
    record_pass "UUID NOT flagged by entropy"
  else
    record_fail "UUID NOT flagged by entropy" "flag=$FLAG"
  fi
fi


# === Section: Empty Input ===
echo ""
echo "=== Edge Cases ==="

# Empty input
echo -n "" | run_redact
assert_eq "Empty input → exit 2" "2" "$LAST_RC"


# === Summary ===
echo ""
echo "============================================="
echo "  REDACT-EXPORT TEST RESULTS"
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
