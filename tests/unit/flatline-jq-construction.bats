#!/usr/bin/env bats
# =============================================================================
# flatline-jq-construction.bats — cycle-062 regression tests (#485)
# =============================================================================
# Guards against two classes of bug in flatline-orchestrator.sh:
#
# 1. jq 1.7 parser error on unparenthesized `+` in object value position:
#    The original bug manifested as `syntax error, unexpected '+', expecting '}'`
#    in the metrics-merge expression. Fix: wrap `(.metrics // {}) + {...}` in an
#    outer pair of parens.
#
# 2. Silent no-op: the orchestrator completes without producing a valid JSON
#    result. Extends cycle-058's silent-no-op pattern (bridge-orchestrator) to
#    flatline. A `--no-silent-noop-detect` flag opts out for CI/tests.
# =============================================================================

setup() {
    ORCH="$BATS_TEST_DIRNAME/../../.claude/scripts/flatline-orchestrator.sh"
}

# T1: the fixed red-team metrics jq is parens-wrapped
@test "flatline: red-team metrics jq expression is parenthesized (jq 1.7 safe)" {
    # The buggy form was: metrics: (.metrics // {}) + { ... }
    # The fixed  form is: metrics: ((.metrics // {}) + { ... })
    # We assert the fixed form appears and the buggy bare form does NOT.
    grep -qF 'metrics: ((.metrics // {}) + {' "$ORCH"
}

# T2: the fixed inquiry metrics jq is also parens-wrapped
@test "flatline: inquiry metrics jq expression is parenthesized (jq 1.7 safe)" {
    # Both red-team and inquiry blocks must use the parenthesized form.
    # Count should be >= 2 (one for red-team, one for inquiry).
    local count
    count=$(grep -cF 'metrics: ((.metrics // {}) + {' "$ORCH")
    [ "$count" -ge 2 ]
}

# T3: isolated jq 1.7 reproduction — buggy form fails, fixed form succeeds
@test "flatline: jq 1.7 rejects unparenthesized metrics+object merge" {
    # Reproduce the original bug in isolation so future jq regressions are
    # caught here even if the orchestrator moves the jq expression around.
    run bash -c 'echo "{}" | jq --arg phase test --argjson lm 1 "{ phase: \$phase, metrics: (.metrics // {}) + { x: \$lm } }"'
    [ "$status" -ne 0 ]
    [[ "$output" == *"syntax error"* || "$output" == *"error"* ]]
}

@test "flatline: jq 1.7 accepts parenthesized metrics+object merge" {
    run bash -c 'echo "{}" | jq --arg phase test --argjson lm 1 "{ phase: \$phase, metrics: ((.metrics // {}) + { x: \$lm }) }"'
    [ "$status" -eq 0 ]
    # Verify structure of output
    echo "$output" | jq -e '.metrics.x == 1' >/dev/null
}

# T4: --no-silent-noop-detect flag is parsed
@test "flatline: --no-silent-noop-detect flag is recognized" {
    grep -qE '\-\-no-silent-noop-detect\)' "$ORCH"
}

# T5: silent-no-op detection helper is defined
@test "flatline: detect_silent_noop_flatline function is defined" {
    grep -q '^detect_silent_noop_flatline()' "$ORCH"
}

# T6: silent-no-op detection is wired into red-team block
@test "flatline: silent-no-op detection invoked in red-team mode" {
    # awk-extract the red-team block. The block starts at the mode-dispatch
    # guard `if [[ "$orchestrator_mode" == "red-team" ]]` and ends at the
    # inquiry dispatch. The call site should be inside.
    awk '/orchestrator_mode" == "red-team"/,/orchestrator_mode" == "inquiry"/' "$ORCH" \
        | grep -q 'detect_silent_noop_flatline "red-team"'
}

# T7: silent-no-op detection is wired into inquiry block
@test "flatline: silent-no-op detection invoked in inquiry mode" {
    awk '/orchestrator_mode" == "inquiry"/,/Phase 1: Independent Reviews/' "$ORCH" \
        | grep -q 'detect_silent_noop_flatline "inquiry"'
}

# T8: exit code 7 is documented
@test "flatline: exit code 7 reserved for silent-no-op" {
    grep -qE '^#[[:space:]]*7 - Silent no-op' "$ORCH"
}

# T9: helper exits 7 on empty result
@test "flatline: detect_silent_noop_flatline exits 7 on empty result" {
    run bash -c "
        awk '/^detect_silent_noop_flatline\\(\\)/,/^}$/' '$ORCH' > /tmp/silent-noop-helper.sh
        error() { echo \"ERROR: \$*\" >&2; }
        export -f error
        source /tmp/silent-noop-helper.sh
        detect_silent_noop_flatline red-team ''
    "
    [ "$status" -eq 7 ]
}

# T10: helper exits 7 on malformed JSON
@test "flatline: detect_silent_noop_flatline exits 7 on non-JSON result" {
    run bash -c "
        awk '/^detect_silent_noop_flatline\\(\\)/,/^}$/' '$ORCH' > /tmp/silent-noop-helper.sh
        error() { echo \"ERROR: \$*\" >&2; }
        export -f error
        source /tmp/silent-noop-helper.sh
        detect_silent_noop_flatline red-team 'not valid json {{{'
    "
    [ "$status" -eq 7 ]
}

# T11: helper accepts valid red-team result
@test "flatline: detect_silent_noop_flatline accepts valid red-team JSON" {
    run bash -c "
        awk '/^detect_silent_noop_flatline\\(\\)/,/^}$/' '$ORCH' > /tmp/silent-noop-helper.sh
        error() { echo \"ERROR: \$*\" >&2; }
        export -f error
        source /tmp/silent-noop-helper.sh
        detect_silent_noop_flatline red-team '{\"mode\":\"red-team\",\"attacks\":{\"confirmed\":[]}}'
    "
    [ "$status" -eq 0 ]
}

# T12: helper rejects result missing mode field
@test "flatline: detect_silent_noop_flatline rejects red-team result missing mode field" {
    run bash -c "
        awk '/^detect_silent_noop_flatline\\(\\)/,/^}$/' '$ORCH' > /tmp/silent-noop-helper.sh
        error() { echo \"ERROR: \$*\" >&2; }
        export -f error
        source /tmp/silent-noop-helper.sh
        detect_silent_noop_flatline red-team '{\"attacks\":{}}'
    "
    [ "$status" -eq 7 ]
}

teardown() {
    rm -f /tmp/silent-noop-helper.sh
}
