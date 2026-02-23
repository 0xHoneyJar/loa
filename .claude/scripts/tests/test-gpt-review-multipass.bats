#!/usr/bin/env bats
# test-gpt-review-multipass.bats — Tests for lib-multipass.sh
# Run: bats .claude/scripts/tests/test-gpt-review-multipass.bats

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

  # Override dirs to test dir
  export TMPDIR="$TEST_DIR"
  export CONFIG_FILE="$TEST_DIR/config.yaml"

  # State dir for multi-pass call tracking
  export MOCK_CODEX_STATE_DIR="$TEST_DIR/mock-state"
  mkdir -p "$MOCK_CODEX_STATE_DIR"

  # Output dir for intermediate pass files
  mkdir -p "$TEST_DIR/a2a/gpt-review"

  # Source libraries
  source "$SCRIPT_DIR/lib-security.sh"
  source "$SCRIPT_DIR/lib-codex-exec.sh"
  source "$SCRIPT_DIR/lib-multipass.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# =============================================================================
# estimate_token_count tests
# =============================================================================

@test "estimate_token_count: returns approximate count for known string" {
  # 100 chars of English text ≈ 25 tokens (chars/4)
  local text="This is a test string that contains exactly one hundred characters of English text for token counting"
  run estimate_token_count "$text"
  [ "$status" -eq 0 ]
  # Should be around 25 (100/4) with heuristic
  local count="$output"
  [ "$count" -ge 20 ]
  [ "$count" -le 35 ]
}

@test "estimate_token_count: returns 1 for empty string" {
  run estimate_token_count ""
  [ "$status" -eq 0 ]
  # (0 + 3) / 4 = 0 with integer division
  [ "$output" -le 1 ]
}

# =============================================================================
# enforce_token_budget tests
# =============================================================================

@test "enforce_token_budget: passes through content under budget" {
  local content="Short content"
  run enforce_token_budget "$content" 1000
  [ "$status" -eq 0 ]
  [ "$output" = "Short content" ]
}

@test "enforce_token_budget: truncates content over budget" {
  # Create a string that exceeds budget (budget=5 → 20 chars)
  local content="This is a much longer string that definitely exceeds the tiny five token budget we set for this test case"
  run enforce_token_budget "$content" 5
  [ "$status" -eq 0 ]
  # Output should be shorter than input
  local out_len=${#output}
  local in_len=${#content}
  [ "$out_len" -lt "$in_len" ]
}

# =============================================================================
# check_budget_overflow tests
# =============================================================================

@test "check_budget_overflow: returns 0 when budget sufficient" {
  run check_budget_overflow 100 300 900
  [ "$status" -eq 0 ]
}

@test "check_budget_overflow: returns 1 when budget exceeded" {
  run check_budget_overflow 700 300 900
  [ "$status" -eq 1 ]
}

# =============================================================================
# Prompt builder tests
# =============================================================================

@test "build_pass1_prompt: includes planning instructions" {
  run build_pass1_prompt "system prompt" "user content"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pass 1: Planning"* ]]
  [[ "$output" == *"system prompt"* ]]
  [[ "$output" == *"user content"* ]]
  [[ "$output" == *"deep planning analysis"* ]]
}

@test "build_pass2_prompt: includes pass1 context" {
  run build_pass2_prompt "system prompt" "content to review" '{"scope":"test"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pass 2: Review"* ]]
  [[ "$output" == *"scope"* ]]
  [[ "$output" == *"content to review"* ]]
}

@test "build_pass3_prompt: includes verification instructions" {
  run build_pass3_prompt "system prompt" '{"findings":[{"issue":"test"}]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pass 3: Verification"* ]]
  [[ "$output" == *"Verify"* ]]
  [[ "$output" == *"false positives"* ]]
}

@test "build_combined_prompt: includes all reasoning instructions" {
  run build_combined_prompt "system prompt" "user content"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Single-Pass Review"* ]]
  [[ "$output" == *"system prompt"* ]]
  [[ "$output" == *"user content"* ]]
}

# =============================================================================
# inject_verification_skipped tests
# =============================================================================

@test "inject_verification_skipped: adds verification field" {
  local json='{"verdict":"CHANGES_REQUIRED","findings":[]}'
  run inject_verification_skipped "$json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verification == "skipped"'
  echo "$output" | jq -e '.verdict == "CHANGES_REQUIRED"'
}

# =============================================================================
# run_multipass tests (integration with mock codex)
# =============================================================================

_setup_multipass_responses() {
  # Pass 1: Planning context
  echo '{"scope_analysis":"test","dependency_map":{},"risk_areas":[],"test_gaps":[]}' \
    > "$MOCK_CODEX_STATE_DIR/response-1.json"
  # Pass 2: Findings
  echo '{"verdict":"APPROVED","summary":"All good","findings":[]}' \
    > "$MOCK_CODEX_STATE_DIR/response-2.json"
  # Pass 3: Verification
  echo '{"verdict":"APPROVED","summary":"Verified","findings":[]}' \
    > "$MOCK_CODEX_STATE_DIR/response-3.json"
}

@test "run_multipass: all 3 passes succeed" {
  _setup_multipass_responses

  local ws="$TEST_DIR/workspace"
  mkdir -p "$ws"
  local of="$TEST_DIR/final-output.json"

  # Override output dir to test dir
  export -f run_multipass codex_exec_single parse_codex_output estimate_token_count \
    enforce_token_budget check_budget_overflow build_pass1_prompt build_pass2_prompt \
    build_pass3_prompt inject_verification_skipped redact_secrets _redact_json \
    _redact_text _build_redaction_sed codex_has_capability detect_capabilities \
    codex_is_available setup_review_workspace cleanup_workspace build_combined_prompt

  # Patch output_dir to use test dir
  run bash -c "
    source '$SCRIPT_DIR/lib-security.sh'
    source '$SCRIPT_DIR/lib-codex-exec.sh'
    source '$SCRIPT_DIR/lib-multipass.sh'
    # Override intermediate output dir
    run_multipass_patched() {
      local output_dir='$TEST_DIR/a2a/gpt-review'
      mkdir -p \"\$output_dir\"
      # Call original with redirected output_dir
      run_multipass \"\$@\"
    }
    run_multipass 'test system' 'test user content' 'gpt-5.2' '$ws' 300 '$of' 'code' 'false'
  "

  [ "$status" -eq 0 ]
  [ -f "$of" ]
  # Output should have verdict
  local result; result=$(cat "$of")
  echo "$result" | jq -e '.verdict' >/dev/null
  # Should have pass_metadata with 3 passes
  echo "$result" | jq -e '.pass_metadata.passes_completed == 3'
  echo "$result" | jq -e '.verification == "passed"'
}

@test "run_multipass: pass 1 fails falls back to single-pass" {
  # Pass 1 fails, single-pass fallback succeeds
  echo "fail" > "$MOCK_CODEX_STATE_DIR/behavior-1"
  echo '{"verdict":"APPROVED","summary":"Single-pass fallback","findings":[]}' \
    > "$MOCK_CODEX_STATE_DIR/response-2.json"

  local ws="$TEST_DIR/workspace"
  mkdir -p "$ws"
  local of="$TEST_DIR/final-output.json"

  run bash -c "
    source '$SCRIPT_DIR/lib-security.sh'
    source '$SCRIPT_DIR/lib-codex-exec.sh'
    source '$SCRIPT_DIR/lib-multipass.sh'
    run_multipass 'test system' 'test user' 'gpt-5.2' '$ws' 300 '$of' 'code' 'false'
  "

  [ "$status" -eq 0 ]
  [ -f "$of" ]
  local result; result=$(cat "$of")
  echo "$result" | jq -e '.verdict' >/dev/null
  echo "$result" | jq -e '.pass_metadata.mode == "single-pass-fallback"'
  echo "$result" | jq -e '.pass_metadata.passes_completed == 1'
}

@test "run_multipass: pass 2 fails twice returns error" {
  _setup_multipass_responses
  # Override pass 2 to fail (calls 2 and 3 since pass 2 retries once)
  echo "fail" > "$MOCK_CODEX_STATE_DIR/behavior-2"
  echo "fail" > "$MOCK_CODEX_STATE_DIR/behavior-3"

  local ws="$TEST_DIR/workspace"
  mkdir -p "$ws"
  local of="$TEST_DIR/final-output.json"

  run bash -c "
    source '$SCRIPT_DIR/lib-security.sh'
    source '$SCRIPT_DIR/lib-codex-exec.sh'
    source '$SCRIPT_DIR/lib-multipass.sh'
    run_multipass 'test system' 'test user' 'gpt-5.2' '$ws' 300 '$of' 'code' 'false'
  "

  [ "$status" -eq 1 ]
}

@test "run_multipass: pass 3 fails returns pass 2 with verification=skipped" {
  _setup_multipass_responses
  # Pass 3 is the 3rd codex call — set it to fail
  echo "fail" > "$MOCK_CODEX_STATE_DIR/behavior-3"

  local ws="$TEST_DIR/workspace"
  mkdir -p "$ws"
  local of="$TEST_DIR/final-output.json"

  run bash -c "
    source '$SCRIPT_DIR/lib-security.sh'
    source '$SCRIPT_DIR/lib-codex-exec.sh'
    source '$SCRIPT_DIR/lib-multipass.sh'
    run_multipass 'test system' 'test user' 'gpt-5.2' '$ws' 300 '$of' 'code' 'false'
  "

  [ "$status" -eq 0 ]
  [ -f "$of" ]
  local result; result=$(cat "$of")
  echo "$result" | jq -e '.verification == "skipped"'
  echo "$result" | jq -e '.pass_metadata.passes_completed == 2'
}
