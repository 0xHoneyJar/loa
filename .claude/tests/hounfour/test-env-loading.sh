#!/usr/bin/env bash
# test-env-loading.sh — Tests for gpt-review-api.sh env loading behavior
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures/env"

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

echo "=== Env Loading Tests ==="

# Test 1: Duplicate keys — last value wins (tail -1 dedup)
result=$(grep -E "^OPENAI_API_KEY=" "$FIXTURES/duplicate-keys.env" | tail -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")
assert_eq "Duplicate keys: last value wins" "sk-second-key-wins" "$result"

# Test 2: Empty key — should be empty string
result=$(grep -E "^OPENAI_API_KEY=" "$FIXTURES/empty-key.env" | tail -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")
assert_eq "Empty key: empty string" "" "$result"

# Test 3: Whitespace trimming
trimmed="${result// /}"
if [[ -z "$trimmed" ]]; then
  echo "  PASS: Empty key: whitespace check passes"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Empty key: should be empty after trim"
  FAIL=$((FAIL + 1))
fi

# Test 4: .env.local overrides .env (simulate)
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT
cp "$FIXTURES/duplicate-keys.env" "$TMPDIR_TEST/.env"
echo "OPENAI_API_KEY=sk-local-override" > "$TMPDIR_TEST/.env.local"

env_key=""
if [[ -f "$TMPDIR_TEST/.env" ]]; then
  env_key=$(grep -E "^OPENAI_API_KEY=" "$TMPDIR_TEST/.env" 2>/dev/null | tail -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'" || true)
fi
if [[ -f "$TMPDIR_TEST/.env.local" ]]; then
  local_key=$(grep -E "^OPENAI_API_KEY=" "$TMPDIR_TEST/.env.local" 2>/dev/null | tail -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'" || true)
  if [[ -n "$local_key" ]]; then
    env_key="$local_key"
  fi
fi
assert_eq ".env.local overrides .env" "sk-local-override" "$env_key"

# Test 5: Inline comments stripped (updated to match tightened pattern: require space before #)
result=$(grep -E "^OPENAI_API_KEY=" "$FIXTURES/inline-comment.env" | tail -1 | cut -d'=' -f2- | sed 's/ \+#.*//' | tr -d '"' | tr -d "'")
assert_eq "Inline comment stripped" "sk-test-key-123" "$result"

# Test 6: Quoted values with inline comments (BB-021)
# Processing order: sed strips " # staging key", then tr strips quotes
result=$(grep -E "^OPENAI_API_KEY=" "$FIXTURES/quoted-inline-comment.env" | tail -1 | cut -d'=' -f2- | sed 's/ \+#.*//' | tr -d '"' | tr -d "'")
assert_eq "Quoted value with inline comment" "sk-test-key-456" "$result"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [[ $FAIL -gt 0 ]]; then exit 1; fi
exit 0
