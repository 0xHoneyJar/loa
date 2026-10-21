"""annotation_merge.py (cycle-132 Task 1.5; sdd.md §1.4 "Merge", §5.2, D-2.2): kappa, agreement measures,
the adjudication contract, cross-source dedupe, v2 label rows, determinism and the schema subset validator."""
import copy
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

ANALYSIS_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if ANALYSIS_DIR not in sys.path:
    sys.path.insert(0, ANALYSIS_DIR)
from c132 import annotation_merge as am  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "merge")
SCHEMA = os.path.join(FIXTURES, "annotation.schema.json")


def hunk(verdict, group, file, anchors, desc, sev, cat, cls=None):
    d = {"verdict": verdict, "group": group, "file": file, "anchor_lines": anchors, "description": desc,
         "severity": sev, "category": cat}
    if cls:
        d["not_defect_class"] = cls
    return d


def incident(verdict, group, file, anchors, desc, sev, cat=None):
    d = {"verdict": verdict, "group": group, "file": file, "anchor_lines": anchors, "description": desc, "severity": sev}
    if cat:
        d["category"] = cat
    return d


A_LABELS = {
    "hunks": {
        "H01": hunk("defect", "D1", "src/a.sh", [5], "the guard is dropped", "high", "logic"),
        "H02": hunk("defect", "D1", "src/a.sh", [6], "the guard's second branch", "high", "logic"),
        "H03": hunk("not-defect", None, None, [], None, None, None, cls="refactor"),
        "H04": hunk("defect", "D2", "src/b.sh", [3], "an unquoted expansion", "low", "input-validation"),
    },
    "incidents": {
        "I01": incident("defect-at-head", None, "src/a.sh", [7], "the guard crash reported later", "medium"),
        "I02": incident("not-at-head", None, None, [], None, None),
        "I03": incident("defect-at-head", None, "src/b.sh", [20], "a later failure in b", "low", "logic"),
    },
}


def disagreeing_b():
    b = copy.deepcopy(A_LABELS)
    b["hunks"]["H01"]["severity"] = "medium"                                         # severity
    b["hunks"]["H02"].update(group="D9", anchor_lines=[6, 8])                       # group + anchors
    b["hunks"]["H03"] = hunk("defect", "D3", "src/a.sh", [20], "x", "low", "logic")  # verdict
    b["hunks"]["H04"]["category"] = "logic"                                          # category
    b["incidents"]["I02"] = incident("defect-at-head", None, "src/b.sh", [10], "y", "low", "logic")  # verdict
    b["incidents"]["I03"]["anchor_lines"] = [22]                                     # anchors
    return b


def put(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def get(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def head_tree(root):
    os.makedirs(os.path.join(root, "src"))
    a = [f"a_{i}=1" for i in range(1, 31)]
    a[14] = "}"
    a[24] = "}"
    a[27] = 'token = "' + "AKIA" + "Q" * 16 + '"'   # a secret-shaped line is never copied as text
    put(os.path.join(root, "src", "a.sh"), "\n".join(a) + "\n")
    b = [f"b_{i}=2" for i in range(1, 31)]
    put(os.path.join(root, "src", "b.sh"), "\n".join(b) + "\n")


def full_adjudication():
    return {
        "H01": {"verdict": "defect", "group": "D1", "file": "src/a.sh", "anchor_lines": [5],
                "description": "the guard is dropped", "severity": "high", "category": "logic",
                "reason": "the hunk restores the guard; high as in A"},
        "H02": {"verdict": "defect", "group": "D1", "file": "src/a.sh", "anchor_lines": [6],
                "description": "the guard's second branch", "severity": "high", "category": "logic",
                "reason": "same defect as H01; line 8 is context"},
        "H03": {"verdict": "not-defect", "group": None, "file": None, "anchor_lines": [], "description": None,
                "severity": None, "category": None, "reason": "a rename only"},
        "H04": {"verdict": "defect", "group": "D2", "file": "src/b.sh", "anchor_lines": [3],
                "description": "an unquoted expansion", "severity": "low", "category": "input-validation",
                "reason": "word splitting, input-validation"},
        "I02": {"verdict": "not-at-head", "group": None, "file": None, "anchor_lines": [], "description": None,
                "severity": None, "category": None, "reason": "the issue names a later file"},
        "I03": {"verdict": "defect-at-head", "group": None, "file": "src/b.sh", "anchor_lines": [20],
                "description": "a later failure in b", "severity": "low", "category": "logic",
                "reason": "line 20 is the failing call"},
    }


class Case(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.mkdtemp(prefix="am-")
        self.head = os.path.join(self.t, "head")
        head_tree(self.head)
        self.meta = self.write("hunks.meta.json", {"H01": {"review_driven": True}, "H02": {"review_driven": False},
                                                   "H03": {"review_driven": False}, "H04": {"review_driven": False}})
        self.a = self.write("A.json", A_LABELS)

    def tearDown(self):
        shutil.rmtree(self.t)

    def write(self, name, obj):
        p = os.path.join(self.t, name)
        with open(p, "w") as f:
            json.dump(obj, f)
        return p

    def run_main(self, b, out, adj=None, extra=()):
        argv = ["--fixture", "pr-90", "--a", self.a, "--b", b, "--head-dir", self.head,
                "--hunks-meta", self.meta, "--schema", SCHEMA, "--out", out, *extra]
        if adj is not None:
            argv += ["--adjudication", adj]
        err = io.StringIO()
        with redirect_stdout(io.StringIO()), redirect_stderr(err):
            rc = am.main(argv)
        return rc, err.getvalue()

    def read(self, out, name):
        return get(os.path.join(out, name))


class KappaTest(unittest.TestCase):
    def test_textbook_two_by_two(self):
        # Cohen (1960) / the standard worked example: 20 yes-yes, 5 yes-no, 10 no-yes, 15 no-no -> 0.4
        k, po = am.cohen_kappa([[20, 5], [10, 15]])
        self.assertAlmostEqual(po, 0.7)
        self.assertAlmostEqual(k, 0.4)

    def test_perfect_and_degenerate(self):
        self.assertAlmostEqual(am.cohen_kappa([[3, 0], [0, 1]])[0], 1.0)
        self.assertIsNone(am.cohen_kappa([[4, 0], [0, 0]])[0])     # one category only: undefined
        self.assertIsNone(am.cohen_kappa([[0, 0], [0, 0]])[0])

    def test_four_category(self):
        # A: high high low medium low; B: medium high low medium low -> po 0.8, pe 0.32, kappa 0.48/0.68
        t = [[0] * 4 for _ in range(4)]
        for x, y in (("high", "medium"), ("high", "high"), ("low", "low"), ("medium", "medium"), ("low", "low")):
            t[am.SEVERITIES.index(x)][am.SEVERITIES.index(y)] += 1
        self.assertAlmostEqual(am.cohen_kappa(t)[0], 0.48 / 0.68)


class AgreementTest(Case):
    def test_no_disagreement_exit_0_kappa_written(self):
        out = os.path.join(self.t, "out")
        rc, err = self.run_main(self.write("B.json", A_LABELS), out)
        self.assertEqual(rc, 0, err)
        k = json.loads(self.read(out, "kappa.json"))
        self.assertEqual(k["hunks"]["table"], [[3, 0], [0, 1]])
        self.assertEqual(k["hunks"]["kappa"], 1.0)
        self.assertEqual(k["hunks"]["n"], 4)
        self.assertEqual(k["incidents"]["table"], [[2, 0], [0, 1]])
        self.assertEqual(k["disagreements"], 0)
        self.assertEqual(k["grouping"]["jaccard"], 1.0)
        self.assertEqual(k["localization"]["share"], 1.0)
        self.assertIn("no disagreements", self.read(out, "adjudication.md"))
        self.assertFalse(os.path.exists(os.path.join(out, "labels.rows.tsv")))

    def test_constructed_disagreements_exit_3_both_labels(self):
        out = os.path.join(self.t, "out")
        rc, err = self.run_main(self.write("B.json", disagreeing_b()), out)
        self.assertEqual(rc, 3, err)
        k = json.loads(self.read(out, "kappa.json"))
        self.assertEqual(k["hunks"]["table"], [[3, 0], [1, 0]])
        self.assertEqual(k["hunks"]["kappa"], 0.0)
        self.assertEqual(k["incidents"]["table"], [[2, 0], [1, 0]])
        self.assertAlmostEqual(k["severity"]["kappa"], round(0.48 / 0.68, 4))
        self.assertEqual(k["severity"]["n"], 5)
        self.assertEqual(k["localization"], {"n": 5, "overlap": 4, "share": 0.8, "median_distance": 0,
                                             "file_mismatch": 0})
        self.assertEqual(k["grouping"], {"pairs_a": 1, "pairs_b": 0, "pairs_both": 0, "jaccard": 0.0})
        self.assertEqual(k["disagreements"], 6)
        md = self.read(out, "adjudication.md")
        want = {"H01": ["group", "severity"], "H02": ["anchors", "group"], "H03": ["verdict"], "H04": ["category"],
                "I02": ["verdict"], "I03": ["anchors"]}
        for i, fields in want.items():
            self.assertIn(f"### {i}: " + ", ".join(fields), md)
        self.assertIn('"severity": "medium"', md)   # B's label is shown beside A's
        self.assertIn('"severity": "high"', md)
        self.assertEqual(k["disagreement_ids"], ["H01", "H02", "H03", "H04", "I02", "I03"])

    def test_identical_ids_required(self):
        b = copy.deepcopy(A_LABELS)
        del b["hunks"]["H04"]
        rc, err = self.run_main(self.write("B.json", b), os.path.join(self.t, "out"))
        self.assertEqual(rc, 1)
        self.assertIn("H04", err)

    def test_schema_violation_refused(self):
        b = copy.deepcopy(A_LABELS)
        b["hunks"]["H01"]["verdict"] = "maybe"
        rc, err = self.run_main(self.write("B.json", b), os.path.join(self.t, "out"))
        self.assertEqual(rc, 1)
        self.assertIn("hunks.H01.verdict", err)


class AdjudicationTest(Case):
    def setUp(self):
        super().setUp()
        self.b = self.write("B.json", disagreeing_b())

    def test_unresolved_refused(self):
        adj = full_adjudication()
        del adj["I03"]
        out = os.path.join(self.t, "out")
        rc, err = self.run_main(self.b, out, self.write("adj.json", adj))
        self.assertEqual(rc, 1)
        self.assertIn("I03", err)
        self.assertFalse(os.path.exists(os.path.join(out, "labels.rows.tsv")))

    def test_incomplete_record_refused(self):
        adj = full_adjudication()
        del adj["H01"]["reason"]
        rc, err = self.run_main(self.b, os.path.join(self.t, "out"), self.write("adj.json", adj))
        self.assertEqual(rc, 1)
        self.assertIn("H01", err)
        self.assertIn("reason", err)

    def test_unknown_id_refused(self):
        adj = full_adjudication()
        adj["H99"] = adj["H01"]
        rc, err = self.run_main(self.b, os.path.join(self.t, "out"), self.write("adj.json", adj))
        self.assertEqual(rc, 1)
        self.assertIn("H99", err)

    def test_anchor_validated_against_head(self):
        for bad, why in (({"anchor_lines": [31]}, "past the end"), ({"anchor_lines": [0]}, "anchor"),
                         ({"file": "../head/src/a.sh"}, "inside head"), ({"file": "src/missing.sh"}, "missing")):
            adj = full_adjudication()
            adj["H01"].update(bad)
            rc, err = self.run_main(self.b, os.path.join(self.t, "out"), self.write("adj.json", adj))
            self.assertEqual(rc, 1, (bad, err))
            self.assertIn(why, err)

    def test_multiline_reason_refused(self):
        adj = full_adjudication()
        adj["H01"]["reason"] = "line one\nline two"
        rc, err = self.run_main(self.b, os.path.join(self.t, "out"), self.write("adj.json", adj))
        self.assertEqual(rc, 1)
        self.assertIn("reason", err)

    def test_merge_dedupe_rows(self):
        out = os.path.join(self.t, "out")
        rc, err = self.run_main(self.b, out, self.write("adj.json", full_adjudication()))
        self.assertEqual(rc, 0, err)
        lines = self.read(out, "labels.rows.tsv").splitlines()
        self.assertEqual(lines[0], "# approved-by: pending")
        self.assertEqual(lines[1].split("\t"), am.HEADER_V2)
        rows = [dict(zip(am.HEADER_V2, l.split("\t"))) for l in lines[2:]]
        by = {}
        for r in rows:
            by.setdefault(r["defect_id"], []).append(r)
        self.assertEqual(sorted(by), ["V01", "V02", "V03"])
        v1 = by["V01"]   # H01 + H02 (one group) + I01 (line 7, within 3 of 6): one defect, both sources
        self.assertEqual([r["must_match"] for r in v1], ["a_5=1", "a_6=1", "a_7=1"])
        self.assertEqual({r["label_source"] for r in v1}, {"fix-commit+incident"})
        self.assertEqual({r["source"] for r in v1}, {"hunk:H01,H02;incident:I01"})
        self.assertEqual({r["agreement"] for r in v1}, {"adjudicated"})
        self.assertEqual({r["review_driven"] for r in v1}, {"true"})     # H01 is review-driven
        self.assertEqual({r["severity"] for r in v1}, {"high"})
        self.assertEqual({r["annotators"] for r in v1}, {"A,B"})
        self.assertIn("the hunk restores the guard", v1[0]["adjudication"])
        self.assertEqual([(r["file"], r["must_match"], r["label_source"], r["review_driven"]) for r in by["V02"]],
                         [("src/b.sh", "b_3=2", "fix-commit", "false")])
        self.assertEqual([(r["file"], r["must_match"], r["label_source"], r["review_driven"], r["category"])
                          for r in by["V03"]], [("src/b.sh", "b_20=2", "incident", "false", "logic")])
        result = self.read(out, "result.md")
        self.assertIn("adjudication share", result)
        self.assertIn("review-driven share", result)

    def test_agreed_items_and_at_line_rows(self):
        a = copy.deepcopy(A_LABELS)
        a["hunks"]["H01"]["anchor_lines"] = [5, 15, 28]      # `}` (not unique) and a secret-shaped line
        self.a = self.write("A.json", a)
        out = os.path.join(self.t, "out")
        rc, err = self.run_main(self.write("B2.json", a), out, self.write("adj.json", {}))
        self.assertEqual(rc, 0, err)
        rows = [l.split("\t") for l in self.read(out, "labels.rows.tsv").splitlines()[2:]]
        v1 = [r for r in rows if r[0] == "V01"]
        self.assertEqual([r[4] for r in v1], ["a_5=1", "a_6=1", "a_7=1", "@L15", "@L28"])
        self.assertEqual({r[8] for r in v1}, {"agreed"})
        self.assertEqual({r[9] for r in v1}, {"-"})
        self.assertNotIn("AKIA", self.read(out, "labels.rows.tsv"))

    def test_incident_beyond_three_lines_stays_separate(self):
        a = copy.deepcopy(A_LABELS)
        a["incidents"]["I01"].update(anchor_lines=[10], category="logic")   # 4 from line 6
        self.a = self.write("A.json", a)
        out = os.path.join(self.t, "out")
        rc, err = self.run_main(self.write("B2.json", a), out, self.write("adj.json", {}))
        self.assertEqual(rc, 0, err)
        rows = [l.split("\t") for l in self.read(out, "labels.rows.tsv").splitlines()[2:]]
        srcs = sorted({(r[0], r[5]) for r in rows})
        self.assertEqual(srcs, [("V01", "fix-commit"), ("V02", "incident"), ("V03", "fix-commit"), ("V04", "incident")])

    def test_incident_only_without_category_needs_adjudication(self):
        a = copy.deepcopy(A_LABELS)
        del a["incidents"]["I03"]["category"]
        self.a = self.write("A.json", a)
        out = os.path.join(self.t, "out")
        rc, err = self.run_main(self.write("B2.json", a), out)
        self.assertEqual(rc, 3, err)
        self.assertIn("### I03: category", self.read(out, "adjudication.md"))

    def test_fix_rows_carried(self):
        fixrows = os.path.join(self.t, "review.tsv")
        put(fixrows, "# approved-by: lead\n" + "\t".join(am.HEADER_V2[:7]) + "\n"
                                 "L01\thigh\tlogic\tsrc/a.sh\ta_5=1\treview\treview:x.md\n"
                                 "F001\t-\tfix\tsrc/a.sh\ta_5=1\tfix\tfix/abc:4-6\n")
        out = os.path.join(self.t, "out")
        rc, err = self.run_main(self.b, out, self.write("adj.json", full_adjudication()), extra=("--fix-rows", fixrows))
        self.assertEqual(rc, 0, err)
        last = self.read(out, "labels.rows.tsv").splitlines()[-1]
        self.assertEqual(last, "F001\t-\tfix\tsrc/a.sh\ta_5=1\tfix\tfix/abc:4-6\t-\t-\t-\t-")
        self.assertNotIn("L01", self.read(out, "labels.rows.tsv"))

    def test_deterministic(self):
        outs = []
        for n in (1, 2):
            out = os.path.join(self.t, f"out{n}")
            rc, err = self.run_main(self.b, out, self.write("adj.json", full_adjudication()))
            self.assertEqual(rc, 0, err)
            outs.append({f: get(os.path.join(out, f)).encode() for f in sorted(os.listdir(out))})
        self.assertEqual(outs[0], outs[1])
        self.assertEqual(sorted(outs[0]), ["adjudication.md", "kappa.json", "labels.rows.tsv", "result.md"])
        for blob in outs[0].values():
            self.assertNotIn(self.t.encode(), blob)


class PoolTest(Case):
    def test_pool_sums_tables(self):
        o1, o2 = os.path.join(self.t, "o1"), os.path.join(self.t, "o2")
        self.run_main(self.write("B.json", A_LABELS), o1)
        self.run_main(self.write("B2.json", disagreeing_b()), o2)
        pooled = os.path.join(self.t, "pooled")
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            rc = am.main(["--pool", os.path.join(o1, "kappa.json"), os.path.join(o2, "kappa.json"), "--out", pooled])
        self.assertEqual(rc, 0)
        k = json.loads(get(os.path.join(pooled, "kappa.json")))
        self.assertEqual(k["hunks"]["table"], [[6, 0], [1, 1]])
        self.assertEqual(k["fixtures"], ["pr-90", "pr-90"])
        self.assertAlmostEqual(k["hunks"]["kappa"], round(am.cohen_kappa([[6, 0], [1, 1]])[0], 4))


class ValidatorTest(unittest.TestCase):
    def test_subset(self):
        s = {"type": "object", "required": ["a"], "properties": {"a": {"$ref": "#/$defs/x"}},
             "additionalProperties": False, "$defs": {"x": {"enum": [1, 2]}}}
        self.assertEqual(am.validate(s, {"a": 1}), [])
        self.assertTrue(am.validate(s, {"a": 3}))
        self.assertTrue(am.validate(s, {"a": 1, "b": 0}))
        self.assertTrue(am.validate(s, {}))
        self.assertTrue(am.validate({"type": "integer"}, True))       # a bool is not an integer
        self.assertEqual(am.validate({"oneOf": [{"type": "string"}, {"type": "null"}]}, None), [])
        self.assertTrue(am.validate({"oneOf": [{"type": "number"}, {"type": "integer"}]}, 1))

    def test_unsupported_keyword_refused(self):
        with self.assertRaises(am.SchemaError):
            am.validate({"if": {"type": "object"}, "then": {"required": ["x"]}}, {})

    def test_shipped_review_manifest_schema_accepts_tracked_manifests(self):
        root = os.path.dirname(os.path.dirname(ANALYSIS_DIR))
        schema = json.loads(get(os.path.join(root, "evals", "harness", "schemas", "review-manifest.schema.json")))
        mdir = os.path.join(root, "evals", "fixtures", "review-prs", "manifests")
        n = 0
        for sub in ("", "c131", "v1"):
            d = os.path.join(mdir, sub)
            for f in sorted(os.listdir(d)):
                if f.endswith(".json"):
                    self.assertEqual(am.validate(schema, json.loads(get(os.path.join(d, f)))), [], f"{sub}/{f}")
                    n += 1
        self.assertGreaterEqual(n, 36)


if __name__ == "__main__":
    unittest.main()
