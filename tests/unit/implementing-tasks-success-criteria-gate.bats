#!/usr/bin/env bats
# =============================================================================
# Issue #961 K-3 — Goal-Driven success-criteria gate in implementing-tasks
# =============================================================================
# Structural regression guard: verifies the gate text is present in SKILL.md
# and references the expected criteria-section variants + config key.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SKILL="$REPO_ROOT/.claude/skills/implementing-tasks/SKILL.md"
    [[ -f "$SKILL" ]] || skip "implementing-tasks SKILL.md not found"
}

@test "#961 K-3: SKILL.md contains <karpathy_goal_driven_gate> block" {
    grep -q '<karpathy_goal_driven_gate>' "$SKILL"
    grep -q '</karpathy_goal_driven_gate>' "$SKILL"
}

@test "#961 K-3: gate references all three criteria-section heading variants" {
    awk '/<karpathy_goal_driven_gate>/,/<\/karpathy_goal_driven_gate>/' "$SKILL" \
        | grep -qF '"Success criteria"'
    awk '/<karpathy_goal_driven_gate>/,/<\/karpathy_goal_driven_gate>/' "$SKILL" \
        | grep -qF '"Acceptance criteria"'
    awk '/<karpathy_goal_driven_gate>/,/<\/karpathy_goal_driven_gate>/' "$SKILL" \
        | grep -qF '"Verification"'
}

@test "#961 K-3: gate references require_success_criteria config key" {
    awk '/<karpathy_goal_driven_gate>/,/<\/karpathy_goal_driven_gate>/' "$SKILL" \
        | grep -qF 'require_success_criteria'
}

@test "#961 K-3: gate is inserted BEFORE the workflow section (precondition discipline)" {
    local gate_line workflow_line
    gate_line=$(grep -n '<karpathy_goal_driven_gate>' "$SKILL" | head -1 | cut -d: -f1)
    workflow_line=$(grep -n '^<workflow>' "$SKILL" | head -1 | cut -d: -f1)
    [ -n "$gate_line" ]
    [ -n "$workflow_line" ]
    [ "$gate_line" -lt "$workflow_line" ]
}
