#!/usr/bin/env bats
# Unit tests for .claude/scripts/verdict-derive.sh (cycle-119 C7)
#
# Validates the LOA-VERDICT machine trailer (C6): presence/well-formedness,
# prose<->trailer agreement, the one-way critical+high>0 => CHANGES_REQUIRED
# severity rule, and the approved-review-has-no-findings-headings rule.

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${PROJECT_ROOT}/.claude/scripts/verdict-derive.sh"
    TEST_TMPDIR="${BATS_TMPDIR:-/tmp}/verdict-derive-test-$$"
    mkdir -p "${TEST_TMPDIR}"
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
}

skip_if_no_jq() {
    command -v jq &>/dev/null || skip "jq not installed"
}

# =============================================================================
# Usage / argument validation
# =============================================================================

@test "verdict-derive: missing --file is a usage error (exit 2)" {
    run "$SCRIPT" --gate review
    [ "$status" -eq 2 ]
}

@test "verdict-derive: missing --gate is a usage error (exit 2)" {
    touch "${TEST_TMPDIR}/f.md"
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md"
    [ "$status" -eq 2 ]
}

@test "verdict-derive: invalid --gate value is a usage error (exit 2)" {
    touch "${TEST_TMPDIR}/f.md"
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate bogus
    [ "$status" -eq 2 ]
}

@test "verdict-derive: nonexistent file is a usage error (exit 2)" {
    run "$SCRIPT" --file "${TEST_TMPDIR}/nope.md" --gate review
    [ "$status" -eq 2 ]
}

@test "verdict-derive: --help exits 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# =============================================================================
# Legacy files (no trailer)
# =============================================================================

@test "verdict-derive: legacy file with no trailer exits 2 by default" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good

No issues found.
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 2 ]
}

@test "verdict-derive: legacy file --json reports trailer_found=false" {
    skip_if_no_jq
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review --json
    [ "$status" -eq 2 ]
    trailer_found=$(echo "$output" | jq -r '.trailer_found')
    [ "$trailer_found" = "false" ]
}

@test "verdict-derive: legacy file with --require-trailer exits 1" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review --require-trailer
    [ "$status" -eq 1 ]
    [[ "$output" == *"require-trailer"* ]]
}

# =============================================================================
# Consistent trailers
# =============================================================================

@test "verdict-derive: approved review with matching trailer is consistent (exit 0)" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good

No issues found.
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 0 ]
}

@test "verdict-derive: --json exposes verdict/counts/consistent on success" {
    skip_if_no_jq
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":2},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.verdict')" = "APPROVED" ]
    [ "$(echo "$output" | jq -r '.consistent')" = "true" ]
    [ "$(echo "$output" | jq -r '.counts.medium')" = "1" ]
}

@test "verdict-derive: changes-required review with non-'All good' first line is consistent" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
## Changes Required

- fix the thing
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 0 ]
}

@test "verdict-derive: approved audit with exact ritual string is consistent" {
    cat > "${TEST_TMPDIR}/f.md" <<EOF
APPROVED - LET'S FUCKING GO

Sprint is solid.
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate audit
    [ "$status" -eq 0 ]
}

# =============================================================================
# Disagreement / violation cases
# =============================================================================

@test "verdict-derive: 'All good' first line but CHANGES_REQUIRED trailer is a violation" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"CHANGES_REQUIRED"* ]]
}

@test "verdict-derive: APPROVED trailer but missing 'All good' first line is a violation" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
Looks fine to me.
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"All good"* ]]
}

@test "verdict-derive: one-way rule — critical+high>0 forces CHANGES_REQUIRED" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":2,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"counts.high=2"* ]]
    [[ "$output" == *"CHANGES_REQUIRED"* ]]
}

@test "verdict-derive: one-way rule does NOT force APPROVED when counts are zero" {
    # CHANGES_REQUIRED with zero critical/high is still valid (reviewer judgment)
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
## Changes Required
- polish the docs
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":0,"medium":3,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 0 ]
}

@test "verdict-derive: approved review with a Findings heading is a violation" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good

## Findings
- minor nit
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"Findings"* ]]
}

@test "verdict-derive: approved audit missing the exact ritual string is a violation" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
Looks good, approved.
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"LET'S FUCKING GO"* ]]
}

@test "verdict-derive: non-EOF trailer (content after it) is a violation" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->

trailing content after trailer
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"last line"* ]]
}

@test "verdict-derive: multiple trailers is a violation" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:01Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"multiple LOA-VERDICT"* ]]
}

@test "verdict-derive: malformed JSON trailer is a violation" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good
<!-- LOA-VERDICT {gate: review, verdict: APPROVED} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"not valid JSON"* ]]
}

@test "verdict-derive: trailer gate mismatch vs requested --gate is a violation" {
    cat > "${TEST_TMPDIR}/f.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md" --gate review
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not match requested --gate"* ]]
}
