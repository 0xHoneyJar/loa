"""Deterministic synthetic batches for the reads / judge tests (no model, no network).

build(root, ...) writes
  root/results/<batch>/<arm>/<task>-t<n>/grade.json   (grader-1.3.2-shaped: recall.missed_pm3,
                                                        labels_meta, per_session on matched cells)
  root/rows.jsonl                                       (row-writer-1.5-shaped rows)
  root/REGISTRATION.json                                (groups, seed, constant, planned_final_se)
and returns the paths.

power_mini_diffs(out, seed=20261023) writes the power-mini head.diff fixtures (out/pr-9N/head.diff and the
preimage out/pr-9N/base/x.sh) that tests/test_power.py reads; CLI:
  python3 -I synth.py power-mini-diffs --seed 20261023 --out DIR
(bd-qxwrm: generated at test time with correct hunk headers instead of committed blobs; exit 0 written, 2 usage).
"""
import argparse
import hashlib
import json
import os
import random
import sys

ARMS = ("a1_full", "a0_bare_matched", "a0_bare_fable_matched", "a1_review_only")


def _p(rng, base):
    return min(0.98, max(0.02, base + rng.uniform(-0.1, 0.1)))


def build(root, n_prs=8, trials=2, k=4, seed=1, p_full=0.75, p_session=0.30, groups=None,
          planned_final_se=0.05, boundary_constant=1.0, batch="c132-g1", mutate=None, open_mount=None):
    """open_mount: {"p": catch probability, "exposed": bool} adds a1_full_openmount cells on G1"""
    rng = random.Random(seed)
    tasks = ["review-s%02d" % i for i in range(1, n_prs + 1)]
    if groups is None:
        groups = [tasks[:6], tasks[6:]] if n_prs > 6 else [tasks]
    reg = {"schema_version": 1, "cycle": "cycle-132-test", "seed": 20261021, "groups": groups,
           "looks": [len(sum(groups[:j + 1], [])) for j in range(len(groups))],
           "boundary_constant": boundary_constant, "mde": 0.10, "planned_final_se": planned_final_se,
           "label_set": "v2", "cap_usd": 100}
    os.makedirs(root, exist_ok=True)
    reg_path = os.path.join(root, "REGISTRATION.json")
    with open(reg_path, "w") as f:
        f.write(json.dumps(reg, sort_keys=True, separators=(",", ":")))
    with open(reg_path, "rb") as f:
        reg_sha = hashlib.sha256(f.read()).hexdigest()
    rows = []
    for ti, task in enumerate(tasks):
        n_def = 4 + (ti * 3) % 9
        ids = ["d%d" % i for i in range(1, n_def + 1)]
        meta = [{"id": d, "label_source": "incident" if j % 4 == 0 else "fix-commit",
                 "agreement": "agreed", "review_driven": j % 3 != 0} for j, d in enumerate(ids)]
        arms = ARMS + (("a1_full_openmount",) if open_mount and task in groups[0] else ())
        for arm in arms:
            for t in range(1, trials + 1):
                row = {"schema_version": 1, "run_id": "%s-%s-%s-t%d" % (batch, arm, task, t), "batch": batch,
                       "arm": arm, "task_id": task, "task_type": "review-catch", "trial": t,
                       "source_commit": "a" * 40, "status": "completed", "contaminated": None,
                       "oracle_exposed_defects": [], "degraded": False, "defects_seeded": n_def,
                       "phases": [{"name": "BARE", "refusal_fallbacks": []}], "label_set": "v2",
                       "registration_sha256": reg_sha}
                grade = {"schema_version": 1, "grader_version": "1.3.2", "label_set": "v2", "labels_meta": meta,
                         "contaminated": None, "oracle_exposed_defects": []}
                if arm.endswith("_matched"):
                    sess, union, costs = [], set(), []
                    for s in range(1, k + 1):
                        det = [d for d in ids if rng.random() < _p(rng, p_session)]
                        cost = round(rng.uniform(0.8, 1.2) * 20.0 / k, 4)
                        sess.append({"session": "s%d" % s, "detected": det, "recall": len(det) / n_def,
                                     "false_positives": 0, "cost_usd": cost, "status": "completed"})
                        union |= set(det)
                        costs.append(cost)
                    row.update(bare_sessions=k, sessions_valid=k, sessions_attempted=k, session_costs=costs,
                               cost_usd=round(sum(costs), 4), all_spend_usd=round(sum(costs), 4),
                               recall_session1=sess[0]["recall"])
                    grade.update(bare_sessions=k, sessions_valid=k, per_session=sess)
                    caught = union
                else:
                    pf = p_full if arm == "a1_full" else p_full - 0.05
                    if arm == "a1_full_openmount":
                        pf = open_mount["p"]
                        if open_mount.get("exposed"):
                            row["oracle_exposed_defects"] = ids[:1]
                    caught = {d for d in ids if rng.random() < _p(rng, pf)}
                    c = round(rng.uniform(18, 22), 4)
                    row.update(cost_usd=c, all_spend_usd=c)
                missed = [d for d in ids if d not in caught]
                row["defects_missed_pm3"] = missed
                row["defects_caught"] = n_def - len(missed)
                grade["recall"] = {"defects_seeded": n_def, "missed_pm3": missed, "recall_pm3": (n_def - len(missed)) / n_def,
                                   "missed": missed}
                if mutate:
                    mutate(row, grade)
                d = os.path.join(root, "results", batch, arm, "%s-t%d" % (task, t))
                os.makedirs(d, exist_ok=True)
                with open(os.path.join(d, "grade.json"), "w") as f:
                    f.write(json.dumps(grade, sort_keys=True))
                rows.append(row)
    rows_path = os.path.join(root, "rows.jsonl")
    with open(rows_path, "w") as f:
        for r in rows:
            f.write(json.dumps(r, sort_keys=True) + "\n")
    return {"rows": rows_path, "results": os.path.join(root, "results"), "registration": reg_path,
            "tasks": tasks, "reg_sha": reg_sha}


POWER_MINI_SEED = 20261023
POWER_MINI_PAIRS = {"pr-91": 30, "pr-92": 200, "pr-93": 750, "pr-94": 1500}   # removed/added line pairs per fixture


def power_mini_diffs(out, seed=POWER_MINI_SEED, headers="correct"):
    """the power-mini head.diff fixtures: one file x.sh, N pairs '-line 2i' / '+line 2i+1' (one hunk).
    headers="correct" declares '@@ -1,N +1,N @@' (git apply accepts it against base/x.sh);
    headers="legacy" writes the committed '@@ -1,1 +1,1 @@' so a test can prove byte-identity with the removed
    blobs. The bodies are a fixed sequence; the seed is validated and recorded, not drawn from."""
    if not isinstance(seed, int) or isinstance(seed, bool) or seed < 0:
        raise ValueError("seed must be a non-negative int")
    if headers not in ("correct", "legacy"):
        raise ValueError("headers must be correct or legacy")
    paths = {}
    for pr, n in sorted(POWER_MINI_PAIRS.items()):
        d = os.path.join(out, pr)
        os.makedirs(os.path.join(d, "base"), exist_ok=True)
        hunk = "@@ -1,1 +1,1 @@" if headers == "legacy" else "@@ -1,%d +1,%d @@" % (n, n)
        body = "".join("-line %d\n+line %d\n" % (2 * i, 2 * i + 1) for i in range(n))
        with open(os.path.join(d, "head.diff"), "w", encoding="utf-8", newline="\n") as f:
            f.write("diff --git a/x.sh b/x.sh\n--- a/x.sh\n+++ b/x.sh\n%s\n%s" % (hunk, body))
        with open(os.path.join(d, "base", "x.sh"), "w", encoding="utf-8", newline="\n") as f:
            f.write("".join("line %d\n" % (2 * i) for i in range(n)))
        paths[pr] = os.path.join(d, "head.diff")
    return paths


def main(argv=None):
    ap = argparse.ArgumentParser(prog="synth.py")
    sub = ap.add_subparsers(dest="cmd")
    pm = sub.add_parser("power-mini-diffs")
    pm.add_argument("--seed", type=int, required=True)
    pm.add_argument("--out", required=True)
    pm.add_argument("--headers", choices=("correct", "legacy"), default="correct")
    try:
        a = ap.parse_args(sys.argv[1:] if argv is None else argv)
    except SystemExit as e:
        return 2 if e.code else 0
    if a.cmd != "power-mini-diffs" or a.seed < 0:
        ap.print_usage(sys.stderr)
        return 2
    power_mini_diffs(a.out, seed=a.seed, headers=a.headers)
    return 0


if __name__ == "__main__":
    sys.exit(main())
