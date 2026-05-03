#!/usr/bin/env bats
# =============================================================================
# tests/integration/audit-envelope-python-concurrent.bats
#
# cycle-098 Sprint 1.5 hardening — issue #689 (L1 audit MED-1).
#
# Mirror of audit-envelope-concurrent-write.bats for the Python adapter.
# audit_envelope.py:300-302 appends without flock; bash adapter (post-Sprint-1
# F3 fix) does flock. Without parity, concurrent writers from bash + Python
# (Sprint 2's L2 ships the first Python writers) race on tail-read/append.
#
# This test forks 5 (then 10) concurrent Python writers and asserts all
# entries land in the chain with prev_hash continuity intact. Pre-fix:
# race conditions cause missing entries or broken chain. Post-fix:
# deterministic.
#
# Cross-adapter test (bash + Python interleaved) lives in audit-envelope-chain.bats.
# This file isolates the Python-only path.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    AUDIT_ENVELOPE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"
    PYTHON_ADAPTER_DIR="$PROJECT_ROOT/.claude/adapters"

    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"
    [[ -d "$PYTHON_ADAPTER_DIR/loa_cheval" ]] || skip "loa_cheval not present"
    command -v flock >/dev/null 2>&1 || skip "flock required for this test"
    python3 -c "import fcntl, jsonschema" 2>/dev/null || skip "python fcntl + jsonschema required"

    TEST_DIR="$(mktemp -d)"
    LOG="$TEST_DIR/python-concurrent.jsonl"

    # Permissive trust-store (F1 isolation: pre-cutoff entries, sign-optional).
    TEST_TRUST_STORE="$TEST_DIR/trust-store.yaml"
    cat > "$TEST_TRUST_STORE" <<'EOF'
schema_version: "1.0"
root_signature:
  algorithm: ed25519
  signer_pubkey: ""
  signed_at: ""
  signature: ""
keys: []
revocations: []
trust_cutoff:
  default_strict_after: "2099-01-01T00:00:00Z"
EOF
    export LOA_TRUST_STORE_FILE="$TEST_TRUST_STORE"
    export PYTHONPATH="$PYTHON_ADAPTER_DIR"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
    fi
    unset LOA_TRUST_STORE_FILE PYTHONPATH
}

# -----------------------------------------------------------------------------
# 5 concurrent Python writers: all entries land + chain valid
# -----------------------------------------------------------------------------
@test "py-concurrent: 5 forked Python writers all land + chain remains valid" {
    local N=5
    local i
    local pids=()
    for i in $(seq 1 $N); do
        python3 -c "
from loa_cheval.audit_envelope import audit_emit
audit_emit('L1', 'panel.bind', {'decision_id': 'd-$i'}, '$LOG')
" &
        pids+=($!)
    done
    # Bridgebuilder F-002: assert each child exited 0. Without this, a crashing
    # writer can leave a log that satisfies line-count + chain-verify checks
    # while masking the bug as a flaky green.
    local failures=0
    for pid in "${pids[@]}"; do
        wait "$pid" || failures=$((failures + 1))
    done
    [[ "$failures" -eq 0 ]] || {
        echo "$failures concurrent writer(s) exited non-zero"
        return 1
    }

    local lines
    lines=$(wc -l < "$LOG")
    [[ "$lines" -eq "$N" ]] || {
        echo "Expected $N lines, got $lines"
        cat "$LOG"
        return 1
    }

    # Chain must validate via Python adapter.
    run python3 -c "
import sys
from loa_cheval.audit_envelope import audit_verify_chain
ok, msg = audit_verify_chain('$LOG')
print(msg)
sys.exit(0 if ok else 1)
"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK $N entries"* ]]

    # And via bash adapter (cross-adapter validation).
    source "$AUDIT_ENVELOPE"
    run audit_verify_chain "$LOG"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK $N entries"* ]]
}

# -----------------------------------------------------------------------------
# 10 concurrent Python writers (stress): all entries land + chain valid
# -----------------------------------------------------------------------------
@test "py-concurrent: 10 forked Python writers all land + chain remains valid (stress)" {
    local N=10
    local i
    local pids=()
    for i in $(seq 1 $N); do
        python3 -c "
from loa_cheval.audit_envelope import audit_emit
audit_emit('L1', 'panel.bind', {'decision_id': 'd-$i'}, '$LOG')
" &
        pids+=($!)
    done
    # Bridgebuilder F-002: assert each child exited 0.
    local failures=0
    for pid in "${pids[@]}"; do
        wait "$pid" || failures=$((failures + 1))
    done
    [[ "$failures" -eq 0 ]] || {
        echo "$failures concurrent writer(s) exited non-zero"
        return 1
    }

    local lines
    lines=$(wc -l < "$LOG")
    [[ "$lines" -eq "$N" ]] || {
        echo "Expected $N lines, got $lines"
        cat "$LOG"
        return 1
    }

    run python3 -c "
import sys
from loa_cheval.audit_envelope import audit_verify_chain
ok, msg = audit_verify_chain('$LOG')
print(msg)
sys.exit(0 if ok else 1)
"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK $N entries"* ]]
}

# -----------------------------------------------------------------------------
# Lock-file pattern parity with bash adapter
# -----------------------------------------------------------------------------
@test "py-concurrent: Python adapter creates lock file at <log_path>.lock" {
    python3 -c "
from loa_cheval.audit_envelope import audit_emit
audit_emit('L1', 'panel.bind', {'decision_id': 'd-1'}, '$LOG')
"
    [[ -f "${LOG}.lock" ]]
}

# -----------------------------------------------------------------------------
# F10 (bridgebuilder): stress-mode race coverage. Default CI runs at N=10;
# stress mode at N=50 surfaces races that smaller pools miss (Kingsbury/Jepsen:
# race bugs typically appear only at N>50 with adversarial scheduling).
# Gated by LOA_STRESS_TESTS=1; skipped by default to keep CI fast.
# -----------------------------------------------------------------------------
@test "py-concurrent: 50 forked Python writers (stress, env-gated)" {
    [[ "${LOA_STRESS_TESTS:-0}" == "1" ]] || skip "stress mode (LOA_STRESS_TESTS=1 to enable)"
    local N=50
    local i
    local pids=()
    for i in $(seq 1 $N); do
        python3 -c "
from loa_cheval.audit_envelope import audit_emit
audit_emit('L1', 'panel.bind', {'decision_id': 'd-$i'}, '$LOG')
" &
        pids+=($!)
    done
    local failures=0
    for pid in "${pids[@]}"; do
        wait "$pid" || failures=$((failures + 1))
    done
    [[ "$failures" -eq 0 ]] || {
        echo "$failures concurrent writer(s) exited non-zero (stress N=$N)"
        return 1
    }

    local lines
    lines=$(wc -l < "$LOG")
    [[ "$lines" -eq "$N" ]] || {
        echo "Expected $N lines, got $lines (race lost entries)"
        return 1
    }

    run python3 -c "
import sys
from loa_cheval.audit_envelope import audit_verify_chain
ok, msg = audit_verify_chain('$LOG')
print(msg)
sys.exit(0 if ok else 1)
"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK $N entries"* ]]
}

# -----------------------------------------------------------------------------
# Cross-adapter concurrent (bash + Python) — defense against the dual-writer
# scenario Sprint 2's L2 ships. Bash audit_emit and Python audit_emit must
# share the same lock file.
# -----------------------------------------------------------------------------
@test "py-concurrent: 5 bash + 5 python interleaved writers (cross-adapter, 10 total)" {
    local pids=()
    # 5 bash writers
    for i in 1 2 3 4 5; do
        bash -c "
            source '$AUDIT_ENVELOPE'
            export LOA_TRUST_STORE_FILE='$LOA_TRUST_STORE_FILE'
            audit_emit L1 panel.bind '{\"decision_id\":\"bash-$i\"}' '$LOG' >/dev/null 2>&1
        " &
        pids+=($!)
    done
    # 5 python writers
    for i in 1 2 3 4 5; do
        python3 -c "
from loa_cheval.audit_envelope import audit_emit
audit_emit('L1', 'panel.bind', {'decision_id': 'py-$i'}, '$LOG')
" &
        pids+=($!)
    done
    # Bridgebuilder F-002: assert each child exited 0.
    local failures=0
    for pid in "${pids[@]}"; do
        wait "$pid" || failures=$((failures + 1))
    done
    [[ "$failures" -eq 0 ]] || {
        echo "$failures concurrent writer(s) exited non-zero"
        return 1
    }

    local lines
    lines=$(wc -l < "$LOG")
    [[ "$lines" -eq 10 ]] || {
        echo "Expected 10 lines, got $lines"
        cat "$LOG"
        return 1
    }

    # Chain valid via both adapters.
    source "$AUDIT_ENVELOPE"
    run audit_verify_chain "$LOG"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK 10 entries"* ]]
}
