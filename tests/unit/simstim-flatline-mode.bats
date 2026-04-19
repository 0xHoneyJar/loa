#!/usr/bin/env bats
# =============================================================================
# simstim-flatline-mode.bats — tests for #579 simstim docs drift
# =============================================================================
# Ensures the simstim skill does NOT document `--mode hitl` (which the
# orchestrator rejects) and DOES document a form the orchestrator accepts.
# =============================================================================

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export SKILL_MD="$PROJECT_ROOT/.claude/skills/simstim-workflow/SKILL.md"
    export ORCH="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

# =========================================================================
# SFM-T1: --mode hitl must NOT appear anywhere in the simstim skill
# =========================================================================

@test "simstim SKILL.md does not reference --mode hitl" {
    run grep -F -- '--mode hitl' "$SKILL_MD"
    [ "$status" -ne 0 ]
}

@test "simstim SKILL.md PRD invocation is valid" {
    run grep -F 'flatline-orchestrator.sh --doc grimoires/loa/prd.md --phase prd --json' "$SKILL_MD"
    [ "$status" -eq 0 ]
}

@test "simstim SKILL.md SDD invocation is valid" {
    run grep -F 'flatline-orchestrator.sh --doc grimoires/loa/sdd.md --phase sdd --json' "$SKILL_MD"
    [ "$status" -eq 0 ]
}

@test "simstim SKILL.md sprint invocation is valid" {
    run grep -F 'flatline-orchestrator.sh --doc grimoires/loa/sprint.md --phase sprint --json' "$SKILL_MD"
    [ "$status" -eq 0 ]
}

# =========================================================================
# SFM-T2: the orchestrator is consistent — help matches validator
# =========================================================================

@test "orchestrator --help lists the same modes as the validator accepts" {
    # The validator in main() accepts: review, red-team, inquiry.
    # The help block must list all three.
    local help_output
    help_output=$("$ORCH" --help 2>&1)

    [[ "$help_output" == *"review"* ]]
    [[ "$help_output" == *"red-team"* ]]
    [[ "$help_output" == *"inquiry"* ]]
}

@test "orchestrator rejects --mode hitl with exit code 1 and actionable error" {
    # Need a doc inside the project root — the orchestrator rejects external paths before
    # reaching mode validation. Create a throwaway fixture under the project tree.
    local project_tmp="$PROJECT_ROOT/tests/unit/.tmp-flatline-fixtures"
    mkdir -p "$project_tmp"
    local fixture="$project_tmp/hitl-mode-test.md"
    echo "# Test doc for mode validation" > "$fixture"

    run "$ORCH" --doc "$fixture" --phase prd --mode hitl --dry-run --json
    local rc=$status
    local captured="$output"
    rm -rf "$project_tmp"

    [ "$rc" -eq 1 ]
    [[ "$captured" == *"Invalid mode"* ]]
    [[ "$captured" == *"expected: review, red-team, inquiry"* ]]
}
