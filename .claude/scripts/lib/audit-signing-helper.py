#!/usr/bin/env python3
"""
audit-signing-helper.py — cycle-098 Sprint 1B.

Helper script invoked by audit-envelope.sh to perform Ed25519 signing and
verification operations. Keeps the cryptography dependency in Python (already
required for the Python adapter) and avoids exposing private-key material to
shell argv.

Subcommands:
  sign --key-id <id> --key-dir <dir> [--password-fd N|--password-file path]
       Reads canonical-JSON bytes from stdin, prints base64 signature on stdout.
  verify --pubkey-dir <dir> --key-id <id>
       Reads {chain_input_json}\\n{base64_sig}\\n from stdin; exits 0 on valid.
  trust-store-verify --pinned-pubkey <path> --trust-store <path>
       Verifies the trust-store's root_signature against the pinned pubkey.

Security invariants:
  - Passwords are loaded via fd or via mode-0600 file. NEVER from argv (the
    --password-fd / --password-file arguments are paths/fd-numbers, not
    secrets themselves).
  - LOA_AUDIT_KEY_PASSWORD env var is supported as a deprecated path with a
    stderr deprecation warning. The caller MUST scrub this var after invocation.
  - Empty / wrong passphrase → non-zero exit with structured stderr message.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import stat
from pathlib import Path

try:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ed25519
    from cryptography.exceptions import InvalidSignature
except ImportError as exc:  # pragma: no cover
    sys.stderr.write(
        "audit-signing-helper: cryptography not installed (pip install cryptography)\n"
    )
    sys.exit(78)  # EX_CONFIG


# Sentinel exit codes (mapped to shell exit codes).
EX_CONFIG = 78
EX_VERIFY_FAIL = 1
EX_USAGE = 2
EX_KEY_LOAD = 3


def _err(msg: str) -> None:
    sys.stderr.write(f"audit-signing-helper: {msg}\n")


def _read_password(args: argparse.Namespace) -> bytes | None:
    """
    Read a password from one of:
      --password-fd N       (file descriptor; preferred)
      --password-file PATH  (file with mode 0600; secondary preferred)
      LOA_AUDIT_KEY_PASSWORD (env var; DEPRECATED — emits stderr warning)
    Returns the password bytes (without trailing newline), or None if no
    password was provided (i.e., the key is unencrypted).
    """
    pw: bytes | None = None
    if args.password_fd is not None:
        fd = int(args.password_fd)
        # Read all bytes from the fd, then close it.
        try:
            with os.fdopen(fd, "rb", closefd=True) as f:
                pw = f.read()
        except OSError as exc:
            _err(f"failed to read --password-fd {fd}: {exc}")
            sys.exit(EX_KEY_LOAD)
    elif args.password_file:
        p = Path(args.password_file)
        if not p.is_file():
            _err(f"--password-file not found: {p}")
            sys.exit(EX_KEY_LOAD)
        # Permission check: refuse if not mode 0600 (owner-only RW).
        st_mode = p.stat().st_mode
        permissive = st_mode & (stat.S_IRWXG | stat.S_IRWXO)
        if permissive:
            _err(
                f"--password-file {p} has too permissive mode "
                f"({oct(st_mode & 0o777)}); require 0600"
            )
            sys.exit(EX_KEY_LOAD)
        pw = p.read_bytes()
    elif "LOA_AUDIT_KEY_PASSWORD" in os.environ:
        _err(
            "WARNING: LOA_AUDIT_KEY_PASSWORD env var is DEPRECATED (SKP-002). "
            "Use --password-fd or --password-file. Will be removed in v2.0."
        )
        pw = os.environ["LOA_AUDIT_KEY_PASSWORD"].encode()
        # Defense-in-depth: scrub the env var so child processes don't inherit it.
        del os.environ["LOA_AUDIT_KEY_PASSWORD"]

    if pw is not None:
        # Strip trailing newline if present (common when stored as a file).
        if pw.endswith(b"\n"):
            pw = pw[:-1]
        if not pw:
            return None
    return pw


def _load_private_key(
    key_dir: Path, key_id: str, password: bytes | None
) -> ed25519.Ed25519PrivateKey:
    priv_path = key_dir / f"{key_id}.priv"
    if not priv_path.is_file():
        # IMP-003 #1 review remediation: exit 78 (EX_CONFIG) when the
        # configured signing key file is missing — distinguishes "config
        # broken / bootstrap-pending" (78) from "key data corrupted" (EX_KEY_LOAD).
        # Operators reading the exit code can route 78 to the bootstrap
        # runbook and 3 to data-corruption recovery.
        _err(f"[BOOTSTRAP-PENDING] private key not found: {priv_path}")
        _err("Hint: see grimoires/loa/runbooks/audit-keys-bootstrap.md")
        sys.exit(EX_CONFIG)
    # Permission check: must be 0600.
    st_mode = priv_path.stat().st_mode
    permissive = st_mode & (stat.S_IRWXG | stat.S_IRWXO)
    if permissive:
        _err(
            f"private key {priv_path} has too permissive mode "
            f"({oct(st_mode & 0o777)}); require 0600"
        )
        sys.exit(EX_KEY_LOAD)
    try:
        priv = serialization.load_pem_private_key(priv_path.read_bytes(), password=password)
    except (TypeError, ValueError) as exc:
        _err(f"failed to load private key {priv_path}: {exc}")
        sys.exit(EX_KEY_LOAD)
    if not isinstance(priv, ed25519.Ed25519PrivateKey):
        _err(f"key at {priv_path} is not Ed25519")
        sys.exit(EX_KEY_LOAD)
    return priv


def _load_public_key(pubkey_dir: Path, key_id: str) -> ed25519.Ed25519PublicKey:
    pub_path = pubkey_dir / f"{key_id}.pub"
    if not pub_path.is_file():
        _err(f"public key not found: {pub_path}")
        sys.exit(EX_KEY_LOAD)
    pub_bytes = pub_path.read_bytes()
    try:
        pub = serialization.load_pem_public_key(pub_bytes)
    except ValueError as exc:
        _err(f"failed to load public key {pub_path}: {exc}")
        sys.exit(EX_KEY_LOAD)
    if not isinstance(pub, ed25519.Ed25519PublicKey):
        _err(f"key at {pub_path} is not Ed25519")
        sys.exit(EX_KEY_LOAD)
    return pub


def cmd_sign(args: argparse.Namespace) -> int:
    """Read canonical-JSON bytes from stdin; print base64 signature on stdout."""
    key_dir = Path(args.key_dir)
    if not key_dir.is_dir():
        _err(f"--key-dir does not exist: {key_dir}")
        return EX_KEY_LOAD
    pw = _read_password(args)
    priv = _load_private_key(key_dir, args.key_id, pw)
    data = sys.stdin.buffer.read()
    sig = priv.sign(data)
    sys.stdout.write(base64.b64encode(sig).decode())
    sys.stdout.flush()
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    """
    Read 'canonical_json_bytes\\nbase64_sig\\n' from stdin (sig on the LAST line).
    Verify the signature against the pubkey at <pubkey-dir>/<key-id>.pub.
    Exit 0 on valid; non-zero otherwise.
    """
    pubkey_dir = Path(args.pubkey_dir)
    pub = _load_public_key(pubkey_dir, args.key_id)
    raw = sys.stdin.buffer.read()
    # Split on the last newline; everything before is canonical bytes.
    if b"\n" not in raw:
        _err("verify: input must be canonical_bytes + '\\n' + base64_sig")
        return EX_VERIFY_FAIL
    idx = raw.rfind(b"\n")
    canonical = raw[:idx]
    sig_b64 = raw[idx + 1 :].rstrip(b"\n").rstrip(b"\r")
    try:
        sig = base64.b64decode(sig_b64, validate=True)
    except Exception as exc:
        _err(f"verify: signature is not valid base64: {exc}")
        return EX_VERIFY_FAIL
    try:
        pub.verify(sig, canonical)
    except InvalidSignature:
        return EX_VERIFY_FAIL
    return 0


def cmd_verify_inline(args: argparse.Namespace) -> int:
    """
    Same as cmd_verify, but the public key PEM is passed inline (used by
    trust-store-driven verification where keys are not on disk).

    Stdin: canonical_bytes + '\\n' + base64_sig
    Args:  --pubkey-pem <pem-string>
    """
    try:
        pub = serialization.load_pem_public_key(args.pubkey_pem.encode())
    except ValueError as exc:
        _err(f"verify: invalid pubkey PEM: {exc}")
        return EX_KEY_LOAD
    if not isinstance(pub, ed25519.Ed25519PublicKey):
        _err("verify: pubkey is not Ed25519")
        return EX_KEY_LOAD
    raw = sys.stdin.buffer.read()
    if b"\n" not in raw:
        _err("verify: input must be canonical_bytes + '\\n' + base64_sig")
        return EX_VERIFY_FAIL
    idx = raw.rfind(b"\n")
    canonical = raw[:idx]
    sig_b64 = raw[idx + 1 :].rstrip(b"\n").rstrip(b"\r")
    try:
        sig = base64.b64decode(sig_b64, validate=True)
    except Exception as exc:
        _err(f"verify: signature is not valid base64: {exc}")
        return EX_VERIFY_FAIL
    try:
        pub.verify(sig, canonical)
    except InvalidSignature:
        return EX_VERIFY_FAIL
    return 0


def cmd_trust_store_verify(args: argparse.Namespace) -> int:
    """
    Verify a trust-store YAML's root_signature against the pinned root pubkey.

    Trust-store YAML:
      schema_version, root_signature {algorithm, signer_pubkey, signed_at, signature},
      keys[], revocations[], trust_cutoff{...}

    Signed bytes: JCS canonicalization of {keys, revocations, trust_cutoff}.

    Multi-channel pubkey verification:
      - Pinned pubkey at args.pinned_pubkey (System Zone, frozen)
      - Trust-store's signer_pubkey field MUST match the pinned pubkey
      - On mismatch: emit [ROOT-PUBKEY-DIVERGENCE] BLOCKER
    """
    try:
        import yaml
    except ImportError:  # pragma: no cover
        _err("trust-store-verify: PyYAML required")
        return EX_CONFIG
    try:
        import rfc8785
    except ImportError:  # pragma: no cover
        _err("trust-store-verify: rfc8785 required")
        return EX_CONFIG

    pinned_path = Path(args.pinned_pubkey)
    if not pinned_path.is_file():
        _err(f"[ROOT-PUBKEY-MISSING] pinned root pubkey not found: {pinned_path}")
        return EX_VERIFY_FAIL

    ts_path = Path(args.trust_store)
    if not ts_path.is_file():
        _err(f"trust-store not found: {ts_path}")
        return EX_VERIFY_FAIL

    pinned_pem = pinned_path.read_bytes()
    try:
        pinned_pub = serialization.load_pem_public_key(pinned_pem)
    except ValueError as exc:
        _err(f"pinned pubkey is not valid PEM: {exc}")
        return EX_KEY_LOAD
    if not isinstance(pinned_pub, ed25519.Ed25519PublicKey):
        _err("pinned pubkey is not Ed25519")
        return EX_KEY_LOAD

    with ts_path.open("r", encoding="utf-8") as f:
        ts_doc = yaml.safe_load(f)

    if not isinstance(ts_doc, dict):
        _err("trust-store: not a YAML mapping")
        return EX_VERIFY_FAIL

    rs = ts_doc.get("root_signature")
    if not isinstance(rs, dict):
        _err("trust-store: missing root_signature")
        return EX_VERIFY_FAIL

    algorithm = rs.get("algorithm")
    if algorithm != "ed25519":
        _err(f"trust-store: unsupported algorithm: {algorithm}")
        return EX_VERIFY_FAIL

    signer_pubkey_pem = (rs.get("signer_pubkey") or "").strip()
    if not signer_pubkey_pem:
        _err("trust-store: missing signer_pubkey")
        return EX_VERIFY_FAIL

    # Multi-channel cross-check: signer_pubkey MUST match the pinned pubkey.
    try:
        signer_pub = serialization.load_pem_public_key(signer_pubkey_pem.encode())
    except ValueError as exc:
        _err(f"trust-store: signer_pubkey not valid PEM: {exc}")
        return EX_VERIFY_FAIL

    pinned_raw = pinned_pub.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    signer_raw = signer_pub.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    if pinned_raw != signer_raw:
        _err(
            "[ROOT-PUBKEY-DIVERGENCE] trust-store signer_pubkey does not match "
            "pinned root pubkey at " + str(pinned_path)
        )
        return EX_VERIFY_FAIL

    sig_b64 = rs.get("signature") or ""
    try:
        sig = base64.b64decode(sig_b64, validate=True)
    except Exception as exc:
        _err(f"trust-store: signature is not valid base64: {exc}")
        return EX_VERIFY_FAIL

    # Construct the signed core (deterministic JCS canonicalization).
    core = {
        "keys": ts_doc.get("keys") or [],
        "revocations": ts_doc.get("revocations") or [],
        "trust_cutoff": ts_doc.get("trust_cutoff") or {},
    }
    canonical = rfc8785.dumps(core)
    try:
        pinned_pub.verify(sig, canonical)
    except InvalidSignature:
        _err("trust-store: root_signature does NOT verify against pinned pubkey")
        return EX_VERIFY_FAIL
    return 0


def main() -> int:
    p = argparse.ArgumentParser(prog="audit-signing-helper")
    sub = p.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("sign")
    sp.add_argument("--key-id", required=True)
    sp.add_argument("--key-dir", required=True)
    grp = sp.add_mutually_exclusive_group()
    grp.add_argument("--password-fd", type=int, default=None)
    grp.add_argument("--password-file", type=str, default=None)
    sp.set_defaults(func=cmd_sign)

    vp = sub.add_parser("verify")
    vp.add_argument("--pubkey-dir", required=True)
    vp.add_argument("--key-id", required=True)
    vp.set_defaults(func=cmd_verify)

    vip = sub.add_parser("verify-inline")
    vip.add_argument("--pubkey-pem", required=True)
    vip.set_defaults(func=cmd_verify_inline)

    tsp = sub.add_parser("trust-store-verify")
    tsp.add_argument("--pinned-pubkey", required=True)
    tsp.add_argument("--trust-store", required=True)
    tsp.set_defaults(func=cmd_trust_store_verify)

    args = p.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
