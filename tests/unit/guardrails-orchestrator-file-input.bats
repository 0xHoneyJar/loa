#!/usr/bin/env bats
# Unit tests for .claude/scripts/guardrails-orchestrator.sh's --file input mode
# (cycle-119 C1: skills MUST pass prompt text via --file, never bash argv, to
# avoid the quote-blindness FP class). --file support already existed on this
# script pre-cycle-119; these tests lock in the JSON contract's byte-shape so
# a future edit cannot silently regress it for the skills that now depend on it.

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${PROJECT_ROOT}/.claude/scripts/guardrails-orchestrator.sh"
    TEST_TMPDIR="${BATS_TMPDIR:-/tmp}/guardrails-orch-test-$$"
    mkdir -p "${TEST_TMPDIR}"
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
}

skip_if_no_jq() {
    command -v jq &>/dev/null || skip "jq not installed"
}

@test "guardrails-orchestrator: --file reads prompt text from a file (not argv)" {
    skip_if_no_jq
    echo "Implement feature X" > "${TEST_TMPDIR}/prompt.txt"
    run "$SCRIPT" --skill implementing-tasks --file "${TEST_TMPDIR}/prompt.txt"
    [ "$status" -eq 0 ]
    action=$(echo "$output" | jq -r '.action')
    [[ "$action" == "PROCEED" || "$action" == "WARN" || "$action" == "BLOCK" ]]
}

@test "guardrails-orchestrator: --file output has the same top-level JSON shape as --input" {
    skip_if_no_jq
    echo "Implement feature X" > "${TEST_TMPDIR}/prompt.txt"
    run "$SCRIPT" --skill implementing-tasks --file "${TEST_TMPDIR}/prompt.txt"
    [ "$status" -eq 0 ]
    file_keys=$(echo "$output" | jq -S '. | keys')

    run "$SCRIPT" --skill implementing-tasks --input "Implement feature X"
    [ "$status" -eq 0 ]
    input_keys=$(echo "$output" | jq -S '. | keys')

    [ "$file_keys" = "$input_keys" ]
}

@test "guardrails-orchestrator: --file with a missing file exits non-zero (fail-open contract for callers)" {
    run "$SCRIPT" --skill implementing-tasks --file "${TEST_TMPDIR}/does-not-exist.txt"
    [ "$status" -ne 0 ]
}

@test "guardrails-orchestrator: missing --file and --input is a usage error" {
    run "$SCRIPT" --skill implementing-tasks
    [ "$status" -ne 0 ]
}
