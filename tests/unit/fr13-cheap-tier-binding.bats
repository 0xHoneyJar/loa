#!/usr/bin/env bats
# cycle-114 FR-13 — bind the (mechanical) flatline-scorer to the cheap tier
# (Sonnet 4.6), NOT the expensive reviewer (gpt-5.5). Adversarial voices that
# carry the load-bearing dissent quality signal must stay on their tier.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CFG="$REPO_ROOT/.claude/defaults/model-config.yaml"
    [[ -f "$CFG" ]] || skip "model-config.yaml not found"
}

@test "FR-13: flatline-scorer is bound to the cheap tier" {
    run bash -c "grep -A6 '^  flatline-scorer:' '$CFG' | grep -m1 'model:'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cheap"* ]]
    [[ "$output" != *"reviewer"* ]]
}

@test "FR-13: adversarial flatline-dissenter tier is unchanged (reasoning)" {
    run bash -c "grep -A4 '^  flatline-dissenter:' '$CFG' | grep -m1 'model:'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"reasoning"* ]]
}

@test "FR-13: the cheap tier alias resolves to a Haiku/Sonnet-class model" {
    run bash -c "grep -E '^  cheap:' '$CFG' | head -1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sonnet"* || "$output" == *"haiku"* ]]
}
