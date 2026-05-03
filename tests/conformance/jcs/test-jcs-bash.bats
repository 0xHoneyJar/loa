#!/usr/bin/env bats
# =============================================================================
# tests/conformance/jcs/test-jcs-bash.bats
#
# cycle-098 Sprint 1A — IMP-001 (HIGH_CONSENSUS 736).
# Exercises lib/jcs.sh against the conformance corpus. Verifies byte-identity
# vs the recorded `expected` outputs in test-vectors.json (which were computed
# from the Python rfc8785 reference implementation).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
    JCS_LIB="$PROJECT_ROOT/lib/jcs.sh"
    VECTORS="$SCRIPT_DIR/test-vectors.json"

    [[ -f "$JCS_LIB" ]] || skip "lib/jcs.sh not present at $JCS_LIB"
    [[ -f "$VECTORS" ]] || skip "test-vectors.json missing"
}

# -----------------------------------------------------------------------------
# Adapter availability
# -----------------------------------------------------------------------------
@test "jcs-bash: --check reports ready" {
    run bash "$JCS_LIB" --check
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"ready"* ]]
}

# -----------------------------------------------------------------------------
# Trivial canonicalization examples
# -----------------------------------------------------------------------------
@test "jcs-bash: orders object keys lexicographically" {
    run bash "$JCS_LIB" '{"b":2,"a":1}'
    [[ "$status" -eq 0 ]]
    [[ "$output" == '{"a":1,"b":2}' ]]
}

@test "jcs-bash: strips whitespace" {
    run bash "$JCS_LIB" '{"a":  1, "b" :  2}'
    [[ "$status" -eq 0 ]]
    [[ "$output" == '{"a":1,"b":2}' ]]
}

@test "jcs-bash: preserves array order (arrays are not sorted)" {
    run bash "$JCS_LIB" '[3,1,2]'
    [[ "$status" -eq 0 ]]
    [[ "$output" == '[3,1,2]' ]]
}

# -----------------------------------------------------------------------------
# Conformance corpus — one bats test per vector for granular failure reports.
# Loop over jq output to materialize per-vector tests at runtime.
# -----------------------------------------------------------------------------
@test "jcs-bash: corpus byte-identity (all vectors)" {
    # Run the bash adapter against every vector; compare bytes.
    local vector_count
    vector_count=$(jq '.vectors | length' "$VECTORS")
    [[ "$vector_count" -ge 20 ]]  # Sprint 1 AC: corpus has at least 20 vectors

    local fails=0
    local i=0
    while [[ "$i" -lt "$vector_count" ]]; do
        local vid input expected actual
        vid=$(jq -r ".vectors[$i].id" "$VECTORS")
        # Re-emit input as JSON via jq (so we get a bytes-faithful payload).
        input=$(jq -c ".vectors[$i].input" "$VECTORS")
        expected=$(jq -r ".vectors[$i].expected" "$VECTORS")
        actual=$(printf '%s' "$input" | bash "$JCS_LIB")
        if [[ "$actual" != "$expected" ]]; then
            echo "FAIL  $vid: got=$actual expected=$expected" >&2
            fails=$((fails + 1))
        fi
        i=$((i + 1))
    done
    [[ "$fails" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Determinism: same input produces same output across multiple invocations.
# -----------------------------------------------------------------------------
@test "jcs-bash: deterministic — repeated calls produce identical bytes" {
    local out1 out2
    out1=$(bash "$JCS_LIB" '{"x":1.5,"y":[1,2,3]}')
    out2=$(bash "$JCS_LIB" '{"y":[1,2,3],"x":1.5}')
    [[ "$out1" == "$out2" ]]
}
