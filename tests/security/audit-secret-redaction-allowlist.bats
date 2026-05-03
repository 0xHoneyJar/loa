#!/usr/bin/env bats
# =============================================================================
# tests/security/audit-secret-redaction-allowlist.bats
#
# cycle-098 Sprint 1.5 hardening — issue #695 F8 (security tightening).
#
# Bridgebuilder iter-1 review of PR #693 surfaced that the audit-secret-redaction
# workflow allowlist was overly broad (`grimoires/loa/.*\.md$` etc.). Agents
# write into `progress/`, `handoffs/`, `a2a/` paths at scale during normal
# sprint work — those paths cannot be redaction blind spots. Secrets that leak
# through agent writes would slip past the workflow.
#
# This test exercises the redaction scanner against fixture paths to assert:
#   1. Assignment patterns in agent-writable paths (progress/, handoffs/, a2a/)
#      are FLAGGED (not allowlisted)
#   2. Assignment patterns in named system files (audit-envelope.sh, etc.) are
#      ALLOWED (these intentionally reference the deprecated env var)
#   3. Assignment patterns in named documentation (audit-keys-bootstrap.md,
#      sdd.md, sprint.md) are ALLOWED
#
# The single-source-of-truth allowlist + scan logic lives in
# `.claude/scripts/audit-secret-redaction-scan.sh` (extracted from the workflow
# so it can be unit-tested). The workflow calls this script.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    SCAN_SCRIPT="$PROJECT_ROOT/.claude/scripts/audit-secret-redaction-scan.sh"
    [[ -f "$SCAN_SCRIPT" ]] || skip "audit-secret-redaction-scan.sh not present (Sprint 1.5 #695 F8)"

    TEST_DIR="$(mktemp -d)"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
    fi
}

# Helper: write a fixture file at a repo-relative path and feed it to the scanner.
_write_fixture() {
    local rel_path="$1"
    local content="$2"
    local abs="$TEST_DIR/$rel_path"
    mkdir -p "$(dirname "$abs")"
    printf '%s' "$content" > "$abs"
}

# Helper: invoke the scanner with a list of repo-relative paths.
# Args: scanner --root <test-root> < file with paths
_run_scanner() {
    local stdin_paths="$1"
    cd "$TEST_DIR" && printf '%s' "$stdin_paths" | "$SCAN_SCRIPT"
}

# -----------------------------------------------------------------------------
# Allowlisted: named system files (intentionally reference deprecated env var)
# -----------------------------------------------------------------------------
@test "allowlist: .claude/scripts/audit-envelope.sh ALLOWED" {
    _write_fixture ".claude/scripts/audit-envelope.sh" 'LOA_AUDIT_KEY_PASSWORD=foo'
    run _run_scanner ".claude/scripts/audit-envelope.sh"
    [[ "$status" -eq 0 ]]
}

@test "allowlist: .claude/scripts/lib/audit-signing-helper.py ALLOWED" {
    _write_fixture ".claude/scripts/lib/audit-signing-helper.py" 'LOA_AUDIT_KEY_PASSWORD=foo'
    run _run_scanner ".claude/scripts/lib/audit-signing-helper.py"
    [[ "$status" -eq 0 ]]
}

@test "allowlist: .claude/adapters/loa_cheval/audit_envelope.py ALLOWED" {
    _write_fixture ".claude/adapters/loa_cheval/audit_envelope.py" 'LOA_AUDIT_KEY_PASSWORD=foo'
    run _run_scanner ".claude/adapters/loa_cheval/audit_envelope.py"
    [[ "$status" -eq 0 ]]
}

@test "allowlist: tests/security/no-env-var-leakage.bats ALLOWED" {
    _write_fixture "tests/security/no-env-var-leakage.bats" 'LOA_AUDIT_KEY_PASSWORD=foo'
    run _run_scanner "tests/security/no-env-var-leakage.bats"
    [[ "$status" -eq 0 ]]
}

@test "allowlist: .github/workflows/audit-secret-redaction.yml ALLOWED" {
    _write_fixture ".github/workflows/audit-secret-redaction.yml" 'LOA_AUDIT_KEY_PASSWORD=foo'
    run _run_scanner ".github/workflows/audit-secret-redaction.yml"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Allowlisted: named documentation files (deprecation rationale + ACs)
# -----------------------------------------------------------------------------
@test "allowlist: grimoires/loa/runbooks/audit-keys-bootstrap.md ALLOWED" {
    _write_fixture "grimoires/loa/runbooks/audit-keys-bootstrap.md" 'See LOA_AUDIT_KEY_PASSWORD=value example'
    run _run_scanner "grimoires/loa/runbooks/audit-keys-bootstrap.md"
    [[ "$status" -eq 0 ]]
}

@test "allowlist: grimoires/loa/sdd.md ALLOWED" {
    _write_fixture "grimoires/loa/sdd.md" 'LOA_AUDIT_KEY_PASSWORD= patterns documented'
    run _run_scanner "grimoires/loa/sdd.md"
    [[ "$status" -eq 0 ]]
}

@test "allowlist: grimoires/loa/sprint.md ALLOWED" {
    _write_fixture "grimoires/loa/sprint.md" 'LOA_AUDIT_KEY_PASSWORD= scan ACs'
    run _run_scanner "grimoires/loa/sprint.md"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# REJECTED: agent-writable paths (the F8 hardening)
# -----------------------------------------------------------------------------
@test "reject: grimoires/loa/a2a/sprint-1/progress-1B.md REJECTED" {
    _write_fixture "grimoires/loa/a2a/sprint-1/progress-1B.md" 'A reference to LOA_AUDIT_KEY_PASSWORD=secret'
    run _run_scanner "grimoires/loa/a2a/sprint-1/progress-1B.md"
    [[ "$status" -ne 0 ]]
    echo "$output" | grep -q 'progress-1B.md' || {
        echo "Expected progress-1B.md in violations, got: $output"
        return 1
    }
}

@test "reject: grimoires/loa/a2a/cycle-099/handoff/spam.md REJECTED" {
    _write_fixture "grimoires/loa/a2a/cycle-099/handoff/spam.md" 'LOA_AUDIT_KEY_PASSWORD=leak'
    run _run_scanner "grimoires/loa/a2a/cycle-099/handoff/spam.md"
    [[ "$status" -ne 0 ]]
}

@test "reject: grimoires/loa/cycles/cycle-099/progress.md REJECTED" {
    _write_fixture "grimoires/loa/cycles/cycle-099/progress.md" 'oops LOA_AUDIT_KEY_PASSWORD=leak'
    run _run_scanner "grimoires/loa/cycles/cycle-099/progress.md"
    [[ "$status" -ne 0 ]]
}

@test "reject: grimoires/loa/handoffs/random.md REJECTED" {
    _write_fixture "grimoires/loa/handoffs/random.md" 'LOA_AUDIT_KEY_PASSWORD=leak'
    run _run_scanner "grimoires/loa/handoffs/random.md"
    [[ "$status" -ne 0 ]]
}

# Random unrelated grimoires markdown — also rejected per F8 (broad glob removed).
@test "reject: grimoires/loa/some-random-doc.md REJECTED" {
    _write_fixture "grimoires/loa/some-random-doc.md" 'LOA_AUDIT_KEY_PASSWORD=leak'
    run _run_scanner "grimoires/loa/some-random-doc.md"
    [[ "$status" -ne 0 ]]
}

# -----------------------------------------------------------------------------
# Mixed batch: violations + allowed in same scan
# -----------------------------------------------------------------------------
@test "mixed: scanner reports only violations, not allowlisted matches" {
    _write_fixture ".claude/scripts/audit-envelope.sh" 'LOA_AUDIT_KEY_PASSWORD=ok'
    _write_fixture "grimoires/loa/a2a/sprint-1/progress-1B.md" 'LOA_AUDIT_KEY_PASSWORD=violation'

    run _run_scanner ".claude/scripts/audit-envelope.sh
grimoires/loa/a2a/sprint-1/progress-1B.md"
    [[ "$status" -ne 0 ]]
    echo "$output" | grep -q 'progress-1B.md'
    ! echo "$output" | grep -q 'audit-envelope.sh'
}

# -----------------------------------------------------------------------------
# Clean batch: no violations
# -----------------------------------------------------------------------------
@test "clean: no LOA_AUDIT_KEY_PASSWORD= in any file → exit 0" {
    _write_fixture "grimoires/loa/some-random-doc.md" 'No assignment here'
    _write_fixture "src/lib.rs" 'fn main() {}'

    run _run_scanner "grimoires/loa/some-random-doc.md
src/lib.rs"
    [[ "$status" -eq 0 ]]
}
