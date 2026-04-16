#!/usr/bin/env bats
# =============================================================================
# Tests for flatline-readiness.sh — Flatline Protocol readiness check (FR-3)
# =============================================================================
# Cycle: cycle-048 (Community Feedback — Review Pipeline Hardening)
# Tests: READY, DISABLED, NO_API_KEYS, DEGRADED, GEMINI_API_KEY alias,
#        --json structure, PROJECT_ROOT override.

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local real_repo_root
    real_repo_root="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$real_repo_root/.claude/scripts/flatline-readiness.sh"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/flatline-readiness-test-$$"
    mkdir -p "$TEST_TMPDIR/.claude/scripts"

    # Pre-populate scripts so _create_test_config can copy from PROJECT_ROOT
    cp "$real_repo_root/.claude/scripts/bootstrap.sh" "$TEST_TMPDIR/.claude/scripts/"
    [[ -f "$real_repo_root/.claude/scripts/path-lib.sh" ]] && \
        cp "$real_repo_root/.claude/scripts/path-lib.sh" "$TEST_TMPDIR/.claude/scripts/"
    [[ -f "$real_repo_root/.claude/scripts/bash-version-guard.sh" ]] && \
        cp "$real_repo_root/.claude/scripts/bash-version-guard.sh" "$TEST_TMPDIR/.claude/scripts/"
    cp "$SCRIPT" "$TEST_TMPDIR/.claude/scripts/"

    # Minimal config so flatline-readiness.sh can read settings from PROJECT_ROOT
    cat > "$TEST_TMPDIR/.loa.config.yaml" << 'CONFIG'
flatline_protocol:
  enabled: true
  models:
    primary: claude-opus-4-6
    secondary: gpt-5.3-codex
CONFIG

    export PROJECT_ROOT="$TEST_TMPDIR"

    # Save original env vars so we can restore in teardown
    _ORIG_ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
    _ORIG_OPENAI_API_KEY="${OPENAI_API_KEY:-}"
    _ORIG_GOOGLE_API_KEY="${GOOGLE_API_KEY:-}"
    _ORIG_GEMINI_API_KEY="${GEMINI_API_KEY:-}"

    # Default: all keys unset (tests set what they need)
    unset ANTHROPIC_API_KEY
    unset OPENAI_API_KEY
    unset GOOGLE_API_KEY
    unset GEMINI_API_KEY
}

teardown() {
    # Restore original env vars
    if [[ -n "$_ORIG_ANTHROPIC_API_KEY" ]]; then
        export ANTHROPIC_API_KEY="$_ORIG_ANTHROPIC_API_KEY"
    fi
    if [[ -n "$_ORIG_OPENAI_API_KEY" ]]; then
        export OPENAI_API_KEY="$_ORIG_OPENAI_API_KEY"
    fi
    if [[ -n "$_ORIG_GOOGLE_API_KEY" ]]; then
        export GOOGLE_API_KEY="$_ORIG_GOOGLE_API_KEY"
    fi
    if [[ -n "$_ORIG_GEMINI_API_KEY" ]]; then
        export GEMINI_API_KEY="$_ORIG_GEMINI_API_KEY"
    fi

    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# =============================================================================
# Helper: Create isolated config for testing
# =============================================================================
_create_test_config() {
    local config_dir="$TEST_TMPDIR/test-project"
    mkdir -p "$config_dir/.claude/scripts"

    # Copy the readiness script to test project
    cp "$SCRIPT" "$config_dir/.claude/scripts/"
    chmod +x "$config_dir/.claude/scripts/flatline-readiness.sh"

    # Copy bootstrap and supporting scripts
    cp "$PROJECT_ROOT/.claude/scripts/bootstrap.sh" "$config_dir/.claude/scripts/"
    if [[ -f "$PROJECT_ROOT/.claude/scripts/path-lib.sh" ]]; then
        cp "$PROJECT_ROOT/.claude/scripts/path-lib.sh" "$config_dir/.claude/scripts/"
    fi
    if [[ -f "$PROJECT_ROOT/.claude/scripts/bash-version-guard.sh" ]]; then
        cp "$PROJECT_ROOT/.claude/scripts/bash-version-guard.sh" "$config_dir/.claude/scripts/"
    fi

    # Initialize git repo (needed for bootstrap.sh PROJECT_ROOT detection)
    (cd "$config_dir" && git init -q 2>/dev/null)

    echo "$config_dir"
}

_write_config() {
    local config_dir="$1"
    local content="$2"
    echo "$content" > "$config_dir/.loa.config.yaml"
}

# =============================================================================
# READY: All 3 keys set → exit 0
# =============================================================================

@test "READY: all 3 provider keys set returns exit 0" {
    export ANTHROPIC_API_KEY="test-anthropic-key"
    export OPENAI_API_KEY="test-openai-key"
    export GOOGLE_API_KEY="test-google-key"

    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"READY"* ]]
}

@test "READY: --json returns status READY with exit_code 0" {
    export ANTHROPIC_API_KEY="test-anthropic-key"
    export OPENAI_API_KEY="test-openai-key"
    export GOOGLE_API_KEY="test-google-key"

    run "$SCRIPT" --json
    [ "$status" -eq 0 ]

    local json_status
    json_status=$(echo "$output" | jq -r '.status')
    [ "$json_status" = "READY" ]

    local json_exit
    json_exit=$(echo "$output" | jq -r '.exit_code')
    [ "$json_exit" = "0" ]
}

# =============================================================================
# DISABLED: flatline_protocol.enabled: false → exit 1
# =============================================================================

@test "DISABLED: flatline_protocol.enabled false returns exit 1" {
    local config_dir
    config_dir=$(_create_test_config)
    _write_config "$config_dir" "flatline_protocol:
  enabled: false
  models:
    primary: opus
    secondary: gpt-5.3-codex
    tertiary: gemini-2.5-pro"

    export ANTHROPIC_API_KEY="test-key"
    export PROJECT_ROOT="$config_dir"

    run "$config_dir/.claude/scripts/flatline-readiness.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"DISABLED"* ]]
}

@test "DISABLED: --json returns status DISABLED" {
    local config_dir
    config_dir=$(_create_test_config)
    _write_config "$config_dir" "flatline_protocol:
  enabled: false"

    export PROJECT_ROOT="$config_dir"

    run "$config_dir/.claude/scripts/flatline-readiness.sh" --json
    [ "$status" -eq 1 ]

    local json_status
    json_status=$(echo "$output" | jq -r '.status')
    [ "$json_status" = "DISABLED" ]
}

# =============================================================================
# NO_API_KEYS: all keys unset → exit 2
# =============================================================================

@test "NO_API_KEYS: all provider keys unset returns exit 2" {
    # All keys are already unset by setup()
    run "$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"NO_API_KEYS"* ]]
}

@test "NO_API_KEYS: --json returns status NO_API_KEYS" {
    run "$SCRIPT" --json
    [ "$status" -eq 2 ]

    local json_status
    json_status=$(echo "$output" | jq -r '.status')
    [ "$json_status" = "NO_API_KEYS" ]

    local json_exit
    json_exit=$(echo "$output" | jq -r '.exit_code')
    [ "$json_exit" = "2" ]
}

# =============================================================================
# DEGRADED: only ANTHROPIC_API_KEY set → exit 3
# =============================================================================

@test "DEGRADED: only ANTHROPIC_API_KEY set returns exit 3" {
    export ANTHROPIC_API_KEY="test-anthropic-key"

    run "$SCRIPT"
    [ "$status" -eq 3 ]
    [[ "$output" == *"DEGRADED"* ]]
}

@test "DEGRADED: --json returns status DEGRADED with recommendations" {
    export ANTHROPIC_API_KEY="test-anthropic-key"

    run "$SCRIPT" --json
    [ "$status" -eq 3 ]

    local json_status
    json_status=$(echo "$output" | jq -r '.status')
    [ "$json_status" = "DEGRADED" ]

    # Should have recommendations for missing providers
    local rec_count
    rec_count=$(echo "$output" | jq '.recommendations | length')
    [ "$rec_count" -gt 0 ]
}

@test "DEGRADED: only OPENAI_API_KEY set returns exit 3" {
    export OPENAI_API_KEY="test-openai-key"

    run "$SCRIPT"
    [ "$status" -eq 3 ]
}

# =============================================================================
# GEMINI_API_KEY alias with deprecation warning
# =============================================================================

@test "GEMINI_API_KEY alias: accepted with deprecation warning" {
    export ANTHROPIC_API_KEY="test-anthropic-key"
    export OPENAI_API_KEY="test-openai-key"
    export GEMINI_API_KEY="test-gemini-key"
    # GOOGLE_API_KEY is NOT set — alias should kick in

    run "$SCRIPT" --json
    [ "$status" -eq 0 ]

    # BATS `run` merges stdout+stderr — filter out WARNING lines before jq parse
    local json_only
    json_only=$(echo "$output" | grep -v '^WARNING:')
    local json_status
    json_status=$(echo "$json_only" | jq -r '.status')
    [ "$json_status" = "READY" ]
}

@test "GEMINI_API_KEY alias: deprecation warning on stderr" {
    export ANTHROPIC_API_KEY="test-anthropic-key"
    export OPENAI_API_KEY="test-openai-key"
    export GEMINI_API_KEY="test-gemini-key"

    # Capture stderr separately
    local stderr_output
    stderr_output=$("$SCRIPT" --json 2>&1 1>/dev/null) || true
    [[ "$stderr_output" == *"GEMINI_API_KEY is deprecated"* ]]
    [[ "$stderr_output" == *"GOOGLE_API_KEY"* ]]
}

@test "GEMINI_API_KEY alias: GOOGLE_API_KEY takes precedence (no warning)" {
    export ANTHROPIC_API_KEY="test-anthropic-key"
    export OPENAI_API_KEY="test-openai-key"
    export GOOGLE_API_KEY="test-google-key"
    export GEMINI_API_KEY="test-gemini-key"

    # With both set, GOOGLE_API_KEY should be used — no deprecation warning
    local stderr_output
    stderr_output=$("$SCRIPT" --json 2>&1 1>/dev/null) || true
    [[ "$stderr_output" != *"GEMINI_API_KEY is deprecated"* ]]
}

# =============================================================================
# --json output structure validation
# =============================================================================

@test "--json: output contains required top-level fields" {
    export ANTHROPIC_API_KEY="test-key"
    export OPENAI_API_KEY="test-key"
    export GOOGLE_API_KEY="test-key"

    run "$SCRIPT" --json
    [ "$status" -eq 0 ]

    # Validate all required fields exist
    echo "$output" | jq -e '.status' >/dev/null
    echo "$output" | jq -e '.exit_code' >/dev/null
    echo "$output" | jq -e '.providers' >/dev/null
    echo "$output" | jq -e '.models' >/dev/null
    echo "$output" | jq -e '.recommendations' >/dev/null
    echo "$output" | jq -e '.timestamp' >/dev/null
}

@test "--json: providers have correct structure" {
    export ANTHROPIC_API_KEY="test-key"
    export OPENAI_API_KEY="test-key"
    export GOOGLE_API_KEY="test-key"

    run "$SCRIPT" --json
    [ "$status" -eq 0 ]

    # Each provider should have configured, available, env_var
    echo "$output" | jq -e '.providers.anthropic.configured' >/dev/null
    echo "$output" | jq -e '.providers.anthropic.available' >/dev/null
    echo "$output" | jq -e '.providers.anthropic.env_var' >/dev/null
    echo "$output" | jq -e '.providers.openai.configured' >/dev/null
    echo "$output" | jq -e '.providers.google.configured' >/dev/null
}

@test "--json: models contain primary, secondary, tertiary" {
    export ANTHROPIC_API_KEY="test-key"
    export OPENAI_API_KEY="test-key"
    export GOOGLE_API_KEY="test-key"

    run "$SCRIPT" --json
    [ "$status" -eq 0 ]

    echo "$output" | jq -e '.models.primary' >/dev/null
    echo "$output" | jq -e '.models.secondary' >/dev/null
    echo "$output" | jq -e '.models.tertiary' >/dev/null
}

@test "--json: timestamp is ISO 8601 format" {
    export ANTHROPIC_API_KEY="test-key"
    export OPENAI_API_KEY="test-key"
    export GOOGLE_API_KEY="test-key"

    run "$SCRIPT" --json
    [ "$status" -eq 0 ]

    local ts
    ts=$(echo "$output" | jq -r '.timestamp')
    # ISO 8601: YYYY-MM-DDTHH:MM:SSZ
    [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "--json: recommendations is array" {
    export ANTHROPIC_API_KEY="test-key"

    run "$SCRIPT" --json
    [ "$status" -eq 3 ]

    local rec_type
    rec_type=$(echo "$output" | jq -r '.recommendations | type')
    [ "$rec_type" = "array" ]
}

# =============================================================================
# PROJECT_ROOT override for test isolation
# =============================================================================

@test "PROJECT_ROOT override: uses custom project root for config" {
    local config_dir
    config_dir=$(_create_test_config)
    _write_config "$config_dir" "flatline_protocol:
  enabled: true
  models:
    primary: claude-3-opus
    secondary: gpt-4o
    tertiary: gemini-2.5-pro"

    export PROJECT_ROOT="$config_dir"
    export ANTHROPIC_API_KEY="test-key"
    export OPENAI_API_KEY="test-key"
    export GOOGLE_API_KEY="test-key"

    run "$config_dir/.claude/scripts/flatline-readiness.sh" --json
    [ "$status" -eq 0 ]

    # Model names should match the custom config
    local primary
    primary=$(echo "$output" | jq -r '.models.primary')
    [ "$primary" = "claude-3-opus" ]

    local secondary
    secondary=$(echo "$output" | jq -r '.models.secondary')
    [ "$secondary" = "gpt-4o" ]
}

@test "PROJECT_ROOT override: disabled config in custom root returns DISABLED" {
    local config_dir
    config_dir=$(_create_test_config)
    _write_config "$config_dir" "flatline_protocol:
  enabled: false"

    export PROJECT_ROOT="$config_dir"
    export ANTHROPIC_API_KEY="test-key"

    run "$config_dir/.claude/scripts/flatline-readiness.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"DISABLED"* ]]
}

# =============================================================================
# --quick flag
# =============================================================================

@test "--quick: still detects READY status" {
    export ANTHROPIC_API_KEY="test-key"
    export OPENAI_API_KEY="test-key"
    export GOOGLE_API_KEY="test-key"

    run "$SCRIPT" --quick
    [ "$status" -eq 0 ]
    [[ "$output" == *"READY"* ]]
}

@test "--quick --json: returns valid JSON" {
    export ANTHROPIC_API_KEY="test-key"
    export OPENAI_API_KEY="test-key"
    export GOOGLE_API_KEY="test-key"

    run "$SCRIPT" --quick --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status' >/dev/null
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "unknown option: returns error" {
    run "$SCRIPT" --invalid
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "provider mapping: anthropic-* model maps to anthropic" {
    local config_dir
    config_dir=$(_create_test_config)
    _write_config "$config_dir" "flatline_protocol:
  enabled: true
  models:
    primary: anthropic-claude-opus
    secondary: openai-gpt-5
    tertiary: google-gemini-pro"

    export PROJECT_ROOT="$config_dir"
    export ANTHROPIC_API_KEY="test-key"
    export OPENAI_API_KEY="test-key"
    export GOOGLE_API_KEY="test-key"

    run "$config_dir/.claude/scripts/flatline-readiness.sh" --json
    [ "$status" -eq 0 ]

    local json_status
    json_status=$(echo "$output" | jq -r '.status')
    [ "$json_status" = "READY" ]
}
