#!/usr/bin/env bash
# test_inquiry_integration.sh - Tests for Sprint 6 (FR-4 Multi-Model Inquiry + Integration)
#
# Tests: inquiry mode in flatline-orchestrator, inquiry integration in bridge-orchestrator,
# end-to-end signal chain, config schema validation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "  PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "  FAIL: $1"
}

# ─────────────────────────────────────────────────────────
# Test: Inquiry Mode in Flatline Orchestrator (Task 6.1)
# ─────────────────────────────────────────────────────────

echo "=== Inquiry Mode — Flatline Orchestrator ==="

test_inquiry_mode_accepted() {
    local script="$SCRIPT_DIR/../.claude/scripts/flatline-orchestrator.sh"

    # Check that 'inquiry' is accepted as a valid mode
    if grep -q '"inquiry"' "$script" 2>/dev/null; then
        pass "inquiry mode accepted in flatline-orchestrator.sh"
    else
        fail "inquiry mode not found in flatline-orchestrator.sh"
    fi
}

test_run_inquiry_function_exists() {
    local script="$SCRIPT_DIR/../.claude/scripts/flatline-orchestrator.sh"

    if grep -q 'run_inquiry()' "$script" 2>/dev/null; then
        pass "run_inquiry function defined"
    else
        fail "run_inquiry function not found"
    fi
}

test_inquiry_3_perspectives() {
    local script="$SCRIPT_DIR/../.claude/scripts/flatline-orchestrator.sh"

    local structural historical governance
    structural=$(grep -c 'structural' "$script" 2>/dev/null) || structural=0
    historical=$(grep -c 'historical' "$script" 2>/dev/null) || historical=0
    governance=$(grep -c 'governance' "$script" 2>/dev/null) || governance=0

    if [[ $structural -gt 3 && $historical -gt 3 && $governance -gt 3 ]]; then
        pass "3 perspectives defined (structural=$structural, historical=$historical, governance=$governance)"
    else
        fail "Missing perspectives (structural=$structural, historical=$historical, governance=$governance)"
    fi
}

test_inquiry_parallel_execution() {
    local script="$SCRIPT_DIR/../.claude/scripts/flatline-orchestrator.sh"

    # Check for 3 background call_model invocations with & in run_inquiry
    local bg_count
    bg_count=$(grep -c 'call_model.*review.*&' "$script" 2>/dev/null) || bg_count=0

    # At least 3 should be from run_inquiry (structural, historical, governance)
    if [[ $bg_count -ge 3 ]]; then
        pass "3+ parallel background call_model queries found ($bg_count)"
    else
        fail "Expected 3+ background call_model queries, found $bg_count"
    fi
}

test_inquiry_graceful_fallback() {
    local script="$SCRIPT_DIR/../.claude/scripts/flatline-orchestrator.sh"

    # Check for minimum 2 queries requirement
    if grep -q 'success_count.*-lt 2' "$script" 2>/dev/null; then
        pass "Graceful fallback: minimum 2 queries required"
    else
        fail "Missing graceful fallback for query count"
    fi
}

test_inquiry_output_saved() {
    local script="$SCRIPT_DIR/../.claude/scripts/flatline-orchestrator.sh"

    # Check that inquiry results are saved to flatline directory
    if grep -q 'inquiry.json' "$script" 2>/dev/null; then
        pass "Inquiry output saved to flatline directory"
    else
        fail "Inquiry output not saved to flatline directory"
    fi
}

test_inquiry_content_redaction() {
    local script="$SCRIPT_DIR/../.claude/scripts/flatline-orchestrator.sh"

    # Inquiry uses call_model which has built-in redaction via redact_secrets
    # Check that call_model is invoked with inquiry perspective models
    if grep -q 'call_model "$structural_model"' "$script" 2>/dev/null && \
       grep -q 'call_model "$historical_model"' "$script" 2>/dev/null && \
       grep -q 'call_model "$governance_model"' "$script" 2>/dev/null; then
        pass "Inquiry uses call_model for all 3 perspectives (inherits content redaction)"
    else
        fail "Inquiry does not use call_model for all perspectives"
    fi
}

# ─────────────────────────────────────────────────────────
# Test: Inquiry Integration in Bridge Orchestrator (Task 6.2)
# ─────────────────────────────────────────────────────────

echo ""
echo "=== Inquiry Integration — Bridge Orchestrator ==="

test_inquiry_signal_in_orchestrator() {
    local script="$SCRIPT_DIR/../.claude/scripts/bridge-orchestrator.sh"

    if grep -q "SIGNAL:INQUIRY_MODE" "$script" 2>/dev/null; then
        pass "SIGNAL:INQUIRY_MODE emitted in bridge-orchestrator.sh"
    else
        fail "SIGNAL:INQUIRY_MODE not found in bridge-orchestrator.sh"
    fi
}

test_inquiry_config_gated() {
    local script="$SCRIPT_DIR/../.claude/scripts/bridge-orchestrator.sh"

    if grep -q 'inquiry_enabled' "$script" 2>/dev/null; then
        pass "Inquiry mode is config-gated (inquiry_enabled)"
    else
        fail "Inquiry mode not config-gated"
    fi
}

test_inquiry_cross_repo_context_fed() {
    local script="$SCRIPT_DIR/../.claude/scripts/bridge-orchestrator.sh"

    # Check that cross-repo context is fed to inquiry
    if grep -q 'cross-repo-context.json' "$script" 2>/dev/null; then
        pass "Cross-repo context fed to inquiry mode"
    else
        fail "Cross-repo context not fed to inquiry mode"
    fi
}

test_inquiry_findings_tracked() {
    local script="$SCRIPT_DIR/../.claude/scripts/bridge-orchestrator.sh"

    if grep -q 'inquiry_findings' "$script" 2>/dev/null; then
        pass "Inquiry findings tracked in bridge state"
    else
        fail "Inquiry findings not tracked in bridge state"
    fi
}

# ─────────────────────────────────────────────────────────
# Test: End-to-End Signal Chain (Task 6.4)
# ─────────────────────────────────────────────────────────

echo ""
echo "=== End-to-End Signal Chain ==="

test_full_signal_chain() {
    local orch_script="$SCRIPT_DIR/../.claude/scripts/bridge-orchestrator.sh"

    # All 5 FR signals should be present in the orchestrator
    local signals=("CROSS_REPO_QUERY" "VISION_CHECK" "LORE_REFERENCE_SCAN" "RESEARCH_ITERATION" "INQUIRY_MODE")
    local missing=0

    for sig in "${signals[@]}"; do
        if ! grep -q "SIGNAL:${sig}" "$orch_script" 2>/dev/null; then
            fail "Missing signal: SIGNAL:${sig}"
            missing=$((missing + 1))
        fi
    done

    if [[ $missing -eq 0 ]]; then
        pass "All 5 FR signals present in bridge orchestrator"
    fi
}

test_state_machine_completeness() {
    local state_script="$SCRIPT_DIR/../.claude/scripts/bridge-state.sh"

    # RESEARCHING and EXPLORING should be in transitions
    local states=("RESEARCHING" "EXPLORING")
    local missing=0

    for state in "${states[@]}"; do
        if ! grep -q "\"$state\"" "$state_script" 2>/dev/null; then
            fail "Missing state: $state"
            missing=$((missing + 1))
        fi
    done

    if [[ $missing -eq 0 ]]; then
        pass "State machine includes all inquiry-related states"
    fi
}

test_lifecycle_tracking_integration() {
    local lore_script="$SCRIPT_DIR/../.claude/scripts/lore-discover.sh"

    # Lore lifecycle tracking should be present
    if grep -q 'update_lore_reference' "$lore_script" 2>/dev/null && \
       grep -q 'scan_for_lore_references' "$lore_script" 2>/dev/null; then
        pass "Lore lifecycle tracking functions present (FR-5)"
    else
        fail "Missing lore lifecycle tracking functions"
    fi
}

test_vision_activation_integration() {
    local vision_script="$SCRIPT_DIR/../.claude/scripts/bridge-vision-capture.sh"

    if grep -q 'check_relevant_visions' "$vision_script" 2>/dev/null && \
       grep -q 'extract_pr_tags' "$vision_script" 2>/dev/null; then
        pass "Vision activation functions present (FR-3)"
    else
        fail "Missing vision activation functions"
    fi
}

# ─────────────────────────────────────────────────────────
# Test: Config Schema (Task 6.5)
# ─────────────────────────────────────────────────────────

echo ""
echo "=== Config Schema ==="

test_inquiry_config_exists() {
    local config="$SCRIPT_DIR/../.loa.config.yaml.example"

    if grep -q "inquiry_enabled:" "$config" 2>/dev/null; then
        pass "inquiry_enabled config key exists"
    else
        fail "inquiry_enabled config key missing"
    fi
}

test_all_fr_configs_present() {
    local config="$SCRIPT_DIR/../.loa.config.yaml.example"

    local keys=("cross_repo_query:" "research_mode:" "inquiry_enabled:")
    local missing=0

    for key in "${keys[@]}"; do
        if ! grep -q "$key" "$config" 2>/dev/null; then
            fail "Config key missing: $key"
            missing=$((missing + 1))
        fi
    done

    if [[ $missing -eq 0 ]]; then
        pass "All FR config keys present in .loa.config.yaml.example"
    fi
}

# ─────────────────────────────────────────────────────────
# Run all tests
# ─────────────────────────────────────────────────────────

test_inquiry_mode_accepted
test_run_inquiry_function_exists
test_inquiry_3_perspectives
test_inquiry_parallel_execution
test_inquiry_graceful_fallback
test_inquiry_output_saved
test_inquiry_content_redaction
test_inquiry_signal_in_orchestrator
test_inquiry_config_gated
test_inquiry_cross_repo_context_fed
test_inquiry_findings_tracked
test_full_signal_chain
test_state_machine_completeness
test_lifecycle_tracking_integration
test_vision_activation_integration
test_inquiry_config_exists
test_all_fr_configs_present

echo ""
echo "─────────────────────────────────────"
echo "Results: ${TESTS_RUN} tests, ${TESTS_PASSED} passed, ${TESTS_FAILED} failed"
echo "─────────────────────────────────────"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
