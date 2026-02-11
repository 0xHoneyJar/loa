#!/usr/bin/env bash
# Test runner for shell-scripts fixture
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(cd "$SCRIPT_DIR/../src" && pwd)"

source "$SRC_DIR/utils.sh"

passed=0
failed=0
total=0

assert_true() {
  local desc="$1"
  shift
  total=$((total + 1))
  if "$@"; then
    echo "  PASS: $desc"
    passed=$((passed + 1))
  else
    echo "  FAIL: $desc"
    failed=$((failed + 1))
  fi
}

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  total=$((total + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $desc"
    passed=$((passed + 1))
  else
    echo "  FAIL: $desc (expected: $expected, got: $actual)"
    failed=$((failed + 1))
  fi
}

echo "=== Shell Utils Tests ==="

# is_integer
assert_true "42 is integer" is_integer 42
assert_true "-7 is integer" is_integer -7
assert_true "abc is not integer" ! is_integer abc

# to_upper
assert_eq "hello to upper" "HELLO" "$(to_upper hello)"
assert_eq "mixed to upper" "HELLO WORLD" "$(to_upper 'hello world')"

# count_lines
tmpfile=$(mktemp)
printf 'line1\nline2\nline3\n' > "$tmpfile"
line_count=$(count_lines "$tmpfile")
# Trim whitespace from wc output
line_count=$(echo "$line_count" | tr -d ' ')
assert_eq "count lines" "3" "$line_count"
rm -f "$tmpfile"

# command_exists
assert_true "bash exists" command_exists bash
assert_true "nonexistent_cmd_xyz does not exist" ! command_exists nonexistent_cmd_xyz

echo ""
echo "Results: $passed/$total passed, $failed failed"
[[ $failed -gt 0 ]] && exit 1
exit 0
