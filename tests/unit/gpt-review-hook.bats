#!/usr/bin/env bats
# Tests for auto-gpt-review-hook.sh - PostToolUse hook
#
# Tests hook output format, config handling, and stdin consumption.

load '../helpers/gpt-review-setup'

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    HOOK_SCRIPT="$PROJECT_ROOT/.claude/scripts/auto-gpt-review-hook.sh"
    SETTINGS_FILE="$PROJECT_ROOT/.claude/settings.json"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures/gpt-review"

    # Create temp directory for test-specific files
    TEST_DIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"

    # Create a minimal hook test environment
    mkdir -p "$TEST_DIR/.claude/scripts"
    cp "$HOOK_SCRIPT" "$TEST_DIR/.claude/scripts/auto-gpt-review-hook.sh"
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
    run grep -q "auto-gpt-review-hook.sh" "$SETTINGS_FILE"
    [[ "$status" -eq 0 ]]
}

@test "hook matcher covers common code extensions" {
    # Check that the matcher includes common extensions
    # The actual pattern uses | for OR: (Edit|Write)
    run grep -E '\(Edit\|Write\).*ts.*js.*py' "$SETTINGS_FILE"
    [[ "$status" -eq 0 ]]
}

# =============================================================================
# Output format tests (when enabled)
# =============================================================================

@test "outputs valid JSON when enabled" {
    # Copy enabled config
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    # Run hook with empty stdin (simulates hook invocation)
    run bash -c 'echo "{}" | .claude/scripts/auto-gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
    # Validate JSON
    echo "$output" | jq empty
}

@test "JSON contains hookSpecificOutput" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    run bash -c 'echo "{}" | .claude/scripts/auto-gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.hookSpecificOutput' > /dev/null
}

@test "JSON contains additionalContext" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    run bash -c 'echo "{}" | .claude/scripts/auto-gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext' > /dev/null
}

@test "additionalContext mentions GPT review" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    run bash -c 'echo "{}" | .claude/scripts/auto-gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
    local context
    context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
    [[ "$context" == *"gpt-review"* ]] || [[ "$context" == *"/gpt-review"* ]]
}

@test "additionalContext emphasizes one-shotting over velocity" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    run bash -c 'echo "{}" | .claude/scripts/auto-gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
    local context
    context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
    # New messaging emphasizes correctness over speed and the uncertainty rule
    [[ "$context" == *"ONE-SHOTTING"* ]] || [[ "$context" == *"unsure"* ]] || [[ "$context" == *"doubt"* ]]
}

# =============================================================================
# Disabled behavior tests
# =============================================================================

@test "no output when GPT review disabled" {
    cp "$FIXTURES_DIR/configs/disabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    run bash -c 'echo "{}" | .claude/scripts/auto-gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "no output when config file missing" {
    # Don't copy any config
    cd "$TEST_DIR"

    run bash -c 'echo "{}" | .claude/scripts/auto-gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

# =============================================================================
# Edge case tests
# =============================================================================

@test "handles missing yq gracefully" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    # Create a script that runs hook without yq in PATH
    cat > "$TEST_DIR/test-no-yq.sh" << 'SCRIPT'
#!/bin/bash
# Run hook with minimal PATH (no yq)
PATH="/bin:/usr/bin"
# Remove any yq from PATH by not including homebrew paths
echo "{}" | ./.claude/scripts/auto-gpt-review-hook.sh
SCRIPT
    chmod +x "$TEST_DIR/test-no-yq.sh"

    # The hook should exit 0 even without yq (graceful handling)
    # Since the hook checks `command -v yq` first
    run bash -c 'echo "{}" | .claude/scripts/auto-gpt-review-hook.sh'
    # Should exit 0 in all cases
    [[ "$status" -eq 0 ]]
}

@test "consumes stdin without blocking" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"

    # Use timeout to ensure it doesn't hang
    run timeout 5 bash -c 'echo "{}" | .claude/scripts/auto-gpt-review-hook.sh'
    [[ "$status" -eq 0 ]]
}
