"""judge_packets.py — the blind judge's packet pieces, shared by judge-sample.sh and judge-pairs.sh.

One copy of the rules both scripts must apply identically (loa-smol judge-v2: a drift between the sampler's
packets and the pair judge's packets would make their verdicts incomparable):

  sources(run_dir)            the arm's own texts as paragraphs — sandbox/review.md, the a2a feedback files, the
                              adversarial envelopes' findings; a matched cell's sessions/s<i>/ copies of the same
  finding_text(paras, region) the first paragraph citing the region's file at its start or end line; over CUT
                              characters it is reduced to the bullet(s) that cite the region under the note
                              "(the citing bullet(s) of a N-line list; k of m chars shown)"; a long paragraph
                              without list structure is shown whole; nothing exceeds CAP characters (" …" when cut).
                              The cycle-132 rule p[:1500] + " …" hid the citing bullet in 616 of 1,283 pair packets
                              (loa-smol out/s1a/RESULTS.md Q1b); judge-v2 addendum 1 replaced it with this one.
  regions(path)               the `path:line[-line]` citations of a gates-combined.md (a union file's "## session"
                              lines are skipped), sorted and deduplicated, as (path, start, end)
  citations(path)             the same citations in file order, duplicates dropped (the grader's cites order)
  resolve_cited(…)            a cited path resolved the way the grader credits it (exact under head/, the labelled
                              defect file by suffix, the unique head/ file by suffix, the PR files)
  head_lines(p, a, b, ctx)    the numbered head lines a-ctx … b+ctx
  finding_section / cited_section / defect_section — the three packet sections (a pair item is the three in order)
  describe(d, descriptions, fixture_name) → (text, annotators|manifest|id_fallback)
  load_descriptions(path)     defect-descriptions.py's output as {fixture: {defect id: text}} (ValueError when malformed)
  provenance_scan(…)          refuses a packet that carries a field line or a forbidden token (ProvenanceError), with
                              the PR-native exemption: an arm id the task's PR itself carries reveals nothing; a
                              field line only when the whole line occurs verbatim there; strict tokens never
  pr_native(fixture_dir)      the task's PR-native text (PR.md, head.diff, head/ and base/ files; bounded)

Pure functions over the file system; no model, no network; python3 -I safe (stdlib only).
"""
import json
import os
import re

CTX = 5                     # head lines of context around a cited region
CUT, CAP = 1500, 6000       # a citing paragraph over CUT chars is reduced to its citing bullet(s); nothing exceeds CAP
BULLET = re.compile(r"\s*(?:[-*+]|\d+[.)]|#{1,6}\s|\[?[A-Z]{2,}-\d+)")   # a bullet, numbered item, heading or finding id
LINE = re.compile(r"^(?P<p>\S+?):(?P<a>\d{1,6})(?:-(?P<b>\d{1,6}))?$")
TRAILER = re.compile(r"<!--\s*LOA-VERDICT.*?-->", re.S)
FIELD = re.compile(r"^\s*(arm|trial|batch|run_id|stratum|grader[_ ]decision)\s*[:=]", re.I | re.M)
PLACEHOLDER = "(the finding's prose could not be located; the citation only)"
WALK_CAP = 200000           # files listed per head tree for the suffix lookup
NATIVE_CAP = 8 << 20        # bytes read per PR file
PR_FILES = {"pr/PR.md": "PR.md", "PR.md": "PR.md", "pr/head.diff": "head.diff"}
_head_files, _native = {}, {}


class ProvenanceError(Exception):
    """a packet would carry a provenance field or token (the argument)"""


def inside(base, rel):
    p = os.path.realpath(os.path.join(base, rel))
    return p if p == os.path.realpath(base) or p.startswith(os.path.realpath(base) + os.sep) else None


def strip_side(p):
    for pre in ("head/", "base/"):
        if p.startswith(pre):
            return p[len(pre):]
    return p


def path_matches(cited, defect_file):
    cited = strip_side(cited)
    if cited == defect_file or defect_file.endswith("/" + cited):
        return True
    return cited == defect_file.rsplit("/", 1)[-1]


def defect_sites(d):
    return [s for s in (d.get("anchors") or [d.get("anchor_line")]) if isinstance(s, int) and not isinstance(s, bool)]


def citations(path):
    """the `path:line[-line]` lines of a gates-combined.md in file order, duplicates dropped; None without the file"""
    if not os.path.isfile(path) or os.path.islink(path):
        return None
    out, seen = [], set()
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = LINE.match(line.strip())
            if m:
                a = int(m.group("a")); b = int(m.group("b") or a)
                c = (m.group("p"), min(a, b), max(a, b))
                if c not in seen:
                    seen.add(c)
                    out.append(c)
    return out


def regions(run_dir):
    c = citations(os.path.join(run_dir, "grading", "gates-combined.md"))
    return None if c is None else sorted(set(c))


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
    """the first paragraph citing the region's file at its start or end line. Over CUT characters the paragraph is
    reduced to the line block(s) that cite the region — each from its bullet, numbered-item, heading or finding-id
    line to the next such start — under a note naming the list's line count and the characters shown (loa-smol
    judge-v2 addendum 1: the cycle-132 rule p[:1500] + " …" hid the citing bullet in 616 of 1,283 pair packets). A
    long paragraph without that structure is shown whole. Never more than CAP characters (then cut with " …")."""
    path, a, b = region
    base = re.escape(strip_side(path).rsplit("/", 1)[-1])
    pat = re.compile(base + r"[`*)\]]{0,3}:(%d|%d)(?!\d)" % (a, b))
    for p in paras:
        if not pat.search(p):
            continue
        if len(p) <= CUT:
            return p
        lines = p.split("\n")
        starts = [i for i, ln in enumerate(lines) if BULLET.match(ln)] or [0]
        keep = set()
        for h in (i for i, ln in enumerate(lines) if pat.search(ln)):
            s = max([x for x in starts if x <= h], default=0)
            e = min([x for x in starts if x > h], default=len(lines))
            keep.update(range(s, e))
        out = p
        if len(keep) < len(lines):
            shown = "\n".join(lines[i] for i in sorted(keep))
            out = "(the citing bullet(s) of a %d-line list; %d of %d chars shown)\n%s" % (len(lines), len(shown), len(p), shown)
        return out if len(out) <= CAP else out[:CAP] + " …"
    return None


def head_files(fixture_dir):
    """relative paths of the regular files under head/ (bounded walk, symlinks skipped; cached)"""
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
    """(absolute path or None, display path, resolution) for a cited region path, in the grader's
    order: exact under head/; the unit's labelled defect file when it ends with "/" + cited (the
    grader's credit rule); the unique head/ file ending with "/" + cited; pr/PR.md, PR.md and
    pr/head.diff → the fixture's PR.md / head.diff. Zero or several suffix matches → unresolved."""
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


def head_lines(p, a, b, ctx=CTX):
    if not p:
        return None
    with open(p, encoding="utf-8", errors="replace") as f:
        lines = f.read().split("\n")
    lo, hi = max(1, a - ctx), min(len(lines), b + ctx)
    return "\n".join("%6d  %s" % (i, lines[i - 1]) for i in range(lo, hi + 1))


def fence(text):
    n = 3
    for m in re.finditer(r"`{3,}", text or ""):
        n = max(n, len(m.group(0)) + 1)
    return "`" * n


def load_descriptions(path):
    """{fixture: {defect id: text}} from defect-descriptions.py's output ({} without a path); ValueError when malformed"""
    if not path:
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
    except (OSError, ValueError) as e:
        raise ValueError("descriptions file unreadable: %s" % e)
    fx = doc.get("fixtures") if isinstance(doc, dict) and doc.get("schema_version") == 1 else None
    if not isinstance(fx, dict):
        raise ValueError("descriptions file is not schema_version 1 with a fixtures object: %s" % path)
    out = {}
    for name, ds in fx.items():
        if not isinstance(ds, dict):
            raise ValueError("descriptions file: fixture %s is not an object" % name)
        for did, e in ds.items():
            t = e.get("text") if isinstance(e, dict) else None
            if isinstance(t, str) and t.strip():
                out.setdefault(name, {})[did] = " ".join(t.split())
    return out


def describe(d, descriptions, fixture_name):
    """the packet's Description text for a defect → (text, source annotators|manifest|id_fallback)"""
    desc = descriptions.get(fixture_name, {}).get(str(d.get("id", "")))
    if desc:
        return desc, "annotators"
    if d.get("description"):
        return d["description"], "manifest"
    return re.sub(r"^[A-Za-z]?\d+-", "", str(d.get("id", ""))).replace("-", " "), "id_fallback"


def finding_section(txt):
    """'## Finding' with the fenced text (the placeholder when the prose was not located)"""
    txt = txt or PLACEHOLDER
    fz = fence(txt)
    return "## Finding\n\n%s text\n%s\n%s\n\n" % (fz, txt, fz)


def cited_section(fixture_dir, region, defect_file, ctx=CTX):
    """the '## Cited lines' header and the fenced head lines → (text, quoted head text or None, resolution)"""
    rp, shown, resolution = resolve_cited(fixture_dir, region[0], defect_file)
    hl = head_lines(rp, region[1], region[2], ctx)
    note = "" if resolution in ("exact", "unresolved") else "; cited as %s" % strip_side(region[0])
    out = "## Cited lines: %s:%d-%d (±%d%s)\n\n" % (shown, region[1], region[2], ctx, note)
    if hl is None:
        out += "(the file is not in the PR's head tree)\n\n"
    else:
        fz = fence(hl)
        out += "%s text\n%s\n%s\n\n" % (fz, hl, fz)
    return out, hl, resolution


def defect_section(d, desc):
    """'## Labelled defect' with the file, anchor lines, description and head line → (text, quoted must_match or None)"""
    sites = defect_sites(d)
    out = "## Labelled defect\n\nFile: `%s`; anchor lines: %s.\n\nDescription: %s\n" % (
        d.get("file"), ", ".join(str(s) for s in sites), desc)
    q = None
    if d.get("must_match") and not str(d["must_match"]).startswith("@L"):
        fz = fence(str(d["must_match"]))
        out += "\nHead line:\n\n%s text\n%s\n%s\n" % (fz, d["must_match"], fz)
        q = str(d["must_match"])
    return out, q


def pr_native(fixture_dir):
    """the task's PR-native text: PR.md, head.diff, every regular file under head/ and base/
    (bounded reads, symlinks skipped); an arm id quoted from it does not reveal the arm"""
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


def provenance_scan(body, quoted, fixture_dir, forbidden, strict):
    """the PR-native exemptions a packet needs (sorted), or ProvenanceError(token). `quoted` head-tree text (the PR's
    own code may name arms) is outside the scan; a field line is exempt only whole and verbatim in the PR-native
    text; a forbidden token is exempt when the PR-native text carries it, unless it is in `strict`"""
    scan = body
    for q in quoted:
        scan = scan.replace(q, "")
    native, exempt = None, []
    for m in FIELD.finditer(scan):
        end = scan.find("\n", m.start())
        whole = scan[m.start():end if end >= 0 else len(scan)].strip()
        native = pr_native(fixture_dir) if native is None else native
        if not whole or whole not in native:
            raise ProvenanceError(m.group(0).strip())
        exempt.append(whole)
    for tok in sorted(forbidden):
        if tok in scan:
            native = pr_native(fixture_dir) if native is None else native
            if tok in strict or tok not in native:
                raise ProvenanceError(tok)
            exempt.append(tok)
    return sorted(set(exempt))
