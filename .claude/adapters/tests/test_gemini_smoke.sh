#!/usr/bin/env bash
# =============================================================================
# test_gemini_smoke.sh - Smoke test for Google Gemini API integration
# =============================================================================
# Tests dry-run, mock mode, and optionally live API for Gemini models.
#
# Usage:
#   bash .claude/adapters/tests/test_gemini_smoke.sh
#
# Environment:
#   GOOGLE_API_KEY    Set for live API tests (optional)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ADAPTER="$PROJECT_ROOT/.claude/scripts/model-adapter.sh.legacy"

passed=0
failed=0
total=0

# Create temp input file
INPUT_FILE=$(mktemp)
trap "rm -f '$INPUT_FILE'" EXIT
cat > "$INPUT_FILE" <<'EOF'
# Test Document

This is a test document for Gemini smoke testing.

## Requirements
- Feature A: Must support JSON output
- Feature B: Must handle errors gracefully
EOF

run_test() {
    local name="$1"
    shift
    total=$((total + 1))
    echo -n "  TEST $total: $name ... "
    local output exit_code=0
    output=$("$@" 2>/dev/null) || exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        passed=$((passed + 1))
        echo "PASS"
    else
        failed=$((failed + 1))
        echo "FAIL (exit $exit_code)"
        echo "    Output: ${output:0:200}"
    fi
}

run_test_json() {
    local name="$1"
    shift
    total=$((total + 1))
    echo -n "  TEST $total: $name ... "
    local output exit_code=0
    output=$("$@" 2>/dev/null) || exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        failed=$((failed + 1))
        echo "FAIL (exit $exit_code)"
        return
    fi
    # Validate JSON
    if echo "$output" | jq empty 2>/dev/null; then
        passed=$((passed + 1))
        echo "PASS"
    else
        failed=$((failed + 1))
        echo "FAIL (invalid JSON)"
        echo "    Output: ${output:0:200}"
    fi
}

echo "═══════════════════════════════════════════════════════════"
echo "  Gemini Integration Smoke Test"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ── Dry Run Tests ────────────────────────────────────────────
echo "Dry Run Tests:"
run_test_json "gemini-2.5-flash dry run" \
    bash "$ADAPTER" --model gemini-2.5-flash --mode review --input "$INPUT_FILE" --dry-run

run_test_json "gemini-2.5-pro dry run" \
    bash "$ADAPTER" --model gemini-2.5-pro --mode review --input "$INPUT_FILE" --dry-run

run_test_json "gemini-2.0 dry run (backward compat)" \
    bash "$ADAPTER" --model gemini-2.0 --mode review --input "$INPUT_FILE" --dry-run

echo ""

# ── Mock Mode Tests ──────────────────────────────────────────
echo "Mock Mode Tests:"
export FLATLINE_MOCK_MODE=true

run_test_json "gemini-2.5-flash review (mock)" \
    bash "$ADAPTER" --model gemini-2.5-flash --mode review --input "$INPUT_FILE"

run_test_json "gemini-2.5-flash skeptic (mock)" \
    bash "$ADAPTER" --model gemini-2.5-flash --mode skeptic --input "$INPUT_FILE"

run_test_json "gemini-2.5-flash score (mock)" \
    bash "$ADAPTER" --model gemini-2.5-flash --mode score --input "$INPUT_FILE"

run_test_json "gemini-2.5-flash dissent (mock)" \
    bash "$ADAPTER" --model gemini-2.5-flash --mode dissent --input "$INPUT_FILE"

run_test_json "gemini-2.5-pro review (mock, multi-part)" \
    bash "$ADAPTER" --model gemini-2.5-pro --mode review --input "$INPUT_FILE"

# BB-201: Test blocked-response fixture (SAFETY finishReason handling)
# Use a temp mock dir where the "review" fixture contains blocked-response content
# so the adapter loads it through normal --mode review path
total=$((total + 1))
echo -n "  TEST $total: gemini-2.5-flash blocked response (mock) ... "
BLOCKED_MOCK_DIR=$(mktemp -d)
trap "rm -f '$INPUT_FILE'; rm -rf '$BLOCKED_MOCK_DIR'" EXIT
cp "$PROJECT_ROOT/tests/fixtures/api-responses/gemini-2.5-flash-blocked-response.json" \
   "$BLOCKED_MOCK_DIR/gemini-2.5-flash-review-response.json"
FLATLINE_MOCK_DIR="$BLOCKED_MOCK_DIR" \
    output=$(bash "$ADAPTER" --model gemini-2.5-flash --mode review --input "$INPUT_FILE" 2>&1) || true
# The adapter should detect SAFETY finishReason and return empty content
if echo "$output" | jq -e '.content == "" or .content == null' >/dev/null 2>&1; then
    passed=$((passed + 1))
    echo "PASS"
else
    failed=$((failed + 1))
    echo "FAIL (blocked response not detected — content was non-empty)"
    echo "    Output: ${output:0:200}"
fi

unset FLATLINE_MOCK_MODE

echo ""

# ── Live API Tests (conditional) ─────────────────────────────
if [[ -n "${GOOGLE_API_KEY:-}" ]]; then
    echo "Live API Tests (GOOGLE_API_KEY detected):"

    total=$((total + 1))
    echo -n "  TEST $total: gemini-2.5-flash live review ... "
    output=$(bash "$ADAPTER" --model gemini-2.5-flash --mode review \
        --input "$INPUT_FILE" --timeout 30 2>/dev/null) || {
        failed=$((failed + 1))
        echo "FAIL (API call failed)"
        output=""
    }
    if [[ -n "$output" ]]; then
        content=$(echo "$output" | jq -r '.content // empty' 2>/dev/null)
        tokens_in=$(echo "$output" | jq -r '.tokens_input // 0' 2>/dev/null)
        tokens_out=$(echo "$output" | jq -r '.tokens_output // 0' 2>/dev/null)
        if [[ -n "$content" && "$tokens_in" -gt 0 && "$tokens_out" -gt 0 ]]; then
            passed=$((passed + 1))
            echo "PASS (in:${tokens_in} out:${tokens_out})"
        else
            failed=$((failed + 1))
            echo "FAIL (empty content or zero tokens)"
        fi
    fi
    echo ""
else
    echo "Live API Tests: SKIPPED (no GOOGLE_API_KEY)"
    echo ""
fi

# ── Summary ──────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════"
echo "  Results: $passed passed, $failed failed (of $total)"
echo "═══════════════════════════════════════════════════════════"

if [[ $failed -gt 0 ]]; then
    exit 1
fi
exit 0
