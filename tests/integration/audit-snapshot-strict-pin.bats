#!/usr/bin/env bats
# =============================================================================
# tests/integration/audit-snapshot-strict-pin.bats
#
# cycle-098 Sprint H2 — closes #708 F-007 (audit-snapshot strict-pin).
# When a signing key is configured (LOA_AUDIT_SIGNING_KEY_ID set), the
# snapshot script MUST force LOA_AUDIT_VERIFY_SIGS=1 regardless of the
# operator's env. Pre-existing operator env from a legacy migration window
# could otherwise leave VERIFY_SIGS=0, which would let snapshot operations
# accept and archive an unsigned/stripped log — corrupting the forensic
# trail.
#
# Coverage:
#   - With signing-key configured + parent VERIFY_SIGS=0: script forces 1
#   - With NO signing-key configured: script leaves VERIFY_SIGS as-set
#     (BOOTSTRAP-PENDING path; nothing to verify strictly anyway)
# =============================================================================

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SNAPSHOT_SCRIPT="${REPO_ROOT}/.claude/scripts/audit/audit-snapshot.sh"
    [[ -x "$SNAPSHOT_SCRIPT" ]] || skip "audit-snapshot.sh not present/executable"

    TEST_DIR="$(mktemp -d)"
    LOGS_DIR="${TEST_DIR}/logs"
    ARCHIVE_DIR="${TEST_DIR}/archive"
    POLICY="${TEST_DIR}/retention-policy.yaml"
    mkdir -p "$LOGS_DIR" "$ARCHIVE_DIR"
    cat > "$POLICY" <<'YAML'
schema_version: "1.0"
primitives:
  L1:
    log_basename: "panel-decisions.jsonl"
    chain_critical: true
    git_tracked: false
YAML
}

teardown() {
    rm -rf "$TEST_DIR"
    unset LOA_AUDIT_SIGNING_KEY_ID LOA_AUDIT_VERIFY_SIGS LOA_AUDIT_DEBUG_PIN
}

# Helper: run the snapshot script in --dry-run mode with a probe. The probe
# is a tiny perl/bash wrapper that captures the value of LOA_AUDIT_VERIFY_SIGS
# AS THE SCRIPT SEES IT after sourcing audit-envelope.sh — meaning post-pin.
# We use `bash -c "source <script> --dry-run; echo VERIFY_SIGS=$LOA_AUDIT_VERIFY_SIGS"`
# but the script `set -euo pipefail` + arg parsing makes this fragile.
# Simpler probe: extract the post-pin value via a single-line bash invocation
# that sources the snapshot script's prelude (just the env-pin block).

@test "F-007: snapshot script's pin block uses conditional gate (not unconditional)" {
    # Critical: the pin must be CONDITIONAL on signing-key presence so
    # BOOTSTRAP-PENDING / test environments aren't broken. An unconditional
    # `export LOA_AUDIT_VERIFY_SIGS=1` would break audit-snapshot.bats
    # (which seeds unsigned envelopes) and any other unsigned-mode workflow.
    grep -B1 'export LOA_AUDIT_VERIFY_SIGS=1' "$SNAPSHOT_SCRIPT" | grep -q 'LOA_AUDIT_SIGNING_KEY_ID'
}

@test "F-007: snapshot script emits the strict-pin block BEFORE sourcing audit-envelope.sh" {
    # The pin must run before audit-envelope.sh is sourced so the trust-store
    # auto-verify cache picks up the correct policy on first call.
    local pin_line source_line
    pin_line="$(grep -n 'export LOA_AUDIT_VERIFY_SIGS=1' "$SNAPSHOT_SCRIPT" | head -1 | cut -d: -f1)"
    source_line="$(grep -n 'source.*audit-envelope.sh' "$SNAPSHOT_SCRIPT" | head -1 | cut -d: -f1)"
    [ -n "$pin_line" ]
    [ -n "$source_line" ]
    [ "$pin_line" -lt "$source_line" ]
}

@test "F-007: actual snapshot script invocation observes pinned VERIFY_SIGS at runtime" {
    # Sprint H2 review iter-1 HIGH: prior tests probed the pin BLOCK in
    # isolation via `bash -c`, not the integrated script. If someone moved
    # the pin into a never-called function, tests would still pass. This
    # test runs the real script with a probe-injected hook that captures
    # the post-source value of $LOA_AUDIT_VERIFY_SIGS as the script sees it.
    #
    # Mechanism: run the script with `--dry-run --primitive L1` against an
    # empty logs dir. The script will exit 0 with no work; we don't care
    # about the exit, we care that during execution `$LOA_AUDIT_VERIFY_SIGS`
    # was actually pinned. We probe by invoking via `bash -x` and grepping
    # the trace for the export.
    export LOA_AUDIT_VERIFY_SIGS=0
    export LOA_AUDIT_SIGNING_KEY_ID="probe-key"
    local trace
    trace="$(bash -x "$SNAPSHOT_SCRIPT" --dry-run --primitive L1 \
        --policy "$POLICY" --archive-dir "$ARCHIVE_DIR" --logs-dir "$LOGS_DIR" 2>&1 | head -100)"
    # The actual script execution must have run `export LOA_AUDIT_VERIFY_SIGS=1`.
    [[ "$trace" == *"export LOA_AUDIT_VERIFY_SIGS=1"* ]]
}

# NOTE: Sprint H2 review iter-2 MEDIUM removed two prior tests
# ("parent VERIFY_SIGS=0 + signing-key-set" and "VERIFY_SIGS pin survives
# child process inheritance"). Both were bash-replicas duplicating the
# pin's conditional logic in a subshell, NOT exercising the actual
# snapshot script. The remaining tests probe the REAL script via grep
# (test 1, "uses conditional gate"), file ordering (test 2, "BEFORE
# sourcing audit-envelope.sh"), and runtime trace (test 3, "actual
# snapshot script invocation"). Replicas would catch a divergence in
# my-understanding-vs-actual-implementation but not regressions in the
# script itself.
