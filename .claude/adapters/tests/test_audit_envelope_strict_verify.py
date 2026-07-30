"""Regression tests for strict audit-envelope verification.

Pins ATK-3 / ATK-4 fail-closed behavior without changing install-time writes.
"""

from __future__ import annotations

import base64
import json
import subprocess
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
        # An operator env var: left set, audit_emit would fail at SIGNING
        # instead of at the trust-store gate the write tests assert on.
        "LOA_AUDIT_SIGNING_KEY_ID",
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


# -----------------------------------------------------------------------------
# Issue #1211 — trust-store fail-open.
#
# (1) A trust-store file that EXISTS but cannot be parsed was downgraded to
#     BOOTSTRAP-PENDING, which _check_trust_store permits for writes and for
#     default (non-strict) verification. Present-but-unparseable must read
#     INVALID (fail closed); only an ABSENT store is BOOTSTRAP-PENDING.
# (2) revocations[] is root-signed but was never consulted at verify time, so
#     revoking a writer key revoked nothing.
# -----------------------------------------------------------------------------

_REPO_ROOT = Path(__file__).resolve().parents[3]
_BASH_ENVELOPE = _REPO_ROOT / ".claude" / "scripts" / "audit-envelope.sh"

_MALFORMED_TRUST_STORE = "schema_version: '1.0'\nkeys: [\n  - writer_id: alice: bad\n"


def _write_signed_trust_store(path: Path, root_priv, *, keys, revocations, cutoff) -> None:
    """Root-sign a trust-store over the JCS core the signing helper checks."""
    rfc8785 = pytest.importorskip("rfc8785")
    core = {
        "schema_version": "1.0",
        "keys": keys,
        "revocations": revocations,
        "trust_cutoff": {"default_strict_after": cutoff},
    }
    path.write_text(
        yaml.safe_dump(
            {
                **core,
                "root_signature": {
                    "algorithm": "ed25519",
                    "signer_pubkey": _pubkey_pem(root_priv),
                    "signed_at": "2026-06-22T00:00:00Z",
                    "signature": base64.b64encode(
                        root_priv.sign(rfc8785.dumps(core))
                    ).decode(),
                },
            }
        ),
        encoding="utf-8",
    )


def _write_signed_entry(log_path: Path, priv, writer_id: str, ts_utc: str) -> None:
    envelope = {
        "schema_version": audit_envelope.DEFAULT_SCHEMA_VERSION,
        "primitive_id": "L1",
        "event_type": "test.event",
        "ts_utc": ts_utc,
        "prev_hash": "GENESIS",
        "payload": {"signed": True},
        "redaction_applied": None,
        "signing_key_id": writer_id,
    }
    envelope["signature"] = base64.b64encode(
        priv.sign(audit_envelope._chain_input_bytes(envelope))
    ).decode()
    log_path.write_text(json.dumps(envelope, separators=(",", ":")) + "\n", encoding="utf-8")


def _bash_verify_chain(log_path: Path, *, verify_for_merge: bool = False):
    """Run the bash twin (R15 behavior identity) and return (rc, stdout+stderr)."""
    flag = "--verify-for-merge " if verify_for_merge else ""
    proc = subprocess.run(
        ["bash", "-c", f'source "$1"; audit_verify_chain {flag}"$2"',
         "bash", str(_BASH_ENVELOPE), str(log_path)],
        capture_output=True, text=True,
    )
    return proc.returncode, proc.stdout + proc.stderr


def _revoked_store_fixture(tmp_path: Path, monkeypatch):
    """Root-signed store: writer `alice` present in keys[] AND revoked."""
    pytest.importorskip("rfc8785")
    from cryptography.hazmat.primitives.asymmetric import ed25519

    root_priv = ed25519.Ed25519PrivateKey.generate()
    writer_priv = ed25519.Ed25519PrivateKey.generate()

    pinned_root = tmp_path / "root.pub"
    pinned_root.write_text(_pubkey_pem(root_priv), encoding="utf-8")

    trust_store = tmp_path / "trust-store.yaml"
    _write_signed_trust_store(
        trust_store,
        root_priv,
        keys=[{"writer_id": "alice", "pubkey_pem": _pubkey_pem(writer_priv)}],
        revocations=[{"writer_id": "alice", "revoked_at": "2020-01-02T00:00:00Z",
                      "reason": "key compromise"}],
        cutoff="2020-01-01T00:00:00Z",
    )

    monkeypatch.setenv("LOA_TRUST_STORE_FILE", str(trust_store))
    monkeypatch.setenv("LOA_PINNED_ROOT_PUBKEY_PATH", str(pinned_root))
    monkeypatch.setenv("LOA_AUDIT_KEY_DIR", str(tmp_path / "no-keys"))
    return writer_priv


def test_unparseable_trust_store_reads_invalid(tmp_path: Path, monkeypatch):
    """#1211: a present-but-unparseable store is INVALID, not BOOTSTRAP-PENDING."""
    trust_store = tmp_path / "trust-store.yaml"
    trust_store.write_text(_MALFORMED_TRUST_STORE, encoding="utf-8")
    monkeypatch.setenv("LOA_TRUST_STORE_FILE", str(trust_store))

    assert audit_envelope._trust_store_status() == "INVALID"


def test_unparseable_trust_store_fails_default_verify(tmp_path: Path, monkeypatch):
    """#1211: default (non-strict) verify — production's mode — fails closed."""
    trust_store = tmp_path / "trust-store.yaml"
    trust_store.write_text(_MALFORMED_TRUST_STORE, encoding="utf-8")
    monkeypatch.setenv("LOA_TRUST_STORE_FILE", str(trust_store))

    log_path = tmp_path / "audit.jsonl"
    _write_minimal_log(log_path)

    ok, msg = audit_envelope.audit_verify_chain(log_path)
    assert ok is False
    assert "[TRUST-STORE-INVALID]" in msg


def test_unparseable_trust_store_refuses_writes(tmp_path: Path, monkeypatch):
    """#1211: the fail-open state also permitted appends — writes must refuse."""
    trust_store = tmp_path / "trust-store.yaml"
    trust_store.write_text(_MALFORMED_TRUST_STORE, encoding="utf-8")
    monkeypatch.setenv("LOA_TRUST_STORE_FILE", str(trust_store))

    with pytest.raises(RuntimeError, match=r"\[TRUST-STORE-INVALID\]"):
        audit_envelope.audit_emit(
            "L1", "test.event", {"ok": True}, tmp_path / "audit.jsonl"
        )


def test_unparseable_trust_store_bash_python_parity(tmp_path: Path, monkeypatch):
    """R15: the bash twin fails closed on the same fixture."""
    trust_store = tmp_path / "trust-store.yaml"
    trust_store.write_text(_MALFORMED_TRUST_STORE, encoding="utf-8")
    monkeypatch.setenv("LOA_TRUST_STORE_FILE", str(trust_store))

    log_path = tmp_path / "audit.jsonl"
    _write_minimal_log(log_path)

    rc, out = _bash_verify_chain(log_path)
    assert rc != 0
    assert "[TRUST-STORE-INVALID]" in out


def test_absent_trust_store_stays_bootstrap_pending(tmp_path: Path, monkeypatch):
    """Install-time bootstrap preserved: an ABSENT store stays permissive."""
    monkeypatch.setenv("LOA_TRUST_STORE_FILE", str(tmp_path / "absent.yaml"))

    log_path = tmp_path / "audit.jsonl"
    _write_minimal_log(log_path)

    assert audit_envelope._trust_store_status() == "BOOTSTRAP-PENDING"
    assert audit_envelope.audit_verify_chain(log_path) == (True, "OK 1 entries")

    rc, out = _bash_verify_chain(log_path)
    assert rc == 0
    assert "OK 1 entries" in out


def test_revoked_writer_rejected_after_revocation(tmp_path: Path, monkeypatch):
    """#1211: revocations[] must be consulted — post-revocation entry rejected."""
    writer_priv = _revoked_store_fixture(tmp_path, monkeypatch)
    log_path = tmp_path / "audit.jsonl"
    _write_signed_entry(log_path, writer_priv, "alice", "2026-07-30T00:00:00.000000Z")

    for verify_for_merge in (False, True):
        ok, msg = audit_envelope.audit_verify_chain(
            log_path, verify_for_merge=verify_for_merge
        )
        assert ok is False, f"verify_for_merge={verify_for_merge}"
        assert "[KEY-REVOKED]" in msg
        assert "signing_key_id=alice" in msg

    for verify_for_merge in (False, True):
        rc, out = _bash_verify_chain(log_path, verify_for_merge=verify_for_merge)
        assert rc != 0, f"bash verify_for_merge={verify_for_merge}: {out}"
        assert "[KEY-REVOKED]" in out


def test_pre_revocation_entry_still_verifies(tmp_path: Path, monkeypatch):
    """Grandfathering per runbooks/audit-keys-bootstrap.md: ts < revoked_at is OK."""
    writer_priv = _revoked_store_fixture(tmp_path, monkeypatch)
    log_path = tmp_path / "audit.jsonl"
    _write_signed_entry(log_path, writer_priv, "alice", "2019-06-01T00:00:00.000000Z")

    assert audit_envelope.audit_verify_chain(log_path) == (True, "OK 1 entries")

    rc, out = _bash_verify_chain(log_path)
    assert rc == 0, out
    assert "OK 1 entries" in out
