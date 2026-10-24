"""The cycle-132 lead-side drivers final.sh and run-judge-defects.sh (cycle-133 sdd.md C-7; beads bd-o3a5h, bd-xr3uq;
Sprint 271 audit SEC-004).

final.sh takes REG / PIN / REG_SHA as flags or parses registration.txt by whitelist (never `source`); both drivers
derive the repository root from BASH_SOURCE, so they run from any cwd with no cache file. run-judge-defects.sh keys
its chunk directory by the key's sha256, refuses packets that do not carry the key's sample_id, stamps the sample_id
into every session's labels.json and reruns a session whose labels belong to another sample.
Each case copies the real script into a throwaway repository; reads-c132.py and blind-session.sh are stubs."""
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest

import _path
from c132 import judge_defects as jd

REPO = os.path.dirname(os.path.dirname(_path.ANALYSIS_DIR))
SCRIPTS = "grimoires/loa/reports/review-catch-c132/scripts"
SUITE = "grimoires/loa/evals/ablation-2.0-c132"
JDIR = "grimoires/loa/reports/ablation-2.0/c132-judge-defects"
PIN = "f" * 40

READS = r'''import os, sys
a = sys.argv[1:]
with open(os.environ["STUB_LOG"], "a") as f:
    f.write("reads %s\n" % " ".join(a))
out = a[a.index("--out") + 1]
os.makedirs(out, exist_ok=True)
if "--name" in a:
    open(os.path.join(out, a[a.index("--name") + 1] + ".md"), "w").write("# stub\n")
'''
BLIND = r'''#!/usr/bin/env bash
set -euo pipefail
out=""; packets=""; prompt=""
while (( $# )); do case "$1" in --out) out="$2"; shift 2;; --packets) packets="$2"; shift 2;; --prompt) prompt="$2"; shift 2;; *) shift;; esac; done
echo "blind packets=$packets prompt=$prompt" >> "$STUB_LOG"
mkdir -p "$out"
python3 -I -c 'import json, os, sys
d = sys.argv[1]
print(json.dumps({n[:-3]: {"verdict": "describes", "note": ""} for n in sorted(os.listdir(d)) if n.endswith(".md")}))' "$packets" > "$out/labels.json"
'''


def _w(p, text, mode=None):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(text)
    if mode:
        os.chmod(p, mode)


def _sha(p):
    with open(p, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


class DriverBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="c132-drv-")
        self.repo = os.path.join(self.tmp, "repo")
        self.home = os.path.join(self.tmp, "home")      # no ~/.cache/loa/cycle-132 in it
        os.makedirs(self.home)
        self.log = os.path.join(self.tmp, "stub.log")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def script(self, name):
        dst = os.path.join(self.repo, SCRIPTS, name)
        _w(dst, open(os.path.join(REPO, SCRIPTS, name)).read(), 0o755)
        return dst

    def run_script(self, argv, cwd="/"):
        env = dict(os.environ, HOME=self.home, STUB_LOG=self.log)
        return subprocess.run(["bash"] + argv, capture_output=True, text=True, env=env, cwd=cwd)

    def stub_log(self):
        return open(self.log).read() if os.path.exists(self.log) else ""


@unittest.skipUnless(shutil.which("bash") and shutil.which("jq"), "needs bash and jq")
class FinalShTest(DriverBase):
    def setUp(self):
        super().setUp()
        self.final = self.script("final.sh")
        _w(os.path.join(self.repo, "evals/analysis/c132/reads-c132.py"), READS)
        self.reg = os.path.join(self.repo, SUITE, "REGISTRATION-15.json")
        _w(self.reg, '{"pin": "x"}\n')
        self.reg_sha = _sha(self.reg)
        _w(os.path.join(self.repo, "evals/results/ablation-2.0/runs.jsonl"),
           json.dumps({"batch": "c132-g1-a1", "run_id": "r"}) + "\n" + json.dumps({"batch": "c132-smoke", "run_id": "s"}) + "\n")

    def flags(self):
        return ["--reg", "REGISTRATION-15.json", "--pin", PIN, "--reg-sha", self.reg_sha]

    def test_flags_from_another_cwd_without_the_cache_file(self):
        p = self.run_script([self.final, "placebo"] + self.flags())
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        log = self.stub_log()
        self.assertIn("--pin %s" % PIN, log)
        self.assertIn("--registration %s/REGISTRATION-15.json" % SUITE, log)
        rows = open(os.path.join(self.repo, "grimoires/loa/reports/ablation-2.0/c132-final/rows.jsonl")).read()
        self.assertIn("c132-g1-a1", rows)
        self.assertNotIn("c132-smoke", rows)

    def test_the_default_registration_file_is_parsed_by_whitelist(self):
        _w(os.path.join(self.home, ".cache/loa/cycle-132/registration.txt"),
           "REG_SHA=%s PIN=%s REG=REGISTRATION-15.json\n" % (self.reg_sha, PIN))
        p = self.run_script([self.final, "placebo"])
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("--pin %s" % PIN, self.stub_log())

    def test_shell_code_in_the_registration_file_is_refused_and_never_run(self):
        pwned = os.path.join(self.tmp, "pwned")
        for text in ("REG_SHA=%s PIN=%s REG=$(touch %s)\n" % (self.reg_sha, PIN, pwned),
                     "REG_SHA=%s PIN=%s;touch %s REG=REGISTRATION-15.json\n" % (self.reg_sha, PIN, pwned),
                     "REG_SHA=%s PIN=%s REG=REGISTRATION-15.json\ntouch %s\n" % (self.reg_sha, PIN, pwned),
                     "REG_SHA=%s PIN=%s REG=../../etc/passwd\n" % (self.reg_sha, PIN),
                     "REG_SHA=%s PIN=%s REG=REGISTRATION-15.json FOO=1\n" % (self.reg_sha, PIN)):
            f = os.path.join(self.tmp, "reg.txt")
            _w(f, text)
            p = self.run_script([self.final, "placebo", "--registration-file", f])
            self.assertEqual(p.returncode, 2, text + p.stderr)
            self.assertIn("registration", p.stderr)
            self.assertFalse(os.path.exists(pwned), text)
            self.assertNotIn("reads", self.stub_log(), "refused before any step")

    def test_a_registration_sha_mismatch_is_refused(self):
        p = self.run_script([self.final, "placebo", "--reg", "REGISTRATION-15.json", "--pin", PIN, "--reg-sha", "0" * 64])
        self.assertEqual(p.returncode, 2)
        self.assertIn("sha256", p.stderr)

    def test_missing_values_and_usage_are_exit_2(self):
        self.assertEqual(self.run_script([self.final, "placebo"]).returncode, 2)          # no flags, no cache file
        self.assertEqual(self.run_script([self.final, "bogus"] + self.flags()).returncode, 2)
        self.assertEqual(self.run_script([self.final]).returncode, 2)


@unittest.skipUnless(shutil.which("bash") and shutil.which("jq"), "needs bash and jq")
class RunJudgeDefectsTest(DriverBase):
    def setUp(self):
        super().setUp()
        self.drv = self.script("run-judge-defects.sh")
        _w(os.path.join(self.repo, SCRIPTS, "prompts/judge.md"), "# judge prompt\n")
        _w(os.path.join(self.repo, "evals/harness/blind-session.sh"), BLIND, 0o755)
        self.jdir = os.path.join(self.repo, JDIR)
        self.key = jd.with_sample_id({"schema_version": 1, "seed": 1, "items": {"D0001": {}, "D0002": {}}})
        self.sid = self.key["sample_id"]
        _w(os.path.join(self.jdir, "key.json"), jd.key_text(self.key))
        for i in ("D0001", "D0002"):
            _w(os.path.join(self.jdir, "packets", i + ".md"), jd.stamp_packet("# Judge item %s\n\nbody\n" % i, self.sid))
        self.cache = os.path.join(self.tmp, "cache")

    def run_drv(self, *extra):
        return self.run_script([self.drv, "--cache", self.cache] + list(extra))

    def labels(self, c="c01"):
        with open(os.path.join(self.jdir, "sessions", c, "labels.json")) as f:
            return json.load(f)

    def test_from_another_cwd_chunks_keyed_by_the_key_sha_and_labels_stamped(self):
        p = self.run_drv()
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        ksha = _sha(os.path.join(self.jdir, "key.json"))
        chunks = os.path.join(self.cache, "judge-defects", "chunks-" + ksha[:16])
        self.assertEqual(open(os.path.join(chunks, "KEY_SHA256")).read().strip(), ksha)
        self.assertEqual(sorted(os.listdir(os.path.join(chunks, "c01"))), ["D0001.md", "D0002.md"])
        lab = self.labels()
        self.assertEqual(lab["sample_id"], self.sid)
        self.assertEqual(sorted(k for k in lab if k != "sample_id"), ["D0001", "D0002"])
        self.assertIn("prompt=%s" % os.path.join(self.repo, SCRIPTS, "prompts/judge.md"), self.stub_log())
        self.assertEqual(self.stub_log().count("blind "), 1, "pass 2 skips a session already labelled for this sample")

    def test_stale_labels_from_another_sample_are_moved_aside_and_rerun(self):
        _w(os.path.join(self.jdir, "sessions/c01/labels.json"), json.dumps({"D0001": {"verdict": "describes"},
                                                                            "sample_id": "0123456789ab"}))
        p = self.run_drv()
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.labels()["sample_id"], self.sid)
        self.assertTrue(any(n.startswith("c01.failed-") for n in os.listdir(os.path.join(self.jdir, "sessions"))))

    def test_packets_without_the_key_sample_id_are_refused(self):
        _w(os.path.join(self.jdir, "packets", "D0002.md"), jd.stamp_packet("# Judge item D0002\n\nbody\n", "0123456789ab"))
        p = self.run_drv()
        self.assertEqual(p.returncode, 2)
        self.assertIn("D0002.md", p.stderr)
        self.assertNotIn("blind", self.stub_log())

    def test_a_key_without_a_sample_id_is_refused(self):
        _w(os.path.join(self.jdir, "key.json"), json.dumps({"items": {}}))
        self.assertEqual(self.run_drv().returncode, 2)

    def test_a_chunk_dir_for_another_key_is_refused(self):
        ksha = _sha(os.path.join(self.jdir, "key.json"))
        _w(os.path.join(self.cache, "judge-defects", "chunks-" + ksha[:16], "KEY_SHA256"), "0" * 64 + "\n")
        p = self.run_drv()
        self.assertEqual(p.returncode, 2)
        self.assertIn("KEY_SHA256", p.stderr)


if __name__ == "__main__":
    unittest.main()
