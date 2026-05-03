#!/usr/bin/env bats
# =============================================================================
# tests/integration/hitl-jury-panel-skill.bats
#
# cycle-098 Sprint 1D — End-to-end exercise of the L1 hitl-jury-panel skill
# via panel_invoke library entry point.
#
# AC sources:
#   - PRD FR-L1-1 (≥3 panelists in parallel)
#   - PRD FR-L1-2 (views logged BEFORE selection)
#   - PRD FR-L1-3 (deterministic seed selection)
#   - PRD FR-L1-7 (audit log entries)
#   - SDD §1.4.2, §5.3
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

    # Mock model-invoke. The shim writes a deterministic view per panelist id
    # taken from $LOA_PANEL_TEST_INVOKE_DIR/<panelist-id>.{view,reasoning,exitcode,sleep}.
    BIN_DIR="$TEST_DIR/bin"
    mkdir -p "$BIN_DIR"
    INVOKE_DIR="$TEST_DIR/invoke"
    mkdir -p "$INVOKE_DIR"

    cat > "$BIN_DIR/model-invoke" <<'SHIM'
#!/usr/bin/env bash
# Mock model-invoke shim driven by LOA_PANEL_TEST_INVOKE_DIR.
# Required env vars:
#   LOA_PANEL_TEST_INVOKE_DIR — directory with <panelist>.view, <panelist>.exitcode, <panelist>.sleep
#   LOA_PANEL_TEST_PANELIST   — current panelist id
set -u
dir="${LOA_PANEL_TEST_INVOKE_DIR:?missing}"
pid="${LOA_PANEL_TEST_PANELIST:?missing}"

# Optional sleep (for timeout testing).
if [[ -f "$dir/$pid.sleep" ]]; then
    sleep "$(cat "$dir/$pid.sleep")"
fi
ec=0
if [[ -f "$dir/$pid.exitcode" ]]; then
    ec="$(cat "$dir/$pid.exitcode")"
fi
if [[ "$ec" != "0" ]]; then
    echo "MOCK_API_ERROR for $pid" >&2
    exit "$ec"
fi
view="default-view-$pid"
if [[ -f "$dir/$pid.view" ]]; then
    view="$(cat "$dir/$pid.view")"
fi
reasoning="default-reasoning-$pid"
if [[ -f "$dir/$pid.reasoning" ]]; then
    reasoning="$(cat "$dir/$pid.reasoning")"
fi
# Output JSON object for parser-friendliness.
jq -nc --arg v "$view" --arg r "$reasoning" '{view:$v, reasoning_summary:$r}'
SHIM
    chmod +x "$BIN_DIR/model-invoke"

    # Configure 3 panelists.
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

    echo "What retry policy should we use for transient API errors?" > "$CONTEXT"

    # Default panelist views (overridable per test).
    echo "retry once with 5s backoff" > "$INVOKE_DIR/alpha.view"
    echo "do not retry; surface error to operator" > "$INVOKE_DIR/beta.view"
    echo "retry with exponential backoff" > "$INVOKE_DIR/gamma.view"

    # Inject the shim onto PATH.
    export PATH="$BIN_DIR:$PATH"
    export LOA_PANEL_TEST_INVOKE_DIR="$INVOKE_DIR"
    export LOA_PANEL_AUDIT_LOG="$LOG"
    export LOA_PANEL_PROTECTED_QUEUE="$TEST_DIR/protected-queue.jsonl"

    # shellcheck disable=SC1090
    source "$AUDIT_ENVELOPE"
    # shellcheck disable=SC1090
    source "$PANEL_LIB"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# -----------------------------------------------------------------------------
# FR-L1-1 — ≥3 panelists in parallel
# -----------------------------------------------------------------------------
@test "skill: panel_invoke convenes 3 panelists, returns BOUND outcome" {
    run panel_invoke "decision-1" "routine.retry_policy" "abc123" "$PANELISTS_YAML" "$CONTEXT"
    [[ "$status" -eq 0 ]]

    echo "$output" | jq -e '.outcome == "BOUND"' >/dev/null
    echo "$output" | jq -e '.selected_panelist_id | length > 0' >/dev/null
    echo "$output" | jq -e '.binding_view | length > 0' >/dev/null
    echo "$output" | jq -e '.selection_seed | test("^[0-9a-f]{64}$")' >/dev/null
}

# -----------------------------------------------------------------------------
# FR-L1-2 — Panelist views logged BEFORE selection
# -----------------------------------------------------------------------------
@test "skill: panel.solicit envelope written BEFORE panel.bind (verifiable line order)" {
    panel_invoke "decision-2" "routine.retry_policy" "abc123" "$PANELISTS_YAML" "$CONTEXT" >/dev/null

    # Find the line numbers of the first panel.solicit and the first panel.bind.
    local solicit_line bind_line
    solicit_line=$(grep -n '"event_type":"panel.solicit"' "$LOG" | head -n 1 | awk -F: '{print $1}')
    bind_line=$(grep -n '"event_type":"panel.bind"' "$LOG" | head -n 1 | awk -F: '{print $1}')

    [[ -n "$solicit_line" ]]
    [[ -n "$bind_line" ]]
    # Solicit comes BEFORE bind.
    (( solicit_line < bind_line ))
}

@test "skill: panel.solicit payload includes views from ALL 3 panelists" {
    panel_invoke "decision-3" "routine.retry_policy" "abc123" "$PANELISTS_YAML" "$CONTEXT" >/dev/null

    local n_panelists
    n_panelists=$(grep '"event_type":"panel.solicit"' "$LOG" | head -n 1 | jq -r '.payload.panelists | length')
    [[ "$n_panelists" -eq 3 ]]
}

# -----------------------------------------------------------------------------
# FR-L1-3 — Deterministic selection
# -----------------------------------------------------------------------------
@test "skill: same (decision_id, context_hash) → same binding view across two invocations" {
    local out1 out2 sel1 sel2
    out1=$(panel_invoke "decision-D" "routine.retry_policy" "ctx-D" "$PANELISTS_YAML" "$CONTEXT")
    sel1=$(echo "$out1" | jq -r '.selected_panelist_id')

    # Truncate log for fresh second run.
    rm -f "$LOG"
    out2=$(panel_invoke "decision-D" "routine.retry_policy" "ctx-D" "$PANELISTS_YAML" "$CONTEXT")
    sel2=$(echo "$out2" | jq -r '.selected_panelist_id')

    [[ "$sel1" == "$sel2" ]]
}

# -----------------------------------------------------------------------------
# FR-L1-7 — Audit log contains panel.bind with binding_view + minority_dissent + seed
# -----------------------------------------------------------------------------
@test "skill: panel.bind envelope has binding_view, minority_dissent, selection_seed" {
    panel_invoke "decision-4" "routine.retry_policy" "abc456" "$PANELISTS_YAML" "$CONTEXT" >/dev/null

    grep '"event_type":"panel.bind"' "$LOG" | head -n 1 | jq -e '
        (.payload.binding_view | length) > 0 and
        (.payload.minority_dissent | type == "array") and
        (.payload.selection_seed | test("^[0-9a-f]{64}$")) and
        .payload.outcome == "BOUND"
    ' >/dev/null
}

@test "skill: minority_dissent contains all panelists EXCEPT the selected one" {
    panel_invoke "decision-5" "routine.retry_policy" "abc789" "$PANELISTS_YAML" "$CONTEXT" >/dev/null

    local sel n_minority
    sel=$(grep '"event_type":"panel.bind"' "$LOG" | head -n 1 | jq -r '.payload.selected_panelist_id')
    n_minority=$(grep '"event_type":"panel.bind"' "$LOG" | head -n 1 | jq -r '.payload.minority_dissent | length')
    # We have 3 panelists; minority is len-1=2 (assuming all 3 contributed views).
    [[ "$n_minority" -eq 2 ]]
    grep '"event_type":"panel.bind"' "$LOG" | head -n 1 | jq -e ".payload.minority_dissent | map(.id) | index(\"$sel\") == null" >/dev/null
}

# -----------------------------------------------------------------------------
# Skill returns the diagnostic JSON contract per SDD §5.3.1
# -----------------------------------------------------------------------------
@test "skill: returned JSON includes outcome, binding_view, selected_panelist_id, selection_seed, minority_dissent" {
    local out
    out=$(panel_invoke "decision-6" "routine.retry_policy" "abc789" "$PANELISTS_YAML" "$CONTEXT")
    echo "$out" | jq -e '
        (.outcome | type == "string") and
        (.binding_view | type == "string") and
        (.selected_panelist_id | type == "string") and
        (.selection_seed | type == "string") and
        (.minority_dissent | type == "array") and
        (.audit_log_entry_id | type == "string") and
        (.diagnostic | type == "string")
    ' >/dev/null
}
