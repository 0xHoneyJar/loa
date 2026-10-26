"""reads.py / common.py: input validation, the validity filter, the partition, degenerate
statuses and byte-identical output (sdd.md §5.2; prd.md FR-5 AC 1, 3)."""
import contextlib
import io
import json
import os
import shutil
import tempfile
import unittest

import _path  # noqa: F401
import synth
from c132 import common, reads


def slurp(path, mode="r"):
    with open(path, mode) as f:
        return f.read()


def jload(path):
    return json.loads(slurp(path))


def run(argv):
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        rc = reads.main(argv)
    return rc, err.getvalue()


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="c132-reads-")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def batch(self, sub="b", **kw):
        root = os.path.join(self.tmp, sub)
        s = synth.build(root, **kw)
        s["inputs_dir"] = os.path.join(root, "in")
        rc, err = run(["--rows", s["rows"], "--results-root", s["results"], "--make-inputs",
                       "--out", s["inputs_dir"], "--pin", "a" * 40, "--label-set", "v2"])
        self.assertEqual(rc, 0, err)
        s["inputs"] = os.path.join(s["inputs_dir"], "INPUTS.json")
        return s

    def common_args(self, s):
        return ["--rows", s["rows"], "--results-root", s["results"], "--inputs", s["inputs"],
                "--registration", s["registration"]]


class OutputTest(Base):
    def test_look_and_final_byte_identical(self):
        s = self.batch()
        for mode in (["--look", "1"], ["--look", "2"], ["--final"]):
            outs = []
            for i in (1, 2):
                o = os.path.join(self.tmp, "o%d" % i)
                rc, err = run(self.common_args(s) + mode + ["--out", o])
                self.assertEqual(rc, 0, err)
                outs.append((slurp(os.path.join(o, "reads.json"), "rb"),
                             slurp(os.path.join(o, "reads.md"), "rb")))
            self.assertEqual(outs[0], outs[1], mode)
            doc = json.loads(outs[0][0])
            self.assertNotIn(self.tmp, outs[0][0].decode())
            self.assertNotIn(self.tmp, outs[0][1].decode())
            if mode[0] == "--look":
                self.assertIn(doc["decision"], ("YES", "NO", "SMALL", "FUTILE", "CONTINUE", "INCONCLUSIVE"))
                self.assertEqual(len(doc["looks"]), int(mode[1]))
        final = json.loads(outs[0][0])
        for k in ("primary", "lmm", "permutation", "secondary", "missingness", "guard", "sensitivities"):
            self.assertIn(k, final)
        self.assertEqual(final["sensitivities"]["order"], reads.DEFAULT_SENSITIVITIES)
        self.assertEqual(final["primary"]["n_prs"], 8)
        self.assertEqual(final["primary"]["status"], "ok")
        for k in ("review_only_vs_full", "pipeline_independent", "matched_fable", "dollar_matching",
                  "defects_per_usd", "cost_per_extra_defect"):
            self.assertIn(k, final["secondary"])
        self.assertEqual(final["secondary"]["pipeline_independent"]["status"], "ok")
        self.assertLess(final["secondary"]["pipeline_independent"]["n_defects"], final["primary"]["n_defects"])
        self.assertEqual(final["sensitivities"]["reads"]["exact_dollar_trim"]["status"], "ok")
        # floats are fixed %.4f
        txt = outs[0][0].decode()
        self.assertRegex(txt, r'"delta": -?\d+\.\d{4}[,}]')

    def test_placebo_without_registration(self):
        s = self.batch()
        o = os.path.join(self.tmp, "p")
        rc, err = run(["--rows", s["rows"], "--results-root", s["results"], "--inputs", s["inputs"],
                       "--placebo", "--placebo-n", "20", "--out", o, "--name", "placebo-existing"])
        self.assertEqual(rc, 0, err)
        doc = jload(os.path.join(o, "placebo-existing.json"))
        self.assertIsNone(doc["inputs"]["registration_sha256"])
        self.assertEqual(doc["placebo"]["n"], 20)
        self.assertIn("unregistered", slurp(os.path.join(o, "placebo-existing.md")))


class InputValidationTest(Base):
    def assert_refused(self, s, extra=("--final",)):
        o = os.path.join(self.tmp, "never")
        rc, err = run(self.common_args(s) + list(extra) + ["--out", o])
        self.assertEqual(rc, 1, err)
        self.assertFalse(os.path.exists(o))
        return err

    def test_tampered_grade(self):
        s = self.batch()
        g = os.path.join(s["results"], "c132-g1", "a1_full", "review-s01-t1", "grade.json")
        with open(g, "a") as f:
            f.write(" ")
        self.assertIn("grade.json sha256 differs", self.assert_refused(s))

    def test_rows_changed(self):
        s = self.batch()
        with open(s["rows"], "a") as f:
            f.write("\n")
        self.assertIn("rows file sha256", self.assert_refused(s))

    def test_registration_mismatch(self):
        s = self.batch()
        with open(s["registration"], "a") as f:
            f.write(" ")
        self.assertIn("registration_sha256 differs", self.assert_refused(s, ("--look", "1")))

    def test_session_membership(self):
        s = self.batch()
        inp = jload(s["inputs"])
        key = "c132-g1/a0_bare_matched/review-s02/1"
        inp["cells"][key]["sessions"] = ["s1", "s2"]
        with open(s["inputs"], "w") as f:
            json.dump(inp, f)
        self.assertIn("session membership differs", self.assert_refused(s))

    def test_pin_and_label_set(self):
        s = self.batch()
        inp = jload(s["inputs"])
        inp["pin"] = "b" * 40
        inp["label_set"] = "c131"
        with open(s["inputs"], "w") as f:
            json.dump(inp, f)
        err = self.assert_refused(s)
        self.assertIn("pin differs", err)
        self.assertIn("label_set", err)

    def test_missing_expected_cell(self):
        s = self.batch()
        inp = jload(s["inputs"])
        inp["cells"]["c132-g1/a1_full/review-s99/1"] = {"grade_sha256": None, "sessions": None}
        with open(s["inputs"], "w") as f:
            json.dump(inp, f)
        self.assertIn("expected cell missing", self.assert_refused(s))

    def test_duplicate_key(self):
        s = self.batch()
        with open(s["rows"]) as f:
            first = f.readline()
        with open(s["rows"], "a") as f:
            f.write(first)
        self.assertIn("duplicate cell key", self.assert_refused(s))

    def test_usage(self):
        self.assertEqual(run(["--rows", "x", "--final", "--out", "y"])[0], 2)          # no --inputs
        self.assertEqual(run(["--rows", "x", "--inputs", "i", "--final", "--out", "y"])[0], 2)  # no --registration
        self.assertEqual(run(["--rows", "x", "--inputs", "i", "--placebo", "--out", "y", "--name", "../z"])[0], 2)


class ExactDollarPm3Test(unittest.TestCase):
    def test_trim_reads_detected_pm3(self):
        row = {"batch": "b", "arm": "a0_bare_matched", "task_id": "t", "trial": 1, "status": "completed",
               "defects_seeded": 3, "defects_missed_pm3": ["d3"], "bare_sessions": 2, "sessions_valid": 2, "cost_usd": 4.0}
        g = {"per_session": [{"session": "s1", "detected": ["d1", "d2"], "detected_pm3": ["d1"], "cost_usd": 2.0},
                             {"session": "s2", "detected": ["d2"], "detected_pm3": ["d2"], "cost_usd": 2.0}]}
        cb = common.build_cell(row, g)
        p = {"pr": "t", "trial": 1, "full": {"caught": 3, "defects": 3, "cost": 2.0, "key": "f"},
             "matched": {"caught": 2, "defects": 3, "cost": 4.0, "key": cb["key"]}}
        out, missing = reads.exact_dollar_pairs([p], {cb["key"]: cb})
        self.assertEqual(missing, 0)
        self.assertEqual(out[0]["matched"]["caught"], 1)      # s1 only fits the full cell's USD 2, pm3 = {d1}
        self.assertEqual(out[0]["matched"]["m"], 1)


class Round1OptionsTest(Base):
    def read(self, s, *extra):
        o = os.path.join(self.tmp, "o")
        rc, err = run(self.common_args(s) + list(extra) + ["--out", o])
        self.assertEqual(rc, 0, err)
        return jload(os.path.join(o, "reads.json"))

    def test_interval_t_default_and_percentile(self):
        s = self.batch()
        t = self.read(s, "--final")
        self.assertEqual(t["interval"], "t")
        self.assertEqual(t["primary"]["ci95"], t["primary"]["ci95_t"])
        self.assertIn("ci95_percentile", t["primary"])
        lk = t["looks"][0]
        self.assertGreater(lk["b_yes"], lk["b_yes_normal"])          # t scale, df = 5
        self.assertEqual(lk["df"], 5)
        self.assertAlmostEqual(lk["rci"][1] - lk["delta"], lk["b_yes"] * lk["se"], places=3)
        p = self.read(s, "--final", "--interval", "percentile")
        self.assertEqual(p["primary"]["ci95"], p["primary"]["ci95_percentile"])
        self.assertEqual(p["looks"][0]["b_yes"], p["looks"][0]["b_yes_normal"])

    def test_validity_c131_keeps_oracle_exposed_full_cells(self):
        def exposed(row, grade):
            if row["arm"] == "a1_full":
                row["oracle_exposed_defects"] = ["d1"]
        s = self.batch(mutate=exposed)
        o = os.path.join(self.tmp, "p")
        base = ["--rows", s["rows"], "--results-root", s["results"], "--inputs", s["inputs"], "--placebo", "--placebo-n", "5"]
        rc, err = run(base + ["--out", o])
        self.assertEqual(rc, 0, err)
        self.assertEqual(jload(os.path.join(o, "reads.json"))["placebo"]["status"], "no_valid_pairs")
        rc, err = run(base + ["--out", o, "--validity", "c131"])
        self.assertEqual(rc, 0, err)
        doc = jload(os.path.join(o, "reads.json"))
        self.assertEqual(doc["validity"], "c131")
        self.assertEqual(doc["placebo"]["status"], "ok")
        self.assertIn("|mean Δ| < 0.03", slurp(os.path.join(o, "reads.md")))


class ValidityTest(unittest.TestCase):
    def cell(self, **row):
        base = {"batch": "b", "arm": "a1_full", "task_id": "t", "trial": 1, "status": "completed",
                "contaminated": None, "oracle_exposed_defects": [], "defects_seeded": 3,
                "defects_missed_pm3": ["d2"], "phases": [{"refusal_fallbacks": []}], "cost_usd": 1.0}
        base.update(row)
        return common.build_cell(base, None)

    def test_valid(self):
        c = self.cell()
        self.assertTrue(c["valid"])
        self.assertEqual(c["caught_ids"], ["d1", "d3"])
        self.assertEqual(c["took_effect"], "not_recorded")

    def test_each_rule(self):
        self.assertIn("status:agent_error", self.cell(status="agent_error")["reasons"])
        self.assertIn("took_effect", self.cell(took_effect={"no_dot_claude": True, "integrity_clean": False})["reasons"])
        self.assertTrue(self.cell(took_effect={"no_dot_claude": True})["valid"])
        self.assertIn("contaminated", self.cell(contaminated={"pattern": "network_egress"})["reasons"])
        self.assertIn("oracle_exposed", self.cell(oracle_exposed_defects=["d1"])["reasons"])
        row = {"batch": "b", "arm": "a1_full", "task_id": "t", "trial": 1, "status": "completed", "defects_seeded": 2,
               "defects_missed_pm3": [], "oracle_exposed_defects": ["d1"]}
        self.assertTrue(common.build_cell(row, None, rules="c131")["valid"])
        self.assertFalse(common.build_cell(dict(row, contaminated={"p": 1}), None, rules="c131")["valid"])
        self.assertTrue(self.cell(arm="a1_full_openmount", oracle_exposed_defects=["d1"])["valid"])
        self.assertIn("refusal_fallbacks", self.cell(phases=[{"refusal_fallbacks": ["x"]}])["reasons"])
        self.assertIn("no_defect_record", self.cell(defects_missed_pm3=None)["reasons"])

    def test_matched_rule(self):
        # k = 5 → valid at ≥ 3 valid sessions; refusal fallbacks in a session do not void the cell
        m = dict(arm="a0_bare_matched", bare_sessions=5, phases=[{"refusal_fallbacks": ["x"]}])
        self.assertTrue(self.cell(sessions_valid=3, **m)["valid"])
        self.assertIn("sessions_valid<ceil(k/2)", self.cell(sessions_valid=2, **m)["reasons"])

    def test_labels_meta_defect_key(self):
        # grader 1.3.2 writes {defect: "d<n>", …}; `id` and the position remain fallbacks
        ids = ["d1", "d2", "d3"]
        g = {"labels_meta": [{"defect": "d3", "review_driven": False}, {"id": "d1", "review_driven": True},
                             {"review_driven": True}]}
        m = common.labels_meta_map(g, ids)
        self.assertEqual(m["d3"]["review_driven"], False)
        self.assertEqual(m["d1"]["review_driven"], True)
        self.assertIn("d3", m)
        self.assertEqual(sorted(m), ["d1", "d3"])          # the third entry falls back to position d3: already taken
        self.assertEqual(common.labels_meta_map({"labels_meta": [{"x": 1}, {"x": 2}]}, ids), {"d1": {"x": 1}, "d2": {"x": 2}})

    def test_session1_prefers_detected_pm3(self):
        row = {"batch": "b", "arm": "a0_bare_matched", "task_id": "t", "trial": 1, "status": "completed",
               "defects_seeded": 4, "defects_missed_pm3": ["d4"], "bare_sessions": 2, "sessions_valid": 2}
        both = {"per_session": [{"session": "s1", "detected": ["d1", "d2", "d3"], "detected_pm3": ["d1"],
                                 "cost_usd": 2.5, "status": "completed"}]}
        c = common.build_cell(row, both)
        self.assertEqual(c["session1"], {"caught": 1, "cost": 2.5})
        plain = {"per_session": [{"session": "s1", "detected": ["d1", "d2"], "cost_usd": 2.5, "status": "completed"}]}
        self.assertEqual(common.build_cell(row, plain)["session1"]["caught"], 2)
        self.assertEqual(common.session_detected({"detected_pm3": [], "detected": ["d1"]}), [])

    def test_took_effect_shapes(self):
        # implementer C's row field: {rule: bool, …} | null
        self.assertTrue(self.cell(took_effect=None)["valid"])
        self.assertEqual(self.cell(took_effect=None)["took_effect"], "not_recorded")
        self.assertTrue(self.cell(took_effect={"a": True, "b": True})["valid"])
        self.assertFalse(self.cell(took_effect={"a": True, "b": False})["valid"])

    def test_statistic_source_order(self):
        c = common.build_cell({"batch": "b", "arm": "a", "task_id": "t", "trial": 1, "status": "completed",
                               "defects_seeded": 2, "defects_missed": ["d1", "d2"]},
                              {"recall": {"missed_pm3": ["d2"]}})
        self.assertEqual(c["statistic_source"], "grade.recall.missed_pm3")
        self.assertEqual(c["caught"], 1)


class PositiveControlTest(Base):
    def final(self, s):
        o = os.path.join(self.tmp, "o")
        rc, err = run(self.common_args(s) + ["--final", "--out", o])
        self.assertEqual(rc, 0, err)
        return jload(os.path.join(o, "reads.json"))

    def test_pass(self):
        doc = self.final(self.batch(open_mount={"p": 0.95, "exposed": True}, p_full=0.6))
        pc = doc["secondary"]["positive_control"]
        self.assertEqual(pc["outcome"], "pass")
        self.assertGreater(pc["delta"], 0)
        self.assertEqual(len(pc["exposed_open_runs"]), 12)
        self.assertFalse(doc["void"])
        self.assertEqual(pc["expected_effect"], 0.067)

    def test_not_exercised(self):
        pc = self.final(self.batch(open_mount={"p": 0.95, "exposed": False}, p_full=0.6))["secondary"]["positive_control"]
        self.assertEqual(pc["outcome"], "control not exercised")

    def test_void(self):
        doc = self.final(self.batch(open_mount={"p": 0.1, "exposed": True}, p_full=0.6))
        self.assertEqual(doc["secondary"]["positive_control"]["outcome"], "void")
        self.assertTrue(doc["void"])

    def test_saturated_pr_exempt(self):
        def sat(row, grade):
            if row["arm"] == "a1_full" and row["task_id"] == "review-s01":
                row["defects_missed_pm3"] = []
                grade["recall"]["missed_pm3"] = []
        pc = self.final(self.batch(open_mount={"p": 0.95, "exposed": True}, p_full=0.6, mutate=sat))["secondary"]["positive_control"]
        self.assertEqual(pc["saturated_exempt"], ["review-s01"])
        self.assertEqual(pc["n_prs"], 5)

    def test_absent(self):
        self.assertEqual(self.final(self.batch())["secondary"]["positive_control"], {"status": "not_run"})


class PartitionTest(unittest.TestCase):
    def test_partition(self):
        d = reads.decide
        # z_yes crosses, z_no does not, interval reaches the MDE → YES
        self.assertEqual(d(3.0, 2.5, 0.5, 2.5, 0.30, 0.10, 0.9, 0.1, False), "YES")
        # both cross → SMALL
        self.assertEqual(d(3.0, 2.5, 3.0, 2.5, 0.08, 0.10, 0.9, 0.9, False), "SMALL")
        # z_yes crosses but the RCI lies entirely below the MDE → SMALL
        self.assertEqual(d(3.0, 2.5, 1.0, 2.5, 0.09, 0.10, 0.9, 0.9, False), "SMALL")
        self.assertEqual(d(0.5, 2.5, 3.0, 2.5, 0.05, 0.10, 0.1, 0.9, False), "NO")
        self.assertEqual(d(0.5, 2.5, 0.5, 2.5, 0.5, 0.10, 0.1, 0.1, False), "FUTILE")
        self.assertEqual(d(0.5, 2.5, 0.5, 2.5, 0.5, 0.10, 0.5, 0.1, False), "CONTINUE")
        self.assertEqual(d(0.5, 2.0, 0.5, 2.0, 0.5, 0.10, 0.1, 0.1, True), "INCONCLUSIVE")


class DegenerateTest(Base):
    def final(self, s):
        o = os.path.join(self.tmp, "o")
        rc, err = run(self.common_args(s) + ["--final", "--out", o])
        self.assertEqual(rc, 0, err)
        return jload(os.path.join(o, "reads.json"))

    def test_too_few_prs_and_minimum_information(self):
        s = self.batch(n_prs=4)
        doc = self.final(s)
        self.assertEqual(doc["primary"]["status"], "too_few_prs")
        self.assertNotIn("delta", doc["primary"])
        self.assertEqual(doc["looks"][-1]["decision"], "CONTINUE")
        self.assertIn("minimum information", doc["looks"][-1]["reason"])

    def test_no_valid_pairs(self):
        def bad(row, grade):
            if row["arm"] == "a0_bare_matched":
                row["status"] = "degraded"
        s = self.batch(mutate=bad)
        doc = self.final(s)
        self.assertEqual(doc["primary"]["status"], "no_valid_pairs")
        self.assertEqual(doc["lmm"]["status"], "no_valid_pairs")
        self.assertTrue(doc["guard"]["inconclusive_by_degradation"])

    def test_zero_se(self):
        def same(row, grade):
            # every PR: 4 defects, full catches 3, every other arm 2 → Δ is 0.25 in every resample
            missed = ["d4"] if row["arm"] == "a1_full" else ["d3", "d4"]
            row["defects_seeded"] = 4
            row["defects_missed_pm3"] = missed
            grade["recall"].update(defects_seeded=4, missed_pm3=missed)
            grade["labels_meta"] = grade["labels_meta"][:4]
            for sess in grade.get("per_session") or []:
                sess["detected"] = [d for d in sess["detected"] if d in ("d1", "d2")]
        s = self.batch(mutate=same)
        doc = self.final(s)
        self.assertEqual(doc["primary"]["status"], "zero_se")
        self.assertNotIn("delta", doc["primary"])

    def test_guard_and_missingness_bounds(self):
        def drop(row, grade):
            if row["arm"] == "a0_bare_matched" and row["task_id"] in ("review-s01", "review-s02", "review-s03"):
                row["sessions_valid"] = 1
                row["status"] = "degraded"
            if row["arm"] == "a0_bare_matched" and row["task_id"] == "review-s04":
                row["sessions_valid"] = 3
        s = self.batch(mutate=drop)
        doc = self.final(s)
        g = doc["guard"]["arms"]["a0_bare_matched"]
        self.assertTrue(g["tripped"])
        self.assertAlmostEqual(g["excluded_share"], 6 / 16.0, places=4)
        b = doc["missingness"]["bounds"]
        lo = b["excluded_sessions_caught_everything"]["delta"]
        hi = b["excluded_sessions_missed_everything"]["delta"]
        self.assertLess(lo, hi)
        ms = doc["missingness"]["sessions_by_arm_k"]["a0_bare_matched/k=4"]
        self.assertEqual(ms["sessions_excluded"], 2 * 3 * 3 + 2 * 1)


if __name__ == "__main__":
    unittest.main()
