#!/usr/bin/env bats
# =============================================================================
# tests/integration/structured-handoff-6b.bats
#
# cycle-098 Sprint 6B — collision suffix (FR-L6-4) + verify_operators
# (IMP-004 / SDD §5.13 default true). Schema_mode strict-vs-warn semantics.
#
# Sprint 6A bats covers schema/id/atomic foundations. This file pins the 6B
# additions in isolation via env-injected OPERATORS.md fixture +
# LOA_HANDOFF_VERIFY_OPERATORS=1.
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
    export LOA_HANDOFF_VERIFY_OPERATORS=1
    # Default mode strict; tests override per-case via LOA_HANDOFF_SCHEMA_MODE.
    export LOA_HANDOFF_SCHEMA_MODE=strict
    # Sprint 6D: bypass same-machine guardrail (6B exercises operators only).
    export LOA_HANDOFF_DISABLE_FINGERPRINT=1

    # OPERATORS.md fixture with three operators: alice, bob (verified) and
    # carol (offboarded → unverified per active_until in the past).
    OPERATORS_FILE="$TEST_DIR/operators.md"
    cat > "$OPERATORS_FILE" <<'EOF'
---
schema_version: "1.0"
operators:
  - id: alice
    display_name: "Alice"
    github_handle: alice-gh
    git_email: "alice@example.test"
    capabilities: [merge]
    active_since: "2026-01-01T00:00:00Z"
  - id: bob
    display_name: "Bob"
    github_handle: bob-gh
    git_email: "bob@example.test"
    capabilities: [merge]
    active_since: "2026-01-01T00:00:00Z"
  - id: carol
    display_name: "Carol"
    github_handle: carol-gh
    git_email: "carol@example.test"
    capabilities: [merge]
    active_since: "2025-01-01T00:00:00Z"
    active_until: "2025-12-31T00:00:00Z"
---

# Operators (test fixture)
EOF
    export LOA_OPERATORS_FILE="$OPERATORS_FILE"

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
    local name="$1" from="${2:-alice}" to="${3:-bob}" topic="${4:-retry-policy}" body="${5:-default body}"
    local path="$TEST_DIR/$name"
    cat > "$path" <<EOF
---
schema_version: '1.0'
from: '$from'
to: '$to'
topic: '$topic'
ts_utc: '$TEST_TS_UTC'
---
$body
EOF
    printf '%s' "$path"
}

# -----------------------------------------------------------------------------
# FR-L6-4 + IMP-010 v1.1: same-day collision suffix
# -----------------------------------------------------------------------------

@test "B1 (FR-L6-4) collision gets suffix -2.md" {
    local p1 p2
    p1="$(_make_doc col1.md alice bob retry-policy 'body 1')"
    p2="$(_make_doc col2.md alice bob retry-policy 'body 2')"
    handoff_write "$p1" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    handoff_write "$p2" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    [[ -f "$HANDOFFS_DIR/2026-05-07-alice-bob-retry-policy.md" ]]
    [[ -f "$HANDOFFS_DIR/2026-05-07-alice-bob-retry-policy-2.md" ]]
}

@test "B2 (FR-L6-4) third collision gets -3.md" {
    local p1 p2 p3
    p1="$(_make_doc c-a.md alice bob retry-policy 'body A')"
    p2="$(_make_doc c-b.md alice bob retry-policy 'body B')"
    p3="$(_make_doc c-c.md alice bob retry-policy 'body C')"
    handoff_write "$p1" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    handoff_write "$p2" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    handoff_write "$p3" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    [[ -f "$HANDOFFS_DIR/2026-05-07-alice-bob-retry-policy.md" ]]
    [[ -f "$HANDOFFS_DIR/2026-05-07-alice-bob-retry-policy-2.md" ]]
    [[ -f "$HANDOFFS_DIR/2026-05-07-alice-bob-retry-policy-3.md" ]]
}

@test "B3 (FR-L6-4) INDEX records the suffixed file path (not the base)" {
    local p1 p2
    p1="$(_make_doc cidx-a.md alice bob retry-policy 'body A')"
    p2="$(_make_doc cidx-b.md alice bob retry-policy 'body B')"
    handoff_write "$p1" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    handoff_write "$p2" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    grep -q '2026-05-07-alice-bob-retry-policy.md ' "$HANDOFFS_DIR/INDEX.md"
    grep -q '2026-05-07-alice-bob-retry-policy-2.md ' "$HANDOFFS_DIR/INDEX.md"
}

@test "B4 (FR-L6-4 internal) _handoff_resolve_collision returns base when no collision" {
    run _handoff_resolve_collision "$HANDOFFS_DIR" "fresh.md"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "fresh.md" ]]
}

@test "B5 (FR-L6-4 internal) _handoff_resolve_collision suffixes when base exists" {
    touch "$HANDOFFS_DIR/x.md"
    run _handoff_resolve_collision "$HANDOFFS_DIR" "x.md"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "x-2.md" ]]
}

@test "B6 (FR-L6-4 internal) _handoff_resolve_collision walks gaps to next free slot" {
    touch "$HANDOFFS_DIR/x.md" "$HANDOFFS_DIR/x-2.md" "$HANDOFFS_DIR/x-3.md" "$HANDOFFS_DIR/x-4.md"
    run _handoff_resolve_collision "$HANDOFFS_DIR" "x.md"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "x-5.md" ]]
}

# -----------------------------------------------------------------------------
# verify_operators: strict-mode rejection paths
# -----------------------------------------------------------------------------

@test "B7 (verify_operators strict) unknown 'from' rejected exit 3" {
    local p; p="$(_make_doc unk-from.md eve bob retry-policy 'body')"
    run handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 3 ]]
    [[ "$output" == *"strict-mode reject"* ]]
}

@test "B8 (verify_operators strict) unknown 'to' rejected exit 3" {
    local p; p="$(_make_doc unk-to.md alice frank retry-policy 'body')"
    run handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 3 ]]
}

@test "B9 (verify_operators strict) offboarded operator (active_until past) rejected" {
    local p; p="$(_make_doc offb.md alice carol retry-policy 'body')"
    run handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 3 ]]
}

# -----------------------------------------------------------------------------
# verify_operators: warn-mode never rejects
# -----------------------------------------------------------------------------

@test "B10 (verify_operators warn) unknown 'from' accepted; audit logs unverified state" {
    export LOA_HANDOFF_SCHEMA_MODE=warn
    local p; p="$(_make_doc warn-unk.md eve bob retry-policy 'body')"
    run handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 0 ]]
    # Verify audit payload reports the verification state honestly.
    local line state
    line="$(grep -v '^\[' "$LOA_HANDOFF_LOG" | head -1)"
    state="$(echo "$line" | jq -r '.payload.operator_verification')"
    [[ "$state" == "unknown" || "$state" == "unverified" ]]
}

@test "B11 (verify_operators warn) offboarded 'to' accepted; audit logs unverified" {
    export LOA_HANDOFF_SCHEMA_MODE=warn
    local p; p="$(_make_doc warn-offb.md alice carol retry-policy 'body')"
    run handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 0 ]]
    local line state
    line="$(grep -v '^\[' "$LOA_HANDOFF_LOG" | head -1)"
    state="$(echo "$line" | jq -r '.payload.operator_verification')"
    [[ "$state" == "unverified" ]]
}

# -----------------------------------------------------------------------------
# verify_operators: happy path
# -----------------------------------------------------------------------------

@test "B12 (verify_operators strict) both verified passes; audit payload says verified" {
    local p; p="$(_make_doc happy.md alice bob retry-policy 'body')"
    run handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 0 ]]
    local line state
    line="$(grep -v '^\[' "$LOA_HANDOFF_LOG" | head -1)"
    state="$(echo "$line" | jq -r '.payload.operator_verification')"
    [[ "$state" == "verified" ]]
}

# -----------------------------------------------------------------------------
# verify_operators: env-disable bypass
# -----------------------------------------------------------------------------

@test "B13 LOA_HANDOFF_VERIFY_OPERATORS=0 bypasses verification entirely" {
    export LOA_HANDOFF_VERIFY_OPERATORS=0
    local p; p="$(_make_doc bypass.md eve frank retry-policy 'body')"
    run handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 0 ]]
    local line state
    line="$(grep -v '^\[' "$LOA_HANDOFF_LOG" | head -1)"
    state="$(echo "$line" | jq -r '.payload.operator_verification')"
    [[ "$state" == "disabled" ]]
}

# -----------------------------------------------------------------------------
# Concurrency: collisions resolve cleanly under flock
# -----------------------------------------------------------------------------

@test "B14 (concurrent + collision) 5 racers on same date+from+to+topic produce 5 unique files" {
    # Disable verify (eve is unknown); focus is collision-resolve race.
    export LOA_HANDOFF_VERIFY_OPERATORS=0
    local i=0
    for i in 1 2 3 4 5; do
        local path="$TEST_DIR/race-$i.md"
        cat > "$path" <<EOF
---
schema_version: '1.0'
from: 'alice'
to: 'bob'
topic: 'race'
ts_utc: '$TEST_TS_UTC'
---
body $i (different so id is unique)
EOF
    done
    local pids=()
    for i in 1 2 3 4 5; do
        ( source "$LIB"
          handoff_write "$TEST_DIR/race-$i.md" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
        ) &
        pids+=("$!")
    done
    for pid in "${pids[@]}"; do wait "$pid"; done

    # All 5 distinct files exist (base + -2 + -3 + -4 + -5).
    local count
    count="$(ls "$HANDOFFS_DIR" | grep -c '2026-05-07-alice-bob-race')"
    [[ "$count" -eq 5 ]]
    # INDEX has 5 distinct rows.
    local rows
    rows="$(grep -c '^| sha256:' "$HANDOFFS_DIR/INDEX.md")"
    [[ "$rows" -eq 5 ]]
}

# -----------------------------------------------------------------------------
# Body integrity: collisions don't corrupt body content
# -----------------------------------------------------------------------------

@test "B15 (body integrity under collision) -2.md contains its own body, not the base's" {
    local p1 p2
    p1="$(_make_doc bint-1.md alice bob retry-policy 'BODY ONE')"
    p2="$(_make_doc bint-2.md alice bob retry-policy 'BODY TWO')"
    handoff_write "$p1" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    handoff_write "$p2" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    grep -q 'BODY ONE' "$HANDOFFS_DIR/2026-05-07-alice-bob-retry-policy.md"
    grep -q 'BODY TWO' "$HANDOFFS_DIR/2026-05-07-alice-bob-retry-policy-2.md"
    ! grep -q 'BODY TWO' "$HANDOFFS_DIR/2026-05-07-alice-bob-retry-policy.md"
    ! grep -q 'BODY ONE' "$HANDOFFS_DIR/2026-05-07-alice-bob-retry-policy-2.md"
}

# -----------------------------------------------------------------------------
# Schema-mode default semantics
# -----------------------------------------------------------------------------

@test "B16 schema_mode defaults to strict when env unset" {
    unset LOA_HANDOFF_SCHEMA_MODE
    run _handoff_schema_mode
    [[ "$status" -eq 0 ]]
    [[ "$output" == "strict" ]]
}

@test "B17 verify_operators defaults to true when env unset and no config key" {
    unset LOA_HANDOFF_VERIFY_OPERATORS
    run _handoff_should_verify_operators
    [[ "$status" -eq 0 ]]
}
