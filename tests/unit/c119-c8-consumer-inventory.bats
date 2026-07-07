#!/usr/bin/env bats
# Cycle-119 C8 consumer inventory regression lock.
#
# golden-path.sh's _gp_sprint_is_reviewed / _gp_sprint_is_audited were made
# structured-first (trust a LOA-VERDICT trailer when present) in this cycle.
# Six OTHER consumers read the same engineer-feedback.md / auditor-sprint-
# feedback.md files via their own prose grep and are explicitly NOT touched
# this cycle (C8: "Do NOT modify these other consumers this cycle"). These
# tests lock in their legacy (no-trailer) behavior so a future change to any
# of them is caught, and document that today's cycle-119 diff (golden-path.sh
# + verdict-derive.sh only) does not touch any of the files below.
#
# Consumer inventory (file:line references are illustrative, not load-bearing
# on line numbers moving):
#   memory-bootstrap.sh   — extract_feedback() first-line "All good"/"APPROVED" skip
#   golden-path.sh        — covered separately in golden-path-c8-verdict-trailer.bats
#   workflow-state.sh     — get_sprint_state()
#   check-prerequisites.sh — --phase audit-sprint
#   preflight.sh          — check_sprint_approved()
#   check-feedback-status.sh — main dispatch
#   spiral-evidence.sh    — _verify_review_verdict() (already covered by
#                           tests/unit/spiral-evidence.bats; re-asserted here
#                           for the C8 inventory record)

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TEST_TMPDIR="${BATS_TMPDIR:-/tmp}/c119-c8-inventory-$$"
    mkdir -p "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1"
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
}

# =============================================================================
# workflow-state.sh:101 — get_sprint_state()
# =============================================================================

@test "C8 inventory: workflow-state.sh get_sprint_state detects audit_approved (legacy, no trailer)" {
    local script="${PROJECT_ROOT}/.claude/scripts/workflow-state.sh"
    local fn
    fn=$(sed -n '/^get_sprint_state() {/,/^}/p' "$script")
    [ -n "$fn" ]

    cat > "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md" <<'EOF'
APPROVED - LET'S FUCKING GO
EOF

    run bash -c "
        $fn
        _GRIMOIRE_DIR='${TEST_TMPDIR}/grimoires/loa'
        get_sprint_state sprint-1
    "
    [ "$status" -eq 0 ]
    [ "$output" = "audit_approved" ]
}

@test "C8 inventory: workflow-state.sh get_sprint_state detects audit_changes_required (legacy, no trailer)" {
    local script="${PROJECT_ROOT}/.claude/scripts/workflow-state.sh"
    local fn
    fn=$(sed -n '/^get_sprint_state() {/,/^}/p' "$script")

    cat > "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md" <<'EOF'
CHANGES_REQUIRED: fix the bug.
EOF

    run bash -c "
        $fn
        _GRIMOIRE_DIR='${TEST_TMPDIR}/grimoires/loa'
        get_sprint_state sprint-1
    "
    [ "$status" -eq 0 ]
    [ "$output" = "audit_changes_required" ]
}

@test "C8 inventory: workflow-state.sh get_sprint_state detects review_approved (legacy, no trailer)" {
    local script="${PROJECT_ROOT}/.claude/scripts/workflow-state.sh"
    local fn
    fn=$(sed -n '/^get_sprint_state() {/,/^}/p' "$script")

    cat > "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/engineer-feedback.md" <<'EOF'
All good
EOF

    run bash -c "
        $fn
        _GRIMOIRE_DIR='${TEST_TMPDIR}/grimoires/loa'
        get_sprint_state sprint-1
    "
    [ "$status" -eq 0 ]
    [ "$output" = "review_approved" ]
}

# =============================================================================
# check-prerequisites.sh:92 — --phase audit-sprint
# =============================================================================

@test "C8 inventory: check-prerequisites.sh --phase audit-sprint passes on 'All good' (legacy)" {
    cd "${TEST_TMPDIR}"
    echo "All good" > "grimoires/loa/a2a/sprint-1/engineer-feedback.md"
    run bash "${PROJECT_ROOT}/.claude/scripts/check-prerequisites.sh" --phase audit-sprint --sprint sprint-1
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "C8 inventory: check-prerequisites.sh --phase audit-sprint fails without 'All good' (legacy)" {
    cd "${TEST_TMPDIR}"
    echo "Needs work" > "grimoires/loa/a2a/sprint-1/engineer-feedback.md"
    run bash "${PROJECT_ROOT}/.claude/scripts/check-prerequisites.sh" --phase audit-sprint --sprint sprint-1
    [ "$status" -eq 1 ]
    [[ "$output" == "MISSING|"* ]]
}

# =============================================================================
# preflight.sh:91 — check_sprint_approved()
# =============================================================================

@test "C8 inventory: preflight.sh check_sprint_approved passes on 'All good' (legacy)" {
    cd "${TEST_TMPDIR}"
    echo "All good" > "grimoires/loa/a2a/sprint-1/engineer-feedback.md"
    source "${PROJECT_ROOT}/.claude/scripts/preflight.sh"
    run check_sprint_approved sprint-1
    [ "$status" -eq 0 ]
}

@test "C8 inventory: preflight.sh check_sprint_approved fails without 'All good' (legacy)" {
    cd "${TEST_TMPDIR}"
    echo "Needs work" > "grimoires/loa/a2a/sprint-1/engineer-feedback.md"
    source "${PROJECT_ROOT}/.claude/scripts/preflight.sh"
    run check_sprint_approved sprint-1
    [ "$status" -eq 1 ]
}

# =============================================================================
# check-feedback-status.sh:33/41 — main dispatch
# =============================================================================

@test "C8 inventory: check-feedback-status.sh reports CLEAR on 'All good' (legacy)" {
    cd "${TEST_TMPDIR}"
    echo "All good" > "grimoires/loa/a2a/sprint-1/engineer-feedback.md"
    run bash "${PROJECT_ROOT}/.claude/scripts/check-feedback-status.sh" sprint-1
    [ "$status" -eq 0 ]
    [ "$output" = "CLEAR" ]
}

@test "C8 inventory: check-feedback-status.sh reports REVIEW_REQUIRED without 'All good' (legacy)" {
    cd "${TEST_TMPDIR}"
    echo "Needs work" > "grimoires/loa/a2a/sprint-1/engineer-feedback.md"
    run bash "${PROJECT_ROOT}/.claude/scripts/check-feedback-status.sh" sprint-1
    [ "$status" -eq 0 ]
    [ "$output" = "REVIEW_REQUIRED" ]
}

@test "C8 inventory: check-feedback-status.sh reports AUDIT_REQUIRED on audit CHANGES_REQUIRED (legacy)" {
    cd "${TEST_TMPDIR}"
    echo "All good" > "grimoires/loa/a2a/sprint-1/engineer-feedback.md"
    echo "CHANGES_REQUIRED: security issue" > "grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md"
    run bash "${PROJECT_ROOT}/.claude/scripts/check-feedback-status.sh" sprint-1
    [ "$status" -eq 0 ]
    [ "$output" = "AUDIT_REQUIRED" ]
}

# =============================================================================
# spiral-evidence.sh:194 — _verify_review_verdict() (already covered by
# tests/unit/spiral-evidence.bats; re-asserted here for the C8 inventory)
# =============================================================================

@test "C8 inventory: spiral-evidence.sh _verify_review_verdict still detects APPROVED (legacy)" {
    source "${PROJECT_ROOT}/.claude/scripts/spiral-evidence.sh"
    mkdir -p "${TEST_TMPDIR}/cycle-test"
    _init_flight_recorder "${TEST_TMPDIR}/cycle-test"
    echo "All good. Sprint approved." > "${TEST_TMPDIR}/feedback.md"
    run _verify_review_verdict "REVIEW" "${TEST_TMPDIR}/feedback.md"
    [ "$status" -eq 0 ]
}

# =============================================================================
# memory-bootstrap.sh:261-264 — extract_feedback() first-line skip
# =============================================================================

@test "C8 inventory: memory-bootstrap.sh skips files whose first line is 'All good'/'APPROVED' (legacy)" {
    # Isolate the exact shipped skip-check (a self-contained conditional
    # keyed only on a file's first line) rather than driving the whole
    # multi-source extraction pipeline.
    local script="${PROJECT_ROOT}/.claude/scripts/memory-bootstrap.sh"
    grep -qF 'first_line=$(head -1 "$f" 2>/dev/null || echo "")' "$script"
    grep -qF '[[ "$first_line" == "All good"* || "$first_line" == "APPROVED"* ]] && continue' "$script"

    echo "All good" > "${TEST_TMPDIR}/approved.md"
    echo "APPROVED - LET'S FUCKING GO" > "${TEST_TMPDIR}/approved2.md"
    echo "## Findings\n- something" > "${TEST_TMPDIR}/not-approved.md"

    run bash -c '
        f="$1"
        first_line=$(head -1 "$f" 2>/dev/null || echo "")
        if [[ "$first_line" == "All good"* || "$first_line" == "APPROVED"* ]]; then
            echo "SKIPPED"
        else
            echo "PROCESSED"
        fi
    ' _ "${TEST_TMPDIR}/approved.md"
    [ "$output" = "SKIPPED" ]

    run bash -c '
        f="$1"
        first_line=$(head -1 "$f" 2>/dev/null || echo "")
        if [[ "$first_line" == "All good"* || "$first_line" == "APPROVED"* ]]; then
            echo "SKIPPED"
        else
            echo "PROCESSED"
        fi
    ' _ "${TEST_TMPDIR}/not-approved.md"
    [ "$output" = "PROCESSED" ]
}
