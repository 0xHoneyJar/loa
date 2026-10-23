#!/usr/bin/env python3
"""judge_defects.py — EXPLORATORY / post hoc defect-level judge read (DEC-0800, DEC-0810).

Usage:
  python3 -I evals/analysis/c132/judge_defects.py sample --key KEY --rows F --results-root DIR [--results-root DIR …]
      --descriptions FILE --out DIR [--seed 20261021] [--per-arm 40] [--suite-root DIR …] [--repo-root DIR]
  python3 -I evals/analysis/c132/judge_defects.py aggregate --key OUT/key.json --labels DIR|FILE --rows F --out DIR
      [--seed N] [--boot 2000]

sample: per arm, a seeded uniform draw of --per-arm grader-credited (cell, defect) pairs over the
valid cells of the Task 2.6 judge universe (KEY = judge-sample.sh's key.json; its `credited` units;
all pairs when the arm has fewer); every credited unit of a sampled pair (every grader-credited
citation) becomes one packet item OUT/packets/D0001.md … built exactly like judge-sample.sh's pair
items (the finding text from the run directory, the cited head lines ±5, the blind defect
description, the defect head line; never the arm, trial, batch, run id or grader decision), in
seeded shuffled order. The provenance scan is judge-sample.sh's: any packet line carrying a
provenance field or token (arm ids exempt only when the PR's own text carries them) refuses the
whole run, nothing written. OUT/key.json (outside the packets) holds the per-arm universe counts,
the sampled pairs with their item ids and inclusion probabilities, the items, the valid cells and
the seed. A cell is valid when the source key holds it and common.py's validity filter passes on
its row and grade.json. OUT/packets must not already hold files.

aggregate: --labels is a merged labels.json {D0001: {verdict, note}} or a directory of judge
sessions (every <DIR>/<session>/labels.json, sessions named *.failed-* skipped; an item labelled
twice is refused). Per arm: the share of sampled pairs with >= 1 citation judged `describes`
(strict) and `describes` or `partially` (lenient) — a pair enters only when every one of its items
is labelled — with PR-cluster bootstrap 95 % percentile intervals; grader recall (credited pairs /
defects over the arm's valid cells) and defect-level corrected recall = grader recall x share, its
interval from the same PR resamples; a1_full - a0_bare_matched (PRs resampled jointly); per-PR
counts. OUT/result.json + OUT/result.md: sorted keys, %.4f floats, no timestamps, no absolute paths.

Exit: 0 written; 1 inputs invalid, or a packet would carry a provenance field (nothing written);
2 usage. Standard library only; no model calls.
"""
import argparse
import hashlib
import json
import os
import random
import re
import sys

if __package__ in (None, ""):
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from c132 import common, stats  # noqa: E402
from c132.common import InputError  # noqa: E402
from c132.reads import dumps, f4, iv  # noqa: E402

PAIR_VERDICTS = ("describes", "partially", "does-not-describe")
WIN, CTX = 3, 5
DIFF = ("a1_full", "a0_bare_matched")
LABEL = "EXPLORATORY / post hoc (DEC-0800, DEC-0810)"
REPO_DEFAULT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


# ------------------------------------------------- packet building: mirrors evals/harness/judge-sample.sh
def task_meta(suites):
    out = {}
    fx = re.compile(r"fixture:\s*([A-Za-z0-9_./-]+)")
    mf = re.compile(r"manifest:\s*([A-Za-z0-9_./-]+)")
    for root in suites:
        tdir = os.path.join(root, "tasks")
        if not os.path.isdir(tdir):
            continue
        for t in sorted(os.listdir(tdir)):
            p = os.path.join(tdir, t, "task.yaml")
            if t in out or not os.path.isfile(p):
                continue
            with open(p, encoding="utf-8") as f:
                for line in f:
                    if line.startswith("review_catch:"):
                        a, b = fx.search(line), mf.search(line)
                        if a and b:
                            out[t] = {"fixture": a.group(1).rstrip(",}"), "manifest": b.group(1).rstrip(",}")}
                        break
    return out


def inside(base, rel):
    p = os.path.realpath(os.path.join(base, rel))
    return p if p == os.path.realpath(base) or p.startswith(os.path.realpath(base) + os.sep) else None


def strip_side(p):
    for pre in ("head/", "base/"):
        if p.startswith(pre):
            return p[len(pre):]
    return p


def path_matches(cited, defect_file):
    for pre in ("head/", "base/"):
        if cited.startswith(pre):
            cited = cited[len(pre):]
    if cited == defect_file or defect_file.endswith("/" + cited):
        return True
    return cited == defect_file.rsplit("/", 1)[-1]


LINE = re.compile(r"^(?P<p>\S+?):(?P<a>\d{1,6})(?:-(?P<b>\d{1,6}))?$")


def regions(run_dir):
    p = os.path.join(run_dir, "grading", "gates-combined.md")
    out = []
    if not os.path.isfile(p) or os.path.islink(p):
        return None
    with open(p, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = LINE.match(line.strip())
            if m:
                a = int(m.group("a"))
                b = int(m.group("b") or a)
                out.append((m.group("p"), min(a, b), max(a, b)))
    return sorted(set(out))


TRAILER = re.compile(r"<!--\s*LOA-VERDICT.*?-->", re.S)


def sources(run_dir):
    """the arm's own texts (paragraph lists) for the finding text"""
    texts = []
    dirs = [run_dir]
    sd = os.path.join(run_dir, "sessions")
    if os.path.isdir(sd):
        dirs += [os.path.join(sd, s) for s in sorted(os.listdir(sd))]
    for d in dirs:
        for rel in ("sandbox/review.md", "sandbox/grimoires/loa/a2a/sprint-1/engineer-feedback.md",
                    "sandbox/grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md"):
            p = os.path.join(d, rel)
            if os.path.isfile(p) and not os.path.islink(p):
                with open(p, encoding="utf-8", errors="replace") as f:
                    texts.append(TRAILER.sub("", f.read()))
        for g in ("review", "audit"):
            p = os.path.join(d, "eval", "adversarial-%s.json" % g)
            if os.path.isfile(p) and not os.path.islink(p):
                try:
                    with open(p, encoding="utf-8") as f:
                        env = json.load(f)
                except ValueError:
                    continue
                for fd in env.get("findings") or []:
                    if isinstance(fd, dict):
                        bits = [str(fd.get(k)) for k in ("title", "description", "file", "anchor_line", "evidence")
                                if fd.get(k) not in (None, "")]
                        if fd.get("file") and isinstance(fd.get("anchor_line"), int):
                            bits.append("%s:%d" % (fd["file"], fd["anchor_line"]))
                        texts.append(" — ".join(bits))
    paras = []
    for t in texts:
        paras += [p.strip() for p in re.split(r"\n\s*\n", t) if p.strip()]
    return paras


def finding_text(paras, region):
    path, a, b = region
    base = re.escape(strip_side(path).rsplit("/", 1)[-1])
    pat = re.compile(base + r"[`*)\]]{0,3}:(%d|%d)(?!\d)" % (a, b))
    for p in paras:
        if pat.search(p):
            return p[:1500] + (" …" if len(p) > 1500 else "")
    return None


def gap(region, site):
    _, a, b = region
    return max(0, a - site, site - b)


def sites_of(d):
    return [s for s in (d.get("anchors") or [d.get("anchor_line")]) if isinstance(s, int)]


WALK_CAP = 200000
PR_FILES = {"pr/PR.md": "PR.md", "PR.md": "PR.md", "pr/head.diff": "head.diff"}
_head_files = {}


def head_files(fixture_dir):
    if fixture_dir not in _head_files:
        top, found = os.path.join(fixture_dir, "head"), []
        if os.path.isdir(top) and not os.path.islink(top):
            for d, dns, fns in os.walk(top, followlinks=False):
                dns[:] = sorted(n for n in dns if not os.path.islink(os.path.join(d, n)))
                for n in sorted(fns):
                    q = os.path.join(d, n)
                    if os.path.isfile(q) and not os.path.islink(q):
                        found.append(os.path.relpath(q, top).replace(os.sep, "/"))
                if len(found) >= WALK_CAP:
                    break
        _head_files[fixture_dir] = found[:WALK_CAP]
    return _head_files[fixture_dir]


def resolve_cited(fixture_dir, rel, defect_file):
    cited = strip_side(rel)
    if not fixture_dir:
        return None, "head/" + cited, "unresolved"
    head = os.path.join(fixture_dir, "head")
    p = inside(head, cited)
    if p and os.path.isfile(p):
        return p, "head/" + cited, "exact"
    if defect_file and defect_file.endswith("/" + cited):
        p = inside(head, defect_file)
        if p and os.path.isfile(p):
            return p, "head/" + defect_file, "defect_suffix"
    hits = [f for f in head_files(fixture_dir) if f.endswith("/" + cited)]
    if len(hits) == 1:
        p = inside(head, hits[0])
        if p and os.path.isfile(p):
            return p, "head/" + hits[0], "unique_suffix"
    if cited in PR_FILES:
        q = os.path.join(fixture_dir, PR_FILES[cited])
        if os.path.isfile(q) and not os.path.islink(q):
            return q, PR_FILES[cited], "pr_file"
    return None, "head/" + cited, "unresolved"


def head_lines(p, a, b):
    if not p:
        return None
    with open(p, encoding="utf-8", errors="replace") as f:
        lines = f.read().split("\n")
    lo, hi = max(1, a - CTX), min(len(lines), b + CTX)
    return "\n".join("%6d  %s" % (i, lines[i - 1]) for i in range(lo, hi + 1))


def fence(text):
    n = 3
    for m in re.finditer(r"`{3,}", text or ""):
        n = max(n, len(m.group(0)) + 1)
    return "`" * n


def load_descriptions(path):
    """{fixture: {defect id: text}} from defect-descriptions.py's output"""
    doc = common.load_json(path, "descriptions file")
    fx = doc.get("fixtures") if isinstance(doc, dict) and doc.get("schema_version") == 1 else None
    if not isinstance(fx, dict):
        raise InputError("descriptions file is not schema_version 1 with a fixtures object: %s" % path)
    out = {}
    for name, ds in fx.items():
        if not isinstance(ds, dict):
            raise InputError("descriptions file: fixture %s is not an object" % name)
        for did, e in ds.items():
            t = e.get("text") if isinstance(e, dict) else None
            if isinstance(t, str) and t.strip():
                out.setdefault(name, {})[did] = " ".join(t.split())
    return out


FIELD = re.compile(r"^\s*(arm|trial|batch|run_id|stratum|grader[_ ]decision)\s*[:=]", re.I | re.M)
NATIVE_CAP = 8 << 20
_native = {}


def pr_native(fixture_dir):
    if not fixture_dir:
        return ""
    if fixture_dir not in _native:
        paths = [os.path.join(fixture_dir, n) for n in ("PR.md", "head.diff")]
        for side in ("head", "base"):
            top = os.path.join(fixture_dir, side)
            if os.path.isdir(top) and not os.path.islink(top):
                for d, dns, fns in os.walk(top, followlinks=False):
                    dns.sort()
                    paths += [os.path.join(d, n) for n in sorted(fns)]
        parts = []
        for p in paths:
            if os.path.isfile(p) and not os.path.islink(p):
                with open(p, "rb") as f:
                    parts.append(f.read(NATIVE_CAP).decode("utf-8", "replace"))
        _native[fixture_dir] = "\n".join(parts)
    return _native[fixture_dir]


def provenance_tokens(rows):
    """(forbidden, strict): every row's arm, batch, run id and cell key; strict = all but arm ids"""
    forbidden, arm_ids = set(), set()
    for r in rows:
        for k in ("arm", "batch", "run_id"):
            if r.get(k):
                forbidden.add(str(r[k]))
        if r.get("arm"):
            arm_ids.add(str(r["arm"]))
        forbidden.add(common.cell_key(r))
    return forbidden, forbidden - arm_ids


class Leak(Exception):
    """a packet would carry a provenance field (exit 1, nothing written)"""


def build_packet(iid, u, descriptions):
    """(body, resolution, description source, quoted texts) for one credited unit u with its
    _text, _fixture, _man, _fxname — judge-sample.sh's pair-item layout"""
    L = ["# Judge item %s\n\n" % iid,
         "Does the finding describe the labelled defect? `describes`, `partially`, or `does-not-describe`.\n\n",
         "## Finding\n\n"]
    quoted = []
    txt = u["_text"] or "(the finding's prose could not be located; the citation only)"
    fz = fence(txt)
    L.append("%s text\n%s\n%s\n\n" % (fz, txt, fz))
    d = u["_man"][int(u["defect"][1:]) - 1]
    rp, shown, resolution = resolve_cited(u["_fixture"], u["region"][0], d.get("file"))
    hl = head_lines(rp, u["region"][1], u["region"][2])
    note = "" if resolution in ("exact", "unresolved") else "; cited as %s" % strip_side(u["region"][0])
    L.append("## Cited lines: %s:%d-%d (±%d%s)\n\n" % (shown, u["region"][1], u["region"][2], CTX, note))
    if hl is None:
        L.append("(the file is not in the PR's head tree)\n\n")
    else:
        fz = fence(hl)
        L.append("%s text\n%s\n%s\n\n" % (fz, hl, fz))
        quoted.append(hl)
    desc = descriptions.get(u["_fxname"], {}).get(str(d.get("id", "")))
    dsource = "annotators"
    if not desc:
        desc, dsource = d.get("description"), "manifest"
    if not desc:
        desc = re.sub(r"^[A-Za-z]?\d+-", "", str(d.get("id", ""))).replace("-", " ")
        dsource = "id_fallback"
    L.append("## Labelled defect\n\nFile: `%s`; anchor lines: %s.\n\nDescription: %s\n" % (
        d.get("file"), ", ".join(str(s) for s in sites_of(d)), desc))
    if d.get("must_match") and not str(d["must_match"]).startswith("@L"):
        fz = fence(str(d["must_match"]))
        L.append("\nHead line:\n\n%s text\n%s\n%s\n" % (fz, d["must_match"], fz))
        quoted.append(str(d["must_match"]))
    return "".join(L), resolution, dsource, quoted


def leak_scan(iid, body, quoted, fixture_dir, forbidden, strict):
    """judge-sample.sh's scan: the exempt tokens/lines, or raise Leak"""
    scan = body
    for q in quoted:
        scan = scan.replace(q, "")
    native, exempt = None, []
    for m in FIELD.finditer(scan):
        end = scan.find("\n", m.start())
        whole = scan[m.start():end if end >= 0 else len(scan)].strip()
        native = pr_native(fixture_dir) if native is None else native
        if not whole or whole not in native:
            raise Leak("packet %s would carry a provenance field (%s)" % (iid, m.group(0).strip()))
        exempt.append(whole)
    for tok in sorted(forbidden):
        if tok in scan:
            native = pr_native(fixture_dir) if native is None else native
            if tok in strict or tok not in native:
                raise Leak("packet %s would carry a provenance field (%s)" % (iid, tok))
            exempt.append(tok)
    return sorted(set(exempt))


# ------------------------------------------------------------------------------------- sample
def sample(src_key, rows, roots, suites, repo, descriptions, seed, per_arm):
    """(packets {id: body}, key doc) — pure apart from reading the run dirs and fixtures"""
    if src_key.get("all_cells"):
        raise InputError("source key enumerates invalid cells (--all-cells); the read needs the valid-cell universe")
    meta = task_meta(suites)
    by_key = {common.cell_key(r): r for r in rows}
    cells, invalid, ctx = {}, [], {}
    for ck, cell in sorted(src_key.get("cells", {}).items()):
        r = by_key.get(ck)
        if r is None:
            raise InputError("source key cell %s has no row" % ck)
        rd = common.run_dir_for(r, roots)
        if not rd:
            raise InputError("no run directory for %s under the results roots" % ck)
        root_of = next(rt for rt in roots if os.path.realpath(rd).startswith(os.path.realpath(rt) + os.sep))
        if os.path.relpath(rd, root_of) != cell.get("run_dir"):
            raise InputError("cell %s: run directory %s differs from the source key's %s"
                             % (ck, os.path.relpath(rd, root_of), cell.get("run_dir")))
        g, _gp = common.load_grade(rd)
        if not common.build_cell(r, g)["valid"]:
            invalid.append(ck)
            continue
        cells[ck] = {k: cell[k] for k in ("arm", "task", "trial", "defects", "credited")}
        ctx[ck] = rd
    units = [u for u in src_key.get("universe", []) if u.get("class") == "credited" and u.get("cell") in cells]
    pairs = {}
    for u in units:
        pairs.setdefault((u["cell"], u["defect"]), []).append(u)
    for (ck, did) in pairs:
        if did not in cells[ck]["credited"]:
            raise InputError("credited unit for %s %s but the cell's credited list lacks it" % (ck, did))
    for ck, c in cells.items():
        for did in c["credited"]:
            if (ck, did) not in pairs:
                raise InputError("cell %s credits %s with no credited unit" % (ck, did))
    by_arm = {}
    for (ck, did) in sorted(pairs, key=lambda p: (p[0], int(p[1][1:]))):
        by_arm.setdefault(cells[ck]["arm"], []).append((ck, did))
    rng = random.Random(seed)
    universe, sampled_pairs = {}, []
    arms = sorted({c["arm"] for c in cells.values()})
    for arm in arms:
        ps = by_arm.get(arm, [])
        n = min(len(ps), per_arm)
        pick = rng.sample(ps, n) if n < len(ps) else list(ps)
        acells = [c for c in cells.values() if c["arm"] == arm]
        universe[arm] = {"cells": len(acells), "prs": len({c["task"] for c in acells}),
                         "defects": sum(c["defects"] for c in acells),
                         "credited_pairs": len(ps), "credited_units": sum(len(pairs[p]) for p in ps),
                         "sampled_pairs": n, "sampled_units": sum(len(pairs[p]) for p in pick),
                         "pi": n / float(len(ps)) if ps else None}
        sampled_pairs += sorted(pick, key=lambda p: (p[0], int(p[1][1:])))
    # per-cell context for the packets (each sampled cell read once)
    paras_of, man_of = {}, {}
    for ck in sorted({p[0] for p in sampled_pairs}):
        c = cells[ck]
        tm = meta.get(c["task"])
        if not tm:
            raise InputError("no task.yaml with review_catch for task %s under the suite roots" % c["task"])
        mpath = inside(repo, tm["manifest"])
        if not mpath or not os.path.isfile(mpath):
            raise InputError("manifest not found for %s: %s" % (c["task"], tm["manifest"]))
        fixture_rel = tm["fixture"] if tm["fixture"].startswith("evals/") else os.path.join("evals/fixtures", tm["fixture"])
        with open(mpath, encoding="utf-8") as f:
            man = json.load(f)
        defects = man.get("defects") or []
        if len(defects) != c["defects"]:
            raise InputError("cell %s: manifest has %d defects, the source key %d" % (ck, len(defects), c["defects"]))
        man_of[ck] = (inside(repo, fixture_rel), defects,
                      str(man.get("fixture") or os.path.basename(tm["fixture"].rstrip("/"))))
        regs = regions(ctx[ck])
        if regs is None:
            raise InputError("cell %s: grading/gates-combined.md missing" % ck)
        paras_of[ck] = (sources(ctx[ck]), set(regs))
    work = []
    pair_ids = {}
    for i, (ck, did) in enumerate(sampled_pairs, 1):
        pair_ids[(ck, did)] = "P%03d" % i
        fixture_dir, defects, fxname = man_of[ck]
        d = defects[int(did[1:]) - 1]
        for u in sorted(pairs[(ck, did)], key=lambda x: x["unit"]):
            reg = tuple(u["region"])
            if reg not in paras_of[ck][1]:
                raise InputError("unit %s: region %s not in the cell's gates-combined.md" % (u["unit"], list(reg)))
            if not (path_matches(reg[0], d.get("file", "")) and any(gap(reg, s) <= WIN for s in sites_of(d))):
                raise InputError("unit %s: region %s does not credit %s under the ±%d rule" % (u["unit"], list(reg), did, WIN))
            work.append(dict(u, _text=finding_text(paras_of[ck][0], reg), _fixture=fixture_dir, _man=defects,
                             _fxname=fxname, pair=pair_ids[(ck, did)]))
    prng = random.Random("%d:packets" % seed)
    work.sort(key=lambda u: u["unit"])
    prng.shuffle(work)
    forbidden, strict = provenance_tokens(rows)
    packets, items, exempt_log = {}, {}, []
    for j, u in enumerate(work, 1):
        iid = "D%04d" % j
        body, resolution, dsource, quoted = build_packet(iid, u, descriptions)
        for tok in leak_scan(iid, body, quoted, u["_fixture"], forbidden, strict):
            exempt_log.append({"item": iid, "token": tok, "reason": "pr_native"})
        packets[iid] = body
        items[iid] = {k: u[k] for k in ("unit", "cell", "arm", "task", "trial", "class", "region", "defect",
                                         "grader_credit", "pair")}
        items[iid]["cited_path_resolution"] = resolution
        items[iid]["description_source"] = dsource
    item_of_pair = {}
    for iid, it in sorted(items.items()):
        item_of_pair.setdefault(it["pair"], []).append(iid)
    pair_doc = {}
    for (ck, did), pid in pair_ids.items():
        c = cells[ck]
        pair_doc[pid] = {"cell": ck, "arm": c["arm"], "pr": c["task"], "trial": c["trial"], "defect": did,
                         "items": item_of_pair.get(pid, []), "units": sorted(u["unit"] for u in pairs[(ck, did)]),
                         "inclusion_probability": universe[c["arm"]]["pi"]}
    doc = {"schema_version": 1, "read": "defect-level judge, " + LABEL, "seed": seed, "per_arm": per_arm,
           "window": WIN, "universe": universe, "pairs": pair_doc, "items": items, "cells": cells,
           "invalid_cells_skipped": sorted(invalid), "provenance_exempt": exempt_log,
           "source_key": {"universe_units": len(src_key.get("universe", [])),
                          "credited_units": sum(1 for u in src_key.get("universe", []) if u.get("class") == "credited"),
                          "seed": src_key.get("seed")}}
    return packets, doc


def write_sample(out, packets, doc, src_key_sha):
    pdir = os.path.join(out, "packets")
    if os.path.isdir(pdir) and os.listdir(pdir):
        raise InputError("%s already holds files; use a fresh --out" % pdir)
    doc["source_key"]["sha256"] = src_key_sha
    os.makedirs(pdir, exist_ok=True)
    for iid, body in sorted(packets.items()):
        with open(os.path.join(pdir, iid + ".md"), "w", encoding="utf-8") as f:
            f.write(body)
    with open(os.path.join(out, "key.json"), "w", encoding="utf-8") as f:
        f.write(json.dumps(doc, sort_keys=True, indent=1) + "\n")


def print_sample(doc, out=sys.stdout):
    out.write("%s\narm\tcells\tPRs\tdefects\tcredited_pairs\tcredited_units\tsampled_pairs\titems\tpi\n" % LABEL)
    for arm, u in sorted(doc["universe"].items()):
        out.write("%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%s\n" % (arm, u["cells"], u["prs"], u["defects"], u["credited_pairs"],
                                                             u["credited_units"], u["sampled_pairs"], u["sampled_units"],
                                                             f4(u["pi"])))
    out.write("packets %d; pairs %d; provenance exemptions %d (pr_native); invalid cells skipped %d\n" % (
        len(doc["items"]), len(doc["pairs"]), len(doc["provenance_exempt"]), len(doc["invalid_cells_skipped"])))
    res = ("exact", "defect_suffix", "unique_suffix", "pr_file", "unresolved")
    out.write("cited paths: " + " ".join("%s=%d" % (k, sum(1 for it in doc["items"].values()
                                                           if it["cited_path_resolution"] == k)) for k in res) + "\n")
    out.write("descriptions: " + " ".join("%s=%d" % (k, sum(1 for it in doc["items"].values()
                                                            if it["description_source"] == k))
                                          for k in ("annotators", "manifest", "id_fallback")) + "\n")


# ---------------------------------------------------------------------------------- aggregate
def load_labels(path):
    if os.path.isfile(path):
        return common.load_json(path, "labels.json")
    if not os.path.isdir(path):
        raise InputError("labels path not found: %s" % path)
    merged = {}
    for s in sorted(os.listdir(path)):
        p = os.path.join(path, s, "labels.json")
        if ".failed-" in s or not os.path.isfile(p):
            continue
        doc = common.load_json(p, "labels.json")
        if not isinstance(doc, dict):
            raise InputError("labels.json is not an object: session %s" % s)
        for k, v in doc.items():
            if k in merged:
                raise InputError("item %s labelled in two sessions" % k)
            merged[k] = v
    return merged


def validate(key, labels):
    if not isinstance(labels, dict):
        raise InputError("labels is not an object")
    errs = []
    for iid in sorted(labels):
        if iid not in key["items"]:
            errs.append("label for an unknown item %s" % iid)
            continue
        v = (labels[iid] or {}).get("verdict") if isinstance(labels[iid], dict) else None
        if v not in PAIR_VERDICTS:
            errs.append("%s: verdict %r not in %s" % (iid, v, "|".join(PAIR_VERDICTS)))
    if errs:
        raise InputError("; ".join(errs))


def pair_outcomes(key, labels):
    """{pair id: (arm, pr, strict hit, lenient hit)} over the pairs whose items are all labelled"""
    out, incomplete = {}, []
    for pid, p in sorted(key["pairs"].items()):
        vs = [labels[i]["verdict"] for i in p["items"] if i in labels]
        if len(vs) != len(p["items"]) or not vs:
            incomplete.append(pid)
            continue
        out[pid] = (p["arm"], p["pr"], any(v == "describes" for v in vs),
                    any(v in ("describes", "partially") for v in vs))
    return out, incomplete


def arm_stats(cells, outs, prs):
    """(grader recall, strict share, lenient share, n pairs) over the cells and pair outcomes of the
    PR multiset prs (a resample) — None where a denominator is zero"""
    cnt = {}
    for t in prs:
        cnt[t] = cnt.get(t, 0) + 1
    d = sum(c["defects"] * cnt.get(c["task"], 0) for c in cells)
    cr = sum(len(c["credited"]) * cnt.get(c["task"], 0) for c in cells)
    n = sum(cnt.get(o[1], 0) for o in outs)
    s = sum(cnt.get(o[1], 0) for o in outs if o[2])
    le = sum(cnt.get(o[1], 0) for o in outs if o[3])
    return (cr / float(d) if d else None, s / float(n) if n else None, le / float(n) if n else None, n)


def ci(vals):
    vals = sorted(v for v in vals if v is not None)
    return [stats.quantile(vals, 0.025), stats.quantile(vals, 0.975)] if vals else None


def mul(a, b):
    return a * b if a is not None and b is not None else None


def figures(cells, outs, prs):
    r, s, le, n = arm_stats(cells, outs, prs)
    return {"recall": r, "strict": s, "lenient": le, "corr_strict": mul(r, s), "corr_lenient": mul(r, le), "n": n}


FIGS = ("strict", "lenient", "corr_strict", "corr_lenient")


def run(key, labels, rows, seed, boot):
    validate(key, labels)
    valid = {c["key"] for c in (common.build_cell(r, None) for r in rows) if c["valid"]}
    missing = sorted(ck for ck in key["cells"] if ck not in valid)
    if missing:
        raise InputError("cells of the key not valid on the rows: %s" % ", ".join(missing))
    outs, incomplete = pair_outcomes(key, labels)
    arms = sorted(key["universe"])
    cells_of = {a: [c for _ck, c in sorted(key["cells"].items()) if c["arm"] == a] for a in arms}
    outs_of = {a: [o for _p, o in sorted(outs.items()) if o[0] == a] for a in arms}
    items_of = {}
    for it in key["items"].values():
        items_of[it["arm"]] = items_of.get(it["arm"], 0) + 1
    per_arm = {}
    for a in arms:
        prs = sorted({c["task"] for c in cells_of[a]})
        est = figures(cells_of[a], outs_of[a], prs)
        rng = random.Random("%d:%s" % (seed, a))
        draws = {k: [] for k in FIGS}
        for _ in range(boot):
            f = figures(cells_of[a], outs_of[a], [prs[rng.randrange(len(prs))] for _ in prs]) if prs else None
            for k in FIGS:
                draws[k].append(f[k] if f else None)
        per_arm[a] = {"cells": len(cells_of[a]), "prs": len(prs), "pairs_sampled": key["universe"][a]["sampled_pairs"],
                      "pairs_judged": est["n"], "items": items_of.get(a, 0),
                      "items_judged": sum(1 for i, it in key["items"].items() if it["arm"] == a and i in labels),
                      "credited_pairs": key["universe"][a]["credited_pairs"],
                      "recall_grader": est["recall"],
                      "share_strict": est["strict"], "share_strict_ci95": ci(draws["strict"]),
                      "share_lenient": est["lenient"], "share_lenient_ci95": ci(draws["lenient"]),
                      "recall_corrected_strict": est["corr_strict"], "recall_corrected_strict_ci95": ci(draws["corr_strict"]),
                      "recall_corrected_lenient": est["corr_lenient"],
                      "recall_corrected_lenient_ci95": ci(draws["corr_lenient"])}
    diff = None
    if all(a in arms for a in DIFF):
        a, b = DIFF
        prs = sorted({c["task"] for c in cells_of[a]} | {c["task"] for c in cells_of[b]})

        def delta(pick):
            fa, fb = figures(cells_of[a], outs_of[a], pick), figures(cells_of[b], outs_of[b], pick)
            return {k: (fa[k] - fb[k]) if fa[k] is not None and fb[k] is not None else None for k in FIGS}
        est = delta(prs)
        rng = random.Random("%d:diff" % seed)
        draws = {k: [] for k in FIGS}
        for _ in range(boot):
            dd = delta([prs[rng.randrange(len(prs))] for _ in prs])
            for k in FIGS:
                draws[k].append(dd[k])
        diff = {"arms": list(DIFF), "prs": len(prs)}
        for k, name in (("strict", "share_strict"), ("lenient", "share_lenient"),
                        ("corr_strict", "recall_corrected_strict"), ("corr_lenient", "recall_corrected_lenient")):
            diff[name] = est[k]
            diff[name + "_ci95"] = ci(draws[k])
            diff[name + "_draws"] = sum(1 for v in draws[k] if v is not None)
    per_pr = {}
    for pid, p in sorted(key["pairs"].items()):
        e = per_pr.setdefault(p["arm"], {}).setdefault(p["pr"], {"pairs": 0, "items": 0, "judged_pairs": 0,
                                                                   "strict": 0, "lenient": 0})
        e["pairs"] += 1
        e["items"] += len(p["items"])
        if pid in outs:
            e["judged_pairs"] += 1
            e["strict"] += int(outs[pid][2])
            e["lenient"] += int(outs[pid][3])
    return {"schema_version": 1, "read": "defect-level judge, " + LABEL, "seed": seed, "boot": boot,
            "items": len(key["items"]), "judged": sum(1 for i in key["items"] if i in labels),
            "pairs": len(key["pairs"]), "incomplete_pairs": incomplete, "per_arm": per_arm, "difference": diff,
            "per_pr": per_pr}


def render_md(doc):
    L = ["# Defect-level judge read — %s\n\n" % LABEL,
         "Not a registered analysis. Per arm a seeded sample of grader-credited (cell, defect) pairs; every credited "
         "citation of a sampled pair judged blind. A pair counts when at least one of its citations is judged `describes` "
         "(strict) or `describes`/`partially` (lenient). Corrected recall = grader recall × share. "
         "%d items, %d judged; %d pairs, %d incomplete; seed %d; %d PR-cluster bootstrap resamples, 95 %% percentile intervals.\n\n"
         % (doc["items"], doc["judged"], doc["pairs"], len(doc["incomplete_pairs"]), doc["seed"], doc["boot"]),
         "## Per arm (EXPLORATORY / post hoc)\n\n"
         "| arm | cells | PRs | pairs judged | items | strict share | 95 % | lenient share | 95 % | grader recall "
         "| corrected strict | 95 % | corrected lenient | 95 % |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"]
    for a, x in sorted(doc["per_arm"].items()):
        L.append("| %s | %d | %d | %d of %d | %d | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n" % (
            a, x["cells"], x["prs"], x["pairs_judged"], x["pairs_sampled"], x["items"],
            f4(x["share_strict"]), iv(x["share_strict_ci95"]), f4(x["share_lenient"]), iv(x["share_lenient_ci95"]),
            f4(x["recall_grader"]), f4(x["recall_corrected_strict"]), iv(x["recall_corrected_strict_ci95"]),
            f4(x["recall_corrected_lenient"]), iv(x["recall_corrected_lenient_ci95"])))
    d = doc["difference"]
    if d:
        L.append("\n## %s − %s (EXPLORATORY / post hoc; PRs resampled jointly, %d PRs)\n\n"
                 "| figure | difference | 95 %% |\n|---|---|---|\n" % (d["arms"][0], d["arms"][1], d["prs"]))
        for k in ("share_strict", "share_lenient", "recall_corrected_strict", "recall_corrected_lenient"):
            L.append("| %s | %s | %s |\n" % (k.replace("_", " "), f4(d[k]), iv(d[k + "_ci95"])))
    L.append("\n## Per PR (EXPLORATORY / post hoc)\n\n| arm | PR | pairs | items | judged pairs | strict | lenient |\n"
             "|---|---|---|---|---|---|---|\n")
    for a in sorted(doc["per_pr"]):
        for pr in sorted(doc["per_pr"][a]):
            e = doc["per_pr"][a][pr]
            L.append("| %s | %s | %d | %d | %d | %d | %d |\n" % (a, pr, e["pairs"], e["items"], e["judged_pairs"],
                                                               e["strict"], e["lenient"]))
    if doc["incomplete_pairs"]:
        L.append("\nIncomplete pairs (an item unlabelled; left out of every share): %s.\n" % ", ".join(doc["incomplete_pairs"]))
    return "".join(L)


# ------------------------------------------------------------------------------------------ CLI
def main(argv=None):
    ap = argparse.ArgumentParser(prog="judge_defects.py")
    sub = ap.add_subparsers(dest="cmd")
    s = sub.add_parser("sample")
    s.add_argument("--key", required=True)
    s.add_argument("--rows", required=True)
    s.add_argument("--results-root", action="append", required=True)
    s.add_argument("--descriptions", required=True)
    s.add_argument("--out", required=True)
    s.add_argument("--seed", type=int, default=20261021)
    s.add_argument("--per-arm", type=int, default=40)
    s.add_argument("--suite-root", action="append", default=[])
    s.add_argument("--repo-root", default=REPO_DEFAULT)
    g = sub.add_parser("aggregate")
    g.add_argument("--key", required=True)
    g.add_argument("--labels", required=True)
    g.add_argument("--rows", required=True)
    g.add_argument("--out", required=True)
    g.add_argument("--seed", type=int)
    g.add_argument("--boot", type=int, default=2000)
    try:
        a = ap.parse_args(sys.argv[1:] if argv is None else argv)
    except SystemExit as e:
        return 2 if e.code else 0
    if a.cmd is None:
        ap.print_usage(sys.stderr)
        return 2
    try:
        if a.cmd == "sample":
            if a.per_arm < 1 or a.seed < 0:
                sys.stderr.write("judge_defects: --per-arm must be >= 1 and --seed >= 0\n")
                return 2
            if not os.path.isdir(a.repo_root):
                raise InputError("repo root not found: %s" % a.repo_root)
            suites = a.suite_root or [os.path.join(a.repo_root, "grimoires/loa/evals", d)
                                      for d in sorted(os.listdir(os.path.join(a.repo_root, "grimoires/loa/evals")))
                                      if os.path.isdir(os.path.join(a.repo_root, "grimoires/loa/evals", d, "tasks"))]
            src = common.load_json(a.key, "source key.json")
            rows = common.load_rows(a.rows)
            packets, doc = sample(src, rows, a.results_root, suites, a.repo_root, load_descriptions(a.descriptions),
                                  a.seed, a.per_arm)
            write_sample(a.out, packets, doc, common.sha256_file(a.key))
            print_sample(doc)
            return 0
        key = common.load_json(a.key, "key.json")
        labels = load_labels(a.labels)
        rows = common.load_rows(a.rows)
        doc = run(key, labels, rows, a.seed if a.seed is not None else int(key.get("seed", 0)), a.boot)
    except Leak as e:
        sys.stderr.write("judge_defects: %s; nothing written\n" % e)
        return 1
    except (InputError, OSError, ValueError, KeyError, TypeError) as e:
        sys.stderr.write("judge_defects: inputs invalid: %s\n" % e)
        return 1
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, "result.json"), "w", encoding="utf-8") as f:
        f.write(dumps(doc))
    with open(os.path.join(a.out, "result.md"), "w", encoding="utf-8") as f:
        f.write(render_md(doc))
    return 0


if __name__ == "__main__":
    sys.exit(main())
