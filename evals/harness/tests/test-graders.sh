#!/usr/bin/env bash
# test-graders.sh — Tests for individual graders
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVALS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GRADERS_DIR="$EVALS_DIR/graders"
TEST_DIR="$(mktemp -d /tmp/loa-test-graders-XXXXXX)"

passed=0
failed=0
total=0

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

assert_pass() {
  local desc="$1"
  local grader="$2"
  shift 2
  total=$((total + 1))
  local output
  output="$("$GRADERS_DIR/$grader" "$@" 2>/dev/null)" && exit_code=0 || exit_code=$?
  local pass
  pass="$(echo "$output" | jq -r '.pass' 2>/dev/null || echo "false")"
  if [[ "$pass" == "true" && $exit_code -eq 0 ]]; then
    echo "  PASS: $desc"
    passed=$((passed + 1))
  else
    echo "  FAIL: $desc (exit=$exit_code, output=$output)"
    failed=$((failed + 1))
  fi
}

assert_grader_fail() {
  local desc="$1"
  local grader="$2"
  shift 2
  total=$((total + 1))
  local output
  output="$("$GRADERS_DIR/$grader" "$@" 2>/dev/null)" && exit_code=0 || exit_code=$?
  local pass
  pass="$(echo "$output" | jq -r '.pass' 2>/dev/null || echo "true")"
  if [[ "$pass" == "false" && $exit_code -eq 1 ]]; then
    echo "  PASS: $desc"
    passed=$((passed + 1))
  else
    echo "  FAIL: $desc (exit=$exit_code, pass=$pass)"
    failed=$((failed + 1))
  fi
}

# --- Setup test workspace ---
mkdir -p "$TEST_DIR/workspace/src" "$TEST_DIR/workspace/.claude/skills/test" "$TEST_DIR/workspace/.claude/data"
echo 'export function hello() { return "world"; }' > "$TEST_DIR/workspace/src/index.ts"
echo '{"constraints":[]}' > "$TEST_DIR/workspace/.claude/data/constraints.json"

echo "=== Grader Tests ==="

# --- file-exists.sh ---
echo ""
echo "--- file-exists.sh ---"
assert_pass "Existing file found" "file-exists.sh" "$TEST_DIR/workspace" "src/index.ts"
assert_grader_fail "Missing file detected" "file-exists.sh" "$TEST_DIR/workspace" "src/nonexistent.ts"
assert_pass "Multiple files found" "file-exists.sh" "$TEST_DIR/workspace" "src/index.ts" ".claude/data/constraints.json"
assert_grader_fail "One missing in multiple" "file-exists.sh" "$TEST_DIR/workspace" "src/index.ts" "missing.txt"

# --- function-exported.sh ---
echo ""
echo "--- function-exported.sh ---"
assert_pass "Export found" "function-exported.sh" "$TEST_DIR/workspace" "hello" "src/index.ts"
assert_grader_fail "Export not found" "function-exported.sh" "$TEST_DIR/workspace" "nonexistent" "src/index.ts"
assert_grader_fail "File not found" "function-exported.sh" "$TEST_DIR/workspace" "hello" "src/missing.ts"

# --- pattern-match.sh ---
echo ""
echo "--- pattern-match.sh ---"
assert_pass "Pattern found" "pattern-match.sh" "$TEST_DIR/workspace" "function hello" "*.ts"
assert_grader_fail "Pattern not found" "pattern-match.sh" "$TEST_DIR/workspace" "nonexistent_pattern" "*.ts"

# --- no-secrets.sh ---
echo ""
echo "--- no-secrets.sh ---"
assert_pass "Clean workspace has no secrets" "no-secrets.sh" "$TEST_DIR/workspace"

# Create a workspace with a secret
mkdir -p "$TEST_DIR/secret-workspace"
echo 'API_KEY=AKIAIOSFODNN7EXAMPLE' > "$TEST_DIR/secret-workspace/config.txt"
assert_grader_fail "Secret detected" "no-secrets.sh" "$TEST_DIR/secret-workspace"

# --- quality-gate.sh ---
echo ""
echo "--- quality-gate.sh ---"
# Create workspace with valid structure
mkdir -p "$TEST_DIR/quality-workspace/.claude/skills/test" "$TEST_DIR/quality-workspace/.claude/data"
echo 'name: test' > "$TEST_DIR/quality-workspace/.claude/skills/test/index.yaml"
echo '{}' > "$TEST_DIR/quality-workspace/.claude/data/constraints.json"
assert_pass "Quality gate: skill-index" "quality-gate.sh" "$TEST_DIR/quality-workspace" "skill-index"
assert_pass "Quality gate: constraints" "quality-gate.sh" "$TEST_DIR/quality-workspace" "constraints"

# --- pattern-match.sh: ReDoS guard ---
echo ""
echo "--- pattern-match.sh: ReDoS guard ---"

# Nested quantifiers should be rejected (exit 2)
assert_grader_error() {
  local desc="$1"
  local grader="$2"
  shift 2
  total=$((total + 1))
  local output
  output="$("$GRADERS_DIR/$grader" "$@" 2>/dev/null)" && exit_code=0 || exit_code=$?
  if [[ $exit_code -eq 2 ]]; then
    echo "  PASS: $desc"
    passed=$((passed + 1))
  else
    echo "  FAIL: $desc (expected exit=2, got exit=$exit_code)"
    failed=$((failed + 1))
  fi
}

assert_grader_error "ReDoS: nested (a+)+" "pattern-match.sh" "$TEST_DIR/workspace" '(a+)+' "*.ts"
assert_grader_error "ReDoS: nested (a*)*" "pattern-match.sh" "$TEST_DIR/workspace" '(a*)*' "*.ts"
assert_grader_error "ReDoS: nested (a{2,}){2,}" "pattern-match.sh" "$TEST_DIR/workspace" '(a{2,}){2,}' "*.ts"

# Long regex should be rejected
long_pattern="$(printf 'a%.0s' {1..201})"
assert_grader_error "ReDoS: pattern exceeds 200 chars" "pattern-match.sh" "$TEST_DIR/workspace" "$long_pattern" "*.ts"

# Normal patterns should still work
assert_pass "Normal regex still works" "pattern-match.sh" "$TEST_DIR/workspace" "function" "*.ts"

# --- tests-pass.sh: metacharacter injection guard ---
echo ""
echo "--- tests-pass.sh: injection guard ---"

# Shell metacharacters should be rejected
assert_grader_error "Injection: semicolon" "tests-pass.sh" "$TEST_DIR/workspace" "echo hello; rm -rf /"
assert_grader_error "Injection: pipe" "tests-pass.sh" "$TEST_DIR/workspace" "echo hello | cat"
assert_grader_error "Injection: backtick" "tests-pass.sh" "$TEST_DIR/workspace" 'echo `whoami`'
assert_grader_error "Injection: dollar" "tests-pass.sh" "$TEST_DIR/workspace" 'echo $HOME'

# --- Path traversal rejection ---
echo ""
echo "--- Security: Path traversal ---"
total=$((total + 1))
output="$("$GRADERS_DIR/file-exists.sh" "$TEST_DIR/workspace" "../../etc/passwd" 2>/dev/null)" && exit_code=0 || exit_code=$?
pass="$(echo "$output" | jq -r '.pass' 2>/dev/null || echo "true")"
if [[ "$pass" == "false" ]]; then
  echo "  PASS: Path traversal rejected by file-exists.sh"
  passed=$((passed + 1))
else
  echo "  FAIL: Path traversal not rejected by file-exists.sh"
  failed=$((failed + 1))
fi

echo ""
echo "Results: $passed/$total passed, $failed failed"
[[ $failed -gt 0 ]] && exit 1
exit 0
