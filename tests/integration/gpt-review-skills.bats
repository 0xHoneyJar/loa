#!/usr/bin/env bats
# Tests for GPT review integration
#
# The simplified architecture uses:
# - A single PostToolUse hook (gpt-review-hook.sh) for ALL Edit/Write
# - A context file managed by inject-gpt-review-gates.sh
# - No skill file or command file injection
#
# When enabled: context file created, hook outputs reminders
# When disabled: context file removed, hook silent

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    INJECT_SCRIPT="$PROJECT_ROOT/.claude/scripts/inject-gpt-review-gates.sh"
    TOGGLE_SCRIPT="$PROJECT_ROOT/.claude/scripts/gpt-review-toggle.sh"
    HOOK_SCRIPT="$PROJECT_ROOT/.claude/scripts/gpt-review-hook.sh"
    CONTEXT_FILE="$PROJECT_ROOT/.claude/context/gpt-review-active.md"
    TEMPLATE_FILE="$PROJECT_ROOT/.claude/templates/gpt-review-instructions.md.template"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures/gpt-review"

    # Create temp directory for test-specific files
    TEST_DIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"

    # Backup config if exists
    if [[ -f "$PROJECT_ROOT/.loa.config.yaml" ]]; then
        cp "$PROJECT_ROOT/.loa.config.yaml" "$TEST_DIR/config.bak"
    fi
}

teardown() {
    # Restore original config
    if [[ -f "$TEST_DIR/config.bak" ]]; then
        cp "$TEST_DIR/config.bak" "$PROJECT_ROOT/.loa.config.yaml"
    fi
    # Clean up context file
    rm -f "$CONTEXT_FILE"
}

# =============================================================================
# Script existence tests
# =============================================================================

@test "inject script exists and is executable" {
    [[ -x "$INJECT_SCRIPT" ]]
}

@test "hook script exists and is executable" {
    [[ -x "$HOOK_SCRIPT" ]]
}

@test "toggle script exists and is executable" {
    [[ -x "$TOGGLE_SCRIPT" ]]
}

@test "template file exists" {
    [[ -f "$TEMPLATE_FILE" ]]
}

# =============================================================================
# Hook registration tests
# =============================================================================

@test "single unified hook registered in settings.json" {
    grep -q "gpt-review-hook.sh" "$PROJECT_ROOT/.claude/settings.json"
}

@test "old hooks are NOT registered in settings.json" {
    ! grep -q "auto-gpt-review-hook.sh" "$PROJECT_ROOT/.claude/settings.json"
    ! grep -q "gpt-review-doc-hook.sh" "$PROJECT_ROOT/.claude/settings.json"
}

# =============================================================================
# Context file management tests
# =============================================================================

@test "inject script creates context file when enabled" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"

    run "$INJECT_SCRIPT"
    [[ "$status" -eq 0 ]]
    [[ -f "$CONTEXT_FILE" ]]

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "inject script removes context file when disabled" {
    # First enable to create file
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"
    [[ -f "$CONTEXT_FILE" ]]

    # Now disable
    cp "$FIXTURES_DIR/configs/disabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    run "$INJECT_SCRIPT"
    [[ "$status" -eq 0 ]]
    [[ ! -f "$CONTEXT_FILE" ]]

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "context file contains instructions from template" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    # Check content matches template
    diff "$TEMPLATE_FILE" "$CONTEXT_FILE"

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

# =============================================================================
# Skill file integrity tests (NO injection)
# =============================================================================

@test "skill files are NOT modified when enabled" {
    local skills_dir="$PROJECT_ROOT/.claude/skills"

    # Get checksums before
    local before_prd before_sdd before_sprint before_impl
    before_prd=$(md5 -q "$skills_dir/discovering-requirements/SKILL.md" 2>/dev/null || md5sum "$skills_dir/discovering-requirements/SKILL.md" | cut -d' ' -f1)
    before_sdd=$(md5 -q "$skills_dir/designing-architecture/SKILL.md" 2>/dev/null || md5sum "$skills_dir/designing-architecture/SKILL.md" | cut -d' ' -f1)
    before_sprint=$(md5 -q "$skills_dir/planning-sprints/SKILL.md" 2>/dev/null || md5sum "$skills_dir/planning-sprints/SKILL.md" | cut -d' ' -f1)
    before_impl=$(md5 -q "$skills_dir/implementing-tasks/SKILL.md" 2>/dev/null || md5sum "$skills_dir/implementing-tasks/SKILL.md" | cut -d' ' -f1)

    # Enable GPT review
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    # Get checksums after
    local after_prd after_sdd after_sprint after_impl
    after_prd=$(md5 -q "$skills_dir/discovering-requirements/SKILL.md" 2>/dev/null || md5sum "$skills_dir/discovering-requirements/SKILL.md" | cut -d' ' -f1)
    after_sdd=$(md5 -q "$skills_dir/designing-architecture/SKILL.md" 2>/dev/null || md5sum "$skills_dir/designing-architecture/SKILL.md" | cut -d' ' -f1)
    after_sprint=$(md5 -q "$skills_dir/planning-sprints/SKILL.md" 2>/dev/null || md5sum "$skills_dir/planning-sprints/SKILL.md" | cut -d' ' -f1)
    after_impl=$(md5 -q "$skills_dir/implementing-tasks/SKILL.md" 2>/dev/null || md5sum "$skills_dir/implementing-tasks/SKILL.md" | cut -d' ' -f1)

    # Verify no changes
    [[ "$before_prd" == "$after_prd" ]]
    [[ "$before_sdd" == "$after_sdd" ]]
    [[ "$before_sprint" == "$after_sprint" ]]
    [[ "$before_impl" == "$after_impl" ]]

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "no GPT review content in skill files" {
    local skills_dir="$PROJECT_ROOT/.claude/skills"

    ! grep -q "GPT Cross-Model Review" "$skills_dir/discovering-requirements/SKILL.md"
    ! grep -q "GPT Cross-Model Review" "$skills_dir/designing-architecture/SKILL.md"
    ! grep -q "GPT Cross-Model Review" "$skills_dir/planning-sprints/SKILL.md"
    ! grep -q "GPT Cross-Model Review" "$skills_dir/implementing-tasks/SKILL.md"
    ! grep -q "GPT REVIEW ENABLED" "$skills_dir/run-mode/SKILL.md"
}

# =============================================================================
# Hook behavior tests
# =============================================================================

@test "hook outputs STOP message when enabled" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"

    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"test.ts\"}}" | '"$HOOK_SCRIPT"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"STOP"* ]]

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "hook silent when disabled" {
    cp "$FIXTURES_DIR/configs/disabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"

    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"test.ts\"}}" | '"$HOOK_SCRIPT"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "hook includes policy for what requires review" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"

    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"test.ts\"}}" | '"$HOOK_SCRIPT"
    local context
    context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')

    [[ "$context" == *"prd.md"* ]]
    [[ "$context" == *"sdd.md"* ]]
    [[ "$context" == *"sprint.md"* ]]
    [[ "$context" == *"backend"* ]] || [[ "$context" == *"Backend"* ]]

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "hook includes policy for what to skip" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"

    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"test.ts\"}}" | '"$HOOK_SCRIPT"
    local context
    context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')

    [[ "$context" == *"typo"* ]] || [[ "$context" == *"Trivial"* ]]
    [[ "$context" == *".gitignore"* ]]

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

# =============================================================================
# Command context_files integration
# =============================================================================

@test "commands have context_files entry for gpt-review-active.md" {
    local commands_dir="$PROJECT_ROOT/.claude/commands"

    grep -q "gpt-review-active.md" "$commands_dir/plan-and-analyze.md"
    grep -q "gpt-review-active.md" "$commands_dir/architect.md"
    grep -q "gpt-review-active.md" "$commands_dir/sprint-plan.md"
    grep -q "gpt-review-active.md" "$commands_dir/implement.md"
}

@test "context_files entries are marked as not required" {
    local commands_dir="$PROJECT_ROOT/.claude/commands"

    # The entry should have required: false
    grep -A1 "gpt-review-active.md" "$commands_dir/plan-and-analyze.md" | grep -q "required: false"
}
