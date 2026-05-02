#!/usr/bin/env bats
# =============================================================================
# flatline-orchestrator-phase-pr.bats — Tests for --phase pr (Issue #663)
# =============================================================================
# sprint-bug-126. Validates that the flatline-orchestrator validator at
# line ~1512 accepts `--phase pr` (the PR-context Flatline review used by
# the post-PR Bridgebuilder loop). Previously, post-pr-orchestrator passed
# `--phase pr` and flatline rejected it as "Invalid phase: pr", which the
# post-pr-orchestrator misinterpreted as a real blocker — silently halting
# the entire autonomous validation pipeline.

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export FLATLINE="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"

    # Hermetic temp doc + project root
    export TMPDIR_TEST="$(mktemp -d -p "$PROJECT_ROOT/.run" 2>/dev/null || mktemp -d)"
    export DOC_FILE="$TMPDIR_TEST/test-doc.md"
    echo "# Test PRD" >"$DOC_FILE"
    # Run dry to avoid LLM/API calls
}

teardown() {
    if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
        rm -rf "$TMPDIR_TEST"
    fi
}

# =========================================================================
# FOPP-T1..T2: --phase pr accepted (the #663 defect class)
# =========================================================================

@test "FOPP-T1: --phase pr is NOT rejected as Invalid phase" {
    cd "$PROJECT_ROOT"
    run "$FLATLINE" --doc "$DOC_FILE" --phase pr --dry-run
    # Must NOT contain the "Invalid phase: pr" error
    [[ "$output" != *"Invalid phase: pr"* ]]
    [[ "$output" != *"Invalid phase: pr (expected"* ]]
}

@test "FOPP-T2: --phase pr appears in valid_phases list" {
    grep -q '"pr"' "$FLATLINE"
}

# =========================================================================
# FOPP-T3..T7: regression guards — pre-existing phases still accepted
# =========================================================================

@test "FOPP-T3: --phase prd still accepted (regression guard)" {
    cd "$PROJECT_ROOT"
    run "$FLATLINE" --doc "$DOC_FILE" --phase prd --dry-run
    [[ "$output" != *"Invalid phase: prd"* ]]
}

@test "FOPP-T4: --phase sdd still accepted (regression guard)" {
    cd "$PROJECT_ROOT"
    run "$FLATLINE" --doc "$DOC_FILE" --phase sdd --dry-run
    [[ "$output" != *"Invalid phase: sdd"* ]]
}

@test "FOPP-T5: --phase sprint still accepted (regression guard)" {
    cd "$PROJECT_ROOT"
    run "$FLATLINE" --doc "$DOC_FILE" --phase sprint --dry-run
    [[ "$output" != *"Invalid phase: sprint"* ]]
}

@test "FOPP-T6: --phase beads still accepted (regression guard)" {
    cd "$PROJECT_ROOT"
    run "$FLATLINE" --doc "$DOC_FILE" --phase beads --dry-run
    [[ "$output" != *"Invalid phase: beads"* ]]
}

@test "FOPP-T7: --phase spec still accepted (regression guard)" {
    cd "$PROJECT_ROOT"
    run "$FLATLINE" --doc "$DOC_FILE" --phase spec --dry-run
    [[ "$output" != *"Invalid phase: spec"* ]]
}

# =========================================================================
# FOPP-T8: invalid phase still rejected
# =========================================================================

@test "FOPP-T8: --phase wibble still rejected" {
    cd "$PROJECT_ROOT"
    run "$FLATLINE" --doc "$DOC_FILE" --phase wibble --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid phase: wibble"* ]]
}

# =========================================================================
# FOPP-T9: usage docs mention pr
# =========================================================================

@test "FOPP-T9: usage docs include 'pr' in Phase type list" {
    # Both header comment block AND interactive usage() must list pr
    grep -E "Phase type:.*\bpr\b" "$FLATLINE" | head -1
    [ "$(grep -cE 'Phase type:.*\bpr\b' "$FLATLINE")" -ge 2 ]
}
