"""common.py — rows, grades, cell keys, the validity filter and the input manifest.

sdd.md §5.2 `reads-c132.py` (validity, pairing, D-7.3, D-7.5), §3.2 rows/grade entities.

A *cell* is one rowed run (or one matched cell of k sessions): the row, its grade.json (when
the run directory is found under a results root) and the derived fields
    key            "<batch>/<arm>/<task>/<trial>" (unique; duplicates refused)
    pr             the task id (the PR × trial pairing unit)
    pair_trial     the trial's rank among the arm × task cells ordered by (batch, trial),
                   so cells of one arm and task from two batches never collide
    defect_ids     d1 … d<defects_seeded>; caught_ids = defect_ids − missed (the decision
                   statistic's missed set: row defects_missed_pm3 → grade recall.missed_pm3 →
                   row defects_missed → grade recall.missed)
    cost           row cost_usd (a matched cell: its valid sessions); all_spend: row
                   all_spend_usd, else cost_usd
    matched        a row with an integer bare_sessions k ≥ 2 (row writer 1.5)
    valid, reasons the validity filter below

Validity (sdd.md §5.2; rules "c132", or "c131" without the oracle_exposed clause): status completed; every took-effect rule true (row `took_effect`:
"pass"/true/{rule: true…}; absent = not recorded, counted); contaminated null on the row and the
grade; oracle_exposed_defects empty except on a1_full_openmount; no refusal_fallbacks in any
phase of a non-matched cell; a matched cell needs sessions_valid ≥ ⌈k/2⌉ (D-7.3).
"""
import hashlib
import json
import math
import os

OPEN_MOUNT_ARMS = ("a1_full_openmount",)


class InputError(Exception):
    """an input that must stop the read before any output (exit 1)"""


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def cell_key(row):
    return "%s/%s/%s/%s" % (row.get("batch"), row.get("arm"), row.get("task_id"), row.get("trial"))


def load_rows(path):
    rows, seen = [], set()
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except ValueError as e:
                raise InputError("%s:%d: not JSON (%s)" % (path, n, e))
            if not isinstance(r, dict):
                raise InputError("%s:%d: not an object" % (path, n))
            k = cell_key(r)
            if k in seen:
                raise InputError("duplicate cell key %s (%s:%d)" % (k, path, n))
            seen.add(k)
            rows.append(r)
    return rows


def run_dir_for(row, results_roots):
    """<root>/<batch>/<arm>/<task>-t<trial>, or its highest -r<k> sibling (a re-run's fresh
    directory — run-ablation.sh run_dir_of), under the first root that holds either; else None"""
    for root in results_roots or []:
        parent = os.path.join(root, str(row.get("batch")), str(row.get("arm")))
        base = "%s-t%s" % (row.get("task_id"), row.get("trial"))
        if not os.path.isdir(parent):
            continue
        best, top = None, 1
        p = os.path.join(parent, base)
        if os.path.isdir(p) and not os.path.islink(p):
            best = p
        for name in sorted(os.listdir(parent)):
            if not name.startswith(base + "-r"):
                continue
            k = name[len(base) + 2:]
            q = os.path.join(parent, name)
            if k.isdigit() and int(k) > top and os.path.isdir(q) and not os.path.islink(q):
                top, best = int(k), q
        if best:
            return best
    return None


def load_grade(run_dir):
    if not run_dir:
        return None, None
    p = os.path.join(run_dir, "grade.json")
    if not os.path.isfile(p) or os.path.islink(p):
        return None, None
    with open(p, encoding="utf-8") as f:
        try:
            return json.load(f), p
        except ValueError:
            raise InputError("grade.json is not JSON: %s" % p)


def _missed(row, grade):
    rec = (grade or {}).get("recall") or {}
    for src, v in (("row.defects_missed_pm3", row.get("defects_missed_pm3")),
                   ("grade.recall.missed_pm3", rec.get("missed_pm3")),
                   ("row.defects_missed", row.get("defects_missed")),
                   ("grade.recall.missed", rec.get("missed"))):
        if isinstance(v, list) and all(isinstance(x, str) and x for x in v):
            return list(v), src
    return None, None


def _n_defects(row, grade):
    n = row.get("defects_seeded")
    if isinstance(n, int) and not isinstance(n, bool):
        return n
    rec = (grade or {}).get("recall") or {}
    n = rec.get("defects_seeded")
    if isinstance(n, int) and not isinstance(n, bool):
        return n
    return None


def _took_effect_ok(v):
    if v is None:
        return True, "not_recorded"
    if v is True or v == "pass":
        return True, "pass"
    if isinstance(v, dict) and v and all(x is True or x == "pass" for x in v.values()):
        return True, "pass"
    return False, "fail"


def is_matched_row(row):
    k = row.get("bare_sessions")
    return isinstance(k, int) and not isinstance(k, bool) and k >= 2


def labels_meta_map(grade, defect_ids):
    """{defect id: {label_source, agreement, review_driven}} from grade.json labels_meta[]
    (by each entry's `defect` — grader 1.3.2 — or `id`, else by position d1 … dN)"""
    meta = (grade or {}).get("labels_meta")
    out = {}
    if isinstance(meta, list):
        # keyed entries first; the positional fallback only fills ids no entry names
        for m in meta:
            if isinstance(m, dict):
                did = next((m[k] for k in ("defect", "id") if isinstance(m.get(k), str) and m[k]), None)
                if did:
                    out[did] = m
        for i, m in enumerate(meta):
            if isinstance(m, dict) and not any(isinstance(m.get(k), str) and m[k] for k in ("defect", "id")):
                if i < len(defect_ids):
                    out.setdefault(defect_ids[i], m)
    elif isinstance(meta, dict):
        out = {k: v for k, v in meta.items() if isinstance(v, dict)}
    return out


VALIDITY_RULES = ("c132", "c131")


def build_cell(row, grade, run_dir=None, grade_path=None, rules="c132"):
    n = _n_defects(row, grade)
    missed, src = _missed(row, grade)
    ids = ["d%d" % i for i in range(1, n + 1)] if n is not None else []
    caught_ids = sorted(set(ids) - set(missed or []), key=lambda d: int(d[1:])) if missed is not None else None
    matched = is_matched_row(row)
    k = row.get("bare_sessions") if matched else None
    cost = row.get("cost_usd")
    cost = float(cost) if isinstance(cost, (int, float)) and not isinstance(cost, bool) else None
    alls = row.get("all_spend_usd")
    alls = float(alls) if isinstance(alls, (int, float)) and not isinstance(alls, bool) else cost
    c = {
        "key": cell_key(row), "batch": row.get("batch"), "arm": row.get("arm"),
        "task": row.get("task_id"), "pr": row.get("task_id"), "trial": row.get("trial"),
        "row": row, "grade": grade, "run_dir": run_dir, "grade_path": grade_path,
        "defect_ids": ids, "defects": n, "caught_ids": caught_ids,
        "caught": len(caught_ids) if caught_ids is not None else None,
        "statistic_source": src, "cost": cost, "all_spend": alls, "matched": matched, "k": k,
        "sessions_valid": row.get("sessions_valid") if matched else None,
        "sessions_attempted": row.get("sessions_attempted") if matched else None,
        "per_session": (grade or {}).get("per_session") if matched else None,
        "labels_meta": labels_meta_map(grade, ids),
    }
    c["valid"], c["reasons"], c["took_effect"] = validity(c, rules)
    c["session1"] = session1(c)
    return c


def validity(c, rules="c132"):
    """rules "c132" (sdd.md §5.2) or "c131" (round 1: the cycle-131 rules for the Phase 0 placebo
    on the 63 existing rows — no oracle_exposed filter, since every cycle-130 a1_full ran under
    the open mount; every other clause unchanged)"""
    if rules not in VALIDITY_RULES:
        raise ValueError("validity rules must be c132 or c131")
    row, grade = c["row"], c["grade"] or {}
    reasons = []
    if row.get("status") != "completed":
        reasons.append("status:%s" % row.get("status"))
    te_ok, te = _took_effect_ok(row.get("took_effect"))
    if not te_ok:
        reasons.append("took_effect")
    if row.get("contaminated") is not None or grade.get("contaminated") is not None:
        reasons.append("contaminated")
    if c["arm"] not in OPEN_MOUNT_ARMS and rules == "c132":
        ox = row.get("oracle_exposed_defects")
        if ox is None:
            ox = grade.get("oracle_exposed_defects")
        if ox:
            reasons.append("oracle_exposed")
    if not c["matched"]:
        for ph in row.get("phases") or []:
            if isinstance(ph, dict) and ph.get("refusal_fallbacks"):
                reasons.append("refusal_fallbacks")
                break
    else:
        k, sv = c["k"], c["sessions_valid"]
        if not isinstance(sv, int) or sv < int(math.ceil(k / 2.0)):
            reasons.append("sessions_valid<ceil(k/2)")
    if c["caught_ids"] is None or c["defects"] is None:
        reasons.append("no_defect_record")
    elif c["defects"] == 0:
        reasons.append("no_labelled_defects")
    return (not reasons), reasons, te


def session_detected(s):
    """a per_session entry's detected ids under the decision statistic: `detected_pm3` (grader
    1.3.2 union grade; DEC-0638 recall_pm3), else `detected` — the rule the union side uses"""
    det = s.get("detected_pm3")
    if isinstance(det, list):
        return det
    det = s.get("detected")
    return det if isinstance(det, list) else None


def session1(c):
    """BARE-1 alone on a matched cell: {caught, cost} from grade per_session[0] (detected list
    or recall × defects) else the row's recall_session1 × defects and session_costs[0]"""
    if not c["matched"]:
        return None
    caught = cost = None
    ps = c["per_session"]
    if isinstance(ps, list) and ps and isinstance(ps[0], dict):
        s = ps[0]
        if s.get("status") not in (None, "completed", "valid"):
            return None
        det = session_detected(s)
        if isinstance(det, list):
            caught = len(set(det) & set(c["defect_ids"]))
        elif isinstance(s.get("recall"), (int, float)) and c["defects"]:
            caught = round(s["recall"] * c["defects"])
        if isinstance(s.get("cost_usd"), (int, float)):
            cost = float(s["cost_usd"])
    if caught is None:
        r1 = c["row"].get("recall_session1")
        if isinstance(r1, (int, float)) and c["defects"]:
            caught = round(r1 * c["defects"])
    if cost is None:
        sc = c["row"].get("session_costs")
        if isinstance(sc, list) and sc:
            first = sc[0]
            if isinstance(first, dict):
                first = first.get("cost_usd")
            if isinstance(first, (int, float)):
                cost = float(first)
    if caught is None:
        return None
    return {"caught": caught, "cost": cost}


def load_cells(rows, results_roots, rules="c132"):
    cells = []
    for r in rows:
        rd = run_dir_for(r, results_roots)
        g, gp = load_grade(rd)
        cells.append(build_cell(r, g, rd, gp, rules))
    assign_pair_trials(cells)
    return cells


def assign_pair_trials(cells):
    by = {}
    for c in cells:
        by.setdefault((c["arm"], c["task"]), []).append(c)
    for group in by.values():
        group.sort(key=lambda c: (str(c["batch"]), c["trial"] if isinstance(c["trial"], int) else 0))
        for i, c in enumerate(group, 1):
            c["pair_trial"] = i


def side(c, caught=None, cost=None, restrict=None):
    """the pair-side dict stats.py consumes; `restrict` limits the defect universe to a set of
    ids (the pipeline-independent read)"""
    ids = c["defect_ids"] if restrict is None else [d for d in c["defect_ids"] if d in restrict]
    got = c["caught_ids"] if restrict is None else [d for d in c["caught_ids"] if d in restrict]
    out = {"caught": len(got) if caught is None else caught, "defects": len(ids),
           "cost": c["cost"] if cost is None else cost, "key": c["key"],
           "caught_ids": got, "defect_ids": ids}
    if c.get("session1") is not None:
        out["session1"] = c["session1"]
    return out


def make_pairs(cells, arm_a, arm_b, tasks=None, valid_only=True, restrict_fn=None):
    """PR × trial pairs between arm_a ("full" side) and arm_b ("matched" side); pairwise
    exclusion — a pair enters only when both cells are valid. Returns (pairs, lost) where lost
    lists the pair keys missing a side or holding an invalid one."""
    a = {(c["task"], c["pair_trial"]): c for c in cells if c["arm"] == arm_a}
    b = {(c["task"], c["pair_trial"]): c for c in cells if c["arm"] == arm_b}
    pairs, lost = [], []
    for key in sorted(set(a) | set(b), key=lambda k: (str(k[0]), k[1])):
        if tasks is not None and key[0] not in tasks:
            continue
        ca, cb = a.get(key), b.get(key)
        if ca is None or cb is None or (valid_only and not (ca["valid"] and cb["valid"])):
            lost.append({"pr": key[0], "trial": key[1],
                         "a": None if ca is None else (ca["key"], ca["valid"], ca["reasons"]),
                         "b": None if cb is None else (cb["key"], cb["valid"], cb["reasons"])})
            continue
        if ca["defects"] != cb["defects"]:
            raise InputError("pair %s/%s: the arms disagree on the defect count (%s vs %s)"
                             % (key[0], key[1], ca["defects"], cb["defects"]))
        restrict = restrict_fn(ca, cb) if restrict_fn else None
        pairs.append({"pr": key[0], "trial": key[1], "full": side(ca, restrict=restrict),
                      "matched": side(cb, restrict=restrict)})
    return pairs, lost


# ---------------------------------------------------------------- input manifest (D-7.5)
def make_inputs(rows_path, rows, cells, pin=None, label_set=None, planned=None, task_fixture=None):
    """the INPUTS.json document for the current rows + run dirs (the lead freezes it)"""
    cm = {}
    for c in cells:
        sessions = None
        if c["matched"] and isinstance(c["per_session"], list):
            sessions = sorted(str(s.get("session")) for s in c["per_session"] if isinstance(s, dict))
        cm[c["key"]] = {"grade_sha256": sha256_file(c["grade_path"]) if c["grade_path"] else None,
                        "sessions": sessions}
    return {"schema_version": 1, "rows_sha256": sha256_file(rows_path), "rows_count": len(rows),
            "pin": pin, "label_set": label_set, "cells": cm,
            "planned_cells": sorted(planned) if planned is not None else sorted(cm),
            "task_fixture": task_fixture or {}}


def validate_inputs(inputs, rows_path, rows, cells):
    """every mismatch between INPUTS.json and what is on disk → InputError (D-7.5)"""
    errs = []
    if inputs.get("schema_version") != 1:
        errs.append("INPUTS.json schema_version is not 1")
    if inputs.get("rows_sha256") != sha256_file(rows_path):
        errs.append("rows file sha256 differs from INPUTS.json")
    want = inputs.get("cells") or {}
    have = {c["key"]: c for c in cells}
    for k in sorted(set(want) - set(have)):
        errs.append("expected cell missing from the rows: %s" % k)
    for k in sorted(set(have) - set(want)):
        errs.append("row not in INPUTS.json: %s" % k)
    planned = set(inputs.get("planned_cells") or [])
    if planned and not set(have) <= planned:
        errs.append("rows outside planned_cells: %s" % ", ".join(sorted(set(have) - planned)))
    pin = inputs.get("pin")
    ls = inputs.get("label_set")
    for k in sorted(set(want) & set(have)):
        c, w = have[k], want[k]
        g_sha = sha256_file(c["grade_path"]) if c["grade_path"] else None
        if g_sha != w.get("grade_sha256"):
            errs.append("grade.json sha256 differs for %s" % k)
        if pin and c["row"].get("source_commit") != pin:
            errs.append("pin differs for %s (%s)" % (k, c["row"].get("source_commit")))
        if ls:
            for where, v in (("row", c["row"].get("label_set")), ("grade", (c["grade"] or {}).get("label_set"))):
                if v is not None and v != ls:
                    errs.append("label_set %s=%s differs from %s for %s" % (where, v, ls, k))
        if c["matched"]:
            sessions = None
            if isinstance(c["per_session"], list):
                sessions = sorted(str(s.get("session")) for s in c["per_session"] if isinstance(s, dict))
            if sessions != w.get("sessions"):
                errs.append("session membership differs for %s" % k)
    if errs:
        raise InputError("; ".join(errs))


def validate_registration(reg_path, rows):
    """every row's registration_sha256 equals sha256(REGISTRATION.json) (D-7.2)"""
    h = sha256_file(reg_path)
    bad = sorted(cell_key(r) for r in rows if r.get("registration_sha256") != h)
    if bad:
        raise InputError("registration_sha256 differs from %s on %d row(s): %s"
                         % (h[:12], len(bad), ", ".join(bad[:5])))
    return h


def load_json(path, what):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        raise InputError("%s unreadable: %s (%s)" % (what, path, e))
