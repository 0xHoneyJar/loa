#!/usr/bin/env bats
# Integration tests for /skill-audit command flow

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

@test "skill-audit.md command exists" {
    [ -f "$COMMANDS_DIR/skill-audit.md" ]
}

@test "skill-audit command is not empty" {
    [ -s "$COMMANDS_DIR/skill-audit.md" ]
}

# =============================================================================
# Subcommand Tests
# =============================================================================

@test "skill-audit supports --pending subcommand" {
    grep -q "\-\-pending" "$COMMANDS_DIR/skill-audit.md"
}

@test "skill-audit supports --approve subcommand" {
    grep -q "\-\-approve" "$COMMANDS_DIR/skill-audit.md"
}

@test "skill-audit supports --reject subcommand" {
    grep -q "\-\-reject" "$COMMANDS_DIR/skill-audit.md"
}

@test "skill-audit supports --prune subcommand" {
    grep -q "\-\-prune" "$COMMANDS_DIR/skill-audit.md"
}

@test "skill-audit supports --stats subcommand" {
    grep -q "\-\-stats" "$COMMANDS_DIR/skill-audit.md"
}

# =============================================================================
# Approval Workflow Tests
# =============================================================================

@test "approval workflow moves from pending to active" {
    grep -qiE "skills-pending.*skills/|pending.*active" "$COMMANDS_DIR/skill-audit.md"
}

@test "approval workflow logs to trajectory" {
    grep -qi "trajectory" "$COMMANDS_DIR/skill-audit.md"
}

# =============================================================================
# Rejection Workflow Tests
# =============================================================================

@test "rejection workflow prompts for reason" {
    grep -qiE "reason|prompt" "$COMMANDS_DIR/skill-audit.md"
}

@test "rejection workflow archives skill" {
    grep -qi "skills-archived" "$COMMANDS_DIR/skill-audit.md"
}

# =============================================================================
# Pruning Criteria Tests
# =============================================================================

@test "pruning criteria includes age threshold" {
    grep -qE "90.*day|day.*90" "$COMMANDS_DIR/skill-audit.md"
}

@test "pruning criteria includes match count threshold" {
    grep -qE "<.*2.*match|2.*match|min.*match" "$COMMANDS_DIR/skill-audit.md"
}

@test "pruning criteria documented in table" {
    grep -qiE "criterion|threshold|criteria" "$COMMANDS_DIR/skill-audit.md"
}

# =============================================================================
# Statistics Tests
# =============================================================================

@test "stats shows skill counts by status" {
    grep -qiE "active.*pending.*archived|status.*count" "$COMMANDS_DIR/skill-audit.md"
}

@test "stats shows match counts" {
    grep -qiE "match.*count|usage" "$COMMANDS_DIR/skill-audit.md"
}

# =============================================================================
# Lifecycle Path Tests
# =============================================================================

@test "skill-audit references all three directories" {
    grep -q "skills/" "$COMMANDS_DIR/skill-audit.md"
    grep -q "skills-pending" "$COMMANDS_DIR/skill-audit.md"
    grep -q "skills-archived" "$COMMANDS_DIR/skill-audit.md"
}

@test "skill-audit directories exist" {
    [ -d "$STATE_DIR/skills" ]
    [ -d "$STATE_DIR/skills-pending" ]
    [ -d "$STATE_DIR/skills-archived" ]
}

# =============================================================================
# Trajectory Logging Tests
# =============================================================================

@test "skill-audit logs approval events" {
    grep -qiE "approval.*log|log.*approval|approval.*event" "$COMMANDS_DIR/skill-audit.md"
}

@test "skill-audit logs rejection events" {
    grep -qiE "rejection.*log|log.*rejection|rejection.*event" "$COMMANDS_DIR/skill-audit.md"
}

@test "skill-audit logs prune events" {
    # Check for prune trajectory entry documentation
    grep -qi '"type": "prune"' "$COMMANDS_DIR/skill-audit.md"
}

# =============================================================================
# Configuration Integration Tests
# =============================================================================

@test "skill-audit references configuration" {
    grep -qiE "\.loa\.config|config" "$COMMANDS_DIR/skill-audit.md"
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "skill-audit documents error handling" {
    grep -qiE "error|not found|invalid" "$COMMANDS_DIR/skill-audit.md"
}

# =============================================================================
# Skill Integration Tests
# =============================================================================

@test "skill-audit activates continuous-learning skill" {
    grep -qi "continuous-learning" "$COMMANDS_DIR/skill-audit.md"
}
