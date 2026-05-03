#!/usr/bin/env bats
# =============================================================================
# tests/integration/panel-protected-class.bats
#
# cycle-098 Sprint 1D — FR-L1-4: Protected-class decisions route to
# QUEUED_PROTECTED without panel invocation.
#
# AC sources:
#   - PRD FR-L1-4 (default protected-class taxonomy in Appendix D)
#   - SDD §1.4.2 L1 (pre-flight short-circuit)
#   - 1B handoff: is_protected_class lib + .run/protected-queue.jsonl write
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    PANEL_LIB="$PROJECT_ROOT/.claude/scripts/lib/hitl-jury-panel-lib.sh"
    AUDIT_ENVELOPE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"
    PROTECTED_ROUTER="$PROJECT_ROOT/.claude/scripts/lib/protected-class-router.sh"

    [[ -f "$PANEL_LIB" ]] || skip "hitl-jury-panel-lib.sh not present"
    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"
    [[ -f "$PROTECTED_ROUTER" ]] || skip "protected-class-router.sh not present"

    TEST_DIR="$(mktemp -d)"
    LOG="$TEST_DIR/panel-decisions.jsonl"
    QUEUE="$TEST_DIR/protected-queue.jsonl"
    PANELISTS_YAML="$TEST_DIR/panelists.yaml"
    CONTEXT="$TEST_DIR/context.txt"

    BIN_DIR="$TEST_DIR/bin"
    mkdir -p "$BIN_DIR"

    # Sentinel-tracked mock — if ANY panelist gets invoked, this file appears.
    cat > "$BIN_DIR/model-invoke" <<'SHIM'
#!/usr/bin/env bash
touch "${LOA_PANEL_TEST_INVOKE_SENTINEL:?missing}"
echo '{"view":"should-not-be-invoked","reasoning_summary":"protected"}'
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

    echo "Operator wants to rotate the GitHub PAT" > "$CONTEXT"

    export PATH="$BIN_DIR:$PATH"
    export LOA_PANEL_TEST_INVOKE_SENTINEL="$TEST_DIR/invoked.sentinel"
    export LOA_PANEL_AUDIT_LOG="$LOG"
    export LOA_PANEL_PROTECTED_QUEUE="$QUEUE"

    # shellcheck disable=SC1090
    source "$AUDIT_ENVELOPE"
    # shellcheck disable=SC1090
    source "$PANEL_LIB"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# -----------------------------------------------------------------------------
# Pre-flight: protected class → QUEUED_PROTECTED, no panelists invoked
# -----------------------------------------------------------------------------
@test "protected-class: credential.rotate → QUEUED_PROTECTED outcome" {
    local out
    out=$(panel_invoke "rotate-pat-001" "credential.rotate" "ctxhash" "$PANELISTS_YAML" "$CONTEXT")
    echo "$out" | jq -e '.outcome == "QUEUED_PROTECTED"' >/dev/null
}

@test "protected-class: credential.rotate → no model-invoke calls (sentinel absent)" {
    panel_invoke "rotate-pat-002" "credential.rotate" "ctxhash" "$PANELISTS_YAML" "$CONTEXT" >/dev/null
    [[ ! -f "$TEST_DIR/invoked.sentinel" ]]
}

@test "protected-class: credential.rotate → entry appended to protected-queue" {
    panel_invoke "rotate-pat-003" "credential.rotate" "ctxhash" "$PANELISTS_YAML" "$CONTEXT" >/dev/null
    [[ -f "$QUEUE" ]]
    grep -q '"decision_id":"rotate-pat-003"' "$QUEUE"
    grep -q '"decision_class":"credential.rotate"' "$QUEUE"
}

@test "protected-class: credential.rotate → audit log emits panel.queued_protected envelope" {
    panel_invoke "rotate-pat-004" "credential.rotate" "ctxhash" "$PANELISTS_YAML" "$CONTEXT" >/dev/null
    [[ -f "$LOG" ]]
    grep -q '"event_type":"panel.queued_protected"' "$LOG"
    grep '"event_type":"panel.queued_protected"' "$LOG" | head -n 1 | jq -e '
        .payload.decision_id == "rotate-pat-004" and
        .payload.decision_class == "credential.rotate" and
        .payload.route == "QUEUED_PROTECTED"
    ' >/dev/null
}

@test "protected-class: production.deploy also routes to QUEUED_PROTECTED" {
    local out
    out=$(panel_invoke "deploy-001" "production.deploy" "ctxhash" "$PANELISTS_YAML" "$CONTEXT")
    echo "$out" | jq -e '.outcome == "QUEUED_PROTECTED"' >/dev/null
    [[ ! -f "$TEST_DIR/invoked.sentinel" ]]
}

@test "protected-class: destructive.irreversible also routes to QUEUED_PROTECTED" {
    local out
    out=$(panel_invoke "delete-001" "destructive.irreversible" "ctxhash" "$PANELISTS_YAML" "$CONTEXT")
    echo "$out" | jq -e '.outcome == "QUEUED_PROTECTED"' >/dev/null
}

# -----------------------------------------------------------------------------
# Negative: non-protected class proceeds to panel
# -----------------------------------------------------------------------------
@test "protected-class: routine.retry_policy is NOT protected → panel proceeds" {
    # We allow the model-invoke shim to actually run (it returns a fixed view).
    local out
    out=$(panel_invoke "retry-001" "routine.retry_policy" "ctxhash" "$PANELISTS_YAML" "$CONTEXT")
    echo "$out" | jq -e '.outcome == "BOUND"' >/dev/null
    # Sentinel was created (panelists invoked).
    [[ -f "$TEST_DIR/invoked.sentinel" ]]
}
