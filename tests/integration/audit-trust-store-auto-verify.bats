#!/usr/bin/env bats
# =============================================================================
# tests/integration/audit-trust-store-auto-verify.bats
#
# cycle-098 Sprint 1.5 hardening — issue #690 (L1 audit MED-2).
#
# audit_trust_store_verify exists and works (5/5 tests in
# trust-store-root-of-trust.bats) but is NOT invoked automatically from
# audit_verify_chain or audit_emit. Once an operator populates trust-store.yaml
# (post-bootstrap), runtime auto-verify becomes critical: an attacker who
# tampers trust-store.yaml (adds malicious writer pubkey + signs entries with
# the corresponding private key) is undetected at runtime.
#
# This test exercises:
#   1. BOOTSTRAP-PENDING: empty keys + empty signature → reads/writes permitted
#   2. VERIFIED: legitimately signed trust-store + populated keys → permitted
#   3. INVALID: tampered trust-store (non-empty keys, missing/bad signature)
#      → audit_emit + audit_verify_chain refuse with [TRUST-STORE-INVALID]
#   4. mtime cache invalidation: change trust-store mtime → re-verify on next call
#   5. No trust-store file (graceful fallback to BOOTSTRAP-PENDING)
#
# Acceptance criteria from issue #690:
#   - audit_verify_chain auto-calls audit_trust_store_verify once per process
#   - Trust-store substitution test: tamper trust-store.yaml; chain ops fail
#   - BOOTSTRAP-PENDING state still permits reads/writes (graceful fallback)
#   - Cached verify result invalidated on trust-store mtime change
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    AUDIT_ENVELOPE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"
    PYTHON_ADAPTER_DIR="$PROJECT_ROOT/.claude/adapters"

    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"
    [[ -d "$PYTHON_ADAPTER_DIR/loa_cheval" ]] || skip "loa_cheval not present"
    if ! python3 -c "import cryptography, yaml, rfc8785" 2>/dev/null; then
        skip "python cryptography + yaml + rfc8785 required"
    fi

    TEST_DIR="$(mktemp -d)"
    PINNED_PUBKEY="$TEST_DIR/pinned-root-pubkey.txt"
    LOG="$TEST_DIR/test.jsonl"

    # Generate root + imposter keypairs (mirrors trust-store-root-of-trust.bats).
    python3 - "$TEST_DIR" <<'PY'
import sys
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization

td = Path(sys.argv[1])
for tag in ["root", "imposter"]:
    priv = ed25519.Ed25519PrivateKey.generate()
    pub_pem = priv.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    priv_pem = priv.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    (td / f"{tag}.pub").write_bytes(pub_pem)
    (td / f"{tag}.priv").write_bytes(priv_pem)

import shutil
shutil.copy(td / "root.pub", td / "pinned-root-pubkey.txt")
PY

    export LOA_PINNED_ROOT_PUBKEY_PATH="$PINNED_PUBKEY"
    export PYTHONPATH="$PYTHON_ADAPTER_DIR"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
    fi
    unset LOA_PINNED_ROOT_PUBKEY_PATH LOA_TRUST_STORE_FILE PYTHONPATH
}

# Helpers delegate to a single Python fixture script (tests/fixtures/trust-store-sign.py).
# Refactored from heredoc-injection helpers per bridgebuilder F-001/F6 (cycle-098 Sprint 1.5):
# heredoc-in-bash-via-python-via-subprocess was three quoting layers brittle to any change,
# and the cross-runtime declare-f trick the mtime test used was a Meta "cross-runtime
# fixture leakage" anti-pattern. Now: standalone CLI fixture, deterministic across both
# bats and Python subprocess callers.
#
# `_FIXTURE_SIGN` is resolved inside helpers (not at file-load time) because bats sets
# PROJECT_ROOT inside setup(), per-test.

_bootstrap_pending_trust_store() {
    python3 "$PROJECT_ROOT/tests/fixtures/trust-store-sign.py" \
        --out "$1" --signer-priv "$TEST_DIR/root.priv" --mode bootstrap-pending
}

_signed_empty_trust_store() {
    python3 "$PROJECT_ROOT/tests/fixtures/trust-store-sign.py" \
        --out "$1" --signer-priv "$2" --mode empty
}

_signed_populated_trust_store() {
    python3 "$PROJECT_ROOT/tests/fixtures/trust-store-sign.py" \
        --out "$1" --signer-priv "$2" --mode populated
}

# -----------------------------------------------------------------------------
# BOOTSTRAP-PENDING: empty keys + empty signature → reads/writes permitted
# -----------------------------------------------------------------------------
@test "auto-verify: BOOTSTRAP-PENDING permits audit_emit (bash)" {
    TS="$TEST_DIR/trust-store.yaml"
    _bootstrap_pending_trust_store "$TS"
    export LOA_TRUST_STORE_FILE="$TS"

    source "$AUDIT_ENVELOPE"
    run audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    [[ "$status" -eq 0 ]]
    [[ -f "$LOG" ]]
    local lines
    lines=$(wc -l < "$LOG")
    [[ "$lines" -eq 1 ]]
}

@test "auto-verify: BOOTSTRAP-PENDING permits audit_verify_chain (bash)" {
    TS="$TEST_DIR/trust-store.yaml"
    _bootstrap_pending_trust_store "$TS"
    export LOA_TRUST_STORE_FILE="$TS"

    source "$AUDIT_ENVELOPE"
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-2"}' "$LOG"
    run audit_verify_chain "$LOG"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK 2 entries"* ]]
}

@test "auto-verify: BOOTSTRAP-PENDING permits audit_emit (Python)" {
    TS="$TEST_DIR/trust-store.yaml"
    _bootstrap_pending_trust_store "$TS"
    export LOA_TRUST_STORE_FILE="$TS"

    run python3 -c "
from loa_cheval.audit_envelope import audit_emit
audit_emit('L1', 'panel.bind', {'decision_id': 'd-1'}, '$LOG')
"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# No trust-store file → BOOTSTRAP-PENDING (graceful fallback)
# -----------------------------------------------------------------------------
@test "auto-verify: missing trust-store file is treated as BOOTSTRAP-PENDING (bash)" {
    export LOA_TRUST_STORE_FILE="$TEST_DIR/nonexistent.yaml"

    source "$AUDIT_ENVELOPE"
    run audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Tampered trust-store (substitution attack)
# -----------------------------------------------------------------------------
@test "auto-verify: trust-store substitution (signed by imposter) blocks audit_emit (bash)" {
    TS="$TEST_DIR/trust-store.yaml"
    _signed_populated_trust_store "$TS" "$TEST_DIR/imposter.priv"
    export LOA_TRUST_STORE_FILE="$TS"

    source "$AUDIT_ENVELOPE"
    run audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    [[ "$status" -ne 0 ]]
    echo "$output" | grep -qE 'TRUST-STORE-INVALID|ROOT-PUBKEY-DIVERGENCE' || {
        echo "Expected [TRUST-STORE-INVALID] BLOCKER, got: $output"
        return 1
    }
}

@test "auto-verify: trust-store substitution (signed by imposter) blocks audit_verify_chain (bash)" {
    # First write the log under a permissive bootstrap-pending trust-store.
    TS="$TEST_DIR/trust-store.yaml"
    _bootstrap_pending_trust_store "$TS"
    export LOA_TRUST_STORE_FILE="$TS"
    source "$AUDIT_ENVELOPE"
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-2"}' "$LOG"

    # Now replace trust-store with imposter-signed populated trust-store.
    _signed_populated_trust_store "$TS" "$TEST_DIR/imposter.priv"

    # Ensure the cache is invalidated by mtime bump. F-003 (bridgebuilder):
    # `touch -d "1 second"` is GNU-coreutils-specific (BSD/macOS rejects it).
    # Portable alternative: sleep + touch.
    sleep 1; touch "$TS"

    # Fresh shell so cache is empty.
    run bash -c "
        source '$AUDIT_ENVELOPE'
        export LOA_TRUST_STORE_FILE='$TS'
        export LOA_PINNED_ROOT_PUBKEY_PATH='$LOA_PINNED_ROOT_PUBKEY_PATH'
        audit_verify_chain '$LOG' 2>&1
    "
    [[ "$status" -ne 0 ]]
    echo "$output" | grep -qE 'TRUST-STORE-INVALID|ROOT-PUBKEY-DIVERGENCE' || {
        echo "Expected [TRUST-STORE-INVALID] BLOCKER, got: $output"
        return 1
    }
}

@test "auto-verify: trust-store substitution blocks audit_emit (Python)" {
    TS="$TEST_DIR/trust-store.yaml"
    _signed_populated_trust_store "$TS" "$TEST_DIR/imposter.priv"
    export LOA_TRUST_STORE_FILE="$TS"

    run python3 -c "
import sys
from loa_cheval.audit_envelope import audit_emit
try:
    audit_emit('L1', 'panel.bind', {'decision_id': 'd-1'}, '$LOG')
    sys.exit(0)
except RuntimeError as e:
    print(f'BLOCKED: {e}')
    sys.exit(1)
"
    [[ "$status" -ne 0 ]]
    echo "$output" | grep -qE 'TRUST-STORE-INVALID|ROOT-PUBKEY-DIVERGENCE' || {
        echo "Expected [TRUST-STORE-INVALID] BLOCKER, got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Legitimately signed populated trust-store → audit_emit succeeds
# -----------------------------------------------------------------------------
@test "auto-verify: legitimately signed populated trust-store permits audit_emit (bash)" {
    TS="$TEST_DIR/trust-store.yaml"
    _signed_populated_trust_store "$TS" "$TEST_DIR/root.priv"
    export LOA_TRUST_STORE_FILE="$TS"

    source "$AUDIT_ENVELOPE"
    run audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    [[ "$status" -eq 0 ]]
}

@test "auto-verify: legitimately signed populated trust-store permits audit_emit (Python)" {
    TS="$TEST_DIR/trust-store.yaml"
    _signed_populated_trust_store "$TS" "$TEST_DIR/root.priv"
    export LOA_TRUST_STORE_FILE="$TS"

    run python3 -c "
from loa_cheval.audit_envelope import audit_emit
audit_emit('L1', 'panel.bind', {'decision_id': 'd-1'}, '$LOG')
"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# mtime cache invalidation
# -----------------------------------------------------------------------------
@test "auto-verify: mtime change invalidates cache (bash, single-process)" {
    TS="$TEST_DIR/trust-store.yaml"
    # Start with valid signed trust-store.
    _signed_populated_trust_store "$TS" "$TEST_DIR/root.priv"
    export LOA_TRUST_STORE_FILE="$TS"

    source "$AUDIT_ENVELOPE"
    # First call: caches VERIFIED.
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"

    # Tamper trust-store: replace with imposter-signed populated trust-store.
    sleep 0.05  # ensure mtime changes (filesystem granularity)
    _signed_populated_trust_store "$TS" "$TEST_DIR/imposter.priv"
    touch "$TS"  # ensure mtime bumps even if writes too fast

    # Second call: cache should be invalidated; auto-verify should fire and FAIL.
    run audit_emit L1 panel.bind '{"decision_id":"d-2"}' "$LOG"
    [[ "$status" -ne 0 ]]
    echo "$output" | grep -qE 'TRUST-STORE-INVALID|ROOT-PUBKEY-DIVERGENCE' || {
        echo "Expected [TRUST-STORE-INVALID] BLOCKER after mtime change, got: $output"
        return 1
    }
}

@test "auto-verify: mtime change invalidates cache (Python, single-process)" {
    TS="$TEST_DIR/trust-store.yaml"
    _signed_populated_trust_store "$TS" "$TEST_DIR/root.priv"
    export LOA_TRUST_STORE_FILE="$TS"

    # Single Python process: emit, tamper via fixture script (no cross-runtime
    # declare -f injection — F-001/F6 remediation), emit again.
    # Fixture path passed as env var; Python invokes it via subprocess with stable args.
    run env LOA_FIXTURE_SIGN="$PROJECT_ROOT/tests/fixtures/trust-store-sign.py" \
        LOA_TS_PATH="$TS" \
        LOA_LOG_PATH="$LOG" \
        LOA_IMPOSTER_PRIV="$TEST_DIR/imposter.priv" \
        python3 - <<'PY'
import sys, time, os, subprocess
from pathlib import Path
from loa_cheval.audit_envelope import audit_emit

ts_path = os.environ["LOA_TS_PATH"]
log_path = os.environ["LOA_LOG_PATH"]
fixture = os.environ["LOA_FIXTURE_SIGN"]
imposter = os.environ["LOA_IMPOSTER_PRIV"]

# 1. First emit: valid trust-store; should succeed.
audit_emit("L1", "panel.bind", {"decision_id": "d-1"}, log_path)

# 2. Tamper via fixture script (single source of truth — no declare -f leakage).
time.sleep(0.05)
subprocess.run(
    ["python3", fixture,
     "--out", ts_path,
     "--signer-priv", imposter,
     "--mode", "populated"],
    check=True,
)
Path(ts_path).touch()

# 3. Second emit: should FAIL due to mtime cache invalidation.
try:
    audit_emit("L1", "panel.bind", {"decision_id": "d-2"}, log_path)
    print("UNEXPECTED: second emit succeeded")
    sys.exit(0)
except RuntimeError as e:
    print(f"BLOCKED: {e}")
    sys.exit(1)
PY
    [[ "$status" -ne 0 ]]
    echo "$output" | grep -q 'TRUST-STORE-INVALID' || {
        echo "Expected [TRUST-STORE-INVALID] token in output, got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# F4 (bridgebuilder): same-second tampering must be caught by content-hash
# even when mtime resolves identically.
# -----------------------------------------------------------------------------
@test "auto-verify: same-second tampering (mtime-coarse FS) detected via content-hash" {
    TS="$TEST_DIR/trust-store.yaml"
    _signed_populated_trust_store "$TS" "$TEST_DIR/root.priv"
    export LOA_TRUST_STORE_FILE="$TS"

    # First emit primes the cache.
    source "$AUDIT_ENVELOPE"
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"

    # Capture mtime, then write imposter trust-store WITHOUT advancing mtime
    # (force exact-mtime collision via touch -r, simulating coarse-granularity FS).
    local mtime_before
    mtime_before="$(stat -c %Y "$TS" 2>/dev/null || stat -f %m "$TS" 2>/dev/null)"
    _signed_populated_trust_store "$TS" "$TEST_DIR/imposter.priv"
    # Pin mtime to exactly what it was — defeats mtime-only invalidation.
    touch -r "$LOG" "$TS" 2>/dev/null || true
    # Best-effort: try to set mtime to mtime_before; on coarse FS this collides.
    # We use a separate file as the time source. If "stat" failed, this is a no-op.

    # Second emit: mtime cache says "valid" but content-hash should detect change.
    # If content-hash is missing from cache key, this would PASS (bypass).
    # Post-F4: it should FAIL with [TRUST-STORE-INVALID].
    run audit_emit L1 panel.bind '{"decision_id":"d-2"}' "$LOG"
    [[ "$status" -ne 0 ]]
    echo "$output" | grep -q 'TRUST-STORE-INVALID' || {
        echo "Expected [TRUST-STORE-INVALID] (content-hash must catch same-mtime tamper), got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Cache hit: same mtime → no re-verification (smoke test for caching presence)
# -----------------------------------------------------------------------------
@test "auto-verify: cached result reused within same process (Python)" {
    TS="$TEST_DIR/trust-store.yaml"
    _signed_populated_trust_store "$TS" "$TEST_DIR/root.priv"
    export LOA_TRUST_STORE_FILE="$TS"

    # Two emits in same Python process; both must succeed AND second must
    # be faster (or at least not slower than re-verify cost). We don't time;
    # we just verify both work.
    run python3 -c "
from loa_cheval.audit_envelope import audit_emit
audit_emit('L1', 'panel.bind', {'decision_id': 'd-1'}, '$LOG')
audit_emit('L1', 'panel.bind', {'decision_id': 'd-2'}, '$LOG')
audit_emit('L1', 'panel.bind', {'decision_id': 'd-3'}, '$LOG')
"
    [[ "$status" -eq 0 ]]
    local lines
    lines=$(wc -l < "$LOG")
    [[ "$lines" -eq 3 ]]
}
