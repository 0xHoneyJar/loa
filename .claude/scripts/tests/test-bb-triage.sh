#!/usr/bin/env bash
# test-bb-triage.sh — Unit tests for _bb_triage_findings and _bb_detect_stuck_findings
# Usage: bash test-bb-triage.sh
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

# Extract BB functions from harness (between markers)
BB_FUNCS_FILE="$TEST_TMPDIR/bb-funcs.sh"
python3 -c "
import sys
with open('$HARNESS') as f:
    content = f.read()
start = content.find('# BB Fix Loop — Supporting Functions')
end = content.find('# =============================================================================\n# Main Pipeline', start)
with open('$BB_FUNCS_FILE', 'w') as out:
    out.write(content[start:end])
" 2>/dev/null || {
    echo "ERROR: Failed to extract BB functions from harness"
    exit 1
}

# Provide stubs for harness dependencies, then source BB functions
PROJECT_ROOT="$TEST_TMPDIR"
EVIDENCE_DIR="$TEST_TMPDIR/evidence"
CYCLE_DIR="$TEST_TMPDIR"
BRANCH="feat/test"
EXECUTOR_MODEL="sonnet"
BB_FIX_BUDGET="3"
BB_MAX_ITERATIONS="3"
_BB_SPEND_USD="0"
_BB_CURRENT_ITER=1
_BB_STUCK_IDS=()
_BB_PREV_ACTIONABLE_IDS=()
_BB_ACTIONABLE_IDS=()
_BB_ACTIONABLE_JSON="[]"
_FLIGHT_RECORDER="$TEST_TMPDIR/flight-recorder.jsonl"
touch "$_FLIGHT_RECORDER"
mkdir -p "$EVIDENCE_DIR" "$TEST_TMPDIR/.run"

log() { : ; }
_record_action() {
    echo "{\"phase\":\"$1\",\"actor\":\"$2\",\"action\":\"$3\",\"verdict\":\"${10:-}\"}" \
        >> "$_FLIGHT_RECORDER"
}

# shellcheck source=/dev/null
source "$BB_FUNCS_FILE"

wf() { printf '%s\n' "$2" > "$1"; }  # write findings

# ── _bb_triage_findings ────────────────────────────────────────────────────
echo ""
echo "=== _bb_triage_findings ==="
echo ""

# TC-T1: CRITICAL confidence=0.1 → actionable
wf "$TEST_TMPDIR/t1.json" '{"findings":[{"id":"F001","severity":"CRITICAL","confidence":0.1,"file":"a.sh","title":"x","description":"x","suggestion":"x","weight":5}],"total":1}'
_BB_ACTIONABLE_IDS=()
_bb_triage_findings "$TEST_TMPDIR/t1.json"
[[ ${#_BB_ACTIONABLE_IDS[@]} -eq 1 && "${_BB_ACTIONABLE_IDS[0]:-}" == "F001" ]] \
    && pass "TC-T1: CRITICAL confidence=0.1 → actionable" \
    || fail "TC-T1: got ids=${_BB_ACTIONABLE_IDS[*]:-none}"

# TC-T2: HIGH no confidence → actionable
wf "$TEST_TMPDIR/t2.json" '{"findings":[{"id":"F002","severity":"HIGH","file":"b.sh","title":"x","description":"x","suggestion":"x","weight":5}],"total":1}'
_BB_ACTIONABLE_IDS=()
_bb_triage_findings "$TEST_TMPDIR/t2.json"
[[ ${#_BB_ACTIONABLE_IDS[@]} -eq 1 && "${_BB_ACTIONABLE_IDS[0]:-}" == "F002" ]] \
    && pass "TC-T2: HIGH no confidence → actionable" \
    || fail "TC-T2: got ids=${_BB_ACTIONABLE_IDS[*]:-none}"

# TC-T3: MEDIUM confidence=0.8 → actionable
wf "$TEST_TMPDIR/t3.json" '{"findings":[{"id":"F003","severity":"MEDIUM","confidence":0.8,"file":"c.sh","title":"x","description":"x","suggestion":"x","weight":3}],"total":1}'
_BB_ACTIONABLE_IDS=()
_bb_triage_findings "$TEST_TMPDIR/t3.json"
[[ ${#_BB_ACTIONABLE_IDS[@]} -eq 1 && "${_BB_ACTIONABLE_IDS[0]:-}" == "F003" ]] \
    && pass "TC-T3: MEDIUM confidence=0.8 → actionable" \
    || fail "TC-T3: got ids=${_BB_ACTIONABLE_IDS[*]:-none}"

# TC-T4: MEDIUM confidence=0.7 → non-actionable
wf "$TEST_TMPDIR/t4.json" '{"findings":[{"id":"F004","severity":"MEDIUM","confidence":0.7,"file":"d.sh","title":"x","description":"x","suggestion":"x","weight":3}],"total":1}'
_BB_ACTIONABLE_IDS=()
_bb_triage_findings "$TEST_TMPDIR/t4.json"
[[ ${#_BB_ACTIONABLE_IDS[@]} -eq 0 ]] \
    && pass "TC-T4: MEDIUM confidence=0.7 → non-actionable" \
    || fail "TC-T4: should be non-actionable, got ${_BB_ACTIONABLE_IDS[*]}"

# TC-T5: MEDIUM no confidence → actionable (default 1.0)
wf "$TEST_TMPDIR/t5.json" '{"findings":[{"id":"F005","severity":"MEDIUM","file":"e.sh","title":"x","description":"x","suggestion":"x","weight":3}],"total":1}'
_BB_ACTIONABLE_IDS=()
_bb_triage_findings "$TEST_TMPDIR/t5.json"
[[ ${#_BB_ACTIONABLE_IDS[@]} -eq 1 && "${_BB_ACTIONABLE_IDS[0]:-}" == "F005" ]] \
    && pass "TC-T5: MEDIUM no confidence → actionable" \
    || fail "TC-T5: got ids=${_BB_ACTIONABLE_IDS[*]:-none}"

# TC-T6: LOW confidence=0.9 → non-actionable, in lore candidates
LORE="$TEST_TMPDIR/.run/bridge-lore-candidates.jsonl"
rm -f "$LORE"
wf "$TEST_TMPDIR/t6.json" '{"findings":[{"id":"F006","severity":"LOW","confidence":0.9,"file":"f.sh","title":"x","description":"x","suggestion":"x","weight":1}],"total":1}'
_BB_ACTIONABLE_IDS=()
_bb_triage_findings "$TEST_TMPDIR/t6.json"
in_lore=false; [[ -f "$LORE" ]] && grep -q '"F006"' "$LORE" 2>/dev/null && in_lore=true
[[ ${#_BB_ACTIONABLE_IDS[@]} -eq 0 && "$in_lore" == "true" ]] \
    && pass "TC-T6: LOW → non-actionable, in lore candidates" \
    || fail "TC-T6: actionable=${#_BB_ACTIONABLE_IDS[@]} in_lore=$in_lore"

# TC-T7: PRAISE → non-actionable, in lore candidates
rm -f "$LORE"
wf "$TEST_TMPDIR/t7.json" '{"findings":[{"id":"F007","severity":"PRAISE","confidence":1.0,"file":"","title":"Great","description":"nice","suggestion":"","weight":0}],"total":1}'
_BB_ACTIONABLE_IDS=()
_bb_triage_findings "$TEST_TMPDIR/t7.json"
in_lore=false; [[ -f "$LORE" ]] && grep -q '"F007"' "$LORE" 2>/dev/null && in_lore=true
[[ ${#_BB_ACTIONABLE_IDS[@]} -eq 0 && "$in_lore" == "true" ]] \
    && pass "TC-T7: PRAISE → non-actionable, in lore candidates" \
    || fail "TC-T7: actionable=${#_BB_ACTIONABLE_IDS[@]} in_lore=$in_lore"

# TC-T8: VISION → non-actionable, NOT in lore candidates
rm -f "$LORE"
wf "$TEST_TMPDIR/t8.json" '{"findings":[{"id":"F008","severity":"VISION","confidence":0.9,"file":"","title":"v","description":"future","suggestion":"","weight":0}],"total":1}'
_BB_ACTIONABLE_IDS=()
_bb_triage_findings "$TEST_TMPDIR/t8.json"
in_lore=false; [[ -f "$LORE" ]] && grep -q '"F008"' "$LORE" 2>/dev/null && in_lore=true
[[ ${#_BB_ACTIONABLE_IDS[@]} -eq 0 && "$in_lore" == "false" ]] \
    && pass "TC-T8: VISION → non-actionable, NOT in lore" \
    || fail "TC-T8: actionable=${#_BB_ACTIONABLE_IDS[@]} in_lore=$in_lore"

# TC-T9: Missing 'findings' key → graceful
wf "$TEST_TMPDIR/t9.json" '{"schema_version":2,"total":0}'
_BB_ACTIONABLE_IDS=()
rc=0; _bb_triage_findings "$TEST_TMPDIR/t9.json" || rc=$?
[[ ${#_BB_ACTIONABLE_IDS[@]} -eq 0 && "$rc" -eq 0 ]] \
    && pass "TC-T9: Missing findings key → empty, return 0" \
    || fail "TC-T9: ids=${#_BB_ACTIONABLE_IDS[@]} rc=$rc"

# TC-T10: Non-existent file → graceful
_BB_ACTIONABLE_IDS=()
rc=0; _bb_triage_findings "/tmp/nonexistent-$$-x.json" || rc=$?
[[ ${#_BB_ACTIONABLE_IDS[@]} -eq 0 && "$rc" -eq 0 ]] \
    && pass "TC-T10: Non-existent file → empty, return 0" \
    || fail "TC-T10: ids=${#_BB_ACTIONABLE_IDS[@]} rc=$rc"

# ── _bb_detect_stuck_findings ──────────────────────────────────────────────
echo ""
echo "=== _bb_detect_stuck_findings ==="
echo ""

# TC-S1: F001 in prev + current → stuck, event emitted
> "$_FLIGHT_RECORDER"
_BB_PREV_ACTIONABLE_IDS=("F001")
_BB_ACTIONABLE_IDS=("F001" "F002")
_BB_STUCK_IDS=()
_BB_CURRENT_ITER=2
_BB_ACTIONABLE_JSON='[{"id":"F001","severity":"HIGH"},{"id":"F002","severity":"MEDIUM"}]'
_bb_detect_stuck_findings
sc=0; for s in ${_BB_STUCK_IDS[@]+"${_BB_STUCK_IDS[@]}"}; do sc=$((sc+1)); done
ev=$(grep -c 'BB_FINDING_STUCK' "$_FLIGHT_RECORDER" 2>/dev/null || echo "0")
[[ "$sc" -eq 1 && "${_BB_STUCK_IDS[0]:-}" == "F001" && "$ev" -ge 1 ]] \
    && pass "TC-S1: F001 prev+current → stuck, event emitted" \
    || fail "TC-S1: stuck_count=$sc ids=${_BB_STUCK_IDS[*]:-none} events=$ev"

# TC-S2: F002 current only → not stuck
> "$_FLIGHT_RECORDER"
_BB_PREV_ACTIONABLE_IDS=("F001")
_BB_ACTIONABLE_IDS=("F002")
_BB_STUCK_IDS=()
_BB_CURRENT_ITER=2
_BB_ACTIONABLE_JSON='[{"id":"F002","severity":"MEDIUM"}]'
_bb_detect_stuck_findings
sc=0; for s in ${_BB_STUCK_IDS[@]+"${_BB_STUCK_IDS[@]}"}; do sc=$((sc+1)); done
[[ "$sc" -eq 0 ]] \
    && pass "TC-S2: F002 current only → not stuck" \
    || fail "TC-S2: expected 0 stuck, got stuck=${_BB_STUCK_IDS[*]}"

# TC-S3: F001 already in _BB_STUCK_IDS → no duplicate event
> "$_FLIGHT_RECORDER"
_BB_PREV_ACTIONABLE_IDS=("F001")
_BB_ACTIONABLE_IDS=("F001")
_BB_STUCK_IDS=("F001")
_BB_CURRENT_ITER=3
_BB_ACTIONABLE_JSON='[{"id":"F001","severity":"HIGH"}]'
_bb_detect_stuck_findings
ev=$(grep -c 'BB_FINDING_STUCK' "$_FLIGHT_RECORDER" 2>/dev/null || true)
ev="${ev:-0}"
[[ "$ev" -eq 0 ]] \
    && pass "TC-S3: already stuck → no duplicate event" \
    || fail "TC-S3: expected 0 new events, got $ev"

# TC-S4: Empty prev IDs → no stuck
> "$_FLIGHT_RECORDER"
_BB_PREV_ACTIONABLE_IDS=()
_BB_ACTIONABLE_IDS=("F001" "F002")
_BB_STUCK_IDS=()
_BB_CURRENT_ITER=1
_BB_ACTIONABLE_JSON='[{"id":"F001","severity":"HIGH"},{"id":"F002","severity":"MEDIUM"}]'
_bb_detect_stuck_findings
sc=0; for s in ${_BB_STUCK_IDS[@]+"${_BB_STUCK_IDS[@]}"}; do sc=$((sc+1)); done
ev=$(grep -c 'BB_FINDING_STUCK' "$_FLIGHT_RECORDER" 2>/dev/null || true)
ev="${ev:-0}"
[[ "$sc" -eq 0 && "$ev" -eq 0 ]] \
    && pass "TC-S4: empty prev → no stuck, no events" \
    || fail "TC-S4: stuck=$sc events=$ev"


# ── _bb_track_resolved_incremental ────────────────────────────────────────────
echo ""
echo "=== _bb_track_resolved_incremental ==="
echo ""

# TC-R1: multi-iteration incremental resolved tracking
_BB_PREV_ACTIONABLE_IDS=()
_BB_ACTIONABLE_IDS=()
_BB_RESOLVED_IDS=()

# Transition: iter1 [F001,F002,F003] -> iter2 [F002]
_BB_PREV_ACTIONABLE_IDS=(F001 F002 F003)
_BB_ACTIONABLE_IDS=(F002)
_bb_track_resolved_incremental

r1_ok=true
[[ " ${_BB_RESOLVED_IDS[*]:-} " == *" F001 "* ]] || { r1_ok=false; }
[[ " ${_BB_RESOLVED_IDS[*]:-} " == *" F003 "* ]] || { r1_ok=false; }
[[ " ${_BB_RESOLVED_IDS[*]:-} " != *" F002 "* ]] || { r1_ok=false; }

# Transition: iter2 [F002] -> iter3 []
_BB_PREV_ACTIONABLE_IDS=(F002)
_BB_ACTIONABLE_IDS=()
_bb_track_resolved_incremental

[[ " ${_BB_RESOLVED_IDS[*]:-} " == *" F001 "* ]] || { r1_ok=false; }
[[ " ${_BB_RESOLVED_IDS[*]:-} " == *" F002 "* ]] || { r1_ok=false; }
[[ " ${_BB_RESOLVED_IDS[*]:-} " == *" F003 "* ]] || { r1_ok=false; }
[[ ${#_BB_RESOLVED_IDS[@]} -eq 3 ]] || { r1_ok=false; }

"$r1_ok"     && pass "TC-R1: multi-iteration incremental resolved tracking"     || fail "TC-R1: resolved=${_BB_RESOLVED_IDS[*]:-none} count=${#_BB_RESOLVED_IDS[@]}"

# ── pre-dispatch budget gate ──────────────────────────────────────────────────
echo ""
echo "=== pre-dispatch budget gate ==="
echo ""

# TC-B1: pre-dispatch budget gate — no claude when budget exhausted
TOTAL_BUDGET="1.00"
_get_cumulative_cost() { echo "1.50"; }
_check_budget() {
    local max_budget="$1"
    local spent; spent=$(_get_cumulative_cost)
    [[ $(echo "$spent >= $max_budget" | bc 2>/dev/null || echo 0) -eq 1 ]] && return 1 || return 0
}
_claude_was_called=0
claude() { _claude_was_called=1; return 0; }
_BB_ACTIONABLE_JSON='[{"id":"F001","severity":"HIGH","confidence":0.9,"file":"a.sh","title":"H","description":"x","suggestion":"fix","weight":5}]'
dispatch_rc=0
_bb_dispatch_fix_cycle 1 2>/dev/null || dispatch_rc=$?
[[ "$dispatch_rc" -ne 0 && "$_claude_was_called" -eq 0 ]] \
    && pass "TC-B1: pre-dispatch budget gate — non-zero return and claude not invoked" \
    || fail "TC-B1: expected non-zero return (got $dispatch_rc) and no claude (was_called=$_claude_was_called)"

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo ""
[[ "$FAIL_COUNT" -eq 0 ]]
