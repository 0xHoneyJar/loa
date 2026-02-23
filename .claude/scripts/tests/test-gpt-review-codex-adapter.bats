#!/usr/bin/env bats
# test-gpt-review-codex-adapter.bats — Tests for lib-codex-exec.sh
# Run: bats .claude/scripts/tests/test-gpt-review-codex-adapter.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"
FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures/gpt-review"

setup() {
  TEST_DIR=$(mktemp -d)
  export MOCK_CODEX_BEHAVIOR="success"
  export MOCK_CODEX_VERSION="codex 0.2.0"
  export OPENAI_API_KEY="sk-test-key-for-testing"

  # Put mock codex on PATH
  mkdir -p "$TEST_DIR/bin"
  cp "$FIXTURES_DIR/mock_codex.bash" "$TEST_DIR/bin/codex"
  chmod +x "$TEST_DIR/bin/codex"
  export PATH="$TEST_DIR/bin:$PATH"

  # Override cache dir to test dir
  export TMPDIR="$TEST_DIR"

  # Source libraries
  source "$SCRIPT_DIR/lib-security.sh"
  source "$SCRIPT_DIR/lib-codex-exec.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# =============================================================================
# codex_is_available tests
# =============================================================================

@test "codex_is_available: returns 0 when codex is on PATH" {
  run codex_is_available
  [ "$status" -eq 0 ]
}

@test "codex_is_available: returns 1 when codex not on PATH" {
  export PATH="/usr/bin:/bin"  # Remove mock from PATH
  run codex_is_available
  [ "$status" -eq 1 ]
}

@test "codex_is_available: returns 2 when version too old" {
  export MOCK_CODEX_VERSION="codex 0.0.1"
  export CODEX_MIN_VERSION="0.1.0"
  run codex_is_available
  [ "$status" -eq 2 ]
}

@test "codex_is_available: accepts version equal to minimum" {
  export MOCK_CODEX_VERSION="codex 0.1.0"
  export CODEX_MIN_VERSION="0.1.0"
  run codex_is_available
  [ "$status" -eq 0 ]
}

# =============================================================================
# detect_capabilities tests
# =============================================================================

@test "detect_capabilities: creates cache file" {
  local cache_file
  cache_file=$(detect_capabilities)
  [ -f "$cache_file" ]
}

@test "detect_capabilities: cache file contains valid JSON" {
  local cache_file
  cache_file=$(detect_capabilities)
  jq empty "$cache_file"
  [ $? -eq 0 ]
}

@test "detect_capabilities: cache is version-scoped" {
  local cache_file
  cache_file=$(detect_capabilities)
  # Cache key is version hash (8 chars), not PID-scoped — avoids accumulating temp files
  [[ "$cache_file" == *"/loa-codex-caps-"*".json" ]]
}

@test "detect_capabilities: returns cached file on second call" {
  local first second
  first=$(detect_capabilities)
  second=$(detect_capabilities)
  [ "$first" = "$second" ]
}

# =============================================================================
# codex_has_capability tests
# =============================================================================

@test "codex_has_capability: --sandbox is supported" {
  run codex_has_capability "--sandbox"
  [ "$status" -eq 0 ]
}

@test "codex_has_capability: --ephemeral is supported" {
  run codex_has_capability "--ephemeral"
  [ "$status" -eq 0 ]
}

# =============================================================================
# parse_codex_output tests
# =============================================================================

@test "parse_codex_output: parses direct JSON" {
  local input='{"verdict":"APPROVED","summary":"OK"}'
  local result
  result=$(parse_codex_output "$input")
  [ "$(echo "$result" | jq -r '.verdict')" = "APPROVED" ]
}

@test "parse_codex_output: extracts JSON from markdown fences" {
  local input='Here is my review:

```json
{"verdict":"CHANGES_REQUIRED","summary":"Issues found"}
```

That is all.'
  local result
  result=$(parse_codex_output "$input")
  [ "$(echo "$result" | jq -r '.verdict')" = "CHANGES_REQUIRED" ]
}

@test "parse_codex_output: extracts greedy JSON from prose" {
  local input='My review says {"verdict":"APPROVED","summary":"Good"} and thats it'
  local result
  result=$(parse_codex_output "$input")
  [ "$(echo "$result" | jq -r '.verdict')" = "APPROVED" ]
}

@test "parse_codex_output: returns error 5 for non-JSON" {
  run parse_codex_output "This has no JSON at all"
  [ "$status" -eq 5 ]
}

# =============================================================================
# Workspace tests
# =============================================================================

@test "setup_review_workspace: creates temp directory" {
  local ws
  ws=$(setup_review_workspace "/dev/null" "false")
  [ -d "$ws" ]
  cleanup_workspace "$ws"
}

@test "cleanup_workspace: removes directory" {
  local ws
  ws=$(setup_review_workspace "/dev/null" "false")
  cleanup_workspace "$ws"
  [ ! -d "$ws" ]
}

# =============================================================================
# codex_exec_single tests
# =============================================================================

@test "codex_exec_single: succeeds with mock codex" {
  local of="$TEST_DIR/output.json"
  run codex_exec_single "Review this code" "gpt-5.2-codex" "$of" "$TEST_DIR" 30
  [ "$status" -eq 0 ]
}

@test "codex_exec_single: fails without OPENAI_API_KEY" {
  unset OPENAI_API_KEY
  local of="$TEST_DIR/output.json"
  run codex_exec_single "Review this" "gpt-5.2-codex" "$of" "$TEST_DIR" 30
  [ "$status" -eq 4 ]
}
