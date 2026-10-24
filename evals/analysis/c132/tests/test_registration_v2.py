"""Registration v2 — `looks_seen` (cycle-133 Sprint 3 Task 3.3; PRD FR-12 AC 2; SDD C-12).

A v2 registration (schema_version 2) names every committed look its authors had seen: each entry
{look, suite, registration_sha256, rows_sha256} must match the committed looks inventory
(<looks_root>/c*-looks/<look>/rows.jsonl tracked by git, with its <look>.json), the entries are in
strictly increasing look order, none names this registration itself, and every committed look not
listed must have been read under this registration or a successor on its `supersedes` chain. A v1
registration (no looks_seen) builds and verifies byte for byte as before — the cycle-132 chain too.

Run: python3 -m unittest discover -s evals/analysis/c132/tests"""
import glob
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
SPEC = importlib.util.spec_from_file_location("registration_c132_v2", os.path.join(HERE, "..", "registration.py"))
reg = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(reg)
SUITE = "5" * 64


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
class RegistrationV2Test(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.mkdtemp(prefix="reg-v2-test.")
        self.repo = os.path.join(self.t, "repo")
        os.makedirs(os.path.join(self.repo, "evals", "analysis", "c132"))
        with open(os.path.join(self.repo, "evals", "analysis", "c132", "stats.py"), "w") as f:
            f.write("X = 1\n")
        shutil.copytree(os.path.join(REPO, "grimoires", "loa", "evals", "ablation-2.0"), os.path.join(self.repo, "root"))
        shutil.copy(os.path.join(REPO, "evals", "suites", "ablation-2.0.yaml"), os.path.join(self.repo, "suite.yaml"))
        with open(os.path.join(self.repo, "SHA256SUMS"), "w") as f:
            f.write("0" * 64 + "  pr-01/fixture.yaml\n")
        with open(os.path.join(self.repo, "PREREGISTRATION.md"), "w") as f:
            f.write("# Pre-registration\n")
        self.reports = os.path.join(self.repo, "reports")
        self.reg_dir = os.path.join(self.repo, "regs")
        os.makedirs(self.reg_dir)
        self.look_a = self.add_look("c900-looks", "look-1", 1, "a" * 64, rows=2)
        self.look_b = self.add_look("c900-looks", "look-2", 2, "a" * 64, rows=3)
        subprocess.run(["git", "-C", self.repo, "init", "-q"], check=True)
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "init")

    def tearDown(self):
        shutil.rmtree(self.t, ignore_errors=True)

    def add_look(self, family, name, index, reg_sha, rows=2, suite=SUITE):
        d = os.path.join(self.reports, family, name)
        os.makedirs(d, exist_ok=True)
        body = "".join(json.dumps({"run_id": f"{name}-{i}", "suite_manifest_sha256": suite, "registration_sha256": reg_sha},
                                  sort_keys=True) + "\n" for i in range(rows))
        with open(os.path.join(d, "rows.jsonl"), "w") as f:
            f.write(body)
        rows_sha = hashlib.sha256(body.encode()).hexdigest()
        with open(os.path.join(d, f"{name}.json"), "w") as f:
            json.dump({"look": index, "inputs": {"registration_sha256": reg_sha, "rows_sha256": rows_sha}}, f)
        return {"look": f"{family}/{name}", "suite": suite, "registration_sha256": reg_sha, "rows_sha256": rows_sha}

    def commit(self, msg="more"):
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", msg)

    def run_main(self, argv):
        so, se = io.StringIO(), io.StringIO()
        with redirect_stdout(so), redirect_stderr(se):
            rc = reg.main(argv)
        return rc, so.getvalue(), se.getvalue()

    def build(self, out, looks_seen=None, supersedes=None):
        argv = ["build", "--repo", self.repo, "--prereg", os.path.join(self.repo, "PREREGISTRATION.md"),
                "--corpus-sums", os.path.join(self.repo, "SHA256SUMS"), "--suite-root", os.path.join(self.repo, "root"),
                "--analysis-tree", "HEAD:evals/analysis/c132", "--pin", "abcdef1",
                "--suite-file", os.path.join(self.repo, "suite.yaml"), "--arms", "a1_full",
                "--groups", '[["review-01"]]', "--looks", "[1]", "--boundary-constant", "1.08", "--cap-usd", "2500",
                "--seed", "1", "--out", out]
        if looks_seen is not None:
            argv += ["--looks-seen", json.dumps(looks_seen), "--looks-root", self.reports]
        if supersedes:
            argv += ["--supersedes", supersedes]
        return self.run_main(argv)

    def verify(self, path):
        return self.run_main(["verify", path, "--repo", self.repo])

    # ------------------------------------------------------------------ build
    def test_a_complete_looks_seen_builds_v2_and_verifies(self):
        out = os.path.join(self.reg_dir, "REGISTRATION.json")
        rc, sha, err = self.build(out, [self.look_a, self.look_b])
        self.assertEqual(rc, 0, err)
        rec = json.loads(rb(out))
        self.assertEqual(rec["schema_version"], 2)
        self.assertEqual(rec["looks_seen"], [self.look_a, self.look_b])
        self.assertEqual(rec["looks_root"], "reports")
        rc, o, _ = self.verify(out)
        self.assertEqual((rc, o.strip()), (0, "ok " + sha.strip()))

    def test_without_looks_seen_the_build_is_v1_byte_for_byte(self):
        out = os.path.join(self.reg_dir, "REGISTRATION.json")
        self.assertEqual(self.build(out)[0], 0)
        rec = json.loads(rb(out))
        self.assertEqual(rec["schema_version"], 1)
        self.assertNotIn("looks_seen", rec)
        self.assertNotIn("looks_root", rec)

    def test_an_omitted_committed_look_is_refused_at_build(self):
        rc, _, err = self.build(os.path.join(self.reg_dir, "R.json"), [self.look_a])
        self.assertEqual(rc, 2)
        self.assertIn("looks_seen omits the committed look c900-looks/look-2", err)

    def test_a_look_whose_rows_hash_differs_is_refused_at_build(self):
        bad = dict(self.look_b, rows_sha256="f" * 64)
        rc, _, err = self.build(os.path.join(self.reg_dir, "R.json"), [self.look_a, bad])
        self.assertEqual(rc, 2)
        self.assertIn("c900-looks/look-2: rows_sha256", err)

    def test_order_duplicates_shape_and_unknown_looks_are_refused(self):
        out = os.path.join(self.reg_dir, "R.json")
        for seen, why in (([self.look_b, self.look_a], "strictly increasing"),
                          ([self.look_a, self.look_a, self.look_b], "strictly increasing"),
                          ([dict(self.look_a, extra=1), self.look_b], "exactly the keys"),
                          ([self.look_a, self.look_b, dict(self.look_b, look="c900-looks/look-9")], "not a committed look"),
                          ({"look": 1}, "a list")):
            rc, _, err = self.build(out, seen)
            self.assertEqual(rc, 2, seen)
            self.assertIn(why, err)

    def test_an_uncommitted_look_is_not_inventory(self):
        self.add_look("c900-looks", "look-3", 3, "a" * 64)   # written, never committed
        out = os.path.join(self.reg_dir, "REGISTRATION.json")
        self.assertEqual(self.build(out, [self.look_a, self.look_b])[0], 0)

    def test_a_look_index_that_disagrees_with_its_name_is_refused(self):
        p = os.path.join(self.reports, "c900-looks", "look-2", "look-2.json")
        with open(p) as f:
            d = json.load(f)
        d["look"] = 7
        with open(p, "w") as f:
            json.dump(d, f)
        self.commit()
        rc, _, err = self.build(os.path.join(self.reg_dir, "R.json"), [self.look_a, self.look_b])
        self.assertEqual(rc, 2)
        self.assertIn("look index 7", err)

    # ----------------------------------------------------------------- verify
    def test_verify_fails_when_a_listed_look_changes_after_the_build(self):
        out = os.path.join(self.reg_dir, "REGISTRATION.json")
        self.assertEqual(self.build(out, [self.look_a, self.look_b])[0], 0)
        with open(os.path.join(self.reports, "c900-looks", "look-1", "rows.jsonl"), "a") as f:
            f.write("{}\n")
        self.commit()
        rc, o, _ = self.verify(out)
        self.assertEqual(rc, 1)
        self.assertIn("drift: looks_seen:", o)
        self.assertIn("c900-looks/look-1", o)

    def test_verify_fails_when_a_committed_look_from_elsewhere_is_not_listed(self):
        out = os.path.join(self.reg_dir, "REGISTRATION.json")
        self.assertEqual(self.build(out, [self.look_a, self.look_b])[0], 0)
        self.add_look("c901-looks", "look-1", 1, "b" * 64)   # read under an unrelated registration
        self.commit()
        rc, o, _ = self.verify(out)
        self.assertEqual(rc, 1)
        self.assertIn("omits the committed look c901-looks/look-1", o)

    def test_looks_read_under_this_registration_or_a_successor_need_not_be_listed(self):
        out = os.path.join(self.reg_dir, "REGISTRATION.json")
        rc, sha, _ = self.build(out, [self.look_a, self.look_b])
        self.assertEqual(rc, 0)
        sha = sha.strip()
        self.add_look("c901-looks", "look-1", 1, sha)                     # under this registration
        self.commit()
        succ = os.path.join(self.reg_dir, "REGISTRATION-1.json")
        rc, sha1, err = self.build(succ, [self.look_a, self.look_b], supersedes=sha)
        self.assertEqual(rc, 2)                                             # the successor must list it
        self.assertIn("omits the committed look c901-looks/look-1", err)
        rc, sha1, err = self.build(succ, [self.look_a, self.look_b, self.add_look("c901-looks", "look-1", 1, sha)],
                                   supersedes=sha)
        self.assertEqual(rc, 0, err)
        self.add_look("c901-looks", "look-2", 2, sha1.strip())             # under the successor
        self.commit()
        self.assertEqual(self.verify(out)[0], 0)                            # the predecessor still verifies
        self.assertEqual(self.verify(succ)[0], 0)

    def test_a_self_reference_and_a_successor_reference_are_refused(self):
        inv = {"c900-looks/look-1": self.look_a}
        errs = reg.looks_seen_errors([dict(self.look_a, registration_sha256="c" * 64)],
                                     dict(inv, **{"c900-looks/look-1": dict(self.look_a, registration_sha256="c" * 64)}),
                                     self_sha="c" * 64, successors=set())
        self.assertTrue(any("names this registration itself" in e for e in errs), errs)
        errs = reg.looks_seen_errors([dict(self.look_a, registration_sha256="d" * 64)],
                                     {"c900-looks/look-1": dict(self.look_a, registration_sha256="d" * 64)},
                                     self_sha="c" * 64, successors={"d" * 64})
        self.assertTrue(any("successor" in e for e in errs), errs)

    def test_a_v1_document_carrying_looks_seen_is_refused(self):
        out = os.path.join(self.reg_dir, "REGISTRATION.json")
        self.assertEqual(self.build(out)[0], 0)
        rec = json.loads(rb(out))
        rec["looks_seen"] = []
        with open(out, "wb") as f:
            f.write(reg.jcs(rec, self.repo))
        rc, o, err = self.verify(out)
        self.assertNotEqual(rc, 0)
        self.assertIn("looks_seen", o + err)


@unittest.skipUnless(jcs_available(), "lib/jcs.sh needs the rfc8785 package")
class Cycle132ChainTest(unittest.TestCase):
    def test_every_tracked_cycle_132_registration_verifies_unchanged(self):
        files = sorted(glob.glob(os.path.join(REPO, "grimoires", "loa", "evals", "ablation-2.0-c132", "REGISTRATION*.json")))
        self.assertGreaterEqual(len(files), 18)
        for p in files:
            so = io.StringIO()
            with redirect_stdout(so), redirect_stderr(io.StringIO()):
                rc = reg.main(["verify", p, "--repo", REPO])
            self.assertEqual(rc, 0, f"{os.path.basename(p)}: {so.getvalue()}")
            self.assertEqual(so.getvalue().strip(), "ok " + hashlib.sha256(rb(p)).hexdigest())
            self.assertEqual(json.loads(rb(p))["schema_version"], 1)


if __name__ == "__main__":
    unittest.main()
