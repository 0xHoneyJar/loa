#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-baseline-capture.bats
#
# cycle-109 Sprint 1 T1.10 — baseline-capture script (PRD §3.4 IMP-003).
#
# Emits 7 baseline artifacts to a TRACKED grimoires/.../baselines/ dir
# so cycle-110 can retrospectively compare cycle-109 outcomes:
#
#   1. issue-counts.json          OPEN substrate-labeled issues (gh)
#   2. kf-recurrence.json         KF-002 recurrence count in known-failures.md
#   3. clean-fp-rate.json         "status: clean" FP rate from MODELINV replay
#   4. legacy-loc.json            wc -l on model-adapter.sh.legacy
#   5. modelinv-coverage.json     cycle-108 T2.M tool output (30d window)
#   6. issue-rate.json            substrate-labeled issue creation rate (gh)
#   7. operator-self-rating.md    operator-attention-tax template
#
# Substrate-degraded posture: gh-dependent baselines (1, 6) mark
# `skipped:gh-unavailable` when gh isn't reachable; the script does
# NOT hard-fail on gh absence.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    BASELINE_CAPTURE="$PROJECT_ROOT/tools/cycle-baseline-capture.sh"

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/baseline-capture.XXXXXX")"
    BASELINES_DIR="$BATS_TMP/baselines"
    mkdir -p "$BASELINES_DIR"

    # Fixture known-failures.md with KF-002 carrying a known recurrence count.
    mkdir -p "$BATS_TMP/grimoires/loa"
    cat > "$BATS_TMP/grimoires/loa/known-failures.md" <<'MD'
# Known Failures

## KF-002: adversarial-review.sh empty-content on review-type prompts at scale

**Status**: LAYERS-2-AND-3-RESOLVED-STRUCTURAL 2026-05-12
**Recurrence count**: 5
**Feature**: adversarial-review.sh review-type
**Symptom**: empty content
**First observed**: 2026-05-09
**Current workaround**: streaming substrate
**Upstream issue**: filed

### Reading guide

Fixture entry.
MD

    # Stub legacy adapter file (the live one's wc -l count is real but
    # this fixture establishes the baseline contract).
    cat > "$BATS_TMP/legacy-adapter.sh" <<'SH'
#!/usr/bin/env bash
# This is a stub of the cycle-109 legacy adapter. Real LOC is 1,081
# per PRD §3.4; for the test we just need a known line count.
echo "stub"
SH

    # Stub MODELINV log.
    mkdir -p "$BATS_TMP/.run"
    cat > "$BATS_TMP/.run/model-invoke.jsonl" <<'JSON'
{"schema_version":"1.1.0","primitive_id":"MODELINV","event_type":"model.invoke.complete","ts_utc":"2026-05-10T00:00:00Z","prev_hash":"GENESIS","payload":{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false}}
{"schema_version":"1.1.0","primitive_id":"MODELINV","event_type":"model.invoke.complete","ts_utc":"2026-05-10T00:01:00Z","prev_hash":"abc","payload":{"models_requested":["openai:gpt-5.5"],"models_succeeded":[],"models_failed":[{"model":"openai:gpt-5.5","error_class":"EMPTY_CONTENT","message_redacted":"x"}],"operator_visible_warn":false}}
JSON
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

_run_capture() {
    "$BASELINE_CAPTURE" \
        --baselines-dir "$BASELINES_DIR" \
        --known-failures "$BATS_TMP/grimoires/loa/known-failures.md" \
        --legacy-adapter "$BATS_TMP/legacy-adapter.sh" \
        --modelinv-log "$BATS_TMP/.run/model-invoke.jsonl" \
        --skip-gh
}

# =============================================================================
# BC1: emits all 7 baseline files
# =============================================================================

@test "BC1: emits all 7 baseline files" {
    run _run_capture
    [ "$status" -eq 0 ]
    [[ -f "$BASELINES_DIR/issue-counts.json" ]]
    [[ -f "$BASELINES_DIR/kf-recurrence.json" ]]
    [[ -f "$BASELINES_DIR/clean-fp-rate.json" ]]
    [[ -f "$BASELINES_DIR/legacy-loc.json" ]]
    [[ -f "$BASELINES_DIR/modelinv-coverage.json" ]]
    [[ -f "$BASELINES_DIR/issue-rate.json" ]]
    [[ -f "$BASELINES_DIR/operator-self-rating.md" ]]
}

# =============================================================================
# BC2: legacy-loc.json carries the wc -l count
# =============================================================================

@test "BC2: legacy-loc.json reports the line count of the legacy adapter" {
    run _run_capture
    [ "$status" -eq 0 ]
    grep -q '"line_count"' "$BASELINES_DIR/legacy-loc.json"
    # The fixture is 5 lines (shebang + comment + comment + echo + newline at EOF).
    grep -q '"line_count":\s*[0-9]' "$BASELINES_DIR/legacy-loc.json"
}

# =============================================================================
# BC3: kf-recurrence.json reports KF-002 recurrence count
# =============================================================================

@test "BC3: kf-recurrence.json extracts KF-002 recurrence count from ledger" {
    run _run_capture
    [ "$status" -eq 0 ]
    grep -q 'KF-002' "$BASELINES_DIR/kf-recurrence.json"
    grep -q '"recurrence_count"' "$BASELINES_DIR/kf-recurrence.json"
}

# =============================================================================
# BC4: clean-fp-rate.json reports false-positive count from MODELINV replay
# =============================================================================

@test "BC4: clean-fp-rate.json reports clean-with-failed-voices rate from MODELINV replay" {
    run _run_capture
    [ "$status" -eq 0 ]
    grep -q '"clean_fp_rate"' "$BASELINES_DIR/clean-fp-rate.json" || \
        grep -q '"false_positive_count"' "$BASELINES_DIR/clean-fp-rate.json"
}

# =============================================================================
# BC5: gh-dependent baselines mark skipped when --skip-gh
# =============================================================================

@test "BC5: --skip-gh marks issue-counts + issue-rate as skipped" {
    run _run_capture
    [ "$status" -eq 0 ]
    grep -q 'skipped\|gh-unavailable\|--skip-gh' "$BASELINES_DIR/issue-counts.json"
    grep -q 'skipped\|gh-unavailable\|--skip-gh' "$BASELINES_DIR/issue-rate.json"
}

# =============================================================================
# BC6: idempotent — re-running produces same content (excluding timestamps)
# =============================================================================

@test "BC6: re-running produces stable baseline values (timestamps excluded)" {
    run _run_capture
    [ "$status" -eq 0 ]
    local kf_first
    kf_first="$(grep -o '"recurrence_count":\s*[0-9]\+' "$BASELINES_DIR/kf-recurrence.json")"
    local loc_first
    loc_first="$(grep -o '"line_count":\s*[0-9]\+' "$BASELINES_DIR/legacy-loc.json")"

    run _run_capture
    [ "$status" -eq 0 ]
    local kf_second
    kf_second="$(grep -o '"recurrence_count":\s*[0-9]\+' "$BASELINES_DIR/kf-recurrence.json")"
    local loc_second
    loc_second="$(grep -o '"line_count":\s*[0-9]\+' "$BASELINES_DIR/legacy-loc.json")"

    [[ "$kf_first" == "$kf_second" ]]
    [[ "$loc_first" == "$loc_second" ]]
}

# =============================================================================
# BC7: operator-self-rating.md is a markdown template (operator fills in
#      at cycle-close)
# =============================================================================

@test "BC7: operator-self-rating.md emits a markdown template with rating prompt" {
    run _run_capture
    [ "$status" -eq 0 ]
    grep -q 'rating\|1-10\|attention-tax\|operator' "$BASELINES_DIR/operator-self-rating.md"
}
