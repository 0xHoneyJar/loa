#!/usr/bin/env bats
# =============================================================================
# tests/integration/structured-handoff-6d.bats
#
# cycle-098 Sprint 6D — same-machine-only guardrail (SDD §1.7.1 SKP-005).
# Verifies the machine-fingerprint check refuses cross-host writes,
# initializes on first run, and emits [CROSS-HOST-REFUSED] BLOCKER to a
# staging log (NOT the canonical chain).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LIB="$PROJECT_ROOT/.claude/scripts/lib/structured-handoff-lib.sh"
    [[ -f "$LIB" ]] || skip "structured-handoff-lib.sh not present"

    TEST_DIR="$(mktemp -d)"
    HANDOFFS_DIR="$TEST_DIR/handoffs"
    mkdir -p "$HANDOFFS_DIR"

    export LOA_TRUST_STORE_FILE="$TEST_DIR/no-such-trust-store.yaml"
    export LOA_HANDOFF_LOG="$TEST_DIR/handoff-events.jsonl"
    export LOA_HANDOFF_VERIFY_OPERATORS=0

    # 6D-specific: isolated fingerprint paths (no pollution of repo .run/).
    export LOA_HANDOFF_FINGERPRINT_FILE="$TEST_DIR/machine-fingerprint"
    export LOA_HANDOFF_CROSS_HOST_STAGING="$TEST_DIR/cross-host-staging.jsonl"

    TEST_TS_UTC="2026-05-07T12:00:00Z"

    # shellcheck source=/dev/null
    source "$LIB"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

_make_doc() {
    local name="$1"
    local path="$TEST_DIR/$name"
    cat > "$path" <<EOF
---
schema_version: '1.0'
from: 'alice'
to: 'bob'
topic: 'retry-policy'
ts_utc: '$TEST_TS_UTC'
---
body
EOF
    printf '%s' "$path"
}

# -----------------------------------------------------------------------------
# Initialization on first run
# -----------------------------------------------------------------------------

@test "D1 first run initializes .run/machine-fingerprint" {
    [[ ! -f "$LOA_HANDOFF_FINGERPRINT_FILE" ]]
    export LOA_HANDOFF_FINGERPRINT_OVERRIDE="abcdef0123456789"
    local p; p="$(_make_doc init.md)"
    handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    [[ -f "$LOA_HANDOFF_FINGERPRINT_FILE" ]]
    local fp; fp="$(jq -r '.fingerprint' "$LOA_HANDOFF_FINGERPRINT_FILE")"
    [[ -n "$fp" ]]
}

@test "D2 fingerprint file has 0600 mode" {
    export LOA_HANDOFF_FINGERPRINT_OVERRIDE="abcdef0123456789"
    local p; p="$(_make_doc mode.md)"
    handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    local mode
    mode="$(stat -c '%a' "$LOA_HANDOFF_FINGERPRINT_FILE" 2>/dev/null || stat -f '%OLp' "$LOA_HANDOFF_FINGERPRINT_FILE")"
    [[ "$mode" == "600" ]]
}

@test "D3 second run on same machine succeeds (fingerprint matches)" {
    export LOA_HANDOFF_FINGERPRINT_OVERRIDE="same-machine-fp"
    local p1 p2
    p1="$(_make_doc d3a.md)"
    p2="$TEST_DIR/d3b.md"
    cat > "$p2" <<EOF
---
schema_version: '1.0'
from: 'alice'
to: 'bob'
topic: 'topic-2'
ts_utc: '$TEST_TS_UTC'
---
second body
EOF
    handoff_write "$p1" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    run handoff_write "$p2" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Cross-host refusal
# -----------------------------------------------------------------------------

@test "D4 fingerprint mismatch (cross-host) rejected with exit 6 + [CROSS-HOST-REFUSED] in staging" {
    # Initialize fingerprint on host A.
    export LOA_HANDOFF_FINGERPRINT_OVERRIDE="host-A-fingerprint"
    local p1; p1="$(_make_doc hostA.md)"
    handoff_write "$p1" --handoffs-dir "$HANDOFFS_DIR" >/dev/null

    # Now simulate host B (different fingerprint).
    export LOA_HANDOFF_FINGERPRINT_OVERRIDE="host-B-fingerprint"
    local p2="$TEST_DIR/hostB.md"
    cat > "$p2" <<EOF
---
schema_version: '1.0'
from: 'alice'
to: 'bob'
topic: 'topic-from-B'
ts_utc: '$TEST_TS_UTC'
---
attempt from machine B
EOF
    run handoff_write "$p2" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 6 ]]
    [[ "$output" == *"CROSS-HOST-REFUSED"* ]]
    [[ -f "$LOA_HANDOFF_CROSS_HOST_STAGING" ]]
    local last_event; last_event="$(tail -1 "$LOA_HANDOFF_CROSS_HOST_STAGING" | jq -r '.event')"
    [[ "$last_event" == "CROSS-HOST-REFUSED" ]]
}

@test "D5 cross-host refusal preserves canonical handoff-events log integrity (no entry written)" {
    export LOA_HANDOFF_FINGERPRINT_OVERRIDE="host-A"
    local p1; p1="$(_make_doc d5a.md)"
    handoff_write "$p1" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    local lines_before; lines_before="$(grep -cv '^\[' "$LOA_HANDOFF_LOG" || echo 0)"

    export LOA_HANDOFF_FINGERPRINT_OVERRIDE="host-B"
    local p2; p2="$(_make_doc d5b.md)"
    run handoff_write "$p2" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 6 ]]

    # Canonical log unchanged — no L6 entry from the refused write.
    local lines_after; lines_after="$(grep -cv '^\[' "$LOA_HANDOFF_LOG" || echo 0)"
    [[ "$lines_before" -eq "$lines_after" ]]
}

@test "D6 staging entry includes recovery_hint pointing operator at /loa machine-fingerprint regenerate" {
    export LOA_HANDOFF_FINGERPRINT_OVERRIDE="host-A"
    handoff_write "$(_make_doc d6a.md)" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    export LOA_HANDOFF_FINGERPRINT_OVERRIDE="host-B"
    run handoff_write "$(_make_doc d6b.md)" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 6 ]]
    local hint
    hint="$(tail -1 "$LOA_HANDOFF_CROSS_HOST_STAGING" | jq -r '.recovery_hint')"
    [[ "$hint" == *"machine-fingerprint regenerate"* ]]
}

@test "D7 unparseable fingerprint file rejected with exit 6" {
    # Pre-create an unparseable file.
    echo "not-json{{}}" > "$LOA_HANDOFF_FINGERPRINT_FILE"
    local p; p="$(_make_doc d7.md)"
    run handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 6 ]]
}

# -----------------------------------------------------------------------------
# Disable flag (test-only escape hatch)
# -----------------------------------------------------------------------------

@test "D8 LOA_HANDOFF_DISABLE_FINGERPRINT=1 bypasses the guardrail entirely" {
    export LOA_HANDOFF_DISABLE_FINGERPRINT=1
    # Pre-write a stale fingerprint so a check WOULD fail if it ran.
    mkdir -p "$(dirname "$LOA_HANDOFF_FINGERPRINT_FILE")"
    echo '{"fingerprint":"some-other-host"}' > "$LOA_HANDOFF_FINGERPRINT_FILE"

    export LOA_HANDOFF_FINGERPRINT_OVERRIDE="this-host"
    local p; p="$(_make_doc d8.md)"
    run handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Lib internal helpers
# -----------------------------------------------------------------------------

@test "D9 _handoff_compute_fingerprint emits a 64-hex SHA-256 by default" {
    unset LOA_HANDOFF_FINGERPRINT_OVERRIDE
    run _handoff_compute_fingerprint
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^[a-f0-9]{64}$ ]]
}

@test "D10 _handoff_compute_fingerprint honors override" {
    export LOA_HANDOFF_FINGERPRINT_OVERRIDE="custom-fp"
    run _handoff_compute_fingerprint
    [[ "$status" -eq 0 ]]
    [[ "$output" == "custom-fp" ]]
}

@test "D11 _handoff_init_fingerprint is idempotent" {
    export LOA_HANDOFF_FINGERPRINT_OVERRIDE="abc123"
    _handoff_init_fingerprint
    local mtime1; mtime1="$(stat -c '%Y' "$LOA_HANDOFF_FINGERPRINT_FILE" 2>/dev/null || stat -f '%m' "$LOA_HANDOFF_FINGERPRINT_FILE")"
    sleep 1
    _handoff_init_fingerprint
    local mtime2; mtime2="$(stat -c '%Y' "$LOA_HANDOFF_FINGERPRINT_FILE" 2>/dev/null || stat -f '%m' "$LOA_HANDOFF_FINGERPRINT_FILE")"
    [[ "$mtime1" == "$mtime2" ]]
}
