"""#1047: reproduce effective writes with harmless bytes in disposable fixtures.

These are accepted-limit pins, not security guarantees. If an enforcement layer
later closes a class, intentionally change its expectation and the runbook.
"""

import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
HOOK = ROOT / ".claude/hooks/safety/block-destructive-bash.sh"


class FenceLimitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="loa-fence-limit-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.target = self.root / ".run/cron.d/probe.sh"
        self.target.parent.mkdir(parents=True)
        self.env = dict(os.environ, LOA_REPO_ROOT=str(self.root),
                        LOA_ZONE_GUARD_AUTH_FILE="/dev/null")
        self.env.pop("LOA_ALLOW_STATE_ZONE_EXEC_WRITE", None)

    def decision(self, command):
        return subprocess.run(
            ["bash", str(HOOK)], cwd=self.root, text=True, capture_output=True,
            input=json.dumps({"tool_input": {"command": command}}), env=self.env,
        )

    def check_effective_write(self, command):
        result = self.decision(command)
        self.assertEqual(result.returncode, 0, result.stderr)
        # Commands in this suite only write the literal bytes "safe" here.
        subprocess.run(["bash", "-c", command], cwd=self.root, env=self.env,
                       check=True, capture_output=True)
        self.assertEqual(self.target.read_bytes(), b"safe")

    def test_direct_protected_redirect_is_blocked_positive_control(self):
        result = self.decision("printf safe > .run/cron.d/probe.sh")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("FR-SZ-REDIR", result.stderr)
        self.assertFalse(self.target.exists())

    def test_quoted_concatenation_changes_effective_path(self):
        self.check_effective_write('printf safe > .r""un/cron.d/probe.sh')

    def test_line_continuation_changes_effective_path(self):
        self.check_effective_write("printf safe > .r\\\nun/cron.d/probe.sh")

    def test_archive_member_is_not_visible_in_command(self):
        with tarfile.open(self.root / "fixture.tar", "w") as archive:
            member = tarfile.TarInfo(".run/cron.d/probe.sh")
            member.size = 4
            archive.addfile(member, io.BytesIO(b"safe"))
        self.check_effective_write("tar -xf fixture.tar")

    def test_interpreter_computes_effective_path(self):
        self.check_effective_write(
            "python3 -c \"from pathlib import Path; "
            "Path('.r' + 'un/cron.d/probe.sh').write_bytes(b'safe')\"")

    def test_ordinary_bash_overwrite_has_no_read_history_precondition(self):
        # #1031: an ordinary State Zone file is not a lifecycle path. This
        # fence does not know whether a Read tool event preceded the write.
        self.target = self.root / "grimoires/loa/NOTES.md"
        self.target.parent.mkdir(parents=True)
        self.target.write_bytes(b"old")
        self.check_effective_write("printf safe > grimoires/loa/NOTES.md")


if __name__ == "__main__":
    unittest.main()
