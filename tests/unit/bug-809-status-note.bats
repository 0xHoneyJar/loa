#!/usr/bin/env bats
# =============================================================================
# bug-809-status-note.bats — issue #809 + #866/#868 residues:
#   1. adversarial-review.sh STATE-3 zero-findings emission said bare
#      `status: clean` — operators/consumers read empty findings as
#      affirmative approval. Additive status_note qualifies it.
#   2. flatline-orchestrator.sh document-size warning referenced CLOSED #774.
#   3. adversarial-review.sh never passed --phase, so model-adapter logged
#      cosmetic "Phase: prd" on review/audit calls.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    ADV="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    FLAT="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

@test "bug-809: STATE-3 clean emission carries a status_note qualifier (shape)" {
    # The zero-findings jq emission must include status_note alongside
    # status: "clean" (backward-compat field retained).
    grep -B 3 -A 8 'STATE 3: Empty findings' "$ADV" | grep -q 'status_note'
    grep -B 3 -A 8 'STATE 3: Empty findings' "$ADV" | grep -q '"clean"'
}

@test "bug-809: status_note text disclaims approval of unreviewed surface" {
    grep -q 'not an approval' "$ADV"
}

@test "bug-809: functional — process_findings on zero findings emits status_note" {
    source "$PROJECT_ROOT/.claude/scripts/lib-content.sh"
    source "$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
    eval "$(sed 's/^main "\$@"/# main disabled for testing/' "$ADV")"
    local out
    # raw_response is the model-adapter envelope; arg 6 (diff_files) is
    # required under set -u.
    out=$(process_findings '{"content": "{\"findings\": []}"}' "review" "test-model" "sprint-test" 0 "" 2>/dev/null)
    [ "$(echo "$out" | jq -r '.metadata.status')" = "clean" ]
    [ "$(echo "$out" | jq -r '.metadata.status_note')" != "null" ]
    [[ "$(echo "$out" | jq -r '.metadata.status_note')" == *"not an approval"* ]]
}

@test "bug-866-residue: flatline doc-size warning no longer references closed #774" {
    # Scoped to the operator-facing document-size warning only.
    ! grep -E 'WARNING: Document size' -A 1 "$FLAT" | grep -q '#774'
}

@test "bug-868-residue: adversarial-review passes --phase to model-adapter (both branches)" {
    [ "$(grep -c '\-\-phase' "$ADV")" -ge 2 ]
}
