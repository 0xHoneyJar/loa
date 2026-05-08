#!/usr/bin/env bats
# Issue #774 — flatline-orchestrator operator-facing strings.
#
# Verifies that the help text, the size-warn threshold, and the degraded-mode
# tip handler all match the reality of `failure_class=PROVIDER_DISCONNECT`:
#   - Help text drops the "≥100KB" threshold AND names BOTH Anthropic + OpenAI
#   - Size warning fires above 30KB (not the old 100KB) with a single canonical
#     warning phrase pinned by these tests
#   - --per-call-max-tokens flag is preserved (back-compat) at the parser layer,
#     not just in --help text
#
# Hermetic: no real network, no real cheval, no real model-invoke binary.
#
# BB-iter-1 remediation (2026-05-08): assertion specificity tightened per
# F1-size-warning-disjunction (MED) + F1-help-text-contract (LOW) +
# F3-threshold-not-validated (LOW) + F4-back-compat-flag-acceptance (LOW).
# Degraded-mode tip emission path (F2-degraded-tip-untested LOW) remains
# uncovered here; it requires stub-failed-call orchestrator state which
# adds non-trivial complexity. Tracked as #774-followup.

# Canonical warning phrase the orchestrator emits at the 30KB threshold.
# Pinning ONE canonical string (not an OR over substrings) per BB F1.
readonly CANONICAL_WARN="long prompts may trip the cheval connection-loss path"

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    ORCHESTRATOR="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"

    # Per-test scratch dir — created in setup so teardown can clean even if
    # the test body fails mid-assertion. Mode 700 to avoid tmp leakage on
    # multi-user hosts. PID + bats-test-name suffix avoids collisions across
    # parallel runs.
    local slug
    slug=$(echo "${BATS_TEST_NAME:-test}" | tr -c 'A-Za-z0-9_' '_')
    SCRATCH="$PROJECT_ROOT/.run/disconnect-hint-test-$$-$slug"
    mkdir -p "$SCRATCH"
    chmod 700 "$SCRATCH"
}

teardown() {
    [[ -n "${SCRATCH:-}" && -d "$SCRATCH" ]] && rm -rf "$SCRATCH"
}

# ---- Help text ------------------------------------------------------------

@test "help text names BOTH Anthropic and OpenAI and references issue #774" {
    run bash "$ORCHESTRATOR" --help
    [ "$status" -eq 0 ]
    # Per BB F1-help-text-contract: the header promised three things and
    # the body must check all three (Anthropic + OpenAI + issue link).
    [[ "$output" == *"Anthropic"* ]]
    [[ "$output" == *"OpenAI"* ]]
    [[ "$output" == *"issue #774"* ]]
}

@test "help text --per-call-max-tokens stanza explicitly states it does NOT address PROVIDER_DISCONNECT" {
    run bash "$ORCHESTRATOR" --help
    [ "$status" -eq 0 ]
    # Pin the precise contract phrase rather than a redundant OR.
    [[ "$output" == *"does NOT address failure_class=PROVIDER_DISCONNECT"* ]]
}

@test "help text --per-call-max-tokens stanza drops the old 'use 4096' lowering recommendation" {
    run bash "$ORCHESTRATOR" --help
    [ "$status" -eq 0 ]
    # The historical operator pointer was "Use 4096 for documents ≥100KB".
    # That phrase MUST NOT appear in the operator-facing help block — its
    # presence means the misleading remedy guidance is back. (Comments
    # elsewhere in the file may still reference 100KB historically; the
    # --help output is the operator surface and must be clean.)
    [[ "$output" != *"Use 4096 for documents"* ]]
    [[ "$output" != *"≥100KB"* ]]
}

# ---- Size warning threshold (30KB instead of 100KB) -----------------------

@test "size warning fires on a 38KB document with the canonical warning phrase" {
    local fixture="$SCRATCH/big.md"
    # Create a 38KB document (matches the issue reporter's break point)
    head -c 39064 < /dev/zero | tr '\0' 'a' > "$fixture"

    run bash "$ORCHESTRATOR" --doc "$fixture" --phase prd --dry-run 2>&1
    [ "$status" -eq 0 ]
    # Pin to ONE canonical phrase (BB F1-size-warning-disjunction). The OR
    # over three substrings was masking regressions because "issue #774"
    # also leaked through unrelated help-text bleed-through.
    [[ "$output" == *"$CANONICAL_WARN"* ]]
}

@test "size warning is silent below the 30KB threshold (5KB document)" {
    local fixture="$SCRATCH/small.md"
    head -c 5120 < /dev/zero | tr '\0' 'a' > "$fixture"

    run bash "$ORCHESTRATOR" --doc "$fixture" --phase prd --dry-run 2>&1
    [ "$status" -eq 0 ]
    # Per BB F3-threshold-not-validated: exclude ALL warning identifiers
    # below the threshold, not just the canonical phrase. A drift in the
    # warning string would otherwise leak through this assertion.
    [[ "$output" != *"$CANONICAL_WARN"* ]]
    [[ "$output" != *"failure_class=PROVIDER_DISCONNECT"* ]]
}

# ---- per-call-max-tokens flag preserved (back-compat) ---------------------

@test "--per-call-max-tokens flag is documented in help" {
    run bash "$ORCHESTRATOR" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--per-call-max-tokens"* ]]
}

@test "--per-call-max-tokens flag is accepted by argument parser" {
    # Per BB F4-back-compat-flag-acceptance: documenting the flag in --help
    # is necessary but not sufficient — operators need it to actually parse.
    # Drive the parser by passing the flag with a 5KB doc + --dry-run; if
    # the parser had been removed, the orchestrator would error with
    # "Unknown option" and exit non-zero before reaching dry-run.
    local fixture="$SCRATCH/probe.md"
    head -c 5120 < /dev/zero | tr '\0' 'a' > "$fixture"

    run bash "$ORCHESTRATOR" --doc "$fixture" --phase prd \
        --per-call-max-tokens 4096 --dry-run 2>&1
    [ "$status" -eq 0 ]
    # The "Unknown option" sentinel comes from the orchestrator's argv
    # parser when an arg is unrecognized. Its absence proves the flag
    # is wired through to the parser, not just the help string.
    [[ "$output" != *"Unknown option: --per-call-max-tokens"* ]]
}
