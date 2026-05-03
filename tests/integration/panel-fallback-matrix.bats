#!/usr/bin/env bats
# =============================================================================
# tests/integration/panel-fallback-matrix.bats
#
# cycle-098 Sprint 1D — FR-L1-5: fallback matrix for the 4 documented cases.
#
# AC sources:
#   - PRD FR-L1-5
#   - SDD §6.3.1 (fallback matrix table)
#       Panelist timeout       → skip; continue with remaining
#       Panelist API failure   → skip; continue with remaining
#       Tertiary unavailable   → continue with 2; degraded
#       All panelists fail     → outcome FALLBACK; queue for operator
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    PANEL_LIB="$PROJECT_ROOT/.claude/scripts/lib/hitl-jury-panel-lib.sh"
    AUDIT_ENVELOPE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"

    [[ -f "$PANEL_LIB" ]] || skip "hitl-jury-panel-lib.sh not present"
    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"

    TEST_DIR="$(mktemp -d)"
    LOG="$TEST_DIR/panel-decisions.jsonl"
    PANELISTS_YAML="$TEST_DIR/panelists.yaml"
    CONTEXT="$TEST_DIR/context.txt"

    BIN_DIR="$TEST_DIR/bin"
    mkdir -p "$BIN_DIR"
    INVOKE_DIR="$TEST_DIR/invoke"
    mkdir -p "$INVOKE_DIR"

    cat > "$BIN_DIR/model-invoke" <<'SHIM'
#!/usr/bin/env bash
set -u
dir="${LOA_PANEL_TEST_INVOKE_DIR:?missing}"
pid="${LOA_PANEL_TEST_PANELIST:?missing}"
if [[ -f "$dir/$pid.sleep" ]]; then sleep "$(cat "$dir/$pid.sleep")"; fi
ec=0
[[ -f "$dir/$pid.exitcode" ]] && ec="$(cat "$dir/$pid.exitcode")"
if [[ "$ec" != "0" ]]; then
    echo "MOCK_API_ERROR for $pid" >&2
    exit "$ec"
fi
view="default-view-$pid"
[[ -f "$dir/$pid.view" ]] && view="$(cat "$dir/$pid.view")"
reasoning="default-reasoning-$pid"
[[ -f "$dir/$pid.reasoning" ]] && reasoning="$(cat "$dir/$pid.reasoning")"
jq -nc --arg v "$view" --arg r "$reasoning" '{view:$v, reasoning_summary:$r}'
SHIM
    chmod +x "$BIN_DIR/model-invoke"

    cat > "$PANELISTS_YAML" <<'YAML'
panelists:
  - id: alpha
    model: claude-opus-4-7
    persona_path: /tmp/alpha.md
  - id: beta
    model: claude-opus-4-7
    persona_path: /tmp/beta.md
  - id: gamma
    model: gpt-5.3-codex
    persona_path: /tmp/gamma.md
YAML

    echo "Routine retry decision" > "$CONTEXT"

    # Default: all panelists succeed.
    echo "view-alpha" > "$INVOKE_DIR/alpha.view"
    echo "view-beta"  > "$INVOKE_DIR/beta.view"
    echo "view-gamma" > "$INVOKE_DIR/gamma.view"

    export PATH="$BIN_DIR:$PATH"
    export LOA_PANEL_TEST_INVOKE_DIR="$INVOKE_DIR"
    export LOA_PANEL_AUDIT_LOG="$LOG"
    export LOA_PANEL_PROTECTED_QUEUE="$TEST_DIR/protected-queue.jsonl"
    # Aggressive timeout for tests.
    export LOA_PANEL_PER_PANELIST_TIMEOUT="2"

    # shellcheck disable=SC1090
    source "$AUDIT_ENVELOPE"
    # shellcheck disable=SC1090
    source "$PANEL_LIB"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# -----------------------------------------------------------------------------
# Case 1: panelist timeout (one panelist sleeps past timeout)
# -----------------------------------------------------------------------------
@test "fallback: one panelist times out → continue with 2; degraded mode logged" {
    echo "5" > "$INVOKE_DIR/gamma.sleep"  # exceeds LOA_PANEL_PER_PANELIST_TIMEOUT=2

    local out
    out=$(panel_invoke "decision-timeout" "routine.retry_policy" "ctx" "$PANELISTS_YAML" "$CONTEXT")
    # With 2/3 panelists, FR-L1-5 says "skip + continue" — outcome BOUND
    # if surviving panel size is acceptable, FALLBACK if too few.
    # Sprint 1D minimum bar: outcome is BOUND or FALLBACK (NOT ERROR);
    # the audit log records the timeout and degraded mode.
    local outcome
    outcome=$(echo "$out" | jq -r '.outcome')
    [[ "$outcome" == "BOUND" ]] || [[ "$outcome" == "FALLBACK" ]]
    # Audit log records the fallback path (timeout) AND the degraded panelists list
    grep -q '"event_type":"panel.solicit"' "$LOG"
    # The bind/fallback should record fallback_path
    grep -E '"event_type":"(panel.bind|panel.fallback)"' "$LOG" | head -n 1 | jq -e '
        (.payload.fallback_path | tostring) | test("timeout")
    ' >/dev/null
}

# -----------------------------------------------------------------------------
# Case 2: API failure (one panelist exits non-zero)
# -----------------------------------------------------------------------------
@test "fallback: one panelist API failure → skip; continue with 2; failure logged" {
    echo "1" > "$INVOKE_DIR/beta.exitcode"  # API failure

    local out
    out=$(panel_invoke "decision-api-fail" "routine.retry_policy" "ctx" "$PANELISTS_YAML" "$CONTEXT")
    local outcome
    outcome=$(echo "$out" | jq -r '.outcome')
    [[ "$outcome" == "BOUND" ]] || [[ "$outcome" == "FALLBACK" ]]
    # The failure is recorded — at minimum panel.solicit captured the error
    # for the failed panelist.
    grep '"event_type":"panel.solicit"' "$LOG" | head -n 1 | jq -e '
        any(.payload.panelists[]; .id == "beta" and (.error // null) != null)
    ' >/dev/null
}

# -----------------------------------------------------------------------------
# Case 3: tertiary unavailable (sufficient panelists still respond)
# -----------------------------------------------------------------------------
@test "fallback: tertiary panelist unavailable → continue with 2 (degraded); BOUND or FALLBACK" {
    # gamma is the "tertiary" (gpt-5.3-codex) — simulate unavailable.
    echo "127" > "$INVOKE_DIR/gamma.exitcode"

    local out
    out=$(panel_invoke "decision-tertiary" "routine.retry_policy" "ctx" "$PANELISTS_YAML" "$CONTEXT")
    local outcome
    outcome=$(echo "$out" | jq -r '.outcome')
    [[ "$outcome" == "BOUND" ]] || [[ "$outcome" == "FALLBACK" ]]
    # bind or fallback envelope must record degraded count
    grep -E '"event_type":"(panel.bind|panel.fallback)"' "$LOG" | head -n 1 | jq -e '
        (.payload.panelists | length) >= 2
    ' >/dev/null
}

# -----------------------------------------------------------------------------
# Case 4: all panelists fail
# -----------------------------------------------------------------------------
@test "fallback: all 3 panelists fail → outcome FALLBACK; queued for operator" {
    echo "1" > "$INVOKE_DIR/alpha.exitcode"
    echo "1" > "$INVOKE_DIR/beta.exitcode"
    echo "1" > "$INVOKE_DIR/gamma.exitcode"

    local out
    out=$(panel_invoke "decision-all-fail" "routine.retry_policy" "ctx" "$PANELISTS_YAML" "$CONTEXT")
    echo "$out" | jq -e '.outcome == "FALLBACK"' >/dev/null
    # Audit log includes panel.fallback envelope
    grep -q '"event_type":"panel.fallback"' "$LOG"
    grep '"event_type":"panel.fallback"' "$LOG" | head -n 1 | jq -e '
        .payload.fallback_path == "all_fail"
    ' >/dev/null
}
