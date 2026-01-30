#!/usr/bin/env bats
# Tests for Continuous Learning zone compliance (State Zone only)

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
    export PROTOCOL_FILE="${PROJECT_ROOT}/.claude/protocols/continuous-learning.md"
    export SKILL_FILE="${PROJECT_ROOT}/.claude/skills/continuous-learning/SKILL.md"
    export TEMPLATE_FILE="${PROJECT_ROOT}/.claude/skills/continuous-learning/resources/skill-template.md"
    export RETRO_CMD="${PROJECT_ROOT}/.claude/commands/retrospective.md"
    export AUDIT_CMD="${PROJECT_ROOT}/.claude/commands/skill-audit.md"
}

# =============================================================================
# State Zone Directory Tests
# =============================================================================

@test "grimoires/loa/skills directory exists" {
    [ -d "${PROJECT_ROOT}/grimoires/loa/skills" ]
}

@test "grimoires/loa/skills-pending directory exists" {
    [ -d "${PROJECT_ROOT}/grimoires/loa/skills-pending" ]
}

@test "grimoires/loa/skills-archived directory exists" {
    [ -d "${PROJECT_ROOT}/grimoires/loa/skills-archived" ]
}

# =============================================================================
# Protocol Zone Compliance Documentation
# =============================================================================

@test "protocol documents State Zone for extracted skills" {
    grep -qi "grimoires/loa/skills" "$PROTOCOL_FILE"
}

@test "protocol prohibits System Zone writes" {
    grep -qiE "forbidden.*location|MUST NOT.*System Zone|cannot.*System Zone" "$PROTOCOL_FILE"
}

@test "protocol has Zone Compliance section" {
    grep -qi "zone compliance\|zone.*rule" "$PROTOCOL_FILE"
}

# =============================================================================
# Command Zone Compliance Tests
# =============================================================================

@test "retrospective command outputs to State Zone" {
    # Should reference grimoires/loa/ for output
    grep -q "grimoires/loa/skills" "$RETRO_CMD"
}

@test "retrospective command does not write to System Zone" {
    # Should not have output paths in .claude/
    ! grep -E "output.*\.claude/skills|write.*\.claude/skills" "$RETRO_CMD"
}

@test "skill-audit command operates in State Zone" {
    # Should reference grimoires/loa/ directories
    grep -q "grimoires/loa/skills" "$AUDIT_CMD"
}

# =============================================================================
# Template Zone Path Tests
# =============================================================================

@test "skill template documents State Zone paths" {
    # Template should not suggest writing to .claude/
    ! grep -qE "write to \.claude|output.*\.claude/skills" "$TEMPLATE_FILE" || true
}

# =============================================================================
# SKILL.md Zone Compliance
# =============================================================================

@test "SKILL.md documents three-zone model compliance" {
    grep -qiE "three.*zone|zone.*model|state zone" "$SKILL_FILE"
}

@test "SKILL.md specifies State Zone for skill storage" {
    grep -q "grimoires/loa/skills" "$SKILL_FILE"
}

# =============================================================================
# Configuration Zone Paths
# =============================================================================

@test "config file has skills_dir in State Zone" {
    grep -q "skills_dir: grimoires/loa/skills" "${PROJECT_ROOT}/.loa.config.yaml"
}

@test "config file has pending_dir in State Zone" {
    grep -q "pending_dir: grimoires/loa/skills-pending" "${PROJECT_ROOT}/.loa.config.yaml"
}

@test "config file has archive_dir in State Zone" {
    grep -q "archive_dir: grimoires/loa/skills-archived" "${PROJECT_ROOT}/.loa.config.yaml"
}

# =============================================================================
# Lifecycle Path Tests
# =============================================================================

@test "skill approval moves within State Zone" {
    # skills-pending/ → skills/ (both in grimoires/loa/)
    grep -qiE "skills-pending.*skills/|pending.*active" "$AUDIT_CMD"
}

@test "skill rejection moves within State Zone" {
    # skills-pending/ → skills-archived/ (both in grimoires/loa/)
    grep -qiE "skills-pending.*archived|reject.*archive" "$AUDIT_CMD"
}

@test "skill pruning archives to State Zone" {
    # skills/ → skills-archived/ (both in grimoires/loa/)
    grep -qiE "prune.*archive|archive.*prune" "$AUDIT_CMD"
}
