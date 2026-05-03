#!/usr/bin/env bats
# =============================================================================
# tests/unit/panel-audit-envelope.bats
#
# cycle-098 Sprint 1D — verify L1 panel-decisions log entries comply with the
# 1A audit envelope schema and 1B signing scheme.
#
# AC sources:
#   - PRD FR-L1-7 (audit log w/ panelist reasoning + seed + binding view + minority dissent)
#   - SDD §3.2.1 (envelope schema), §5.3.3 (PanelDecision payload schema)
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

    # shellcheck disable=SC1090
    source "$AUDIT_ENVELOPE"
    # shellcheck disable=SC1090
    source "$PANEL_LIB"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# -----------------------------------------------------------------------------
# panel_log_views — audit envelope structure
# -----------------------------------------------------------------------------
@test "panel-audit: log_views appends entry with envelope shape" {
    local views
    views=$(jq -nc '[
        {id:"alpha",model:"claude-opus-4-7",persona_path:"x.md",view:"v1",reasoning_summary:"r1"},
        {id:"beta",model:"claude-opus-4-7",persona_path:"x.md",view:"v2",reasoning_summary:"r2"}
    ]')
    panel_log_views "decision-1" "$views" "$LOG"

    [[ -f "$LOG" ]]
    local line
    line=$(head -n 1 "$LOG")
    # Required envelope fields.
    echo "$line" | jq -e '
        (.schema_version | type == "string") and
        .primitive_id == "L1" and
        .event_type == "panel.solicit" and
        (.ts_utc | type == "string") and
        (.prev_hash | type == "string") and
        (.payload | type == "object")
    ' >/dev/null
}

@test "panel-audit: log_views payload contains panelists with required fields" {
    local views
    views=$(jq -nc '[
        {id:"alpha",model:"x",persona_path:"p.md",view:"v1",reasoning_summary:"r1"},
        {id:"beta",model:"y",persona_path:"q.md",view:"v2",reasoning_summary:"r2"}
    ]')
    panel_log_views "decision-2" "$views" "$LOG"

    head -n 1 "$LOG" | jq -e '
        .payload.decision_id == "decision-2" and
        (.payload.panelists | length) == 2 and
        (.payload.panelists[0] | (.id and .model and .persona_path and .view and .reasoning_summary))
    ' >/dev/null
}

# -----------------------------------------------------------------------------
# panel_log_binding — full PanelDecision payload schema (SDD §5.3.3)
# -----------------------------------------------------------------------------
@test "panel-audit: log_binding includes all required PanelDecision fields" {
    local minority='[{"id":"beta","view":"alt-view"}]'
    panel_log_binding \
        "decision-3" \
        "alpha" \
        "f4e3d2c1b0a9000000000000000000000000000000000000000000000000beef" \
        "$minority" \
        "$LOG"

    head -n 1 "$LOG" | jq -e '
        .event_type == "panel.bind" and
        .payload.decision_id == "decision-3" and
        .payload.selected_panelist_id == "alpha" and
        (.payload.selection_seed | test("^[0-9a-f]{64}$")) and
        (.payload.minority_dissent | type == "array") and
        .payload.outcome == "BOUND"
    ' >/dev/null
}

# -----------------------------------------------------------------------------
# Hash chain integrity — panel events form a valid chain
# -----------------------------------------------------------------------------
@test "panel-audit: solicit + bind form a verifiable chain" {
    local views='[{"id":"alpha","model":"x","persona_path":"p.md","view":"v1","reasoning_summary":"r1"},{"id":"beta","model":"y","persona_path":"q.md","view":"v2","reasoning_summary":"r2"}]'
    panel_log_views "decision-4" "$views" "$LOG"
    panel_log_binding "decision-4" "alpha" "deadbeef$(printf '%.0s0' {1..56})" "[]" "$LOG"

    # Disable signature verification (no signing key set in this test); chain must still validate.
    LOA_AUDIT_VERIFY_SIGS=0 run audit_verify_chain "$LOG"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK 2 entries"* ]]
}

@test "panel-audit: panel.queued_protected emits envelope with route field" {
    # When a protected class is matched, the panel emits panel.queued_protected
    # via panel_invoke; we test panel_invoke directly with a simulated protected class.
    LOA_PANEL_AUDIT_LOG="$LOG" \
    LOA_PANEL_PROTECTED_QUEUE="$TEST_DIR/protected-queue.jsonl" \
        panel_log_queued_protected "decision-prot" "credential.rotate" "$LOG"

    head -n 1 "$LOG" | jq -e '
        .primitive_id == "L1" and
        .event_type == "panel.queued_protected" and
        .payload.decision_class == "credential.rotate" and
        .payload.route == "QUEUED_PROTECTED"
    ' >/dev/null
}

# -----------------------------------------------------------------------------
# Signing pass-through — when LOA_AUDIT_SIGNING_KEY_ID is set
# -----------------------------------------------------------------------------
@test "panel-audit: emits signed envelope when LOA_AUDIT_SIGNING_KEY_ID is set" {
    if ! python3 -c "import cryptography" 2>/dev/null; then
        skip "python cryptography not installed"
    fi
    KEY_DIR="$TEST_DIR/audit-keys"
    mkdir -p "$KEY_DIR"
    chmod 700 "$KEY_DIR"

    python3 - "$KEY_DIR" <<'PY'
import sys
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization
key_dir = Path(sys.argv[1])
priv = ed25519.Ed25519PrivateKey.generate()
priv_b = priv.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption())
pub_b = priv.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo)
(key_dir / "panelist-1.priv").write_bytes(priv_b)
(key_dir / "panelist-1.priv").chmod(0o600)
(key_dir / "panelist-1.pub").write_bytes(pub_b)
PY

    export LOA_AUDIT_KEY_DIR="$KEY_DIR"
    export LOA_AUDIT_SIGNING_KEY_ID="panelist-1"

    panel_log_views "decision-signed" '[{"id":"alpha","model":"x","persona_path":"p.md","view":"v1","reasoning_summary":"r1"}]' "$LOG"

    head -n 1 "$LOG" | jq -e '(.signature | length) > 0 and .signing_key_id == "panelist-1"' >/dev/null
}
