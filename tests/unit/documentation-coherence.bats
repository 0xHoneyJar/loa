#!/usr/bin/env bats
# Tests for documentation-coherence subagent
# Sprint 1, Task 1.3

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
    export SUBAGENTS_DIR="${PROJECT_ROOT}/.claude/subagents"
    export COMMANDS_DIR="${PROJECT_ROOT}/.claude/commands"
    export DOC_SUBAGENT="${SUBAGENTS_DIR}/documentation-coherence.md"
}

# =============================================================================
# Subagent Existence Tests
# =============================================================================

@test "documentation-coherence.md exists" {
    [ -f "$DOC_SUBAGENT" ]
}

@test "documentation-coherence.md is not empty" {
    [ -s "$DOC_SUBAGENT" ]
}

# =============================================================================
# YAML Frontmatter Tests (SDD Specification)
# =============================================================================

@test "documentation-coherence has valid YAML frontmatter" {
    # First line should be ---
    head -1 "$DOC_SUBAGENT" | grep -q "^---$"
    # Second occurrence should be within first 20 lines (frontmatter closing)
    head -20 "$DOC_SUBAGENT" | grep -c "^---$" | grep -q "2"
}

@test "documentation-coherence has name field" {
    grep -q "^name:" "$DOC_SUBAGENT"
}

@test "documentation-coherence has version field" {
    grep -q "^version:" "$DOC_SUBAGENT"
}

@test "documentation-coherence has description field" {
    grep -q "^description:" "$DOC_SUBAGENT"
}

@test "documentation-coherence has triggers field" {
    grep -q "^triggers:" "$DOC_SUBAGENT"
}

@test "documentation-coherence has severity_levels field" {
    grep -q "^severity_levels:" "$DOC_SUBAGENT"
}

@test "documentation-coherence has output_path field" {
    grep -q "^output_path:" "$DOC_SUBAGENT"
}

# =============================================================================
# Task Type Detection Tests
# =============================================================================

@test "documentation-coherence documents task type detection" {
    grep -q "Task Type Detection" "$DOC_SUBAGENT"
}

@test "documentation-coherence detects new feature task type" {
    grep -q "New feature" "$DOC_SUBAGENT"
}

@test "documentation-coherence detects bug fix task type" {
    grep -q "Bug fix" "$DOC_SUBAGENT"
}

@test "documentation-coherence detects new command task type" {
    grep -q "New command" "$DOC_SUBAGENT"
}

@test "documentation-coherence detects API change task type" {
    grep -q "API change" "$DOC_SUBAGENT"
}

@test "documentation-coherence detects refactor task type" {
    grep -q "Refactor" "$DOC_SUBAGENT"
}

@test "documentation-coherence detects security fix task type" {
    grep -q "Security fix" "$DOC_SUBAGENT"
}

@test "documentation-coherence detects config change task type" {
    grep -q "Config change" "$DOC_SUBAGENT"
}

# =============================================================================
# CHANGELOG Verification Tests
# =============================================================================

@test "documentation-coherence checks CHANGELOG entry exists" {
    grep -q "CHANGELOG.*entry" "$DOC_SUBAGENT"
}

@test "missing CHANGELOG entry returns ACTION_REQUIRED" {
    grep -q "CHANGELOG.*missing.*ACTION_REQUIRED\|ACTION_REQUIRED.*CHANGELOG.*missing" "$DOC_SUBAGENT" || \
    grep -A5 "Escalation Rules" "$DOC_SUBAGENT" | grep -q "CHANGELOG.*ACTION_REQUIRED"
}

@test "documentation-coherence verifies CHANGELOG section type" {
    grep -q "Correct section\|Added.*Changed.*Fixed" "$DOC_SUBAGENT"
}

@test "documentation-coherence verifies unreleased section" {
    grep -q "Unreleased" "$DOC_SUBAGENT"
}

# =============================================================================
# Severity Level Tests
# =============================================================================

@test "documentation-coherence defines COHERENT severity" {
    grep -q "COHERENT" "$DOC_SUBAGENT"
}

@test "documentation-coherence defines NEEDS_UPDATE severity" {
    grep -q "NEEDS_UPDATE" "$DOC_SUBAGENT"
}

@test "documentation-coherence defines ACTION_REQUIRED severity" {
    grep -q "ACTION_REQUIRED" "$DOC_SUBAGENT"
}

@test "COHERENT is non-blocking" {
    grep -A2 "COHERENT" "$DOC_SUBAGENT" | grep -qi "no\|non-blocking\|advisory"
}

@test "ACTION_REQUIRED is blocking" {
    grep -A2 "ACTION_REQUIRED" "$DOC_SUBAGENT" | grep -qi "yes\|blocking\|critical"
}

# =============================================================================
# Escalation Rules Tests
# =============================================================================

@test "documentation-coherence has escalation rules" {
    grep -q "Escalation Rules" "$DOC_SUBAGENT"
}

@test "new command without CLAUDE.md is ACTION_REQUIRED" {
    grep -q "CLAUDE.md.*ACTION_REQUIRED\|command.*CLAUDE.md" "$DOC_SUBAGENT"
}

@test "security fix without comments is ACTION_REQUIRED" {
    grep -qi "Security.*comment.*ACTION_REQUIRED\|security.*code.*ACTION_REQUIRED" "$DOC_SUBAGENT"
}

# =============================================================================
# Report Format Tests
# =============================================================================

@test "documentation-coherence has task-level report format" {
    grep -q "Task-Level Report Format\|Task.*Report.*Format" "$DOC_SUBAGENT"
}

@test "documentation-coherence has sprint-level report format" {
    grep -q "Sprint-Level Report Format\|Sprint.*Report.*Format" "$DOC_SUBAGENT"
}

@test "task report includes documentation checklist" {
    grep -q "Documentation Checklist" "$DOC_SUBAGENT"
}

@test "task report includes task type" {
    grep -q "Task Type\|Detected Type" "$DOC_SUBAGENT"
}

@test "sprint report includes task coverage" {
    grep -q "Task Coverage\|Coverage" "$DOC_SUBAGENT"
}

@test "sprint report includes release readiness" {
    grep -q "Release Readiness" "$DOC_SUBAGENT"
}

# =============================================================================
# Blocking Behavior Tests
# =============================================================================

@test "documentation-coherence documents blocking behavior" {
    grep -q "Blocking Behavior" "$DOC_SUBAGENT"
}

@test "after implementing-tasks is non-blocking" {
    grep -A10 "Blocking Behavior" "$DOC_SUBAGENT" | grep -qi "implementing.*No\|implementing.*advisory"
}

@test "before reviewing-code is blocking" {
    grep -A10 "Blocking Behavior" "$DOC_SUBAGENT" | grep -qi "reviewing.*Yes\|review.*blocking"
}

@test "/validate docs command is advisory" {
    grep -A10 "Blocking Behavior" "$DOC_SUBAGENT" | grep -qi "validate.*No\|command.*advisory"
}

# =============================================================================
# Integration Notes Tests
# =============================================================================

@test "documentation-coherence documents reviewing-code integration" {
    grep -q "With reviewing-code\|reviewing-code" "$DOC_SUBAGENT"
}

@test "documentation-coherence documents auditing-security integration" {
    grep -q "With auditing-security\|auditing-security" "$DOC_SUBAGENT"
}

@test "documentation-coherence documents deploying-infrastructure integration" {
    grep -q "With deploying-infrastructure\|deploying-infrastructure" "$DOC_SUBAGENT"
}

# =============================================================================
# /validate docs Command Tests
# =============================================================================

@test "validate.md includes docs subcommand" {
    grep -q "docs" "$COMMANDS_DIR/validate.md"
}

@test "validate docs --sprint option documented" {
    grep -q "\-\-sprint" "$COMMANDS_DIR/validate.md"
}

@test "validate docs --task option documented" {
    grep -q "\-\-task" "$COMMANDS_DIR/validate.md"
}

@test "validate command lists documentation-coherence subagent" {
    grep -q "documentation-coherence" "$COMMANDS_DIR/validate.md"
}

@test "validate command shows docs blocking verdict" {
    grep -q "ACTION_REQUIRED" "$COMMANDS_DIR/validate.md"
}

@test "validate command shows docs non-blocking verdicts" {
    grep -q "NEEDS_UPDATE\|COHERENT" "$COMMANDS_DIR/validate.md"
}

# =============================================================================
# Requirements Matrix Tests
# =============================================================================

@test "documentation-coherence has requirements matrix" {
    grep -q "requirements_matrix\|Per-Task Documentation Requirements" "$DOC_SUBAGENT"
}

@test "requirements matrix includes CHANGELOG column" {
    grep -A10 "requirements_matrix\|Per-Task Documentation" "$DOC_SUBAGENT" | grep -q "CHANGELOG"
}

@test "requirements matrix includes README column" {
    grep -A10 "requirements_matrix\|Per-Task Documentation" "$DOC_SUBAGENT" | grep -q "README"
}

@test "requirements matrix includes CLAUDE.md column" {
    grep -A10 "requirements_matrix\|Per-Task Documentation" "$DOC_SUBAGENT" | grep -q "CLAUDE.md"
}

@test "requirements matrix includes Code Comments column" {
    grep -A10 "requirements_matrix\|Per-Task Documentation" "$DOC_SUBAGENT" | grep -q "Code Comments\|Comments"
}

@test "requirements matrix includes SDD column" {
    grep -A10 "requirements_matrix\|Per-Task Documentation" "$DOC_SUBAGENT" | grep -q "SDD"
}
