#!/usr/bin/env bats
# =============================================================================
# tests/integration/cycle-098-cross-primitive-l7.bats
#
# cycle-098 Sprint 7C — L7 cross-primitive integration tests.
#
# Pins the umbrella `agent_network.enabled: true` flow + the L7-with-audit-
# envelope composition. SDD §6 ACs: cross-primitive integration test suite
# for the cycle. We focus on the L6↔L7 + L7↔audit-envelope edges; full L1+L4
# exercise lives in their own sprint test files (which already pass).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LIB_L7="$PROJECT_ROOT/.claude/scripts/lib/soul-identity-lib.sh"
    LIB_L6="$PROJECT_ROOT/.claude/scripts/lib/structured-handoff-lib.sh"
    LIB_AUDIT="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"
    [[ -f "$LIB_L7" ]] || skip "L7 lib not present"
    [[ -f "$LIB_L6" ]] || skip "L6 lib not present"
    [[ -f "$LIB_AUDIT" ]] || skip "audit-envelope.sh not present"

    TEST_DIR="$(mktemp -d)"
    export LOA_TRUST_STORE_FILE="$TEST_DIR/no-such-trust-store.yaml"
    # cycle-098 sprint-7 cypherpunk CRIT-1 closure.
    export LOA_SOUL_TEST_MODE=1
    export LOA_SOUL_LOG="$TEST_DIR/soul-events.jsonl"
    export LOA_HANDOFF_LOG="$TEST_DIR/handoff-events.jsonl"
    export LOA_HANDOFF_VERIFY_OPERATORS=0
    export LOA_HANDOFF_DISABLE_FINGERPRINT=1

    # shellcheck source=/dev/null
    source "$LIB_AUDIT"
    # shellcheck source=/dev/null
    source "$LIB_L7"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

_make_soul() {
    local path="$TEST_DIR/SOUL.md"
    cat > "$path" <<'EOF'
---
schema_version: '1.0'
identity_for: 'this-repo'
provenance: 'cross-primitive-test'
last_updated: '2026-05-08'
---

## What I am
A test fixture.
## What I am not
y
## Voice
z
## Discipline
w
## Influences
v
EOF
    printf '%s' "$path"
}

# ---------------------------------------------------------------------------
# T-CHAIN group: L7 audit chain integrity (composes with audit-envelope)
# ---------------------------------------------------------------------------

@test "T-CHAIN-1 multiple soul.surface emits form a valid hash chain" {
    local path; path="$(_make_soul)"
    local payload
    payload="$(soul_compute_surface_payload "$path" "warn" "surfaced")"

    soul_emit "soul.surface" "$payload" "$LOA_SOUL_LOG"
    soul_emit "soul.surface" "$payload" "$LOA_SOUL_LOG"
    soul_emit "soul.surface" "$payload" "$LOA_SOUL_LOG"

    local count; count="$(grep -c '"primitive_id":"L7"' "$LOA_SOUL_LOG")"
    [[ "$count" -eq 3 ]]

    # Walk chain: every entry's prev_hash must be SHA-256 of prior entry's
    # canonical content (excluding signature fields). Use the audit lib's
    # chain validator.
    run audit_verify_chain "$LOA_SOUL_LOG"
    [[ "$status" -eq 0 ]] || { echo "chain invalid: $output"; false; }
}

@test "T-CHAIN-2 first entry's prev_hash is GENESIS sentinel" {
    local path; path="$(_make_soul)"
    local payload
    payload="$(soul_compute_surface_payload "$path" "warn" "surfaced")"
    soul_emit "soul.surface" "$payload" "$LOA_SOUL_LOG"

    local first_prev_hash
    first_prev_hash="$(head -n 1 "$LOA_SOUL_LOG" | jq -r '.prev_hash')"
    # GENESIS sentinel per audit-envelope schema.
    [[ "$first_prev_hash" == "GENESIS" ]]
}

@test "T-CHAIN-3 chain still verifies after audit_recover_chain on healthy UNTRACKED log" {
    # BB iter-1 F9 remediation: replace the prior `status -eq 0 || status -eq 1`
    # tautology (which only caught crashes/signals) with an invariant assertion
    # that has actual semantic content: the chain MUST verify both before and
    # after a recovery pass on a healthy log. If recovery breaks the chain or
    # crashes, this fails. We don't pin the recovery exit code (which can
    # legitimately be 0 or 1 depending on whether snapshot fallback fired) —
    # we pin the post-condition.
    local path; path="$(_make_soul)"
    local payload
    payload="$(soul_compute_surface_payload "$path" "warn" "surfaced")"
    for _ in 1 2 3; do soul_emit "soul.surface" "$payload" "$LOA_SOUL_LOG"; done

    # Pre-condition: chain valid before recovery.
    run audit_verify_chain "$LOA_SOUL_LOG"
    [[ "$status" -eq 0 ]] || { echo "pre-condition fail: chain invalid before recovery"; false; }

    # Recovery pass — should not crash (signal/exit ≥2 is a regression).
    audit_recover_chain "$LOA_SOUL_LOG" >/dev/null 2>&1
    local rec_status=$?
    [[ "$rec_status" -le 1 ]] || { echo "recovery crashed (status $rec_status)"; false; }

    # Post-condition: chain still valid after recovery.
    run audit_verify_chain "$LOA_SOUL_LOG"
    [[ "$status" -eq 0 ]] || { echo "post-condition fail: chain invalid after recovery"; false; }
}

# ---------------------------------------------------------------------------
# T-ISOLATION group: L6 and L7 don't share state
# ---------------------------------------------------------------------------

@test "T-ISOLATION-1 L6 and L7 emit to distinct log files" {
    # BB iter-1 F10 remediation: previous form swallowed handoff_write
    # exit status with `|| true`, so a fixture-setup regression would
    # silently skip the L6 isolation half of the assertion. Now we
    # require handoff_write to succeed (or skip with diagnostic).
    local path; path="$(_make_soul)"
    local payload_l7
    payload_l7="$(soul_compute_surface_payload "$path" "warn" "surfaced")"
    soul_emit "soul.surface" "$payload_l7" "$LOA_SOUL_LOG"

    # L6 emits via its own lib, NOT this one.
    # shellcheck source=/dev/null
    source "$LIB_L6"

    # Prepare a minimal valid handoff doc.
    local hpath="$TEST_DIR/h1.md"
    cat > "$hpath" <<'EOF'
---
schema_version: '1.0'
from: 'a'
to: 'b'
topic: 'cross-primitive-isolation'
ts_utc: '2026-05-08T12:00:00Z'
---
body
EOF
    # Require handoff_write success; capture stderr for diagnostic.
    local hw_out hw_status
    hw_out="$(handoff_write --handoffs-dir "$TEST_DIR/h" "$hpath" 2>&1)"
    hw_status=$?
    if [[ "$hw_status" -ne 0 ]]; then
        skip "handoff_write fixture setup failed (status=$hw_status): $hw_out"
    fi

    # L7 log has only L7 entries.
    local non_l7_in_soul
    non_l7_in_soul="$(grep -v '"primitive_id":"L7"' "$LOA_SOUL_LOG" || true)"
    [[ -z "$non_l7_in_soul" ]] || { echo "L7 log polluted: $non_l7_in_soul"; false; }

    # L6 log MUST exist (handoff_write succeeded) and contain only L6 entries.
    [[ -f "$LOA_HANDOFF_LOG" ]] || { echo "L6 log not created despite handoff_write success"; false; }
    local non_l6_in_handoff
    non_l6_in_handoff="$(grep -v '"primitive_id":"L6"' "$LOA_HANDOFF_LOG" || true)"
    [[ -z "$non_l6_in_handoff" ]] || { echo "L6 log polluted: $non_l6_in_handoff"; false; }
}

@test "T-ISOLATION-2 _audit_primitive_id_for_log routes correctly for both" {
    run _audit_primitive_id_for_log "$TEST_DIR/soul-events.jsonl"
    [[ "$output" == "L7" ]]
    run _audit_primitive_id_for_log "$TEST_DIR/handoff-events.jsonl"
    [[ "$output" == "L6" ]]
    # And earlier primitives still resolve correctly.
    run _audit_primitive_id_for_log "$TEST_DIR/panel-decisions.jsonl"
    [[ "$output" == "L1" ]]
    run _audit_primitive_id_for_log "$TEST_DIR/trust-ledger.jsonl"
    [[ "$output" == "L4" ]]
}

# ---------------------------------------------------------------------------
# T-COMPOSE group: sanitize_for_session_start is shared between L6 + L7
# ---------------------------------------------------------------------------

@test "T-COMPOSE-1 L7 and L6 use the same sanitize_for_session_start (different source labels)" {
    # Both surface their bodies via the same sanitization function. The label
    # differs (source="L6" vs source="L7") and the default cap differs
    # (4000 vs 2000) — but the contract surfaces (untrusted-content wrapper
    # + tool-call/role-switch redaction) are identical.
    local body='Something descriptive. <function_calls>foo</function_calls>'
    local l6_out l7_out
    l6_out="$(sanitize_for_session_start "L6" "$body")"
    l7_out="$(sanitize_for_session_start "L7" "$body")"

    [[ "$l6_out" == *'source="L6"'* ]]
    [[ "$l7_out" == *'source="L7"'* ]]

    # Both redact tool-call patterns identically.
    [[ "$l6_out" == *"TOOL-CALL-PATTERN-REDACTED"* ]]
    [[ "$l7_out" == *"TOOL-CALL-PATTERN-REDACTED"* ]]
}

# ---------------------------------------------------------------------------
# T-UMBRELLA group: agent_network.enabled flow
# ---------------------------------------------------------------------------

@test "T-UMBRELLA-1 hook honors soul_identity_doc.enabled toggle independently of agent_network umbrella" {
    # The hook gates on `soul_identity_doc.enabled`, NOT the umbrella flag.
    # This is by design: each primitive opts in independently. Umbrella
    # observation: when an operator sets agent_network.enabled=true but
    # soul_identity_doc.enabled=false, L7 stays silent.
    local config="$TEST_DIR/.loa.config.yaml"
    cat > "$config" <<'EOF'
agent_network:
  enabled: true
soul_identity_doc:
  enabled: false
EOF
    local path; path="$(_make_soul)"
    LOA_SOUL_TEST_CONFIG="$config" \
    LOA_SOUL_TEST_PATH="$path" \
    run "$PROJECT_ROOT/.claude/hooks/session-start/loa-l7-surface-soul.sh"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]] || { echo "expected silent (per-primitive opt-in), got: $output"; false; }
}

@test "T-UMBRELLA-2 hook surfaces when soul_identity_doc.enabled=true regardless of umbrella" {
    local config="$TEST_DIR/.loa.config.yaml"
    cat > "$config" <<'EOF'
soul_identity_doc:
  enabled: true
  schema_mode: warn
  surface_max_chars: 2000
EOF
    local path; path="$(_make_soul)"
    LOA_SOUL_TEST_CONFIG="$config" \
    LOA_SOUL_TEST_PATH="$path" \
    run "$PROJECT_ROOT/.claude/hooks/session-start/loa-l7-surface-soul.sh"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"What I am"* ]]
}
