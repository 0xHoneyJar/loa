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
        self.assertEqual(pc["outcome"], "not exercised")
        self.assertEqual(pc["n_exposed_open_runs"], 0)
        self.assertEqual(pc["consequence"], "every other read unconfirmed by the positive control")
        self.assertEqual(pc["outcome_pre_addendum_10"], "control not exercised")
        self.assertEqual(pc["rule"], "§8 (addendum 10)")

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


def _expose_only(keep):
    """mutate: open-mount rows keep their oracle exposure only for the (task, trial)s in `keep`"""
    def mut(row, grade):
        if row["arm"] == "a1_full_openmount" and (row["task_id"], row["trial"]) not in keep:
            row["oracle_exposed_defects"] = []
    return mut


def _same_missed(open_extra=()):
    """mutate: a1_full and the open mount miss d1, d2 on every PR (Δ̂ = 0); the open mount also
    misses d3 on the (task, trial)s in `open_extra` (Δ̂ slightly < 0, the interval covering 0)"""
    def mut(row, grade):
        if row["arm"] in ("a1_full", "a1_full_openmount"):
            missed = ["d1", "d2"]
            if row["arm"] == "a1_full_openmount" and (row["task_id"], row["trial"]) in open_extra:
                missed.append("d3")
            row["defects_missed_pm3"] = missed
            grade["recall"]["missed_pm3"] = missed
    return mut


class PositiveControlAddendum10Test(Base):
    """PREREGISTRATION §8 (addendum 10): one test per outcome row, every group's pairs, and the
    pre-addendum-10 label beside"""

    def cells(self, s):
        return common.load_cells(common.load_rows(s["rows"]), [s["results"]], "c132")

    def pc(self, s, reg=None):
        return reads.positive_control(self.cells(s), reg or jload(s["registration"]), 20261021)

    def test_table_ordered_and_exhaustive(self):
        o = reads.pc_outcome
        self.assertEqual(o(0, 12, 0.1, [0.05, 0.15]), "not exercised")
        self.assertEqual(o(0, 12, -0.3, [-0.4, -0.2]), "not exercised")     # no exposure precedes void
        self.assertEqual(o(5, 2, -0.3, [-0.4, -0.2]), "not exercised")      # < 3 eligible pairs precedes void
        self.assertEqual(o(5, 0, None, None), "not exercised")
        self.assertEqual(o(1, 12, -0.3, [-0.4, -0.2]), "void")              # void needs exposure only
        self.assertEqual(o(2, 12, 0.05, [0.01, 0.09]), "pass")
        self.assertEqual(o(2, 12, 0.0, [-0.02, 0.02]), "not demonstrated")
        self.assertEqual(o(2, 12, -0.02, [-0.05, 0.01]), "not demonstrated")
        self.assertEqual(o(1, 12, 0.05, [0.01, 0.09]), "not demonstrated")
        p = reads.pc_outcome_pre_addendum_10
        self.assertEqual([p(0, 12, 0.1), p(1, 12, 0.1), p(1, 12, -0.01), p(1, 12, 0.0), p(1, 0, None), p(0, 0, None)],
                         ["control not exercised", "pass", "void", "inconclusive", "inconclusive", "control not exercised"])

    def test_not_exercised_fewer_than_three_pairs(self):
        def drop(row, grade):   # every open run but review-s01's two is degraded: 2 eligible pairs
            if row["arm"] == "a1_full_openmount" and row["task_id"] != "review-s01":
                row["status"] = "degraded"
        pc = self.pc(self.batch(open_mount={"p": 0.95, "exposed": True}, p_full=0.6, mutate=drop))
        self.assertEqual(pc["eligible_pairs"], 2)
        self.assertGreaterEqual(pc["n_exposed_open_runs"], 2)
        self.assertEqual(pc["outcome"], "not exercised")

    def test_void_by_ci90_below_zero(self):
        pc = self.pc(self.batch(open_mount={"p": 0.1, "exposed": True}, p_full=0.6))
        self.assertLess(pc["ci90_t"][1], 0)
        self.assertEqual(pc["outcome"], "void")
        self.assertEqual(pc["consequence"], "every other read void")

    def test_pass_with_two_exposures(self):
        mut = _expose_only({("review-s01", 1), ("review-s02", 2)})
        pc = self.pc(self.batch(open_mount={"p": 0.95, "exposed": True}, p_full=0.6, mutate=mut))
        self.assertEqual(pc["n_exposed_open_runs"], 2)
        self.assertGreater(pc["delta"], 0)
        self.assertEqual((pc["outcome"], pc["consequence"]), ("pass", ""))

    def test_not_demonstrated_one_exposure(self):
        mut = _expose_only({("review-s01", 1)})
        pc = self.pc(self.batch(open_mount={"p": 0.95, "exposed": True}, p_full=0.6, mutate=mut))
        self.assertEqual(pc["n_exposed_open_runs"], 1)
        self.assertGreater(pc["delta"], 0)
        self.assertEqual(pc["outcome"], "not demonstrated")
        self.assertEqual(pc["outcome_pre_addendum_10"], "pass")      # the old rule passed on one exposure
        self.assertEqual(pc["consequence"], "every other read unconfirmed by the positive control")

    def test_not_demonstrated_delta_zero(self):
        pc = self.pc(self.batch(open_mount={"p": 0.95, "exposed": True}, mutate=_same_missed()))
        self.assertEqual(pc["delta"], 0)
        self.assertEqual(pc["outcome"], "not demonstrated")
        self.assertEqual(pc["outcome_pre_addendum_10"], "inconclusive")

    def test_not_demonstrated_delta_negative_interval_covering_zero(self):
        pc = self.pc(self.batch(open_mount={"p": 0.95, "exposed": True}, mutate=_same_missed({("review-s01", 1)})))
        self.assertLess(pc["delta"], 0)
        self.assertLessEqual(pc["ci90_t"][0], 0)
        self.assertGreaterEqual(pc["ci90_t"][1], 0)
        self.assertEqual(pc["outcome"], "not demonstrated")
        self.assertEqual(pc["outcome_pre_addendum_10"], "void")      # the old rule voided on any Δ̂ < 0

    def test_every_group_included(self):
        s = self.batch(open_mount={"p": 0.95, "exposed": True}, p_full=0.6,
                       groups=[["review-s%02d" % i for i in range(1, 9)]])      # open mount on all 8 PRs
        tasks = s["tasks"]
        two = {"groups": [tasks[:6], tasks[6:]]}
        pc = self.pc(s, two)
        self.assertEqual((pc["n_prs"], pc["eligible_pairs"], pc["n_exposed_open_runs"]), (8, 16, 16))
        self.assertTrue(any("review-s07" in k for k in pc["exposed_open_runs"]))      # a groups[1] PR
        g1 = self.pc(s, {"groups": [tasks[:6]]})
        self.assertEqual((g1["n_prs"], g1["eligible_pairs"]), (6, 12))
        self.assertNotEqual(pc["delta"], g1["delta"])

    def test_pre_addendum_label_on_g1_only_fixture(self):
        # the synth open mount runs on G1 only: the old label equals the old code's outcome
        for kw, old in (({"p": 0.95, "exposed": True}, "pass"), ({"p": 0.1, "exposed": True}, "void"),
                        ({"p": 0.95, "exposed": False}, "control not exercised")):
            pc = self.pc(self.batch(sub="b-%s-%s" % (kw["p"], kw["exposed"]), open_mount=kw, p_full=0.6))
            self.assertEqual(pc["outcome_pre_addendum_10"], old, kw)


class LookCoReadsTest(Base):
    def test_co_reads_beside_an_unchanged_decision(self):
        s = self.batch()
        o = os.path.join(self.tmp, "o")
        rc, err = run(self.common_args(s) + ["--look", "1", "--out", o])
        self.assertEqual(rc, 0, err)
        doc = jload(os.path.join(o, "reads.json"))
        co = doc["co_reads"]
        self.assertEqual(set(co) - {"look"}, {"pipeline_independent", "stratified", "cost_matched"})
        self.assertEqual(co["pipeline_independent"]["status"], "ok")
        st = co["stratified"]
        n_all = sum(r["a1_full"]["defects"] for r in st["review_driven"].values())
        self.assertLess(0, co["pipeline_independent"]["n_defects"])
        self.assertLess(co["pipeline_independent"]["n_defects"], n_all)
        self.assertEqual(set(st["review_driven"]), {"true", "false"})
        self.assertEqual(set(st["label_source"]), {"incident", "fix-commit"})
        for dim in st.values():   # strata partition the look's defects per arm
            self.assertEqual(sum(r["a1_full"]["defects"] for r in dim.values()),
                             sum(r["a0_bare_matched"]["defects"] for r in dim.values()))
        cm = co["cost_matched"]
        self.assertEqual(cm["dollar_matching"]["n"], doc["looks"][0]["n_pairs"])
        self.assertEqual(cm["n_pairs_within_tolerance"], cm["dollar_matching"]["within"])
        self.assertIn("## Co-reads (§5, reported at every look)", slurp(os.path.join(o, "reads.md")))
        # the decision is the look table's, computed without the co-reads
        cells = common.load_cells(common.load_rows(s["rows"]), [s["results"]], "c132")
        reg = jload(s["registration"])
        lt = reads.look_table(cells, reg, 1, reg["seed"], reg["planned_final_se"])
        self.assertEqual(doc["looks"][0]["decision"], lt[0]["decision"])
        self.assertEqual(doc["decision"], lt[-1]["decision"])
        self.assertAlmostEqual(doc["looks"][0]["delta"], lt[0]["delta"], places=4)


CLASSES = [  # (task, trial, contamination dict) — one matched cell per class
    ("review-s01", 1, {"pattern": "outside_path"}),
    ("review-s02", 1, {"pattern": "git_history"}),
    ("review-s03", 1, {"pattern": "repo_name"}),
    ("review-s04", 1, {"pattern": "network_egress", "repo_named": True, "host": "github.com"}),
    ("review-s05", 1, {"pattern": "network_egress", "repo_named": False, "host": "github.com"}),
    ("review-s06", 1, {"pattern": "suite_path"}),
    ("review-s07", 1, {"pattern": "hidden"}),
    ("review-s08", 1, {"pattern": "something_new"}),
]


class ContaminationFamilyTest(Base):
    def batch_with_classes(self):
        def mut(row, grade):
            for task, trial, cont in CLASSES:
                if row["arm"] == "a0_bare_matched" and row["task_id"] == task and row["trial"] == trial:
                    row["contaminated"] = dict(cont)
                    row["status"] = "contaminated"
                    grade["contaminated"] = dict(cont)
            # a contaminated cell with a second invalidity never comes back
            if row["arm"] == "a0_bare_matched" and row["task_id"] == "review-s08" and row["trial"] == 2:
                row["contaminated"] = {"pattern": "outside_path"}
                row["status"] = "contaminated"
                row["oracle_exposed_defects"] = ["d1"]
        return self.batch(mutate=mut)

    def test_per_class_and_all_classes(self):
        s = self.batch_with_classes()
        o = os.path.join(self.tmp, "o")
        rc, err = run(self.common_args(s) + ["--final", "--out", o])
        self.assertEqual(rc, 0, err)
        doc = jload(os.path.join(o, "reads.json"))
        self.assertEqual(doc["primary"]["n_pairs"], 7)          # 16 pairs − 9 contaminated matched cells
        fam = doc["sensitivities"]["reads"]["contaminated_reincluded_per_class"]
        want = sorted(["outside_path", "git_history", "repo_name", "network_egress:repo", "network_egress:nonrepo",
                       "suite_path", "hidden", "something_new"])
        self.assertEqual(fam["observed"], want)
        for task, trial, cont in CLASSES:
            cls = common.contamination_detail(cont)
            r = fam["classes"][cls]
            self.assertEqual(r["n_pairs"], 8, cls)               # exactly one pair comes back per class
            self.assertEqual(r["reincluded_keys"], ["c132-g1/a0_bare_matched/%s/%d" % (task, trial)], cls)
            self.assertIn("recall_matched", r)
        # the all-classes row: all eight come back; the outside_path cell that is also oracle-exposed stays out
        self.assertEqual(fam["all_classes"]["n_pairs"], 15)
        self.assertEqual(len(fam["all_classes"]["reincluded_keys"]), 8)
        self.assertEqual(fam["counts"]["a0_bare_matched"]["G1"]["outside_path"], 1)
        self.assertEqual(fam["counts"]["a0_bare_matched"]["G2"], {"hidden": 1, "something_new": 1})
        order = doc["sensitivities"]["order"]
        self.assertEqual(order.index("contaminated_reincluded_per_class"), order.index("degraded_contaminated_excluded") + 1)
        self.assertEqual(doc["missingness"]["cells_by_arm"]["a0_bare_matched"]["excluded"]["contaminated"], 9)
        md = slurp(os.path.join(o, "reads.md"))
        self.assertIn("re-included: network_egress:nonrepo", md)
        self.assertIn("re-included: every class", md)
        self.assertIn("a0_bare_matched / G2: hidden 1, something_new 1", md)

    def test_round4_name_still_runs_its_member(self):
        s = self.batch_with_classes()
        with open(s["registration"]) as f:
            reg = json.load(f)
        reg["sensitivities"] = ["class9_nonrepo_egress_reincluded"]
        with open(s["registration"], "w") as f:
            f.write(json.dumps(reg, sort_keys=True, separators=(",", ":")))
        import hashlib
        with open(s["registration"], "rb") as f:
            h = hashlib.sha256(f.read()).hexdigest()
        rows = [json.loads(l) for l in slurp(s["rows"]).splitlines()]
        with open(s["rows"], "w") as f:
            for r in rows:
                r["registration_sha256"] = h
                f.write(json.dumps(r, sort_keys=True) + "\n")
        rc, err = run(["--rows", s["rows"], "--results-root", s["results"], "--make-inputs", "--out", s["inputs_dir"]])
        self.assertEqual(rc, 0, err)
        o = os.path.join(self.tmp, "o")
        rc, err = run(self.common_args(s) + ["--final", "--out", o])
        self.assertEqual(rc, 0, err)
        r = jload(os.path.join(o, "reads.json"))["sensitivities"]["reads"]["class9_nonrepo_egress_reincluded"]
        self.assertEqual(r["reincluded_keys"], ["c132-g1/a0_bare_matched/review-s05/1"])

    def _register(self, s, names):
        import hashlib
        with open(s["registration"]) as f:
            reg = json.load(f)
        reg["sensitivities"] = names
        with open(s["registration"], "w") as f:
            f.write(json.dumps(reg, sort_keys=True, separators=(",", ":")))
        with open(s["registration"], "rb") as f:
            h = hashlib.sha256(f.read()).hexdigest()
        rows = [json.loads(l) for l in slurp(s["rows"]).splitlines()]
        with open(s["rows"], "w") as f:
            for r in rows:
                r["registration_sha256"] = h
                f.write(json.dumps(r, sort_keys=True) + "\n")
        rc, err = run(["--rows", s["rows"], "--results-root", s["results"], "--make-inputs", "--out", s["inputs_dir"]])
        self.assertEqual(rc, 0, err)

    def test_round4_name_one_bootstrap_same_bytes_as_family_member(self):
        """round 9 (review DISS-C-002): the legacy name calls reinclude once for its class and never builds
        the family; its read is byte-identical to the family's member, and the family is unchanged"""
        s = self.batch_with_classes()
        self._register(s, ["contaminated_reincluded_per_class", "class9_nonrepo_egress_reincluded"])
        o = os.path.join(self.tmp, "both")
        rc, err = run(self.common_args(s) + ["--final", "--out", o])
        self.assertEqual(rc, 0, err)
        both = jload(os.path.join(o, "reads.json"))["sensitivities"]["reads"]
        dump = lambda v: json.dumps(v, sort_keys=True)
        self.assertEqual(dump(both["class9_nonrepo_egress_reincluded"]),
                         dump(both["contaminated_reincluded_per_class"]["classes"]["network_egress:nonrepo"]))
        self._register(s, ["class9_nonrepo_egress_reincluded"])
        calls, fam_calls = [], []
        real_re, real_fam = reads.reinclude, reads.reincluded_family
        reads.reinclude = lambda *a, **k: calls.append(a[3]) or real_re(*a, **k)
        reads.reincluded_family = lambda *a, **k: fam_calls.append(1) or real_fam(*a, **k)
        try:
            o1 = os.path.join(self.tmp, "legacy")
            rc, err = run(self.common_args(s) + ["--final", "--out", o1])
        finally:
            reads.reinclude, reads.reincluded_family = real_re, real_fam
        self.assertEqual(rc, 0, err)
        self.assertEqual((calls, fam_calls), (["network_egress:nonrepo"], []))
        legacy = jload(os.path.join(o1, "reads.json"))["sensitivities"]["reads"]["class9_nonrepo_egress_reincluded"]
        self.assertEqual(dump(legacy), dump(both["class9_nonrepo_egress_reincluded"]))

    def test_detail(self):
        d = common.contamination_detail
        self.assertEqual(d({"pattern": "network_egress", "repo_named": False}), "network_egress:nonrepo")
        self.assertEqual(d({"pattern": "network_egress", "repo_named": True}), "network_egress:repo")
        self.assertEqual(d({"pattern": "network_egress"}), "network_egress:unstated")
        self.assertEqual(d(None, {"pattern": "outside_path"}), "outside_path")
        self.assertEqual(d(None, None), "unknown")

    def test_no_contamination(self):
        s = self.batch()
        o = os.path.join(self.tmp, "o")
        rc, err = run(self.common_args(s) + ["--final", "--out", o])
        self.assertEqual(rc, 0, err)
        fam = jload(os.path.join(o, "reads.json"))["sensitivities"]["reads"]["contaminated_reincluded_per_class"]
        self.assertEqual(fam["status"], "no_contaminated_cells")
        self.assertEqual(fam["observed"], [])
        self.assertEqual(fam["oracle_exposed"]["status"], "no_oracle_exposed_cells")


ORACLE = [  # (task, by_form) on a1_full trial 1
    ("review-s01", {"diff": [], "read": ["d1"]}),
    ("review-s02", {"diff": ["d1"], "read": []}),
    ("review-s03", {"diff": ["d2"], "read": ["d1"]}),
    ("review-s04", None),                                    # exposed, no form record
]


class OracleFamilyTest(Base):
    def test_by_form(self):
        def mut(row, grade):
            if row["arm"] != "a1_full" or row["trial"] != 1:
                return
            for task, form in ORACLE:
                if row["task_id"] == task:
                    row["oracle_exposed_defects"] = ["d1"]
                    grade["oracle_exposed_defects"] = ["d1"]
                    grade["oracle_exposed_by_form"] = form
            if row["task_id"] == "review-s07":                    # exposed AND contaminated: never re-included
                row["oracle_exposed_defects"] = ["d1"]
                grade["oracle_exposed_by_form"] = {"diff": [], "read": ["d1"]}
                row["contaminated"] = {"pattern": "outside_path"}
                row["status"] = "contaminated"
        s = self.batch(mutate=mut)
        o = os.path.join(self.tmp, "o")
        rc, err = run(self.common_args(s) + ["--final", "--out", o])
        self.assertEqual(rc, 0, err)
        doc = jload(os.path.join(o, "reads.json"))
        self.assertEqual(doc["primary"]["n_pairs"], 11)
        ox = doc["sensitivities"]["reads"]["contaminated_reincluded_per_class"]["oracle_exposed"]
        self.assertEqual(ox["status"], "ok")
        self.assertEqual(ox["read_only"]["reincluded_keys"], ["c132-g1/a1_full/review-s01/1"])
        self.assertEqual(ox["read_only"]["n_pairs"], 12)
        self.assertEqual(ox["diff"]["reincluded_keys"], ["c132-g1/a1_full/review-s02/1", "c132-g1/a1_full/review-s03/1"])
        self.assertEqual(ox["diff"]["n_pairs"], 13)
        self.assertEqual(len(ox["all"]["reincluded_keys"]), 4)           # s01–s04; s07 stays out
        self.assertEqual(ox["all"]["n_pairs"], 15)
        self.assertEqual(ox["counts"]["a1_full"]["G1"],
                         {"review-s01": {"read": 1}, "review-s02": {"diff": 1}, "review-s03": {"diff": 1},
                          "review-s04": {"unknown": 1}})
        self.assertIn("recall_full", ox["all"])
        # the primary filter is unchanged and the contamination members do not pick up oracle cells
        fam = doc["sensitivities"]["reads"]["contaminated_reincluded_per_class"]
        self.assertEqual(fam["classes"]["outside_path"]["reincluded_keys"], [])
        md = slurp(os.path.join(o, "reads.md"))
        self.assertIn("re-included: oracle-exposed, read form only", md)
        self.assertIn("a1_full / G1 / review-s01: read 1", md)

    def test_form(self):
        self.assertEqual(common.oracle_form({"diff": [], "read": ["d1"]}), "read")
        self.assertEqual(common.oracle_form({"diff": ["d1"], "read": ["d1"]}), "diff")
        self.assertEqual(common.oracle_form(None), "unknown")


class PartitionTest(unittest.TestCase):
    """reads.decide — the ordered, exhaustive table (round 3; Flatline SKP-003/SKP-006).
    Arguments: delta, z_yes, b_yes, z_no, b_no, rci_hi, mde, cp_yes, cp_no, final."""

    def d(self, delta, se, b=2.5, mde=0.10, cp=(0.5, 0.5), final=False, b_no=None):
        z_yes, z_no = delta / se, (mde - delta) / se
        b_no = b if b_no is None else b_no
        return reads.decide(delta, z_yes, b, z_no, b_no, delta + b * se, mde, cp[0], cp[1], final)

    def test_rule1_negative(self):
        # a significantly negative Δ̂: |z_yes| = 4 ≥ 2.5 and Δ̂ < 0 → NEGATIVE (z_no also crosses; rule 1 wins)
        self.assertEqual(self.d(-0.20, 0.05), "NEGATIVE")
        self.assertEqual(self.d(-0.20, 0.05, final=True), "NEGATIVE")
        # a negative Δ̂ that does not cross is NO when z_no crosses (rule 4), not NEGATIVE
        self.assertEqual(self.d(-0.05, 0.05), "NO")

    def test_rule2_yes_and_its_boundary_with_small(self):
        # Δ̂ 0.30, SE 0.05: z_yes 6 crosses, z_no −4 does not, RCI upper 0.425 ≥ MDE → YES
        self.assertEqual(self.d(0.30, 0.05), "YES")
        # Δ̂ 0.13, SE 0.05 with b 2.5: z_yes 2.6 crosses; RCI upper 0.255 ≥ 0.10; z_no −0.6 → YES
        self.assertEqual(self.d(0.13, 0.05), "YES")

    def test_rule3_small(self):
        # z_yes crosses and z_no crosses: Δ̂ 0.05, SE 0.01 → z_yes 5, z_no 5 → SMALL
        self.assertEqual(self.d(0.05, 0.01), "SMALL")
        # z_yes crosses, z_no does not, but the RCI upper bound is below the MDE → SMALL
        self.assertEqual(reads.decide(0.05, 3.0, 2.5, 1.0, 2.5, 0.09, 0.10, 0.9, 0.9, False), "SMALL")
        # the edge: RCI upper exactly at the MDE is YES (≥), just below is SMALL
        self.assertEqual(reads.decide(0.05, 3.0, 2.5, 1.0, 2.5, 0.10, 0.10, 0.9, 0.9, False), "YES")
        self.assertEqual(reads.decide(0.05, 3.0, 2.5, 1.0, 2.5, 0.0999, 0.10, 0.9, 0.9, False), "SMALL")

    def test_rule4_to_6(self):
        self.assertEqual(self.d(0.0, 0.03), "NO")                                   # z_no 3.33 ≥ 2.5
        self.assertEqual(self.d(0.05, 0.05, cp=(0.1, 0.1)), "FUTILE")
        self.assertEqual(self.d(0.05, 0.05, cp=(0.5, 0.1)), "CONTINUE")
        self.assertEqual(self.d(0.05, 0.05, cp=(0.1, 0.1), final=True), "INCONCLUSIVE")

    def test_exhaustive_and_ordered(self):
        seen = set()
        for delta in (-0.3, -0.1, -0.01, 0.0, 0.01, 0.05, 0.1, 0.2, 0.4):
            for se in (0.01, 0.03, 0.06, 0.2):
                for final in (False, True):
                    for cp in ((0.1, 0.1), (0.5, 0.5)):
                        out = self.d(delta, se, cp=cp, final=final)
                        self.assertIn(out, reads.OUTCOMES)
                        seen.add(out)
                        if out == "NEGATIVE":
                            self.assertLess(delta, 0)
                        if out in ("YES", "SMALL"):
                            self.assertGreaterEqual(delta, 0)
        self.assertEqual(seen, set(reads.OUTCOMES))

    def test_legend_in_look_output(self):
        self.assertIn("NEGATIVE", reads.PARTITION_LEGEND)


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


class FinalCoReadsTest(Base):
    def test_final_carries_co_reads(self):
        """addendum 16 (iv): --final carries the §5 co-reads over every group, rendered before Missingness"""
        s = self.batch()
        o = os.path.join(self.tmp, "o")
        rc, err = run(self.common_args(s) + ["--final", "--out", o])
        self.assertEqual(rc, 0, err)
        doc = jload(os.path.join(o, "reads.json"))
        co = doc["co_reads"]
        self.assertEqual(co["look"], len(jload(s["registration"])["groups"]))
        for k in ("pipeline_independent", "stratified", "cost_matched"):
            self.assertIn(k, co)
        self.assertEqual(co["pipeline_independent"]["status"], "ok")
        self.assertEqual(co["pipeline_independent"]["delta"], doc["secondary"]["pipeline_independent"]["delta"])
        self.assertEqual(sorted(co["stratified"]), ["label_source", "review_driven"])
        self.assertIn("dollar_matching", co["cost_matched"])
        self.assertEqual(co["cost_matched"]["dollar_matching"], doc["secondary"]["dollar_matching"])
        md = slurp(os.path.join(o, "reads.md"))
        i, j, m = md.index("## Pre-registered reads"), md.index("## Co-reads"), md.index("## Missingness")
        self.assertLess(i, j)
        self.assertLess(j, m)
        self.assertEqual(md.count("## Co-reads"), 1)


class LabelSensitivityTest(Base):
    """addendum 16: review_derived_labels after v1_labels (§10 order), read from DIR/review/"""

    def test_order(self):
        o = reads.DEFAULT_SENSITIVITIES
        self.assertEqual(o[:3], ["frozen_c131_labels", "v1_labels", "review_derived_labels"])
        self.assertEqual(reads.LABEL_SENSITIVITIES["review_derived_labels"], "review")

    def test_read_from_review_dir(self):
        s = self.batch()
        sens = os.path.join(self.tmp, "sens")
        n = 0
        for dp, _ds, fs in os.walk(s["results"]):
            if "grade.json" in fs:
                rel = os.path.relpath(dp, s["results"])
                if rel.split(os.sep)[-1].startswith("review-s08"):
                    continue          # a fixture without a key in the set: no re-grade
                g = jload(os.path.join(dp, "grade.json"))
                g["label_set"] = "review"
                os.makedirs(os.path.join(sens, "review", rel))
                with open(os.path.join(sens, "review", rel, "grade.json"), "w") as f:
                    f.write(json.dumps(g))
                n += 1
        o = os.path.join(self.tmp, "o")
        rc, err = run(self.common_args(s) + ["--final", "--sensitivity-grades", sens, "--out", o])
        self.assertEqual(rc, 0, err)
        doc = jload(os.path.join(o, "reads.json"))
        sv = doc["sensitivities"]
        self.assertEqual(sv["order"][2], "review_derived_labels")
        r = sv["reads"]["review_derived_labels"]
        self.assertEqual(r["status"], "ok")
        self.assertEqual(r["label_dir"], "review")
        self.assertEqual(r["cells_regraded"], n)
        self.assertEqual(r["cells_without_regrade"], doc["inputs"]["n_rows"] - n)
        self.assertEqual(r["n_prs"], 7)                      # review-s08 has no re-grade → no defect record
        self.assertEqual(r["descriptive"]["n_prs"], 7)
        self.assertEqual(r["descriptive"]["a1_full"]["caught"], r["caught_full"])
        for name in ("frozen_c131_labels", "v1_labels"):
            self.assertEqual(sv["reads"][name], {"status": "not_provided"})
        md = slurp(os.path.join(o, "reads.md"))
        self.assertIn("| review_derived_labels (key dir `review`) | Δ ", md)
        self.assertIn("review_derived_labels: descriptive, valid pairs", md)

    def test_cost_statuses_rendered(self):
        s = self.batch()
        o = os.path.join(self.tmp, "o")
        rc, err = run(self.common_args(s) + ["--final", "--out", o])
        self.assertEqual(rc, 0, err)
        doc = jload(os.path.join(o, "reads.json"))
        for st, val in (("dominated", None), ("dominated_by_cost", None), ("ok", 2.5)):
            doc["secondary"]["cost_per_extra_defect"]["matched_valid"] = {
                "status": st, "value": val, "extra_defects": 4 if st != "dominated_by_cost" else 0,
                "cost_full": 30.0 if st != "dominated" else 10.0, "cost_baseline": 20.0}
            md = reads.render_md(doc)
            line = [x for x in md.splitlines() if x.startswith("| matched_valid |")][0]
            cells = [x.strip() for x in line.strip("|").split("|")]
            self.assertEqual(cells[-1], st)
            self.assertEqual(cells[1], "—" if val is None else "2.5000")
            self.assertEqual(cells[3], {"dominated": "-10.0000", "dominated_by_cost": "10.0000", "ok": "10.0000"}[st])
            self.assertIn("`dominated`: the full arm caught more defects for no more cost", md)



if __name__ == "__main__":
    unittest.main()
