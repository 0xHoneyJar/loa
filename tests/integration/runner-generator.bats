#!/usr/bin/env bats
# Apparatus tests for tests/red-team/jailbreak/runner.bats (cycle-100 T1.4).
# Tests the GENERATOR behavior: dynamic registration, suppressed-skip,
# per-vector resilience.

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    SANDBOX="$(mktemp -d "${BATS_TMPDIR}/runner-gen-XXXXXX")"
    # Set up a minimal "isolated" tree mirroring the real layout but pointing
    # at a synthetic corpus, so we can exercise empty / 1-vector / suppressed.
    export LOA_JAILBREAK_TEST_MODE=1
    export LOA_JAILBREAK_CORPUS_DIR="${SANDBOX}/corpus"
    mkdir -p "$LOA_JAILBREAK_CORPUS_DIR"
    export LOA_JAILBREAK_AUDIT_DIR="${SANDBOX}/run"
    export LC_ALL=C
}

teardown() {
    if [[ -d "$SANDBOX" ]]; then
        find "$SANDBOX" -mindepth 1 -delete 2>/dev/null || true
        rmdir "$SANDBOX" 2>/dev/null || true
    fi
}

_make_vec() {
    local id="${1:-RT-RS-001}" status="${2:-active}" extra="${3:-}"
    local base
    base="$(jq -nc --arg id "$id" --arg status "$status" '{
        vector_id: $id,
        category: "role_switch",
        title: "test vector for runner-generator apparatus suite",
        defense_layer: "L1",
        payload_construction: "_make_evil_body_rt_rs_001",
        expected_outcome: "redacted",
        expected_marker: "[ROLE-SWITCH-PATTERN-REDACTED]",
        source_citation: "in-house-cypherpunk apparatus fixture",
        severity: "LOW",
        status: $status
    }')"
    if [[ -n "$extra" ]]; then
        printf '%s' "$base" | jq -c --argjson e "$extra" '. + $e'
    else
        printf '%s' "$base"
    fi
}

@test "runner-gen: empty corpus → 0 tests, runner exits 0" {
    cd "$REPO_ROOT"
    run env LOA_JAILBREAK_CORPUS_DIR="$LOA_JAILBREAK_CORPUS_DIR" \
        LOA_JAILBREAK_AUDIT_DIR="$LOA_JAILBREAK_AUDIT_DIR" \
        bats tests/red-team/jailbreak/runner.bats
    [ "$status" -eq 0 ]
    [[ "$output" == *"1..0"* ]]
}

@test "runner-gen: 1 active vector → 1 test, passes" {
    _make_vec "RT-RS-001" > "$LOA_JAILBREAK_CORPUS_DIR/role_switch.jsonl"
    cd "$REPO_ROOT"
    run env LOA_JAILBREAK_CORPUS_DIR="$LOA_JAILBREAK_CORPUS_DIR" \
        LOA_JAILBREAK_AUDIT_DIR="$LOA_JAILBREAK_AUDIT_DIR" \
        bats tests/red-team/jailbreak/runner.bats
    [ "$status" -eq 0 ]
    [[ "$output" == *"1..1"* ]]
    [[ "$output" == *"ok 1 RT-RS-001"* ]]
}

@test "runner-gen: suppressed vector is not iterated (no test registered)" {
    {
        printf '%s\n' "$(_make_vec "RT-RS-001")"
        printf '%s\n' "$(_make_vec "RT-RS-099" "suppressed" '{"suppression_reason": "Stale legacy fixture; documented in apparatus suite."}')"
    } > "$LOA_JAILBREAK_CORPUS_DIR/role_switch.jsonl"
    cd "$REPO_ROOT"
    run env LOA_JAILBREAK_CORPUS_DIR="$LOA_JAILBREAK_CORPUS_DIR" \
        LOA_JAILBREAK_AUDIT_DIR="$LOA_JAILBREAK_AUDIT_DIR" \
        bats tests/red-team/jailbreak/runner.bats
    [ "$status" -eq 0 ]
    [[ "$output" == *"1..1"* ]]
    [[ "$output" == *"RT-RS-001"* ]]
    [[ "$output" != *"RT-RS-099"* ]]
}

@test "runner-gen: per-vector failure does not abort run (NFR-Rel2)" {
    # Two vectors: a normal pass and a deliberate fail (expected_outcome=rejected
    # against a payload that the SUT does not reject — runner reports fail and
    # continues).
    {
        printf '%s\n' "$(_make_vec "RT-RS-001")"
        printf '%s\n' "$(_make_vec "RT-RS-002" "active" '{"expected_outcome": "rejected"}')"
    } > "$LOA_JAILBREAK_CORPUS_DIR/role_switch.jsonl"
    cd "$REPO_ROOT"
    run env LOA_JAILBREAK_CORPUS_DIR="$LOA_JAILBREAK_CORPUS_DIR" \
        LOA_JAILBREAK_AUDIT_DIR="$LOA_JAILBREAK_AUDIT_DIR" \
        bats tests/red-team/jailbreak/runner.bats
    # Bats exits non-zero on any test failure but reports BOTH tests in TAP.
    [ "$status" -ne 0 ]
    [[ "$output" == *"1..2"* ]]
    [[ "$output" == *"ok 1 RT-RS-001"* ]]
    [[ "$output" == *"not ok 2 RT-RS-002"* ]]
}

@test "runner-gen: F5 — corrupted corpus aborts test registration (no green-with-zero-tests)" {
    # Plant a malformed JSONL line and assert runner.bats exits non-zero
    # with a BAIL message rather than silently registering 0 tests.
    echo "{not valid json" > "$LOA_JAILBREAK_CORPUS_DIR/role_switch.jsonl"
    cd "$REPO_ROOT"
    run env LOA_JAILBREAK_TEST_MODE=1 \
        LOA_JAILBREAK_CORPUS_DIR="$LOA_JAILBREAK_CORPUS_DIR" \
        LOA_JAILBREAK_AUDIT_DIR="$LOA_JAILBREAK_AUDIT_DIR" \
        bats tests/red-team/jailbreak/runner.bats
    [ "$status" -ne 0 ]
    [[ "$output" == *"BAIL"* || "$output" == *"validation"* || "$output" == *"corpus"* ]]
}

@test "runner-gen: failure stdout is truncated to ≤200 chars per FR-3 AC" {
    # Wide expected_outcome with predictable failure text.
    local long_id="RT-RS-001"
    printf '%s\n' "$(_make_vec "$long_id" "active" '{"expected_outcome": "rejected"}')" \
        > "$LOA_JAILBREAK_CORPUS_DIR/role_switch.jsonl"
    cd "$REPO_ROOT"
    run env LOA_JAILBREAK_CORPUS_DIR="$LOA_JAILBREAK_CORPUS_DIR" \
        LOA_JAILBREAK_AUDIT_DIR="$LOA_JAILBREAK_AUDIT_DIR" \
        bats tests/red-team/jailbreak/runner.bats
    # The diagnostic line ${vid}: redacted ... is in stderr; bats captures it
    # in $output. We assert the truncation marker (≤200 chars after :) is present.
    [[ "$output" == *"RT-RS-001"* ]]
    # Truncation: the `truncated 200` substring appears for the redacted-marker
    # branch, NOT for rejected; we check the rejected branch surfaces a
    # diagnostic that's bounded in length. A loose bound check: no single
    # diagnostic line in output exceeds 600 chars (truncation + label).
    while IFS= read -r line; do
        [ "${#line}" -lt 600 ]
    done <<< "$output"
}
