#!/usr/bin/env bats
# Apparatus tests for tests/red-team/jailbreak/lib/corpus_loader.sh (cycle-100 T1.2)

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    LOADER="${REPO_ROOT}/tests/red-team/jailbreak/lib/corpus_loader.sh"
    BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    SANDBOX="$(mktemp -d "${BATS_TMPDIR}/corpus-loader-XXXXXX")"
    export LOA_JAILBREAK_TEST_MODE=1
    export LOA_JAILBREAK_CORPUS_DIR="${SANDBOX}/corpus"
    mkdir -p "$LOA_JAILBREAK_CORPUS_DIR"
    export LC_ALL=C
}

teardown() {
    rm -rf "$SANDBOX"
}

# Build a minimal valid vector JSON; allow overrides via env vars `V_<key>`.
_make_vec() {
    local id="${1:-RT-RS-001}" status="${2:-active}" extra="${3:-}"
    local base
    base="$(jq -nc --arg id "$id" --arg status "$status" '{
        vector_id: $id,
        category: "role_switch",
        title: "test vector for bats apparatus",
        defense_layer: "L1",
        payload_construction: "_make_evil_body_x",
        expected_outcome: "redacted",
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

@test "loader: validate-all on empty corpus exits 0" {
    run bash "$LOADER" validate-all
    [ "$status" -eq 0 ]
}

@test "loader: validate-all on valid single vector exits 0" {
    _make_vec "RT-RS-001" > "$LOA_JAILBREAK_CORPUS_DIR/role_switch.jsonl"
    run bash "$LOADER" validate-all
    [ "$status" -eq 0 ]
}

@test "loader: validate-all strips ^# comments before parsing" {
    {
        echo "# schema-major: 1"
        echo "# section: prototypical role-switch vectors"
        echo ""
        _make_vec "RT-RS-001"
    } > "$LOA_JAILBREAK_CORPUS_DIR/role_switch.jsonl"
    run bash "$LOADER" validate-all
    [ "$status" -eq 0 ]
}

@test "loader: validate-all detects bad vector_id pattern" {
    _make_vec "rs-001" > "$LOA_JAILBREAK_CORPUS_DIR/role_switch.jsonl"
    run bash "$LOADER" validate-all
    [ "$status" -ne 0 ]
    [[ "$output" == *"vector_id"* ]] || [[ "$output" == *"pattern"* ]]
}

@test "loader: validate-all detects duplicate vector_id across files" {
    _make_vec "RT-RS-001" > "$LOA_JAILBREAK_CORPUS_DIR/a.jsonl"
    _make_vec "RT-RS-001" > "$LOA_JAILBREAK_CORPUS_DIR/b.jsonl"
    run bash "$LOADER" validate-all
    [ "$status" -ne 0 ]
    [[ "$output" == *"duplicate vector_id"* ]]
}

@test "loader: validate-all rejects suppressed without suppression_reason" {
    _make_vec "RT-RS-001" "suppressed" > "$LOA_JAILBREAK_CORPUS_DIR/role_switch.jsonl"
    run bash "$LOADER" validate-all
    [ "$status" -ne 0 ]
}

@test "loader: validate-all rejects extra property (additionalProperties:false)" {
    local base
    base="$(_make_vec "RT-RS-001")"
    printf '%s' "$base" | jq -c '. + {bogus_extra: "no"}' > "$LOA_JAILBREAK_CORPUS_DIR/role_switch.jsonl"
    run bash "$LOADER" validate-all
    [ "$status" -ne 0 ]
}

@test "loader: iter-active emits only active vectors sorted by vector_id" {
    {
        _make_vec "RT-RS-005"
        _make_vec "RT-RS-002"
        printf '%s\n' "$(_make_vec "RT-RS-099" "superseded" | jq -c '. + {superseded_by: "RT-RS-002"}')"
    } > "$LOA_JAILBREAK_CORPUS_DIR/role_switch.jsonl"
    run bash "$LOADER" iter-active
    [ "$status" -eq 0 ]
    # Extract just vector_ids for ordering assertion.
    ids="$(printf '%s\n' "$output" | jq -r '.vector_id')"
    expected="$(printf 'RT-RS-002\nRT-RS-005\n')"
    [ "$ids" = "$expected" ]
}

@test "loader: iter-active filters by category" {
    {
        _make_vec "RT-RS-001"
        printf '%s\n' "$(_make_vec "RT-CL-001" | jq -c '.category="credential_leak"')"
    } > "$LOA_JAILBREAK_CORPUS_DIR/mixed.jsonl"
    run bash "$LOADER" iter-active credential_leak
    [ "$status" -eq 0 ]
    [[ "$output" == *"RT-CL-001"* ]]
    [[ "$output" != *"RT-RS-001"* ]]
}

@test "loader: get-field returns category for known vector" {
    _make_vec "RT-RS-001" > "$LOA_JAILBREAK_CORPUS_DIR/f.jsonl"
    run bash "$LOADER" get-field RT-RS-001 category
    [ "$status" -eq 0 ]
    [[ "$output" == *"role_switch"* ]]
}

@test "loader: get-field exits 1 on unknown vector_id" {
    _make_vec "RT-RS-001" > "$LOA_JAILBREAK_CORPUS_DIR/f.jsonl"
    run bash "$LOADER" get-field RT-XX-999 category
    [ "$status" -eq 1 ]
}

@test "loader: count emits tab-separated active/superseded/suppressed totals" {
    {
        _make_vec "RT-RS-001"
        _make_vec "RT-RS-002"
        printf '%s\n' "$(_make_vec "RT-RS-003" "superseded" | jq -c '. + {superseded_by: "RT-RS-001"}')"
        printf '%s\n' "$(_make_vec "RT-RS-004" "suppressed" | jq -c '. + {suppression_reason: "Stale legacy fixture; kept as documented audit anchor."}')"
    } > "$LOA_JAILBREAK_CORPUS_DIR/f.jsonl"
    run bash "$LOADER" count
    [ "$status" -eq 0 ]
    [[ "$output" == *"active=2"* ]]
    [[ "$output" == *"superseded=1"* ]]
    [[ "$output" == *"suppressed=1"* ]]
}
