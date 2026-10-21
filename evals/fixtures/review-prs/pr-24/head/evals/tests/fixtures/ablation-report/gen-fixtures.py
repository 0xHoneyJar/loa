#!/usr/bin/env python3
# =============================================================================
# gen-fixtures.py — planted runs.jsonl rows and batch manifests for ablation-report.bats
#
# Usage: python3 -I gen-fixtures.py OUTDIR
# Writes OUTDIR/<scenario>/runs.jsonl and OUTDIR/<scenario>/manifests/<batch>/MANIFEST.json
# for the scenarios below. Every number is planted so the expected decision is known:
#
#   build tasks fb-01..04, bf-01..04, rf-01..04 (i = 0..11); a1_full passes 0.40 + 0.03 i on
#   every trial (3 trials), costs USD 10.00 and 1,000,000 ms per run;
#   review-catch tasks rc-01 (8 defects), rc-02 (2), rc-03 (4), rc-04 (4).
#
#   main        a0 −0.20 (H1 established); a2 −0.05 ± 0.005 (Keep); a3 0.00 at USD 8.00
#               (Remove, c −20 %); a4 −0.10 (Keep; A4 holds); a5 0.00 at USD 9.50 (Simplify);
#               a6 +0.25 / −0.35 alternating, d −0.05 (Inconclusive, wide); a7 +0.04 (Investigate);
#               an a4 review-catch row refused (infrastructure_error, not applicable);
#               a smoke batch (smoke: true) with a2 rows at 0.0 (listed, never decided)
#   boundary    a0 = a4 = a1 (H1 not established; A4 fails); a2 −0.03 at USD 8.50 (Remove:
#               d = −0.03 is not Keep, c = −15 inclusive); a5 −0.03 at USD 10 (Simplify);
#               a6 one task −0.48, d −0.04, hi = 0 (not Keep: strict) → Inconclusive;
#               a3 0.00 with wall-clock 850,000 ms (Remove on w = −15); a7 0.00 (Simplify)
#   exclusions  a2 one cap_failure on fb-01 t1 (scores 0; the sensitivity figure drops it) and a
#               transport_error on rf-01 t3; a3 a degraded fb-02 t2 at 0.0 where a1 holds 0.73
#               (dropped from both arms); a5 +0.05 on its valid cells (lo > 0) with 11 of
#               36 cells contaminated/interrupted (Inconclusive-by-degradation first, DEC-0393); a4 −0.10 plus a refused review-catch row;
#               a6 ±0.25 alternating, d 0 (Simplify by the predicates, MDE > 0.10 →
#               Inconclusive-by-power); a7 an agent_error at 0.50 on bf-01 t1 (counted) and
#               rc-01 caught d1..d4 of 8 (a1 catches every defect): the defect unit weighs
#               rc-01 eight times; rc-02 rows carry no defects_missed (rate fallback)
#   partial     a0 rows only (no a1_full): --partial has no decidable comparison (exit 1)
# =============================================================================
import json
import os
import sys

BUILD = [("fb-%02d" % k, "feature-build") for k in range(1, 5)] + \
        [("bf-%02d" % k, "bug-fix") for k in range(1, 5)] + \
        [("rf-%02d" % k, "refactor") for k in range(1, 5)]
RC = [("rc-01", 8), ("rc-02", 2), ("rc-03", 4), ("rc-04", 4)]
TRIALS = (1, 2, 3)
SRC = "1111111111111111111111111111111111111111"
SHA = "30e1f2ad" + "0" * 56
IMG = "sha256:4e37cb5f" + "0" * 56


def base(i):
    return 0.40 + 0.03 * i


def row(batch, arm, task, ttype, trial, status="completed", rate=None, catch=None, seeded=None,
        missed=None, cost=10.0, wall=1000000, degraded=False, degraded_reason=None, run_id=None,
        with_missed=True):
    rid = run_id or f"{batch}-{arm}-{task}-t{trial}"
    rc = ttype == "review-catch"
    r = {
        "schema_version": 1, "run_id": rid, "batch": batch, "arm": arm, "task_id": task, "task_type": ttype,
        "trial": trial, "source_commit": SRC, "suite_manifest_sha256": SHA, "suite_version": 1,
        "host_fingerprint": "fp:planted", "image_digest": IMG, "executor_mode": "container", "agy_opt_in": False,
        "started": "2026-10-15T00:00:00Z", "finished": "2026-10-15T00:10:00Z", "phases": [],
        "voices_run": None,
        "hidden_tests": None if rc or rate is None else {"passed": int(round(rate * 1000)), "total": 1000},
        "hidden_test_pass_rate": None if rc else rate,
        "defects_seeded": seeded if rc else None,
        "defects_caught": (None if catch is None else int(round(catch * seeded))) if rc else None,
        "defect_catch_rate": catch if rc else None,
        "flags": 3 if rc else None, "false_positives": 1 if rc else None,
        "verdict": "CHANGES_REQUIRED" if rc else "APPROVED", "verdict_accuracy": True,
        "verdict_accuracy_review": True, "verdict_accuracy_audit": True,
        "regressions": None if rc else 0, "diff_lines": None if rc else 100, "files_changed": None if rc else 2,
        "cost_usd": cost, "wall_clock_ms": wall, "tokens_in": 1000, "tokens_out": 100, "stalls": 0,
        "attempts": 1, "retry_reason": None, "degraded": degraded, "degraded_reason": degraded_reason,
        "status": status, "cap_phase": "IMPLEMENT" if status == "cap_failure" else None,
        "snapshots": {"implement": None, "fix1": None, "fix2": None}, "contaminated": None,
        "zone_violations": {"dot_claude_writes": [], "bash_mount_refs": [], "mount_changed": [],
                            "envelope_mismatch": []},
    }
    if rc and with_missed and missed is not None:
        r["defects_missed"] = missed
    return r


def rc_row(batch, arm, task, n, trial, missed, ids=True, **kw):
    return row(batch, arm, task, "review-catch", trial, catch=(n - len(missed)) / n, seeded=n,
               missed=missed, with_missed=ids, **kw)


def build_rows(batch, arm, f, cost=10.0, wall=1000000, trials=TRIALS):
    return [row(batch, arm, t, ty, k, rate=f(i, k), cost=cost, wall=wall)
            for i, (t, ty) in enumerate(BUILD) for k in trials]


A1_MISSED_MAIN = {"rc-01": ["d1", "d2"], "rc-02": [], "rc-03": ["d4"], "rc-04": ["d1"]}


def rc_rows(batch, arm, missed_map, cost=10.0, wall=1000000, ids=True):
    return [rc_row(batch, arm, t, n, k, missed_map[t], ids=ids, cost=cost, wall=wall)
            for t, n in RC for k in TRIALS]


def manifest(batch, smoke=False):
    return {"schema_version": 1, "batch": batch, "smoke": smoke, "arm_map": {}, "shuffle_seed": 20261015,
            "source_commit": SRC, "suite_manifest_sha256": SHA, "suite_version": 1,
            "pre_registration_ref": "NOTES.md § Decision Log 2026-10-15T09:00:00Z",
            "cli_version": "2.1.300 (Claude Code)", "image_digest": IMG}


def main_scenario():
    b = "priority-1"
    rows = []
    rows += build_rows(b, "a1_full", lambda i, k: base(i))
    rows += rc_rows(b, "a1_full", A1_MISSED_MAIN)
    rows += build_rows(b, "a0_bare", lambda i, k: base(i) - 0.20, cost=2.0)
    rows += rc_rows(b, "a0_bare", {t: ["d%d" % j for j in range(2, n + 1)] for t, n in RC}, cost=2.0)
    rows += build_rows(b, "a2_no_sprint_plan", lambda i, k: base(i) - 0.05 + (i % 3 - 1) * 0.005)
    rows += build_rows(b, "a3_one_voice", lambda i, k: base(i), cost=8.0)
    rows += rc_rows(b, "a3_one_voice", A1_MISSED_MAIN, cost=8.0)
    rows += build_rows(b, "a4_no_gates", lambda i, k: base(i) - 0.10, cost=3.0)
    rows.append(row(b, "a4_no_gates", "rc-01", "review-catch", 1, status="infrastructure_error", cost=0, wall=0))
    rows += build_rows(b, "a5_no_flatline", lambda i, k: base(i), cost=9.5)
    rows += build_rows(b, "a6_one_window", lambda i, k: base(i) + (0.25 if i % 2 == 0 else -0.35))
    rows += build_rows(b, "a7_effort_medium", lambda i, k: base(i) + 0.04)
    rows += rc_rows(b, "a7_effort_medium", A1_MISSED_MAIN)
    s = "smoke-260"
    rows += build_rows(s, "a2_no_sprint_plan", lambda i, k: 0.0, trials=(1,))
    rows += build_rows(s, "a1_full", lambda i, k: 1.0, trials=(1,))
    mans = {b: manifest(b), s: manifest(s, smoke=True)}
    m = mans[b]
    m["arm_map"] = {r["run_id"]: r["arm"] for r in rows if r["batch"] == b}
    return rows, mans


def boundary_scenario():
    b = "boundary-1"
    rows = []
    rows += build_rows(b, "a1_full", lambda i, k: base(i))
    rows += rc_rows(b, "a1_full", A1_MISSED_MAIN)
    rows += build_rows(b, "a0_bare", lambda i, k: base(i))
    rows += rc_rows(b, "a0_bare", A1_MISSED_MAIN)
    rows += build_rows(b, "a4_no_gates", lambda i, k: base(i))
    rows += build_rows(b, "a2_no_sprint_plan", lambda i, k: base(i) - 0.03, cost=8.5)
    rows += build_rows(b, "a5_no_flatline", lambda i, k: base(i) - 0.03)
    rows += build_rows(b, "a6_one_window", lambda i, k: base(i) - (0.48 if i == 11 else 0.0))
    rows += build_rows(b, "a3_one_voice", lambda i, k: base(i), wall=850000)
    rows += rc_rows(b, "a3_one_voice", A1_MISSED_MAIN, wall=850000)
    rows += build_rows(b, "a7_effort_medium", lambda i, k: base(i))
    rows += rc_rows(b, "a7_effort_medium", A1_MISSED_MAIN)
    return rows, {b: manifest(b)}


def exclusions_scenario():
    b = "excl-1"
    rows = []
    a1 = lambda i, k: 0.73 if (i == 1 and k == 2) else base(i)  # noqa: E731
    none = {t: [] for t, _ in RC}
    rows += build_rows(b, "a1_full", a1)
    rows += [r for r in rc_rows(b, "a1_full", none) if r["task_id"] != "rc-02"]
    rows += [rc_row(b, "a1_full", "rc-02", 2, k, [], ids=False) for k in TRIALS]
    rows += build_rows(b, "a0_bare", lambda i, k: a1(i, k) - 0.20)
    rows += rc_rows(b, "a0_bare", {t: ["d1"] for t, _ in RC})
    a2 = build_rows(b, "a2_no_sprint_plan", a1)
    for r in a2:
        if r["task_id"] == "fb-01" and r["trial"] == 1:
            r["status"], r["cap_phase"], r["cost_usd"] = "cap_failure", "IMPLEMENT", 12.0
            r["hidden_test_pass_rate"], r["hidden_tests"] = 0.9, {"passed": 900, "total": 1000}
        if r["task_id"] == "rf-01" and r["trial"] == 3:
            r["status"] = "transport_error"
    rows += a2
    a3 = build_rows(b, "a3_one_voice", lambda i, k: base(i))
    for r in a3:
        if r["task_id"] == "fb-02" and r["trial"] == 2:
            r["hidden_test_pass_rate"], r["hidden_tests"] = 0.0, {"passed": 0, "total": 1000}
            r["degraded"], r["degraded_reason"] = True, "IMPLEMENT models_used global.anthropic.claude-sonnet-5-5"
    rows += a3
    rows += [r for r in rc_rows(b, "a3_one_voice", none) if r["task_id"] != "rc-02"]
    rows += [rc_row(b, "a3_one_voice", "rc-02", 2, k, [], ids=False) for k in TRIALS]
    rows += build_rows(b, "a4_no_gates", lambda i, k: a1(i, k) - 0.10)
    rows.append(row(b, "a4_no_gates", "rc-02", "review-catch", 1, status="infrastructure_error", cost=0, wall=0))
    a5 = build_rows(b, "a5_no_flatline", lambda i, k: a1(i, k) + 0.05)
    for n, r in enumerate(a5[:11]):
        r["status"] = "contaminated" if n % 2 == 0 else "interrupted"
        if r["status"] == "contaminated":
            r["contaminated"] = {"phase": "IMPLEMENT", "pattern": "planted"}
    rows += a5
    rows += build_rows(b, "a6_one_window", lambda i, k: a1(i, k) + (0.25 if i % 2 == 0 else -0.25))
    a7 = build_rows(b, "a7_effort_medium", a1)
    for r in a7:
        if r["task_id"] == "bf-01" and r["trial"] == 1:
            r["status"], r["hidden_test_pass_rate"] = "agent_error", 0.5
            r["hidden_tests"] = {"passed": 500, "total": 1000}
    rows += a7
    a7rc = {"rc-01": ["d5", "d6", "d7", "d8"], "rc-03": [], "rc-04": []}
    rows += [rc_row(b, "a7_effort_medium", t, n, k, a7rc[t]) for t, n in RC if t != "rc-02" for k in TRIALS]
    rows += [rc_row(b, "a7_effort_medium", "rc-02", 2, k, [], ids=False) for k in TRIALS]
    return rows, {b: manifest(b)}


def partial_scenario():
    b = "priority-0"
    rows = build_rows(b, "a0_bare", lambda i, k: base(i), trials=(1,))
    return rows, {b: manifest(b)}


def write(out, name, rows, mans):
    d = os.path.join(out, name)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "runs.jsonl"), "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r, sort_keys=True) + "\n")
    for b, m in mans.items():
        md = os.path.join(d, "manifests", b)
        os.makedirs(md, exist_ok=True)
        with open(os.path.join(md, "MANIFEST.json"), "w", encoding="utf-8") as fh:
            json.dump(m, fh, indent=2, sort_keys=True)
            fh.write("\n")


def main(argv):
    if len(argv) != 1:
        sys.stderr.write("usage: gen-fixtures.py OUTDIR\n")
        return 2
    for name, fn in (("main", main_scenario), ("boundary", boundary_scenario),
                     ("exclusions", exclusions_scenario), ("partial", partial_scenario)):
        rows, mans = fn()
        write(argv[0], name, rows, mans)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
