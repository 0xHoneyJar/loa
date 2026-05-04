#!/usr/bin/env bats
# =============================================================================
# tests/integration/hitl-jury-panel-signed-mode.bats
#
# cycle-098 Sprint H1 — L1 trailing-gap closure. tests/unit/panel-audit-
# envelope.bats covers the SIGN-ON-EMIT path for L1 (one entry, signature
# present); this file adds the multi-event CHAIN-VALIDATES path that the L2
# and L3 H1 files exercise — so L1 has the same end-to-end coverage shape.
#
# Coverage:
#   - panel_log_views + panel_log_bind sign every envelope
#   - audit_verify_chain validates a 3-decision chain
#   - Tampering one envelope → chain fails
# =============================================================================

load_fixtures() {
    # shellcheck source=../lib/signing-fixtures.sh
    source "${BATS_TEST_DIRNAME}/../lib/signing-fixtures.sh"
}

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    PANEL_LIB="${REPO_ROOT}/.claude/scripts/lib/hitl-jury-panel-lib.sh"
    AUDIT_ENVELOPE="${REPO_ROOT}/.claude/scripts/audit-envelope.sh"
    [[ -f "$PANEL_LIB" ]] || skip "hitl-jury-panel-lib.sh not present"
    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"

    load_fixtures
    signing_fixtures_setup --strict --key-id "test-panel-writer"

    PANEL_LOG="${TEST_DIR}/panel-decisions.jsonl"

    # shellcheck source=/dev/null
    source "$AUDIT_ENVELOPE"
    # shellcheck source=/dev/null
    source "$PANEL_LIB"
}

teardown() {
    if declare -f signing_fixtures_teardown >/dev/null 2>&1; then
        signing_fixtures_teardown
    fi
}

# Helper: a 3-panelist views payload.
_views_payload() {
    jq -nc '[
        {id:"alpha",model:"claude-opus-4-7",persona_path:"a.md",view:"v1",reasoning_summary:"r1"},
        {id:"beta",model:"claude-opus-4-7",persona_path:"b.md",view:"v2",reasoning_summary:"r2"},
        {id:"gamma",model:"claude-opus-4-7",persona_path:"c.md",view:"v3",reasoning_summary:"r3"}
    ]'
}

# -----------------------------------------------------------------------------
# Sign-on-emit
# -----------------------------------------------------------------------------

@test "L1 signed-mode: panel_log_views emits SIGNED envelope" {
    panel_log_views "dec-1" "$(_views_payload)" "$PANEL_LOG"
    [ -f "$PANEL_LOG" ]
    run jq -sr '.[] | select(.event_type == "panel.solicit") | .signature' "$PANEL_LOG"
    [ -n "$output" ]
    [ "$output" != "null" ]
    run jq -sr '.[] | select(.event_type == "panel.solicit") | .signing_key_id' "$PANEL_LOG"
    [ "$output" = "test-panel-writer" ]
}

# -----------------------------------------------------------------------------
# Chain validates across multiple panel decisions
# -----------------------------------------------------------------------------

@test "L1 signed-mode: chain validates across 3 successive panel decisions" {
    panel_log_views "dec-1" "$(_views_payload)" "$PANEL_LOG"
    panel_log_views "dec-2" "$(_views_payload)" "$PANEL_LOG"
    panel_log_views "dec-3" "$(_views_payload)" "$PANEL_LOG"
    run audit_verify_chain "$PANEL_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "L1 signed-mode: every L1 entry on chain carries signature + signing_key_id" {
    panel_log_views "dec-1" "$(_views_payload)" "$PANEL_LOG"
    panel_log_views "dec-2" "$(_views_payload)" "$PANEL_LOG"
    local n_total n_signed
    n_total="$(jq -sr '[.[] | select(.primitive_id == "L1")] | length' "$PANEL_LOG")"
    n_signed="$(jq -sr '[.[] | select(.primitive_id == "L1") | select(.signature != null and .signing_key_id != null)] | length' "$PANEL_LOG")"
    [ "$n_total" -eq "$n_signed" ]
    [ "$n_signed" -ge 2 ]
}

# -----------------------------------------------------------------------------
# Tamper detection
# -----------------------------------------------------------------------------

@test "L1 signed-mode: stripping signature → chain FAILS" {
    panel_log_views "dec-1" "$(_views_payload)" "$PANEL_LOG"
    panel_log_views "dec-2" "$(_views_payload)" "$PANEL_LOG"
    panel_log_views "dec-3" "$(_views_payload)" "$PANEL_LOG"
    local tmp
    tmp="${TEST_DIR}/strip-tampered.jsonl"
    {
        sed -n '1p' "$PANEL_LOG"
        sed -n '2p' "$PANEL_LOG" | jq -c 'del(.signature)'
        sed -n '3p' "$PANEL_LOG"
    } > "$tmp"
    run audit_verify_chain "$tmp"
    [ "$status" -ne 0 ]
}

@test "L1 signed-mode: corrupting payload → chain FAILS" {
    panel_log_views "dec-1" "$(_views_payload)" "$PANEL_LOG"
    panel_log_views "dec-2" "$(_views_payload)" "$PANEL_LOG"
    local tmp
    tmp="${TEST_DIR}/payload-tampered.jsonl"
    {
        sed -n '1p' "$PANEL_LOG"
        sed -n '2p' "$PANEL_LOG" | jq -c '.payload.decision_id = "fraudulent-id"'
    } > "$tmp"
    run audit_verify_chain "$tmp"
    [ "$status" -ne 0 ]
}
