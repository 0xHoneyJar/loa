#!/usr/bin/env bats
# =============================================================================
# tests/unit/panel-distribution-audit.bats
#
# cycle-098 Sprint 1D — FR-L1-8 distribution audit script.
# Walks .run/panel-decisions.jsonl for last 30 days; counts selections per
# panelist; asserts no panelist >50% selection rate when N≥10.
#
# AC sources:
#   - PRD FR-L1-8 (audit script ships; enforcement is post-ship telemetry)
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    DIST_AUDIT="$PROJECT_ROOT/.claude/scripts/panel-distribution-audit.sh"

    [[ -x "$DIST_AUDIT" ]] || skip "panel-distribution-audit.sh not present or not executable"

    TEST_DIR="$(mktemp -d)"
    LOG="$TEST_DIR/panel-decisions.jsonl"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# Helper: emit a synthetic panel.bind envelope for panelist <id> at <ts>.
_emit_bind() {
    local panelist="$1"
    local ts="$2"
    local seed
    seed=$(printf '%s' "$panelist-$ts" | sha256sum | awk '{print $1}')
    jq -nc \
        --arg p "$panelist" \
        --arg t "$ts" \
        --arg s "$seed" \
        '{
            schema_version:"1.1.0",
            primitive_id:"L1",
            event_type:"panel.bind",
            ts_utc:$t,
            prev_hash:"GENESIS",
            payload:{
                decision_id:("d-" + $p + "-" + $t),
                selected_panelist_id:$p,
                selection_seed:$s,
                outcome:"BOUND"
            },
            redaction_applied:null
        }' >> "$LOG"
}

# -----------------------------------------------------------------------------
# Below threshold (N<10) — the script reports but does NOT fail
# -----------------------------------------------------------------------------
@test "dist-audit: N<10 → no enforcement (script ships warning at most)" {
    # 5 entries, all alpha → 100% but N<10
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    for i in 1 2 3 4 5; do
        _emit_bind "alpha" "$now"
    done

    run "$DIST_AUDIT" --log "$LOG"
    [[ "$status" -eq 0 ]]
    # Output mentions N<10 telemetry threshold not met or similar
    [[ "$output" == *"5"* ]]
}

# -----------------------------------------------------------------------------
# Above threshold (N>=10), one panelist >50% → script reports concentration
# -----------------------------------------------------------------------------
@test "dist-audit: N>=10 + alpha >50% → exit non-zero (concentration breach)" {
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # alpha=8/12 (~66%), beta=2, gamma=2  → alpha breaches 50%
    for i in 1 2 3 4 5 6 7 8; do
        _emit_bind "alpha" "$now"
    done
    for i in 1 2; do
        _emit_bind "beta" "$now"
    done
    for i in 1 2; do
        _emit_bind "gamma" "$now"
    done

    run "$DIST_AUDIT" --log "$LOG"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"alpha"* ]]
}

# -----------------------------------------------------------------------------
# N>=10, healthy distribution (no panelist >50%)
# -----------------------------------------------------------------------------
@test "dist-audit: N>=10 + balanced → exit 0" {
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # alpha=4/12, beta=4/12, gamma=4/12 — all 33.3%
    for i in 1 2 3 4; do
        _emit_bind "alpha" "$now"
    done
    for i in 1 2 3 4; do
        _emit_bind "beta" "$now"
    done
    for i in 1 2 3 4; do
        _emit_bind "gamma" "$now"
    done

    run "$DIST_AUDIT" --log "$LOG"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# 30-day window — entries older than 30d are excluded
# -----------------------------------------------------------------------------
@test "dist-audit: entries older than 30d excluded from count" {
    local now old
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # 60 days ago — should be excluded
    old=$(python3 -c 'from datetime import datetime, timedelta, timezone; print((datetime.now(timezone.utc) - timedelta(days=60)).strftime("%Y-%m-%dT%H:%M:%SZ"))')

    # 20 ancient alpha entries (would breach 50% if counted) — excluded
    for i in $(seq 1 20); do
        _emit_bind "alpha" "$old"
    done
    # 12 recent balanced entries (4/4/4) — within window
    for i in 1 2 3 4; do
        _emit_bind "alpha" "$now"
    done
    for i in 1 2 3 4; do
        _emit_bind "beta" "$now"
    done
    for i in 1 2 3 4; do
        _emit_bind "gamma" "$now"
    done

    run "$DIST_AUDIT" --log "$LOG"
    # Within the 30d window, distribution is balanced → exit 0
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# --json output mode
# -----------------------------------------------------------------------------
@test "dist-audit: --json mode emits structured object" {
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    for i in 1 2 3 4; do
        _emit_bind "alpha" "$now"
    done
    for i in 1 2 3 4; do
        _emit_bind "beta" "$now"
    done
    for i in 1 2 3 4; do
        _emit_bind "gamma" "$now"
    done

    run "$DIST_AUDIT" --log "$LOG" --json
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '
        (.window_days == 30) and
        (.total_decisions | type == "number") and
        (.distribution | type == "object") and
        ((.violations // []) | type == "array")
    ' >/dev/null
}

# -----------------------------------------------------------------------------
# Missing log file → graceful no-op (zero decisions to audit)
# -----------------------------------------------------------------------------
@test "dist-audit: missing log file → exit 0 with zero decisions" {
    run "$DIST_AUDIT" --log "$TEST_DIR/nonexistent.jsonl"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Skip non-bind events
# -----------------------------------------------------------------------------
@test "dist-audit: skips non-bind events (e.g. panel.solicit)" {
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Add a panel.solicit (NOT a bind) — should be ignored
    jq -nc --arg t "$now" '{
        schema_version:"1.1.0", primitive_id:"L1", event_type:"panel.solicit",
        ts_utc:$t, prev_hash:"GENESIS",
        payload:{decision_id:"d", panelists:[{id:"alpha",view:"v"}]},
        redaction_applied:null
    }' >> "$LOG"

    # 12 binds, balanced
    for i in 1 2 3 4; do _emit_bind "alpha" "$now"; done
    for i in 1 2 3 4; do _emit_bind "beta" "$now"; done
    for i in 1 2 3 4; do _emit_bind "gamma" "$now"; done

    run "$DIST_AUDIT" --log "$LOG" --json
    [[ "$status" -eq 0 ]]
    # Total binds counted = 12 (solicit ignored)
    echo "$output" | jq -e '.total_decisions == 12' >/dev/null
}
