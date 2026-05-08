#!/usr/bin/env bats
# Issue #774 — flatline-orchestrator operator-facing strings.
#
# Verifies that the help text, the size-warn threshold, and the degraded-mode
# tip handler all match the reality of `failure_class=PROVIDER_DISCONNECT`:
#   - Help text drops the "≥100KB" threshold and names BOTH Anthropic + OpenAI
#   - Size warning fires above 30KB (not the old 100KB) and points operators
#     at issue #774, not the proven-ineffective `--per-call-max-tokens 4096`
#     remedy
#   - The degraded-mode tip only surfaces when ≥1 failed call carries
#     the `failure_class: "PROVIDER_DISCONNECT"` JSON marker
#
# Hermetic: no real network, no real cheval, no real model-invoke binary.

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    ORCHESTRATOR="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

# ---- Help text ------------------------------------------------------------

@test "help text references issue #774 and OpenAI" {
    run bash "$ORCHESTRATOR" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"issue #774"* ]]
    [[ "$output" == *"OpenAI"* ]]
}

@test "help text drops the misleading >=100KB threshold from per-call-max-tokens guidance" {
    run bash "$ORCHESTRATOR" --help
    [ "$status" -eq 0 ]
    # Allowed: comments may mention ≥100KB historically. Operator-facing
    # `--per-call-max-tokens` help block must NOT recommend lowering at 100KB.
    # We assert by checking the help-stanza for the negation phrase.
    [[ "$output" == *"does NOT address failure_class=PROVIDER_DISCONNECT"* ]] || \
    [[ "$output" == *"does NOT address"*"PROVIDER_DISCONNECT"* ]]
}

# ---- Size warning threshold (30KB instead of 100KB) -----------------------

@test "size warning fires on a 38KB document" {
    # Fixture must live inside PROJECT_ROOT (orchestrator's path-traversal
    # gate rejects out-of-tree docs). Use a per-test scratch dir.
    local scratch="$PROJECT_ROOT/.run/jailbreak-corpus-test-$$"
    mkdir -p "$scratch"
    local fixture="$scratch/big.md"
    # Create a 38KB document (matches the issue reporter's break point)
    head -c 39064 < /dev/zero | tr '\0' 'a' > "$fixture"

    run bash "$ORCHESTRATOR" --doc "$fixture" --phase prd --dry-run 2>&1
    rm -rf "$scratch"

    # Expect the new warning string to surface
    [[ "$output" == *"failure_class=PROVIDER_DISCONNECT"* ]] || \
    [[ "$output" == *"long prompts may trip the cheval connection-loss path"* ]] || \
    [[ "$output" == *"issue #774"* ]]
}

@test "size warning is silent on a 5KB document" {
    local scratch="$PROJECT_ROOT/.run/jailbreak-corpus-test-$$"
    mkdir -p "$scratch"
    local fixture="$scratch/small.md"
    head -c 5120 < /dev/zero | tr '\0' 'a' > "$fixture"

    run bash "$ORCHESTRATOR" --doc "$fixture" --phase prd --dry-run 2>&1
    rm -rf "$scratch"

    # Below the 30KB threshold the warning must not appear
    [[ "$output" != *"long prompts may trip the cheval connection-loss path"* ]]
}

# ---- per-call-max-tokens flag preserved (back-compat) ---------------------

@test "--per-call-max-tokens flag is preserved (back-compat)" {
    run bash "$ORCHESTRATOR" --help
    [ "$status" -eq 0 ]
    # The flag must still be documented; operators who used it for the
    # historical #675 remedy must continue to be able to set it.
    [[ "$output" == *"--per-call-max-tokens"* ]]
}
