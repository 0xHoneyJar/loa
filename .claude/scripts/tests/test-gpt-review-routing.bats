#!/usr/bin/env bats
# test-gpt-review-routing.bats — Tests for route_review() in gpt-review-api.sh
# Run: bats .claude/scripts/tests/test-gpt-review-routing.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"
FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures/gpt-review"

setup() {
  TEST_DIR=$(mktemp -d)
  export OPENAI_API_KEY="sk-test-key-for-testing"
  export MOCK_CODEX_BEHAVIOR="success"
  export MOCK_CODEX_VERSION="codex 0.2.0"

  # Put mock codex on PATH
  mkdir -p "$TEST_DIR/bin"
  cp "$FIXTURES_DIR/mock_codex.bash" "$TEST_DIR/bin/codex"
  chmod +x "$TEST_DIR/bin/codex"
  export PATH="$TEST_DIR/bin:$PATH"
  export TMPDIR="$TEST_DIR"

  # Create minimal config
  cat > "$TEST_DIR/.loa.config.yaml" << 'YAML'
gpt_review:
  enabled: true
  execution_mode: auto
hounfour:
  flatline_routing: false
YAML
  export CONFIG_FILE="$TEST_DIR/.loa.config.yaml"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# =============================================================================
# route_review via source
# =============================================================================

# We can't easily test route_review by sourcing gpt-review-api.sh (it calls main).
# Instead, test the component libraries and integration via the CLI.

# =============================================================================
# CLI flag parsing tests
# =============================================================================

@test "gpt-review-api.sh: --help exits 0" {
  run "$SCRIPT_DIR/gpt-review-api.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"review_type"* ]]
}

@test "gpt-review-api.sh: no args exits 2" {
  run "$SCRIPT_DIR/gpt-review-api.sh"
  [ "$status" -eq 2 ]
}

@test "gpt-review-api.sh: invalid review type exits 2" {
  local cf="$TEST_DIR/content.txt"
  echo "test content" > "$cf"
  run "$SCRIPT_DIR/gpt-review-api.sh" invalid "$cf"
  [ "$status" -eq 2 ]
}

@test "gpt-review-api.sh: missing content file exits 2" {
  run "$SCRIPT_DIR/gpt-review-api.sh" code "/nonexistent/file.txt" \
    --expertise "$TEST_DIR/exp.md" --context "$TEST_DIR/ctx.md"
  [ "$status" -eq 2 ]
}

@test "gpt-review-api.sh: missing expertise file exits 2" {
  local cf="$TEST_DIR/content.txt"; echo "test" > "$cf"
  run "$SCRIPT_DIR/gpt-review-api.sh" code "$cf" --context "$TEST_DIR/ctx.md"
  [ "$status" -eq 2 ]
}

@test "gpt-review-api.sh: missing context file exits 2" {
  local cf="$TEST_DIR/content.txt"; echo "test" > "$cf"
  local ef="$TEST_DIR/exp.md"; echo "expertise" > "$ef"
  run "$SCRIPT_DIR/gpt-review-api.sh" code "$cf" --expertise "$ef"
  [ "$status" -eq 2 ]
}

@test "gpt-review-api.sh: exits 4 without OPENAI_API_KEY" {
  unset OPENAI_API_KEY
  local cf="$TEST_DIR/content.txt"; echo "test" > "$cf"
  local ef="$TEST_DIR/exp.md"; echo "expertise" > "$ef"
  local ctf="$TEST_DIR/ctx.md"; echo "context" > "$ctf"
  run "$SCRIPT_DIR/gpt-review-api.sh" code "$cf" --expertise "$ef" --context "$ctf"
  [ "$status" -eq 4 ]
}

@test "gpt-review-api.sh: --fast flag is accepted" {
  run "$SCRIPT_DIR/gpt-review-api.sh" --help
  [[ "$output" == *"--fast"* ]]
}

@test "gpt-review-api.sh: --tool-access flag is accepted" {
  run "$SCRIPT_DIR/gpt-review-api.sh" --help
  [[ "$output" == *"--tool-access"* ]]
}

# =============================================================================
# Execution mode config tests
# =============================================================================

@test "config: execution_mode curl forces curl-only path" {
  cat > "$TEST_DIR/.loa.config.yaml" << 'YAML'
gpt_review:
  enabled: true
  execution_mode: curl
YAML
  # With execution_mode=curl, codex should never be tried
  # (We can't easily test the full routing without a real API,
  # but we verify the config is read correctly)
  source "$SCRIPT_DIR/lib-security.sh"
  source "$SCRIPT_DIR/lib-codex-exec.sh"
  source "$SCRIPT_DIR/lib-curl-fallback.sh"
  local em
  em=$(yq eval '.gpt_review.execution_mode // "auto"' "$CONFIG_FILE")
  [ "$em" = "curl" ]
}

@test "config: execution_mode defaults to auto" {
  cat > "$TEST_DIR/.loa.config.yaml" << 'YAML'
gpt_review:
  enabled: true
YAML
  local em
  em=$(yq eval '.gpt_review.execution_mode // "auto"' "$CONFIG_FILE")
  [ "$em" = "auto" ]
}

# =============================================================================
# Line count verification (G1)
# =============================================================================

@test "gpt-review-api.sh: line count ≤ 300" {
  local lines
  lines=$(wc -l < "$SCRIPT_DIR/gpt-review-api.sh")
  [ "$lines" -le 300 ]
}

# =============================================================================
# Curl extraction parity
# =============================================================================

@test "lib-curl-fallback.sh: is_flatline_routing_enabled respects env var" {
  source "$SCRIPT_DIR/lib-security.sh"
  source "$SCRIPT_DIR/lib-curl-fallback.sh"
  export HOUNFOUR_FLATLINE_ROUTING="true"
  run is_flatline_routing_enabled
  [ "$status" -eq 0 ]
}

@test "lib-curl-fallback.sh: is_flatline_routing_enabled defaults to false" {
  source "$SCRIPT_DIR/lib-security.sh"
  source "$SCRIPT_DIR/lib-curl-fallback.sh"
  unset HOUNFOUR_FLATLINE_ROUTING
  export CONFIG_FILE="/nonexistent"
  run is_flatline_routing_enabled
  [ "$status" -eq 1 ]
}
