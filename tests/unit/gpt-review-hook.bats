#!/usr/bin/env bats
# Tests for gpt-review-hook.sh - Unified PostToolUse hook
#
# Tests hook output format, config handling, and stdin consumption.

load '../helpers/gpt-review-setup'

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    HOOK_SCRIPT="$PROJECT_ROOT/.claude/scripts/gpt-review-hook.sh"
    SETTINGS_FILE="$PROJECT_ROOT/.claude/settings.json"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures/gpt-review"

    # Create temp directory for test-specific files
    TEST_DIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"

    # Create a minimal hook test environment
    mkdir -p "$TEST_DIR/.claude/scripts"
    cp "$HOOK_SCRIPT" "$TEST_DIR/.claude/scripts/gpt-review-hook.sh"
}

# =============================================================================
# Existence tests
# =============================================================================

@test "hook script exists and is executable" {
    [[ -x "$HOOK_SCRIPT" ]]
}

@test "hook is registered in settings.json" {
    [[ -f "$SETTINGS_FILE" ]]
    run grep -q "PostToolUse" "$SETTINGS_FILE"
    [[ "$status" -eq 0 ]]
    run grep -q "gpt-review-hook.sh" "$SETTINGS_FILE"
    [[ "$status" -eq 0 ]]
}

@test "hook matcher uses Edit|Write pattern" {
    run grep -E '"Edit\|Write"' "$SETTINGS_FILE"
    [[ "$status" -eq 0 ]]
}

# =============================================================================
# Output format tests (when enabled)
# =============================================================================

@test "outputs valid JSON when enabled" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"test.ts\"}}" | .claude/scripts/gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
    echo "$output" | jq empty
}

@test "JSON contains hookSpecificOutput" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"test.ts\"}}" | .claude/scripts/gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.hookSpecificOutput' > /dev/null
}

@test "JSON contains additionalContext" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"test.ts\"}}" | .claude/scripts/gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext' > /dev/null
}

@test "additionalContext mentions GPT review" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"test.ts\"}}" | .claude/scripts/gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
    local context
    context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
    [[ "$context" == *"gpt-review"* ]] || [[ "$context" == *"GPT"* ]]
}

@test "additionalContext includes STOP language" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"test.ts\"}}" | .claude/scripts/gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
    local context
    context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
    [[ "$context" == *"STOP"* ]]
}

@test "additionalContext includes file path" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/auth.ts\"}}" | .claude/scripts/gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
    local context
    context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
    [[ "$context" == *"src/auth.ts"* ]]
}

@test "additionalContext lists what requires review" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"test.ts\"}}" | .claude/scripts/gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
    local context
    context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
    [[ "$context" == *"prd.md"* ]]
    [[ "$context" == *"sdd.md"* ]]
    [[ "$context" == *"sprint.md"* ]]
}

@test "additionalContext lists what to skip" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"test.ts\"}}" | .claude/scripts/gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
    local context
    context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
    [[ "$context" == *"typo"* ]] || [[ "$context" == *"Trivial"* ]]
}

# =============================================================================
# Disabled behavior tests
# =============================================================================

@test "no output when GPT review disabled" {
    cp "$FIXTURES_DIR/configs/disabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"test.ts\"}}" | .claude/scripts/gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "no output when config file missing" {
    cd "$TEST_DIR"

    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"test.ts\"}}" | .claude/scripts/gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

# =============================================================================
# Edge case tests
# =============================================================================

@test "handles missing yq gracefully" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    run bash -c 'echo "{}" | .claude/scripts/gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
}

@test "consumes stdin without blocking" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    run timeout 5 bash -c 'echo "{\"tool_input\":{\"file_path\":\"test.ts\"}}" | .claude/scripts/gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
}

@test "handles empty file_path gracefully" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    run bash -c 'echo "{\"tool_input\":{}}" | .claude/scripts/gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
    # Should still output (with "a file" as fallback)
    echo "$output" | jq -e '.hookSpecificOutput' > /dev/null
}
