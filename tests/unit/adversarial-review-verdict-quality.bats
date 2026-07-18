#!/usr/bin/env bats
# =============================================================================
# tests/unit/adversarial-review-verdict-quality.bats
#
# cycle-109 Sprint 2 T2.5 — adversarial-review.sh consumes verdict_quality
# (CONSUMER #3 per SDD §3.2.3 IMP-004; closes #807 / #823 / #868).
#
# Per SDD: adversarial-review.sh's main() runs through a cross-model
# fallback_chain — each attempt is a per-voice cheval invocation that
# produces a verdict_quality envelope via the LOA_VERDICT_QUALITY_SIDECAR
# transport (T2.4). The main loop collects per-attempt envelopes and
# aggregates them via the canonical Python aggregator
# (python -m loa_cheval.verdict.aggregate) so the resulting
# adversarial-{review,audit}.json carries a multi-voice envelope
# describing chain_health, voices_dropped, blocker_risk, etc.
#
# This file tests TWO surfaces:
#
#   1. The bash helper `_adv_aggregate_envelopes` (a function inside
#      adversarial-review.sh that shells out to the Python aggregator).
#      Tested in isolation by sourcing only the helper definitions.
#
#   2. The adversarial-{review,audit}.json output shape — verified by
#      asserting that the verdict_quality field exists in a synthesized
#      result via a focused, dependency-light pathway.
#
# The full end-to-end path (real cheval invocation under
# adversarial-review.sh) is covered by Sprint 2 T2.8 conformance matrix.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi
    export PYTHONPATH="$PROJECT_ROOT/.claude/adapters"

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/adv-vq.XXXXXX")"
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

_require_python_deps() {
    "$PYTHON_BIN" -c "import jsonschema" 2>/dev/null \
        || skip "jsonschema not installed in this Python env"
}

# Write a single-voice envelope fixture.
_write_envelope_approved() {
    local path="$1"
    local voice_id="${2:-voice-a}"
    cat > "$path" <<JSON
{
    "status": "APPROVED",
    "consensus_outcome": "consensus",
    "truncation_waiver_applied": false,
    "voices_planned": 1,
    "voices_succeeded": 1,
    "voices_succeeded_ids": ["${voice_id}"],
    "voices_dropped": [],
    "chain_health": "ok",
    "confidence_floor": "low",
    "rationale": "single-voice cheval invoke (voice=${voice_id})",
    "single_voice_call": true
}
JSON
}

_write_envelope_failed() {
    local path="$1"
    local voice_id="${2:-voice-c}"
    local risk="${3:-med}"
    cat > "$path" <<JSON
{
    "status": "FAILED",
    "consensus_outcome": "consensus",
    "truncation_waiver_applied": false,
    "voices_planned": 1,
    "voices_succeeded": 0,
    "voices_succeeded_ids": [],
    "voices_dropped": [
        {
            "voice": "${voice_id}",
            "reason": "EmptyContent",
            "exit_code": 1,
            "blocker_risk": "${risk}",
            "chain_walk": []
        }
    ],
    "chain_health": "exhausted",
    "confidence_floor": "low",
    "rationale": "single-voice cheval invoke (voice=${voice_id}); failed",
    "single_voice_call": true
}
JSON
}

# Source ONLY the helper functions from adversarial-review.sh.
# adversarial-review.sh is large and has top-level main() invocation;
# to test the helper in isolation we declare a thin extracter that
# locates and sources just the helper region.
_source_adv_review_helpers() {
    local adv_review="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    [[ -f "$adv_review" ]] || {
        printf 'FATAL: adversarial-review.sh not found at %s\n' "$adv_review" >&2
        return 1
    }
    # Stub out the logger before sourcing so the helper's `log` calls
    # don't try to write to non-existent paths.
    log() { :; }
    error() { printf '%s\n' "$*" >&2; return 1; }
    # Extract by sourcing the full script under guard that prevents main()
    # from running. adversarial-review.sh ends with `main "$@"`; we
    # neutralize by overriding main BEFORE sourcing.
    main() { :; }
    # shellcheck disable=SC1090
    source "$adv_review"
}

# =============================================================================
# AV-1: helper exists in adversarial-review.sh
# =============================================================================

@test "AV1: _adv_aggregate_envelopes helper is defined in adversarial-review.sh" {
    grep -q "_adv_aggregate_envelopes" "$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
}

# =============================================================================
# AV-2: helper emits empty / non-zero when no envelopes supplied
# =============================================================================

@test "AV2: _adv_aggregate_envelopes returns non-zero on empty input" {
    _require_python_deps
    _source_adv_review_helpers
    run _adv_aggregate_envelopes
    [ "$status" -ne 0 ]
}

# =============================================================================
# AV-3: helper aggregates 2 single-voice envelopes via Python CLI
# =============================================================================

@test "AV3: _adv_aggregate_envelopes aggregates two single-voice envelopes" {
    _require_python_deps
    _source_adv_review_helpers
    local f1="$BATS_TMP/v1.json"
    local f2="$BATS_TMP/v2.json"
    _write_envelope_approved "$f1" "model-a"
    _write_envelope_failed "$f2" "model-b" "med"

    run _adv_aggregate_envelopes "$f1" "$f2"
    [ "$status" -eq 0 ]
    local status_value voices_planned
    status_value=$(echo "$output" | jq -r '.status')
    voices_planned=$(echo "$output" | jq -r '.voices_planned')
    [ "$status_value" = "DEGRADED" ]
    [ "$voices_planned" -eq 2 ]
}

# =============================================================================
# AV-4: helper skips missing / non-JSON files
# =============================================================================

@test "AV4: _adv_aggregate_envelopes skips missing files but aggregates valid ones" {
    _require_python_deps
    _source_adv_review_helpers
    local valid="$BATS_TMP/valid.json"
    _write_envelope_approved "$valid" "model-a"
    local missing="$BATS_TMP/missing.json"  # never created
    local empty="$BATS_TMP/empty.json"
    : > "$empty"  # zero-byte file

    run _adv_aggregate_envelopes "$missing" "$valid" "$empty"
    [ "$status" -eq 0 ]
    local voices_planned
    voices_planned=$(echo "$output" | jq -r '.voices_planned')
    # Only the 1 valid envelope contributed
    [ "$voices_planned" -eq 1 ]
}

# =============================================================================
# AV-5: helper skips files with malformed JSON
# =============================================================================

@test "AV5: _adv_aggregate_envelopes skips malformed JSON files" {
    _require_python_deps
    _source_adv_review_helpers
    local valid="$BATS_TMP/valid.json"
    _write_envelope_approved "$valid" "model-a"
    local malformed="$BATS_TMP/bad.json"
    printf 'not json {' > "$malformed"

    run _adv_aggregate_envelopes "$valid" "$malformed"
    [ "$status" -eq 0 ]
    local voices_planned
    voices_planned=$(echo "$output" | jq -r '.voices_planned')
    [ "$voices_planned" -eq 1 ]
}

# =============================================================================
# AV-6: high-risk drop in aggregate auto-promotes to FAILED (NFR-Rel-1 closure)
# =============================================================================

@test "AV6: aggregate with high blocker_risk in any attempt promotes to FAILED" {
    _require_python_deps
    _source_adv_review_helpers
    local f1="$BATS_TMP/v1.json"
    local f2="$BATS_TMP/v2.json"
    _write_envelope_approved "$f1" "model-a"
    _write_envelope_failed "$f2" "model-b" "high"

    run _adv_aggregate_envelopes "$f1" "$f2"
    [ "$status" -eq 0 ]
    local status_value
    status_value=$(echo "$output" | jq -r '.status')
    [ "$status_value" = "FAILED" ]
}

# =============================================================================
# AV-7: invoke_dissenter wires LOA_VERDICT_QUALITY_SIDECAR (presence check)
# =============================================================================

@test "AV7: invoke_dissenter accepts a sidecar path argument" {
    # Verify the source-level wiring: invoke_dissenter signature accepts
    # a 5th positional arg for the sidecar path, AND the main loop passes
    # one. The full behavioral test is gated on a live cheval invocation
    # (T2.8 conformance matrix).
    grep -q "invoke_dissenter()" "$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    # Function body references vq_sidecar parameter
    grep -q "vq_sidecar=" "$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    # Main loop calls invoke_dissenter with the 5th arg
    grep -qE 'invoke_dissenter[^)]*"\$vq_sidecar"' "$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
}

# =============================================================================
# AV-8: main loop sets LOA_VERDICT_QUALITY_SIDECAR per attempt
# =============================================================================

@test "AV8: main loop references LOA_VERDICT_QUALITY_SIDECAR" {
    grep -q "LOA_VERDICT_QUALITY_SIDECAR" "$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
}

# =============================================================================
# AV-9: write_output emits verdict_quality in adversarial-{type}.json
# =============================================================================

@test "AV9: write_output flow preserves verdict_quality in result JSON" {
    # Source check: verify that result construction includes a
    # verdict_quality field (preceded by the aggregation step). This
    # is the consumer-contract check from FR-2.7 / NFR-Rel-1: the
    # adversarial-{type}.json file MUST carry the envelope.
    grep -q "verdict_quality" "$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
}

# =============================================================================
# AV-10+: cycle-117 item D (#1177) — write_output emits a degraded-verdict
# trajectory record + exactly one page for the crate 4-day-outage scenario
# (forced api_exit_code != 0), and emits/pages NOTHING for a clean run.
#
# write_output is exercised for real (not just grepped) via a small
# generated runner script — sourced adversarial-review.sh in a fresh bash
# process, with push_notify stubbed AFTER sourcing (bash resolves functions
# at call time, so the stub wins over degraded-verdict-lib.sh's real
# push-notify-lib.sh definition) and LOA_DEGRADED_VERDICT_DIR redirected
# into $BATS_TMP so the real repo's grimoires/loa/a2a/trajectory/ is never
# touched by this new signal. write_output's own (pre-existing, untouched)
# main-output write still lands under the real
# grimoires/loa/a2a/<sprint_id>/ — cleaned up in teardown via $sprint_id.
# =============================================================================

_run_adv_write_output() {
    local sprint_id="$1" type="$2" api_exit="$3" result_json="$4"
    local runner="$BATS_TMP/runner-${sprint_id}.sh"
    cat > "$runner" <<EOF
#!/usr/bin/env bash
set -euo pipefail
log() { :; }
error() { printf '%s\n' "\$*" >&2; return 1; }
main() { :; }
source "$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
push_notify() { echo "PUSH|\$1|\$2|\$3|\$4" >> "$BATS_TMP/pushlog-${sprint_id}.txt"; return 0; }
export LOA_DEGRADED_VERDICT_DIR="$BATS_TMP/trajectory-${sprint_id}"
write_output '$result_json' "$sprint_id" "$type" "$api_exit"
EOF
    bash "$runner"
}

_adv_test_sprint_ids=()

teardown_adv_sprint_dirs() {
    local sid
    for sid in "${_adv_test_sprint_ids[@]:-}"; do
        [[ -n "$sid" ]] && rm -rf "$PROJECT_ROOT/grimoires/loa/a2a/${sid}" 2>/dev/null
    done
}

@test "AV10: write_output emits DEGRADED record + one page for review-type api_failure (crate outage)" {
    _require_python_deps
    local sprint_id="av10-test-$$"
    _adv_test_sprint_ids+=("$sprint_id")
    local result_json
    result_json=$(jq -nc --arg sid "$sprint_id" '{
        findings: [],
        metadata: {type: "review", model: "gpt-5.5-pro", sprint_id: $sid,
                   timestamp: "2026-07-06T00:00:00Z", status: "api_failure",
                   degraded: false, error: "API call failed with exit code 3"}
    }')

    run _run_adv_write_output "$sprint_id" "review" "3" "$result_json"
    [ "$status" -eq 0 ]

    local traj
    traj="$BATS_TMP/trajectory-${sprint_id}/degraded-verdict-"*.jsonl
    [ -f $traj ]
    [ "$(jq -r '.gate' $traj)" = "adversarial-review:review" ]
    [ "$(jq -r '.verdict_band' $traj)" = "DEGRADED" ]
    [ "$(jq -r '.sprint_id' $traj)" = "$sprint_id" ]
    [ "$(jq -r '.model_exit_code' $traj)" = "3" ]
    [ "$(jq -c '.degraded_legs' $traj)" = '["gpt-5.5-pro"]' ]

    local pushlog="$BATS_TMP/pushlog-${sprint_id}.txt"
    [ -f "$pushlog" ]
    [ "$(wc -l < "$pushlog")" -eq 1 ]

    teardown_adv_sprint_dirs
}

@test "AV11: write_output emits DEGRADED record for audit-type api_failure (pre-existing degraded=true path)" {
    _require_python_deps
    local sprint_id="av11-test-$$"
    _adv_test_sprint_ids+=("$sprint_id")
    local result_json
    result_json=$(jq -nc --arg sid "$sprint_id" '{
        findings: [],
        metadata: {type: "audit", model: "gpt-5.5-pro", sprint_id: $sid,
                   timestamp: "2026-07-06T00:00:00Z", status: "api_failure",
                   degraded: true, error: "API call failed with exit code 5"}
    }')

    run _run_adv_write_output "$sprint_id" "audit" "5" "$result_json"
    [ "$status" -eq 0 ]

    local traj
    traj="$BATS_TMP/trajectory-${sprint_id}/degraded-verdict-"*.jsonl
    [ -f $traj ]
    [ "$(jq -r '.gate' $traj)" = "adversarial-review:audit" ]
    [ "$(jq -r '.verdict_band' $traj)" = "DEGRADED" ]
    [ "$(jq -r '.model_exit_code' $traj)" = "5" ]

    teardown_adv_sprint_dirs
}

@test "AV12: write_output emits a FAILED record from a multi-voice verdict_quality envelope" {
    _require_python_deps
    local sprint_id="av12-test-$$"
    _adv_test_sprint_ids+=("$sprint_id")
    local result_json
    result_json=$(jq -nc --arg sid "$sprint_id" '{
        findings: [],
        metadata: {type: "audit", model: "opus", sprint_id: $sid,
                   timestamp: "2026-07-06T00:00:00Z", status: "success"},
        verdict_quality: {
            status: "FAILED",
            consensus_outcome: "consensus",
            truncation_waiver_applied: false,
            voices_planned: 2,
            voices_succeeded: 1,
            voices_succeeded_ids: ["opus"],
            voices_dropped: [
                {voice: "gemini-3.1-pro", reason: "EmptyContent", exit_code: 1, blocker_risk: "high"}
            ],
            chain_health: "degraded",
            confidence_floor: "med",
            rationale: "gemini dropped with high blocker_risk"
        }
    }')

    run _run_adv_write_output "$sprint_id" "audit" "0" "$result_json"
    [ "$status" -eq 0 ]

    local traj
    traj="$BATS_TMP/trajectory-${sprint_id}/degraded-verdict-"*.jsonl
    [ -f $traj ]
    [ "$(jq -r '.verdict_band' $traj)" = "FAILED" ]
    [ "$(jq -r '.degradation_reason' $traj)" = "EmptyContent" ]
    [ "$(jq -r '.model_exit_code' $traj)" = "1" ]
    [ "$(jq -c '.degraded_legs' $traj)" = '["gemini-3.1-pro"]' ]

    teardown_adv_sprint_dirs
}

@test "AV13: write_output emits NO degraded-verdict record and pages nothing for a clean APPROVED run" {
    _require_python_deps
    local sprint_id="av13-test-$$"
    _adv_test_sprint_ids+=("$sprint_id")
    local result_json
    result_json=$(jq -nc --arg sid "$sprint_id" '{
        findings: [],
        metadata: {type: "review", model: "gpt-5.5-pro", sprint_id: $sid,
                   timestamp: "2026-07-06T00:00:00Z", status: "success"},
        verdict_quality: {
            status: "APPROVED",
            consensus_outcome: "consensus",
            truncation_waiver_applied: false,
            voices_planned: 1,
            voices_succeeded: 1,
            voices_succeeded_ids: ["gpt-5.5-pro"],
            voices_dropped: [],
            chain_health: "ok",
            confidence_floor: "high",
            rationale: "single-voice success"
        }
    }')

    run _run_adv_write_output "$sprint_id" "review" "0" "$result_json"
    [ "$status" -eq 0 ]

    local traj_dir="$BATS_TMP/trajectory-${sprint_id}"
    [ ! -d "$traj_dir" ] || [ -z "$(ls "$traj_dir" 2>/dev/null)" ]
    [ ! -f "$BATS_TMP/pushlog-${sprint_id}.txt" ]

    teardown_adv_sprint_dirs
}
