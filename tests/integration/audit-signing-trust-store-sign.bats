#!/usr/bin/env bats
# trust-store-sign subcommand (maintainer ceremony Step 4 tooling) — OKF cycle follow-up.
# Round-trips against trust-store-verify; refuses to sign with a divergent root key.

setup() {
  BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
  H="$PROJECT_ROOT/.claude/scripts/lib/audit-signing-helper.py"
  command -v python3 >/dev/null || skip "python3 required"
  python3 -c "import cryptography, rfc8785, yaml" 2>/dev/null || skip "crypto/rfc8785/yaml unavailable"
  TD="$(mktemp -d)"
  python3 - "$TD" <<'PY'
import sys, yaml
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization
td=Path(sys.argv[1])
pub=lambda k:k.public_key().public_bytes(serialization.Encoding.PEM,serialization.PublicFormat.SubjectPublicKeyInfo).decode()
prv=lambda k:k.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()).decode()
root=ed25519.Ed25519PrivateKey.generate(); wrong=ed25519.Ed25519PrivateKey.generate()
(td/"root.priv").write_text(prv(root)); (td/"root.priv").chmod(0o600); (td/"root.pub").write_text(pub(root))
(td/"wrong.priv").write_text(prv(wrong)); (td/"wrong.priv").chmod(0o600)
ts={"schema_version":"1.0","keys":[{"writer_id":"ci-bot","pubkey_pem":pub(ed25519.Ed25519PrivateKey.generate())}],
    "revocations":[],"trust_cutoff":{"default_strict_after":"2026-05-03T00:00:00Z"},
    "root_signature":{"algorithm":"ed25519","signer_pubkey":"","signed_at":"","signature":""}}
(td/"trust-store.yaml").write_text(yaml.safe_dump(ts))
# a variant missing schema_version
import copy; ts2=copy.deepcopy(ts); del ts2["schema_version"]
(td/"no-schema.yaml").write_text(yaml.safe_dump(ts2))
PY
}
teardown() { [[ -n "${TD:-}" ]] && find "$TD" -mindepth 0 -delete 2>/dev/null || true; }

@test "trust-store-sign: signs in place and the result verifies against the pinned root pubkey" {
  run python3 "$H" trust-store-sign --root-priv "$TD/root.priv" --trust-store "$TD/trust-store.yaml" \
      --signer-pubkey-from "$TD/root.pub" --signed-at "2026-06-28T00:00:00Z" --output-mode in-place
  [ "$status" -eq 0 ]
  run python3 "$H" trust-store-verify --pinned-pubkey "$TD/root.pub" --trust-store "$TD/trust-store.yaml"
  [ "$status" -eq 0 ]
}

@test "trust-store-sign: REFUSES a root key that diverges from the pinned pubkey" {
  run python3 "$H" trust-store-sign --root-priv "$TD/wrong.priv" --trust-store "$TD/trust-store.yaml" \
      --signer-pubkey-from "$TD/root.pub" --signed-at "2026-06-28T00:00:00Z" --output-mode stdout
  [ "$status" -ne 0 ]
  [[ "$output" == *"ROOT-PUBKEY-DIVERGENCE"* ]]
}

@test "trust-store-sign: stdout mode does not mutate the trust-store" {
  local before; before="$(sha256sum "$TD/trust-store.yaml" | cut -d' ' -f1)"
  run python3 "$H" trust-store-sign --root-priv "$TD/root.priv" --trust-store "$TD/trust-store.yaml" \
      --signer-pubkey-from "$TD/root.pub" --signed-at "2026-06-28T00:00:00Z" --output-mode stdout
  [ "$status" -eq 0 ]
  [[ "$output" == *"root_signature"* ]]
  [ "$(sha256sum "$TD/trust-store.yaml" | cut -d' ' -f1)" = "$before" ]
}

@test "trust-store-sign: a tampered keys[] after signing breaks verification (signed payload covers keys)" {
  python3 "$H" trust-store-sign --root-priv "$TD/root.priv" --trust-store "$TD/trust-store.yaml" \
      --signer-pubkey-from "$TD/root.pub" --signed-at "2026-06-28T00:00:00Z" --output-mode in-place
  # inject a rogue writer key AFTER signing
  python3 - "$TD/trust-store.yaml" <<'PY'
import sys, yaml
p=sys.argv[1]; d=yaml.safe_load(open(p))
d["keys"].append({"writer_id":"rogue","pubkey_pem":"-----BEGIN PUBLIC KEY-----\nX\n-----END PUBLIC KEY-----"})
open(p,"w").write(yaml.safe_dump(d))
PY
  run python3 "$H" trust-store-verify --pinned-pubkey "$TD/root.pub" --trust-store "$TD/trust-store.yaml"
  [ "$status" -ne 0 ]
}

@test "trust-store-sign: refuses to sign a trust-store missing schema_version" {
  run python3 "$H" trust-store-sign --root-priv "$TD/root.priv" --trust-store "$TD/no-schema.yaml" \
      --signer-pubkey-from "$TD/root.pub" --signed-at "2026-06-28T00:00:00Z" --output-mode stdout
  [ "$status" -ne 0 ]
  [[ "$output" == *"schema_version"* ]]
}

@test "trust-store-sign: re-signing an already-signed store is idempotent (old sig excluded from payload)" {
  python3 "$H" trust-store-sign --root-priv "$TD/root.priv" --trust-store "$TD/trust-store.yaml" \
      --signer-pubkey-from "$TD/root.pub" --signed-at "2026-06-28T00:00:00Z" --output-mode in-place
  run python3 "$H" trust-store-verify --pinned-pubkey "$TD/root.pub" --trust-store "$TD/trust-store.yaml"; [ "$status" -eq 0 ]
  # re-sign the already-signed store → still verifies (root_signature is not part of the signed core)
  run python3 "$H" trust-store-sign --root-priv "$TD/root.priv" --trust-store "$TD/trust-store.yaml" \
      --signer-pubkey-from "$TD/root.pub" --signed-at "2026-06-29T00:00:00Z" --output-mode in-place
  [ "$status" -eq 0 ]
  run python3 "$H" trust-store-verify --pinned-pubkey "$TD/root.pub" --trust-store "$TD/trust-store.yaml"; [ "$status" -eq 0 ]
}

@test "trust-store-sign: signature-only mode emits just the root_signature block, non-mutating" {
  local before; before="$(sha256sum "$TD/trust-store.yaml" | cut -d' ' -f1)"
  run python3 "$H" trust-store-sign --root-priv "$TD/root.priv" --trust-store "$TD/trust-store.yaml" \
      --signer-pubkey-from "$TD/root.pub" --signed-at "2026-06-28T00:00:00Z" --output-mode signature-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"root_signature"* ]]
  [[ "$output" != *"schema_version"* ]]
  [ "$(sha256sum "$TD/trust-store.yaml" | cut -d' ' -f1)" = "$before" ]
}

@test "trust-store-sign: a password-protected root key round-trips via --password-file" {
  python3 - "$TD" <<'PY'
import sys, yaml
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization
td=Path(sys.argv[1])
pub=lambda k:k.public_key().public_bytes(serialization.Encoding.PEM,serialization.PublicFormat.SubjectPublicKeyInfo).decode()
k=ed25519.Ed25519PrivateKey.generate()
enc=k.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,
    serialization.BestAvailableEncryption(b"s3cret"))
(td/"enc.priv").write_bytes(enc); (td/"enc.priv").chmod(0o600); (td/"enc.pub").write_text(pub(k))
(td/"pw.txt").write_text("s3cret"); (td/"pw.txt").chmod(0o600)
ts={"schema_version":"1.0","keys":[],"revocations":[],"trust_cutoff":{"default_strict_after":"2026-05-03T00:00:00Z"},
    "root_signature":{"algorithm":"ed25519","signer_pubkey":"","signed_at":"","signature":""}}
(td/"ts-enc.yaml").write_text(yaml.safe_dump(ts))
PY
  run python3 "$H" trust-store-sign --root-priv "$TD/enc.priv" --trust-store "$TD/ts-enc.yaml" \
      --signer-pubkey-from "$TD/enc.pub" --signed-at "2026-06-28T00:00:00Z" --output-mode in-place --password-file "$TD/pw.txt"
  [ "$status" -eq 0 ]
  run python3 "$H" trust-store-verify --pinned-pubkey "$TD/enc.pub" --trust-store "$TD/ts-enc.yaml"
  [ "$status" -eq 0 ]
}
