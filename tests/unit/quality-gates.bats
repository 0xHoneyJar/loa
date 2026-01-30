#!/usr/bin/env bats
# Tests for Continuous Learning quality gates

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
    export PROTOCOL_FILE="${PROJECT_ROOT}/.claude/protocols/continuous-learning.md"
    export SKILL_FILE="${PROJECT_ROOT}/.claude/skills/continuous-learning/SKILL.md"
}

# =============================================================================
# Protocol Existence Tests
# =============================================================================

@test "continuous-learning protocol exists" {
    [ -f "$PROTOCOL_FILE" ]
}

@test "continuous-learning SKILL.md exists" {
    [ -f "$SKILL_FILE" ]
}

# =============================================================================
# Quality Gates Documentation Tests
# =============================================================================

@test "protocol documents Discovery Depth gate" {
    grep -qi "Discovery Depth" "$PROTOCOL_FILE"
}

@test "protocol documents Reusability gate" {
    grep -qi "Reusability" "$PROTOCOL_FILE"
}

@test "protocol documents Trigger Clarity gate" {
    grep -qi "Trigger Clarity" "$PROTOCOL_FILE"
}

@test "protocol documents Verification gate" {
    grep -qi "Verification" "$PROTOCOL_FILE"
}

@test "protocol requires ALL gates to pass" {
    grep -qi "all.*pass\|ALL PASS\|must pass" "$PROTOCOL_FILE"
}

# =============================================================================
# Quality Gate Criteria Tests
# =============================================================================

@test "Discovery Depth has pass criteria" {
    # Should mention investigation steps or non-obvious
    grep -A5 -i "Discovery Depth" "$PROTOCOL_FILE" | grep -qiE "investigation|non-obvious|multiple.*step"
}

@test "Reusability has pass criteria" {
    # Should mention generalizable or future use
    grep -A5 -i "Reusability" "$PROTOCOL_FILE" | grep -qiE "generaliz|future|reusable|pattern"
}

@test "Trigger Clarity has pass criteria" {
    # Should mention error messages or symptoms
    grep -A5 -i "Trigger Clarity" "$PROTOCOL_FILE" | grep -qiE "error|symptom|trigger|precise"
}

@test "Verification has pass criteria" {
    # Should mention tested or confirmed
    grep -A5 -i "Verification" "$PROTOCOL_FILE" | grep -qiE "test|confirm|verified|working"
}

# =============================================================================
# SKILL.md Quality Gate Integration Tests
# =============================================================================

@test "SKILL.md references quality gates" {
    grep -qi "quality gate" "$SKILL_FILE"
}

@test "SKILL.md has activation triggers section" {
    grep -qi "activation trigger\|trigger" "$SKILL_FILE"
}

@test "SKILL.md documents phase gating" {
    grep -qiE "phase.*gat|phase.*activ" "$SKILL_FILE"
}

# =============================================================================
# Gate Evaluation Flow Tests
# =============================================================================

@test "protocol has evaluation flow" {
    # Should have ASCII flow diagram or workflow
    grep -qE "──►|→|workflow|flow" "$PROTOCOL_FILE"
}

@test "protocol documents PASS/FAIL outcomes" {
    grep -qiE "PASS|FAIL|pass|fail" "$PROTOCOL_FILE"
}

# =============================================================================
# Configuration Integration Tests
# =============================================================================

@test "protocol references configuration" {
    grep -qiE "\.loa\.config|config" "$PROTOCOL_FILE"
}

@test "SKILL.md references configuration" {
    grep -qiE "\.loa\.config|config" "$SKILL_FILE"
}
