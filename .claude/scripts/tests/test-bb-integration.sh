#!/usr/bin/env bash
# test-bb-integration.sh — Integration test for _phase_bb_fix_loop
# Scenario: 1-iteration FLATLINE convergence (3 of 4 findings resolved).
# Usage: bash test-bb-integration.sh
# Exit: 0 on all pass, 1 on any failure

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="$(dirname "$SCRIPT_DIR")/spiral-harness.sh"

PASS_COUNT=0
FAIL_COUNT=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# ── Mock Tool Directory ────────────────────────────────────────────────────
MOCK_BIN="$TEST_TMPDIR/mock-bin"
mkdir -p "$MOCK_BIN"

# Mock bridge-findings-parser.sh
# Call 1 (initial, iter 1): F001 HIGH, F002 MEDIUM@0.9, F003 MEDIUM@0.8, F004 PRAISE
# Call 2+ (re-review): empty
PARSER_COUNT="$TEST_TMPDIR/parser-count"
echo "0" > "$PARSER_COUNT"
mkdir -p "$TEST_TMPDIR/bin"
cat > "$TEST_TMPDIR/bin/bridge-findings-parser.sh" << 'PARSEREOF'
#!/usr/bin/env bash
INPUT=""; OUTPUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in --input) INPUT="$2"; shift 2 ;; --output) OUTPUT="$2"; shift 2 ;; *) shift ;; esac
done
PCFILE="PCFILE_PLACEHOLDER"
c=$(cat "$PCFILE" 2>/dev/null || echo "0"); c=$((c + 1)); echo "$c" > "$PCFILE"
case "$c" in
  1) printf '{"schema_version":2,"findings":[{"id":"F001","severity":"HIGH","confidence":0.9,"file":"a.sh","title":"H","description":"x","suggestion":"fix","weight":5},{"id":"F002","severity":"MEDIUM","confidence":0.9,"file":"b.sh","title":"M","description":"x","suggestion":"fix","weight":3},{"id":"F003","severity":"MEDIUM","confidence":0.8,"file":"c.sh","title":"M2","description":"x","suggestion":"fix","weight":3},{"id":"F004","severity":"PRAISE","confidence":1.0,"file":"","title":"Nice","description":"nice","suggestion":"","weight":0}],"total":4}' > "$OUTPUT" ;;
  *) printf '{"schema_version":2,"findings":[],"total":0}' > "$OUTPUT" ;;
esac
exit 0
PARSEREOF
sed -i "s|PCFILE_PLACEHOLDER|$PARSER_COUNT|g" "$TEST_TMPDIR/bin/bridge-findings-parser.sh"
chmod +x "$TEST_TMPDIR/bin/bridge-findings-parser.sh"

# Mock claude: returns cost=0.25
cat > "$MOCK_BIN/claude" << 'CLAUDEEOF'
#!/usr/bin/env bash
printf '{"cost_usd": 0.25, "result": "Fixed."}'
exit 0
CLAUDEEOF
chmod +x "$MOCK_BIN/claude"

# Mock gh pr comment
cat > "$MOCK_BIN/gh" << 'GHEOF'
#!/usr/bin/env bash
echo "PR comment posted"
exit 0
GHEOF
chmod +x "$MOCK_BIN/gh"

# Mock git
cat > "$MOCK_BIN/git" << 'GITEOF'
#!/usr/bin/env bash
if [[ "${1:-} ${2:-} ${3:-}" == "rev-parse --abbrev-ref HEAD" ]]; then
    echo "feat/test-bb"
elif [[ "${1:-}" == "push" ]]; then
    echo "pushed"
else
    command git "$@" 2>/dev/null || true
fi
exit 0
GITEOF
chmod +x "$MOCK_BIN/git"

# Mock entry.sh: always produces empty review (FLATLINE after first fix cycle)
mkdir -p "$TEST_TMPDIR/skills/bridgebuilder-review/resources"
cat > "$TEST_TMPDIR/skills/bridgebuilder-review/resources/entry.sh" << 'ENTRYEOF'
#!/usr/bin/env bash
echo "No findings."
exit 0
ENTRYEOF
chmod +x "$TEST_TMPDIR/skills/bridgebuilder-review/resources/entry.sh"

# Mock post-pr-triage.sh: always returns FLATLINE
cat > "$TEST_TMPDIR/bin/post-pr-triage.sh" << 'TRIAGEEOF'
#!/usr/bin/env bash
CWD_AT_INVOKE="$(pwd)"
mkdir -p "$CWD_AT_INVOKE/.run"
printf '{"state":"FLATLINE","ts":"%s"}' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    > "$CWD_AT_INVOKE/.run/bridge-triage-convergence.json"
exit 0
TRIAGEEOF
chmod +x "$TEST_TMPDIR/bin/post-pr-triage.sh"

# ── Test Environment Setup ─────────────────────────────────────────────────
export PATH="$MOCK_BIN:$PATH"

PROJECT_ROOT="$TEST_TMPDIR"
EVIDENCE_DIR="$TEST_TMPDIR/evidence"
CYCLE_DIR="$TEST_TMPDIR"
BRANCH="feat/test-bb"
EXECUTOR_MODEL="sonnet"
BB_FIX_BUDGET="3"
TOTAL_BUDGET="10"
BB_MAX_ITERATIONS="3"
_BB_SPEND_USD="0"
_BB_CURRENT_ITER=1
_BB_STUCK_IDS=()
_BB_PREV_ACTIONABLE_IDS=()
_BB_ACTIONABLE_IDS=()
_BB_ACTIONABLE_JSON="[]"
_BB_NONACTIONABLE_JSON="[]"
_BB_RESOLVED_IDS=()
_BB_REMAINING_IDS=()
_FLIGHT_RECORDER="$TEST_TMPDIR/flight-recorder.jsonl"
touch "$_FLIGHT_RECORDER"
mkdir -p "$EVIDENCE_DIR" "$TEST_TMPDIR/.run"
SCRIPT_DIR="$TEST_TMPDIR/bin"

log() { echo "[test] $*" >&2; }
_check_budget() { return 0; }  # budget always ok in integration test
_record_action() {
    printf '{"phase":"%s","actor":"%s","action":"%s","verdict":"%s"}\n' \
        "$1" "$2" "$3" "${10:-}" >> "$_FLIGHT_RECORDER"
}

# Write initial BB review fixture (cycle-073 representative)
cat > "$EVIDENCE_DIR/bb-review-iter-1.md" << 'FIXEOF'
# Bridgebuilder Review — Cycle-073 Fixture

## Finding F001
Severity: HIGH
Confidence: 0.9
File: .claude/scripts/spiral-harness.sh
Description: High severity issue requiring immediate fix

## Finding F002
Severity: MEDIUM
Confidence: 0.9
File: .claude/scripts/spiral-evidence.sh
Description: Medium severity issue

## Finding F003
Severity: MEDIUM
Confidence: 0.8
File: .claude/scripts/bridge-findings-parser.sh
Description: Another medium severity issue

## Finding F004
Severity: PRAISE
File:
Description: Well-structured error handling
FIXEOF

# Extract and source BB functions
BB_FUNCS_FILE="$TEST_TMPDIR/bb-funcs.sh"
python3 -c "
with open('$HARNESS') as f:
    content = f.read()
start = content.find('# BB Fix Loop — Supporting Functions')
end = content.find('# =============================================================================\n# Main Pipeline', start)
with open('$BB_FUNCS_FILE', 'w') as out:
    out.write(content[start:end])
"
# shellcheck source=/dev/null
source "$BB_FUNCS_FILE"

# ── Run Integration Test ───────────────────────────────────────────────────
echo ""
echo "=== Integration Test: 1-iteration FLATLINE convergence ==="
echo ""

# cd to PROJECT_ROOT so post-pr-triage.sh CWD_AT_INVOKE matches PROJECT_ROOT
cd "$TEST_TMPDIR"
_phase_bb_fix_loop "42" 2>/dev/null

echo ""
echo "--- Assertions ---"

# AC1: BB_LOOP_COMPLETE with reason=convergence
loop_complete_line=$(grep '"BB_LOOP_COMPLETE"' "$_FLIGHT_RECORDER" 2>/dev/null || true)
if [[ -n "$loop_complete_line" ]] && echo "$loop_complete_line" | grep -q "convergence"; then
    pass "AC1: BB_LOOP_COMPLETE with reason=convergence"
else
    fail "AC1: missing convergence in BB_LOOP_COMPLETE (recorder: $loop_complete_line)"
fi

# AC2: _BB_RESOLVED_IDS contains at least F001, F002, F003
resolved_count=0
for id in ${_BB_RESOLVED_IDS[@]+"${_BB_RESOLVED_IDS[@]}"}; do
    resolved_count=$((resolved_count + 1))
done
[[ "$resolved_count" -ge 3 ]] \
    && pass "AC2: _BB_RESOLVED_IDS has ≥3 findings (got $resolved_count: ${_BB_RESOLVED_IDS[*]+"${_BB_RESOLVED_IDS[*]}"})" \
    || fail "AC2: expected ≥3 resolved, got $resolved_count: ${_BB_RESOLVED_IDS[*]:-none}"

# AC3: Iterations ≤ 3
[[ "$_BB_CURRENT_ITER" -le 3 ]] \
    && pass "AC3: Iterations ≤ 3 (ran $_BB_CURRENT_ITER)" \
    || fail "AC3: Too many iterations: $_BB_CURRENT_ITER"

# AC4: Spend ≤ $3.0
spend_ok=$(echo "${_BB_SPEND_USD:-0} <= 3.0" | bc 2>/dev/null || echo "1")
[[ "$spend_ok" -eq 1 ]] \
    && pass "AC4: Spend ≤ \$3.0 (spent \$${_BB_SPEND_USD:-0})" \
    || fail "AC4: Over budget: \$${_BB_SPEND_USD:-0}"

# AC5: Required event types present
declare -a REQUIRED_EVENTS=("BB_FIX_CYCLE_START" "BB_FIX_CYCLE_COMPLETE" "BB_REREVIEW" "BB_CONVERGENCE" "BB_LOOP_COMPLETE")
all_ok=true
for ev in "${REQUIRED_EVENTS[@]}"; do
    if grep -q "\"$ev\"" "$_FLIGHT_RECORDER" 2>/dev/null; then
        : # present
    else
        fail "AC5: Missing event: $ev"
        all_ok=false
    fi
done
[[ "$all_ok" == "true" ]] && pass "AC5: All 5 required event types present"

# AC6: Final PR comment posted
grep -q '"BB_POST_COMMENT"' "$_FLIGHT_RECORDER" 2>/dev/null \
    && pass "AC6: Final PR comment posted" \
    || fail "AC6: No BB_POST_COMMENT recorded"

# AC7: No stuck findings (FLATLINE before any iteration can repeat)
sc=0
for s in ${_BB_STUCK_IDS[@]+"${_BB_STUCK_IDS[@]}"}; do sc=$((sc + 1)); done
[[ "$sc" -eq 0 ]] \
    && pass "AC7: No stuck findings" \
    || fail "AC7: Unexpected stuck findings: ${_BB_STUCK_IDS[*]}"

echo ""
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo ""
[[ "$FAIL_COUNT" -eq 0 ]]
