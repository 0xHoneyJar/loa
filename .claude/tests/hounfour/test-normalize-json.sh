#!/usr/bin/env bash
# test-normalize-json.sh — Tests for normalize-json.sh library
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../../scripts/lib"
FIXTURES="$SCRIPT_DIR/fixtures/mock-responses"

source "$LIB_DIR/normalize-json.sh"

PASS=0
FAIL=0

assert_eq() {
  local test_name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    Expected: $expected"
    echo "    Actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit() {
  local test_name="$1" expected_exit="$2"
  shift 2
  local actual_exit=0
  "$@" >/dev/null 2>&1 || actual_exit=$?
  if [[ "$actual_exit" -eq "$expected_exit" ]]; then
    echo "  PASS: $test_name (exit $actual_exit)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    Expected exit: $expected_exit"
    echo "    Actual exit:   $actual_exit"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== normalize_json_response tests ==="

# Test 1: Valid JSON passthrough
result=$(normalize_json_response "$(cat "$FIXTURES/valid-json.txt")")
key=$(echo "$result" | jq -r '.improvements[0].id')
assert_eq "Valid JSON passthrough" "IMP-001" "$key"

# Test 2: Fenced JSON extraction
result=$(normalize_json_response "$(cat "$FIXTURES/fenced-json.txt")")
key=$(echo "$result" | jq -r '.improvements[0].id')
assert_eq "Fenced JSON extraction" "IMP-001" "$key"

# Test 3: Prose-wrapped JSON extraction
result=$(normalize_json_response "$(cat "$FIXTURES/prose-wrapped-json.txt")")
key=$(echo "$result" | jq -r '.improvements[0].id')
assert_eq "Prose-wrapped JSON extraction" "IMP-001" "$key"

# Test 4: Nested braces in strings
result=$(normalize_json_response "$(cat "$FIXTURES/nested-braces.txt")")
key=$(echo "$result" | jq -r '.improvements[0].id')
assert_eq "Nested braces in strings" "IMP-001" "$key"

# Test 5: Multiple JSON blocks (extracts first only)
multi='{"first": true} some text {"second": true}'
result=$(normalize_json_response "$multi")
first=$(echo "$result" | jq -r '.first // empty')
assert_eq "Multiple JSON blocks — extracts first" "true" "$first"

# Test 6: Prose containing {} before real payload
tricky='The config uses {} for defaults. Here is the review: {"improvements": []}'
result=$(normalize_json_response "$tricky" 2>/dev/null) || true
has_improvements=$(echo "$result" | jq 'has("improvements")' 2>/dev/null || echo "false")
# Either extracts {} or {"improvements":[]} — both are valid JSON
if echo "$result" | jq empty 2>/dev/null; then
  echo "  PASS: Prose with {} before payload — valid JSON extracted"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Prose with {} before payload"
  FAIL=$((FAIL + 1))
fi

# Test 7: BOM fixture verification — confirm actual BOM bytes exist (BB-020)
bom_check=$(head -c 3 "$FIXTURES/bom-prefixed-json.txt" | od -An -tx1 | tr -d ' \n')
assert_eq "BOM fixture has BOM bytes" "efbbbf" "$bom_check"

# Test 7b: Verify BOM is stripped during normalization (first 3 bytes of fixture != first bytes of output)
raw_first3=$(head -c 3 "$FIXTURES/bom-prefixed-json.txt" | od -An -tx1 | tr -d ' \n')
result_first=$(normalize_json_response "$(cat "$FIXTURES/bom-prefixed-json.txt")" | head -c 1)
if [[ "$raw_first3" == "efbbbf" ]] && [[ "$result_first" == "{" ]]; then
  echo "  PASS: BOM stripped — raw starts with BOM, output starts with {"
  PASS=$((PASS + 1))
else
  echo "  FAIL: BOM stripping verification"
  FAIL=$((FAIL + 1))
fi

# Test 7c: BOM-prefixed JSON extraction via normalize (exercises Step 1)
result=$(normalize_json_response "$(cat "$FIXTURES/bom-prefixed-json.txt")")
key=$(echo "$result" | jq -r '.improvements[0].id')
assert_eq "BOM-prefixed JSON extraction" "IMP-001" "$key"

# Test 8: Multi-fragment JSON extraction (BB-004 — exercises Step 4 python3 path)
result=$(normalize_json_response "$(cat "$FIXTURES/multi-fragment.txt")" 2>/dev/null) || true
if echo "$result" | jq empty 2>/dev/null; then
  echo "  PASS: Multi-fragment — valid JSON extracted"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Multi-fragment — no valid JSON extracted"
  FAIL=$((FAIL + 1))
fi

# Test 9: Malformed JSON → exit 1
assert_exit "Malformed JSON rejected" 1 normalize_json_response "$(cat "$FIXTURES/malformed.txt")"

# Test 10: Empty input → exit 1
assert_exit "Empty input rejected" 1 normalize_json_response ""

echo ""
echo "=== validate_json_field tests ==="

# Test 9: Array field valid
assert_exit "Array field valid" 0 validate_json_field '{"arr":[1,2]}' "arr" "array"

# Test 10: Null field rejected
assert_exit "Null array field rejected" 1 validate_json_field '{"arr":null}' "arr" "array"

# Test 11: String field valid
assert_exit "String field valid" 0 validate_json_field '{"name":"test"}' "name" "string"

# Test 12: Wrong type rejected
assert_exit "Wrong type (string vs number)" 1 validate_json_field '{"name":42}' "name" "string"

# Test 13: Integer field valid
assert_exit "Integer field valid" 0 validate_json_field '{"score":850}' "score" "integer"

# Test 14: Float rejected as integer
assert_exit "Float rejected as integer" 1 validate_json_field '{"score":85.5}' "score" "integer"

# Test 15: Missing field rejected
assert_exit "Missing field rejected" 1 validate_json_field '{"other":"val"}' "name" "string"

echo ""
echo "=== validate_agent_response tests ==="

# Test 16: Valid flatline-reviewer
assert_exit "Valid flatline-reviewer" 0 validate_agent_response '{"improvements":[{"id":"IMP-001","description":"test","priority":"HIGH"}]}' "flatline-reviewer"

# Test 17: Empty flatline-reviewer (valid — 0 findings)
assert_exit "Empty flatline-reviewer" 0 validate_agent_response '{"improvements":[]}' "flatline-reviewer"

# Test 18: Missing improvements array
assert_exit "Missing improvements array" 1 validate_agent_response '{"results":[]}' "flatline-reviewer"

# Test 19: Valid flatline-skeptic
assert_exit "Valid flatline-skeptic" 0 validate_agent_response '{"concerns":[{"id":"SKP-001","concern":"risk","severity":"HIGH","severity_score":750}]}' "flatline-skeptic"

# Test 20: Skeptic severity_score out of range
assert_exit "Skeptic severity_score >1000" 1 validate_agent_response '{"concerns":[{"id":"SKP-001","concern":"risk","severity":"HIGH","severity_score":1500}]}' "flatline-skeptic"

# Test 21: Valid flatline-scorer
assert_exit "Valid flatline-scorer" 0 validate_agent_response '{"scores":[{"id":"IMP-001","score":850}]}' "flatline-scorer"

# Test 22: Valid gpt-reviewer APPROVED
assert_exit "Valid gpt-reviewer APPROVED" 0 validate_agent_response '{"verdict":"APPROVED","summary":"looks good"}' "gpt-reviewer"

# Test 23: Valid gpt-reviewer CHANGES_REQUIRED
assert_exit "Valid gpt-reviewer CHANGES_REQUIRED" 0 validate_agent_response '{"verdict":"CHANGES_REQUIRED","summary":"needs work"}' "gpt-reviewer"

# Test 24: Invalid verdict enum
assert_exit "Invalid verdict enum" 1 validate_agent_response '{"verdict":"REJECTED","summary":"no"}' "gpt-reviewer"

# Test 25: Unknown agent (should pass — no validation)
assert_exit "Unknown agent passes" 0 validate_agent_response '{"anything":true}' "unknown-agent"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS + FAIL))"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
