#!/usr/bin/env bats
# =============================================================================
# tests/integration/structured-handoff-followup-776.bats
#
# cycle-098 follow-up #776 — pin the L6 strict test-mode gate.
# Mirrors the L7 sprint-7 CRIT-1 closure (tests/integration/
# soul-identity-7-remediation.bats:CRIT-1) for the L6 primitive.
#
# Pre-fix: `_handoff_test_mode_active` permitted bypass via `BATS_TMPDIR`
# alone (any developer-leaked env or nested tooling could flip production
# into test-mode). Same dead-code-clause regression as L4 cycle-099 #761
# and L7 sprint-7 CRIT-1.
#
# Post-fix: strict gate requires BOTH `LOA_HANDOFF_TEST_MODE=1` AND a
# robust bats marker (`BATS_TEST_FILENAME` or `BATS_VERSION`).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LIB="$PROJECT_ROOT/.claude/scripts/lib/structured-handoff-lib.sh"
    [[ -f "$LIB" ]] || skip "structured-handoff-lib.sh not present"
}

@test "CRIT-1 BATS_TMPDIR alone does NOT activate L6 test-mode (was a bypass pre-fix)" {
    bash -c '
        unset BATS_TEST_DIRNAME BATS_TEST_FILENAME BATS_VERSION LOA_HANDOFF_TEST_MODE
        export BATS_TMPDIR=/tmp
        # shellcheck source=/dev/null
        source "'"$LIB"'"
        if _handoff_test_mode_active; then
            echo "BYPASS: BATS_TMPDIR alone activated test-mode"; exit 1
        fi
        exit 0
    '
}

@test "CRIT-1 LOA_HANDOFF_TEST_MODE alone (no bats marker) does NOT activate L6 test-mode" {
    bash -c '
        unset BATS_TEST_DIRNAME BATS_TEST_FILENAME BATS_VERSION BATS_TMPDIR
        export LOA_HANDOFF_TEST_MODE=1
        # shellcheck source=/dev/null
        source "'"$LIB"'"
        if _handoff_test_mode_active; then
            echo "BYPASS: LOA_HANDOFF_TEST_MODE alone activated test-mode"; exit 1
        fi
        exit 0
    '
}

@test "CRIT-1 only BOTH LOA_HANDOFF_TEST_MODE=1 + BATS marker activates L6 test-mode" {
    bash -c '
        unset BATS_TEST_DIRNAME BATS_TMPDIR
        export LOA_HANDOFF_TEST_MODE=1 BATS_VERSION=1.10.0
        # shellcheck source=/dev/null
        source "'"$LIB"'"
        _handoff_test_mode_active || { echo "FAIL: legitimate test-mode rejected"; exit 1; }
        exit 0
    '
}

@test "CRIT-1 production-mode env override emits stderr WARN and is ignored" {
    bash -c '
        unset BATS_TEST_DIRNAME BATS_TEST_FILENAME BATS_VERSION BATS_TMPDIR LOA_HANDOFF_TEST_MODE
        # shellcheck source=/dev/null
        source "'"$LIB"'"
        # Lib has set -euo pipefail; disable -e so we can capture the
        # expected non-zero return from _handoff_check_env_override.
        set +e
        out="$(_handoff_check_env_override LOA_HANDOFF_LOG /tmp/poison.jsonl 2>&1)"
        rc=$?
        set -e
        if [[ "$rc" -ne 1 ]]; then
            echo "production override accepted (rc=$rc): $out"; exit 1
        fi
        if [[ "$out" != *"WARNING"* ]]; then
            echo "production override silently ignored (no WARN): $out"; exit 1
        fi
    '
}
