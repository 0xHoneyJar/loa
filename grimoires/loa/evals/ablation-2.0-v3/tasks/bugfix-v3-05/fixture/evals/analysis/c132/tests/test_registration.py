"""Unit tests for evals/analysis/c132/registration.py (cycle-132 Sprint 269 Task 1.7c; SDD §3.2, D-7.2).

Run: python3 -m unittest discover -s evals/analysis/c132/tests  (or this file directly).
The module is loaded by path, so the tests do not depend on the package's __init__.py. Each case builds a
throwaway git repository holding a suite root copy, the corpus sums, a pre-registration and an analysis
tree; canonicalisation goes through the real lib/jcs.sh (skipped when rfc8785 is not installed)."""
import hashlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
SPEC = importlib.util.spec_from_file_location("registration_c132", os.path.join(HERE, "..", "registration.py"))
reg = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(reg)


def jcs_available():
    p = subprocess.run(["bash", "-c", 'source "$1" && jcs_available', "_", os.path.join(REPO, "lib", "jcs.sh")],
                       capture_output=True)
    return p.returncode == 0


def rb(path):
    with open(path, "rb") as f:
        return f.read()


def git(repo, *args):
    subprocess.run(["git", "-C", repo, "-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false"] + list(args),
                   check=True, capture_output=True)


@unittest.skipUnless(jcs_available(), "lib/jcs.sh needs the rfc8785 package")
class RegistrationTest(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.mkdtemp(prefix="reg-test.")
        self.repo = os.path.join(self.t, "repo")
        os.makedirs(os.path.join(self.repo, "evals", "analysis", "c132"))
        with open(os.path.join(self.repo, "evals", "analysis", "c132", "stats.py"), "w") as f:
            f.write("X = 1\n")
        shutil.copytree(os.path.join(REPO, "grimoires", "loa", "evals", "ablation-2.0"), os.path.join(self.repo, "root"))
        task = os.path.join(self.repo, "root", "tasks", "review-01", "task.yaml")
        subprocess.run(["yq", "-i", ".review_catch.bare_sessions_matched = 3 | .review_catch.bare_sessions_matched_fable = 2", task], check=True)
        shutil.copy(os.path.join(REPO, "evals", "suites", "ablation-2.0.yaml"), os.path.join(self.repo, "suite.yaml"))
        with open(os.path.join(self.repo, "SHA256SUMS"), "w") as f:
            f.write("0" * 64 + "  pr-01/fixture.yaml\n")
        with open(os.path.join(self.repo, "PREREGISTRATION.md"), "w") as f:
            f.write("# Pre-registration\n")
        subprocess.run(["git", "-C", self.repo, "init", "-q"], check=True)
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "init")
        self.out = os.path.join(self.repo, "REGISTRATION.json")

    def tearDown(self):
        shutil.rmtree(self.t, ignore_errors=True)

    def args(self, **over):
        a = {"prereg": "PREREGISTRATION.md", "corpus-sums": "SHA256SUMS", "suite-root": "root",
             "analysis-tree": "HEAD:evals/analysis/c132", "pin": "abcdef1", "suite-file": "suite.yaml",
             "arms": "a1_full,a0_bare_matched,a0_bare_fable_matched", "groups": '[["review-01"]]',
             "looks": "[1]", "boundary-constant": "1.08", "cap-usd": "2500", "seed": "20261021",
             "kickoff": "2026-10-21T00:23:00Z", "image-digest": "sha256:" + "a" * 64, "out": self.out}
        a.update(over)
        argv = ["build", "--repo", self.repo]
        for k, v in a.items():
            if v is not None:
                argv += ["--" + k, os.path.join(self.repo, v) if k in ("prereg", "corpus-sums", "suite-root", "suite-file") else v]
        return argv

    def run_main(self, argv):
        so, se = io.StringIO(), io.StringIO()
        with redirect_stdout(so), redirect_stderr(se):
            rc = reg.main(argv)
        return rc, so.getvalue(), se.getvalue()

    def test_build_is_canonical_deterministic_and_prints_its_sha256(self):
        rc, out, err = self.run_main(self.args())
        self.assertEqual(rc, 0, err)
        data = rb(self.out)
        self.assertEqual(out.strip(), hashlib.sha256(data).hexdigest())
        self.assertFalse(data.endswith(b"\n"))
        rec = json.loads(data)
        self.assertEqual(data, json.dumps(rec, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode())
        first = data
        rc, out2, _ = self.run_main(self.args())
        self.assertEqual(rb(self.out), first)
        self.assertEqual(out2, out)
        self.assertNotIn(self.repo, data.decode())   # no absolute path

    def test_record_fields_bind_every_input(self):
        self.assertEqual(self.run_main(self.args())[0], 0)
        rec = json.loads(rb(self.out))
        h = lambda p: hashlib.sha256(rb(os.path.join(self.repo, p))).hexdigest()
        self.assertEqual(rec["preregistration_sha256"], h("PREREGISTRATION.md"))
        self.assertEqual(rec["corpus_sha256sums_sha256"], h("SHA256SUMS"))
        self.assertEqual(rec["suite_manifest_sha256"], h("root/MANIFEST.sha256"))
        tree = subprocess.run(["git", "-C", self.repo, "rev-parse", "HEAD:evals/analysis/c132"], capture_output=True, text=True).stdout.strip()
        self.assertEqual(rec["analysis_tree_sha256"], tree)
        self.assertEqual((rec["pin"], rec["label_set"], rec["seed"], rec["cap_usd"], rec["boundary_constant"]),
                         ("abcdef1", "v2", 20261021, 2500, 1.08))
        self.assertEqual((rec["kickoff"], rec["supersedes"], rec["addenda"], rec["schema_version"]),
                         ("2026-10-21T00:23:00Z", None, [], 1))
        arms = {x["id"]: x for x in rec["arms"]}
        self.assertEqual([x["id"] for x in rec["arms"]], ["a1_full", "a0_bare_matched", "a0_bare_fable_matched"])
        self.assertEqual(arms["a0_bare_matched"]["k_by_task"], {"review-01": 3})
        self.assertEqual(arms["a0_bare_fable_matched"]["k_by_task"], {"review-01": 2})
        self.assertEqual(arms["a0_bare_fable_matched"]["phase_models"], {"BARE": reg.FABLE})
        self.assertEqual(arms["a0_bare_matched"]["phase_models"], {"BARE": reg.OPUS})
        self.assertEqual(arms["a1_full"]["phase_models"], {"REVIEW": reg.FABLE, "AUDIT": reg.FABLE})
        self.assertEqual(arms["a1_full"]["k_by_task"], {})

    def test_verify_ok_then_drift_on_a_changed_corpus_sum_prereg_or_analysis_tree(self):
        self.assertEqual(self.run_main(self.args())[0], 0)
        rc, out, _ = self.run_main(["verify", self.out, "--repo", self.repo])
        self.assertEqual(rc, 0)
        self.assertTrue(out.startswith("ok "))
        with open(os.path.join(self.repo, "SHA256SUMS"), "a") as f:
            f.write("1" * 64 + "  pr-02/fixture.yaml\n")
        rc, out, _ = self.run_main(["verify", self.out, "--repo", self.repo])
        self.assertEqual(rc, 1)
        self.assertIn("drift: corpus_sha256sums_sha256:", out)
        with open(os.path.join(self.repo, "evals", "analysis", "c132", "stats.py"), "w") as f:
            f.write("X = 2\n")
        git(self.repo, "commit", "-qam", "change")
        with open(os.path.join(self.repo, "PREREGISTRATION.md"), "a") as f:
            f.write("an edit\n")
        rc, out, _ = self.run_main(["verify", self.out, "--repo", self.repo])
        for field in ("analysis_tree_sha256", "preregistration_sha256", "corpus_sha256sums_sha256"):
            self.assertIn(f"drift: {field}:", out)

    def test_verify_refuses_a_non_canonical_file_and_a_changed_k(self):
        self.assertEqual(self.run_main(self.args())[0], 0)
        rec = json.loads(rb(self.out))
        with open(self.out, "w") as f:
            json.dump(rec, f, indent=2)
        rc, out, _ = self.run_main(["verify", self.out, "--repo", self.repo])
        self.assertEqual(rc, 1)
        self.assertIn("drift: canonical_form:", out)
        self.assertEqual(self.run_main(self.args())[0], 0)
        # the k of an ungrouped task is not registered; the grouped one's is
        subprocess.run(["yq", "-i", ".review_catch.bare_sessions_matched = 5",
                        os.path.join(self.repo, "root", "tasks", "review-02", "task.yaml")], check=True)
        self.assertEqual(self.run_main(["verify", self.out, "--repo", self.repo])[0], 0)
        subprocess.run(["yq", "-i", ".review_catch.bare_sessions_matched = 4",
                        os.path.join(self.repo, "root", "tasks", "review-01", "task.yaml")], check=True)
        rc, out, _ = self.run_main(["verify", self.out, "--repo", self.repo])
        self.assertEqual(rc, 1)
        self.assertIn("drift: arms:", out)

    def test_an_addendum_names_its_predecessor(self):
        rc, sha, _ = self.run_main(self.args())
        rc, _, err = self.run_main(self.args(out="REGISTRATION-2.json".join([self.repo + "/", ""]), supersedes=sha.strip()))
        self.assertEqual(rc, 0, err)
        self.assertEqual(json.loads(rb(os.path.join(self.repo, "REGISTRATION-2.json")))["supersedes"], sha.strip())

    def test_invalid_arguments_exit_2(self):
        cases = [dict(pin="XYZ"), dict(groups='[["review-01", "review-01"]]'), dict(groups='[["no-such-task"]]'),
                 dict(looks="[1, 1]"), dict(looks="[9]"), dict(arms="a8_no_ceremonies"), dict(arms="nope"),
                 dict(**{"cap-usd": "0"}), dict(**{"boundary-constant": "-1"}), dict(supersedes="abc"),
                 dict(kickoff="yesterday"), dict(**{"analysis-tree": "HEAD:no/such/dir"})]
        for over in cases:
            rc, _, err = self.run_main(self.args(**over))
            self.assertEqual(rc, 2, f"{over}: {err}")
        # a matched arm on a task without k
        subprocess.run(["yq", "-i", "del(.review_catch.bare_sessions_matched)",
                        os.path.join(self.repo, "root", "tasks", "review-01", "task.yaml")], check=True)
        rc, _, err = self.run_main(self.args(arms="a0_bare_matched"))
        self.assertEqual(rc, 2)
        self.assertIn("has no review_catch.bare_sessions_matched", err)
        # an input outside the repository
        rc, _, err = self.run_main(self.args(prereg="../outside.md"))
        self.assertEqual(rc, 2)


if __name__ == "__main__":
    unittest.main()
