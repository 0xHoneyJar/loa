#!/usr/bin/env bats
# Integration tests for /validate command flow

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
    export SUBAGENTS_DIR="${PROJECT_ROOT}/.claude/subagents"
    export COMMANDS_DIR="${PROJECT_ROOT}/.claude/commands"
    export PROTOCOLS_DIR="${PROJECT_ROOT}/.claude/protocols"
    export REPORTS_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/subagent-reports"
    export SKILLS_DIR="${PROJECT_ROOT}/.claude/skills"
}

# =============================================================================
# /validate Command Tests
# =============================================================================

@test "validate.md command exists" {
    [ -f "$COMMANDS_DIR/validate.md" ]
}

@test "validate command supports architecture type" {
    grep -q "architecture" "$COMMANDS_DIR/validate.md"
}

@test "validate command supports security type" {
    grep -q "security" "$COMMANDS_DIR/validate.md"
}

@test "validate command supports tests type" {
    grep -q "tests" "$COMMANDS_DIR/validate.md"
}

@test "validate command supports all type" {
    grep -q '"all"' "$COMMANDS_DIR/validate.md" || grep -q '`all`' "$COMMANDS_DIR/validate.md"
}

@test "validate command references subagent-reports output" {
    grep -q "subagent-reports" "$COMMANDS_DIR/validate.md"
}

@test "validate command references invocation protocol" {
    grep -q "subagent-invocation" "$COMMANDS_DIR/validate.md"
}

# =============================================================================
# Protocol Integration Tests
# =============================================================================

@test "subagent-invocation protocol exists" {
    [ -f "$PROTOCOLS_DIR/subagent-invocation.md" ]
}

@test "protocol mentions all three subagents" {
    grep -q "architecture-validator" "$PROTOCOLS_DIR/subagent-invocation.md"
    grep -q "security-scanner" "$PROTOCOLS_DIR/subagent-invocation.md"
    grep -q "test-adequacy-reviewer" "$PROTOCOLS_DIR/subagent-invocation.md"
}

@test "protocol defines blocking verdicts for all subagents" {
    grep -q "CRITICAL_VIOLATION" "$PROTOCOLS_DIR/subagent-invocation.md"
    grep -q "CRITICAL.*HIGH" "$PROTOCOLS_DIR/subagent-invocation.md" || \
    (grep -q "CRITICAL" "$PROTOCOLS_DIR/subagent-invocation.md" && grep -q "HIGH" "$PROTOCOLS_DIR/subagent-invocation.md")
    grep -q "INSUFFICIENT" "$PROTOCOLS_DIR/subagent-invocation.md"
}

@test "protocol references /validate command" {
    grep -q "/validate" "$PROTOCOLS_DIR/subagent-invocation.md"
}

# =============================================================================
# reviewing-code Skill Integration Tests
# =============================================================================

@test "reviewing-code skill exists" {
    [ -f "$SKILLS_DIR/reviewing-code/SKILL.md" ]
}

@test "reviewing-code skill has subagent report check section" {
    grep -q "Subagent Report Check" "$SKILLS_DIR/reviewing-code/SKILL.md"
}

@test "reviewing-code skill references v0.16.0" {
    grep -q "v0.16.0" "$SKILLS_DIR/reviewing-code/SKILL.md"
}

@test "reviewing-code skill documents blocking verdicts" {
    grep -q "CRITICAL_VIOLATION" "$SKILLS_DIR/reviewing-code/SKILL.md"
    grep -q "INSUFFICIENT" "$SKILLS_DIR/reviewing-code/SKILL.md"
}

@test "reviewing-code skill has DO NOT APPROVE instruction" {
    grep -q "DO NOT APPROVE" "$SKILLS_DIR/reviewing-code/SKILL.md"
}

@test "reviewing-code skill references subagent-reports directory" {
    grep -q "subagent-reports" "$SKILLS_DIR/reviewing-code/SKILL.md"
}

# =============================================================================
# End-to-End Flow Tests
# =============================================================================

@test "subagent-reports directory is ready for output" {
    [ -d "$REPORTS_DIR" ]
    [ -f "$REPORTS_DIR/.gitkeep" ]
}

@test "all subagents define output paths to reports directory" {
    for subagent in architecture-validator security-scanner test-adequacy-reviewer; do
        grep -q "grimoires/loa/a2a/subagent-reports/" "$SUBAGENTS_DIR/${subagent}.md"
    done
}

@test "validate command output location matches subagent output paths" {
    # Both should reference subagent-reports
    grep -q "subagent-reports" "$COMMANDS_DIR/validate.md"
    grep -q "subagent-reports" "$SUBAGENTS_DIR/architecture-validator.md"
    grep -q "subagent-reports" "$SUBAGENTS_DIR/security-scanner.md"
    grep -q "subagent-reports" "$SUBAGENTS_DIR/test-adequacy-reviewer.md"
}

@test "all components reference each other consistently" {
    # README mentions all subagents
    grep -q "architecture-validator" "$SUBAGENTS_DIR/README.md"
    grep -q "security-scanner" "$SUBAGENTS_DIR/README.md"
    grep -q "test-adequacy-reviewer" "$SUBAGENTS_DIR/README.md"

    # Protocol mentions all subagents
    grep -q "architecture-validator" "$PROTOCOLS_DIR/subagent-invocation.md"
    grep -q "security-scanner" "$PROTOCOLS_DIR/subagent-invocation.md"
    grep -q "test-adequacy-reviewer" "$PROTOCOLS_DIR/subagent-invocation.md"

    # validate command documents all types
    grep -q "architecture" "$COMMANDS_DIR/validate.md"
    grep -q "security" "$COMMANDS_DIR/validate.md"
    grep -q "tests" "$COMMANDS_DIR/validate.md"
}

# =============================================================================
# Scope Determination Tests
# =============================================================================

@test "all subagents document scope determination" {
    for subagent in architecture-validator security-scanner test-adequacy-reviewer; do
        grep -q "Scope Determination" "$SUBAGENTS_DIR/${subagent}.md"
    done
}

@test "all subagents follow same scope priority order" {
    # All should mention: explicit > sprint context > git diff
    for subagent in architecture-validator security-scanner test-adequacy-reviewer; do
        grep -q "Explicit" "$SUBAGENTS_DIR/${subagent}.md"
        grep -q "sprint" "$SUBAGENTS_DIR/${subagent}.md"
        grep -q "git diff" "$SUBAGENTS_DIR/${subagent}.md"
    done
}

# =============================================================================
# File Format Consistency Tests
# =============================================================================

@test "all subagent files are valid markdown" {
    for subagent in architecture-validator security-scanner test-adequacy-reviewer; do
        [ -f "$SUBAGENTS_DIR/${subagent}.md" ]
        # Check they're not empty
        [ -s "$SUBAGENTS_DIR/${subagent}.md" ]
    done
}

@test "no non-markdown files in subagents directory except README" {
    local non_md
    non_md=$(find "$SUBAGENTS_DIR" -type f ! -name "*.md" | wc -l)
    [ "$non_md" -eq 0 ]
}
