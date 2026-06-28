#!/usr/bin/env bats
# OKF/ICM cycle Sprint 9 (R2) — bash strict-mode parity (verify-for-merge) +
# the operator-opt-in fail-closed gate. Pins ATK-3/ATK-4 parity with the Python
# reference (test_audit_envelope_strict_verify.py) without changing install-time writes.

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT_REAL="$(cd "$SCRIPT_DIR/../.." && pwd)"
  AENV="$PROJECT_ROOT_REAL/.claude/scripts/audit-envelope.sh"
  GATE="$PROJECT_ROOT_REAL/.claude/scripts/audit-verify-for-merge.sh"
  [[ -f "$AENV" && -f "$GATE" ]] || skip "audit scripts not present"
  command -v jq >/dev/null || skip "jq required"

  TEST_DIR="$(mktemp -d)"
  # BOOTSTRAP-PENDING trust-store: empty signature + empty keys + empty revocations
  BOOT_TS="$TEST_DIR/trust-store-bootstrap.yaml"
  cat > "$BOOT_TS" <<'EOF'
root_signature:
  signature: ""
  signed_at: ""
  signer_pubkey: ""
keys: []
revocations: []
EOF
  # a minimal log to verify (strict fails at the trust-store check before walking)
  LOG="$TEST_DIR/model-invoke.jsonl"
  printf '{"prev_hash":"GENESIS","payload":{}}\n' > "$LOG"
}
teardown() { [[ -n "${TEST_DIR:-}" ]] && find "$TEST_DIR" -mindepth 0 -delete 2>/dev/null || true; }

@test "strict: --verify-for-merge fails closed on BOOTSTRAP-PENDING (ATK-3)" {
  run env LOA_TRUST_STORE_FILE="$BOOT_TS" bash "$AENV" verify-chain --verify-for-merge "$LOG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"[TRUST-STORE-BOOTSTRAP-PENDING]"* ]]
  [[ "$output" == *"ATK-3"* ]]
}

@test "strict: env LOA_AUDIT_STRICT_VERIFY=1 also fails closed on BOOTSTRAP-PENDING" {
  run env LOA_TRUST_STORE_FILE="$BOOT_TS" LOA_AUDIT_STRICT_VERIFY=1 bash "$AENV" verify-chain "$LOG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BOOTSTRAP-PENDING"* ]]
}

@test "non-strict: verify-chain still PERMITS BOOTSTRAP-PENDING (install-time behavior preserved)" {
  run env LOA_TRUST_STORE_FILE="$BOOT_TS" bash "$AENV" verify-chain "$LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "strict: a missing trust-store fails closed (resolves to BOOTSTRAP-PENDING → ATK-3)" {
  run env LOA_TRUST_STORE_FILE="$TEST_DIR/does-not-exist.yaml" bash "$AENV" verify-chain --verify-for-merge "$LOG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"[TRUST-STORE-"* ]]   # missing → BOOTSTRAP-PENDING/ATK-3; fail-closed either way
}

@test "gate: DISABLED by default (no LOA_AUDIT_VERIFY_FOR_MERGE) → exit 0, no verification" {
  run env -u LOA_AUDIT_VERIFY_FOR_MERGE bash "$GATE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DISABLED"* ]]
}

@test "gate: ENABLED + BOOTSTRAP-PENDING + a present log → fail-closed (exit 1)" {
  run env LOA_AUDIT_VERIFY_FOR_MERGE=1 LOA_TRUST_STORE_FILE="$BOOT_TS" \
      LOA_AUDIT_MERGE_LOGS="$LOG" PROJECT_ROOT="$TEST_DIR" bash "$GATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL-CLOSED"* ]]
}

@test "gate: default PROJECT_ROOT resolves to the repo root (a repo-relative log is FOUND, not skipped)" {
  # Regression: PROJECT_ROOT default was SCRIPT_DIR/.. (=.claude) — it must be the
  # repo root, else .run/model-invoke.jsonl is never found and the gate fail-OPENS.
  # Use a tracked repo-root-relative file: it is FOUND (gate tries to verify it →
  # FAIL-CLOSED on non-JSONL), NOT "skip (absent)".
  run env -u PROJECT_ROOT LOA_AUDIT_VERIFY_FOR_MERGE=1 LOA_TRUST_STORE_FILE="$BOOT_TS" \
      LOA_AUDIT_MERGE_LOGS="grimoires/loa/known-failures.md" bash "$GATE"
  [[ "$output" != *"skip (absent)"* ]]
  [[ "$output" == *"known-failures.md"* ]]
}

@test "gate: ENABLED but no target logs present → exit 0 (nothing to verify)" {
  run env LOA_AUDIT_VERIFY_FOR_MERGE=1 LOA_TRUST_STORE_FILE="$BOOT_TS" \
      LOA_AUDIT_MERGE_LOGS="$TEST_DIR/absent.jsonl" PROJECT_ROOT="$TEST_DIR" bash "$GATE"
  [ "$status" -eq 0 ]
}

# Build a VERIFIED (root-signed) trust-store with a writer in keys[] + the writer
# keypair on disk. Echoes the writer_id. Skips if crypto deps are unavailable.
_build_verified_store() {
  python3 - "$TEST_DIR" "$1" >/dev/null 2>&1 <<'PY'
import sys, base64, yaml
from pathlib import Path
try:
    import rfc8785
    from cryptography.hazmat.primitives.asymmetric import ed25519
    from cryptography.hazmat.primitives import serialization
except Exception:
    sys.exit(7)
td=Path(sys.argv[1]); kd=Path(sys.argv[2]); kd.mkdir(parents=True, exist_ok=True)
pub=lambda k:k.public_key().public_bytes(serialization.Encoding.PEM,serialization.PublicFormat.SubjectPublicKeyInfo).decode()
prv=lambda k:k.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()).decode()
root=ed25519.Ed25519PrivateKey.generate(); w=ed25519.Ed25519PrivateKey.generate(); wid="ci-bot"
(td/"root.pub").write_text(pub(root))
(kd/f"{wid}.priv").write_text(prv(w)); (kd/f"{wid}.priv").chmod(0o600); (kd/f"{wid}.pub").write_text(pub(w))
core={"schema_version":"1.0","keys":[{"writer_id":wid,"pubkey_pem":pub(w)}],"revocations":[],
      "trust_cutoff":{"default_strict_after":"2020-01-01T00:00:00Z"}}
ts={**core,"root_signature":{"algorithm":"ed25519","signer_pubkey":pub(root),
    "signed_at":"2026-06-28T00:00:00Z","signature":base64.b64encode(root.sign(rfc8785.dumps(core))).decode()}}
(td/"trust-store.yaml").write_text(yaml.safe_dump(ts))
PY
}

@test "parity-positive (e2e): VERIFIED store + writer in keys[] + signed entry PASSES strict verify-for-merge" {
  local kd="$TEST_DIR/vkeys"
  _build_verified_store "$kd" || skip "cryptography/rfc8785 unavailable"
  local elog="$TEST_DIR/signed.jsonl"
  env LOA_TRUST_STORE_FILE="$TEST_DIR/trust-store.yaml" LOA_PINNED_ROOT_PUBKEY_PATH="$TEST_DIR/root.pub" \
      LOA_AUDIT_KEY_DIR="$kd" LOA_AUDIT_SIGNING_KEY_ID="ci-bot" \
      bash "$AENV" emit-signed "L1" "t.ev" '{"signed":true}' "$elog"
  run env LOA_TRUST_STORE_FILE="$TEST_DIR/trust-store.yaml" LOA_PINNED_ROOT_PUBKEY_PATH="$TEST_DIR/root.pub" \
      LOA_AUDIT_KEY_DIR="$kd" bash "$AENV" verify-chain --verify-for-merge "$elog"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "parity-positive (e2e): a tampered signed entry FAILS strict verify-for-merge" {
  local kd="$TEST_DIR/vkeys2"
  _build_verified_store "$kd" || skip "cryptography/rfc8785 unavailable"
  local elog="$TEST_DIR/signed2.jsonl"
  env LOA_TRUST_STORE_FILE="$TEST_DIR/trust-store.yaml" LOA_PINNED_ROOT_PUBKEY_PATH="$TEST_DIR/root.pub" \
      LOA_AUDIT_KEY_DIR="$kd" LOA_AUDIT_SIGNING_KEY_ID="ci-bot" \
      bash "$AENV" emit-signed "L1" "t.ev" '{"signed":true}' "$elog"
  sed -i 's/"signed":true/"signed":false/' "$elog"
  run env LOA_TRUST_STORE_FILE="$TEST_DIR/trust-store.yaml" LOA_PINNED_ROOT_PUBKEY_PATH="$TEST_DIR/root.pub" \
      LOA_AUDIT_KEY_DIR="$kd" bash "$AENV" verify-chain --verify-for-merge "$elog"
  [ "$status" -ne 0 ]
}

@test "footgun-fix: exported LOA_AUDIT_STRICT_VERIFY=1 does NOT block the audit_emit write path" {
  # Mirrors Python: only the verify path consults the env; emit ignores it.
  run env LOA_TRUST_STORE_FILE="$BOOT_TS" LOA_AUDIT_STRICT_VERIFY=1 \
      bash "$AENV" emit "L1" "t.ev" '{"k":1}' "$TEST_DIR/emit.jsonl"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$TEST_DIR/emit.jsonl")" -eq 1 ]
}

@test "parity: _audit_pubkey_for_key_id refuses producer-writable local .pub under strict (ATK-3)" {
  local kd="$TEST_DIR/keys"; mkdir -p "$kd"
  printf -- '-----BEGIN PUBLIC KEY-----\nFAKE\n-----END PUBLIC KEY-----\n' > "$kd/wkid.pub"
  run env LOA_AUDIT_KEY_DIR="$kd" LOA_TRUST_STORE_FILE="$BOOT_TS" bash -c '
    source "'"$AENV"'" >/dev/null 2>&1 || true
    _audit_pubkey_for_key_id wkid 0 >/dev/null 2>&1 && echo NONSTRICT_OK
    _audit_pubkey_for_key_id wkid 1 >/dev/null 2>&1 && echo STRICT_RESOLVED || echo STRICT_REFUSED
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"NONSTRICT_OK"* ]]
  [[ "$output" == *"STRICT_REFUSED"* ]]
}
