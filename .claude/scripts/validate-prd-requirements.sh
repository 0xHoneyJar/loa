#!/usr/bin/env bash
# v0.9.0 Lossless Ledger Protocol - PRD Requirements Validation
# UAT Validation Script
set -euo pipefail

# Color codes
if [[ "${CI:-}" == "true" ]] || [[ ! -t 1 ]]; then
    RED=''; GREEN=''; YELLOW=''; NC=''
else
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
fi

PASSED=0
FAILED=0
WARNINGS=0

log_pass() { echo -e "${GREEN}✓${NC} $*"; PASSED=$((PASSED + 1)); }
log_fail() { echo -e "${RED}✗${NC} $*"; FAILED=$((FAILED + 1)); }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; WARNINGS=$((WARNINGS + 1)); }
log_info() { echo -e "  $*"; }

# =============================================================================
# Functional Requirements Validation
# =============================================================================

validate_fr1_truth_hierarchy() {
    echo ""
    echo "FR-1: Truth Hierarchy"
    echo "---------------------"

    # Check session-continuity.md has truth hierarchy
    if grep -q "IMMUTABLE TRUTH HIERARCHY" .claude/protocols/session-continuity.md 2>/dev/null; then
        log_pass "Truth hierarchy documented in session-continuity.md"
    else
        log_fail "Truth hierarchy not found in session-continuity.md"
    fi

    # Check 7-level hierarchy defined
    if grep -q "CODE.*ABSOLUTE" .claude/protocols/session-continuity.md 2>/dev/null; then
        log_pass "Code as absolute truth defined"
    else
        log_fail "Code as absolute truth not defined"
    fi

    # Check context window transient
    if grep -q "CONTEXT WINDOW.*TRANSIENT" .claude/protocols/session-continuity.md 2>/dev/null; then
        log_pass "Context window marked as transient"
    else
        log_fail "Context window transient status not documented"
    fi
}

validate_fr2_session_continuity() {
    echo ""
    echo "FR-2: Session Continuity Protocol"
    echo "----------------------------------"

    # Check protocol exists
    if [[ -f ".claude/protocols/session-continuity.md" ]]; then
        log_pass "Session continuity protocol exists"
    else
        log_fail "Session continuity protocol missing"
        return
    fi

    # Check session lifecycle phases
    if grep -q "Phase 1: Session Start" .claude/protocols/session-continuity.md; then
        log_pass "Session start phase documented"
    else
        log_fail "Session start phase not documented"
    fi

    if grep -q "Phase 2: During Session" .claude/protocols/session-continuity.md; then
        log_pass "During session phase documented"
    else
        log_fail "During session phase not documented"
    fi

    if grep -q "Phase 3: Before /clear" .claude/protocols/session-continuity.md; then
        log_pass "Before clear phase documented"
    else
        log_fail "Before clear phase not documented"
    fi
}

validate_fr3_tiered_recovery() {
    echo ""
    echo "FR-3: Tiered Ledger Recovery"
    echo "----------------------------"

    # Check 3 recovery levels defined
    if grep -q "Level.*1.*~100" .claude/protocols/session-continuity.md 2>/dev/null; then
        log_pass "Level 1 recovery (~100 tokens) defined"
    else
        log_fail "Level 1 recovery not properly defined"
    fi

    if grep -q "Level.*2.*~.*500" .claude/protocols/session-continuity.md 2>/dev/null; then
        log_pass "Level 2 recovery (~200-500 tokens) defined"
    else
        log_warn "Level 2 recovery definition may be incomplete"
    fi

    if grep -q "Level.*3\|Level 3\|Full.*read\|Full scan" .claude/protocols/session-continuity.md 2>/dev/null; then
        log_pass "Level 3 full recovery defined"
    else
        log_fail "Level 3 recovery not defined"
    fi
}

validate_fr4_attention_budget() {
    echo ""
    echo "FR-4: Attention Budget Management"
    echo "----------------------------------"

    # Check protocol exists
    if [[ -f ".claude/protocols/attention-budget.md" ]]; then
        log_pass "Attention budget protocol exists"
    else
        log_fail "Attention budget protocol missing"
        return
    fi

    # Check threshold levels
    if grep -q "Green.*0-5,000" .claude/protocols/attention-budget.md; then
        log_pass "Green zone threshold defined"
    else
        log_fail "Green zone threshold not defined"
    fi

    if grep -q "Yellow.*5,000" .claude/protocols/attention-budget.md; then
        log_pass "Yellow zone (delta-synthesis) threshold defined"
    else
        log_fail "Yellow zone threshold not defined"
    fi

    if grep -q "Red.*15,000" .claude/protocols/attention-budget.md; then
        log_pass "Red zone threshold defined"
    else
        log_fail "Red zone threshold not defined"
    fi

    # Check advisory mode
    if grep -q "advisory" .claude/protocols/attention-budget.md; then
        log_pass "Advisory mode documented"
    else
        log_fail "Advisory mode not documented"
    fi
}

validate_fr5_jit_retrieval() {
    echo ""
    echo "FR-5: JIT Retrieval Protocol"
    echo "----------------------------"

    # Check protocol exists
    if [[ -f ".claude/protocols/jit-retrieval.md" ]]; then
        log_pass "JIT retrieval protocol exists"
    else
        log_fail "JIT retrieval protocol missing"
        return
    fi

    # Check lightweight identifiers
    if grep -q "Lightweight Identifier" .claude/protocols/jit-retrieval.md; then
        log_pass "Lightweight identifier format documented"
    else
        log_fail "Lightweight identifier format not documented"
    fi

    # Check 97% reduction claim
    if grep -q "97%" .claude/protocols/jit-retrieval.md; then
        log_pass "97% token reduction documented"
    else
        log_fail "97% token reduction claim not found"
    fi

    # Check \${PROJECT_ROOT} requirement
    if grep -q '\${PROJECT_ROOT}' .claude/protocols/jit-retrieval.md; then
        log_pass "\${PROJECT_ROOT} path format documented"
    else
        log_fail "\${PROJECT_ROOT} path format not documented"
    fi
}

validate_fr6_grounding_ratio() {
    echo ""
    echo "FR-6: Grounding Ratio Enforcement"
    echo "----------------------------------"

    # Check protocol exists
    if [[ -f ".claude/protocols/grounding-enforcement.md" ]]; then
        log_pass "Grounding enforcement protocol exists"
    else
        log_fail "Grounding enforcement protocol missing"
        return
    fi

    # Check script exists
    if [[ -f ".claude/scripts/grounding-check.sh" ]]; then
        log_pass "grounding-check.sh script exists"
        if [[ -x ".claude/scripts/grounding-check.sh" ]]; then
            log_pass "grounding-check.sh is executable"
        else
            log_fail "grounding-check.sh is not executable"
        fi
    else
        log_fail "grounding-check.sh script missing"
    fi

    # Check 0.95 threshold
    if grep -q "0.95" .claude/protocols/grounding-enforcement.md; then
        log_pass "0.95 default threshold documented"
    else
        log_fail "0.95 default threshold not documented"
    fi

    # Check grounding types
    if grep -q "citation" .claude/protocols/grounding-enforcement.md && \
       grep -q "code_reference" .claude/protocols/grounding-enforcement.md && \
       grep -q "assumption" .claude/protocols/grounding-enforcement.md; then
        log_pass "All grounding types documented"
    else
        log_fail "Not all grounding types documented"
    fi
}

validate_fr7_negative_grounding() {
    echo ""
    echo "FR-7: Negative Grounding Protocol"
    echo "----------------------------------"

    # Check negative grounding in protocols
    if grep -q "Negative Grounding" .claude/protocols/grounding-enforcement.md 2>/dev/null; then
        log_pass "Negative grounding documented in grounding-enforcement.md"
    else
        log_fail "Negative grounding not documented"
    fi

    # Check two-query requirement
    if grep -q "Two.*queries\|2.*queries" .claude/protocols/grounding-enforcement.md 2>/dev/null || \
       grep -q "Query 1.*Query 2" .claude/protocols/grounding-enforcement.md 2>/dev/null; then
        log_pass "Two-query verification documented"
    else
        log_warn "Two-query verification may not be clearly documented"
    fi

    # Check Ghost Feature handling
    if grep -q "Ghost Feature\|UNVERIFIED GHOST" .claude/protocols/grounding-enforcement.md 2>/dev/null; then
        log_pass "Ghost feature handling documented"
    else
        log_fail "Ghost feature handling not documented"
    fi
}

validate_fr8_trajectory_handoff() {
    echo ""
    echo "FR-8: Trajectory Handoff Logging"
    echo "---------------------------------"

    # Check trajectory directory structure
    if grep -q "trajectory" .claude/protocols/session-continuity.md 2>/dev/null; then
        log_pass "Trajectory logging documented"
    else
        log_fail "Trajectory logging not documented"
    fi

    # Check session_handoff format
    if grep -q "session_handoff" .claude/protocols/synthesis-checkpoint.md 2>/dev/null; then
        log_pass "Session handoff format documented"
    else
        log_fail "Session handoff format not documented"
    fi

    # Check handoffs[] in Bead schema
    if grep -q "handoffs:" .claude/protocols/session-continuity.md 2>/dev/null; then
        log_pass "Bead handoffs[] array documented"
    else
        log_warn "Bead handoffs[] array may not be documented"
    fi
}

validate_fr9_self_healing() {
    echo ""
    echo "FR-9: Self-Healing State Zone"
    echo "------------------------------"

    # Check script exists
    if [[ -f ".claude/scripts/self-heal-state.sh" ]]; then
        log_pass "self-heal-state.sh script exists"
        if [[ -x ".claude/scripts/self-heal-state.sh" ]]; then
            log_pass "self-heal-state.sh is executable"
        else
            log_fail "self-heal-state.sh is not executable"
        fi
    else
        log_fail "self-heal-state.sh script missing"
    fi

    # Check recovery priority documented
    if grep -q "git.*history\|git show" .claude/protocols/session-continuity.md 2>/dev/null; then
        log_pass "Git-based recovery documented"
    else
        log_warn "Git-based recovery may not be fully documented"
    fi

    # Check template fallback
    if grep -q "template" .claude/protocols/session-continuity.md 2>/dev/null; then
        log_pass "Template fallback documented"
    else
        log_warn "Template fallback may not be documented"
    fi
}

validate_fr10_notes_extension() {
    echo ""
    echo "FR-10: NOTES.md Schema Extension"
    echo "---------------------------------"

    # Check Session Continuity section documented
    if grep -q "Session Continuity" .claude/protocols/session-continuity.md; then
        log_pass "Session Continuity section documented"
    else
        log_fail "Session Continuity section not documented"
    fi

    # Check Lightweight Identifiers section
    if grep -q "Lightweight Identifiers" .claude/protocols/session-continuity.md; then
        log_pass "Lightweight Identifiers section documented"
    else
        log_fail "Lightweight Identifiers section not documented"
    fi

    # Check Decision Log format
    if grep -q "Decision Log" .claude/protocols/session-continuity.md; then
        log_pass "Decision Log format documented"
    else
        log_fail "Decision Log format not documented"
    fi
}

validate_fr11_bead_schema() {
    echo ""
    echo "FR-11: Bead Schema Extension"
    echo "----------------------------"

    # Check decisions[] array
    if grep -q "decisions:" .claude/protocols/session-continuity.md 2>/dev/null; then
        log_pass "Bead decisions[] array documented"
    else
        log_fail "Bead decisions[] array not documented"
    fi

    # Check test_scenarios[] array
    if grep -q "test_scenarios:" .claude/protocols/session-continuity.md 2>/dev/null; then
        log_pass "Bead test_scenarios[] array documented"
    else
        log_fail "Bead test_scenarios[] array not documented"
    fi

    # Check backwards compatibility
    if grep -q "Backwards Compatibility\|backwards.*compatible\|OPTIONAL.*ADDITIVE" .claude/protocols/session-continuity.md 2>/dev/null; then
        log_pass "Backwards compatibility documented"
    else
        log_warn "Backwards compatibility may not be clearly documented"
    fi
}

# =============================================================================
# Integration Requirements Validation
# =============================================================================

validate_ir1_ck_integration() {
    echo ""
    echo "IR-1: ck Integration"
    echo "--------------------"

    # Check JIT retrieval references ck
    if grep -q "ck" .claude/protocols/jit-retrieval.md 2>/dev/null; then
        log_pass "ck integration documented in JIT retrieval"
    else
        log_fail "ck integration not documented in JIT retrieval"
    fi

    # Check fallback documented
    if grep -q "fallback\|grep\|sed" .claude/protocols/jit-retrieval.md 2>/dev/null; then
        log_pass "Fallback behavior documented"
    else
        log_fail "Fallback behavior not documented"
    fi

    # Check semantic search
    if grep -q "semantic\|--hybrid" .claude/protocols/jit-retrieval.md 2>/dev/null; then
        log_pass "Semantic search documented"
    else
        log_warn "Semantic search may not be clearly documented"
    fi
}

validate_ir2_beads_integration() {
    echo ""
    echo "IR-2: Beads CLI Integration"
    echo "---------------------------"

    # Check br commands documented
    if grep -q "br " .claude/protocols/session-continuity.md 2>/dev/null; then
        log_pass "Beads CLI commands documented"
    else
        log_fail "Beads CLI commands not documented"
    fi

    # Check br sync
    if grep -q "br sync" .claude/protocols/session-continuity.md 2>/dev/null; then
        log_pass "br sync workflow documented"
    else
        log_warn "br sync workflow may not be documented"
    fi

    # Check fallback to NOTES.md
    if grep -q "Fallback.*NOTES\|NOTES.*fallback" .claude/protocols/session-continuity.md 2>/dev/null; then
        log_pass "Fallback to NOTES.md documented"
    else
        log_warn "Fallback to NOTES.md may not be documented"
    fi
}

# =============================================================================
# Main Validation
# =============================================================================

main() {
    echo ""
    echo "======================================================================="
    echo "  v0.9.0 Lossless Ledger Protocol - PRD Requirements Validation"
    echo "======================================================================="
    echo ""
    echo "Validating Functional Requirements (FR-1 through FR-11)..."
    echo ""

    # Functional Requirements
    validate_fr1_truth_hierarchy
    validate_fr2_session_continuity
    validate_fr3_tiered_recovery
    validate_fr4_attention_budget
    validate_fr5_jit_retrieval
    validate_fr6_grounding_ratio
    validate_fr7_negative_grounding
    validate_fr8_trajectory_handoff
    validate_fr9_self_healing
    validate_fr10_notes_extension
    validate_fr11_bead_schema

    echo ""
    echo "Validating Integration Requirements (IR-1 and IR-2)..."

    # Integration Requirements
    validate_ir1_ck_integration
    validate_ir2_beads_integration

    # Summary
    echo ""
    echo "======================================================================="
    echo "  UAT Validation Summary"
    echo "======================================================================="
    echo ""
    echo -e "  ${GREEN}Passed:${NC}   $PASSED"
    echo -e "  ${RED}Failed:${NC}   $FAILED"
    echo -e "  ${YELLOW}Warnings:${NC} $WARNINGS"
    echo ""

    if [[ $FAILED -gt 0 ]]; then
        echo -e "${RED}UAT VALIDATION FAILED${NC}"
        echo "Please address the failed requirements before release."
        exit 1
    elif [[ $WARNINGS -gt 0 ]]; then
        echo -e "${YELLOW}UAT VALIDATION PASSED WITH WARNINGS${NC}"
        echo "Consider addressing warnings before release."
        exit 0
    else
        echo -e "${GREEN}UAT VALIDATION PASSED${NC}"
        echo "All PRD requirements validated successfully."
        exit 0
    fi
}

main "$@"
