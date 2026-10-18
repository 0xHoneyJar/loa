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
#
# Sprint 262 (suite_version partition, read states, degradation guard on H1/A4, degenerate pairs):
#   versions      batch ver-v1 (suite_version 1): a1/a0/a4 build rows as in main (H1 +0.20,
#                 A4 −0.10 holds) and a1/a0 review rows; batch ver-v2 (suite_version 2, its own
#                 manifest sha ddd200b3…): a1/a0 on the SAME review task ids and trials, a1 misses
#                 nothing, a0 misses d1, d2 everywhere (catch d = 8/18 = +0.444, H1 established on
#                 the catch rate); v2 has no build task (pass rate and A4 not testable)
#   degraded      batch deg-v2 (suite_version 2): a0/a1 on rc-01..04 × 3 with ids; a1 misses
#                 nothing, a0 misses d1, d2; 9 of 12 a1 rows degraded (rc-01..03), rc-04 valid →
#                 a1 excluded share 0.750 (H1 inconclusive by degradation); with --exclude-degraded
#                 false the same rows establish H1
#   degraded-a4   batch deg-a4 (suite_version 1): build rows only, a1 base, a0 −0.20, a4 −0.10;
#                 a1's fb-01..04 (12 of 36 cells) degraded → share 0.333 on both H1's pass rate and
#                 A4 (both inconclusive by degradation); with false, H1 established, A4 holds
#   degenerate-1  batch dg-1 (suite_version 2): a0/a1/a3 on rc-04 only, rows without
#                 defects_missed (rate fallback); a1 1.0, a0 0.5, a3 0.75 → one task, zero variance:
#                 degenerate (H1 not yet decidable; a3 inconclusive, no valid pair)
#   degenerate-2  the same on rc-03 and rc-04 (a0 rc-03 0.75): two tasks → not degenerate, H1 established
#   degenerate-ids  degenerate-1 with defects_missed on every row → not degenerate (ids decide)
#
# Sprint 262 R3 (presentation: sensitivity H1/A4 lines, batch record, precision, budget-matched):
#   present       batch pr-2 (suite_version 2), review rows only: a0_bare (USD 1.00 per run, 1 false
#                 positive per row) on rc-01 (8 defects) t1 misses d1..d4, t2 misses d5..d8, t3 misses
#                 all → union catches all 8 (1.000) though no trial beats 0.500; on rc-02 (2) rows
#                 without defects_missed at 0.5 → "rate fallback" (0.500); a1_full (USD 10.00, 0
#                 false positives) rc-01 misses d1 each trial (0.875), rc-02 misses nothing (1.000);
#                 a3_one_voice rc-01/rc-02 catches nothing with 0 false positives (precision and cost
#                 per true defect null). a0 precision 11 / 17 = 0.647059, USD 6 / 11 = 0.545455; a1
#                 precision 1.0, USD 60 / 27 = 2.222222. Budget-matched: a0 union mean 0.75, a1 mean
#                 0.9375; "3 a0_bare trials cost USD 3.00 vs one a1_full trial USD 10.00".
#                 manifests/pr-2/STATUS.json holds rerowed (2 completed→completed, 1 contaminated→
#                 cap_failure), rerun (1 transport_error→completed), drift_cleared 1, outage_history 2,
#                 extra_models, a cut and a paused arm; run dirs a0_bare/rc-01-t1 (grade.json grader
#                 1.2.5), rc-01-t2-r2 (1.2.11), rc-01-t3 (no grade.json). Batch pr-1 (suite_version 1,
#                 build rows of a0/a1 only, no STATUS.json, no run dirs): the budget-matched section of
#                 suite_version 1 reads "not available".
#
# Sprint 262 R4 (report 1.2.1: version keys, the batch-record grader tally, version-less listed rows):
#   graders       batch gr-mixed (suite_version 2): a1_full rc-01 t1..t3 with run dirs rc-01-t1 (grader
#                 1.2.0), rc-01-t2 (1.2.0-rc1), rc-01-t3 (no grade.json) → tally 1.2.0 ×1, 1.2.0-rc1 ×1,
#                 n/a ×1 (1.2.0 aborted on the mixed int/str sort key); batch gr-rerun: a0_bare rc-01 t1
#                 with rc-01-t1 (meta/pipeline.json run_id = the row's, interrupted, no grade), rc-01-t1-r2
#                 (the same run_id, grader 1.2.11) and rc-01-t1-r3 (another run_id, grader 9.9.9) → the
#                 row reads r2 once: 1.2.11 ×1, run_dirs_missing 0; batch gr-missing: a0_bare rc-01 t2
#                 with no run dir → n/a ×1, run_dirs_missing 1
#   versions-float  batch vf-2 (suite_version 2) and vf-21 (suite_version 2.1, a float): a1/a0 on the
#                 review tasks as in versions' v2 (a0 misses d1, d2); vf-21's a0 misses d1 only → the two
#                 versions are never pooled, keys "2" and "2.1", 2.1 primary
#   legacy        the versions scenario plus version-less rows that never reach a decision: a smoke batch
#                 leg-smoke (manifest suite_version null) with an a1_full row and an unbatched row (batch
#                 leg-loose, no manifest) → listed under the primary version 2 as "no suite_version; …"
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
SHA2 = "ddd200b3" + "0" * 56
IMG = "sha256:4e37cb5f" + "0" * 56


def base(i):
    return 0.40 + 0.03 * i


def row(batch, arm, task, ttype, trial, status="completed", rate=None, catch=None, seeded=None,
        missed=None, cost=10.0, wall=1000000, degraded=False, degraded_reason=None, run_id=None,
        with_missed=True, sv=1, sha=SHA):
    rid = run_id or f"{batch}-{arm}-{task}-t{trial}"
    rc = ttype == "review-catch"
    r = {
        "schema_version": 1, "run_id": rid, "batch": batch, "arm": arm, "task_id": task, "task_type": ttype,
        "trial": trial, "source_commit": SRC, "suite_manifest_sha256": sha, "suite_version": sv,
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


def build_rows(batch, arm, f, cost=10.0, wall=1000000, trials=TRIALS, **kw):
    return [row(batch, arm, t, ty, k, rate=f(i, k), cost=cost, wall=wall, **kw)
            for i, (t, ty) in enumerate(BUILD) for k in trials]


A1_MISSED_MAIN = {"rc-01": ["d1", "d2"], "rc-02": [], "rc-03": ["d4"], "rc-04": ["d1"]}


def rc_rows(batch, arm, missed_map, cost=10.0, wall=1000000, ids=True, **kw):
    return [rc_row(batch, arm, t, n, k, missed_map[t], ids=ids, cost=cost, wall=wall, **kw)
            for t, n in RC for k in TRIALS]


def manifest(batch, smoke=False, sv=1, sha=SHA):
    return {"schema_version": 1, "batch": batch, "smoke": smoke, "arm_map": {}, "shuffle_seed": 20261015,
            "source_commit": SRC, "suite_manifest_sha256": sha, "suite_version": sv,
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


V2 = {"sv": 2, "sha": SHA2}
A0_MISS_D12 = {t: ["d1", "d2"] for t, _ in RC}
NONE = {t: [] for t, _ in RC}


def versions_scenario():
    b1, b2 = "ver-v1", "ver-v2"
    rows = []
    rows += build_rows(b1, "a1_full", lambda i, k: base(i))
    rows += rc_rows(b1, "a1_full", A1_MISSED_MAIN)
    rows += build_rows(b1, "a0_bare", lambda i, k: base(i) - 0.20, cost=2.0)
    rows += rc_rows(b1, "a0_bare", {t: ["d%d" % j for j in range(2, n + 1)] for t, n in RC}, cost=2.0)
    rows += build_rows(b1, "a4_no_gates", lambda i, k: base(i) - 0.10, cost=3.0)
    rows += rc_rows(b2, "a1_full", NONE, **V2)
    rows += rc_rows(b2, "a0_bare", A0_MISS_D12, cost=1.0, **V2)
    return rows, {b1: manifest(b1), b2: manifest(b2, **V2)}


def degraded_scenario():
    b = "deg-v2"
    rows = rc_rows(b, "a0_bare", A0_MISS_D12, cost=1.0, **V2)
    a1 = rc_rows(b, "a1_full", NONE, **V2)
    for r in a1:
        if r["task_id"] != "rc-04":
            r["degraded"] = True
            r["degraded_reason"] = "review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed"
    return rows + a1, {b: manifest(b, **V2)}


def degraded_a4_scenario():
    b = "deg-a4"
    a1 = build_rows(b, "a1_full", lambda i, k: base(i))
    for r in a1:
        if r["task_id"].startswith("fb-"):
            r["degraded"], r["degraded_reason"] = True, "IMPLEMENT models_used planted"
    rows = a1 + build_rows(b, "a0_bare", lambda i, k: base(i) - 0.20, cost=2.0) + \
        build_rows(b, "a4_no_gates", lambda i, k: base(i) - 0.10, cost=3.0)
    return rows, {b: manifest(b)}


def degenerate_scenario(batch, tasks, ids):
    def f():
        rows = []
        for t, n in RC:
            if t not in tasks:
                continue
            a0_miss = ["d1"] if t == "rc-03" else ["d1", "d2"]
            for k in TRIALS:
                rows.append(rc_row(batch, "a1_full", t, n, k, [], ids=ids, **V2))
                rows.append(rc_row(batch, "a0_bare", t, n, k, a0_miss, ids=ids, cost=1.0, **V2))
                rows.append(rc_row(batch, "a3_one_voice", t, n, k, ["d1"], ids=ids, **V2))
        return rows, {batch: manifest(batch, **V2)}
    return f


def present_scenario():
    b2, b1 = "pr-2", "pr-1"
    rows = []
    a0 = {"rc-01": (["d1", "d2", "d3", "d4"], ["d5", "d6", "d7", "d8"], ["d%d" % j for j in range(1, 9)])}
    for k in TRIALS:
        rows.append(rc_row(b2, "a0_bare", "rc-01", 8, k, a0["rc-01"][k - 1], cost=1.0, **V2))
        rows.append(rc_row(b2, "a0_bare", "rc-02", 2, k, ["d2"], ids=False, cost=1.0, **V2))
        for r in (rc_row(b2, "a1_full", "rc-01", 8, k, ["d1"], **V2), rc_row(b2, "a1_full", "rc-02", 2, k, [], **V2),
                  rc_row(b2, "a3_one_voice", "rc-01", 8, k, ["d%d" % j for j in range(1, 9)], **V2),
                  rc_row(b2, "a3_one_voice", "rc-02", 2, k, ["d1", "d2"], **V2)):
            r["false_positives"] = 0
            rows.append(r)
    rows += build_rows(b1, "a1_full", lambda i, k: base(i))
    rows += build_rows(b1, "a0_bare", lambda i, k: base(i) - 0.20, cost=2.0)
    status = {"schema_version": 1, "batch": b2, "state": "complete", "trials_planned": 20,
              "spend": {"rows_usd": 69.0, "ledger_usd": 1.5, "spent_usd": 70.5, "max_usd": 100},
              "extra_models": {"global.anthropic.claude-haiku-4-5-20251001-v1:0": {"runs": 2, "output_tokens": 900}},
              "rerowed": [{"run_id": "x1", "from": "completed", "to": "completed"},
                          {"run_id": "x2", "from": "contaminated", "to": "cap_failure"},
                          {"run_id": "x3", "from": "completed", "to": "completed"}],
              "rerun": [{"run_id": "x4", "from": "transport_error", "to": "completed", "old_cost_usd": 0}],
              "drift_cleared": [{"run_id": "x5"}], "outage_history": [{"at": "a"}, {"at": "b"}],
              "cuts": [{"reason": "max_usd", "at_trial": 19, "spent": 99.5, "max": 100}],
              "paused_arms": {"a3_one_voice": "took_effect miss"}}
    extras = {f"{b2}/STATUS.json": status,
              f"{b2}/a0_bare/rc-01-t1/grade.json": {"grader_version": "1.2.5"},
              f"{b2}/a0_bare/rc-01-t2-r2/grade.json": {"grader_version": "1.2.11"},
              f"{b2}/a0_bare/rc-01-t3": None}
    return rows, {b2: manifest(b2, **V2), b1: manifest(b1)}, extras


def graders_scenario():
    bm, br, bx = "gr-mixed", "gr-rerun", "gr-missing"
    rows = [rc_row(bm, "a1_full", "rc-01", 8, k, [], **V2) for k in TRIALS]
    rows.append(rc_row(br, "a0_bare", "rc-01", 8, 1, ["d1", "d2"], cost=1.0, **V2))
    rows.append(rc_row(bx, "a0_bare", "rc-01", 8, 2, ["d1", "d2"], cost=1.0, **V2))
    rid = f"{br}-a0_bare-rc-01-t1"
    extras = {f"{bm}/a1_full/rc-01-t1/grade.json": {"grader_version": "1.2.0"},
              f"{bm}/a1_full/rc-01-t2/grade.json": {"grader_version": "1.2.0-rc1"},
              f"{bm}/a1_full/rc-01-t3": None,
              f"{br}/a0_bare/rc-01-t1/meta/pipeline.json": {"run_id": rid, "status": "interrupted"},
              f"{br}/a0_bare/rc-01-t1-r2/meta/pipeline.json": {"run_id": rid, "status": "completed"},
              f"{br}/a0_bare/rc-01-t1-r2/grade.json": {"grader_version": "1.2.11"},
              f"{br}/a0_bare/rc-01-t1-r3/meta/pipeline.json": {"run_id": "another-run", "status": "completed"},
              f"{br}/a0_bare/rc-01-t1-r3/grade.json": {"grader_version": "9.9.9"}}
    return rows, {bm: manifest(bm, **V2), br: manifest(br, **V2), bx: manifest(bx, **V2)}, extras


def versions_float_scenario():
    b2, b21 = "vf-2", "vf-21"
    v21 = {"sv": 2.1, "sha": SHA2}
    rows = rc_rows(b2, "a1_full", NONE, **V2) + rc_rows(b2, "a0_bare", A0_MISS_D12, cost=1.0, **V2)
    rows += rc_rows(b21, "a1_full", NONE, **v21)
    rows += rc_rows(b21, "a0_bare", {t: ["d1"] for t, _ in RC}, cost=1.0, **v21)
    return rows, {b2: manifest(b2, **V2), b21: manifest(b21, **v21)}


def legacy_scenario():
    rows, mans = versions_scenario()
    smoke = row("leg-smoke", "a1_full", "fb-01", "feature-build", 1, rate=0.5, sv=None)
    loose = row("leg-loose", "a0_bare", "fb-01", "feature-build", 1, rate=0.5, sv=None)
    mans = dict(mans)
    mans["leg-smoke"] = manifest("leg-smoke", smoke=True, sv=None)
    return rows + [smoke, loose], mans


def write(out, name, rows, mans, extras=None):
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
    for rel, data in sorted((extras or {}).items()):
        path = os.path.join(d, "manifests", rel)
        if data is None:
            os.makedirs(path, exist_ok=True)
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2, sort_keys=True)
            fh.write("\n")


def main(argv):
    if len(argv) != 1:
        sys.stderr.write("usage: gen-fixtures.py OUTDIR\n")
        return 2
    for name, fn in (("main", main_scenario), ("boundary", boundary_scenario),
                     ("exclusions", exclusions_scenario), ("partial", partial_scenario),
                     ("versions", versions_scenario), ("degraded", degraded_scenario),
                     ("degraded-a4", degraded_a4_scenario),
                     ("degenerate-1", degenerate_scenario("dg-1", ("rc-04",), False)),
                     ("degenerate-2", degenerate_scenario("dg-2", ("rc-03", "rc-04"), False)),
                     ("degenerate-ids", degenerate_scenario("dg-ids", ("rc-04",), True)),
                     ("present", present_scenario), ("graders", graders_scenario),
                     ("versions-float", versions_float_scenario), ("legacy", legacy_scenario)):
        write(argv[0], name, *fn())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
