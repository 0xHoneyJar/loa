#!/usr/bin/env bats
# Integration tests for /retrospective command flow

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
    export COMMANDS_DIR="${PROJECT_ROOT}/.claude/commands"
    export SKILLS_DIR="${PROJECT_ROOT}/.claude/skills"
    export PROTOCOL_DIR="${PROJECT_ROOT}/.claude/protocols"
    export STATE_DIR="${PROJECT_ROOT}/grimoires/loa"
}

# =============================================================================
# Command Existence Tests
# =============================================================================

@test "retrospective.md command exists" {
    [ -f "$COMMANDS_DIR/retrospective.md" ]
}

@test "retrospective command is not empty" {
    [ -s "$COMMANDS_DIR/retrospective.md" ]
}

# =============================================================================
# Five-Step Workflow Tests
# =============================================================================

@test "retrospective documents Session Analysis step" {
    grep -qi "session analysis" "$COMMANDS_DIR/retrospective.md"
}

@test "retrospective documents Quality Gate Evaluation step" {
    grep -qi "quality gate" "$COMMANDS_DIR/retrospective.md"
}

@test "retrospective documents Cross-Reference Check step" {
    grep -qi "cross-reference" "$COMMANDS_DIR/retrospective.md"
}

@test "retrospective documents Skill Extraction step" {
    grep -qi "skill extraction\|extract" "$COMMANDS_DIR/retrospective.md"
}

@test "retrospective documents Summary step" {
    grep -qi "summary" "$COMMANDS_DIR/retrospective.md"
}

# =============================================================================
# Option Tests
# =============================================================================

@test "retrospective supports --scope option" {
    grep -q "\-\-scope" "$COMMANDS_DIR/retrospective.md"
}

@test "retrospective supports --force option" {
    grep -q "\-\-force" "$COMMANDS_DIR/retrospective.md"
}

@test "retrospective --scope accepts agent names" {
    grep -qi "implementing-tasks\|reviewing-code\|auditing-security" "$COMMANDS_DIR/retrospective.md"
}

# =============================================================================
# NOTES.md Integration Tests
# =============================================================================

@test "retrospective documents NOTES.md integration" {
    grep -qi "NOTES.md" "$COMMANDS_DIR/retrospective.md"
}

@test "retrospective checks NOTES.md before extraction" {
    grep -qiE "check.*NOTES|cross-reference.*NOTES|duplicate" "$COMMANDS_DIR/retrospective.md"
}

# =============================================================================
# Output Path Tests
# =============================================================================

@test "retrospective outputs to skills-pending" {
    grep -q "skills-pending" "$COMMANDS_DIR/retrospective.md"
}

@test "retrospective trajectory logging documented" {
    grep -qi "trajectory" "$COMMANDS_DIR/retrospective.md"
}

# =============================================================================
# Skill Integration Tests
# =============================================================================

@test "retrospective activates continuous-learning skill" {
    grep -qi "continuous-learning" "$COMMANDS_DIR/retrospective.md"
}

@test "continuous-learning skill exists" {
    [ -f "$SKILLS_DIR/continuous-learning/SKILL.md" ]
}

@test "continuous-learning protocol exists" {
    [ -f "$PROTOCOL_DIR/continuous-learning.md" ]
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "retrospective documents error handling" {
    grep -qiE "error|handling" "$COMMANDS_DIR/retrospective.md"
}

# =============================================================================
# Example Flow Tests
# =============================================================================

@test "retrospective has example conversation flow" {
    grep -qi "Example Conversation Flow" "$COMMANDS_DIR/retrospective.md"
}
