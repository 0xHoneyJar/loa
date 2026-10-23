#!/usr/bin/env python3
"""regrade_labels.py — the label-set re-grades behind the cycle-132 label sensitivities.

PREREGISTRATION §10 items 1–2 (frozen cycle-131 labels, v1 labels, the seeded review-derived key),
analysis addendum 16, DEC-0809. Stdlib only; no model calls. reads.py --sensitivity-grades OUT reads
what this writes (sensitivities frozen_c131_labels, v1_labels, review_derived_labels).

Usage:
  python3 -I evals/analysis/c132/regrade_labels.py --rows F --results-root DIR --suite-root R
      --labels c131,v1,review --out DIR [--work DIR] [--roots DIR] [--only TASK …] [--jobs N]
      [--force] [--dry-run] [--check] [--seed N] [--grader PATH] [--image IMG] [--repo-root DIR]

Label sets and keys. A label names directories under the task key's manifests/ directory (the
directory of each task's review_catch.manifest in R/tasks/<task>/task.yaml), tried in order:
  c131    manifests/c131/<pr>.json     (the frozen cycle-131 set: pr-11, 14, 15, 16 in this corpus)
  v1      manifests/v1/<pr>.json       (the original anchors: the same four)
  review  manifests/review/<pr>.json, else manifests/c131/<pr>.json (the seeded review-derived key:
          review/ for pr-19 … pr-28; for the four older fixtures the seeder documents c131/ as the moved
          review-derived set — evals/harness/seed-corpus-from-record.sh)
The key file is looked up under the grader's repository (--repo-root, default three levels above the
grader), the first place ablation-grade.sh looks. The grader derives grade.json label_set from the
key's directory, so every grade must carry the directory its task's key came from (c131 for the four
older fixtures under `review`); any other value refuses the label (exit 1, no INDEX.json).

Suite roots (the choice: re-freeze, never --allow-unfrozen). For each label, ROOTS/<label>/ is a
fresh copy of R with review_catch.manifest re-pointed for every task that has a key in the set
(other tasks unchanged), frozen with freeze.sh --allow-partial (the freeze.sh beside the grader).
Every grade is then taken under a frozen root (grade.json suite_frozen true) and
OUT/<label>/INDEX.json records the root's MANIFEST.sha256 digest and every re-pointed task;
OUT/<label>/MANIFEST.sha256 is a copy of the root's manifest. WORK/<label>/SUITE-ROOT.sha256 pins
the digest the work tree was graded under: a later run whose root digest differs is refused
unless --force.

Re-grade (DEC-0809: never grade a recorded run directory — the grader rewrites <run-dir>/grading/
even with --out). For each label and each row cell (the row's run directory under DIR, highest
-r<k> sibling as reads.py finds it) whose task has a key in the set:
  1. WORK/<label>/<batch>/<arm>/<task>-t<trial>/ = a hard-link copy (cp -al per entry, same
     filesystem) of the cell without its grading/ and grade.json; for a matched cell also without
     each sessions/<dir>/grading/ and grade.json. Nothing in the record is opened for writing.
  2. matched cell: every session cell.json lists is graded in the copy
     (ablation-grade.sh <copy>/<run_dir> <task> --suite-root ROOTS/<label> --out <copy>/<run_dir>/grade.json
     --allow-partial --executor container --image IMG); a session cell.json marks invalid may fail
     to grade (recorded, not fatal). Then ablation-grade.sh --union <copy> --task-id <task> … --out
     <copy>/grade.json. Non-matched cell: one grade, --out <copy>/grade.json.
  3. OUT/<label>/<batch>/<arm>/<task>-t<trial>/grade.json, and for a matched cell
     OUT/…/<run_dir>/grade.json per graded session (normally sessions/s<i>/grade.json).
A copy that already holds its cell grade.json is not re-graded (resumable, idempotent; --force
re-copies and re-grades). Cells whose task has no key in the set are listed in INDEX.json
cells_without_key (reads.py builds them with grade None, the registered behaviour).

OUT/<label>/INDEX.json (sorted keys, no timestamps, no absolute paths): label, key_dirs, keys
{task: {manifest, sha256, label_set}}, suite_root {frozen, manifest_sha256, source_manifest_sha256,
repointed}, grader_version (one across every grade, else refused), label_sets_observed {set: n},
cells [{key, batch, arm, task, trial, fixture, matched, grade, grade_sha256, label_set, recall_pm3,
sessions [{id, run_dir, valid, grade, grade_sha256, error}]}], cells_without_key, n_cells,
n_sessions (matched sessions graded), only. The refusals run on the work copies before OUT is
written; a run that fails leaves the label without INDEX.json.

--check: a seeded sample (--seed, default 20261021) of 3 cells over every label's INDEX.json is
re-graded from scratch into a temporary directory under WORK (same roots, the digests must equal
the INDEX's) and every grade.json is compared byte for byte with OUT, and grading/gates-combined.md
with the work copy's; the result goes to stdout and OUT/CHECK.json (pass or fail).
--dry-run: the plan on stdout, nothing written.

Refusals before any write (exit 1): unreadable rows; a task without task.yaml or a single
review_catch manifest; a key path outside manifests/; a row whose run directory is missing; a
matched cell without a readable meta/cell.json or with a session run_dir outside sessions/;
OUT, WORK or ROOTS inside the results root or the suite root; WORK on another filesystem than the
results root (hard links); a path holding ':' or ',' (the grader refuses them); no grader or
freeze.sh. After grading (exit 1, no INDEX.json): a failed grade of a cell or a valid session, a
label_set other than the key's directory, two grader versions.

Exit: 0 written (or the plan printed, or --check passed); 1 refused / a grade failed / --check
mismatch; 2 usage.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import random
import re
import shutil
import stat
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from c132 import common  # noqa: E402
from c132.common import InputError  # noqa: E402

LABEL_DIRS = {"c131": ("c131",), "v1": ("v1",), "review": ("review", "c131")}
DEFAULT_IMAGE = "loa-ablation:258"
DEFAULT_SEED = 20261021
CHECK_N = 3
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_GRADER = os.path.join(os.path.dirname(os.path.dirname(SCRIPT_DIR)), "harness", "ablation-grade.sh")
EXCLUDE = ("grading", "grade.json")
RC_LINE = re.compile(r"^review_catch:.*$", re.M)
RC_MANIFEST = re.compile(r"(\bmanifest:\s*)([^,}\s]+)")


class GradeFailure(Exception):
    """a grade that failed after writes began (exit 1, no INDEX.json)"""


# ---------------------------------------------------------------- helpers
def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def dump(obj):
    return json.dumps(obj, sort_keys=True, indent=2, ensure_ascii=False) + "\n"


def write_atomic(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data if isinstance(data, bytes) else data.encode("utf-8"))
    os.replace(tmp, path)


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def inside(path, root):
    p, r = os.path.realpath(path), os.path.realpath(root)
    return p == r or p.startswith(r + os.sep)


def nearest_existing(path):
    p = os.path.abspath(path)
    while not os.path.exists(p):
        p = os.path.dirname(p)
    return p


def safe_rmtree(path, root):
    """remove a work copy: entries are unlinked (a hard link's inode, i.e. the record, is untouched);
    a directory without write permission gets u+rwx — never a file (a file's mode is the record's)"""
    if not inside(path, root) or os.path.realpath(path) == os.path.realpath(root):
        raise InputError("refusing to remove %s: not inside %s" % (path, root))

    def onexc(func, p, exc):
        parent = os.path.dirname(p)
        for d in (parent, p):
            if os.path.isdir(d) and not os.path.islink(d) and inside(d, root):
                os.chmod(d, stat.S_IMODE(os.lstat(d).st_mode) | stat.S_IRWXU)
        func(p)

    if os.path.lexists(path):
        shutil.rmtree(path, onexc=onexc)


def link_copy(src, dst, exclude=EXCLUDE):
    """dst = hard-link copy of src's entries except `exclude` (cp -al per entry: regular files linked,
    symlinks copied as links, directories recreated)"""
    os.makedirs(dst)
    for name in sorted(os.listdir(src)):
        if name in exclude:
            continue
        p = subprocess.run(["cp", "-al", "--", os.path.join(src, name), os.path.join(dst, name)],
                           capture_output=True, text=True)
        if p.returncode != 0:
            raise GradeFailure("cp -al %s: %s" % (os.path.join(src, name), p.stderr.strip()[:300]))


def copy_cell(src, dst, matched):
    if not matched:
        link_copy(src, dst)
        return
    link_copy(src, dst, EXCLUDE + ("sessions",))
    s_src, s_dst = os.path.join(src, "sessions"), os.path.join(dst, "sessions")
    os.makedirs(s_dst)
    for name in sorted(os.listdir(s_src)):
        q = os.path.join(s_src, name)
        if os.path.isdir(q) and not os.path.islink(q):
            link_copy(q, os.path.join(s_dst, name))
        else:
            link_copy_entry(q, os.path.join(s_dst, name))


def link_copy_entry(src, dst):
    p = subprocess.run(["cp", "-al", "--", src, dst], capture_output=True, text=True)
    if p.returncode != 0:
        raise GradeFailure("cp -al %s: %s" % (src, p.stderr.strip()[:300]))


# ---------------------------------------------------------------- suite root and keys
def task_manifest(suite_root, task):
    p = os.path.join(suite_root, "tasks", task, "task.yaml")
    if not os.path.isfile(p) or os.path.islink(p):
        raise InputError("no task.yaml for %s under %s" % (task, suite_root))
    text = read_bytes(p).decode("utf-8")
    lines = RC_LINE.findall(text)
    if len(lines) != 1:
        raise InputError("%s: expected one review_catch line, found %d" % (p, len(lines)))
    m = RC_MANIFEST.findall(lines[0])
    if len(m) != 1:
        raise InputError("%s: expected one review_catch manifest, found %d" % (p, len(m)))
    rel = m[0][1]
    d = os.path.dirname(rel)
    if os.path.basename(d) != "manifests" or not rel.endswith(".json") or ".." in rel.split("/"):
        raise InputError("%s: manifest %s is not a manifests/<pr>.json key" % (p, rel))
    return rel


def key_for(repo_root, manifest_rel, label):
    """(relpath, label_set) of the label's key for a task, or None"""
    base = os.path.dirname(manifest_rel)
    pr = os.path.basename(manifest_rel)
    for d in LABEL_DIRS[label]:
        rel = "%s/%s/%s" % (base, d, pr)
        full = os.path.join(repo_root, rel)
        if os.path.isfile(full) and not os.path.islink(full):
            return rel, d
    return None


def build_root(suite_root, dst, repoint, freeze):
    """copy suite_root to dst, re-point the tasks in `repoint` {task: new manifest}, freeze; returns
    the MANIFEST.sha256 digest"""
    shutil.copytree(suite_root, dst, symlinks=True)
    for task in sorted(repoint):
        p = os.path.join(dst, "tasks", task, "task.yaml")
        text = read_bytes(p).decode("utf-8")
        line = RC_LINE.findall(text)[0]
        new = RC_MANIFEST.sub(lambda m: m.group(1) + repoint[task], line, count=1)
        write_atomic(p, text.replace(line, new, 1))
    p = subprocess.run(["bash", freeze, "--root", dst, "--allow-partial"], capture_output=True, text=True)
    if p.returncode != 0:
        raise GradeFailure("freeze.sh failed on %s: %s" % (dst, (p.stdout + p.stderr).strip()[-400:]))
    return sha256_bytes(read_bytes(os.path.join(dst, "MANIFEST.sha256")))


# ---------------------------------------------------------------- planning (no writes)
def plan(a):
    rows = common.load_rows(a.rows)
    tasks = sorted({str(r.get("task_id")) for r in rows})
    if a.only:
        unknown = sorted(set(a.only) - set(tasks))
        if unknown:
            raise InputError("--only names tasks absent from the rows: %s" % ", ".join(unknown))
        tasks = sorted(set(a.only))
    manifests = {t: task_manifest(a.suite_root, t) for t in tasks}
    keys = {lab: {} for lab in a.labels}
    for lab in a.labels:
        for t in tasks:
            k = key_for(a.repo_root, manifests[t], lab)
            if k:
                keys[lab][t] = {"manifest": k[0], "label_set": k[1],
                                "sha256": common.sha256_file(os.path.join(a.repo_root, k[0]))}
    cells = []
    for r in sorted(rows, key=common.cell_key):
        t = str(r.get("task_id"))
        if t not in tasks:
            continue
        rd = common.run_dir_for(r, [a.results_root])
        if rd is None:
            raise InputError("no run directory for %s under %s" % (common.cell_key(r), a.results_root))
        matched = common.is_matched_row(r)
        c = {"key": common.cell_key(r), "batch": str(r.get("batch")), "arm": str(r.get("arm")), "task": t,
             "trial": r.get("trial"), "fixture": os.path.basename(manifests[t])[:-5], "matched": matched,
             "src": rd, "rel": os.path.join(str(r.get("batch")), str(r.get("arm")), "%s-t%s" % (t, r.get("trial")))}
        if matched:
            cj = common.load_json(os.path.join(rd, "meta", "cell.json"), "cell.json")
            sess = cj.get("sessions") if isinstance(cj, dict) else None
            if not isinstance(sess, list) or not sess:
                raise InputError("%s: cell.json has no sessions list" % rd)
            c["sessions"] = []
            for s in sess:
                rdir = s.get("run_dir") if isinstance(s, dict) else None
                if not isinstance(rdir, str) or not re.match(r"^sessions/[A-Za-z0-9._-]+\Z", rdir) or \
                        not os.path.isdir(os.path.join(rd, rdir)) or os.path.islink(os.path.join(rd, rdir)):
                    raise InputError("%s: session run_dir %r is not a directory under sessions/" % (rd, rdir))
                c["sessions"].append({"id": s.get("id"), "run_dir": rdir, "valid": s.get("valid") is True})
        else:
            sb = os.path.join(rd, "sandbox")
            if not os.path.isdir(sb) or os.path.islink(sb):
                raise InputError("%s: no sandbox/ directory" % rd)
        cells.append(c)
    return {"tasks": tasks, "manifests": manifests, "keys": keys, "cells": cells}


def check_paths(a):
    for name in ("out", "work", "roots"):
        p = getattr(a, name)
        for root, what in ((a.results_root, "the results root"), (a.suite_root, "the suite root")):
            if inside(p, root):
                raise InputError("--%s %s is inside %s" % (name, p, what))
        if ":" in os.path.abspath(p) or "," in os.path.abspath(p):
            raise InputError("--%s must not contain ':' or ','" % name)
    if os.stat(nearest_existing(a.work)).st_dev != os.stat(a.results_root).st_dev:
        raise InputError("--work %s is not on the results root's filesystem (hard links)" % a.work)
    if not os.path.isfile(a.grader):
        raise InputError("no grader at %s" % a.grader)
    if not os.path.isfile(a.freeze):
        raise InputError("no freeze.sh at %s" % a.freeze)


# ---------------------------------------------------------------- grading
def run_grader(a, args):
    """None on success, else the grader's output tail with the work and roots paths replaced by
    WORK / ROOTS (INDEX.json holds no absolute path)"""
    p = subprocess.run(["bash", a.grader] + args, capture_output=True, text=True)
    if p.returncode != 0:
        msg = (p.stdout + p.stderr).strip() or "exit %d" % p.returncode
        return msg.replace(a.work, "WORK").replace(a.roots, "ROOTS")[-600:]
    return None


def grade_cell(a, lab, root, c, work_base, force):
    """grade one cell into work_base/<rel>; returns the work copy path. Raises GradeFailure."""
    dst = os.path.join(work_base, c["rel"])
    gpath = os.path.join(dst, "grade.json")
    if os.path.isfile(gpath) and not force:
        return dst, False
    safe_rmtree(dst, a.work)
    copy_cell(c["src"], dst, c["matched"])
    common_args = ["--suite-root", root, "--allow-partial", "--executor", "container", "--image", a.image]
    errors = {}
    if c["matched"]:
        for s in c["sessions"]:
            sd = os.path.join(dst, s["run_dir"])
            err = run_grader(a, [sd, c["task"], "--out", os.path.join(sd, "grade.json")] + common_args)
            if err:
                if s["valid"]:
                    raise GradeFailure("%s %s session %s: %s" % (lab, c["key"], s["id"], err))
                errors[s["run_dir"]] = err
        if errors:
            write_atomic(os.path.join(dst, "session-grade-errors.json"), dump(errors))
        err = run_grader(a, ["--union", dst, "--task-id", c["task"], "--out", gpath] + common_args)
    else:
        err = run_grader(a, [dst, c["task"], "--out", gpath] + common_args)
    if err:
        raise GradeFailure("%s %s: %s" % (lab, c["key"], err))
    return dst, True


def collect(dst, c):
    """the cell's INDEX entry and the files to publish [(rel under the cell, bytes)] from the work copy
    (reads only: OUT is written after the label's refusals)"""
    errors, files = {}, []
    ep = os.path.join(dst, "session-grade-errors.json")
    if os.path.isfile(ep):
        errors = json.loads(read_bytes(ep).decode("utf-8"))
    g = read_bytes(os.path.join(dst, "grade.json"))
    files.append(("grade.json", g))
    gj = json.loads(g.decode("utf-8"))
    entry = {"key": c["key"], "batch": c["batch"], "arm": c["arm"], "task": c["task"], "trial": c["trial"],
             "fixture": c["fixture"], "matched": c["matched"], "grade": c["rel"] + "/grade.json",
             "grade_sha256": sha256_bytes(g), "label_set": gj.get("label_set"),
             "recall_pm3": (gj.get("recall") or {}).get("recall_pm3"), "grader_version": gj.get("grader_version"),
             "sessions_valid": gj.get("sessions_valid") if c["matched"] else None}
    if c["matched"]:
        entry["sessions"] = []
        for s in c["sessions"]:
            sp = os.path.join(dst, s["run_dir"], "grade.json")
            se = {"id": s["id"], "run_dir": s["run_dir"], "valid": s["valid"], "grade": None, "grade_sha256": None,
                  "label_set": None, "grader_version": None, "error": errors.get(s["run_dir"])}
            if os.path.isfile(sp) and s["run_dir"] not in errors:
                b = read_bytes(sp)
                files.append((s["run_dir"] + "/grade.json", b))
                sj = json.loads(b.decode("utf-8"))
                se.update(grade="%s/%s/grade.json" % (c["rel"], s["run_dir"]), grade_sha256=sha256_bytes(b),
                          label_set=sj.get("label_set"), grader_version=sj.get("grader_version"))
            entry["sessions"].append(se)
    return entry, files


def verify_entries(lab, keys, entries):
    """label_set and grader-version refusals over every grade of a label"""
    versions, observed, errs = set(), {}, []
    for e in entries:
        want = keys[e["task"]]["label_set"]
        grades = [(e["key"], e["label_set"], e["grader_version"], e["matched"] and not e.get("sessions_valid"))]
        grades += [("%s %s" % (e["key"], s["id"]), s["label_set"], s["grader_version"], False)
                   for s in e.get("sessions") or [] if s["grade"]]
        for where, ls, gv, empty_union in grades:
            versions.add(gv)
            if ls is None and empty_union:
                continue    # a union with no valid session carries no label_set (ablation-grade.sh grade_union)
            observed[str(ls)] = observed.get(str(ls), 0) + 1
            if ls != want:
                errs.append("%s: label_set %r, the key directory is %r" % (where, ls, want))
    if len(versions) > 1:
        errs.append("grader versions differ: %s" % ", ".join(sorted(str(v) for v in versions)))
    if errs:
        raise GradeFailure("label %s refused: %s" % (lab, "; ".join(errs[:20])))
    return (sorted(versions)[0] if versions else None), observed


def prepare_root(a, lab, pl, force):
    repoint = {t: k["manifest"] for t, k in pl["keys"][lab].items()}
    root = os.path.join(a.roots, lab)
    os.makedirs(a.roots, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix=lab + ".new-", dir=a.roots)
    new = os.path.join(tmp, "root")
    try:
        digest = build_root(a.suite_root, new, repoint, a.freeze)
    except BaseException:
        shutil.rmtree(tmp)
        raise
    marker = os.path.join(a.work, lab, "SUITE-ROOT.sha256")
    if os.path.isfile(marker) and read_bytes(marker).decode().strip() != digest and not force:
        shutil.rmtree(tmp)
        raise GradeFailure("label %s: the suite root digest %s differs from the one the work tree was graded under "
                           "(%s); --force re-grades" % (lab, digest, read_bytes(marker).decode().strip()))
    if os.path.lexists(root):
        shutil.rmtree(root)
    os.replace(new, root)
    os.rmdir(tmp)
    write_atomic(marker, digest + "\n")
    return root, digest, repoint


def regrade(a, pl):
    src_manifest = os.path.join(a.suite_root, "MANIFEST.sha256")
    src_digest = sha256_bytes(read_bytes(src_manifest)) if os.path.isfile(src_manifest) else None
    for lab in a.labels:
        root, digest, repoint = prepare_root(a, lab, pl, a.force)
        todo = [c for c in pl["cells"] if c["task"] in pl["keys"][lab]]
        skipped = [{"key": c["key"], "fixture": c["fixture"]} for c in pl["cells"] if c["task"] not in pl["keys"][lab]]
        work_base = os.path.join(a.work, lab)
        out_base = os.path.join(a.out, lab)
        if os.path.isfile(os.path.join(out_base, "INDEX.json")):
            os.unlink(os.path.join(out_base, "INDEX.json"))   # a failed run leaves no INDEX.json
        done = {}
        with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as ex:
            futs = {ex.submit(grade_cell, a, lab, root, c, work_base, a.force): c for c in todo}
            failures = []
            for f in concurrent.futures.as_completed(futs):
                c = futs[f]
                try:
                    done[c["key"]], fresh = f.result()
                    sys.stderr.write("regrade_labels: %s %s %s\n" % (lab, c["key"], "graded" if fresh else "kept"))
                except (GradeFailure, InputError, OSError) as e:
                    failures.append(str(e))
            if failures:
                raise GradeFailure("; ".join(sorted(failures)[:10]))
        collected = [(c, collect(done[c["key"]], c)) for c in todo]
        entries = [e for _c, (e, _f) in collected]
        gv, observed = verify_entries(lab, pl["keys"][lab], entries)
        for c, (_e, files) in collected:
            for rel, b in files:
                write_atomic(os.path.join(out_base, c["rel"], rel), b)
        idx = {"schema_version": 1, "label": lab, "key_dirs": list(LABEL_DIRS[lab]),
               "keys": pl["keys"][lab], "grader_version": gv, "label_sets_observed": observed,
               "suite_root": {"frozen": True, "freeze": "freeze.sh --allow-partial on a copy of the suite root",
                              "manifest_sha256": digest, "source_manifest_sha256": src_digest,
                              "repointed": {t: {"from": pl["manifests"][t], "to": repoint[t]} for t in sorted(repoint)}},
               "cells": entries, "cells_without_key": skipped, "n_cells": len(entries),
               "n_sessions": sum(1 for e in entries for s in e.get("sessions") or [] if s["grade"]),
               "only": sorted(a.only) if a.only else None}
        write_atomic(os.path.join(out_base, "MANIFEST.sha256"), read_bytes(os.path.join(root, "MANIFEST.sha256")))
        write_atomic(os.path.join(out_base, "INDEX.json"), dump(idx))
        sys.stdout.write("regrade_labels: %s: %d cells (%d without a key), INDEX.json sha256 %s\n" % (
            lab, len(entries), len(skipped), common.sha256_file(os.path.join(out_base, "INDEX.json"))))


def check(a, pl):
    """re-grade a seeded sample of CHECK_N cells into a temporary work dir; compare bytes"""
    pool = []
    for lab in a.labels:
        ip = os.path.join(a.out, lab, "INDEX.json")
        idx = common.load_json(ip, "INDEX.json")
        root = os.path.join(a.roots, lab)
        mp = os.path.join(root, "MANIFEST.sha256")
        if not os.path.isfile(mp) or sha256_bytes(read_bytes(mp)) != idx["suite_root"]["manifest_sha256"]:
            raise InputError("label %s: ROOTS/%s does not hold the suite root INDEX.json was graded under" % (lab, lab))
        pool += [(lab, e["key"]) for e in idx["cells"]]
    by_key = {c["key"]: c for c in pl["cells"]}
    pool = sorted(p for p in pool if p[1] in by_key)
    sample = random.Random(a.seed).sample(pool, min(CHECK_N, len(pool)))
    os.makedirs(a.work, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="check-", dir=a.work)
    results, ok = [], True
    try:
        for lab, key in sorted(sample):
            c = by_key[key]
            dst, _ = grade_cell(a, lab, os.path.join(a.roots, lab), c, os.path.join(tmp, lab), True)
            files = ["grade.json"] + ["%s/grade.json" % s["run_dir"] for s in c.get("sessions") or []]
            cmp = []
            for rel in files:
                fresh, kept = os.path.join(dst, rel), os.path.join(a.out, lab, c["rel"], rel)
                if not os.path.isfile(fresh) and not os.path.isfile(kept):
                    continue
                same = os.path.isfile(fresh) and os.path.isfile(kept) and read_bytes(fresh) == read_bytes(kept)
                cmp.append({"file": rel, "identical": same})
                ok = ok and same
            gc = os.path.join(dst, "grading", "gates-combined.md")
            wc = os.path.join(a.work, lab, c["rel"], "grading", "gates-combined.md")
            if os.path.isfile(wc):
                same = os.path.isfile(gc) and read_bytes(gc) == read_bytes(wc)
                cmp.append({"file": "grading/gates-combined.md", "identical": same})
                ok = ok and same
            results.append({"label": lab, "key": key, "files": cmp})
    finally:
        safe_rmtree(tmp, a.work)
    doc = {"schema_version": 1, "seed": a.seed, "sample": results, "pass": ok,
           "files_compared": sum(len(r["files"]) for r in results)}
    write_atomic(os.path.join(a.out, "CHECK.json"), dump(doc))
    sys.stdout.write(dump(doc))
    return 0 if ok else 1


# ---------------------------------------------------------------- CLI
def parse(argv):
    ap = argparse.ArgumentParser(prog="regrade_labels.py", description="label-set re-grades (addendum 16)")
    ap.add_argument("--rows", required=True)
    ap.add_argument("--results-root", required=True)
    ap.add_argument("--suite-root", required=True)
    ap.add_argument("--labels", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--work")
    ap.add_argument("--roots")
    ap.add_argument("--only", nargs="+", action="extend")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--force", action="store_true")
    m = ap.add_mutually_exclusive_group()
    m.add_argument("--dry-run", action="store_true")
    m.add_argument("--check", action="store_true")
    ap.add_argument("--seed", type=int, default=DEFAULT_SEED)
    ap.add_argument("--grader", default=DEFAULT_GRADER)
    ap.add_argument("--image", default=DEFAULT_IMAGE)
    ap.add_argument("--repo-root")
    a = ap.parse_args(argv)
    a.labels = [x for x in a.labels.split(",") if x]
    bad = [x for x in a.labels if x not in LABEL_DIRS]
    if not a.labels or bad or len(set(a.labels)) != len(a.labels):
        ap.error("--labels takes distinct members of %s" % ",".join(sorted(LABEL_DIRS)))
    if a.jobs < 1 or a.jobs > 32:
        ap.error("--jobs must be 1 … 32")
    for name in ("results_root", "suite_root"):
        if not os.path.isdir(getattr(a, name)):
            ap.error("--%s is not a directory" % name.replace("_", "-"))
    cache = os.path.join(os.path.expanduser("~"), ".cache", "loa", "regrade-labels")
    a.work = os.path.abspath(a.work or os.path.join(cache, "work"))
    a.roots = os.path.abspath(a.roots or os.path.join(cache, "roots"))
    a.out = os.path.abspath(a.out)
    a.grader = os.path.abspath(a.grader)
    a.freeze = os.path.join(os.path.dirname(a.grader), "freeze.sh")
    a.repo_root = os.path.abspath(a.repo_root or os.path.dirname(os.path.dirname(os.path.dirname(a.grader))))
    a.results_root = os.path.abspath(a.results_root)
    a.suite_root = os.path.abspath(a.suite_root)
    return a


def main(argv=None):
    try:
        a = parse(sys.argv[1:] if argv is None else argv)
    except SystemExit as e:
        return 2 if e.code else 0
    try:
        check_paths(a)
        pl = plan(a)
        if a.dry_run:
            sys.stdout.write(dump({
                "labels": {lab: {"keys": pl["keys"][lab],
                                 "cells": [c["key"] for c in pl["cells"] if c["task"] in pl["keys"][lab]],
                                 "cells_without_key": [c["key"] for c in pl["cells"] if c["task"] not in pl["keys"][lab]]}
                           for lab in a.labels},
                "sessions": sum(len(c.get("sessions") or []) for c in pl["cells"])}))
            return 0
        if a.check:
            return check(a, pl)
        regrade(a, pl)
    except InputError as e:
        sys.stderr.write("regrade_labels: refused: %s\n" % e)
        return 1
    except GradeFailure as e:
        sys.stderr.write("regrade_labels: failed: %s\n" % e)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
