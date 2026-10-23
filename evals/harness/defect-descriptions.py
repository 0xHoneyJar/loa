#!/usr/bin/env python3
"""defect-descriptions.py — a judge-facing description per labelled defect (cycle-132 addendum 14)

Usage:
  python3 -I evals/harness/defect-descriptions.py --manifests-dir DIR --annotation-root DIR
      --fixtures pr-11,pr-14,… --out FILE [--pr-root DIR] [--forbid TOKEN …]

For every defect of every listed fixture's manifest (DIR/<fixture>.json) and each source id its
`source` names (`hunk:H04`, `hunk:H04,H05`, `hunk:H01;incident:I02`, `incident:I01`), collects the
non-empty `description` of the blind Phase 0 annotators' records
(<annotation-root>/<fixture>/{A,B}/labels.json; top level `hunks`/`incidents` or flat by id) —
both, whitespace-normalised, deduplicated, A first then B, never the annotator's identity — and
(the lead's adjudication reason is read for completeness but never written into the text: it is bookkeeping and can name the annotators).

Writes {"schema_version": 1, "fixtures": {fixture: {defect id: {"text", "sources",
"n_descriptions"}}}} (sorted keys, no timestamps). text = one clause per source id joined by
" | " ("Fixing change H04 — <desc>; <desc>", "Incident I01 — …";
a source id with no annotator description reads "H04: no annotator description"), then
"(category: x; severity: y)" from the manifest. A stderr summary counts the source ids without
an annotator description.

Refuses (exit 1, nothing written) when a text carries an arm id (a<digits>_…), the words
"trial" or "arm ", or a --forbid token (batch names, run ids), unless that token also occurs in
the fixture's PR content (PR.md, head.diff, the files under head/ and base/ of
<pr-root>/<fixture>; default pr-root = the manifests directory's parent).

Exit: 0 written; 1 inputs invalid or a refusal; 2 usage.
"""
import argparse
import json
import os
import re
import sys
import tempfile

ANNOTATORS = ("A", "B")
SECTION = {"hunk": "hunks", "incident": "incidents"}
LEAD = {"hunk": "Fixing change", "incident": "Incident"}
ID = re.compile(r"^[HI]\d+$")
FIXTURE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
NATIVE_CAP = 8 << 20
PATTERNS = (re.compile(r"\ba\d+_[A-Za-z0-9_]*"), re.compile(r"\btrial", re.I), re.compile(r"\barm ", re.I))


class Refuse(Exception):
    pass


def load_json(path, what):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        raise Refuse("%s unreadable: %s (%s)" % (what, path, e))


def norm(s):
    return " ".join(s.split()) if isinstance(s, str) else ""


def parse_sources(src, did):
    out = []
    for part in str(src or "").split(";"):
        part = part.strip()
        if not part:
            continue
        kind, _, ids = part.partition(":")
        if kind not in SECTION:
            raise Refuse("defect %s: unknown source kind %r" % (did, part))
        for i in ids.split(","):
            i = i.strip()
            if not ID.match(i):
                raise Refuse("defect %s: bad source id %r" % (did, part))
            out.append((kind, i))
    if not out:
        raise Refuse("defect %s: no source" % did)
    return out


def record(labels, kind, sid):
    if not isinstance(labels, dict):
        return None
    sec = labels.get(SECTION[kind])
    r = sec.get(sid) if isinstance(sec, dict) else labels.get(sid)
    return r if isinstance(r, dict) else None


def annotation(root, fixture):
    base = os.path.join(root, fixture)
    labels = {}
    for a in ANNOTATORS:
        p = os.path.join(base, a, "labels.json")
        labels[a] = load_json(p, "labels") if os.path.isfile(p) else None
    lead = []
    for n in ("adjudication.json", "decisions.json"):
        p = os.path.join(base, n)
        d = load_json(p, n) if os.path.isfile(p) else None
        lead.append(d if isinstance(d, dict) else {})
    return labels, lead


def pr_native(pr_dir):
    paths = [os.path.join(pr_dir, n) for n in ("PR.md", "head.diff")]
    for side in ("head", "base"):
        top = os.path.join(pr_dir, side)
        if os.path.isdir(top) and not os.path.islink(top):
            for d, dns, fns in os.walk(top, followlinks=False):
                dns.sort()
                paths += [os.path.join(d, n) for n in sorted(fns)]
    parts = []
    for p in paths:
        if os.path.isfile(p) and not os.path.islink(p):
            with open(p, "rb") as f:
                parts.append(f.read(NATIVE_CAP).decode("utf-8", "replace"))
    return "\n".join(parts)


def leaks(text, native, forbid):
    """the provenance-looking tokens of text that the PR content does not also carry"""
    toks = set()
    for pat in PATTERNS:
        toks.update(m.group(0) for m in pat.finditer(text))
    toks.update(t for t in forbid if t and t in text)
    return sorted(t for t in toks if t not in native)


def build(a):
    fixtures = [f.strip() for f in a.fixtures.split(",") if f.strip()]
    if not fixtures:
        raise Refuse("no fixtures")
    pr_root = a.pr_root or os.path.dirname(os.path.abspath(a.manifests_dir))
    out, missing, n_def, n_src, empty = {}, 0, 0, 0, 0
    for fx in sorted(set(fixtures)):
        if not FIXTURE.match(fx) or ".." in fx:
            raise Refuse("bad fixture id %r" % fx)
        man = load_json(os.path.join(a.manifests_dir, fx + ".json"), "manifest")
        defects = man.get("defects") if isinstance(man, dict) else None
        if not isinstance(defects, list):
            raise Refuse("manifest %s has no defects list" % fx)
        labels, lead = annotation(a.annotation_root, fx)
        native = None
        entries = {}
        for d in defects:
            did = str(d.get("id", ""))
            if not did or did in entries:
                raise Refuse("manifest %s: missing or duplicate defect id %r" % (fx, did))
            clauses, srcs, n = [], [], 0
            for kind, sid in parse_sources(d.get("source"), did):
                srcs.append("%s:%s" % (kind, sid))
                n_src += 1
                descs = []
                for ann in ANNOTATORS:
                    t = norm((record(labels[ann], kind, sid) or {}).get("description"))
                    if t and t not in descs:
                        descs.append(t)
                reason = next((norm(L[sid].get("reason")) for L in lead
                               if isinstance(L.get(sid), dict) and norm(L[sid].get("reason"))), "")
                if not descs:
                    missing += 1
                    clauses.append("%s: no annotator description" % sid)
                    continue
                n += len(descs)
                c = "%s %s — %s" % (LEAD[kind], sid, "; ".join(descs))
                clauses.append(c)   # the lead adjudication reason is bookkeeping (anchors, grouping) and can name the annotators: not shown to the judge (lead, addendum 14)
            meta = "; ".join("%s: %s" % (k, d[k]) for k in ("category", "severity") if d.get(k))
            text = " | ".join(clauses) + (" (%s)" % meta if meta else "")
            if n == 0:
                empty += 1
            native = pr_native(os.path.join(pr_root, fx)) if native is None else native
            bad = leaks(text, native, a.forbid)
            if bad:
                raise Refuse("%s %s: description would carry a provenance token (%s)" % (fx, did, ", ".join(bad)))
            entries[did] = {"text": text, "sources": srcs, "n_descriptions": n}
            n_def += 1
        out[fx] = entries
    sys.stderr.write("defect-descriptions: %d fixture(s), %d defect(s), %d source id(s); %d source id(s) without "
                     "an annotator description; %d defect(s) with annotator text, %d without\n"
                     % (len(out), n_def, n_src, missing, n_def - empty, empty))
    return {"schema_version": 1, "fixtures": out}


def main(argv=None):
    ap = argparse.ArgumentParser(prog="defect-descriptions.py")
    ap.add_argument("--manifests-dir", required=True)
    ap.add_argument("--annotation-root", required=True)
    ap.add_argument("--fixtures", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--pr-root")
    ap.add_argument("--forbid", action="append", default=[])
    try:
        a = ap.parse_args(sys.argv[1:] if argv is None else argv)
    except SystemExit as e:
        return 2 if e.code else 0
    try:
        doc = build(a)
    except Refuse as e:
        sys.stderr.write("defect-descriptions: %s\n" % e)
        return 1
    body = json.dumps(doc, sort_keys=True, indent=1, ensure_ascii=False) + "\n"
    d = os.path.dirname(os.path.abspath(a.out))
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".defect-descriptions.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(body)
        os.replace(tmp, a.out)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    return 0


if __name__ == "__main__":
    sys.exit(main())
