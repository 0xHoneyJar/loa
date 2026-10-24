"""synth.power_mini_diffs: the power-mini head.diff fixtures generated at test time (bd-qxwrm; Bridgebuilder PR #1289
r1 F-007; cycle-133 sdd.md C-7).

The four head.diff files used to be committed (4,976 lines, 4.5 K of them in pr-93/pr-94) under a single
'@@ -1,1 +1,1 @@' header that contradicts their bodies. The generator rebuilds them; these assertions pin the
removed files by sha256 so the byte-identity proof stays after the removal:
  - headers="legacy" reproduces every committed file byte for byte (the full-file digest of the removed blob);
  - the default (correct headers) keeps every body line byte-identical and declares '@@ -1,N +1,N @@';
  - `git apply --check` accepts each generated diff against the generated base file;
  - power.diff_lines (the only consumer) counts the same lines either way.
The seed is recorded here and in the CLI invocation; the bodies are a fixed sequence and do not draw from it."""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

import _path
import synth
from c132 import power

SEED = 20261023
# pr -> (removed/added pairs, sha256 of the committed head.diff, sha256 of its body after the 4 header lines)
COMMITTED = {
    "pr-91": (30, "eeb6ef833af50dddc2a0d1ab377bcb7926d35679f17e180c5decf09575f829ec",
              "ddf96a3deb0f4bc1e7008103dd0815e0ee908ad1f9c4747e30bb59303dd55e7a"),
    "pr-92": (200, "451fb59b547a628d81a516af11ddfef63c435bfd04141339b2a388f718ed079f",
              "6a0c7317d1497e3880e8d781740a58a0a92a9e4514c1a22e377018378a218d87"),
    "pr-93": (750, "e856ce8a937c13888e06c6446dea17e6cf9d97f5b7a496112be845369c7bb725",
              "be8561abb6042369ed6be60ee9cb2ecd9230cd4f3c8fe2a11380111c93527565"),
    "pr-94": (1500, "1ac8b4ad7414e1dbf7c2bef12927a01a9c4f61fb2a3916d6622997be00bf46be",
              "2235ade2b16e252cae0a35b60480caff45b04ee5fa85878c6aeacf353da1021f"),
}


def _read(p):
    with open(p, "rb") as f:
        return f.read()


def _sha(b):
    return hashlib.sha256(b).hexdigest()


def _body(b):
    return b.split(b"\n", 4)[4]


class PowerMiniDiffsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="c132-synth-")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_legacy_headers_reproduce_the_committed_files_byte_for_byte(self):
        synth.power_mini_diffs(self.tmp, seed=SEED, headers="legacy")
        for pr, (_n, full, _body_sha) in sorted(COMMITTED.items()):
            self.assertEqual(_sha(_read(os.path.join(self.tmp, pr, "head.diff"))), full, pr)

    def test_correct_headers_keep_every_body_line_and_declare_the_counts(self):
        synth.power_mini_diffs(self.tmp, seed=SEED)
        for pr, (n, _full, body_sha) in sorted(COMMITTED.items()):
            b = _read(os.path.join(self.tmp, pr, "head.diff"))
            self.assertEqual(_sha(_body(b)), body_sha, pr)
            self.assertEqual(b.split(b"\n")[3], b"@@ -1,%d +1,%d @@" % (n, n), pr)
            self.assertEqual(power.diff_lines(os.path.join(self.tmp, pr, "head.diff")), 2 * n)

    @unittest.skipUnless(shutil.which("git"), "needs git")
    def test_git_apply_check_accepts_the_generated_diffs(self):
        synth.power_mini_diffs(self.tmp, seed=SEED)
        for pr in sorted(COMMITTED):
            d = os.path.join(self.tmp, pr)
            self.assertTrue(os.path.isfile(os.path.join(d, "base", "x.sh")), pr)
            p = subprocess.run(["git", "apply", "--check", os.path.join(d, "head.diff")],
                               cwd=os.path.join(d, "base"), capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, "%s: %s" % (pr, p.stderr))

    def test_the_legacy_header_is_what_git_apply_rejects(self):
        """the defect itself: the committed header declares one line over N-line hunks"""
        if not shutil.which("git"):
            self.skipTest("needs git")
        synth.power_mini_diffs(self.tmp, seed=SEED, headers="legacy")
        d = os.path.join(self.tmp, "pr-93")
        p = subprocess.run(["git", "apply", "--check", os.path.join(d, "head.diff")], cwd=os.path.join(d, "base"),
                           capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)

    def test_deterministic_and_cli(self):
        a, b = os.path.join(self.tmp, "a"), os.path.join(self.tmp, "b")
        synth.power_mini_diffs(a, seed=SEED)
        p = subprocess.run([sys.executable, "-I", os.path.join(os.path.dirname(os.path.abspath(__file__)), "synth.py"),
                            "power-mini-diffs", "--seed", str(SEED), "--out", b], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        for pr in sorted(COMMITTED):
            self.assertEqual(_read(os.path.join(a, pr, "head.diff")), _read(os.path.join(b, pr, "head.diff")))
        self.assertEqual(subprocess.run([sys.executable, "-I", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                                           "synth.py")], capture_output=True).returncode, 2)


if __name__ == "__main__":
    unittest.main()
