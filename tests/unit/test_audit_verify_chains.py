"""cycle-137 FR-7 (bd-09z1i, SDD § 5.7): `audit_verify_chains` equivalence proof.

The batch entry point verifies N chains in one process by calling the
UNCHANGED `audit_verify_chain` once per path. This file proves that the batch
records equal fresh per-call results when the trust store is mutated BETWEEN
paths (replace with a store revoking the signing key; tamper the store; delete
it; tamper then repair), using a hook that wraps — never edits — the protected
functions: `audit_verify_chain` is monkeypatched with a wrapper that calls the
original and then applies the scheduled mutation.

Two oracles, both independent of the batch: a fresh process per call
(`subprocess`) and an in-process sequential loop (valid because
`_TRUST_STORE_CACHE` is content-keyed, nothing is cleared between calls).
Expected outcomes are also stated by hand per schedule.

Run: python -m pytest tests/unit/test_audit_verify_chains.py -q
"""

from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

rfc8785 = pytest.importorskip("rfc8785")
yaml = pytest.importorskip("yaml")
pytest.importorskip("cryptography")
from cryptography.hazmat.primitives import serialization  # noqa: E402
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
ADAPTERS = REPO / ".claude" / "adapters"
sys.path.insert(0, str(ADAPTERS))
from loa_cheval import audit_envelope as audit  # noqa: E402

ORIGINAL_VERIFY = audit.audit_verify_chain
STORE_INVALID = (
    "[TRUST-STORE-INVALID] trust-store root_signature does NOT verify "
    "against pinned root pubkey; refusing all writes/reads (issue #690)"
)
BOOTSTRAP_SIGNED = "[TRUST-STORE-BOOTSTRAP-PENDING] signed history requires a verified store"


def _pem(key):
    return key.public_key().public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo
    ).decode()


class Fixture:
    def __init__(self, root: Path):
        self.root = root
        self.root_key = Ed25519PrivateKey.generate()
        self.writer = Ed25519PrivateKey.generate()
        self.rogue = Ed25519PrivateKey.generate()
        self.pin = root / "root.pub"
        self.pin.write_text(_pem(self.root_key))
        self.store = root / "trust-store.yaml"
        self.keys = root / "keys"
        self.keys.mkdir()
        self.good_store = self._signed_store()
        self.revoking_store = self._signed_store(revocations=[{
            "writer_id": "w1", "pubkey_pem": _pem(self.writer),
            "revoked_at": "2021-01-01T00:00:00Z",
        }])
        doc = yaml.safe_load(self.good_store)
        doc["keys"].append({"writer_id": "rogue", "pubkey_pem": _pem(self.rogue)})
        self.tampered_store = yaml.safe_dump(doc)
        self.chains = []
        for name in ("a", "b", "c"):
            path = root / f"chain {name}.jsonl"
            path.write_text(self._chain(name))
            self.chains.append(path)
        self.reset_store()

    def _signed_store(self, revocations=()):
        core = {
            "schema_version": "1.0",
            "keys": [{"writer_id": "w1", "pubkey_pem": _pem(self.writer)}],
            "revocations": list(revocations),
            "trust_cutoff": {"default_strict_after": "2020-01-01T00:00:00Z"},
        }
        return yaml.safe_dump({**core, "root_signature": {
            "algorithm": "ed25519", "signer_pubkey": _pem(self.root_key),
            "signed_at": "2020-01-01T00:00:00Z",
            "signature": base64.b64encode(self.root_key.sign(rfc8785.dumps(core))).decode(),
        }})

    def _chain(self, tag):
        prev, lines = "GENESIS", []
        for k in range(2):
            env = {
                "schema_version": "1.1.0", "primitive_id": "L1", "event_type": "test.event",
                "ts_utc": f"2024-01-01T00:00:0{k}.000000Z", "prev_hash": prev,
                "payload": {"n": k, "tag": tag}, "redaction_applied": None,
                "signing_key_id": "w1",
            }
            env["signature"] = base64.b64encode(
                self.writer.sign(audit._chain_input_bytes(env))
            ).decode()
            lines.append(json.dumps(env))
            prev = audit._sha256_hex(audit._chain_input_bytes(env))
        return "\n".join(lines) + "\n"

    def reset_store(self):
        self.store.write_text(self.good_store)

    def mutate(self, action):
        if action == "revoke":
            self.store.write_text(self.revoking_store)
        elif action == "tamper":
            self.store.write_text(self.tampered_store)
        elif action == "delete":
            self.store.unlink()
        elif action == "repair":
            self.store.write_text(self.good_store)
        else:  # pragma: no cover
            raise AssertionError(action)


@pytest.fixture
def fx(tmp_path, monkeypatch):
    for key in list(os.environ):
        if key.startswith("LOA_AUDIT_") or key in ("LOA_TRUST_STORE_FILE", "LOA_PINNED_ROOT_PUBKEY_PATH"):
            monkeypatch.delenv(key, raising=False)
    f = Fixture(tmp_path)
    monkeypatch.setenv("LOA_TRUST_STORE_FILE", str(f.store))
    monkeypatch.setenv("LOA_PINNED_ROOT_PUBKEY_PATH", str(f.pin))
    monkeypatch.setenv("LOA_AUDIT_KEY_DIR", str(f.keys))
    return f


def _record(i, path, ok, message):
    return {"i": i, "path": str(path), "ok": ok, "error": None if ok else message}


def _batch(fx, monkeypatch, schedule, strict):
    """The batch, with `schedule[k]` applied right after path k is verified."""
    fx.reset_store()
    calls = []

    def hooked(path, *, verify_for_merge=False):
        result = ORIGINAL_VERIFY(path, verify_for_merge=verify_for_merge)
        k = len(calls)
        calls.append(str(path))
        if schedule.get(k):
            fx.mutate(schedule[k])
        return result

    monkeypatch.setattr(audit, "audit_verify_chain", hooked)
    try:
        return audit.audit_verify_chains(fx.chains, verify_for_merge=strict)
    finally:
        monkeypatch.setattr(audit, "audit_verify_chain", ORIGINAL_VERIFY)
        assert calls == [str(p) for p in fx.chains]


def _oracle_in_process(fx, schedule, strict):
    fx.reset_store()
    out = []
    for k, path in enumerate(fx.chains):
        ok, message = ORIGINAL_VERIFY(path, verify_for_merge=strict)
        out.append(_record(k, path, ok, message))
        if schedule.get(k):
            fx.mutate(schedule[k])
    return out


_ONE_CALL = (
    "import json, sys\n"
    "sys.path.insert(0, sys.argv[1])\n"
    "from loa_cheval.audit_envelope import audit_verify_chain\n"
    "print(json.dumps(audit_verify_chain(sys.argv[2], verify_for_merge=sys.argv[3] == '1')))\n"
)


def _oracle_fresh_process(fx, schedule, strict):
    fx.reset_store()
    out = []
    for k, path in enumerate(fx.chains):
        proc = subprocess.run(
            [sys.executable, "-c", _ONE_CALL, str(ADAPTERS), str(path), "1" if strict else "0"],
            capture_output=True, text=True, env=dict(os.environ), check=True,
        )
        ok, message = json.loads(proc.stdout)
        out.append(_record(k, path, ok, message))
        if schedule.get(k):
            fx.mutate(schedule[k])
    return out


# schedule: {index of the path AFTER which the mutation runs: action}
# expected: per path, None for ok or the expected error (a str prefix match).
SCHEDULES = {
    "unchanged": ({}, [None, None, None]),
    "revoke-after-a": ({0: "revoke"}, [None, "BROKEN line 1: cannot resolve public key for signing_key_id=w1",
                                       "BROKEN line 1: cannot resolve public key for signing_key_id=w1"]),
    "revoke-after-b": ({1: "revoke"}, [None, None, "BROKEN line 1: cannot resolve public key for signing_key_id=w1"]),
    "tamper-after-a": ({0: "tamper"}, [None, STORE_INVALID, STORE_INVALID]),
    "delete-after-a": ({0: "delete"}, [None, "BROKEN line 1: " + BOOTSTRAP_SIGNED,
                                       "BROKEN line 1: " + BOOTSTRAP_SIGNED]),
    "tamper-then-repair": ({0: "tamper", 1: "repair"}, [None, STORE_INVALID, None]),
}
STRICT_DELETE_ERR = "[TRUST-STORE-BOOTSTRAP-PENDING] trust-store is not signed"


@pytest.mark.parametrize("strict", [False, True], ids=["default", "verify-for-merge"])
@pytest.mark.parametrize("name", list(SCHEDULES))
def test_batch_equals_per_call_under_store_mutation_schedule(fx, monkeypatch, name, strict):
    schedule, expected = SCHEDULES[name]
    batch = _batch(fx, monkeypatch, schedule, strict)
    in_process = _oracle_in_process(fx, schedule, strict)
    fresh = _oracle_fresh_process(fx, schedule, strict)
    print(f"\n[{name} strict={strict}]")
    for rec in batch:
        print("  batch:", json.dumps(rec))
    assert in_process == fresh, "the two oracles disagree"
    assert batch == fresh
    # Independently stated outcomes.
    for k, want in enumerate(expected):
        rec = batch[k]
        assert rec["i"] == k and rec["path"] == str(fx.chains[k])
        if strict and name == "delete-after-a" and k > 0:
            want = STRICT_DELETE_ERR  # strict refuses the missing store before the walk
        if want is None:
            assert rec["ok"] is True and rec["error"] is None, rec
        else:
            assert rec["ok"] is False and rec["error"].startswith(want), rec


def test_store_reauthenticated_only_when_its_content_changes(fx, monkeypatch):
    """The subprocess snapshot (trust-store-verify) runs once for an unchanged
    store and again after each content change between paths."""
    real_run = subprocess.run
    helper_calls = []

    def counting_run(argv, *args, **kwargs):
        if "trust-store-verify" in argv:
            helper_calls.append(argv)
        return real_run(argv, *args, **kwargs)

    monkeypatch.setattr(subprocess, "run", counting_run)
    audit._TRUST_STORE_CACHE.update(path=None, key=None, status=None, document=None)
    assert [r["ok"] for r in _batch(fx, monkeypatch, {}, False)] == [True, True, True]
    assert len(helper_calls) == 1
    helper_calls.clear()
    audit._TRUST_STORE_CACHE.update(path=None, key=None, status=None, document=None)
    records = _batch(fx, monkeypatch, {0: "tamper", 1: "repair"}, False)
    assert [r["ok"] for r in records] == [True, False, True]
    assert len(helper_calls) == 3  # good, tampered, good again (repair re-authenticates)


def test_per_path_exception_is_isolated_and_missing_is_reported(fx, monkeypatch):
    def flaky(path, *, verify_for_merge=False):
        if Path(path).name == "chain b.jsonl":
            raise ValueError("boom")
        return ORIGINAL_VERIFY(path, verify_for_merge=verify_for_merge)

    monkeypatch.setattr(audit, "audit_verify_chain", flaky)
    missing = fx.root / "nope.jsonl"
    records = audit.audit_verify_chains([*fx.chains, missing])
    assert records == [
        {"i": 0, "path": str(fx.chains[0]), "ok": True, "error": None},
        {"i": 1, "path": str(fx.chains[1]), "ok": False, "error": "ValueError: boom"},
        {"i": 2, "path": str(fx.chains[2]), "ok": True, "error": None},
        {"i": 3, "path": str(missing), "ok": False, "error": "missing"},
    ]


def test_empty_input_returns_no_records(fx):
    assert audit.audit_verify_chains([]) == []
