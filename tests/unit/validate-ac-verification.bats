#!/usr/bin/env bats
# Unit tests for .claude/scripts/validate-ac-verification.sh (cycle-119 C9)

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${PROJECT_ROOT}/.claude/scripts/validate-ac-verification.sh"
    TEST_TMPDIR="${BATS_TMPDIR:-/tmp}/validate-ac-test-$$"
    mkdir -p "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1"

    cat > "${TEST_TMPDIR}/sprint.md" <<'EOF'
## Sprint 1: Auth hardening

### Sprint Goal
Harden auth.

### Acceptance Criteria
- [ ] API returns 401 on invalid creds
- [ ] Passwords are hashed with bcrypt

### Technical Tasks
- [ ] Task 1.1: implement middleware
EOF

    cat > "${TEST_TMPDIR}/grimoires/loa/NOTES.md" <<'EOF'
# Notes

## Decision Log
- 2026-07-07: AC-1.2 deferred to sprint-2 because bcrypt lib not yet vetted.
EOF
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
}

skip_if_no_jq() {
    command -v jq &>/dev/null || skip "jq not installed"
}

# =============================================================================
# Usage errors
# =============================================================================

@test "AC-verify: missing --report is a usage error (exit 2)" {
    run "$SCRIPT" --sprint "${TEST_TMPDIR}/sprint.md"
    [ "$status" -eq 2 ]
}

@test "AC-verify: missing --sprint is a usage error (exit 2)" {
    run "$SCRIPT" --report "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md"
    [ "$status" -eq 2 ]
}

@test "AC-verify: nonexistent report file is a usage error (exit 2)" {
    run "$SCRIPT" --report "${TEST_TMPDIR}/nope.md" --sprint "${TEST_TMPDIR}/sprint.md"
    [ "$status" -eq 2 ]
}

@test "AC-verify: --help exits 0 and states honest scoping" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"HONEST SCOPING"* || "$output" == *"FABRICATED"* ]]
}

# =============================================================================
# Passing report
# =============================================================================

@test "AC-verify: passes when every AC is walked, Met has evidence, deferred is logged" {
    cat > "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md" <<'EOF'
## AC Verification

**AC-1.1**: "API returns 401 on invalid creds"
- Status: `✓ Met`
- Evidence: `src/auth/middleware.ts:42` — returns 401 when token invalid

**AC-1.2**: "Passwords are hashed with bcrypt"
- Status: `⏸ [ACCEPTED-DEFERRED]`
- Notes: deferred, see NOTES.md
EOF
    run "$SCRIPT" --report "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md" --sprint "${TEST_TMPDIR}/sprint.md"
    [ "$status" -eq 0 ]
}

@test "AC-verify: extensionless evidence file (Makefile:12) is valid" {
    cat > "${TEST_TMPDIR}/sprint-single.md" <<'EOF'
### Acceptance Criteria
- [ ] Build target exists
EOF
    cat > "${TEST_TMPDIR}/report-makefile.md" <<'EOF'
## AC Verification

**AC-1.1**: "Build target exists"
- Status: `✓ Met`
- Evidence: `Makefile:12` — defines the build target
EOF
    run "$SCRIPT" --report "${TEST_TMPDIR}/report-makefile.md" --sprint "${TEST_TMPDIR}/sprint-single.md"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Violations
# =============================================================================

@test "AC-verify: fails when '## AC Verification' section is missing entirely" {
    cat > "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md" <<'EOF'
# Implementation Report

## Executive Summary
Done.
EOF
    run "$SCRIPT" --report "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md" --sprint "${TEST_TMPDIR}/sprint.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing the required '## AC Verification' section"* ]]
}

@test "AC-verify: fails when a sprint.md AC is not walked verbatim in the report" {
    cat > "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md" <<'EOF'
## AC Verification

**AC-1.1**: "API returns 401 on invalid creds"
- Status: `✓ Met`
- Evidence: `src/auth/middleware.ts:42`
EOF
    run "$SCRIPT" --report "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md" --sprint "${TEST_TMPDIR}/sprint.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Passwords are hashed with bcrypt"* ]]
}

@test "AC-verify: fails when a paraphrased (non-verbatim) AC is used" {
    cat > "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md" <<'EOF'
## AC Verification

**AC-1.1**: "Returns HTTP 401 on bad credentials"
- Status: `✓ Met`
- Evidence: `src/auth/middleware.ts:42`

**AC-1.2**: "Passwords are hashed with bcrypt"
- Status: `⏸ [ACCEPTED-DEFERRED]`
EOF
    run "$SCRIPT" --report "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md" --sprint "${TEST_TMPDIR}/sprint.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"API returns 401 on invalid creds"* ]]
}

@test "AC-verify: fails when a '✓ Met' row has no Evidence: line" {
    cat > "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md" <<'EOF'
## AC Verification

**AC-1.1**: "API returns 401 on invalid creds"
- Status: `✓ Met`

**AC-1.2**: "Passwords are hashed with bcrypt"
- Status: `⏸ [ACCEPTED-DEFERRED]`
EOF
    run "$SCRIPT" --report "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md" --sprint "${TEST_TMPDIR}/sprint.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"AC-1.1"* ]]
    [[ "$output" == *"Evidence"* ]]
}

@test "AC-verify: fails when a '✓ Met' row has evidence without a line number" {
    cat > "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md" <<'EOF'
## AC Verification

**AC-1.1**: "API returns 401 on invalid creds"
- Status: `✓ Met`
- Evidence: implemented in src/auth/

**AC-1.2**: "Passwords are hashed with bcrypt"
- Status: `⏸ [ACCEPTED-DEFERRED]`
EOF
    run "$SCRIPT" --report "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md" --sprint "${TEST_TMPDIR}/sprint.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"AC-1.1"* ]]
}

@test "AC-verify: fails when '[ACCEPTED-DEFERRED]' has no matching NOTES.md Decision Log entry" {
    cat > "${TEST_TMPDIR}/no-mention-notes.md" <<'EOF'
# Notes
## Decision Log
- unrelated entry about something else
EOF
    cat > "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md" <<'EOF'
## AC Verification

**AC-1.1**: "API returns 401 on invalid creds"
- Status: `✓ Met`
- Evidence: `src/auth/middleware.ts:42`

**AC-1.2**: "Passwords are hashed with bcrypt"
- Status: `⏸ [ACCEPTED-DEFERRED]`
EOF
    run "$SCRIPT" --report "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md" --sprint "${TEST_TMPDIR}/sprint.md" --notes "${TEST_TMPDIR}/no-mention-notes.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"AC-1.2"* ]]
    [[ "$output" == *"Decision Log"* ]]
}

@test "AC-verify: default --notes path resolves to grimoires/loa/NOTES.md relative to the report" {
    # No --notes passed; report lives at grimoires/loa/a2a/sprint-1/reviewer.md
    # so the default must resolve to grimoires/loa/NOTES.md (created in setup).
    cat > "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md" <<'EOF'
## AC Verification

**AC-1.1**: "API returns 401 on invalid creds"
- Status: `✓ Met`
- Evidence: `src/auth/middleware.ts:42`

**AC-1.2**: "Passwords are hashed with bcrypt"
- Status: `⏸ [ACCEPTED-DEFERRED]`
EOF
    run "$SCRIPT" --report "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md" --sprint "${TEST_TMPDIR}/sprint.md"
    [ "$status" -eq 0 ]
}

@test "AC-verify: --json reports ac_count and pass=false with a violations array" {
    skip_if_no_jq
    cat > "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md" <<'EOF'
## AC Verification

**AC-1.1**: "API returns 401 on invalid creds"
- Status: `✓ Met`
EOF
    run "$SCRIPT" --report "${TEST_TMPDIR}/grimoires/loa/a2a/sprint-1/reviewer.md" --sprint "${TEST_TMPDIR}/sprint.md" --json
    [ "$status" -eq 1 ]
    [ "$(echo "$output" | jq -r '.pass')" = "false" ]
    [ "$(echo "$output" | jq -r '.ac_count')" = "2" ]
    [ "$(echo "$output" | jq -r '.violations | length')" -gt 0 ]
}
