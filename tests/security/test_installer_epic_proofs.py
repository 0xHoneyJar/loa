"""#1168: narrow behavioral proofs for already-fixed installer mechanisms.

No installation or downloads. LOA_EPIC_SOURCE_ROOT can point at an archived HEAD
to distinguish existing fixes from concurrent installer work.
"""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

REPO = Path(os.environ.get("LOA_EPIC_SOURCE_ROOT", Path(__file__).resolve().parents[2]))


class InstallerEpicProofs(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.scripts = REPO / ".claude/scripts"

    def test_script_entrypoints_reject_missing_operands(self):
        for script, flags in (
            ("mount-loa.sh", ("--branch", "--tag", "--ref", "--constructs-pack")),
            ("mount-submodule.sh", ("--branch", "--tag", "--ref")),
        ):
            for flag in flags:
                for tail in ([], ["--force"]):
                    with self.subTest(script=script, flag=flag, tail=tail):
                        proc = subprocess.run(
                            ["bash", str(self.scripts / script), flag, *tail],
                            cwd=self.root, text=True, capture_output=True,
                        )
                        self.assertNotEqual(proc.returncode, 0)
                        self.assertIn("requires a value", proc.stderr)
                        self.assertNotIn("unbound variable", proc.stderr)

    def test_pipe_ref_traversal_is_rejected_before_download(self):
        tools = self.root / "bin"
        tools.mkdir()
        curl = tools / "curl"
        curl.write_text('#!/bin/sh\nprintf called > "$PROBE_CURL_CALLED"\nexit 1\n')
        curl.chmod(0o755)
        marker = self.root / "curl-called"
        env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                   PROBE_CURL_CALLED=str(marker), TMPDIR=str(self.root))
        env.pop("_LOA_MOUNT_REEXEC", None)
        source = (self.scripts / "mount-loa.sh").read_text()
        for ref in ("../attacker/main", "main?query", "main#fragment"):
            with self.subTest(ref=ref):
                proc = subprocess.run(
                    ["bash", "-s", "--", "--ref", ref], input=source,
                    cwd=self.root, env=env, text=True, capture_output=True,
                )
                self.assertNotEqual(proc.returncode, 0)
                self.assertRegex(proc.stderr, r"invalid ref|path traversal blocked")
                self.assertFalse(marker.exists())

    def test_output_helpers_preserve_operator_backslashes(self):
        message = r"-n literal\nline\tcolumn\cend"
        for script in ("mount-loa.sh", "mount-submodule.sh"):
            source = (self.scripts / script).read_text()
            function = re.search(r"^log\(\).*$", source, re.M).group()
            proc = subprocess.run(
                ["bash", "-c", 'GREEN=""; NC=""; ' + function + '\nlog "$1"',
                 "_", message],
                text=True, capture_output=True,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertTrue(proc.stdout.endswith(message + "\n"))
            self.assertEqual(proc.stdout.count("\n"), 1)

    def test_actual_symlink_validator_rejects_sibling_prefix_and_symlink_escape(self):
        source = (self.scripts / "mount-submodule.sh").read_text()
        function = re.search(
            r"^validate_symlink_target\(\) \{.*?^\}", source, re.M | re.S
        ).group()
        repo = self.root / "repo"
        outside = self.root / "repo-evil"
        repo.mkdir()
        outside.mkdir()
        (repo / "inside").mkdir()
        (repo / "escape").symlink_to(outside, target_is_directory=True)
        harness = (
            'get_repo_root() { printf "%s" "$EPIC_REPO"; }\n'
            'warn() { printf "%s\\n" "$*" >&2; }\n'
            'err() { printf "%s\\n" "$*" >&2; exit 1; }\n'
        )
        for target, expected in ((repo / "inside", 0), (outside, 1), (repo / "escape", 1)):
            proc = subprocess.run(
                ["bash", "-c", harness + function + '\nvalidate_symlink_target "$1"',
                 "_", str(target)],
                cwd=repo, env=dict(os.environ, EPIC_REPO=str(repo)),
                text=True, capture_output=True,
            )
            with self.subTest(target=target):
                self.assertEqual(proc.returncode, expected, proc.stderr)
                if expected:
                    self.assertIn("escapes repository bounds", proc.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
