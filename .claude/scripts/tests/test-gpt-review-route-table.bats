#!/usr/bin/env bats
# test-gpt-review-route-table.bats — Tests for declarative route table (cycle-034)
# Run: bats .claude/scripts/tests/test-gpt-review-route-table.bats
#
# NOTE: Bash associative arrays (declare -A) cannot survive subshells.
# ALL functions that use registries must redirect to files, not $().
#
# Covers:
#   Task 1.8: Golden tests for backend selection sequences (7 tests)
#   Task 1.9: Route table parser tests (9 tests)
#   Task 1.10: Adversarial YAML security tests (6 tests)
#   Task 1.4: Result contract tests (7 tests)

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"
FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures/gpt-review"
ROUTE_CONFIGS_DIR="$FIXTURES_DIR/route-configs"

# =============================================================================
# Setup / Teardown
# =============================================================================

setup() {
  TEST_DIR=$(mktemp -d)
  export OPENAI_API_KEY="sk-test-key-for-testing"
  export TMPDIR="$TEST_DIR"
  export CONFIG_FILE="$TEST_DIR/.loa.config.yaml"

  # Reset double-source guards
  unset _LIB_ROUTE_TABLE_LOADED
  unset _LIB_CURL_FALLBACK_LOADED
  unset _LIB_CODEX_EXEC_LOADED
  unset _LIB_MULTIPASS_LOADED
  unset _LIB_SECURITY_LOADED

  # Track which backends were called (for golden tests)
  export MOCK_BACKEND_LOG="$TEST_DIR/backend-calls.log"
  touch "$MOCK_BACKEND_LOG"

  # Output capture files (avoid subshells that lose assoc arrays)
  export OUT_FILE="$TEST_DIR/stdout.txt"
  export ERR_FILE="$TEST_DIR/stderr.txt"

  # Minimal config
  cat > "$CONFIG_FILE" << 'YAML'
gpt_review:
  enabled: true
hounfour:
  flatline_routing: false
YAML

  # Mock model-invoke (non-executable by default)
  export MODEL_INVOKE="$TEST_DIR/mock-model-invoke"

  # Provide stub functions for dependencies before sourcing
  log() { echo "[gpt-review-api] $*" >&2; }
  error() { echo "ERROR: $*" >&2; }

  # Mock codex functions
  codex_is_available() { return 1; }
  is_flatline_routing_enabled() { return 1; }
  call_api_via_model_invoke() { return 1; }
  call_api() { return 1; }
  setup_review_workspace() { echo "$TEST_DIR"; }
  cleanup_workspace() { true; }
  run_multipass() { return 1; }
  codex_exec_single() { return 1; }
  parse_codex_output() { return 1; }

  # Source only lib-route-table.sh (dependencies mocked above)
  source "$SCRIPT_DIR/lib-route-table.sh"

  # IMPORTANT: declare -A inside the sourced file creates function-local
  # variables (because setup() is a function). Re-declare with -g so the
  # associative arrays survive into the test body.
  declare -gA _CONDITION_REGISTRY=()
  declare -gA _BACKEND_REGISTRY=()
}

teardown() {
  rm -rf "$TEST_DIR"
}

# =============================================================================
# Helpers
# =============================================================================

_setup_mock_backends() {
  _backend_hounfour() {
    echo "hounfour" >> "$MOCK_BACKEND_LOG"
    if [[ "${MOCK_HOUNFOUR_RESULT:-fail}" == "success" ]]; then
      echo '{"verdict":"APPROVED","summary":"hounfour review","findings":[]}'
      return 0
    fi
    return 1
  }

  _backend_codex() {
    echo "codex" >> "$MOCK_BACKEND_LOG"
    if [[ "${MOCK_CODEX_RESULT:-fail}" == "success" ]]; then
      echo '{"verdict":"APPROVED","summary":"codex review","findings":[]}'
      return 0
    fi
    return 1
  }

  _backend_curl() {
    echo "curl" >> "$MOCK_BACKEND_LOG"
    if [[ "${MOCK_CURL_RESULT:-fail}" == "success" ]]; then
      echo '{"verdict":"CHANGES_REQUIRED","summary":"curl review","findings":[]}'
      return 0
    fi
    return 1
  }

  register_builtin_backends
}

_setup_all_conditions_true() {
  _cond_always() { return 0; }
  _cond_flatline_routing_enabled() { return 0; }
  _cond_model_invoke_available() { return 0; }
  _cond_codex_available() { return 0; }
  register_builtin_conditions
}

_get_backend_sequence() {
  cat "$MOCK_BACKEND_LOG" | tr '\n' ',' | sed 's/,$//'
}

# =============================================================================
# Task 1.8: Golden Tests for Backend Selection Sequences (7 tests)
# =============================================================================

@test "golden: all backends available — hounfour wins" {
  _setup_mock_backends
  _setup_all_conditions_true
  _rt_load_defaults
  export MOCK_HOUNFOUR_RESULT="success"
  export MOCK_CODEX_RESULT="success"
  export MOCK_CURL_RESULT="success"

  local status=0
  execute_route_table "model" "sys" "usr" "300" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 0 ]
  [[ "$(cat "$OUT_FILE")" == *'"verdict":"APPROVED"'* ]]
  [ "$(_get_backend_sequence)" = "hounfour" ]
}

@test "golden: hounfour fails — codex wins" {
  _setup_mock_backends
  _setup_all_conditions_true
  _rt_load_defaults
  export MOCK_HOUNFOUR_RESULT="fail"
  export MOCK_CODEX_RESULT="success"
  export MOCK_CURL_RESULT="success"

  local status=0
  execute_route_table "model" "sys" "usr" "300" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 0 ]
  [ "$(_get_backend_sequence)" = "hounfour,codex" ]
}

@test "golden: full cascade — hounfour fail, codex fail, curl wins" {
  _setup_mock_backends
  _setup_all_conditions_true
  _rt_load_defaults
  export MOCK_HOUNFOUR_RESULT="fail"
  export MOCK_CODEX_RESULT="fail"
  export MOCK_CURL_RESULT="success"

  local status=0
  execute_route_table "model" "sys" "usr" "300" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 0 ]
  [ "$(_get_backend_sequence)" = "hounfour,codex,curl" ]
}

@test "golden: curl-only mode — only curl tried" {
  _setup_mock_backends
  _setup_all_conditions_true
  _rt_load_defaults
  _rt_apply_execution_mode "curl"
  export MOCK_CURL_RESULT="success"

  local status=0
  execute_route_table "model" "sys" "usr" "300" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 0 ]
  [ "$(_get_backend_sequence)" = "curl" ]
}

@test "golden: codex hard_fail stops cascade" {
  _setup_mock_backends
  _setup_all_conditions_true
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()
  _rt_append_route "codex" "always" "" "hard_fail" "" "0"
  _rt_append_route "curl" "always" "" "hard_fail" "" "0"
  export MOCK_CODEX_RESULT="fail"
  export MOCK_CURL_RESULT="success"

  local status=0
  execute_route_table "model" "sys" "usr" "300" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  # hard_fail propagates backend's exit code (non-zero), NOT always 2
  [ "$status" -ne 0 ]
  [ "$(_get_backend_sequence)" = "codex" ]
}

@test "golden: invalid JSON from backend triggers fallthrough" {
  _setup_all_conditions_true

  _backend_hounfour() {
    echo "hounfour" >> "$MOCK_BACKEND_LOG"
    echo "not valid json at all"
    return 0
  }
  _backend_curl() {
    echo "curl" >> "$MOCK_BACKEND_LOG"
    echo '{"verdict":"APPROVED","summary":"curl review","findings":[]}'
    return 0
  }
  register_builtin_backends
  _rt_load_defaults

  local status=0
  execute_route_table "model" "sys" "usr" "300" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 0 ]
  local seq="$(_get_backend_sequence)"
  [[ "$seq" == *"hounfour"* ]]
  [[ "$seq" == *"curl"* ]]
}

@test "golden: empty route table — exits 2" {
  _setup_mock_backends
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()

  local status=0
  execute_route_table "model" "sys" "usr" "300" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 2 ]
  [ "$(_get_backend_sequence)" = "" ]
}

# =============================================================================
# Task 1.9: Route Table Parser Tests (9 tests)
# =============================================================================

@test "parser: valid 3-route config parsed correctly" {
  register_builtin_conditions
  register_builtin_backends
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()

  parse_route_table "$ROUTE_CONFIGS_DIR/valid-3-routes.yaml"
  [ ${#_RT_BACKENDS[@]} -eq 3 ]
  [ "${_RT_BACKENDS[0]}" = "hounfour" ]
  [ "${_RT_BACKENDS[1]}" = "codex" ]
  [ "${_RT_BACKENDS[2]}" = "curl" ]
  [ "${_RT_FAIL_MODES[2]}" = "hard_fail" ]
}

@test "parser: empty routes falls back to defaults" {
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()

  parse_route_table "$ROUTE_CONFIGS_DIR/empty-routes.yaml"
  [ ${#_RT_BACKENDS[@]} -eq 3 ]
  [ "${_RT_BACKENDS[0]}" = "hounfour" ]
}

@test "parser: unknown backend rejected in validation (custom)" {
  register_builtin_conditions
  register_builtin_backends
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()

  parse_route_table "$ROUTE_CONFIGS_DIR/unknown-backend.yaml"
  local status=0
  validate_route_table "true" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 2 ]
}

@test "parser: unknown condition rejected in validation (custom)" {
  register_builtin_conditions
  register_builtin_backends
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()

  parse_route_table "$ROUTE_CONFIGS_DIR/unknown-condition.yaml"
  local status=0
  validate_route_table "true" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 2 ]
}

@test "parser: schema v2 rejected" {
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()

  local status=0
  parse_route_table "$ROUTE_CONFIGS_DIR/schema-v2.yaml" 2>/dev/null || status=$?
  [ "$status" -eq 2 ]
}

@test "parser: max routes exceeded rejected" {
  register_builtin_conditions
  register_builtin_backends
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()

  parse_route_table "$ROUTE_CONFIGS_DIR/max-routes-exceeded.yaml"
  local status=0
  validate_route_table "true" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 2 ]
}

@test "parser: missing when is valid (unconditional match)" {
  # Missing 'when' or 'when: []' both produce empty conditions = unconditional match
  # This is intentional: custom routes should support unconditional backends
  register_builtin_conditions
  register_builtin_backends
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()

  parse_route_table "$ROUTE_CONFIGS_DIR/missing-when.yaml"
  local status=0
  validate_route_table "true" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 0 ]
}

@test "parser: invalid fail_mode rejected in validation (custom)" {
  register_builtin_conditions
  register_builtin_backends
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()

  parse_route_table "$ROUTE_CONFIGS_DIR/invalid-fail-mode.yaml"
  local status=0
  validate_route_table "true" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 2 ]
}

@test "parser: duplicate backend is valid (not an error)" {
  register_builtin_conditions
  register_builtin_backends
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()

  parse_route_table "$ROUTE_CONFIGS_DIR/duplicate-backend.yaml"
  local status=0
  validate_route_table "true" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 0 ]
  [ ${#_RT_BACKENDS[@]} -eq 2 ]
  [ "${_RT_BACKENDS[0]}" = "curl" ]
  [ "${_RT_BACKENDS[1]}" = "curl" ]
}

# =============================================================================
# Task 1.10: Adversarial YAML Security Tests (6 tests)
# =============================================================================

@test "adversarial: shell injection in backend name rejected" {
  register_builtin_conditions
  register_builtin_backends
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()

  parse_route_table "$ROUTE_CONFIGS_DIR/adversarial-shell-injection.yaml"
  local status=0
  validate_route_table "true" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 2 ]
  [[ "$(cat "$ERR_FILE")" == *"unknown backend"* ]]
}

@test "adversarial: command substitution in condition name rejected" {
  register_builtin_conditions
  register_builtin_backends
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()

  parse_route_table "$ROUTE_CONFIGS_DIR/adversarial-command-sub.yaml"
  local status=0
  validate_route_table "true" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 2 ]
  [[ "$(cat "$ERR_FILE")" == *"unknown condition"* ]]
}

@test "adversarial: extreme timeout clamped to 600" {
  register_builtin_conditions
  register_builtin_backends
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()

  parse_route_table "$ROUTE_CONFIGS_DIR/adversarial-extreme-values.yaml"
  [ "${_RT_TIMEOUTS[0]}" = "600" ]
}

@test "adversarial: extreme retries clamped to 5" {
  register_builtin_conditions
  register_builtin_backends
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()

  parse_route_table "$ROUTE_CONFIGS_DIR/adversarial-extreme-values.yaml"
  [ "${_RT_RETRIES[0]}" = "5" ]
}

@test "adversarial: YAML anchors handled safely" {
  register_builtin_conditions
  register_builtin_backends
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()

  parse_route_table "$ROUTE_CONFIGS_DIR/adversarial-yaml-anchors.yaml"
  local status=0
  validate_route_table "true" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 0 ]
  [ "${_RT_BACKENDS[0]}" = "curl" ]
}

@test "adversarial: multiline backend name rejected" {
  register_builtin_conditions
  register_builtin_backends
  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()

  parse_route_table "$ROUTE_CONFIGS_DIR/adversarial-multiline.yaml"
  local status=0
  validate_route_table "true" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 2 ]
  [[ "$(cat "$ERR_FILE")" == *"unknown backend"* ]]
}

# =============================================================================
# Task 1.4: Result Contract Tests (7 tests)
# =============================================================================

@test "result contract: valid APPROVED accepted" {
  local status=0
  validate_review_result '{"verdict":"APPROVED","summary":"all good","findings":[]}' 2>/dev/null || status=$?
  [ "$status" -eq 0 ]
}

@test "result contract: valid CHANGES_REQUIRED accepted" {
  local status=0
  validate_review_result '{"verdict":"CHANGES_REQUIRED","summary":"needs work","findings":[{"id":"F1","severity":"HIGH"}]}' 2>/dev/null || status=$?
  [ "$status" -eq 0 ]
}

@test "result contract: missing verdict rejected" {
  local status=0
  validate_review_result '{"summary":"no verdict here","findings":[]}' 2>/dev/null || status=$?
  [ "$status" -eq 1 ]
}

@test "result contract: invalid verdict rejected" {
  local status=0
  validate_review_result '{"verdict":"MAYBE","summary":"uncertain"}' 2>/dev/null || status=$?
  [ "$status" -eq 1 ]
}

@test "result contract: too short response rejected" {
  local status=0
  validate_review_result '{"verdict":"OK"}' 2>/dev/null || status=$?
  [ "$status" -eq 1 ]
}

@test "result contract: invalid JSON rejected" {
  local status=0
  validate_review_result 'not json at all {broken' 2>/dev/null || status=$?
  [ "$status" -eq 1 ]
}

@test "result contract: findings not array rejected" {
  local status=0
  validate_review_result '{"verdict":"APPROVED","summary":"test verdict ok","findings":"not an array"}' 2>/dev/null || status=$?
  [ "$status" -eq 1 ]
}

# =============================================================================
# Additional: Array safety, execution mode, condition, utility tests
# =============================================================================

@test "array safety: _rt_validate_array_lengths passes for valid table" {
  _rt_load_defaults
  local status=0
  _rt_validate_array_lengths 2>/dev/null || status=$?
  [ "$status" -eq 0 ]
}

@test "array safety: _rt_validate_array_lengths fails on desync" {
  _rt_load_defaults
  _RT_BACKENDS+=("extra")
  local status=0
  _rt_validate_array_lengths 2>/dev/null || status=$?
  [ "$status" -eq 1 ]
}

@test "execution mode: curl filter keeps only curl" {
  _rt_load_defaults
  _rt_apply_execution_mode "curl"
  [ ${#_RT_BACKENDS[@]} -eq 1 ]
  [ "${_RT_BACKENDS[0]}" = "curl" ]
  [ "${_RT_FAIL_MODES[0]}" = "hard_fail" ]
}

@test "execution mode: codex filter keeps codex and curl" {
  _rt_load_defaults
  _rt_apply_execution_mode "codex"
  [ ${#_RT_BACKENDS[@]} -eq 2 ]
  [ "${_RT_BACKENDS[0]}" = "codex" ]
  [ "${_RT_BACKENDS[1]}" = "curl" ]
  [ "${_RT_FAIL_MODES[0]}" = "hard_fail" ]
}

@test "execution mode: auto leaves table unmodified" {
  _rt_load_defaults
  local before=${#_RT_BACKENDS[@]}
  _rt_apply_execution_mode "auto"
  [ ${#_RT_BACKENDS[@]} -eq $before ]
}

@test "defaults: load_defaults produces 3-route cascade" {
  _rt_load_defaults
  [ ${#_RT_BACKENDS[@]} -eq 3 ]
  [ "${_RT_BACKENDS[0]}" = "hounfour" ]
  [ "${_RT_BACKENDS[1]}" = "codex" ]
  [ "${_RT_BACKENDS[2]}" = "curl" ]
  [ "${_RT_FAIL_MODES[0]}" = "fallthrough" ]
  [ "${_RT_FAIL_MODES[1]}" = "fallthrough" ]
  [ "${_RT_FAIL_MODES[2]}" = "hard_fail" ]
}

@test "conditions: _evaluate_conditions with whitespace trimming" {
  register_builtin_conditions
  local status=0
  _evaluate_conditions "always , always" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 0 ]
}

@test "conditions: _evaluate_conditions rejects empty tokens gracefully" {
  register_builtin_conditions
  local status=0
  _evaluate_conditions ",always" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 0 ]
}

@test "conditions: unknown condition evaluates as false" {
  register_builtin_conditions
  local status=0
  _evaluate_conditions "nonexistent_condition" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 1 ]
}

@test "clamp: _rt_clamp enforces bounds" {
  [ "$(_rt_clamp 0 1 600)" = "1" ]
  [ "$(_rt_clamp 300 1 600)" = "300" ]
  [ "$(_rt_clamp 999 1 600)" = "600" ]
  [ "$(_rt_clamp "abc" 1 600)" = "1" ]
}

@test "log: log_route_table emits hash" {
  _rt_load_defaults
  log_route_table > "$OUT_FILE" 2>"$ERR_FILE"
  [[ "$(cat "$ERR_FILE")" == *"sha256:"* ]]
  [[ "$(cat "$ERR_FILE")" == *"effective routes:"* ]]
}

@test "init: init_route_table loads defaults without config routes" {
  register_builtin_conditions
  register_builtin_backends
  local status=0
  init_route_table "$CONFIG_FILE" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 0 ]
  [ ${#_RT_BACKENDS[@]} -eq 3 ]
}

# =============================================================================
# CI Policy Constraints (cycle-034, Task 3.4)
# =============================================================================

@test "CI policy: custom routes without LOA_CUSTOM_ROUTES=1 fall back to defaults" {
  register_builtin_conditions
  register_builtin_backends

  # Write custom routes config
  cat > "$CONFIG_FILE" << 'YAML'
gpt_review:
  route_schema: 1
  routes:
    - backend: curl
      when: []
      fail_mode: hard_fail
YAML

  export CI="true"
  unset LOA_CUSTOM_ROUTES

  local status=0
  init_route_table "$CONFIG_FILE" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 0 ]
  # Should fall back to 3 default routes (not the 1 custom route)
  [ ${#_RT_BACKENDS[@]} -eq 3 ]
  unset CI
}

@test "CI policy: custom routes with LOA_CUSTOM_ROUTES=1 are accepted" {
  register_builtin_conditions
  register_builtin_backends

  cat > "$CONFIG_FILE" << 'YAML'
gpt_review:
  route_schema: 1
  routes:
    - backend: curl
      when: []
      fail_mode: hard_fail
YAML

  export CI="true"
  export LOA_CUSTOM_ROUTES="1"

  local status=0
  init_route_table "$CONFIG_FILE" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 0 ]
  # Should use the 1 custom route
  [ ${#_RT_BACKENDS[@]} -eq 1 ]
  [ "${_RT_BACKENDS[0]}" = "curl" ]
  unset CI LOA_CUSTOM_ROUTES
}

@test "global max attempts: stops after _RT_MAX_TOTAL_ATTEMPTS" {
  _RT_MAX_TOTAL_ATTEMPTS=2
  _setup_all_conditions_true

  _backend_curl() {
    echo "curl" >> "$MOCK_BACKEND_LOG"
    return 1
  }
  register_builtin_backends

  _RT_BACKENDS=(); _RT_CONDITIONS=(); _RT_CAPABILITIES=()
  _RT_FAIL_MODES=(); _RT_TIMEOUTS=(); _RT_RETRIES=()
  _rt_append_route "curl" "always" "" "fallthrough" "" "1"
  _rt_append_route "curl" "always" "" "hard_fail" "" "1"

  local status=0
  execute_route_table "model" "sys" "usr" "300" > "$OUT_FILE" 2>"$ERR_FILE" || status=$?
  [ "$status" -eq 2 ]
  local calls
  calls=$(wc -l < "$MOCK_BACKEND_LOG")
  [ "$calls" -le 2 ]
}
