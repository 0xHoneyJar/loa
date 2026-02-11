#!/usr/bin/env bash
# test-validate-task.sh — Tests for validate-task.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EVALS_DIR="$(cd "$HARNESS_DIR/.." && pwd)"
VALIDATE="$HARNESS_DIR/validate-task.sh"
TEST_DIR="$(mktemp -d /tmp/loa-test-validate-XXXXXX)"

passed=0
failed=0
total=0

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

assert_valid() {
  local desc="$1"
  local file="$2"
  total=$((total + 1))
  local result
  result="$("$VALIDATE" "$file" 2>/dev/null)" && exit_code=0 || exit_code=$?
  local valid
  valid="$(echo "$result" | jq -r '.valid')"
  if [[ "$valid" == "true" && $exit_code -eq 0 ]]; then
    echo "  PASS: $desc"
    passed=$((passed + 1))
  else
    echo "  FAIL: $desc (expected valid, got: $result)"
    failed=$((failed + 1))
  fi
}

assert_invalid() {
  local desc="$1"
  local file="$2"
  local expected_error="${3:-}"
  total=$((total + 1))
  local result
  result="$("$VALIDATE" "$file" 2>/dev/null)" && exit_code=0 || exit_code=$?
  local valid
  valid="$(echo "$result" | jq -r '.valid')"
  if [[ "$valid" == "false" ]]; then
    if [[ -n "$expected_error" ]]; then
      if echo "$result" | jq -r '.errors[]' | grep -q "$expected_error"; then
        echo "  PASS: $desc"
        passed=$((passed + 1))
      else
        echo "  FAIL: $desc (expected error containing '$expected_error', got: $result)"
        failed=$((failed + 1))
      fi
    else
      echo "  PASS: $desc"
      passed=$((passed + 1))
    fi
  else
    echo "  FAIL: $desc (expected invalid, got valid)"
    failed=$((failed + 1))
  fi
}

# --- Setup test fixtures ---
# Create a valid task file
mkdir -p "$TEST_DIR"
cat > "$TEST_DIR/valid-task.yaml" <<'YAML'
id: valid-task
schema_version: 1
skill: test-skill
category: framework
fixture: loa-skill-dir
description: "A valid test task"
trials: 1
timeout:
  per_trial: 60
  per_grader: 30
graders:
  - type: code
    script: file-exists.sh
    args: [".claude/skills/test-skill/index.yaml"]
    weight: 1.0
YAML

echo "=== validate-task.sh Tests ==="

# Test 1: Valid task passes
assert_valid "Valid task passes validation" "$TEST_DIR/valid-task.yaml"

# Test 2: Missing id
cat > "$TEST_DIR/no-id.yaml" <<'YAML'
schema_version: 1
skill: test-skill
category: framework
fixture: loa-skill-dir
description: "Missing id"
graders:
  - type: code
    script: file-exists.sh
    args: ["file.txt"]
YAML
assert_invalid "Missing id detected" "$TEST_DIR/no-id.yaml" "Missing required field: id"

# Test 3: Wrong schema_version
cat > "$TEST_DIR/bad-schema.yaml" <<'YAML'
id: bad-schema
schema_version: 99
skill: test-skill
category: framework
fixture: loa-skill-dir
description: "Bad schema version"
graders:
  - type: code
    script: file-exists.sh
    args: ["file.txt"]
YAML
assert_invalid "Unsupported schema_version" "$TEST_DIR/bad-schema.yaml" "Unsupported schema_version"

# Test 4: Invalid category
cat > "$TEST_DIR/bad-category.yaml" <<'YAML'
id: bad-category
schema_version: 1
skill: test-skill
category: invalid-category
fixture: loa-skill-dir
description: "Bad category"
graders:
  - type: code
    script: file-exists.sh
    args: ["file.txt"]
YAML
assert_invalid "Invalid category detected" "$TEST_DIR/bad-category.yaml" "Invalid category"

# Test 5: Missing graders
cat > "$TEST_DIR/no-graders.yaml" <<'YAML'
id: no-graders
schema_version: 1
skill: test-skill
category: framework
fixture: loa-skill-dir
description: "No graders"
graders: []
YAML
assert_invalid "Missing graders detected" "$TEST_DIR/no-graders.yaml" "At least one grader"

# Test 6: Id mismatch with filename
cat > "$TEST_DIR/wrong-id.yaml" <<'YAML'
id: different-name
schema_version: 1
skill: test-skill
category: framework
fixture: loa-skill-dir
description: "ID mismatch"
graders:
  - type: code
    script: file-exists.sh
    args: ["file.txt"]
YAML
assert_invalid "ID mismatch with filename" "$TEST_DIR/wrong-id.yaml" "does not match filename"

# Test 7: Shell metacharacter in grader args
cat > "$TEST_DIR/metachar.yaml" <<'YAML'
id: metachar
schema_version: 1
skill: test-skill
category: framework
fixture: loa-skill-dir
description: "Metachar test"
graders:
  - type: code
    script: file-exists.sh
    args: ["file.txt; rm -rf /"]
YAML
assert_invalid "Shell metacharacter in args rejected" "$TEST_DIR/metachar.yaml" "shell metacharacter"

# Test 8: Path traversal in grader args
cat > "$TEST_DIR/traversal.yaml" <<'YAML'
id: traversal
schema_version: 1
skill: test-skill
category: framework
fixture: loa-skill-dir
description: "Traversal test"
graders:
  - type: code
    script: file-exists.sh
    args: ["../../etc/passwd"]
YAML
assert_invalid "Path traversal in args rejected" "$TEST_DIR/traversal.yaml" "path traversal"

# Test 9: File not found
assert_invalid "Nonexistent file" "$TEST_DIR/does-not-exist.yaml" "Task file not found"

# --- Summary ---
echo ""
echo "Results: $passed/$total passed, $failed failed"
if [[ $failed -gt 0 ]]; then
  exit 1
fi
exit 0
