#!/usr/bin/env bash
# test-sandbox.sh — Tests for sandbox.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SANDBOX="$HARNESS_DIR/sandbox.sh"

passed=0
failed=0
total=0

assert_ok() {
  local desc="$1"
  shift
  total=$((total + 1))
  if "$@" &>/dev/null; then
    echo "  PASS: $desc"
    passed=$((passed + 1))
  else
    echo "  FAIL: $desc (exit code: $?)"
    failed=$((failed + 1))
  fi
}

assert_fail() {
  local desc="$1"
  shift
  total=$((total + 1))
  if ! "$@" &>/dev/null; then
    echo "  PASS: $desc"
    passed=$((passed + 1))
  else
    echo "  FAIL: $desc (expected failure, got success)"
    failed=$((failed + 1))
  fi
}

assert_contains() {
  local desc="$1"
  local haystack="$2"
  local needle="$3"
  total=$((total + 1))
  if echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $desc"
    passed=$((passed + 1))
  else
    echo "  FAIL: $desc (expected '$needle' in output)"
    failed=$((failed + 1))
  fi
}

echo "=== sandbox.sh Tests ==="

# Test 1: Create sandbox from fixture
sandbox_path="$("$SANDBOX" create --fixture loa-skill-dir --run-id test-run-1 --trial-id test-run-1-trial-1 2>/dev/null)"
total=$((total + 1))
if [[ -d "$sandbox_path" ]]; then
  echo "  PASS: Sandbox created at $sandbox_path"
  passed=$((passed + 1))
else
  echo "  FAIL: Sandbox not created"
  failed=$((failed + 1))
fi

# Test 2: Fixture files copied
total=$((total + 1))
if [[ -f "$sandbox_path/fixture.yaml" ]]; then
  echo "  PASS: Fixture files present in sandbox"
  passed=$((passed + 1))
else
  echo "  FAIL: Fixture files not found in sandbox"
  failed=$((failed + 1))
fi

# Test 3: Git initialized
total=$((total + 1))
if [[ -d "$sandbox_path/.git" ]]; then
  echo "  PASS: Git initialized in sandbox"
  passed=$((passed + 1))
else
  echo "  FAIL: Git not initialized in sandbox"
  failed=$((failed + 1))
fi

# Test 4: Environment fingerprint created
total=$((total + 1))
parent_dir="$(dirname "$sandbox_path")"
if [[ -f "$parent_dir/env-fingerprint.json" ]]; then
  echo "  PASS: Environment fingerprint created"
  passed=$((passed + 1))
else
  echo "  FAIL: Environment fingerprint not found"
  failed=$((failed + 1))
fi

# Test 5: Destroy sandbox
"$SANDBOX" destroy --trial-id test-run-1-trial-1 2>/dev/null
total=$((total + 1))
if [[ ! -d "$parent_dir" ]]; then
  echo "  PASS: Sandbox destroyed"
  passed=$((passed + 1))
else
  echo "  FAIL: Sandbox still exists after destroy"
  failed=$((failed + 1))
  rm -rf "$parent_dir"
fi

# Test 6: Path traversal rejected
total=$((total + 1))
output="$("$SANDBOX" create --fixture "../../../etc" --run-id test-run-2 2>&1)" && exit_code=0 || exit_code=$?
if [[ $exit_code -ne 0 ]]; then
  echo "  PASS: Path traversal rejected"
  passed=$((passed + 1))
else
  echo "  FAIL: Path traversal not rejected"
  failed=$((failed + 1))
fi

# Test 7: Missing fixture rejected
total=$((total + 1))
output="$("$SANDBOX" create --fixture nonexistent-fixture --run-id test-run-3 2>&1)" && exit_code=0 || exit_code=$?
if [[ $exit_code -ne 0 ]]; then
  echo "  PASS: Missing fixture rejected"
  passed=$((passed + 1))
else
  echo "  FAIL: Missing fixture not rejected"
  failed=$((failed + 1))
fi

# Test 8: Destroy-all works
"$SANDBOX" create --fixture loa-skill-dir --run-id test-run-4 --trial-id test-run-4-trial-1 &>/dev/null || true
"$SANDBOX" create --fixture loa-skill-dir --run-id test-run-4 --trial-id test-run-4-trial-2 &>/dev/null || true
"$SANDBOX" destroy-all --run-id test-run-4 2>/dev/null
total=$((total + 1))
remaining=$(find /tmp -maxdepth 1 -name "loa-eval-test-run-4*" -type d 2>/dev/null | wc -l)
if [[ "$remaining" -eq 0 ]]; then
  echo "  PASS: destroy-all cleaned up"
  passed=$((passed + 1))
else
  echo "  FAIL: destroy-all left $remaining sandboxes"
  failed=$((failed + 1))
fi

echo ""
echo "Results: $passed/$total passed, $failed failed"
[[ $failed -gt 0 ]] && exit 1
exit 0
