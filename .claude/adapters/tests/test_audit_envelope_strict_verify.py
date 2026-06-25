"""Regression tests for strict audit-envelope verification.

Pins ATK-3 / ATK-4 fail-closed behavior without changing install-time writes.
"""

from __future__ import annotations

import base64
import json
import sys
from pathlib import Path

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval import audit_envelope


def _write_minimal_log(log_path: Path) -> None:
    envelope = {
        "schema_version": audit_envelope.DEFAULT_SCHEMA_VERSION,
        "primitive_id": "L1",
        "event_type": "test.event",
        "ts_utc": "2026-06-22T00:00:00.000000Z",
        "prev_hash": "GENESIS",
        "payload": {"ok": True},
        "redaction_applied": None,
    }
    log_path.write_text(json.dumps(envelope, separators=(",", ":")) + "\n", encoding="utf-8")


def _pubkey_pem(priv) -> str:
    from cryptography.hazmat.primitives import serialization

    return priv.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode()


def _privkey_pem(priv) -> bytes:
    from cryptography.hazmat.primitives import serialization

    return priv.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


@pytest.fixture(autouse=True)
def _clear_env_and_cache(monkeypatch):
    for name in (
        "LOA_TRUST_STORE_FILE",
        "LOA_PINNED_ROOT_PUBKEY_PATH",
        "LOA_AUDIT_KEY_DIR",
        "LOA_AUDIT_STRICT_VERIFY",
        "LOA_AUDIT_VERIFY_SIGS",
    ):
        monkeypatch.delenv(name, raising=False)
    audit_envelope._TRUST_STORE_CACHE.update({"path": None, "key": None, "status": None})


def test_strict_verify_bootstrap_pending_fails_closed(tmp_path: Path, monkeypatch):
    """ATK-3: BOOTSTRAP-PENDING must not pass verify-for-merge."""
    trust_store = tmp_path / "trust-store.yaml"
    trust_store.write_text(
        yaml.safe_dump(
            {
                "schema_version": "1.0",
                "root_signature": {
                    "algorithm": "ed25519",
                    "signer_pubkey": "",
                    "signed_at": "",
                    "signature": "",
                },
                "keys": [],
                "revocations": [],
                "trust_cutoff": {"default_strict_after": "2026-01-01T00:00:00Z"},
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setenv("LOA_TRUST_STORE_FILE", str(trust_store))

    log_path = tmp_path / "audit.jsonl"
    _write_minimal_log(log_path)

    ok, msg = audit_envelope.audit_verify_chain(log_path, verify_for_merge=True)

    assert ok is False
    assert "[TRUST-STORE-BOOTSTRAP-PENDING]" in msg
    assert "ATK-3" in msg


def test_strict_verify_refuses_local_pubkey_fallback(tmp_path: Path, monkeypatch):
    """ATK-3: strict verify accepts only trust-store-rooted writer keys."""
    rfc8785 = pytest.importorskip("rfc8785")
    from cryptography.hazmat.primitives.asymmetric import ed25519

    root_priv = ed25519.Ed25519PrivateKey.generate()
    writer_priv = ed25519.Ed25519PrivateKey.generate()
    writer_id = "producer-controlled"

    pinned_root = tmp_path / "root.pub"
    pinned_root.write_text(_pubkey_pem(root_priv), encoding="utf-8")

    key_dir = tmp_path / "keys"
    key_dir.mkdir()
    (key_dir / f"{writer_id}.priv").write_bytes(_privkey_pem(writer_priv))
    (key_dir / f"{writer_id}.priv").chmod(0o600)
    (key_dir / f"{writer_id}.pub").write_text(_pubkey_pem(writer_priv), encoding="utf-8")

    core = {
        "schema_version": "1.0",
        "keys": [],
        "revocations": [],
        "trust_cutoff": {"default_strict_after": "2020-01-01T00:00:00Z"},
    }
    trust_store = tmp_path / "trust-store.yaml"
    trust_store.write_text(
        yaml.safe_dump(
            {
                **core,
                "root_signature": {
                    "algorithm": "ed25519",
                    "signer_pubkey": _pubkey_pem(root_priv),
                    "signed_at": "2026-06-22T00:00:00Z",
                    "signature": base64.b64encode(root_priv.sign(rfc8785.dumps(core))).decode(),
                },
            }
        ),
        encoding="utf-8",
    )

    monkeypatch.setenv("LOA_TRUST_STORE_FILE", str(trust_store))
    monkeypatch.setenv("LOA_PINNED_ROOT_PUBKEY_PATH", str(pinned_root))
    monkeypatch.setenv("LOA_AUDIT_KEY_DIR", str(key_dir))

    envelope = {
        "schema_version": audit_envelope.DEFAULT_SCHEMA_VERSION,
        "primitive_id": "L1",
        "event_type": "test.event",
        "ts_utc": "2026-06-22T00:00:00.000000Z",
        "prev_hash": "GENESIS",
        "payload": {"signed": True},
        "redaction_applied": None,
    }
    envelope["signing_key_id"] = writer_id
    envelope["signature"] = base64.b64encode(
        writer_priv.sign(audit_envelope._chain_input_bytes(envelope))
    ).decode()

    log_path = tmp_path / "audit.jsonl"
    log_path.write_text(json.dumps(envelope, separators=(",", ":")) + "\n", encoding="utf-8")

    ok, msg = audit_envelope.audit_verify_chain(log_path)
    assert (ok, msg) == (True, "OK 1 entries")

    ok, msg = audit_envelope.audit_verify_chain(log_path, verify_for_merge=True)
    assert ok is False
    assert "cannot resolve public key" in msg
    assert f"signing_key_id={writer_id}" in msg
