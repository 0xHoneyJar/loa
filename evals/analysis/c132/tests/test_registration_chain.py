"""common.validate_registration / registration_provenance: rows registered under a predecessor on
the `supersedes` chain are readable (PREREGISTRATION.md §12, addendum 11)."""
import contextlib
import hashlib
import io
import json
import os
import shutil
import tempfile
import unittest

import _path  # noqa: F401
import synth
from c132 import common, reads


def write_reg(d, name, supersedes, tag):
    p = os.path.join(d, name)
    with open(p, "w") as f:
        f.write(json.dumps({"schema_version": 1, "tag": tag, "supersedes": supersedes}, sort_keys=True))
    with open(p, "rb") as f:
        return p, hashlib.sha256(f.read()).hexdigest()


def rows_for(shas):
    return [{"batch": "g1", "arm": "a1_full", "task_id": "t%d" % i, "trial": 1, "registration_sha256": h}
            for i, h in enumerate(shas)]


class ChainTest(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(prefix="c132-regchain-")
        _, self.h0 = write_reg(self.d, "REGISTRATION.json", None, 0)
        _, self.h1 = write_reg(self.d, "REGISTRATION-1.json", self.h0, 1)
        self.p2, self.h2 = write_reg(self.d, "REGISTRATION-2.json", self.h1, 2)

    def tearDown(self):
        shutil.rmtree(self.d)

    def test_current_sha_passes(self):
        self.assertEqual(common.validate_registration(self.p2, rows_for([self.h2, self.h2])), self.h2)

    def test_direct_predecessor_passes(self):
        self.assertEqual(common.validate_registration(self.p2, rows_for([self.h1, self.h2])), self.h2)

    def test_two_step_predecessor_passes(self):
        self.assertEqual(common.validate_registration(self.p2, rows_for([self.h0, self.h1, self.h2])), self.h2)

    def test_outside_chain_fails(self):
        for stray in ("f" * 64, None):
            with self.assertRaises(common.InputError) as cm:
                common.validate_registration(self.p2, rows_for([self.h2, stray]))
            self.assertIn("registration_sha256 differs from %s on 1 row(s): g1/a1_full/t1/1" % self.h2[:12],
                          str(cm.exception))

    def test_newer_registration_not_accepted_under_older(self):
        with self.assertRaises(common.InputError):
            common.validate_registration(os.path.join(self.d, "REGISTRATION-1.json"), rows_for([self.h2]))

    def test_missing_predecessor_unresolved_and_refused(self):
        # round 9 (audit DISS-C-001): a declared predecessor whose file is absent stays in the reported
        # lineage but is not accepted; rows under it fail, tagged as an unresolved predecessor
        os.remove(os.path.join(self.d, "REGISTRATION-1.json"))
        rows = rows_for([self.h1, self.h2, self.h2])
        with self.assertRaises(common.InputError) as cm:
            common.validate_registration(self.p2, rows)
        self.assertIn("registration_sha256 differs from %s on 1 row(s): g1/a1_full/t0/1" % self.h2[:12],
                      str(cm.exception))
        self.assertIn("%s (unresolved predecessor)" % self.h1[:12], str(cm.exception))
        self.assertEqual(common.validate_registration(self.p2, rows_for([self.h2])), self.h2)
        prov = common.registration_provenance(self.p2, rows)
        self.assertEqual(prov["chain"], [self.h2, self.h1])
        self.assertEqual(prov["unresolved_predecessor"], [self.h1])
        self.assertEqual(prov["rows_by_registration"], {self.h1: 1, self.h2: 2})
        # the walk stops at the missing file: h0 lies beyond the evidence and is refused
        with self.assertRaises(common.InputError):
            common.validate_registration(self.p2, rows_for([self.h0]))

    def test_malformed_supersedes_is_an_input_error(self):
        for bad in ("f" * 63, "F" * 64, self.h2 + "\n", "g" * 64, "not-a-sha"):
            p, _ = write_reg(self.d, "REGISTRATION-9.json", bad, 9)
            for fn in (lambda: common.validate_registration(p, rows_for([self.h2])),
                       lambda: common.registration_provenance(p, [])):
                with self.assertRaises(common.InputError) as cm:
                    fn()
                self.assertIn("not a 64-hex sha256", str(cm.exception))

    def test_malformed_supersedes_in_a_predecessor_is_an_input_error(self):
        _, hb = write_reg(self.d, "REGISTRATION-7.json", "xyz", 7)
        p, _ = write_reg(self.d, "REGISTRATION-8.json", hb, 8)
        with self.assertRaises(common.InputError):
            common.registration_chain(p)

    def test_provenance_counts(self):
        rows = rows_for([self.h0, self.h1, self.h1, self.h2, self.h2, self.h2])
        prov = common.registration_provenance(self.p2, rows)
        self.assertEqual(prov, {"current": self.h2, "chain": [self.h2, self.h1, self.h0],
                                "rows_by_registration": {self.h0: 1, self.h1: 2, self.h2: 3},
                                "unresolved_predecessor": []})

    def test_non_string_supersedes_ends_the_chain(self):
        p, h = write_reg(self.d, "REGISTRATION-3.json", {"sha256": self.h2}, 3)
        self.assertEqual(common.registration_chain(p), ([h], []))
        with self.assertRaises(common.InputError):
            common.validate_registration(p, rows_for([self.h2]))


class ReadDocTest(unittest.TestCase):
    """end to end: --make-inputs and a look over rows from a predecessor and the current registration"""
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="c132-regchain-read-")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_reads(self, argv):
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            rc = reads.main(argv)
        self.assertEqual(rc, 0, err.getvalue())

    def test_read_doc_reports_rows_by_registration(self):
        s = synth.build(os.path.join(self.tmp, "b"))
        h_old = s["reg_sha"]
        with open(s["registration"]) as f:
            reg = json.load(f)
        reg["supersedes"] = h_old
        new = os.path.join(os.path.dirname(s["registration"]), "REGISTRATION-1.json")
        with open(new, "w") as f:
            f.write(json.dumps(reg, sort_keys=True, separators=(",", ":")))
        with open(new, "rb") as f:
            h_new = hashlib.sha256(f.read()).hexdigest()
        with open(s["rows"]) as f:
            rows = [json.loads(l) for l in f.read().splitlines()]
        n_new = len(rows) // 2
        for r in rows[:n_new]:
            r["registration_sha256"] = h_new
        with open(s["rows"], "w") as f:
            for r in rows:
                f.write(json.dumps(r, sort_keys=True) + "\n")
        want = {h_new: n_new, h_old: len(rows) - n_new}
        inputs_dir, out = os.path.join(self.tmp, "in"), os.path.join(self.tmp, "o")
        self.run_reads(["--rows", s["rows"], "--results-root", s["results"], "--make-inputs", "--registration", new,
                        "--out", inputs_dir, "--pin", "a" * 40, "--label-set", "v2"])
        with open(os.path.join(inputs_dir, "INPUTS.json")) as f:
            inp = json.load(f)
        self.assertEqual(inp["registrations"]["rows_by_registration"], want)
        self.run_reads(["--rows", s["rows"], "--results-root", s["results"], "--inputs",
                        os.path.join(inputs_dir, "INPUTS.json"), "--registration", new, "--look", "1", "--out", out])
        with open(os.path.join(out, "reads.json")) as f:
            doc = json.load(f)
        self.assertEqual(doc["inputs"]["registration_sha256"], h_new)
        self.assertEqual(doc["inputs"]["registrations"]["chain"], [h_new, h_old])
        self.assertEqual(doc["inputs"]["registrations"]["rows_by_registration"], want)
        with open(os.path.join(out, "reads.md")) as f:
            md = f.read()
        self.assertIn("Rows by registration: %s." % ", ".join(
            "%s: %d" % (k[:12], n) for k, n in sorted(want.items())), md)
        self.assertIn("Registration chain (current first): `%s` → `%s`." % (h_new[:12], h_old[:12]), md)


if __name__ == "__main__":
    unittest.main()
