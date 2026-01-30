#!/usr/bin/env bats
# Tests for GPT review skill integration
#
# Verifies that GPT review phases are dynamically injected into skill files
# based on config. When enabled: phases are injected. When disabled: removed.
# The /toggle-gpt-review command controls everything (no startup hooks needed).

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    SKILLS_DIR="$PROJECT_ROOT/.claude/skills"
    INJECT_SCRIPT="$PROJECT_ROOT/.claude/scripts/inject-gpt-review-gates.sh"
    TOGGLE_SCRIPT="$PROJECT_ROOT/.claude/scripts/gpt-review-toggle.sh"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures/gpt-review"

    # Create temp directory for test-specific files
    TEST_DIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"

    # Backup original skill files
    for skill in discovering-requirements designing-architecture planning-sprints implementing-tasks; do
        cp "$SKILLS_DIR/$skill/SKILL.md" "$TEST_DIR/${skill}-SKILL.md.bak"
    done
}

teardown() {
    # Restore original skill files
    for skill in discovering-requirements designing-architecture planning-sprints implementing-tasks; do
        if [[ -f "$TEST_DIR/${skill}-SKILL.md.bak" ]]; then
            cp "$TEST_DIR/${skill}-SKILL.md.bak" "$SKILLS_DIR/$skill/SKILL.md"
        fi
    done
}

# =============================================================================
# Inject script tests
# =============================================================================

@test "inject script exists and is executable" {
    [[ -x "$INJECT_SCRIPT" ]]
}

@test "inject script adds GPT review phase when enabled" {
    # Setup: copy enabled config to project root
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"

    # Run inject
    run "$INJECT_SCRIPT"
    [[ "$status" -eq 0 ]]

    # Check GPT review phases were added (look for the phase header)
    grep -q "GPT Cross-Model Review" "$SKILLS_DIR/discovering-requirements/SKILL.md"
    grep -q "GPT Cross-Model Review" "$SKILLS_DIR/designing-architecture/SKILL.md"
    grep -q "GPT Cross-Model Review" "$SKILLS_DIR/planning-sprints/SKILL.md"
    grep -q "GPT Cross-Model Review" "$SKILLS_DIR/implementing-tasks/SKILL.md"

    # Cleanup
    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "inject script removes GPT review phase when disabled" {
    # Setup: first add phases
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    # Verify phases exist
    grep -q "GPT Cross-Model Review" "$SKILLS_DIR/discovering-requirements/SKILL.md"

    # Now disable
    cp "$FIXTURES_DIR/configs/disabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    run "$INJECT_SCRIPT"
    [[ "$status" -eq 0 ]]

    # Check phases were removed
    ! grep -q "GPT Cross-Model Review" "$SKILLS_DIR/discovering-requirements/SKILL.md"
    ! grep -q "GPT Cross-Model Review" "$SKILLS_DIR/designing-architecture/SKILL.md"
    ! grep -q "GPT Cross-Model Review" "$SKILLS_DIR/planning-sprints/SKILL.md"
    ! grep -q "GPT Cross-Model Review" "$SKILLS_DIR/implementing-tasks/SKILL.md"

    # Cleanup
    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "skill files are IDENTICAL to original after phase removal" {
    # Store checksums of original files
    local orig_prd_checksum orig_sdd_checksum orig_sprint_checksum orig_impl_checksum
    orig_prd_checksum=$(md5 -q "$TEST_DIR/discovering-requirements-SKILL.md.bak")
    orig_sdd_checksum=$(md5 -q "$TEST_DIR/designing-architecture-SKILL.md.bak")
    orig_sprint_checksum=$(md5 -q "$TEST_DIR/planning-sprints-SKILL.md.bak")
    orig_impl_checksum=$(md5 -q "$TEST_DIR/implementing-tasks-SKILL.md.bak")

    # Add phases
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    # Verify phases were added
    grep -q "GPT Cross-Model Review" "$SKILLS_DIR/discovering-requirements/SKILL.md"

    # Remove phases
    cp "$FIXTURES_DIR/configs/disabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    # Verify files are IDENTICAL to originals (byte-for-byte)
    local new_prd_checksum new_sdd_checksum new_sprint_checksum new_impl_checksum
    new_prd_checksum=$(md5 -q "$SKILLS_DIR/discovering-requirements/SKILL.md")
    new_sdd_checksum=$(md5 -q "$SKILLS_DIR/designing-architecture/SKILL.md")
    new_sprint_checksum=$(md5 -q "$SKILLS_DIR/planning-sprints/SKILL.md")
    new_impl_checksum=$(md5 -q "$SKILLS_DIR/implementing-tasks/SKILL.md")

    [[ "$orig_prd_checksum" == "$new_prd_checksum" ]]
    [[ "$orig_sdd_checksum" == "$new_sdd_checksum" ]]
    [[ "$orig_sprint_checksum" == "$new_sprint_checksum" ]]
    [[ "$orig_impl_checksum" == "$new_impl_checksum" ]]

    # Cleanup
    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "injection adds phase inside workflow section" {
    # Add phases
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    # Verify phase was added
    grep -q "GPT Cross-Model Review" "$SKILLS_DIR/discovering-requirements/SKILL.md"

    # Phase should be INSIDE workflow (before </workflow>)
    local phase_line workflow_end_line
    phase_line=$(grep -n "GPT Cross-Model Review" "$SKILLS_DIR/discovering-requirements/SKILL.md" | cut -d: -f1)
    workflow_end_line=$(grep -n "</workflow>" "$SKILLS_DIR/discovering-requirements/SKILL.md" | cut -d: -f1)

    # Phase should be before </workflow>
    [[ "$phase_line" -lt "$workflow_end_line" ]]

    # Phase should use standard ### format
    grep -q "### Phase.*GPT Cross-Model Review" "$SKILLS_DIR/discovering-requirements/SKILL.md"

    # Cleanup
    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "GPT review phase not present in skill files at rest" {
    # Without any config manipulation, skill files should be clean
    ! grep -q "GPT Cross-Model Review" "$TEST_DIR/discovering-requirements-SKILL.md.bak"
    ! grep -q "GPT Cross-Model Review" "$TEST_DIR/designing-architecture-SKILL.md.bak"
    ! grep -q "GPT Cross-Model Review" "$TEST_DIR/planning-sprints-SKILL.md.bak"
    ! grep -q "GPT Cross-Model Review" "$TEST_DIR/implementing-tasks-SKILL.md.bak"
}

@test "inject script removes phases when config missing" {
    # Setup: first add phases
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    # Verify phases exist
    grep -q "GPT Cross-Model Review" "$SKILLS_DIR/discovering-requirements/SKILL.md"

    # Remove config
    rm -f "$PROJECT_ROOT/.loa.config.yaml"
    run "$INJECT_SCRIPT"
    [[ "$status" -eq 0 ]]

    # Check phases were removed
    ! grep -q "GPT Cross-Model Review" "$SKILLS_DIR/discovering-requirements/SKILL.md"
}

@test "injected PRD phase uses Skill tool pattern for gpt-review" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    # Check for explicit Skill tool invocation pattern
    grep -q "Skill: gpt-review" "$SKILLS_DIR/discovering-requirements/SKILL.md"
    grep -q "Args: prd" "$SKILLS_DIR/discovering-requirements/SKILL.md"

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "injected SDD phase uses Skill tool pattern for gpt-review" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    grep -q "Skill: gpt-review" "$SKILLS_DIR/designing-architecture/SKILL.md"
    grep -q "Args: sdd" "$SKILLS_DIR/designing-architecture/SKILL.md"

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "injected Sprint phase uses Skill tool pattern for gpt-review" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    grep -q "Skill: gpt-review" "$SKILLS_DIR/planning-sprints/SKILL.md"
    grep -q "Args: sprint" "$SKILLS_DIR/planning-sprints/SKILL.md"

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "injected Code phase uses Skill tool pattern for gpt-review" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    grep -q "Skill: gpt-review" "$SKILLS_DIR/implementing-tasks/SKILL.md"
    grep -q "Args: code" "$SKILLS_DIR/implementing-tasks/SKILL.md"

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "inject is idempotent - running twice doesn't duplicate phases" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"

    # Run twice
    "$INJECT_SCRIPT"
    "$INJECT_SCRIPT"

    # Count occurrences - should be exactly 1
    local count
    count=$(grep -c "GPT Cross-Model Review" "$SKILLS_DIR/discovering-requirements/SKILL.md")
    [[ "$count" -eq 1 ]]

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

# =============================================================================
# Toggle integration tests
# =============================================================================

@test "toggle script calls inject script" {
    grep -q "inject-gpt-review-gates.sh" "$TOGGLE_SCRIPT"
}

@test "toggle script is executable" {
    [[ -x "$TOGGLE_SCRIPT" ]]
}

# =============================================================================
# Static infrastructure tests
# =============================================================================

@test "gpt-review-api.sh script is executable" {
    [[ -x "$PROJECT_ROOT/.claude/scripts/gpt-review-api.sh" ]]
}

@test "/gpt-review command definition exists" {
    [[ -f "$PROJECT_ROOT/.claude/commands/gpt-review.md" ]]
}

@test "/toggle-gpt-review command definition exists" {
    [[ -f "$PROJECT_ROOT/.claude/commands/toggle-gpt-review.md" ]]
}

@test "PostToolUse hook for code files exists" {
    grep -q "auto-gpt-review-hook.sh" "$PROJECT_ROOT/.claude/settings.json"
}

# =============================================================================
# API script tests
# =============================================================================

@test "API script works regardless of config (config controls auto-prompting only)" {
    # Setup: DISABLE GPT review in config
    cp "$FIXTURES_DIR/configs/disabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"

    # Create test files
    mkdir -p "$TEST_DIR/grimoires/loa"
    echo "# Test PRD" > "$TEST_DIR/grimoires/loa/prd.md"
    echo "You are an expert in test domains." > "$TEST_DIR/expertise.md"
    echo "## Product Context\nTest product." > "$TEST_DIR/context.md"

    # Run API script - should NOT skip due to config, but will fail due to fake API key
    cd "$PROJECT_ROOT"
    export OPENAI_API_KEY="test-key-for-mock"
    run .claude/scripts/gpt-review-api.sh prd "$TEST_DIR/grimoires/loa/prd.md" \
        --expertise "$TEST_DIR/expertise.md" \
        --context "$TEST_DIR/context.md"

    # Should fail with API error (exit 1 or 4), NOT succeed with SKIPPED
    # The point is: config doesn't block manual invocation
    [[ "$status" -ne 0 ]]
    ! echo "$output" | grep -q '"verdict": "SKIPPED"'

    # Cleanup
    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "API script fails gracefully without API key" {
    # Setup: enable GPT review but no API key
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"

    # Create test files
    mkdir -p "$TEST_DIR/grimoires/loa"
    echo "# Test PRD" > "$TEST_DIR/grimoires/loa/prd.md"
    echo "You are an expert in test domains." > "$TEST_DIR/expertise.md"
    echo "## Product Context\nTest product." > "$TEST_DIR/context.md"

    # Unset API key
    unset OPENAI_API_KEY

    # Remove any .env files that might have keys
    rm -f "$PROJECT_ROOT/.env" "$PROJECT_ROOT/.env.local"

    # Run API script - should fail with exit code 4 (missing API key)
    cd "$PROJECT_ROOT"
    run .claude/scripts/gpt-review-api.sh prd "$TEST_DIR/grimoires/loa/prd.md" \
        --expertise "$TEST_DIR/expertise.md" \
        --context "$TEST_DIR/context.md"

    # Should fail with specific exit code for missing API key
    [[ "$status" -eq 4 ]]

    # Cleanup
    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "API script requires --expertise file" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"

    mkdir -p "$TEST_DIR/grimoires/loa"
    echo "# Test PRD" > "$TEST_DIR/grimoires/loa/prd.md"
    echo "## Context" > "$TEST_DIR/context.md"

    cd "$PROJECT_ROOT"
    export OPENAI_API_KEY="test-key"

    # Call without --expertise
    run .claude/scripts/gpt-review-api.sh prd "$TEST_DIR/grimoires/loa/prd.md" \
        --context "$TEST_DIR/context.md"

    # Should fail with exit code 2 (invalid input)
    [[ "$status" -eq 2 ]]
    echo "$output" | grep -q "Missing --expertise file"

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "API script requires --context file" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"

    mkdir -p "$TEST_DIR/grimoires/loa"
    echo "# Test PRD" > "$TEST_DIR/grimoires/loa/prd.md"
    echo "You are an expert." > "$TEST_DIR/expertise.md"

    cd "$PROJECT_ROOT"
    export OPENAI_API_KEY="test-key"

    # Call without --context
    run .claude/scripts/gpt-review-api.sh prd "$TEST_DIR/grimoires/loa/prd.md" \
        --expertise "$TEST_DIR/expertise.md"

    # Should fail with exit code 2 (invalid input)
    [[ "$status" -eq 2 ]]
    echo "$output" | grep -q "Missing --context file"

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

# =============================================================================
# Success criteria injection tests
# =============================================================================

@test "inject script adds success criterion when enabled" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    # Check GPT Review success criterion was added to all skills
    grep -q "GPT Review.*Cross-model review" "$SKILLS_DIR/discovering-requirements/SKILL.md"
    grep -q "GPT Review.*Cross-model review" "$SKILLS_DIR/designing-architecture/SKILL.md"
    grep -q "GPT Review.*Cross-model review" "$SKILLS_DIR/planning-sprints/SKILL.md"
    grep -q "GPT Review.*Cross-model review" "$SKILLS_DIR/implementing-tasks/SKILL.md"

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "inject script removes success criterion when disabled" {
    # First add
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"
    grep -q "GPT Review.*Cross-model review" "$SKILLS_DIR/discovering-requirements/SKILL.md"

    # Then disable
    cp "$FIXTURES_DIR/configs/disabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    # Check criterion was removed
    ! grep -q "GPT Review.*Cross-model review" "$SKILLS_DIR/discovering-requirements/SKILL.md"
    ! grep -q "GPT Review.*Cross-model review" "$SKILLS_DIR/designing-architecture/SKILL.md"
    ! grep -q "GPT Review.*Cross-model review" "$SKILLS_DIR/planning-sprints/SKILL.md"
    ! grep -q "GPT Review.*Cross-model review" "$SKILLS_DIR/implementing-tasks/SKILL.md"

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "success criterion is inside success_criteria section" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    # Criterion should be BEFORE </success_criteria>
    local criterion_line criteria_end_line
    criterion_line=$(grep -n "GPT Review.*Cross-model review" "$SKILLS_DIR/discovering-requirements/SKILL.md" | cut -d: -f1)
    criteria_end_line=$(grep -n "</success_criteria>" "$SKILLS_DIR/discovering-requirements/SKILL.md" | cut -d: -f1)

    [[ "$criterion_line" -lt "$criteria_end_line" ]]

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "success criterion not present in skill files at rest" {
    ! grep -q "GPT Review.*Cross-model review" "$TEST_DIR/discovering-requirements-SKILL.md.bak"
    ! grep -q "GPT Review.*Cross-model review" "$TEST_DIR/designing-architecture-SKILL.md.bak"
    ! grep -q "GPT Review.*Cross-model review" "$TEST_DIR/planning-sprints-SKILL.md.bak"
    ! grep -q "GPT Review.*Cross-model review" "$TEST_DIR/implementing-tasks-SKILL.md.bak"
}

# =============================================================================
# Document hook tests
# =============================================================================

@test "document hook script exists and is executable" {
    [[ -x "$PROJECT_ROOT/.claude/scripts/gpt-review-doc-hook.sh" ]]
}

@test "PostToolUse hook for document files is registered" {
    grep -q "gpt-review-doc-hook.sh" "$PROJECT_ROOT/.claude/settings.json"
}

@test "PostToolUse hook matches prd.md files" {
    grep -q 'prd.*\\.md' "$PROJECT_ROOT/.claude/settings.json"
}

@test "PostToolUse hook matches sdd.md files" {
    grep -q 'sdd.*\\.md' "$PROJECT_ROOT/.claude/settings.json"
}

@test "PostToolUse hook matches sprint.md files" {
    grep -q 'sprint.*\\.md' "$PROJECT_ROOT/.claude/settings.json"
}

# =============================================================================
# Command file injection tests (what Claude actually reads!)
# =============================================================================

@test "inject script adds GPT review phase to command files when enabled" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    grep -q "GPT Cross-Model Review (MANDATORY)" "$PROJECT_ROOT/.claude/commands/plan-and-analyze.md"
    grep -q "GPT Cross-Model Review (MANDATORY)" "$PROJECT_ROOT/.claude/commands/architect.md"
    grep -q "GPT Cross-Model Review (MANDATORY)" "$PROJECT_ROOT/.claude/commands/sprint-plan.md"
    grep -q "GPT Cross-Model Review (MANDATORY)" "$PROJECT_ROOT/.claude/commands/implement.md"

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "inject script removes GPT review phase from command files when disabled" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"
    grep -q "GPT Cross-Model Review (MANDATORY)" "$PROJECT_ROOT/.claude/commands/plan-and-analyze.md"

    cp "$FIXTURES_DIR/configs/disabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    ! grep -q "GPT Cross-Model Review (MANDATORY)" "$PROJECT_ROOT/.claude/commands/plan-and-analyze.md"
    ! grep -q "GPT Cross-Model Review (MANDATORY)" "$PROJECT_ROOT/.claude/commands/architect.md"
    ! grep -q "GPT Cross-Model Review (MANDATORY)" "$PROJECT_ROOT/.claude/commands/sprint-plan.md"
    ! grep -q "GPT Cross-Model Review (MANDATORY)" "$PROJECT_ROOT/.claude/commands/implement.md"

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "command files are IDENTICAL to original after phase removal" {
    # Store original checksums
    local orig_plan orig_arch orig_sprint orig_impl
    orig_plan=$(md5 -q "$PROJECT_ROOT/.claude/commands/plan-and-analyze.md")
    orig_arch=$(md5 -q "$PROJECT_ROOT/.claude/commands/architect.md")
    orig_sprint=$(md5 -q "$PROJECT_ROOT/.claude/commands/sprint-plan.md")
    orig_impl=$(md5 -q "$PROJECT_ROOT/.claude/commands/implement.md")

    # Inject
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    # Remove
    cp "$FIXTURES_DIR/configs/disabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    # Compare
    [[ "$orig_plan" == "$(md5 -q "$PROJECT_ROOT/.claude/commands/plan-and-analyze.md")" ]]
    [[ "$orig_arch" == "$(md5 -q "$PROJECT_ROOT/.claude/commands/architect.md")" ]]
    [[ "$orig_sprint" == "$(md5 -q "$PROJECT_ROOT/.claude/commands/sprint-plan.md")" ]]
    [[ "$orig_impl" == "$(md5 -q "$PROJECT_ROOT/.claude/commands/implement.md")" ]]

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "GPT review phase not present in command files at rest" {
    ! grep -q "GPT Cross-Model Review (MANDATORY)" "$PROJECT_ROOT/.claude/commands/plan-and-analyze.md"
    ! grep -q "GPT Cross-Model Review (MANDATORY)" "$PROJECT_ROOT/.claude/commands/architect.md"
    ! grep -q "GPT Cross-Model Review (MANDATORY)" "$PROJECT_ROOT/.claude/commands/sprint-plan.md"
    ! grep -q "GPT Cross-Model Review (MANDATORY)" "$PROJECT_ROOT/.claude/commands/implement.md"
}

# =============================================================================
# CLAUDE.md banner injection tests
# =============================================================================

@test "inject script adds GPT review banner to CLAUDE.md when enabled" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    grep -q "GPT CROSS-MODEL REVIEW IS ENABLED" "$PROJECT_ROOT/CLAUDE.md"

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "inject script removes GPT review banner from CLAUDE.md when disabled" {
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"
    grep -q "GPT CROSS-MODEL REVIEW IS ENABLED" "$PROJECT_ROOT/CLAUDE.md"

    cp "$FIXTURES_DIR/configs/disabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    ! grep -q "GPT CROSS-MODEL REVIEW IS ENABLED" "$PROJECT_ROOT/CLAUDE.md"

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "CLAUDE.md is IDENTICAL to original after banner removal" {
    local orig_checksum
    orig_checksum=$(md5 -q "$PROJECT_ROOT/CLAUDE.md")

    cp "$FIXTURES_DIR/configs/enabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    cp "$FIXTURES_DIR/configs/disabled.yaml" "$PROJECT_ROOT/.loa.config.yaml"
    "$INJECT_SCRIPT"

    [[ "$orig_checksum" == "$(md5 -q "$PROJECT_ROOT/CLAUDE.md")" ]]

    rm -f "$PROJECT_ROOT/.loa.config.yaml"
}

@test "GPT review banner not present in CLAUDE.md at rest" {
    ! grep -q "GPT CROSS-MODEL REVIEW IS ENABLED" "$PROJECT_ROOT/CLAUDE.md"
}
