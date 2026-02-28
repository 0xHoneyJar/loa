#!/usr/bin/env bash
# =============================================================================
# flatline-3model.sh — Integration test for 3-model Flatline (Opus+GPT+Gemini)
# =============================================================================
# Version: 1.0.0
# Part of: Review Pipeline Hardening (cycle-045, FR-1)
#
# Verifies that when tertiary model is configured, Flatline output includes
# tertiary_model_used and tertiary_status fields.
#
# Exit codes:
#   0 - PASS or SKIP
#   1 - FAIL
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FLATLINE="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"

# =============================================================================
# Test Utilities
# =============================================================================

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
skip() { echo "SKIP: $*"; exit 0; }

# =============================================================================
# Pre-flight
# =============================================================================

# Check for required API keys
if [[ -z "${GOOGLE_API_KEY:-}" ]]; then
    skip "GOOGLE_API_KEY not set (integration test requires Gemini API access)"
fi

if [[ -z "${ANTHROPIC_API_KEY:-}" ]] && [[ -z "${OPENAI_API_KEY:-}" ]]; then
    skip "Neither ANTHROPIC_API_KEY nor OPENAI_API_KEY set"
fi

# Check flatline orchestrator exists
if [[ ! -x "$FLATLINE" ]]; then
    fail "flatline-orchestrator.sh not found or not executable at: $FLATLINE"
fi

# Check tertiary model is configured
tertiary_model=""
if command -v yq &> /dev/null; then
    tertiary_model=$(yq -r '.flatline_protocol.models.tertiary // ""' "$PROJECT_ROOT/.loa.config.yaml" 2>/dev/null || echo "")
fi

if [[ -z "$tertiary_model" ]]; then
    skip "flatline_protocol.models.tertiary not configured in .loa.config.yaml"
fi

# =============================================================================
# Test: 3-model Flatline output fields
# =============================================================================

# Create minimal test document
TEST_DOC=$(mktemp)
cat > "$TEST_DOC" << 'EOF'
# Test PRD

## Problem Statement
This is a minimal test document for 3-model Flatline verification.

## Requirements
- FR-1: Basic functionality
EOF

echo "Running 3-model Flatline with tertiary: $tertiary_model ..."

output=$("$FLATLINE" --doc "$TEST_DOC" --phase prd --json 2>/dev/null) || {
    rm -f "$TEST_DOC"
    fail "Flatline orchestrator failed (exit $?)"
}
rm -f "$TEST_DOC"

# Validate output is JSON
if ! echo "$output" | jq '.' > /dev/null 2>&1; then
    fail "Flatline output is not valid JSON"
fi

# Check tertiary_model_used field
tertiary_used=$(echo "$output" | jq -r '.tertiary_model_used // "MISSING"')
if [[ "$tertiary_used" == "MISSING" ]]; then
    fail "Output missing tertiary_model_used field"
fi

if [[ "$tertiary_used" == "null" ]]; then
    fail "tertiary_model_used is null despite tertiary model being configured"
fi

pass "tertiary_model_used present: $tertiary_used"

# Check tertiary_status field
tertiary_status=$(echo "$output" | jq -r '.tertiary_status // "MISSING"')
if [[ "$tertiary_status" == "MISSING" ]]; then
    fail "Output missing tertiary_status field"
fi

if [[ "$tertiary_status" != "active" ]]; then
    fail "Expected tertiary_status=active, got: $tertiary_status"
fi

pass "tertiary_status: $tertiary_status"

# Check model count (if present) — .models may be a number or object
models_raw=$(echo "$output" | jq -r 'if (.models | type) == "number" then .models else 0 end')
if [[ "$models_raw" -eq 3 ]]; then
    pass "Model count: 3"
elif [[ "$models_raw" -eq 0 ]]; then
    echo "INFO: models field not present or not numeric (non-critical)"
else
    fail "Expected 3 models, got $models_raw"
fi

echo ""
echo "ALL TESTS PASSED — 3-model Flatline verified"
