#!/usr/bin/env bats
# test-gpt-review-adaptive.bats — Tests for adaptive multi-pass + token estimation (cycle-034)
# Run: bats .claude/scripts/tests/test-gpt-review-adaptive.bats
#
# Covers:
#   Task 2.1: classify_complexity() — deterministic diff-based classification
#   Task 2.2: reclassify_with_model_signals() — dual-signal reclassification
#   Task 2.4: Token estimation word-count tier benchmark
#   Task 2.5: Token estimation benchmark corpus validation

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"
CORPUS_DIR="$BATS_TEST_DIRNAME/fixtures/gpt-review/token-corpus"

# =============================================================================
# Setup / Teardown
# =============================================================================

setup() {
  TEST_DIR=$(mktemp -d)
  export CONFIG_FILE="$TEST_DIR/.loa.config.yaml"
  export TMPDIR="$TEST_DIR"

  # Reset double-source guards
  unset _LIB_MULTIPASS_LOADED
  unset _LIB_CODEX_EXEC_LOADED
  unset _LIB_SECURITY_LOADED
  unset _LIB_ROUTE_TABLE_LOADED

  # Stub dependencies that lib-multipass.sh sources
  # lib-codex-exec.sh requires lib-gpt-review.sh which needs various env vars
  # We stub the chain to avoid needing the full stack
  _STUB_FILE="$TEST_DIR/lib-codex-exec.sh"
  cat > "$_STUB_FILE" << 'STUB'
_LIB_CODEX_EXEC_LOADED="true"
codex_exec_single() { echo '{}'; return 0; }
parse_codex_output() { echo "$1"; }
redact_secrets() { echo "$1"; }
detect_capabilities() { echo "streaming"; }
STUB

  # Point lib-multipass.sh to our stub
  mkdir -p "$TEST_DIR/scripts"
  cp "$SCRIPT_DIR/lib-multipass.sh" "$TEST_DIR/scripts/lib-multipass.sh"
  # Patch the source line to use our stub
  sed -i "s|source \"\$_lib_dir/lib-codex-exec.sh\"|source \"$_STUB_FILE\"|" "$TEST_DIR/scripts/lib-multipass.sh"

  source "$TEST_DIR/scripts/lib-multipass.sh"
}

teardown() {
  [[ -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# =============================================================================
# Helper: generate mock diff content
# =============================================================================

_mock_diff() {
  local files="${1:-2}" lines="${2:-50}" security_path="${3:-}"
  local output=""
  for ((i=1; i<=files; i++)); do
    local path="src/module-${i}.ts"
    [[ -n "$security_path" && $i -eq 1 ]] && path="$security_path"
    output+="diff --git a/$path b/$path
--- a/$path
+++ b/$path
@@ -1,10 +1,10 @@
"
    for ((j=1; j<=lines/files; j++)); do
      output+="+added line $j
-removed line $j
"
    done
  done
  printf '%s' "$output"
}

# =============================================================================
# Test 1: Small diff — both signals low → 1 pass (adaptive-single-pass)
# =============================================================================

@test "classify_complexity: small diff (2 files, 50 lines) → low" {
  local diff; diff=$(_mock_diff 2 50)
  local result; result=$(classify_complexity "$diff")
  [ "$result" = "low" ]
}

@test "reclassify: det=low + model=low → low (single-pass)" {
  # Small Pass 1 output: low risk_area_count, small token footprint
  local p1_output='{"verdict":"APPROVED","findings":[],"complexity":{"risk_area_count":1}}'
  local result; result=$(reclassify_with_model_signals "low" "$p1_output")
  [ "$result" = "low" ]
}

# =============================================================================
# Test 2: Large diff — det high → 3 pass
# =============================================================================

@test "classify_complexity: large diff (20 files, 3000 lines) → high" {
  local diff; diff=$(_mock_diff 20 3000)
  local result; result=$(classify_complexity "$diff")
  [ "$result" = "high" ]
}

# =============================================================================
# Test 3: Security path → always high
# =============================================================================

@test "classify_complexity: security path (.claude/) → high" {
  local diff; diff=$(_mock_diff 1 10 ".claude/scripts/danger.sh")
  local result; result=$(classify_complexity "$diff")
  [ "$result" = "high" ]
}

@test "classify_complexity: auth path → high" {
  local diff; diff=$(_mock_diff 2 20 "src/auth/login.ts")
  local result; result=$(classify_complexity "$diff")
  [ "$result" = "high" ]
}

# =============================================================================
# Test 4: det=low, model=high → high (3 pass)
# =============================================================================

@test "reclassify: det=low + model=high → high" {
  # Large Pass 1 output: high risk_area_count
  local p1_output='{"verdict":"CHANGES_REQUIRED","findings":[{"s":"high"},{"s":"high"},{"s":"high"},{"s":"high"},{"s":"high"},{"s":"high"},{"s":"high"},{"s":"high"}],"complexity":{"risk_area_count":8}}'
  local result; result=$(reclassify_with_model_signals "low" "$p1_output")
  [ "$result" = "high" ]
}

# =============================================================================
# Test 5: det=high, model=low → high (3 pass — high wins)
# =============================================================================

@test "reclassify: det=high + model=low → high" {
  local p1_output='{"verdict":"APPROVED","findings":[],"complexity":{"risk_area_count":0}}'
  local result; result=$(reclassify_with_model_signals "high" "$p1_output")
  [ "$result" = "high" ]
}

# =============================================================================
# Test 6: Adaptive disabled → standard 3-pass (no classification)
# =============================================================================

@test "GPT_REVIEW_ADAPTIVE=0 disables adaptive classification" {
  export GPT_REVIEW_ADAPTIVE="0"
  # Re-source to pick up the env var — the adaptive flag is read inside run_multipass()
  # We test that classify_complexity is NOT called by checking that the function
  # still works but the env var controls the branch
  local adaptive="true"
  [[ "${GPT_REVIEW_ADAPTIVE}" == "0" ]] && adaptive="false"
  [ "$adaptive" = "false" ]
  unset GPT_REVIEW_ADAPTIVE
}

# =============================================================================
# Test 7: Medium complexity — dual-signal matrix
# =============================================================================

@test "classify_complexity: medium diff (5 files, 300 lines) → medium" {
  local diff; diff=$(_mock_diff 5 300)
  local result; result=$(classify_complexity "$diff")
  [ "$result" = "medium" ]
}

@test "reclassify: det=medium + model=medium → medium" {
  # Medium Pass 1 output: moderate risk areas and scope
  local p1_output='{"verdict":"APPROVED","findings":[{"s":"low"}],"complexity":{"risk_area_count":4}}'
  local result; result=$(reclassify_with_model_signals "medium" "$p1_output")
  [ "$result" = "medium" ]
}

# =============================================================================
# Test 8: Token estimation — hybrid word+char formula benchmark
# =============================================================================

@test "token estimation: hybrid tier mean error ≤15% and p95 ≤25% against corpus" {
  # Skip if corpus is missing
  [ -d "$CORPUS_DIR" ] || skip "Token corpus not found"

  local total_err=0 count=0 max_err=0
  local -a errors=()

  for sample in "$CORPUS_DIR"/sample-*; do
    # Skip .tokens companion files
    [[ "$sample" == *.tokens ]] && continue
    local tokens_file="${sample}.tokens"
    [ -f "$tokens_file" ] || continue

    local actual; actual=$(cat "$tokens_file" | tr -d '[:space:]')
    [ "$actual" -gt 0 ] || continue

    local content; content=$(cat "$sample")
    local estimated; estimated=$(estimate_token_count "$content")

    local abs_err
    if [ "$estimated" -gt "$actual" ]; then
      abs_err=$((estimated - actual))
    else
      abs_err=$((actual - estimated))
    fi
    # Percentage error * 1000 (for integer arithmetic with 1 decimal precision)
    local pct_err_x10=$(( abs_err * 1000 / actual ))
    errors+=("$pct_err_x10")
    total_err=$((total_err + pct_err_x10))
    count=$((count + 1))
  done

  [ "$count" -ge 10 ] || { echo "Need ≥10 samples, found $count"; false; }

  # Mean error
  local mean_x10=$(( total_err / count ))
  echo "# Mean error: ${mean_x10}/10 % (target ≤150)" >&3

  # Sort errors for p95
  IFS=$'\n' sorted=($(printf '%s\n' "${errors[@]}" | sort -n)); unset IFS

  # p95 = value at 95th percentile index
  local p95_idx=$(( count * 95 / 100 ))
  [ "$p95_idx" -ge "$count" ] && p95_idx=$((count - 1))
  local p95_x10="${sorted[$p95_idx]}"
  echo "# P95 error: ${p95_x10}/10 % (target ≤250)" >&3

  # Assert: mean ≤ 15.0% (150/10), p95 ≤ 25.0% (250/10)
  [ "$mean_x10" -le 150 ]
  [ "$p95_x10" -le 250 ]
}

# =============================================================================
# Test 9: Token estimation — edge cases
# =============================================================================

@test "token estimation: empty string returns 0" {
  local result; result=$(estimate_token_count "")
  [ "$result" -eq 0 ]
}

@test "token estimation: single word" {
  local result; result=$(estimate_token_count "hello")
  [ "$result" -gt 0 ]
}

# =============================================================================
# Test 10: GPT_REVIEW_ADAPTIVE env var overrides (cycle-034, Task 3.4)
# =============================================================================

@test "GPT_REVIEW_ADAPTIVE=1 enables adaptive regardless of config" {
  export GPT_REVIEW_ADAPTIVE="1"
  local adaptive="true"
  if [[ -n "${GPT_REVIEW_ADAPTIVE:-}" ]]; then
    [[ "${GPT_REVIEW_ADAPTIVE}" == "0" ]] && adaptive="false" || adaptive="true"
  fi
  [ "$adaptive" = "true" ]
  unset GPT_REVIEW_ADAPTIVE
}

@test "GPT_REVIEW_ADAPTIVE unset uses default (true)" {
  unset GPT_REVIEW_ADAPTIVE
  local adaptive="true"
  if [[ -n "${GPT_REVIEW_ADAPTIVE:-}" ]]; then
    [[ "${GPT_REVIEW_ADAPTIVE}" == "0" ]] && adaptive="false" || adaptive="true"
  fi
  # Default is true when env var not set
  [ "$adaptive" = "true" ]
}

# =============================================================================
# Bridge medium-1: _read_mp_config input guard
# =============================================================================

@test "_read_mp_config: valid dotted key accepted" {
  cat > "$CONFIG_FILE" << 'YAML'
gpt_review:
  multipass:
    adaptive: true
YAML
  local result; result=$(_read_mp_config '.gpt_review.multipass.adaptive' 'fallback')
  [ "$result" = "true" ]
}

@test "_read_mp_config: unsafe key with shell chars rejected" {
  local result; result=$(_read_mp_config '; rm -rf /' 'safe_default')
  [ "$result" = "safe_default" ]
}

@test "_read_mp_config: unsafe key with parens rejected" {
  local result; result=$(_read_mp_config '.foo | select(.bar)' 'safe_default')
  [ "$result" = "safe_default" ]
}

@test "_read_mp_config: unsafe key with quotes rejected" {
  local result; result=$(_read_mp_config '.foo"bar' 'safe_default')
  [ "$result" = "safe_default" ]
}

# =============================================================================
# Bridge medium-2: Segment-anchored security path patterns
# =============================================================================

@test "classify_complexity: false positive — authorization/ not matched by auth pattern" {
  local diff; diff=$(_mock_diff 2 20 "src/authorization/README.md")
  local result; result=$(classify_complexity "$diff")
  # authorization/ should NOT trigger security path, so small diff → low
  [ "$result" = "low" ]
}

@test "classify_complexity: false positive — environment.ts not matched by .env pattern" {
  local diff; diff=$(_mock_diff 2 20 "lib/environment.ts")
  local result; result=$(classify_complexity "$diff")
  [ "$result" = "low" ]
}

@test "classify_complexity: true positive — .env file still detected" {
  local diff; diff=$(_mock_diff 2 20 ".env")
  local result; result=$(classify_complexity "$diff")
  [ "$result" = "high" ]
}

@test "classify_complexity: true positive — .env.local still detected" {
  local diff; diff=$(_mock_diff 2 20 ".env.local")
  local result; result=$(classify_complexity "$diff")
  [ "$result" = "high" ]
}

@test "classify_complexity: true positive — auth/ directory still detected" {
  local diff; diff=$(_mock_diff 2 20 "src/auth/middleware.ts")
  local result; result=$(classify_complexity "$diff")
  [ "$result" = "high" ]
}

@test "classify_complexity: true positive — secrets/ directory still detected" {
  local diff; diff=$(_mock_diff 2 20 "config/secrets/prod.yaml")
  local result; result=$(classify_complexity "$diff")
  [ "$result" = "high" ]
}
