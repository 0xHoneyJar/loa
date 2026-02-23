#!/usr/bin/env bats
# test-gpt-review-security.bats — Tests for lib-security.sh
# Run: bats .claude/scripts/tests/test-gpt-review-security.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"

setup() {
  TEST_DIR=$(mktemp -d)
  # Source the library
  source "$SCRIPT_DIR/lib-security.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# =============================================================================
# ensure_codex_auth tests
# =============================================================================

@test "ensure_codex_auth: returns 0 when OPENAI_API_KEY is set" {
  OPENAI_API_KEY="sk-test-key-12345"
  run ensure_codex_auth
  [ "$status" -eq 0 ]
}

@test "ensure_codex_auth: returns 1 when OPENAI_API_KEY is empty" {
  unset OPENAI_API_KEY
  run ensure_codex_auth
  [ "$status" -eq 1 ]
}

@test "ensure_codex_auth: returns 1 when OPENAI_API_KEY is unset" {
  OPENAI_API_KEY=""
  run ensure_codex_auth
  [ "$status" -eq 1 ]
}

# =============================================================================
# redact_secrets tests (text mode)
# =============================================================================

@test "redact_secrets: redacts OpenAI API keys in text" {
  local input="My key is sk-proj-abc123def456ghi789jkl012mno345pqr678"
  local result
  result=$(redact_secrets "$input" "text")
  [[ "$result" != *"sk-proj-"* ]]
  [[ "$result" == *"[REDACTED]"* ]]
}

@test "redact_secrets: redacts Anthropic API keys in text" {
  local input="Anthropic key: sk-ant-api03-abc123def456ghi789jkl012mno345"
  local result
  result=$(redact_secrets "$input" "text")
  [[ "$result" != *"sk-ant-"* ]]
  [[ "$result" == *"[REDACTED]"* ]]
}

@test "redact_secrets: redacts GitHub tokens in text" {
  local input="Token: ghp_abcdefghijklmnopqrstuvwxyz1234567890AB"
  local result
  result=$(redact_secrets "$input" "text")
  [[ "$result" != *"ghp_"* ]]
  [[ "$result" == *"[REDACTED]"* ]]
}

@test "redact_secrets: redacts AWS access keys in text" {
  local input="AWS key: AKIAIOSFODNN7EXAMPLE"
  local result
  result=$(redact_secrets "$input" "text")
  [[ "$result" != *"AKIAIOSFODNN7"* ]]
  [[ "$result" == *"[REDACTED]"* ]]
}

@test "redact_secrets: leaves non-secret text unchanged" {
  local input="This is a normal review comment with no secrets"
  local result
  result=$(redact_secrets "$input" "text")
  [ "$result" = "$input" ]
}

# =============================================================================
# redact_secrets tests (JSON mode)
# =============================================================================

@test "redact_secrets: redacts values in JSON, preserves keys" {
  local input='{"api_key":"sk-proj-abc123def456ghi789jkl012mno345pqr678","name":"test"}'
  local result
  result=$(redact_secrets "$input" "json")
  # Key preserved
  [[ "$result" == *'"api_key"'* ]]
  # Value redacted
  [[ "$result" != *"sk-proj-"* ]]
  [[ "$result" == *"[REDACTED]"* ]]
  # JSON still valid
  echo "$result" | jq empty
}

@test "redact_secrets: preserves JSON structure after redaction" {
  local input='{"a":"safe","b":{"c":"sk-proj-test12345678901234567890abcdef","d":42}}'
  local result
  result=$(redact_secrets "$input" "json")
  # Count keys — should be same before and after
  local pre_keys post_keys
  pre_keys=$(echo "$input" | jq '[paths(scalars)] | length')
  post_keys=$(echo "$result" | jq '[paths(scalars)] | length')
  [ "$pre_keys" = "$post_keys" ]
}

@test "redact_secrets: JSON output remains valid after redaction" {
  local input='{"verdict":"APPROVED","secret":"sk-test-abcdefghijklmnopqrstuvwxyz"}'
  local result
  result=$(redact_secrets "$input" "json")
  echo "$result" | jq empty
  [ $? -eq 0 ]
}

# =============================================================================
# is_sensitive_file tests
# =============================================================================

@test "is_sensitive_file: detects .env files" {
  run is_sensitive_file ".env"
  [ "$status" -eq 0 ]
}

@test "is_sensitive_file: detects .env.local" {
  run is_sensitive_file ".env.local"
  [ "$status" -eq 0 ]
}

@test "is_sensitive_file: detects PEM files" {
  run is_sensitive_file "certs/server.pem"
  [ "$status" -eq 0 ]
}

@test "is_sensitive_file: detects credentials.json" {
  run is_sensitive_file "config/credentials.json"
  [ "$status" -eq 0 ]
}

@test "is_sensitive_file: allows normal source files" {
  run is_sensitive_file "src/main.ts"
  [ "$status" -eq 1 ]
}

@test "is_sensitive_file: allows markdown files" {
  run is_sensitive_file "docs/README.md"
  [ "$status" -eq 1 ]
}
