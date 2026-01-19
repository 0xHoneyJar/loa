#!/usr/bin/env bats
# Integration tests for documentation-coherence skill integrations
# Sprint 2, Task 2.4

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
    export SKILLS_DIR="${PROJECT_ROOT}/.claude/skills"
    export SUBAGENTS_DIR="${PROJECT_ROOT}/.claude/subagents"
    export COMMANDS_DIR="${PROJECT_ROOT}/.claude/commands"
}

# =============================================================================
# reviewing-code Skill Integration Tests
# =============================================================================

@test "reviewing-code skill has documentation verification section" {
    grep -q "Documentation Verification" "$SKILLS_DIR/reviewing-code/SKILL.md"
}

@test "reviewing-code documents pre-review check for doc reports" {
    grep -q "Pre-Review Check\|documentation-coherence report" "$SKILLS_DIR/reviewing-code/SKILL.md"
}

@test "reviewing-code has documentation checklist" {
    grep -q "Documentation Checklist" "$SKILLS_DIR/reviewing-code/SKILL.md"
}

@test "reviewing-code lists CHANGELOG as blocking requirement" {
    grep -A20 "Documentation Checklist\|Cannot Approve If" "$SKILLS_DIR/reviewing-code/SKILL.md" | grep -qi "CHANGELOG.*YES\|CHANGELOG.*blocking\|CHANGELOG entry missing"
}

@test "reviewing-code lists CLAUDE.md as blocking for commands" {
    grep -A20 "Cannot Approve If" "$SKILLS_DIR/reviewing-code/SKILL.md" | grep -qi "CLAUDE.md"
}

@test "reviewing-code has approval language template" {
    grep -q "Approval Language\|If documentation is complete" "$SKILLS_DIR/reviewing-code/SKILL.md"
}

@test "reviewing-code has rejection language template" {
    grep -q "documentation needs work\|Changes required\|Documentation verification: FAIL" "$SKILLS_DIR/reviewing-code/SKILL.md"
}

@test "reviewing-code blocks on ACTION_REQUIRED status" {
    grep -q "ACTION_REQUIRED" "$SKILLS_DIR/reviewing-code/SKILL.md"
}

# =============================================================================
# auditing-security Skill Integration Tests
# =============================================================================

@test "auditing-security skill has documentation audit section" {
    grep -q "Documentation Audit" "$SKILLS_DIR/auditing-security/SKILL.md"
}

@test "auditing-security verifies sprint documentation coverage" {
    grep -q "Sprint Documentation Verification\|task coverage\|task has documentation" "$SKILLS_DIR/auditing-security/SKILL.md"
}

@test "auditing-security has security-specific documentation checks" {
    grep -q "Security-Specific Documentation\|SECURITY.md\|Auth documentation" "$SKILLS_DIR/auditing-security/SKILL.md"
}

@test "auditing-security documents red flags for documentation" {
    grep -q "Red Flags\|Internal URLs\|Hardcoded credentials" "$SKILLS_DIR/auditing-security/SKILL.md"
}

@test "auditing-security blocks on secrets in documentation" {
    grep -A30 "Cannot Approve If\|Red Flags" "$SKILLS_DIR/auditing-security/SKILL.md" | grep -qi "Secrets\|secrets"
}

@test "auditing-security has audit checklist addition" {
    grep -q "Audit Checklist Addition\|documentation-coherence reports" "$SKILLS_DIR/auditing-security/SKILL.md"
}

# =============================================================================
# deploying-infrastructure Skill Integration Tests
# =============================================================================

@test "deploying-infrastructure skill has release documentation section" {
    grep -q "Release Documentation Verification" "$SKILLS_DIR/deploying-infrastructure/SKILL.md"
}

@test "deploying-infrastructure has pre-deployment documentation checklist" {
    grep -q "Pre-Deployment Documentation\|CHANGELOG.*Version" "$SKILLS_DIR/deploying-infrastructure/SKILL.md"
}

@test "deploying-infrastructure verifies CHANGELOG version set" {
    grep -q "Version set\|not.*Unreleased\|version finalized" "$SKILLS_DIR/deploying-infrastructure/SKILL.md"
}

@test "deploying-infrastructure verifies all tasks documented in CHANGELOG" {
    grep -q "All sprint tasks documented\|tasks documented" "$SKILLS_DIR/deploying-infrastructure/SKILL.md"
}

@test "deploying-infrastructure verifies breaking changes documented" {
    grep -q "Breaking changes\|breaking changes" "$SKILLS_DIR/deploying-infrastructure/SKILL.md"
}

@test "deploying-infrastructure has README verification" {
    grep -q "README Verification\|README.*features" "$SKILLS_DIR/deploying-infrastructure/SKILL.md"
}

@test "deploying-infrastructure has deployment documentation requirements" {
    grep -q "Deployment Documentation\|Environment vars\|Rollback procedure" "$SKILLS_DIR/deploying-infrastructure/SKILL.md"
}

@test "deploying-infrastructure has operational readiness checks" {
    grep -q "Operational Readiness\|Runbook\|Monitoring" "$SKILLS_DIR/deploying-infrastructure/SKILL.md"
}

@test "deploying-infrastructure has cannot deploy conditions" {
    grep -q "Cannot Deploy If" "$SKILLS_DIR/deploying-infrastructure/SKILL.md"
}

@test "deploying-infrastructure blocks on unreleased CHANGELOG" {
    grep -A10 "Cannot Deploy If" "$SKILLS_DIR/deploying-infrastructure/SKILL.md" | grep -qi "Unreleased\|version"
}

# =============================================================================
# /validate docs Command Integration Tests
# =============================================================================

@test "validate command supports docs subcommand" {
    grep -q "docs" "$COMMANDS_DIR/validate.md"
}

@test "validate docs produces expected output fields" {
    # Check command documents output location
    grep -q "subagent-reports" "$COMMANDS_DIR/validate.md"
}

@test "validate command references documentation-coherence subagent" {
    grep -q "documentation-coherence" "$COMMANDS_DIR/validate.md"
}

# =============================================================================
# Cross-Integration Tests
# =============================================================================

@test "subagent defines all severity levels used by skills" {
    # Verify subagent defines COHERENT, NEEDS_UPDATE, ACTION_REQUIRED
    grep -q "COHERENT" "$SUBAGENTS_DIR/documentation-coherence.md"
    grep -q "NEEDS_UPDATE" "$SUBAGENTS_DIR/documentation-coherence.md"
    grep -q "ACTION_REQUIRED" "$SUBAGENTS_DIR/documentation-coherence.md"
}

@test "reviewing-code references same blocking verdict as subagent" {
    # Both should reference ACTION_REQUIRED as blocking
    grep -q "ACTION_REQUIRED" "$SKILLS_DIR/reviewing-code/SKILL.md"
    grep -q "ACTION_REQUIRED" "$SUBAGENTS_DIR/documentation-coherence.md"
}

@test "all skills reference v0.19.0 for documentation features" {
    grep -q "v0\.19\.0\|0\.19\.0" "$SKILLS_DIR/reviewing-code/SKILL.md"
    grep -q "v0\.19\.0\|0\.19\.0" "$SKILLS_DIR/auditing-security/SKILL.md"
    grep -q "v0\.19\.0\|0\.19\.0" "$SKILLS_DIR/deploying-infrastructure/SKILL.md"
}

@test "documentation-coherence subagent mentions all integrated skills" {
    grep -q "reviewing-code" "$SUBAGENTS_DIR/documentation-coherence.md"
    grep -q "auditing-security" "$SUBAGENTS_DIR/documentation-coherence.md"
    grep -q "deploying-infrastructure" "$SUBAGENTS_DIR/documentation-coherence.md"
}
