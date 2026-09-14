"""Real Ed25519 attack paths through both adapters and the rollup caller.

Run: python3 tests/security/test_audit_trust_policy.py
No network, operator keys, or repository trust-store mutations.
"""

import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import rfc8785
import yaml
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / ".claude/adapters"))
from loa_cheval import audit_envelope as audit


def pem(key):
    return key.public_key().public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo
    ).decode()


class AuditTrustPolicy(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.root_key = Ed25519PrivateKey.generate()
        self.writer = Ed25519PrivateKey.generate()
        self.rogue = Ed25519PrivateKey.generate()
        self.store = self.root / "trust.yaml"
        self.log = self.root / "log.jsonl"
        self.pin = self.root / "root.pub"
        self.pin.write_text(pem(self.root_key))
        self.keys = self.root / "keys"
        self.keys.mkdir()
        for name, key in (("writer", self.writer), ("rogue", self.rogue)):
            (self.keys / f"{name}.pub").write_text(pem(key))
        env = {k: v for k, v in os.environ.items() if not k.startswith("LOA_AUDIT_")}
        env.update(
            LOA_TRUST_STORE_FILE=str(self.store),
            LOA_PINNED_ROOT_PUBKEY_PATH=str(self.pin),
            LOA_AUDIT_KEY_DIR=str(self.keys),
        )
        self.env_patch = patch.dict(os.environ, env, clear=True)
        self.env_patch.start()
        self.addCleanup(self.env_patch.stop)
        audit._TRUST_STORE_CACHE.update(path=None, key=None, status=None)
        self.sign_store()
        self.write_log()

    def sign_store(self, cutoff="2020-01-01T00:00:00Z", revocations=None, keys=None):
        core = {
            "schema_version": "1.0",
            "keys": keys if keys is not None else [
                {"writer_id": "writer", "pubkey_pem": pem(self.writer)}
            ],
            "revocations": revocations or [],
            "trust_cutoff": {} if cutoff is None else {"default_strict_after": cutoff},
        }
        self.store.write_text(yaml.safe_dump({
            **core,
            "root_signature": {
                "algorithm": "ed25519",
                "signer_pubkey": pem(self.root_key),
                "signed_at": "2020-01-01T00:00:00Z",
                "signature": base64.b64encode(
                    self.root_key.sign(rfc8785.dumps(core))
                ).decode(),
            },
        }))

    def write_log(self, *, key="writer", ts="2024-01-01T00:00:00.000000Z"):
        envelope = {
            "schema_version": "1.2.0",
            "primitive_id": "MODELINV",
            "event_type": "model.invoke",
            "ts_utc": ts,
            "prev_hash": "GENESIS",
            "payload": {
                "writer_version": "1.2", "final_model_id": "test",
                "cost_micro_usd": 1, "pricing_snapshot": {},
            },
            "redaction_applied": None,
        }
        if key:
            private = self.writer if key == "writer" else self.rogue
            envelope["signing_key_id"] = key
            envelope["signature"] = base64.b64encode(
                private.sign(audit._chain_input_bytes(envelope))
            ).decode()
        self.log.write_text(json.dumps(envelope) + "\n")

    def verify(self, adapter, strict=True):
        if adapter == "python":
            return audit.audit_verify_chain(self.log, verify_for_merge=strict)
        proc = subprocess.run(
            ["bash", str(REPO / ".claude/scripts/audit-envelope.sh"), "verify-chain",
             *(["--verify-for-merge"] if strict else []), str(self.log)],
            text=True, capture_output=True,
        )
        return proc.returncode == 0, proc.stdout + proc.stderr

    def both(self, expected, *, strict=True, diagnostic=None):
        for adapter in ("python", "bash"):
            with self.subTest(adapter=adapter, strict=strict):
                ok, message = self.verify(adapter, strict)
                self.assertEqual(ok, expected, message)
                if diagnostic:
                    self.assertIn(diagnostic, message)

    def test_root_bound_writer_passes(self):
        self.both(True)

    def test_warm_cache_tracks_pin_path_content_and_existence(self):
        alternate = self.root / "alternate.pub"
        alternate.write_text(pem(self.rogue))
        for change in ("content", "path", "missing"):
            with self.subTest(change=change):
                self.pin.write_text(pem(self.root_key))
                os.environ["LOA_PINNED_ROOT_PUBKEY_PATH"] = str(self.pin)
                self.assertTrue(self.verify("python")[0])
                if change == "content":
                    self.pin.write_text(pem(self.rogue))
                elif change == "path":
                    os.environ["LOA_PINNED_ROOT_PUBKEY_PATH"] = str(alternate)
                else:
                    self.pin.unlink()
                self.assertFalse(audit.audit_trust_store_verify(self.store)[0])
                ok, message = self.verify("python")
                self.assertFalse(ok, message)
                # A repaired pin must invalidate a cached rejection too.
                self.pin.write_text(pem(self.root_key))
                os.environ["LOA_PINNED_ROOT_PUBKEY_PATH"] = str(self.pin)
                self.assertTrue(self.verify("python")[0])

    def test_authentication_uses_the_pin_bytes_captured_for_cache_identity(self):
        # Change the original pin immediately before the real helper is called.
        # Verification must still use its captured pin; the next call must then
        # observe the changed original and reject.
        original_run = subprocess.run
        changed = False

        def change_pin(argv, *args, **kwargs):
            nonlocal changed
            if "trust-store-verify" in argv and not changed:
                self.pin.write_text(pem(self.rogue))
                changed = True
            return original_run(argv, *args, **kwargs)

        with patch.object(subprocess, "run", side_effect=change_pin):
            ok, message = self.verify("python")
        self.assertTrue(changed)
        self.assertTrue(ok, message)
        self.assertFalse(self.verify("python")[0])

    def test_verification_does_not_depend_on_yq_flavor_or_parser_success(self):
        tools = self.root / "bin"
        tools.mkdir()
        yq = tools / "yq"
        yq.write_text("#!/bin/sh\nexit 7\n")
        yq.chmod(0o755)
        os.environ["PATH"] = str(tools) + os.pathsep + os.environ["PATH"]
        self.both(True)
        self.write_log(key="rogue")
        self.both(False, strict=False)

    def test_unquoted_timestamp_has_structured_verification_error(self):
        text = self.store.read_text().replace(
            "'2020-01-01T00:00:00Z'", "2020-01-01T00:00:00Z"
        )
        self.store.write_text(text)
        proc = subprocess.run(
            ["python3", str(REPO / ".claude/scripts/lib/audit-signing-helper.py"),
             "trust-store-verify", "--trust-store", str(self.store),
             "--pinned-pubkey", str(self.pin)],
            text=True, capture_output=True,
        )
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("QUOTE all timestamps", proc.stderr)
        self.assertNotIn("Traceback", proc.stderr)

    def test_verified_store_miss_cannot_use_rogue_local_key(self):
        self.write_log(key="rogue")
        for strict in (False, True):
            self.both(False, strict=strict, diagnostic="cannot resolve public key")

    def test_verified_bytes_cannot_drift_before_key_or_cutoff_reads(self):
        # A real executable schedules file replacement around the real crypto
        # helper: authenticate the legitimate file, then leave forged policy at
        # the path for the reader. No verifier result or key is mocked.
        trusted = self.root / "trusted.yaml"
        forged = self.root / "forged.yaml"
        trusted.write_bytes(self.store.read_bytes())
        tools = self.root / "bin"
        tools.mkdir()
        wrapper = tools / "python3"
        wrapper.write_text("""#!/bin/bash
if [[ "$*" == *trust-store-verify* ]]; then
    cp "$RACE_TRUSTED" "$LOA_TRUST_STORE_FILE"
    "$RACE_PYTHON" "$@"
    rc=$?
    cp "$RACE_FORGED" "$LOA_TRUST_STORE_FILE"
    exit "$rc"
fi
exec "$RACE_PYTHON" "$@"
""")
        wrapper.chmod(0o755)
        os.environ.update(
            RACE_TRUSTED=str(trusted), RACE_FORGED=str(forged),
            RACE_PYTHON=sys.executable,
            PATH=str(tools) + os.pathsep + os.environ["PATH"],
        )
        for attack in ("writer", "cutoff"):
            doc = yaml.safe_load(trusted.read_text())
            if attack == "writer":
                doc["keys"].append({"writer_id": "rogue", "pubkey_pem": pem(self.rogue)})
                self.write_log(key="rogue")
            else:
                doc["trust_cutoff"]["default_strict_after"] = "2025-01-01T00:00:00Z"
                self.write_log(key=None)
            forged.write_text(yaml.safe_dump(doc))
            self.store.write_bytes(forged.read_bytes())
            audit._TRUST_STORE_CACHE.update(path=None, key=None, status=None)
            with self.subTest(attack=attack):
                self.both(False, diagnostic="TRUST-STORE-INVALID")

    def test_local_key_cannot_replace_registered_writer(self):
        (self.keys / "writer.pub").write_text(pem(self.rogue))
        self.write_log(key="rogue")
        entry = json.loads(self.log.read_text())
        entry["signing_key_id"] = "writer"
        self.log.write_text(json.dumps(entry) + "\n")
        self.both(False, strict=False, diagnostic="signature verification")

    def test_revocation_boundary_and_fractional_timestamp(self):
        self.sign_store(revocations=[{
            "writer_id": "writer", "pubkey_pem": pem(self.writer),
            "revoked_at": "2024-01-01T00:00:00Z",
        }])
        for ts, expected in (
            ("2023-12-31T23:59:59.999999Z", True),
            ("2024-01-01T00:00:00Z", False),
            ("2024-01-01T00:00:00.000000Z", False),
            ("2024-01-01T00:00:01Z", False),
        ):
            self.write_log(ts=ts)
            with self.subTest(timestamp=ts):
                self.both(expected, strict=False)

    def test_strict_ignores_signature_disable_for_forged_and_stripped_entries(self):
        os.environ["LOA_AUDIT_VERIFY_SIGS"] = "0"
        for key in (None, "rogue"):
            self.write_log(key=key)
            self.both(False)

    def test_strict_env_also_forces_verification(self):
        os.environ["LOA_AUDIT_STRICT_VERIFY"] = "1"
        os.environ["LOA_AUDIT_VERIFY_SIGS"] = "0"
        self.write_log(key=None)
        self.both(False, strict=False)

    def test_strict_requires_nonempty_valid_effective_cutoff(self):
        for cutoff in (None, "", "not-a-date", "2999-01-01T00:00:00Z"):
            self.sign_store(cutoff=cutoff)
            self.write_log(key=None)
            with self.subTest(cutoff=cutoff):
                self.both(False, diagnostic="TRUST-CUTOFF-INVALID")

    def test_unsigned_at_fractional_cutoff_is_not_grandfathered(self):
        self.sign_store(cutoff="2024-01-01T00:00:00Z")
        self.write_log(key=None, ts="2024-01-01T00:00:00.000000Z")
        self.both(False, diagnostic="STRIP-ATTACK-DETECTED")

    def test_strict_rejects_missing_or_invalid_entry_timestamp(self):
        for ts in ("", "not-a-date", None):
            self.write_log(key=None, ts=ts)
            self.both(False)

    def test_pre_cutoff_unsigned_history_remains_valid(self):
        self.write_log(key=None, ts="2019-12-31T23:59:59Z")
        self.both(True)

    def test_multiple_signed_entries_detect_payload_and_chain_rewrites(self):
        first = json.loads(self.log.read_text())
        second = dict(first, prev_hash=audit._sha256_hex(audit._chain_input_bytes(first)))
        second["signature"] = base64.b64encode(
            self.writer.sign(audit._chain_input_bytes(second))
        ).decode()
        self.log.write_text(json.dumps(first) + "\n" + json.dumps(second) + "\n")
        self.both(True)
        first["payload"] = {"forged": True}
        self.log.write_text(json.dumps(first) + "\n" + json.dumps(second) + "\n")
        self.both(False, diagnostic="signature verification")
        first["signature"] = base64.b64encode(
            self.writer.sign(audit._chain_input_bytes(first))
        ).decode()
        self.log.write_text(json.dumps(first) + "\n" + json.dumps(second) + "\n")
        self.both(False, diagnostic="prev_hash mismatch")

    def test_missing_store_strict_fails_closed_even_for_unsigned_history(self):
        self.store.unlink()
        self.write_log(key=None, ts="2019-12-31T23:59:59Z")
        self.both(False, diagnostic="TRUST-STORE")

    def test_missing_store_with_signed_history_never_uses_local_key(self):
        self.store.unlink()
        self.both(False, strict=False, diagnostic="TRUST-STORE")

    def test_replacing_store_with_bootstrap_cannot_authorize_signed_history(self):
        self.store.write_text("keys: []\nrevocations: []\nroot_signature: {}\n")
        self.write_log(key="rogue")
        for toggle in ("0", "1"):
            os.environ["LOA_AUDIT_VERIFY_SIGS"] = toggle
            self.both(False, strict=False, diagnostic="TRUST-STORE")

    def test_malformed_store_is_invalid_even_outside_strict_mode(self):
        self.store.write_text("keys: [\n")
        self.both(False, strict=False, diagnostic="TRUST-STORE-INVALID")

    def test_unreadable_store_fails_closed(self):
        self.store.chmod(0)
        self.addCleanup(self.store.chmod, 0o600)
        if os.access(self.store, os.R_OK):
            self.skipTest("requires an unprivileged user to exercise mode-000 denial")
        self.both(False, diagnostic="TRUST-STORE")

    def test_bootstrap_unsigned_install_writes_still_work(self):
        self.store.write_text("keys: []\nrevocations: []\nroot_signature: {}\n")
        audit.audit_emit("L1", "test.event", {}, self.root / "install.jsonl")
        self.both(False, diagnostic="TRUST-STORE-BOOTSTRAP-PENDING")

    def test_trust_root_tampering_is_detected(self):
        doc = yaml.safe_load(self.store.read_text())
        doc["keys"].append({"writer_id": "rogue", "pubkey_pem": pem(self.rogue)})
        self.store.write_text(yaml.safe_dump(doc))
        self.write_log(key="rogue")
        self.both(False, strict=False, diagnostic="TRUST-STORE-INVALID")

    def test_require_signed_live_rollup_cannot_be_disabled(self):
        os.environ["LOA_AUDIT_VERIFY_SIGS"] = "0"
        self.write_log(key=None)
        for flags in ([], ["--no-chain-verify"]):
            proc = subprocess.run(
                ["bash", str(REPO / "tools/modelinv-rollup.sh"), "--require-signed",
                 "--input", str(self.log), "--output-json", str(self.root / "out.json"),
                 *flags],
                text=True, capture_output=True,
            )
            with self.subTest(flags=flags):
                self.assertNotEqual(proc.returncode, 0, proc.stdout + proc.stderr)
                self.assertFalse((self.root / "out.json").exists())

    def test_require_signed_live_rollup_accepts_rooted_chain(self):
        output = self.root / "rollup.json"
        proc = subprocess.run(
            ["bash", str(REPO / "tools/modelinv-rollup.sh"), "--require-signed",
             "--input", str(self.log), "--output-json", str(output)],
            text=True, capture_output=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertTrue(output.is_file())


if __name__ == "__main__":
    unittest.main(verbosity=2)
