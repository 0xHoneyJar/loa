#!/usr/bin/env python3
"""record_lite.py — the cycle-132 sandbox-lite record and its reconstruction (DEC-0811; sprint Tasks 3.3a/3.3b; prd FR-10).

The grader (evals/harness/ablation-grade.sh) refuses a run directory without sandbox/ and reads, under sandbox/, only
the findings files (review.md, grimoires/loa/a2a/sprint-1/{engineer-feedback,auditor-sprint-feedback}.md), the sandbox
copy of each key defect file (the oracle-exposure check) and sandbox/pr/ (copied to grading/pr: its symlink and
oversize counts enter grade.json). The row writer reads sandbox/grimoires/loa/a2a/sprint-1/adversarial-*.json. The
record therefore keeps, per run directory, a sandbox-lite set and a manifest of every sandbox file, and a reproducer
rebuilds sandbox/ = the PR fixture's files (as listed under pr/ in the manifest, sha-checked) + the lite files.

Usage:
  record_lite.py build --results-root DIR --batches B1,B2,… --fixtures-root DIR --suite-root DIR --out DIR
                       [--only TASK …] [--check N] [--check-unit REL …] [--seed 20261021] [--grader PATH]
                       [--scratch DIR] [--jobs N] [--no-build]
  record_lite.py reconstruct --record-root DIR --lite-root DIR --fixtures-root DIR --suite-root DIR
                       --dest DIR REL [REL …]
  record_lite.py reproduce --record-root DIR --scratch DIR [--batches …] [--jobs N] [--grader PATH] [--row-bin PATH]
                       [--steps reconstruct,grade,rows,reads,report] [--env-json F] [--report F] [--dry-run] …
                       (the engine behind evals/analysis/c132/reproduce.sh; see that script's header)

Run directories: <results-root>/<batch>/<arm>/<task>-t<n>[-r<k>] (a cell) and, in a matched cell, every directory
under sessions/ (s<i>, s<i>-r<n>). A run directory is one that holds sandbox/ (or, without one, meta/pipeline.json:
its manifest then says sandbox_present false). A matched cell holds no sandbox; it is graded with --union.

build writes, for every run directory REL (relative to the results root):
  OUT/REL/sandbox-lite/…        review.md; every regular file under sandbox/grimoires/; the sandbox copy of every
                                defect file any key for the PR names (the task's review_catch.manifest, plus
                                manifests/<set>/<pr>.json for the label-set sensitivities); every sandbox/pr/ file
                                that is not byte-identical to the fixture's file at the same path
  OUT/REL/sandbox-manifest.json {files: [{path, size, sha256} | {path, type: symlink, target} | {path, type: other}]
                                for every entry under sandbox/ (.git/ and .eval/ included), pr_head_equals_fixture,
                                pr_base_equals_fixture, pr_diffs, pr_missing, defect_files, defect_files_absent,
                                lite_sha256 {path: sha}, dropped {count, bytes}, reconstructable {count, bytes}, …}
  OUT/INDEX.json                every run directory built, with its manifest's sha256
A symlink in the lite set (review.md, anything under grimoires/, a defect file or a path component of one, a
differing pr/ file) is refused: exit 1 and nothing is written (every run directory is scanned before any write).
Output is deterministic (sorted keys and paths, no timestamps, no absolute paths).

--check N: after the build, a seeded (--seed), arm-stratified sample of N units — a pipeline cell, a matched session,
or a matched cell (all its sessions, then --union) — plus every --check-unit REL is reconstructed into a scratch
directory (--scratch, default a fresh temp dir), re-graded with the grader (container executor, the batch
MANIFEST's tasks_dir and allow_partial) and its grade.json compared byte for byte with the recorded one; a table is
printed. The recorded run directories are never written (the grader rewrites <run-dir>/grading/).

Exit codes: 0 done (every check identical); 1 refused (symlink in the lite set), a reconstruction failed its
manifest, or a check / reproduction differs; 2 usage or unreadable input.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

SCHEMA = 1
SEED = 20261021
CELL_RE = re.compile(r"^(?P<task>.+)-t(?P<trial>[0-9]+)(?:-r(?P<re>[0-9]+))?$")
SPRINT = "sprint-1"
RECORDED_SUBDIRS = ("meta", "transcripts", "eval")   # copied from the record for every run dir (plus the cell meta/)
GROUP_BATCHES = tuple("c132-g%d-%s" % (g, a) for g in (1, 2, 3) for a in ("a1", "a2", "a3", "b"))
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))


class Refusal(Exception):
    """a symlink in the lite set (exit 1)"""


class InputError(Exception):
    """unreadable or malformed input (exit 2)"""


class Mismatch(Exception):
    """a reconstructed file does not match its manifest (exit 1)"""


# ---------------------------------------------------------------- hashing
_SHA_CACHE = {}


def sha256_file(path):
    st = os.stat(path, follow_symlinks=False)
    key = (st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns)
    hit = _SHA_CACHE.get(key)
    if hit is not None:
        return hit
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    _SHA_CACHE[key] = h.hexdigest()
    return _SHA_CACHE[key]


def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def dump_json(obj):
    """deterministic JSON: sorted keys, two-space indent, trailing newline; a `files` list one entry per line"""
    if not (isinstance(obj, dict) and isinstance(obj.get("files"), list)):
        return json.dumps(obj, indent=2, sort_keys=True) + "\n"
    parts = []
    for k in sorted(obj):
        if k == "files":
            fs = obj[k]
            v = ("[\n" + ",\n".join("    " + json.dumps(e, sort_keys=True) for e in fs) + "\n  ]") if fs else "[]"
        else:
            v = json.dumps(obj[k], indent=2, sort_keys=True).replace("\n", "\n  ")
        parts.append("  %s: %s" % (json.dumps(k), v))
    return "{\n" + ",\n".join(parts) + "\n}\n"


# ---------------------------------------------------------------- tasks and keys
_TASK_CACHE = {}


def task_info(suite_root, tasks_dir, task):
    """(fixture rel 'review-prs/pr-NN', manifest rel) from <suite>/<tasks_dir>/<task>/task.yaml (flow mapping
    review_catch: {fixture: …, manifest: …}; stdlib only, so a targeted parse)"""
    key = (suite_root, tasks_dir, task)
    if key in _TASK_CACHE:
        return _TASK_CACHE[key]
    p = os.path.join(suite_root, tasks_dir, task, "task.yaml")
    try:
        text = open(p, encoding="utf-8").read()
    except OSError as e:
        raise InputError("cannot read %s: %s" % (p, e))
    m = re.search(r"^review_catch:\s*\{(?P<body>[^}]*)\}", text, re.M)
    if not m:
        raise InputError("%s: no review_catch flow mapping (record_lite handles review-catch tasks only)" % p)
    body = m.group("body")
    fx = re.search(r"(?:^|,)\s*fixture:\s*([^,\s]+)", body)
    mf = re.search(r"(?:^|,)\s*manifest:\s*([^,\s]+)", body)
    if not fx or not mf:
        raise InputError("%s: review_catch lacks fixture or manifest" % p)
    _TASK_CACHE[key] = (fx.group(1).strip("'\""), mf.group(1).strip("'\""))
    return _TASK_CACHE[key]


def pr_name(fixture_rel):
    return fixture_rel.rstrip("/").rsplit("/", 1)[-1]


def defect_files(fixtures_root, manifest_rel, pr, repo_root):
    """{defect file: [key labels]} over the task's key and every manifests/<set>/<pr>.json beside it"""
    out = {}
    mdir = os.path.join(fixtures_root, "manifests")
    pre = "evals/fixtures/review-prs/"
    first = os.path.join(fixtures_root, *manifest_rel[len(pre):].split("/")) if manifest_rel.startswith(pre) \
        else os.path.join(repo_root, manifest_rel)
    cands = [("task", first)]
    if os.path.isdir(mdir):
        for s in sorted(os.listdir(mdir)):
            p = os.path.join(mdir, s, pr + ".json")
            if os.path.isdir(os.path.join(mdir, s)) and os.path.isfile(p):
                cands.append((s, p))
    if not os.path.isfile(cands[0][1]):
        alt = os.path.join(mdir, pr + ".json")
        if not os.path.isfile(alt):
            raise InputError("key manifest not found: %s" % manifest_rel)
        cands[0] = ("task", alt)
    for label, p in cands:
        try:
            doc = json.load(open(p, encoding="utf-8"))
        except (OSError, ValueError) as e:
            raise InputError("cannot read key %s: %s" % (p, e))
        for d in doc.get("defects") or []:
            f = d.get("file") if isinstance(d, dict) else None
            if isinstance(f, str) and safe_rel(f):
                out.setdefault(f, set()).add(label)
    return {f: sorted(v) for f, v in out.items()}


def safe_rel(rel):
    if not rel or rel.startswith("/") or "\\" in rel or "\x00" in rel:
        return False
    parts = rel.split("/")
    return all(p not in ("", ".", "..") for p in parts)


_FIX_CACHE = {}


def fixture_map(fixtures_root, pr):
    """{rel path under the fixture dir: (sha256, size)} for every regular file of evals/fixtures/review-prs/<pr>"""
    root = os.path.join(fixtures_root, pr)
    if root in _FIX_CACHE:
        return _FIX_CACHE[root]
    if not os.path.isdir(root):
        raise InputError("fixture not found: %s" % root)
    m = {}
    for r, ds, fs in os.walk(root):
        ds.sort()
        for n in fs:
            p = os.path.join(r, n)
            if os.path.isfile(p) and not os.path.islink(p):
                m[os.path.relpath(p, root).replace(os.sep, "/")] = (sha256_file(p), os.path.getsize(p))
    _FIX_CACHE[root] = m
    return m


# ---------------------------------------------------------------- run-dir enumeration
def batch_meta(results_root, batch):
    p = os.path.join(results_root, batch, "MANIFEST.json")
    try:
        m = json.load(open(p, encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise InputError("cannot read %s: %s" % (p, e))
    return {"tasks_dir": m.get("tasks_dir") or "tasks", "allow_partial": m.get("allow_partial") is True}


def cells_of(results_root, batch, only=None):
    """[(rel cell, arm, task, matched)] sorted; a cell is <batch>/<arm>/<task>-t<n>[-r<k>] holding meta/"""
    out = []
    broot = os.path.join(results_root, batch)
    if not os.path.isdir(broot):
        raise InputError("no batch directory %s" % broot)
    for arm in sorted(os.listdir(broot)):
        ad = os.path.join(broot, arm)
        if not os.path.isdir(ad) or os.path.islink(ad):
            continue
        for name in sorted(os.listdir(ad)):
            m = CELL_RE.match(name)
            cd = os.path.join(ad, name)
            if not m or not os.path.isdir(cd) or os.path.islink(cd) or not os.path.isdir(os.path.join(cd, "meta")):
                continue
            if only and m.group("task") not in only:
                continue
            matched = os.path.isfile(os.path.join(cd, "meta", "cell.json"))
            out.append(("/".join((batch, arm, name)), arm, m.group("task"), matched))
    return out


def sessions_of(results_root, cell_rel):
    sd = os.path.join(results_root, cell_rel, "sessions")
    if not os.path.isdir(sd):
        return []
    return ["%s/sessions/%s" % (cell_rel, n) for n in sorted(os.listdir(sd))
            if os.path.isdir(os.path.join(sd, n)) and not os.path.islink(os.path.join(sd, n))]


def run_dirs_of(results_root, cell_rel, matched):
    """the run directories of a cell: itself (a pipeline cell) or its session directories (a matched cell)"""
    if matched:
        return sessions_of(results_root, cell_rel)
    return [cell_rel]


# ---------------------------------------------------------------- build
def scan_sandbox(sb):
    """every entry under sandbox/ (directories implied): regular {path,size,sha256}; symlink; other"""
    files = []
    for r, ds, fs in os.walk(sb):
        ds.sort()
        for n in list(ds):
            p = os.path.join(r, n)
            if os.path.islink(p):   # os.walk does not descend a symlinked dir; list it as a link
                ds.remove(n)
                files.append({"path": os.path.relpath(p, sb).replace(os.sep, "/"), "type": "symlink",
                              "target": os.readlink(p)})
        for n in sorted(fs):
            p = os.path.join(r, n)
            rel = os.path.relpath(p, sb).replace(os.sep, "/")
            if os.path.islink(p):
                files.append({"path": rel, "type": "symlink", "target": os.readlink(p)})
            elif os.path.isfile(p):
                files.append({"path": rel, "size": os.path.getsize(p), "sha256": sha256_file(p)})
            else:
                files.append({"path": rel, "type": "other"})
    files.sort(key=lambda e: e["path"])
    return files


def plan_run_dir(results_root, rel, task, tasks_dir, suite_root, fixtures_root, repo_root):
    """→ (manifest dict, {lite rel: source path}); Refusal on a symlink in the lite set"""
    rd = os.path.join(results_root, rel)
    sb = os.path.join(rd, "sandbox")
    fixture_rel, manifest_rel = task_info(suite_root, tasks_dir, task)
    pr = pr_name(fixture_rel)
    man = {"schema_version": SCHEMA, "run_dir": rel, "task_id": task, "fixture": pr, "sandbox_present": False}
    if os.path.islink(sb):
        raise Refusal("%s: sandbox/ is a symlink" % rel)
    if not os.path.isdir(sb):
        man.update(files=[], lite_sha256={}, defect_files=[], defect_files_absent=[], pr_diffs=[], pr_missing=[],
                   pr_head_equals_fixture=None, pr_base_equals_fixture=None,
                   dropped={"count": 0, "bytes": 0}, reconstructable={"count": 0, "bytes": 0})
        return man, {}
    man["sandbox_present"] = True
    files = scan_sandbox(sb)
    by_path = {e["path"]: e for e in files}
    lite = {}

    def take(path, why):
        e = by_path.get(path)
        parts = path.split("/")
        for i in range(1, len(parts)):   # a symlinked parent component
            if os.path.islink(os.path.join(sb, *parts[:i])):
                raise Refusal("%s: %s has a symlinked parent %s (%s)" % (rel, path, "/".join(parts[:i]), why))
        if e is None:
            return False
        if e.get("type") == "symlink":
            raise Refusal("%s: sandbox/%s is a symlink (%s)" % (rel, path, why))
        if e.get("type") == "other":
            return False
        lite[path] = os.path.join(sb, *parts)
        return True

    take("review.md", "review.md")
    for e in files:
        if e["path"].startswith("grimoires/"):
            if e.get("type") == "symlink":
                raise Refusal("%s: sandbox/%s is a symlink (grimoires/)" % (rel, e["path"]))
            take(e["path"], "grimoires/")
    if os.path.islink(os.path.join(sb, "grimoires")):
        raise Refusal("%s: sandbox/grimoires is a symlink" % rel)
    dfs = defect_files(fixtures_root, manifest_rel, pr, repo_root)
    copied, absent = [], []
    for f in sorted(dfs):
        (copied if take(f, "defect file") else absent).append(f)
    fmap = fixture_map(fixtures_root, pr)
    pr_diffs, pr_seen = [], set()
    for e in files:
        if not e["path"].startswith("pr/"):
            continue
        sub = e["path"][3:]
        pr_seen.add(sub)
        fx = fmap.get(sub)
        if e.get("type") is None and fx is not None and fx[0] == e["sha256"]:
            continue
        pr_diffs.append(e["path"])
        if e.get("type") is None:
            take(e["path"], "pr/ file differing from the fixture")
        elif e.get("type") == "symlink" and fx is not None:
            pass   # a symlink where the fixture has a file: recreated from the manifest (grading/pr drops it)
    pr_missing = sorted("pr/" + s for s in fmap if s not in pr_seen)

    def side_equal(side):
        want = {s: v for s, v in fmap.items() if s.startswith(side + "/")}
        have = {e["path"][3:]: e for e in files if e["path"].startswith("pr/%s/" % side)}
        if set(want) != set(have):
            return False
        return all(have[s].get("sha256") == want[s][0] for s in want)

    lite_sha = {p: by_path[p]["sha256"] for p in sorted(lite)}
    drop_n = drop_b = rec_n = rec_b = 0
    for e in files:
        if e.get("type") is not None or e["path"] in lite:
            continue
        if e["path"].startswith("pr/"):
            rec_n += 1
            rec_b += e["size"]
        else:
            drop_n += 1
            drop_b += e["size"]
    man.update(files=files, lite_sha256=lite_sha, defect_files=copied, defect_files_absent=absent,
               defect_file_keys={f: dfs[f] for f in sorted(dfs)},
               pr_diffs=sorted(pr_diffs), pr_missing=pr_missing,
               pr_head_equals_fixture=side_equal("head"), pr_base_equals_fixture=side_equal("base"),
               dropped={"count": drop_n, "bytes": drop_b}, reconstructable={"count": rec_n, "bytes": rec_b},
               lite={"count": len(lite), "bytes": sum(by_path[p]["size"] for p in lite)},
               symlinks=sum(1 for e in files if e.get("type") == "symlink"),
               others=sum(1 for e in files if e.get("type") == "other"))
    return man, lite


def remove_tree(p):
    if os.path.islink(p) or os.path.isfile(p):
        os.unlink(p)
    elif os.path.isdir(p):
        shutil.rmtree(p)


def write_lite(out, rel, man, lite):
    d = os.path.join(out, rel)
    os.makedirs(d, exist_ok=True)
    ld = os.path.join(d, "sandbox-lite")
    if os.path.lexists(ld):
        remove_tree(ld)
    for path in sorted(lite):
        dst = os.path.join(ld, *path.split("/"))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(lite[path], dst, follow_symlinks=False)
        if sha256_file(dst) != man["lite_sha256"][path]:
            raise Mismatch("%s: the copy of %s changed while copying" % (rel, path))
    text = dump_json(man)
    with open(os.path.join(d, "sandbox-manifest.json"), "w", encoding="utf-8") as f:
        f.write(text)
    return sha256_bytes(text.encode("utf-8"))


def build(results_root, batches, fixtures_root, suite_root, out, only=None, repo_root=REPO, log=print):
    plans = []
    for b in batches:
        bm = batch_meta(results_root, b)
        for cell, arm, task, matched in cells_of(results_root, b, only):
            for rel in run_dirs_of(results_root, cell, matched):
                man, lite = plan_run_dir(results_root, rel, task, bm["tasks_dir"], suite_root, fixtures_root, repo_root)
                man["arm"] = arm
                man["kind"] = "session" if matched else "cell"
                plans.append((rel, man, lite))
    index = []
    for rel, man, lite in plans:
        index.append({"run_dir": rel, "kind": man["kind"], "arm": man["arm"], "task_id": man["task_id"],
                      "manifest_sha256": write_lite(out, rel, man, lite)})
    tot = {"run_dirs": len(plans),
           "lite_files": sum(len(l) for _r, _m, l in plans),
           "lite_bytes": sum(m.get("lite", {}).get("bytes", 0) for _r, m, _l in plans),
           "dropped_files": sum(m["dropped"]["count"] for _r, m, _l in plans),
           "dropped_bytes": sum(m["dropped"]["bytes"] for _r, m, _l in plans),
           "reconstructable_files": sum(m["reconstructable"]["count"] for _r, m, _l in plans),
           "reconstructable_bytes": sum(m["reconstructable"]["bytes"] for _r, m, _l in plans),
           "pr_head_differs": sum(1 for _r, m, _l in plans if m["pr_head_equals_fixture"] is False),
           "pr_base_differs": sum(1 for _r, m, _l in plans if m["pr_base_equals_fixture"] is False),
           "no_sandbox": sum(1 for _r, m, _l in plans if not m["sandbox_present"])}
    idx = {"schema_version": SCHEMA, "batches": list(batches), "only": sorted(only) if only else None,
           "run_dirs": index, "totals": tot}
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "INDEX.json" if not only else "INDEX-only.json"), "w", encoding="utf-8") as f:
        f.write(dump_json(idx))
    log("record_lite: %d run dirs; lite %d files %d bytes; dropped %d files %d bytes; from the fixture %d files %d bytes; "
        "pr/head differs %d, pr/base differs %d, no sandbox %d"
        % (tot["run_dirs"], tot["lite_files"], tot["lite_bytes"], tot["dropped_files"], tot["dropped_bytes"],
           tot["reconstructable_files"], tot["reconstructable_bytes"], tot["pr_head_differs"], tot["pr_base_differs"],
           tot["no_sandbox"]))
    return idx


# ---------------------------------------------------------------- reconstruct
def link_or_copy(src, dst):
    try:
        os.link(src, dst)
    except OSError:
        shutil.copyfile(src, dst, follow_symlinks=False)


def copy_recorded(src_rd, dst_rd, cell=False):
    """the recorded files a grade and a row read: meta/, transcripts/, eval/ (regular files, copied); a cell's meta/ too"""
    for sub in RECORDED_SUBDIRS:
        s = os.path.join(src_rd, sub)
        if not os.path.isdir(s) or os.path.islink(s):
            continue
        for r, ds, fs in os.walk(s):
            ds[:] = sorted(d for d in ds if not os.path.islink(os.path.join(r, d)))
            for n in sorted(fs):
                p = os.path.join(r, n)
                if os.path.islink(p) or not os.path.isfile(p):
                    continue
                q = os.path.join(dst_rd, os.path.relpath(p, src_rd))
                os.makedirs(os.path.dirname(q), exist_ok=True)
                shutil.copyfile(p, q)


def reconstruct_run_dir(record_root, lite_root, fixtures_root, rel, dest_root):
    """rebuild dest_root/rel: the recorded files + sandbox/ (fixture pr/ files listed in the manifest, sha-checked,
    and the lite files, sha-checked). → the manifest. Mismatch on any difference; InputError on a missing manifest."""
    src = os.path.join(record_root, rel)
    dst = os.path.join(dest_root, rel)
    mp = os.path.join(lite_root, rel, "sandbox-manifest.json")
    try:
        man = json.load(open(mp, encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise InputError("no readable sandbox manifest for %s: %s" % (rel, e))
    if man.get("schema_version") != SCHEMA or man.get("run_dir") != rel:
        raise Mismatch("%s: the manifest names %r (schema %r)" % (rel, man.get("run_dir"), man.get("schema_version")))
    os.makedirs(dst, exist_ok=True)
    copy_recorded(src, dst)
    if not man.get("sandbox_present"):
        return man
    sb = os.path.join(dst, "sandbox")
    if os.path.lexists(sb):
        remove_tree(sb)
    os.makedirs(sb)
    lite_sha = man.get("lite_sha256") or {}
    fmap = fixture_map(fixtures_root, man["fixture"])
    errs = []
    for e in man.get("files") or []:
        path = e["path"]
        if not safe_rel(path):
            raise Mismatch("%s: unsafe manifest path %r" % (rel, path))
        q = os.path.join(sb, *path.split("/"))
        if path in lite_sha:
            s = os.path.join(lite_root, rel, "sandbox-lite", *path.split("/"))
            if not os.path.isfile(s) or os.path.islink(s):
                errs.append("lite file missing: %s" % path)
                continue
            got = sha256_file(s)
            if got != lite_sha[path] or got != e.get("sha256"):
                errs.append("lite file sha differs: %s" % path)
                continue
            os.makedirs(os.path.dirname(q), exist_ok=True)
            shutil.copyfile(s, q)
        elif path.startswith("pr/"):
            if e.get("type") == "symlink":
                os.makedirs(os.path.dirname(q), exist_ok=True)
                os.symlink(e["target"], q)
                continue
            if e.get("type") == "other":
                continue
            fx = fmap.get(path[3:])
            if fx is None or fx[0] != e.get("sha256"):
                errs.append("pr file not reconstructable from the fixture: %s" % path)
                continue
            os.makedirs(os.path.dirname(q), exist_ok=True)
            link_or_copy(os.path.join(fixtures_root, man["fixture"], *path[3:].split("/")), q)
    for path in lite_sha:
        if not any(e["path"] == path for e in man.get("files") or []):
            errs.append("lite file not in the manifest's files: %s" % path)
    if errs:
        raise Mismatch("%s: %s" % (rel, "; ".join(errs[:8]) + (" (+%d more)" % (len(errs) - 8) if len(errs) > 8 else "")))
    return man


def reconstruct_cell(record_root, lite_root, fixtures_root, cell_rel, matched, dest_root):
    """a whole cell: a pipeline cell is one run dir; a matched cell = its meta/ + every session"""
    if not matched:
        return [reconstruct_run_dir(record_root, lite_root, fixtures_root, cell_rel, dest_root)]
    src = os.path.join(record_root, cell_rel)
    dst = os.path.join(dest_root, cell_rel)
    os.makedirs(dst, exist_ok=True)
    copy_recorded(src, dst, cell=True)
    return [reconstruct_run_dir(record_root, lite_root, fixtures_root, rel, dest_root)
            for rel in sessions_of(record_root, cell_rel)]


# ---------------------------------------------------------------- grading
def grader_cmd(grader, run_dir, task, suite_root, bm, union=False):
    cmd = ["bash", grader]
    cmd += (["--union", run_dir, "--task-id", task] if union else [run_dir, task])
    cmd += ["--suite-root", suite_root]
    if bm["tasks_dir"] != "tasks":
        cmd += ["--tasks-dir", bm["tasks_dir"]]
    if bm["allow_partial"]:
        cmd.append("--allow-partial")
    return cmd


def run_grader(cmd, log_path):
    with open(log_path, "w", encoding="utf-8") as lf:
        p = subprocess.run(cmd, stdout=lf, stderr=subprocess.STDOUT, timeout=1800)
    return p.returncode


def file_sha(p):
    return sha256_file(p) if os.path.isfile(p) and not os.path.islink(p) else None


def compare_unit(results_root, scratch_root, rel):
    rec_g = file_sha(os.path.join(results_root, rel, "grade.json"))
    new_g = file_sha(os.path.join(scratch_root, rel, "grade.json"))
    rec_c = file_sha(os.path.join(results_root, rel, "grading", "gates-combined.md"))
    new_c = file_sha(os.path.join(scratch_root, rel, "grading", "gates-combined.md"))
    return {"run_dir": rel, "recorded": rec_g, "reproduced": new_g, "recorded_graded": rec_g is not None,
            "grade_equal": rec_g is not None and rec_g == new_g, "combined_equal": rec_c == new_c}


def pick_units(results_root, batches, n, seed, only=None):
    """arm-stratified seeded sample: units (kind, rel, arm, task, matched); kinds cell | session | union"""
    pools = {}
    for b in batches:
        for cell, arm, task, matched in cells_of(results_root, b, only):
            if matched:
                pools.setdefault(arm, []).append(("union", cell, arm, task, True, b))
                for s in sessions_of(results_root, cell):
                    pools.setdefault(arm, []).append(("session", s, arm, task, True, b))
            else:
                pools.setdefault(arm, []).append(("cell", cell, arm, task, False, b))
    rng = random.Random(seed)
    for arm in sorted(pools):
        rng.shuffle(pools[arm])
    picked, arms = [], sorted(pools)
    while len(picked) < n and any(pools[a] for a in arms):
        for a in arms:
            if pools[a] and len(picked) < n:
                picked.append(pools[a].pop(0))
    return picked


def unit_for(results_root, rel, batches):
    parts = rel.split("/")
    if len(parts) < 3 or parts[0] not in batches:
        raise InputError("--check-unit %s: not <batch>/<arm>/<cell>[/sessions/<s>] of the given batches" % rel)
    cell = "/".join(parts[:3])
    m = CELL_RE.match(parts[2])
    if not m:
        raise InputError("--check-unit %s: bad cell name" % rel)
    matched = os.path.isfile(os.path.join(results_root, cell, "meta", "cell.json"))
    if len(parts) == 3:
        return ("union" if matched else "cell", cell, parts[1], m.group("task"), matched, parts[0])
    return ("session", rel, parts[1], m.group("task"), True, parts[0])


def check(results_root, lite_root, fixtures_root, suite_root, batches, n, seed, grader, scratch, extra=(), only=None,
          jobs=1, log=print):
    units = pick_units(results_root, batches, n, seed, only) if n else []
    for rel in extra:
        u = unit_for(results_root, rel, batches)
        if u not in units:
            units.append(u)
    os.makedirs(scratch, exist_ok=True)
    if ":" in os.path.abspath(scratch) or "," in os.path.abspath(scratch):
        raise InputError("the scratch path must not contain ':' or ','")
    rows = []
    for kind, rel, arm, task, matched, b in units:
        bm = batch_meta(results_root, b)
        cell = "/".join(rel.split("/")[:3])
        if kind == "session":
            reconstruct_run_dir(results_root, lite_root, fixtures_root, rel, scratch)
            targets = [rel]
        else:
            reconstruct_cell(results_root, lite_root, fixtures_root, cell, matched, scratch)
            targets = sessions_of(results_root, cell) if matched else [cell]

        def one(t):
            rd = os.path.join(scratch, t)
            return t, run_grader(grader_cmd(grader, rd, task, suite_root, bm), rd + ".grade.log")

        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, jobs)) as ex:
            rcs = dict(ex.map(one, targets))
        for t in targets:
            r = compare_unit(results_root, scratch, t)
            r.update(kind="session" if kind != "cell" else "cell", arm=arm, rc=rcs[t])
            rows.append(r)
        if kind == "union":
            cd = os.path.join(scratch, cell)
            rc = run_grader(grader_cmd(grader, cd, task, suite_root, bm, union=True), cd + ".grade.log")
            r = compare_unit(results_root, scratch, cell)
            r.update(kind="union", arm=arm, rc=rc)
            rows.append(r)
    w = max([len(r["run_dir"]) for r in rows] + [8])
    log("%-*s  %-7s  %-21s  %-12s  %-12s  %-8s  %s" % (w, "run dir", "kind", "arm", "recorded", "reproduced", "combined", "grade.json"))
    for r in rows:
        log("%-*s  %-7s  %-21s  %-12s  %-12s  %-8s  %s" % (
            w, r["run_dir"], r["kind"], r["arm"], (r["recorded"] or "-")[:12], (r["reproduced"] or "-")[:12],
            "equal" if r["combined_equal"] else "DIFFERS", "IDENTICAL" if r["grade_equal"] else "DIFFERS (rc %s)" % r["rc"]))
    same = sum(1 for r in rows if r["grade_equal"])
    log("check: %d of %d grade.json byte-identical (%s)" % (same, len(rows), ", ".join(
        "%s %d" % (k, sum(1 for r in rows if r["kind"] == k)) for k in ("cell", "session", "union"))))
    return rows


# ---------------------------------------------------------------- reproduce (engine of reproduce.sh)
def canon(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"))


def run_dir_for_row(results_root, row):
    """the row's run dir under results_root: <batch>/<arm>/<task>-t<n>, or its highest -r<k> sibling (common.run_dir_for)"""
    parent = os.path.join(results_root, str(row.get("batch")), str(row.get("arm")))
    base = "%s-t%s" % (row.get("task_id"), row.get("trial"))
    if not os.path.isdir(parent):
        return None
    best, top = (os.path.join(parent, base) if os.path.isdir(os.path.join(parent, base)) else None), 1
    for name in sorted(os.listdir(parent)):
        k = name[len(base) + 2:] if name.startswith(base + "-r") else ""
        if k.isdigit() and int(k) > top and os.path.isdir(os.path.join(parent, name)):
            top, best = int(k), os.path.join(parent, name)
    return best


def reproduce(a, log=print):
    rr = os.path.abspath(a.record_root)
    results = os.path.join(rr, a.results_rel)
    lite = os.path.abspath(a.lite_root or os.path.join(results, "c132-lite"))
    fixtures = os.path.abspath(a.fixtures_root or os.path.join(rr, "evals", "fixtures", "review-prs"))
    suite = os.path.abspath(a.suite_root or os.path.join(rr, "grimoires", "loa", "evals", "ablation-2.0-c132"))
    scratch = os.path.abspath(a.scratch)
    sres = os.path.join(scratch, "results")
    grader = os.path.abspath(a.grader or os.path.join(rr, "evals", "harness", "ablation-grade.sh"))
    row_bin = os.path.abspath(a.row_bin or os.path.join(rr, "evals", "harness", "ablation-row.sh"))
    reads_bin = os.path.abspath(a.reads_bin or os.path.join(rr, "evals", "analysis", "c132", "reads-c132.py"))
    steps = set(a.steps.split(","))
    batches = a.batches.split(",") if a.batches else list(GROUP_BATCHES)
    if ":" in scratch or "," in scratch:
        raise InputError("the scratch path must not contain ':' or ','")
    os.makedirs(sres, exist_ok=True)
    cells = []
    for b in batches:
        bm = batch_meta(results, b)
        for cell, arm, task, matched in cells_of(results, b):
            cells.append((b, bm, cell, arm, task, matched))
    n_sess = sum(len(sessions_of(results, c)) for _b, _m, c, _a, _t, mt in cells if mt)
    log("reproduce: %d batches, %d cells (%d matched, %d sessions)" % (
        len(batches), len(cells), sum(1 for c in cells if c[5]), n_sess))
    res = {"sessions": [], "cells": [], "unions": [], "reconstruct_errors": [], "rows": [], "reads": [], "inputs_cells": []}
    if a.dry_run:
        log("reproduce: --dry-run — reconstruct, grade, rows and reads skipped")
        res["dry_run"] = True
        return res
    # (b) reconstruct (resumable: a marker per cell)
    if "reconstruct" in steps:
        for b, bm, cell, arm, task, matched in cells:
            mark = os.path.join(sres, cell, ".reconstructed")
            if os.path.isfile(mark):
                continue
            try:
                reconstruct_cell(results, lite, fixtures, cell, matched, sres)
                open(mark, "w").close()
            except (Mismatch, InputError) as e:
                res["reconstruct_errors"].append(str(e))
        log("reproduce: reconstructed (%d errors)" % len(res["reconstruct_errors"]))
    # (c) grade: sessions and pipeline cells in parallel, then the unions (skip when the scratch grade.json exists)
    if "grade" in steps:
        jobs = []
        for b, bm, cell, arm, task, matched in cells:
            for rel in (sessions_of(results, cell) if matched else [cell]):
                jobs.append((rel, task, bm))

        def g1(j):
            rel, task, bm = j
            rd = os.path.join(sres, rel)
            if os.path.isfile(os.path.join(rd, "grade.json")):
                return rel, 0
            if not os.path.isdir(os.path.join(rd, "sandbox")):
                return rel, None   # no sandbox recorded: nothing to grade (the recorded run has no grade either)
            if not os.path.isfile(os.path.join(results, rel, "grade.json")):
                return rel, None   # not graded in the record (a run the runner never graded: interrupted, superseded, invalid); not graded here either
            return rel, run_grader(grader_cmd(grader, rd, task, suite, bm), rd + ".grade.log")

        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, a.jobs)) as ex:
            rcs = dict(ex.map(g1, jobs))
        for b, bm, cell, arm, task, matched in cells:
            if not matched:
                continue
            cd = os.path.join(sres, cell)
            if not os.path.isfile(os.path.join(cd, "grade.json")) and os.path.isfile(os.path.join(results, cell, "grade.json")):
                rcs[cell] = run_grader(grader_cmd(grader, cd, task, suite, bm, union=True), cd + ".grade.log")
        for b, bm, cell, arm, task, matched in cells:
            for rel in (sessions_of(results, cell) if matched else [cell]):
                r = compare_unit(results, sres, rel)
                r.update(arm=arm, rc=rcs.get(rel))
                res["sessions" if matched else "cells"].append(r)
            if matched:
                r = compare_unit(results, sres, cell)
                r.update(arm=arm, rc=rcs.get(cell))
                res["unions"].append(r)
        if a.inputs and os.path.isfile(a.inputs):
            want = json.load(open(a.inputs, encoding="utf-8")).get("cells") or {}
            for key in sorted(want):
                bt, arm, task, trial = key.split("/")
                rd = run_dir_for_row(sres, {"batch": bt, "arm": arm, "task_id": task, "trial": trial})
                got = file_sha(os.path.join(rd, "grade.json")) if rd else None
                res["inputs_cells"].append({"cell": key, "want": want[key].get("grade_sha256"), "got": got,
                                            "equal": got is not None and got == want[key].get("grade_sha256")})
        log("reproduce: graded")
    # (d) rows: ablation-row.sh per tracked row, as run-ablation.sh calls it
    if "rows" in steps and a.rows:
        tracked = [l for l in open(a.rows, encoding="utf-8").read().split("\n") if l.strip()]
        out_lines = []
        rdir = os.path.join(scratch, "rows")
        os.makedirs(rdir, exist_ok=True)
        for line in tracked:
            row = json.loads(line)
            rd = run_dir_for_row(sres, row)
            ent = {"run_id": row.get("run_id"), "equal": False, "fields": [], "override": False, "error": None}
            if rd is None:
                ent["error"] = "no run dir"
                res["rows"].append(ent)
                out_lines.append("")
                continue
            bm = batch_meta(results, row["batch"])
            tyaml = os.path.join(suite, bm["tasks_dir"], row["task_id"], "task.yaml")
            man = os.path.join(results, row["batch"], "MANIFEST.json")
            cell = os.path.isfile(os.path.join(rd, "meta", "cell.json"))

            def row_once(status=None):
                outp = os.path.join(rdir, "%s.row" % row["run_id"])
                if os.path.exists(outp):
                    os.unlink(outp)
                cmd = ["bash", row_bin, "--run-dir", rd, "--task-yaml", tyaml, "--manifest", man, "--out", outp]
                if not cell:
                    cmd += ["--attempts", str(row.get("attempts") or 1)]
                    if row.get("retry_reason"):
                        cmd += ["--retry-reason", str(row["retry_reason"])]
                    prior = (row.get("all_spend_usd") or 0) - (row.get("cost_usd") or 0)
                    if prior > 0:
                        cmd += ["--prior-spend", repr(round(prior, 6))]
                if status:
                    cmd += ["--status", status]
                with open(outp + ".log", "w", encoding="utf-8") as lf:
                    rc = subprocess.run(cmd, stdout=lf, stderr=subprocess.STDOUT).returncode
                if rc != 0 or not os.path.isfile(outp):
                    return None
                p = subprocess.run(["jq", "-c", "."], stdin=open(outp, encoding="utf-8"), capture_output=True, text=True)
                return p.stdout.strip() if p.returncode == 0 else None

            new = row_once()
            if new is None:
                ent["error"] = "ablation-row.sh failed"
            else:
                nr = json.loads(new)
                if canon(nr) != canon(row) and nr.get("status") != row.get("status"):
                    alt = row_once(status=row.get("status"))
                    if alt is not None and canon(json.loads(alt)) == canon(row):
                        new, nr, ent["override"] = alt, json.loads(alt), True
                ent["fields"] = sorted(k for k in set(nr) | set(row) if canon(nr.get(k)) != canon(row.get(k)))
                ent["equal"] = not ent["fields"]
                ent["bytes_equal"] = new == line
            out_lines.append(new or "")
            res["rows"].append(ent)
        rows_out = os.path.join(scratch, "rows.jsonl")
        with open(rows_out, "w", encoding="utf-8") as f:
            f.write("".join(l + "\n" for l in out_lines if l))
        res["rows_file"] = {"want": file_sha(a.rows), "got": file_sha(rows_out)}
        log("reproduce: rowed %d (%d equal)" % (len(res["rows"]), sum(1 for r in res["rows"] if r["equal"])))
    # (e) reads
    if "reads" in steps and a.rows:
        rows_out = os.path.join(scratch, "rows.jsonl")
        rdo = os.path.join(scratch, "reads")
        os.makedirs(rdo, exist_ok=True)
        base = ["python3", "-I", reads_bin, "--rows", rows_out, "--results-root", sres]

        def reads(args, label):
            with open(os.path.join(rdo, label + ".log"), "w", encoding="utf-8") as lf:
                return subprocess.run(base + args, stdout=lf, stderr=subprocess.STDOUT, cwd=rr).returncode

        rc = reads(["--make-inputs", "--out", rdo, "--pin", a.pin, "--label-set", "v2", "--suite-root", suite], "make-inputs")
        res["reads"].append({"artefact": "INPUTS.json", "rc": rc, "want": file_sha(a.inputs) if a.inputs else None,
                             "got": file_sha(os.path.join(rdo, "INPUTS.json"))})
        common = ["--inputs", os.path.join(rdo, "INPUTS.json"), "--registration", a.registration, "--out", rdo]
        fin = ["--final", "--name", "final"] + (["--power", a.power] if a.power else [])
        if a.judge and os.path.exists(a.judge):
            fin += ["--judge", a.judge]
        if a.sensitivity_grades and os.path.isdir(a.sensitivity_grades):
            fin += ["--sensitivity-grades", a.sensitivity_grades]
        rc = reads(common + fin, "final")
        for ext in ("md", "json"):
            res["reads"].append({"artefact": "final.%s" % ext, "rc": rc,
                                 "want": file_sha(os.path.join(a.tracked_reads, "final.%s" % ext)) if a.tracked_reads else None,
                                 "got": file_sha(os.path.join(rdo, "final.%s" % ext))})
        rc = reads(common + ["--placebo", "--name", "placebo-phase1"], "placebo")
        for ext in ("md", "json"):
            res["reads"].append({"artefact": "placebo-phase1.%s" % ext, "rc": rc,
                                 "want": file_sha(os.path.join(a.tracked_reads, "placebo-phase1.%s" % ext)) if a.tracked_reads else None,
                                 "got": file_sha(os.path.join(rdo, "placebo-phase1.%s" % ext))})
        log("reproduce: reads done")
    return res


def classes(res):
    def tally(lst, key="grade_equal"):
        graded = [r for r in lst if r.get("recorded_graded", True)]
        return len(graded), sum(1 for r in graded if r.get(key))
    t = []
    for label, lst, key in (("session grade.json", res["sessions"], "grade_equal"),
                            ("session gates-combined.md", res["sessions"], "combined_equal"),
                            ("pipeline-cell grade.json", res["cells"], "grade_equal"),
                            ("pipeline-cell gates-combined.md", res["cells"], "combined_equal"),
                            ("union-cell grade.json", res["unions"], "grade_equal"),
                            ("union-cell gates-combined.md", res["unions"], "combined_equal"),
                            ("INPUTS.json cells[*].grade_sha256", res["inputs_cells"], "equal"),
                            ("rows (canonical JSON)", res["rows"], "equal"),
                            ("rows (bytes)", res["rows"], "bytes_equal")):
        n, k = tally(lst, key)
        t.append((label, n, k))
    ungraded = sum(1 for kind in ("sessions", "cells", "unions") for r in res[kind] if not r.get("recorded_graded", True))
    t.append(("not graded in the record (skipped, listed below)", ungraded, ungraded))
    return t


def write_report(res, path, env=None):
    lines = ["# cycle-132 reproduction report", "",
             "Written by `evals/analysis/c132/reproduce.sh` from a fresh clone of the stage-1 record commit. "
             "Every count below is recorded vs reproduced; an artefact is equal when its sha256 (or, for a row, its "
             "canonical JSON) matches the record.", "", "## Environment", ""]
    if env:
        for k in sorted(env):
            lines.append("- %s: `%s`" % (k, env[k]))
    else:
        lines.append("- (no environment block passed)")
    lines += ["", "## Hash table", "", "| artefact class | count | equal | differ |", "|---|---:|---:|---:|"]
    for label, n, k in classes(res):
        lines.append("| %s | %d | %d | %d |" % (label, n, k, n - k))
    if res.get("rows_file"):
        rf = res["rows_file"]
        lines.append("| rows.jsonl file sha256 | 1 | %d | %d |" % (int(rf["want"] == rf["got"] and rf["got"] is not None),
                                                               int(not (rf["want"] == rf["got"] and rf["got"] is not None))))
    for r in res["reads"]:
        eq = r["want"] is not None and r["want"] == r["got"]
        lines.append("| %s | 1 | %d | %d |" % (r["artefact"], int(eq), int(not eq)))
    lines += ["", "## Reads (recorded vs reproduced sha256)", "", "| artefact | recorded | reproduced | rc |", "|---|---|---|---:|"]
    if res.get("rows_file"):
        lines.append("| rows.jsonl | `%s` | `%s` | |" % (res["rows_file"]["want"], res["rows_file"]["got"]))
    for r in res["reads"]:
        lines.append("| %s | `%s` | `%s` | %s |" % (r["artefact"], r["want"], r["got"], r["rc"]))
    lines += ["", "## Differences", ""]
    diffs = []
    skipped = []
    for kind in ("sessions", "cells", "unions"):
        for r in res[kind]:
            if not r.get("recorded_graded", True):
                skipped.append("- %s %s" % (kind[:-1], r["run_dir"]))
                continue
            if not r["grade_equal"]:
                diffs.append("- %s %s: grade.json recorded `%s` reproduced `%s` (grader exit %s)" % (
                    kind[:-1], r["run_dir"], r["recorded"], r["reproduced"], r.get("rc")))
            elif not r["combined_equal"]:
                diffs.append("- %s %s: gates-combined.md differs" % (kind[:-1], r["run_dir"]))
    for r in res["inputs_cells"]:
        if not r["equal"]:
            diffs.append("- INPUTS cell %s: want `%s` got `%s`" % (r["cell"], r["want"], r["got"]))
    for r in res["rows"]:
        if not r["equal"]:
            diffs.append("- row %s: %s" % (r["run_id"], r["error"] or "fields differ: " + ", ".join(r["fields"])))
    for e in res["reconstruct_errors"]:
        diffs.append("- reconstruction: %s" % e)
    lines += diffs or ["None."]
    lines += ["", "## Not graded in the record", "",
              "Run directories the record holds without a grade.json (the runner never graded them: a run interrupted by a host reboot, "
              "a session superseded by a retry, an invalid session) — not graded here either, excluded from every count above."]
    lines += skipped or ["None."]
    ov = [r["run_id"] for r in res["rows"] if r.get("override")]
    if ov:
        lines += ["", "Rows re-rowed with the recorded status as `--status` (the runner's override, as run-ablation.sh "
                  "passes it): %s." % ", ".join(ov)]
    lines += ["", "## Sampled live rerun", "",
              "Left for the lead: the registered live sample (REPRODUCE.md § Live rerun) runs with "
              "`reproduce.sh --live-sample FILE` and needs model credentials; its grades are reported against the "
              "arm's recorded range here.", ""]
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    return all(n == k for _l, n, k in classes(res)) and not res["reconstruct_errors"] and all(
        r["want"] is not None and r["want"] == r["got"] for r in res["reads"]) and (
        not res.get("rows_file") or res["rows_file"]["want"] == res["rows_file"]["got"])


# ---------------------------------------------------------------- CLI
def main(argv=None):
    ap = argparse.ArgumentParser(prog="record_lite.py", description=__doc__.split("\n")[0])
    sp = ap.add_subparsers(dest="cmd")
    b = sp.add_parser("build")
    b.add_argument("--results-root", required=True)
    b.add_argument("--batches", required=True)
    b.add_argument("--fixtures-root", required=True)
    b.add_argument("--suite-root", required=True)
    b.add_argument("--out", required=True)
    b.add_argument("--only", nargs="+")
    b.add_argument("--check", type=int, default=0)
    b.add_argument("--check-unit", action="append", default=[])
    b.add_argument("--seed", type=int, default=SEED)
    b.add_argument("--grader", default=os.environ.get("LOA_C132_GRADER") or os.path.join(REPO, "evals", "harness", "ablation-grade.sh"))
    b.add_argument("--scratch")
    b.add_argument("--jobs", type=int, default=2)
    b.add_argument("--no-build", action="store_true", help="only --check against an existing --out")
    r = sp.add_parser("reconstruct")
    r.add_argument("--record-root", required=True)
    r.add_argument("--lite-root", required=True)
    r.add_argument("--fixtures-root", required=True)
    r.add_argument("--suite-root", required=True)
    r.add_argument("--dest", required=True)
    r.add_argument("rel", nargs="+")
    p = sp.add_parser("reproduce")
    p.add_argument("--record-root", required=True)
    p.add_argument("--results-rel", default=os.path.join("evals", "results", "ablation-2.0"))
    p.add_argument("--lite-root")
    p.add_argument("--fixtures-root")
    p.add_argument("--suite-root")
    p.add_argument("--scratch", required=True)
    p.add_argument("--batches")
    p.add_argument("--jobs", type=int, default=4)
    p.add_argument("--grader")
    p.add_argument("--row-bin")
    p.add_argument("--reads-bin")
    p.add_argument("--rows")
    p.add_argument("--inputs")
    p.add_argument("--tracked-reads")
    p.add_argument("--registration")
    p.add_argument("--power")
    p.add_argument("--judge")
    p.add_argument("--sensitivity-grades")
    p.add_argument("--pin", default="fbd36a0c9880b244af08133013f3b6959b085c94")
    p.add_argument("--steps", default="reconstruct,grade,rows,reads,report")
    p.add_argument("--env-json")
    p.add_argument("--report")
    p.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    if not a.cmd:
        ap.print_help(sys.stderr)
        return 2
    try:
        if a.cmd == "build":
            rr, fx, su = (os.path.abspath(x) for x in (a.results_root, a.fixtures_root, a.suite_root))
            out = os.path.abspath(a.out)
            batches = [x for x in a.batches.split(",") if x]
            only = set(a.only) if a.only else None
            if not a.no_build:
                build(rr, batches, fx, su, out, only)
            if a.check or a.check_unit:
                scratch = a.scratch or tempfile.mkdtemp(prefix="record-lite-check.")
                rows = check(rr, out, fx, su, batches, a.check, a.seed, os.path.abspath(a.grader), scratch,
                             a.check_unit, only, a.jobs)
                if not all(x["grade_equal"] for x in rows):
                    return 1
            return 0
        if a.cmd == "reconstruct":
            for rel in a.rel:
                cell = "/".join(rel.split("/")[:3])
                matched = os.path.isfile(os.path.join(a.record_root, cell, "meta", "cell.json"))
                if rel == cell:
                    reconstruct_cell(a.record_root, a.lite_root, a.fixtures_root, cell, matched, a.dest)
                else:
                    reconstruct_run_dir(a.record_root, a.lite_root, a.fixtures_root, rel, a.dest)
                print("reconstructed %s" % rel)
            return 0
        res = reproduce(a)
        if res.get("dry_run"):
            return 0
        if "report" in a.steps.split(","):
            env = json.load(open(a.env_json, encoding="utf-8")) if a.env_json else None
            rp = a.report or os.path.join(a.record_root, "grimoires", "loa", "a2a", "sprint-271", "reproduction", "report.md")
            ok = write_report(res, rp, env)
            with open(os.path.join(os.path.abspath(a.scratch), "reproduce-result.json"), "w", encoding="utf-8") as f:
                f.write(json.dumps(res, indent=2, sort_keys=True) + "\n")
            print("report: %s (%s)" % (rp, "every hash equal" if ok else "DIFFERENCES — see the report"))
            return 0 if ok else 1
        return 0
    except Refusal as e:
        print("record_lite: refused: %s" % e, file=sys.stderr)
        return 1
    except Mismatch as e:
        print("record_lite: mismatch: %s" % e, file=sys.stderr)
        return 1
    except InputError as e:
        print("record_lite: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
