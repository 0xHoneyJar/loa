"""Bind consumer output to verified bytes; no keys or signature claims here.

The real consumer scripts run in a disposable layout. A verifier seam records
the bytes it accepts, then an independent writer replaces/appends the original
source before returning. Existing trust tests cover real authentication.
"""

import gzip
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
ROLLUP = "tools/modelinv-rollup.sh"
ARCHIVER = ".claude/scripts/audit/audit-snapshot.sh"

VERIFIER = r"""
import json, os, stat, subprocess, sys
from pathlib import Path
p = Path(sys.argv[-1])
data = p.read_bytes()
Path(os.environ["AUDIT_TEST_VERIFIED"]).write_bytes(data)
Path(os.environ["AUDIT_TEST_RECORD"]).write_text(json.dumps({
    "path": str(p), "args": sys.argv[1:],
    "mode": stat.S_IMODE(p.stat().st_mode),
    "parent_mode": stat.S_IMODE(p.parent.stat().st_mode),
}))
mode = os.environ.get("AUDIT_TEST_MUTATION", "none")
if mode != "none":
    # Independent writer, synchronized after the verifier's read; no sleeps.
    subprocess.run([sys.executable, "-c", '''
import os, sys
from pathlib import Path
source, replacement = map(Path, sys.argv[1:3])
mode = sys.argv[3]
if mode == "replace":
    os.replace(replacement, source)
elif mode == "append":
    with source.open("ab") as f:
        f.write(replacement.read_bytes())
elif mode == "delete":
    source.unlink()
''', os.environ["AUDIT_TEST_SOURCE"], os.environ["AUDIT_TEST_REPLACEMENT"], mode],
        check=True)
sys.exit(int(os.environ.get("AUDIT_TEST_VERIFY_EXIT", "0")))
"""


def envelope(model="verified-model", cost=10, writer="1.2", hour="10"):
    payload = {
        "writer_version": writer, "final_model_id": model,
        "calling_primitive": "verified-skill", "cost_micro_usd": cost,
        "invocation_chain": ["verified-skill"],
        "pricing_snapshot": {"input_per_mtok": 1000000},
    }
    if writer is None:
        del payload["writer_version"]
    return (json.dumps({
        "schema_version": "1.1.0", "primitive_id": "MODELINV",
        "event_type": "model.invoke.complete", "prev_hash": "GENESIS",
        "ts_utc": f"2026-09-14T{hour}:00:00Z", "payload": payload,
    }) + "\n").encode()


class ConsumerSnapshots(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="loa-consumer-snapshots-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "consumer repo"
        for rel in (ROLLUP, ARCHIVER):
            target = self.root / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / rel, target)
        self.logs = self.root / "logs"
        self.logs.mkdir()
        self.scratch = self.root / "private scratch"
        self.scratch.mkdir()
        self.archive = self.root / "archive"
        self.source = self.logs / "events.jsonl"
        self.original = envelope()
        self.source.write_bytes(self.original)
        self.source.chmod(0o666)  # Capturing must not inherit public source mode.
        self.replacement = self.logs / "replacement.jsonl"
        self.replacement.write_bytes(envelope("unverified-model", 999))
        self.verified = self.root / "verified.jsonl"
        self.record = self.root / "verification.json"
        self.json_output = self.root / "report.json"
        self.md_output = self.root / "report.md"
        self.policy = self.root / "policy.json"
        self.policy.write_text(json.dumps({"primitives": {"L2": {
            "chain_critical": True, "git_tracked": False,
            "log_basename": self.source.name,
        }}}))
        self.probe = self.root / "verifier.py"
        self.probe.write_text(VERIFIER)
        (self.root / ".claude/scripts/audit-envelope.sh").write_text(
            'audit_verify_chain() {\n'
            '  "$AUDIT_TEST_PYTHON" "$AUDIT_TEST_PROBE" "$@"\n'
            '}\n'
        )
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith(("LOA_AUDIT_", "LOA_PINNED_ROOT_"))
                    and k != "BASH_ENV"}
        self.env.update({
            "PATH": f"{self.bin}:/usr/local/bin:/usr/bin:/bin",
            "TMPDIR": str(self.scratch),
            "AUDIT_TEST_PYTHON": sys.executable,
            "AUDIT_TEST_PROBE": str(self.probe),
            "AUDIT_TEST_RECORD": str(self.record),
            "AUDIT_TEST_VERIFIED": str(self.verified),
            "AUDIT_TEST_SOURCE": str(self.source),
            "AUDIT_TEST_REPLACEMENT": str(self.replacement),
            "LOA_AUDIT_SNAPSHOT_TEST_DAY": "2026-09-14",
        })

    def run_consumer(self, consumer, mutation="none", args=()):
        env = dict(self.env, AUDIT_TEST_MUTATION=mutation)
        if consumer == ROLLUP:
            options = ["--require-signed", "--input", str(self.source),
                       "--output-json", str(self.json_output),
                       "--output-md", str(self.md_output),
                       "--per-skill-daily-quota", "100"]
        else:
            options = ["--policy", str(self.policy), "--logs-dir", str(self.logs),
                       "--archive-dir", str(self.archive)]
        return subprocess.run(
            ["bash", str(self.root / consumer), *options, *args],
            cwd=self.root, env=env, text=True, capture_output=True, timeout=15,
        )

    def assert_private_and_cleaned(self):
        record = json.loads(self.record.read_text())
        path = Path(record["path"])
        self.assertNotEqual(path, self.source)
        self.assertEqual(record["mode"], 0o400)
        self.assertEqual(record["parent_mode"], 0o700)
        self.assertEqual(self.verified.read_bytes(), self.original)
        self.assertFalse(path.exists(), "private input survived consumer exit")
        self.assertEqual(list(self.scratch.iterdir()), [])
        return record

    def assert_no_output(self):
        self.assertFalse(self.json_output.exists())
        self.assertFalse(self.md_output.exists())
        self.assertFalse(self.archive.exists() and any(self.archive.iterdir()))

    def test_rollup_replacement_cannot_change_aggregation_or_quota(self):
        result = self.run_consumer(ROLLUP, "replace")
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(self.json_output.read_text())
        self.assertEqual(report["total_envelopes"], 1)
        self.assertEqual(report["groups"][0]["group_key"], "verified-model")
        self.assertEqual(report["groups"][0]["total_cost_micro_usd"], 10)
        self.assertNotIn("QUOTA-ALERT", result.stderr)
        self.assertNotIn("unverified-model", self.md_output.read_text())
        self.assertIn(b"unverified-model", self.source.read_bytes())
        self.assertIn("--verify-for-merge", self.assert_private_and_cleaned()["args"])

    def test_rollup_concurrent_append_is_outside_verified_input(self):
        result = self.run_consumer(ROLLUP, "append")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.json_output.read_text())["total_envelopes"], 1)
        self.assertEqual(len(self.source.read_bytes().splitlines()), 2)
        self.assertNotIn("QUOTA-ALERT", result.stderr)
        self.assert_private_and_cleaned()

    def test_rollup_strip_scan_ignores_later_unverified_replacement(self):
        self.replacement.write_bytes(envelope() + envelope(writer=None, hour="11"))
        result = self.run_consumer(ROLLUP, "replace")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.json_output.read_text())["total_envelopes"], 1)
        self.assertNotIn("STRIP-ATTACK", result.stderr)
        self.assert_private_and_cleaned()

    def test_rollup_captured_strip_violation_cannot_be_erased_by_source_swap(self):
        self.original += envelope(writer=None, hour="11")
        self.source.write_bytes(self.original)
        result = self.run_consumer(ROLLUP, "replace", ["--strict-strip"])
        self.assertEqual(result.returncode, 78, result.stderr)
        self.assertIn("STRIP-ATTACK-DETECTED", result.stderr)
        self.assert_no_output()
        self.assert_private_and_cleaned()

    def test_rollup_quota_uses_captured_cost_even_if_source_is_reduced(self):
        self.original = envelope(cost=200)
        self.source.write_bytes(self.original)
        self.replacement.write_bytes(envelope(cost=1))
        result = self.run_consumer(ROLLUP, "replace")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("verified-skill: 200 tokens", result.stderr)
        self.assert_private_and_cleaned()

    def test_archive_replacement_compresses_verified_bytes(self):
        result = self.run_consumer(ARCHIVER, "replace")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(gzip.decompress(next(self.archive.glob("*.gz")).read_bytes()),
                         self.original)
        self.assertIn(b"unverified-model", self.source.read_bytes())
        self.assert_private_and_cleaned()

    def test_archive_concurrent_append_is_not_included(self):
        result = self.run_consumer(ARCHIVER, "append")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(gzip.decompress(next(self.archive.glob("*.gz")).read_bytes()),
                         self.original)
        self.assertEqual(len(self.source.read_bytes().splitlines()), 2)
        self.assert_private_and_cleaned()

    def test_archive_does_not_need_original_after_verification(self):
        result = self.run_consumer(ARCHIVER, "delete")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(gzip.decompress(next(self.archive.glob("*.gz")).read_bytes()),
                         self.original)
        self.assertFalse(self.source.exists())
        self.assert_private_and_cleaned()

    def test_dry_run_verifies_private_bytes_without_archive_output(self):
        result = self.run_consumer(ARCHIVER, "append", ["--dry-run"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("DRY-RUN", result.stderr)
        self.assert_no_output()
        self.assert_private_and_cleaned()

    def test_verification_failure_leaves_no_output_or_private_copy(self):
        self.env["AUDIT_TEST_VERIFY_EXIT"] = "1"
        for consumer in (ROLLUP, ARCHIVER):
            with self.subTest(consumer=consumer):
                result = self.run_consumer(consumer)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assert_no_output()
                self.assert_private_and_cleaned()

    def test_partial_capture_failure_never_reaches_verification(self):
        # Fail the copy producer AFTER emitting a valid prefix; its exit status
        # must prevent treating even a parseable captured prefix as complete.
        cat = self.bin / "cat"
        cat.write_text('#!/bin/bash\n'
                       'for arg in "$@"; do\n'
                       '  if [[ "$arg" == "$AUDIT_TEST_SOURCE" ]]; then\n'
                       '    /bin/cat "$arg"\n'
                       '    exit 23\n'
                       '  fi\n'
                       'done\nexec /bin/cat "$@"\n')
        cat.chmod(0o755)
        for consumer in (ROLLUP, ARCHIVER):
            with self.subTest(consumer=consumer):
                result = self.run_consumer(consumer)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn("capture", result.stderr.lower())
                self.assertFalse(self.record.exists(), "verified a failed capture")
                self.assert_no_output()
                self.assertEqual(list(self.scratch.iterdir()), [])

    def test_private_directory_failure_stops_before_verification(self):
        mktemp = self.bin / "mktemp"
        mktemp.write_text("#!/bin/sh\nexit 23\n")
        mktemp.chmod(0o755)
        for consumer in (ROLLUP, ARCHIVER):
            with self.subTest(consumer=consumer):
                result = self.run_consumer(consumer)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertFalse(self.record.exists())
                self.assert_no_output()
                self.assertEqual(list(self.scratch.iterdir()), [])

    def test_gzip_failure_removes_partial_archive_and_private_copy(self):
        binary = self.bin / "gzip"
        binary.write_text("#!/bin/sh\nprintf partial\nexit 23\n")
        binary.chmod(0o755)
        result = self.run_consumer(ARCHIVER)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("gzip failed", result.stderr)
        self.assert_no_output()
        self.assert_private_and_cleaned()


if __name__ == "__main__":
    unittest.main()
