"""reads-c131.py — cycle-131 Sprint 265 reads (python3 -I, stdlib): the pre-registered interval reads R1, R5, R3, R4 over the Sprint 264
batch rows, with the decision statistic defect_catch_rate_pm3 (DEC-0638), defect-level paired bootstrap (10,000, 90 %), a cluster
bootstrap by PR (descriptive), the pre-registered validity filters and labelled sensitivities, and catch per USD.
usage: reads-c131.py --rows F [--rows F …] --batches-root DIR --manifests DIR --pin SHA [--out report.md] [--json report.json] [--seed N]"""
import argparse, json, os, random, re, statistics, sys

TASK_PR = {"review-r17": "pr-17", "review-r18": "pr-18"}
B = 10000
LEVEL = 0.90

def load_rows(files, pin):
    rows = []
    for f in files:
        for line in open(f, encoding="utf-8"):
            line = line.strip()
            if not line: continue
            r = json.loads(line)
            if not str(r.get("batch", "")).startswith("c131-") and not str(r.get("run_id", "")).startswith("c131-"): continue
            sc = str(r.get("source_commit") or "")
            ok = bool(re.fullmatch(r"[0-9a-f]{12,40}", sc)) and bool(re.fullmatch(r"[0-9a-f]{12,40}", pin)) and (sc.startswith(pin) or pin.startswith(sc))
            r["_pin_ok"] = ok
            if not ok:
                LOAD_NOTES.append(f"pin check rejected {r.get('run_id')}: source_commit {sc!r} vs pin {pin[:12]} (audit DISS-C-003)")
            rows.append(r)
    return rows

LOAD_NOTES = []   # every grade or transcript that could not be read is named here and in the report (review DISS-C-002/C-003)
SAFE = re.compile(r"^[A-Za-z0-9_.-]+$")
def run_dir(r, root):
    """<root>/<batch>/<arm>/<task>-t<n>, every component validated and the result confined to root (audit DISS-C-002)"""
    parts = [str(r.get("batch", "")), str(r.get("arm", "")), str(r.get("run_id", "")).split(f"-{r.get('arm', '')}-", 1)[-1]]
    if not all(SAFE.fullmatch(x) for x in parts):
        raise ValueError("unsafe path component")
    d = os.path.realpath(os.path.join(root, *parts))
    if os.path.commonpath([os.path.realpath(root), d]) != os.path.realpath(root):
        raise ValueError("path escapes the batches root")
    return d

def grade_of(r, root):
    try:
        p = os.path.join(run_dir(r, root), "grade.json")
        return json.load(open(p))
    except Exception as e:
        LOAD_NOTES.append(f"grade.json unreadable for {r.get('run_id')}: {type(e).__name__}")
        return None

def caught_set(r, n):
    """grade.json and the row name defects by POSITION d1..dN in the current manifest (row writer 1.4 / grader 1.3.0), never
    by id; n is the manifest's defect count (review DISS-C-004)"""
    missed = r.get("defects_missed_pm3")
    if not isinstance(missed, list): return None
    universe = {f"d{i}" for i in range(1, n + 1)}
    stray = [m for m in missed if m not in universe]
    if stray:   # a missed id outside the positional universe would otherwise count as caught (review DISS-C-004)
        LOAD_NOTES.append(f"defects_missed_pm3 outside d1..d{n} for {r.get('run_id')}: {stray}")
        return None
    return universe - set(missed)

def valid(r, g, mode, root=None):
    """mode: main | diff_only (oracle exclusion by diff form only) | strict (drop degraded and dissent-absent rows) |
    s3 (contaminated rows whose only hit is a scratch-directory outside_path re-included)"""
    if not r["_pin_ok"]: return False
    if mode == "s3" and r.get("status") == "contaminated" and s3_eligible(r, g, root):
        pass
    elif r.get("status") != "completed" or r.get("contaminated") is not None: return False
    if r["arm"] != "a1_full_openmount":
        exposed = r.get("oracle_exposed_defects") or []
        if mode == "diff_only" and g is not None:
            exposed = (g.get("oracle_exposed_by_form") or {}).get("diff") or []
        if exposed: return False
    if mode == "strict":   # a planned absence (dissent_absent_reason disabled — the a1_no_dissent arm) is not a degradation (review DISS-C-007)
        if r.get("degraded"): return False
        reasons = r.get("dissent_absent_reason") or {}
        if any(reasons.get(gt) not in (None, "none", "disabled") for gt in (r.get("dissent_absent_gates") or [])): return False
        vr = r.get("voices_run") or {}
        if any((vr.get(gt) or {}).get("completed") == 0 for gt in ("review", "audit")): return False
    return True

import re as _re
# the declared S3 shapes, anchored to a path start (review DISS-C-006): $HOME/tmp/…, ~/tmp/…, /home/<user>/tmp/…, /tmp/…, mktemp
SCRATCH_RE = _re.compile(r'(?:^|[\s"\'=:(])(?:\$HOME|\$\{HOME\}|~|/home/[A-Za-z0-9_.-]+)/tmp/|(?:^|[\s"\'=:(])/tmp/|\$\(mktemp\b|\bmktemp\s+-d\b')
def s3_eligible(r, g, root):
    """S3 (NOTES 2026-10-20T05:41:08Z): a contaminated row whose only recorded hit is an outside_path write under a scratch
    directory, with no repo-name, hidden, suite-path or git-history token in the excerpt's command — re-included in the S3
    sensitivity only; classification by pattern and path shape, never by the row's catch. Limit (review DISS-C-006): the
    grader stops at the first contamination hit and records only that one, so 'only recorded hit' is all this can test;
    a second hit later in the same run would be invisible here as it is in grade.json."""
    c = (g or {}).get("contaminated") or r.get("contaminated")
    if not isinstance(c, dict) or c.get("pattern") != "outside_path": return False
    try:
        phase, line = c["excerpt_id"].split(":"); n = int(line)
        if phase not in ("BARE", "REVIEW", "AUDIT", "PLAN", "IMPLEMENT", "FIX"):
            LOAD_NOTES.append(f"S3: unknown phase {phase!r} for {r.get('run_id')}"); return False
        with open(os.path.join(run_dir(r, root), "transcripts", f"events-{phase}.jsonl"), encoding="utf-8", errors="replace") as f:
            for i, ln in enumerate(f, 1):
                if i == n:
                    ev = json.loads(ln); break
            else:
                LOAD_NOTES.append(f"S3: excerpt line {n} not found for {r.get('run_id')}"); return False
        cmds = [b.get("input", {}).get("command", "") for b in (ev.get("message") or {}).get("content", []) if isinstance(b, dict) and b.get("type") == "tool_use"]
        txt = "\n".join(c_ for c_ in cmds if isinstance(c_, str))
    except Exception as e:
        LOAD_NOTES.append(f"S3: transcript unreadable for {r.get('run_id')}: {type(e).__name__}"); return False
    low = txt.lower()
    # the command is model-authored text: the test is word-level over its tokens, fail-closed on anything that reaches the
    # network, the upstream repository, the hidden suite or git history, and the scratch shape must be an anchored path
    # (bare `mktemp` is not enough); every S3 re-inclusion is named in the load notes (audit DISS-C-001)
    try:
        import shlex
        words = [w.lower() for w in shlex.split(txt, comments=False, posix=True)]
    except ValueError:
        words = low.split()
    NET = {"curl", "wget", "gh", "fetch", "pip", "pip3", "npm", "npx", "pnpm", "yarn", "ssh", "scp", "nc", "ncat", "rsync", "docker", "podman", "aria2c"}
    GIT_HIST = {"log", "show", "reflog", "rev-list", "clone", "fetch", "pull", "remote", "ls-remote", "diff"}
    base = [w.rsplit("/", 1)[-1] for w in words]
    for i, b in enumerate(base):
        if b in NET: return False
        if b == "git" and any(x in GIT_HIST for x in base[i + 1:i + 4]): return False
    if re.search(r"0x\W*honeyjar\W*/+\W*loa", low) or "hidden" in low or "grimoires/loa/evals/ablation-2.0" in low or "://" in low: return False
    m = SCRATCH_RE.search(txt)
    if m is None: return False
    LOAD_NOTES.append(f"S3 re-included {r.get('run_id')} (pattern outside_path at {c.get('excerpt_id')}; scratch shape {m.group(0).strip()!r})")
    return True

def fallback(r):
    """a refusal fallback in any phase (KF-051). The pre-registration excludes exactly these rows from R5; other causes of
    `degraded` (failed voices) stay in the main read and are handled by the strict sensitivity, so `degraded` alone is not
    an R5 exclusion (review DISS-C-005: documented wording refers to fallback rows)"""
    return any((ph.get("refusal_fallbacks") or []) for ph in (r.get("phases") or []))

def per_defect(rows_arm, task, n):
    """probability of catch per defect over the arm's valid trials on the task; None when no trial"""
    sets = [caught_set(r, n) for r in rows_arm if r["task_id"] == task]
    sets = [s for s in sets if s is not None]
    if not sets: return None, 0
    return {f"d{i}": sum(1 for s in sets if f"d{i}" in s) / len(sets) for i in range(1, n + 1)}, len(sets)

def contrast(rowsA, rowsB, tasks, nmap, seed, min_cells=4):
    """min_cells: 4 = the pre-registered rule; 3 = the trial-level sensitivity (the planned trials per cell)"""
    defects, cells = [], {}
    for t in tasks:
        pa, ka = per_defect(rowsA, t, nmap[t]); pb, kb = per_defect(rowsB, t, nmap[t])
        cells[t] = (ka, kb)
        if pa is None or pb is None: continue
        for d in sorted(pa, key=lambda x: int(x[1:])):
            defects.append((t, d, pa[d], pb[d]))
    if not defects: return {"insufficient": True, "cells": cells, "n_defects": 0}
    # valid cells of a contrast = Σ over its tasks of min(valid trials A, valid trials B) (report 1.3 semantics); the
    # pre-registered threshold is min_valid_cells 4 — a single-task contrast with 3 planned trials per arm is therefore
    # "insufficient" by construction under the rule as written (DEC-0650); the trial-level sensitivity uses 3
    n_cells = sum(min(cells[t]) for t in tasks)
    insufficient = n_cells < min_cells or len(defects) == 0
    rnd = random.Random(seed)
    diffs = [a - b for _, _, a, b in defects]
    point = statistics.fmean(diffs)
    boots = []
    for _ in range(B):
        samp = [diffs[rnd.randrange(len(diffs))] for _ in diffs]
        boots.append(statistics.fmean(samp))
    boots.sort(); lo, hi = boots[int(len(boots) * (1 - LEVEL) / 2)], boots[int(len(boots) * (1 - (1 - LEVEL) / 2)) - 1]
    # cluster bootstrap by PR (descriptive)
    by_pr = {}
    for t, d, a, b in defects: by_pr.setdefault(t, []).append(a - b)
    prs = list(by_pr)
    cl = []
    for _ in range(B):
        picked = [prs[rnd.randrange(len(prs))] for _ in prs]
        vals = [x for p in picked for x in by_pr[p]]
        cl.append(statistics.fmean(vals))
    cl.sort(); clo, chi = cl[int(len(cl) * 0.05)], cl[int(len(cl) * 0.95) - 1]
    rateA = statistics.fmean(a for _, _, a, _ in defects); rateB = statistics.fmean(b for _, _, _, b in defects)
    return {"insufficient": insufficient, "cells": cells, "n_cells": n_cells, "n_defects": len(defects), "rate_a": round(rateA, 4), "rate_b": round(rateB, 4),
            "delta": round(point, 4), "ci90": [round(lo, 4), round(hi, 4)], "cluster_ci90": [round(clo, 4), round(chi, 4)]}

def cost(rows_arm, tasks):
    rs = [r for r in rows_arm if r["task_id"] in tasks and r.get("cost_usd") is not None]
    return round(statistics.fmean(r["cost_usd"] for r in rs), 2) if rs else None

def outcome(read, c, costA=None, costB=None):
    if c.get("insufficient") or not c.get("ci90"): return "insufficient"
    lo, hi = c["ci90"]
    if read == "R1":
        return "inflated" if lo > 0.05 else ("no measurable inflation" if lo >= -0.05 and hi <= 0.05 else "investigate")
    if read == "R3":
        ratio = (costA / costB) if (costA and costB) else None
        if lo >= -0.05 and hi <= 0.05 and ratio is not None and ratio <= 0.6: return "propose audit-gate opt-in"
        if hi < -0.10: return "keep"
        return "inconclusive"
    if read == "R4":
        if lo >= -0.08 and hi <= 0.08: return "propose dissent opt-in"
        if hi < -0.08: return "keep (the dissent earns its cost)"
        if lo > 0.08: return "investigate"
        return "inconclusive"
    return "?"

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--rows", action="append", required=True); ap.add_argument("--batches-root", required=True)
    ap.add_argument("--manifests", required=True); ap.add_argument("--pin", required=True); ap.add_argument("--out"); ap.add_argument("--json"); ap.add_argument("--seed", type=int, default=20261015)
    a = ap.parse_args()
    rows = load_rows(a.rows, a.pin)
    nmap = {t: len(json.load(open(os.path.join(a.manifests, pr + ".json")))["defects"]) for t, pr in TASK_PR.items()}
    grades = {r["run_id"]: grade_of(r, a.batches_root) for r in rows}
    out = {"pin": a.pin, "rows": len(rows), "statistic": "defect_catch_rate_pm3", "reads": {}, "sensitivities": {}}
    L = []
    L.append(f"# cycle-131 reads — pin `{a.pin}` — {len(rows)} c131 rows — statistic `defect_catch_rate_pm3` (DEC-0638; pre-registration DEC-0648)\n")
    def arm_rows(arm, mode, excl_fallback=False):
        return [r for r in rows if r["arm"] == arm and valid(r, grades.get(r["run_id"]), mode, a.batches_root) and not (excl_fallback and fallback(r))]
    specs = [("R1", "a1_full_openmount", "a1_full", ["review-r17"], False),
             ("R5a", "a0_bare_fable", "a1_full", ["review-r17", "review-r18"], True),
             ("R5b", "a0_bare_fable", "a0_bare", ["review-r17", "review-r18"], True),
             ("R3", "a1_review_only", "a1_full", ["review-r17"], False),
             ("R4", "a1_no_dissent", "a1_full", ["review-r17"], False)]
    for mode in ("main", "trial_level", "diff_only", "strict", "s3"):
        out["sensitivities"][mode] = {}
        title = {"main": "Main read (min_valid_cells 4 as pre-registered)", "trial_level": "Sensitivity: trial level (min 3 valid trials per side, the planned count; DEC-0650)", "diff_only": "Sensitivity: oracle exclusion by the diff form only", "strict": "Sensitivity: degraded rows and unplanned dissent absences excluded (a disabled gate is planned)", "s3": "Sensitivity S3: scratch-directory outside_path contaminations re-included (NOTES 2026-10-20T05:41:08Z; min 3 trials)"}[mode]
        L.append(f"\n## {title}\n")
        L.append("| read | contrast | PRs | defects | cells A/B (Σ) | rate A | rate B | Δ | 90 % defect CI | cluster CI (PR) | USD/run A | USD/run B | outcome |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|")
        for read, A_, B_, tasks, exfb in specs:
            ra, rb = arm_rows(A_, "main" if mode == "trial_level" else mode, exfb), arm_rows(B_, "main" if mode == "trial_level" else mode, exfb)
            c = contrast(ra, rb, tasks, nmap, a.seed, min_cells=3 if mode in ("trial_level", "s3") else 4); ca, cb = cost(ra, tasks), cost(rb, tasks)
            if read in ("R5a", "R5b"):   # insufficient is tested first (review DISS-C-001); the band test only on a sufficient contrast
                oc = "insufficient" if (c.get("insufficient") or not c.get("ci90")) else ("within ±0.05" if c["ci90"][0] >= -0.05 and c["ci90"][1] <= 0.05 else "outside ±0.05")
            else:
                oc = outcome(read[:2], c, ca, cb)
            cells = " ".join(f"{t.split('-')[-1]}:{c['cells'][t][0]}/{c['cells'][t][1]}" for t in tasks) + f" (Σ{c.get('n_cells', 0)})"
            L.append(f"| {read} | {A_} − {B_} | {', '.join(TASK_PR[t] for t in tasks)} | {c.get('n_defects', 0)} | {cells} | {c.get('rate_a', '-')} | {c.get('rate_b', '-')} | {c.get('delta', '-')} | {c.get('ci90', '-')} | {c.get('cluster_ci90', '-')} | {ca} | {cb} | {oc} |")
            (out["reads"] if mode == "main" else out["sensitivities"][mode])[read] = {"a": A_, "b": B_, "tasks": tasks, **c, "usd_a": ca, "usd_b": cb, "outcome": oc}
        if mode == "main":
            r5 = out["reads"]; both = r5["R5a"]["outcome"] == "within ±0.05", r5["R5b"]["outcome"] == "within ±0.05"
            r5o = "the model explains the lift" if both[0] and not both[1] else ("the gates earn their cost" if both[1] and not both[0] else ("between (both intervals reported)" if not any(x == "insufficient" for x in (r5["R5a"]["outcome"], r5["R5b"]["outcome"])) else "insufficient"))
            out["reads"]["R5"] = {"outcome": r5o}; L.append(f"\nR5 outcome: **{r5o}** (R5a bare-Fable vs full: {r5['R5a']['outcome']}; R5b bare-Fable vs bare: {r5['R5b']['outcome']}).")
    # row inventory
    L.append("\n## Row inventory\n\n| arm | task | rows | completed | main-valid | S3-eligible | degraded | fallback | oracle-exposed | USD |\n|---|---|---|---|---|---|---|---|---|---|")
    for arm in sorted({r["arm"] for r in rows}):
        for t in sorted({r["task_id"] for r in rows if r["arm"] == arm}):
            rs = [r for r in rows if r["arm"] == arm and r["task_id"] == t]
            L.append(f"| {arm} | {t} | {len(rs)} | {sum(1 for r in rs if r['status']=='completed')} | {sum(1 for r in rs if valid(r, grades.get(r['run_id']), 'main', a.batches_root))} | {sum(1 for r in rs if r.get('status')=='contaminated' and s3_eligible(r, grades.get(r['run_id']), a.batches_root))} | {sum(1 for r in rs if r.get('degraded'))} | {sum(1 for r in rs if fallback(r))} | {sum(1 for r in rs if r.get('oracle_exposed_defects'))} | {round(sum(r.get('cost_usd') or 0 for r in rs), 2)} |")
    notes = list(dict.fromkeys(LOAD_NOTES))   # one line per distinct note (the sensitivities re-classify the same rows)
    L.append(f"\nGrades loaded: {sum(1 for g in grades.values() if g)} of {len(rows)} rows; load notes: {len(notes)}" + ("".join(f"\n- {n}" for n in notes) if notes else " (none)"))
    out["grades_loaded"] = sum(1 for g in grades.values() if g); out["load_notes"] = notes
    text = "\n".join(L) + "\n"
    if a.out: open(a.out, "w", encoding="utf-8").write(text)
    else: sys.stdout.write(text)
    if a.json: json.dump(out, open(a.json, "w"), indent=1)

if __name__ == "__main__":
    main()
