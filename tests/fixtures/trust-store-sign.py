#!/usr/bin/env python3
"""
trust-store-sign.py — cycle-098 Sprint 1.5 (#695 F9 + bridgebuilder F-001
remediation).

Standalone test fixture for signing trust-stores in tests. Replaces the
brittle bats `_sign_*_trust_store` heredoc helpers that injected Python via
shell here-docs, and the cross-runtime `declare -f` injection used in mtime
invalidation tests.

This is a single source of truth: bats tests + Python subprocesses both call
this fixture directly with stable CLI arguments. No nested-quoting brittleness;
no cross-language scope leakage.

Usage:
  trust-store-sign.py \\
      --out PATH                  \\
      --signer-priv PRIV.pem      \\
      [--mode bootstrap-pending|empty|populated] \\
      [--schema-version 1.0]      \\
      [--keys-pubkey PUB.pem]     \\
      [--cutoff 2026-05-02T00:00:00Z]

Modes:
  bootstrap-pending — empty signature, empty keys, empty revocations
                      (cycle-098 install-time default)
  empty             — sign empty {keys, revocations} but with valid root_signature
  populated         — sign with one writer key in keys[]

Sprint 1.5 #695 F9: schema_version IS in the signed payload.
"""
from __future__ import annotations

import argparse
import base64
import sys
from pathlib import Path

try:
    from cryptography.hazmat.primitives.asymmetric import ed25519
    from cryptography.hazmat.primitives import serialization
    import rfc8785
except ImportError as exc:
    sys.stderr.write(f"trust-store-sign: missing dep: {exc}\n")
    sys.exit(78)


def _yaml_block(pem: str, indent: int = 4) -> str:
    pad = " " * indent
    return "\n".join(pad + line for line in pem.strip().split("\n"))


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True, type=Path)
    p.add_argument("--signer-priv", required=True, type=Path,
                   help="Private key PEM file (PKCS8) — used only when mode != bootstrap-pending")
    p.add_argument("--mode", choices=("bootstrap-pending", "empty", "populated"),
                   default="empty")
    p.add_argument("--schema-version", default="1.0")
    p.add_argument("--cutoff", default="2026-05-02T00:00:00Z")
    p.add_argument("--writer-pubkey-out", type=Path, default=None,
                   help="Optional: write a generated writer pubkey PEM to this path "
                        "(populated mode only).")
    args = p.parse_args()

    if args.mode == "bootstrap-pending":
        # No signing — empty signature, empty keys.
        yaml_text = f"""---
schema_version: "{args.schema_version}"
root_signature:
  algorithm: ed25519
  signer_pubkey: ""
  signed_at: ""
  signature: ""
keys: []
revocations: []
trust_cutoff:
  default_strict_after: "2099-01-01T00:00:00Z"
"""
        args.out.write_text(yaml_text)
        return 0

    # Sign: load signer priv, build core, canonicalize, sign.
    priv = serialization.load_pem_private_key(args.signer_priv.read_bytes(), password=None)
    pub_pem = priv.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode()

    keys: list = []
    if args.mode == "populated":
        writer = ed25519.Ed25519PrivateKey.generate()
        writer_pub_pem = writer.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        ).decode()
        keys = [{
            "writer_id": "test-writer-1",
            "operator_id": "test-operator",
            "pubkey_pem": writer_pub_pem,
            "valid_from": "2026-05-03T00:00:00Z",
            "valid_until": None,
        }]
        if args.writer_pubkey_out:
            args.writer_pubkey_out.write_text(writer_pub_pem)

    # Sprint 1.5 #695 F9: schema_version IS in the signed payload.
    core = {
        "schema_version": args.schema_version,
        "keys": keys,
        "revocations": [],
        "trust_cutoff": {"default_strict_after": args.cutoff},
    }
    sig_b64 = base64.b64encode(priv.sign(rfc8785.dumps(core))).decode()

    # Hand-write YAML to keep field order stable.
    keys_yaml = "[]"
    if keys:
        k0 = keys[0]
        keys_yaml = (
            "\n  - writer_id: \"test-writer-1\""
            "\n    operator_id: \"test-operator\""
            "\n    pubkey_pem: |\n"
            f"{_yaml_block(k0['pubkey_pem'], 6)}"
            "\n    valid_from: \"2026-05-03T00:00:00Z\""
            "\n    valid_until: null"
        )

    yaml_text = f"""---
schema_version: "{args.schema_version}"
root_signature:
  algorithm: ed25519
  signer_pubkey: |
{_yaml_block(pub_pem, 4)}
  signed_at: "2026-05-03T00:00:00Z"
  signature: "{sig_b64}"
keys: {keys_yaml}
revocations: []
trust_cutoff:
  default_strict_after: "{args.cutoff}"
"""
    args.out.write_text(yaml_text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
