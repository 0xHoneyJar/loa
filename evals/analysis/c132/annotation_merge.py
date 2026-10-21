#!/usr/bin/env python3
"""annotation_merge.py — two blind annotators' label files → kappa, an adjudication list and v2 label rows
(cycle-132 FR-2; sdd.md §1.4 "Annotation packets and merge", §3.2 annotation files, §5.2; D-2.2, D-2.3).

Usage:
  annotation_merge.py --fixture pr-NN --a A.json --b B.json --head-dir DIR --out DIR
                      [--kappa] [--adjudication adj.json --hunks-meta hunks.meta.json]
                      [--manifest-c131 PATH] [--fix-rows LABELS.tsv] [--schema PATH]
  annotation_merge.py --pool <kappa.json>… --out DIR
  annotation_merge.py --validate SCHEMA FILE…

Options:
  --fixture pr-NN       the fixture the labels are for (recorded in every output)
  --a / --b FILE        annotator A's and annotator B's label files (schema: --schema)
  --head-dir DIR        the fixture's head/ tree: every anchor is validated against it
  --out DIR             output directory (created; existing outputs are overwritten)
  --kappa               the agreement phase only (the default when --adjudication is absent)
  --adjudication FILE   the lead's records, {<item id>: {verdict, group, file, anchor_lines,
                        description, severity, category, reason}}: one per disagreement (more are
                        allowed: an override of an agreed item); every key present, nulls allowed
                        only for a not-defect / not-at-head verdict; reason one line
  --hunks-meta FILE     packets/pr-NN/hunks.meta.json (outside the blind packet): review_driven per
                        hunk id, as {"H01": {"review_driven": true}}, {"hunks": {…}} or {"H01": true};
                        required with --adjudication
  --manifest-c131 PATH  the frozen review-derived key (manifests/c131/pr-NN.json), when the fixture
                        has one: result.md reports how many of its defects the v2 defects confirm
  --fix-rows FILE       a labels file whose `fix` rows (fix regions) are carried into labels.rows.tsv
  --schema PATH         the annotation schema (default evals/harness/schemas/annotation.schema.json)
  --pool FILE…          pool per-fixture kappa.json files: tables summed, kappa recomputed
  --validate SCHEMA F…  validate JSON files against SCHEMA with the subset validator below

Agreement (kappa.json, always written): Cohen's kappa on the hunk verdicts (2 × 2: rows A, columns B,
defect first), on the incident verdicts (defect-at-head first) and on severity among the items both
call a defect (4 × 4, critical … low); kappa is null when the chance agreement is 1 (one category).
localization: among the items both call a defect, the share whose files match and anchor sets
overlap, the median of the smallest anchor distance (same file only) and the file mismatches.
grouping: over hunks, the pairs A puts in one group, the pairs B does, and their Jaccard
(null when neither groups any pair).

Disagreements (adjudication.md): an item whose verdicts differ (verdict), or, for an agreed defect,
whose file, anchor set, group membership (the other items sharing its group, so group ids need not
match), severity or category differ; an anchor that is not a line of head/<file>; an incident both
call a defect that has no category and no hunk to inherit one from. Descriptions are free text and
never match: both are shown, and the merged record takes A's for an agreed item.

Merge (with --adjudication; writes labels.rows.tsv and result.md): an agreed item takes A's label,
an adjudicated item the lead's record; group ids live in A's namespace (adjudication records use A's
ids or new ones). Items of one group form one defect (split by file); a defect made only of hunks and
one made only of incidents whose anchors lie within ±3 lines in one file are one defect. Per defect:
anchors = the members' union, severity the highest, category and description the first member's
(hunks before incidents, by id), label_source fix-commit | incident | fix-commit+incident, agreement
adjudicated when any member was, adjudication the members' reasons ("; ") or "-", review_driven true
when any member hunk is review-driven (an incident never is), source "hunk:H01,H02;incident:I01".
Defects are ordered by (file, first anchor, first member) and named V01, V02, …. labels.rows.tsv is
a complete labels v2 file (`# approved-by: pending`, the v2 header, one row per anchor line;
must_match the head line's stripped text when that text is on exactly one line and is not
secret-shaped or `@L`-shaped, else `@L<n>`), which seed-corpus-from-record.sh --build-manifest reads.

Determinism: sorted keys, fixed number formats (4 decimals), no timestamps, no absolute paths.
Exit: 0 written (no disagreements, or merged); 1 refused (an input fails its schema or a check, an
unresolved or incomplete adjudication, an invalid anchor); 2 usage; 3 disagreements written to
adjudication.md (agreement phase). Tested by evals/analysis/c132/tests/test_annotation_merge.py.
"""
import argparse
import json
import os
import re
import sys

HEADER = ["defect_id", "severity", "category", "file", "must_match", "label_source", "source"]
HEADER_V2 = HEADER + ["annotators", "agreement", "adjudication", "review_driven"]
SEVERITIES = ["critical", "high", "medium", "low"]
VERDICTS = {"hunk": ("defect", "not-defect"), "incident": ("defect-at-head", "not-at-head")}
ADJ_FIELDS = ("verdict", "group", "file", "anchor_lines", "description", "severity", "category", "reason")
DEDUPE_LINES = 3
ANNOTATORS = ("A", "B")
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
DEFAULT_SCHEMA = os.path.join(REPO_ROOT, "evals", "harness", "schemas", "annotation.schema.json")
ID_RX = {"hunk": re.compile(r"^H[0-9]+$"), "incident": re.compile(r"^I[0-9]+$")}
GROUP_RX = re.compile(r"^D[0-9]+$")
FIXTURE_RX = re.compile(r"^pr-[0-9]{2,}$")
CTRL_RX = re.compile(r"[\x00-\x1f\x7f-\x9f  ]")
AT_SHAPE_RX = re.compile(r"^@L[0-9A-Za-z-]*$")   # the seeder's `@L` grammar shape: never written as text
# the seeder's secret shapes (seed-corpus-from-record.sh SECRET_RX): such a head line becomes @L<n>
SECRET_RX = [re.compile(p) for p in (
    r"AKIA[0-9A-Z]{16}", r"sk-[a-zA-Z0-9]{20,}", r"ghp_[a-zA-Z0-9]{36}", r"gho_[a-zA-Z0-9]{36}",
    r"github_pat_[A-Za-z0-9_]{20,}", r"gh[su]_[a-zA-Z0-9]{36}",
    r"glpat-[a-zA-Z0-9\-]{20,}", r"xox[bpors]-[a-zA-Z0-9\-]+", r"sk-ant-[a-zA-Z0-9\-]{20,}",
    r"AIza[0-9A-Za-z\-_]{35}", r"(?:sk|rk)_(?:live|test)_[0-9a-zA-Z]{20,}",
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----[^-]*-----END [A-Z ]*PRIVATE KEY-----",
    r"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}",
    r"password[ \t]*[:=][ \t]*[\"'][^\"'\n]{8,}", r"secret[ \t]*[:=][ \t]*[\"'][^\"'\n]{8,}",
    r"(?:api[_-]?key|access[_-]?token|auth[_-]?token)[ \t]*[:=][ \t]*[\"'][^\"'\n]{16,}")]


class SchemaError(Exception):
    """the schema uses a keyword the subset validator does not implement"""


class Refused(Exception):
    """exit 1"""


# ------------------------------------------------------------------ JSON Schema subset validator
ANNOTATION_KEYWORDS = {"$schema", "$id", "title", "description", "$comment", "examples", "default", "format",
                       "$defs", "definitions", "readOnly", "writeOnly", "deprecated"}
VALIDATION_KEYWORDS = {"type", "properties", "required", "additionalProperties", "patternProperties", "enum",
                       "const", "items", "minItems", "maxItems", "uniqueItems", "minimum", "maximum", "minLength",
                       "maxLength", "pattern", "oneOf", "anyOf", "allOf", "not", "$ref"}


def _type_ok(t, x):
    return {"object": isinstance(x, dict), "array": isinstance(x, list), "string": isinstance(x, str),
            "boolean": isinstance(x, bool), "null": x is None,
            "integer": isinstance(x, int) and not isinstance(x, bool),
            "number": isinstance(x, (int, float)) and not isinstance(x, bool)}.get(t, None)


def validate(schema, inst, root=None, path=""):
    """errors (list of "<path>: <why>") of inst against schema; raises SchemaError on an unsupported keyword"""
    root = schema if root is None else root
    if schema is True or schema == {}:
        return []
    if schema is False:
        return [f"{path or '(root)'}: no value is allowed here"]
    if not isinstance(schema, dict):
        raise SchemaError(f"schema at {path or '(root)'} is not an object")
    bad = set(schema) - ANNOTATION_KEYWORDS - VALIDATION_KEYWORDS
    if bad:
        raise SchemaError(f"unsupported schema keyword(s) {sorted(bad)} at {path or '(root)'}")
    where = path or "(root)"
    errs = []
    if "$ref" in schema:
        ref = schema["$ref"]
        m = re.match(r"^#/(\$defs|definitions)/([A-Za-z0-9_.-]+)$", ref) if isinstance(ref, str) else None
        if not m or m.group(2) not in (root.get(m.group(1)) or {}):
            raise SchemaError(f"unsupported or unresolved $ref {ref!r} at {where}")
        errs += validate(root[m.group(1)][m.group(2)], inst, root, path)
    if "type" in schema:
        ts = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        oks = [_type_ok(t, inst) for t in ts]
        if None in oks:
            raise SchemaError(f"unknown type in {ts} at {where}")
        if not any(oks):
            return errs + [f"{where}: {json.dumps(inst)[:60]} is not of type {'|'.join(ts)}"]
    if "enum" in schema and not any(inst == e and type(inst) is type(e) for e in schema["enum"]):
        errs.append(f"{where}: {json.dumps(inst)[:60]} is not one of {json.dumps(schema['enum'])}")
    if "const" in schema and not (inst == schema["const"] and type(inst) is type(schema["const"])):
        errs.append(f"{where}: {json.dumps(inst)[:60]} is not {json.dumps(schema['const'])}")
    if isinstance(inst, str):
        if "minLength" in schema and len(inst) < schema["minLength"]:
            errs.append(f"{where}: shorter than {schema['minLength']}")
        if "maxLength" in schema and len(inst) > schema["maxLength"]:
            errs.append(f"{where}: longer than {schema['maxLength']}")
        if "pattern" in schema and not re.search(schema["pattern"], inst):
            errs.append(f"{where}: {inst[:60]!r} does not match {schema['pattern']}")
    if _type_ok("number", inst):
        if "minimum" in schema and inst < schema["minimum"]:
            errs.append(f"{where}: {inst} < {schema['minimum']}")
        if "maximum" in schema and inst > schema["maximum"]:
            errs.append(f"{where}: {inst} > {schema['maximum']}")
    if isinstance(inst, list):
        if "minItems" in schema and len(inst) < schema["minItems"]:
            errs.append(f"{where}: fewer than {schema['minItems']} items")
        if "maxItems" in schema and len(inst) > schema["maxItems"]:
            errs.append(f"{where}: more than {schema['maxItems']} items")
        if schema.get("uniqueItems") and len({json.dumps(x, sort_keys=True) for x in inst}) != len(inst):
            errs.append(f"{where}: items are not unique")
        if "items" in schema:
            for i, x in enumerate(inst):
                errs += validate(schema["items"], x, root, f"{path}[{i}]")
    if isinstance(inst, dict):
        for k in schema.get("required", []):
            if k not in inst:
                errs.append(f"{where}: {k!r} is required")
        props, pats = schema.get("properties", {}), schema.get("patternProperties", {})
        for k in sorted(inst):
            sub = f"{path}.{k}" if path else k
            matched = False
            if k in props:
                matched = True
                errs += validate(props[k], inst[k], root, sub)
            for p, s in pats.items():
                if re.search(p, k):
                    matched = True
                    errs += validate(s, inst[k], root, sub)
            if not matched and "additionalProperties" in schema:
                ap = schema["additionalProperties"]
                if ap is False:
                    errs.append(f"{sub}: additional property is not allowed")
                elif isinstance(ap, dict):
                    errs += validate(ap, inst[k], root, sub)
    for s in schema.get("allOf", []):
        errs += validate(s, inst, root, path)
    if "anyOf" in schema and not any(not validate(s, inst, root, path) for s in schema["anyOf"]):
        errs.append(f"{where}: matches none of anyOf")
    if "oneOf" in schema:
        n = sum(1 for s in schema["oneOf"] if not validate(s, inst, root, path))
        if n != 1:
            errs.append(f"{where}: matches {n} of oneOf (exactly one required)")
    if "not" in schema and not validate(schema["not"], inst, root, path):
        errs.append(f"{where}: matches the `not` schema")
    return errs


# ------------------------------------------------------------------ statistics
def cohen_kappa(table):
    """(kappa, observed agreement) of a square table (rows rater A, columns rater B); kappa None when the
    chance agreement is 1 (a single category), both None on an empty table"""
    k = len(table)
    n = sum(sum(r) for r in table)
    if n == 0:
        return None, None
    po = sum(table[i][i] for i in range(k)) / n
    pe = sum((sum(table[i]) / n) * (sum(table[j][i] for j in range(k)) / n) for i in range(k))
    if abs(1 - pe) < 1e-12:
        return None, po
    return (po - pe) / (1 - pe), po


def r4(x):
    return None if x is None else round(x, 4)


def kappa_block(table, labels=None):
    k, po = cohen_kappa(table)
    out = {"table": table, "kappa": r4(k), "po": r4(po), "n": sum(sum(r) for r in table)}
    if labels:
        out["labels"] = labels
    return out


def median(xs):
    if not xs:
        return None
    s = sorted(xs)
    m = len(s) // 2
    return s[m] if len(s) % 2 else (s[m - 1] + s[m]) / 2


# ------------------------------------------------------------------ inputs
def load_json(path, what):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except OSError as e:
        raise Refused(f"{what}: cannot read {os.path.basename(path)} ({e.strerror})")
    except ValueError as e:
        raise Refused(f"{what}: {os.path.basename(path)} is not JSON ({e})")


def item_order(ids):
    return sorted(ids, key=lambda i: (i[0] != "H", int(i[1:]), i))


def kind_of(item):
    return "hunk" if item.startswith("H") else "incident"


def is_defect(rec, kind):
    return rec.get("verdict") == VERDICTS[kind][0]


def one_line(s):
    return isinstance(s, str) and s.strip() != "" and not CTRL_RX.search(s)


def check_record(rec, kind, who, with_reason=False):
    """shape problems of one label (annotator or adjudication record), as messages"""
    out = []
    if not isinstance(rec, dict):
        return [f"{who}: not an object"]
    v = rec.get("verdict")
    if v not in VERDICTS[kind]:
        out.append(f"{who}: verdict {v!r} is not {'|'.join(VERDICTS[kind])}")
    g = rec.get("group")
    if g is not None and not (isinstance(g, str) and GROUP_RX.match(g)):
        out.append(f"{who}: group {g!r} is not D<k> or null")
    if with_reason and not one_line(rec.get("reason")):
        out.append(f"{who}: reason must be one non-empty line")
    if v == VERDICTS[kind][0]:
        f = rec.get("file")
        if not (isinstance(f, str) and f):
            out.append(f"{who}: a defect names its file")
        al = rec.get("anchor_lines")
        if not (isinstance(al, list) and al and all(isinstance(x, int) and not isinstance(x, bool) for x in al)):
            out.append(f"{who}: a defect has anchor_lines, a non-empty list of integers")
        if rec.get("severity") not in SEVERITIES:
            out.append(f"{who}: severity {rec.get('severity')!r} is not {'|'.join(SEVERITIES)}")
        c = rec.get("category")
        if (kind == "hunk" or with_reason) and not (isinstance(c, str) and c and not CTRL_RX.search(c)):
            out.append(f"{who}: a defect has a one-line category")
        elif c is not None and not (isinstance(c, str) and c and not CTRL_RX.search(c)):
            out.append(f"{who}: category must be one line")
        d = rec.get("description")
        if d is not None and not isinstance(d, str):
            out.append(f"{who}: description must be a string")
    return out


def load_labels(path, schema, who):
    lab = load_json(path, who)
    errs = [f"{who}: {e}" for e in validate(schema, lab)]
    if not errs:
        if not isinstance(lab, dict) or not isinstance(lab.get("hunks"), dict) or not isinstance(lab.get("incidents"), dict):
            errs.append(f"{who}: hunks and incidents must be objects")
        else:
            for kind, key in (("hunk", "hunks"), ("incident", "incidents")):
                for i, rec in lab[key].items():
                    if not ID_RX[kind].match(i):
                        errs.append(f"{who}: {key}.{i}: id is not {ID_RX[kind].pattern}")
                    errs += check_record(rec, kind, f"{who}: {key}.{i}")
    if errs:
        raise Refused("; ".join(errs[:12]))
    return {**lab["hunks"], **lab["incidents"]}


def load_meta(path):
    raw = load_json(path, "hunks meta")
    if isinstance(raw, dict) and isinstance(raw.get("hunks"), dict):
        raw = raw["hunks"]
    if not isinstance(raw, dict):
        raise Refused("hunks meta: not an object of hunk ids")
    out = {}
    for k, v in raw.items():
        rd = v.get("review_driven") if isinstance(v, dict) else v
        if not isinstance(rd, bool):
            raise Refused(f"hunks meta: {k}: review_driven must be true or false")
        out[k] = rd
    return out


class Head:
    """head/<file> lines, with the seeder's path rule (no absolute path, `..`, backslash or NUL; stays inside)"""
    def __init__(self, root):
        self.root = os.path.realpath(root)
        self.cache = {}

    def lines(self, f):
        if f in self.cache:
            return self.cache[f]
        if not isinstance(f, str) or not f or os.path.isabs(f) or "\\" in f or "\x00" in f or ".." in f.split("/"):
            raise ValueError(f"file {f!r} is not a path inside head/ (absolute, `..`, backslash or NUL)")
        p = os.path.join(self.root, f)
        if not os.path.realpath(p).startswith(self.root + os.sep):
            raise ValueError(f"file {f!r} is not a path inside head/ (it resolves outside)")
        if not os.path.isfile(p):
            raise ValueError(f"head/{f} missing")
        with open(p, encoding="utf-8", errors="replace") as fh:
            self.cache[f] = fh.read().splitlines()
        return self.cache[f]

    def anchor_errors(self, rec):
        try:
            lines = self.lines(rec.get("file"))
        except ValueError as e:
            return [str(e)]
        out = []
        for n in rec.get("anchor_lines") or []:
            if not isinstance(n, int) or isinstance(n, bool) or n < 1:
                out.append(f"anchor {n!r} is not a positive integer")
            elif n > len(lines):
                out.append(f"anchor {n} is past the end of head/{rec['file']} ({len(lines)} lines)")
        return out


# ------------------------------------------------------------------ agreement
def co_members(labels, ids):
    groups = {}
    for i in ids:
        g = labels[i].get("group")
        if g is not None:
            groups.setdefault(g, set()).add(i)
    return {i: (groups[labels[i]["group"]] - {i}) if labels[i].get("group") is not None else set() for i in ids}


def compare(items, a, b, head):
    """{item: [fields]} of the disagreements, and {item: [notes]} (invalid anchors)"""
    coa, cob = co_members(a, items), co_members(b, items)
    out, notes = {}, {}
    for i in items:
        k = kind_of(i)
        x, y = a[i], b[i]
        fields = []
        if x["verdict"] != y["verdict"]:
            fields = ["verdict"]
        elif is_defect(x, k):
            if x["file"] != y["file"]:
                fields.append("file")
            bad = [f"A: {e}" for e in head.anchor_errors(x)] + [f"B: {e}" for e in head.anchor_errors(y)]
            if bad:
                notes[i] = bad
            if set(x["anchor_lines"]) != set(y["anchor_lines"]) or bad:
                fields.append("anchors")
            if coa[i] != cob[i]:
                fields.append("group")
            if x["severity"] != y["severity"]:
                fields.append("severity")
            cx, cy = x.get("category"), y.get("category")
            if cx is not None and cy is not None and cx != cy:
                fields.append("category")
        elif coa[i] != cob[i]:
            fields.append("group")
        if fields:
            out[i] = fields
    return out, notes, coa, cob


def agreement(items, a, b):
    t = {"hunk": [[0, 0], [0, 0]], "incident": [[0, 0], [0, 0]]}
    sev = [[0] * 4 for _ in SEVERITIES]
    loc_n = loc_overlap = mism = 0
    dists = []
    for i in items:
        k = kind_of(i)
        da, db = is_defect(a[i], k), is_defect(b[i], k)
        t[k][0 if da else 1][0 if db else 1] += 1
        if da and db:
            sev[SEVERITIES.index(a[i]["severity"])][SEVERITIES.index(b[i]["severity"])] += 1
            loc_n += 1
            if a[i]["file"] != b[i]["file"]:
                mism += 1
                continue
            sa, sb = set(a[i]["anchor_lines"]), set(b[i]["anchor_lines"])
            loc_overlap += bool(sa & sb)
            dists.append(min(abs(p - q) for p in sa for q in sb))
    hunks = [i for i in items if kind_of(i) == "hunk"]
    pa = pb = both = 0
    for x in range(len(hunks)):
        for y in range(x + 1, len(hunks)):
            ga = a[hunks[x]].get("group") is not None and a[hunks[x]].get("group") == a[hunks[y]].get("group")
            gb = b[hunks[x]].get("group") is not None and b[hunks[x]].get("group") == b[hunks[y]].get("group")
            pa, pb, both = pa + ga, pb + gb, both + (ga and gb)
    union = pa + pb - both
    md = median(dists)
    return {"hunks": kappa_block(t["hunk"]), "incidents": kappa_block(t["incident"]),
            "severity": kappa_block(sev, SEVERITIES),
            "localization": {"n": loc_n, "overlap": loc_overlap, "share": r4(loc_overlap / loc_n) if loc_n else None,
                             "median_distance": md if md is None or md != int(md) else int(md),
                             "file_mismatch": mism},
            "grouping": {"pairs_a": pa, "pairs_b": pb, "pairs_both": both,
                         "jaccard": r4(both / union) if union else None}}


# ------------------------------------------------------------------ merge
class UF:
    def __init__(self, xs):
        self.p = {x: x for x in xs}

    def find(self, x):
        while self.p[x] != x:
            self.p[x] = self.p[self.p[x]]
            x = self.p[x]
        return x

    def union(self, x, y):
        rx, ry = self.find(x), self.find(y)
        if rx != ry:
            a, b = sorted((rx, ry), key=lambda i: (i[0] != "H", int(i[1:])))
            self.p[b] = a


def merge(final, items, meta, require_category=True):
    """defects (ordered, named V01…) from the final per-item labels; raises Refused on a defect without a category"""
    dids = [i for i in items if is_defect(final[i]["rec"], kind_of(i))]
    uf = UF(dids)
    by_group = {}   # one group across files is split by file (a labels defect names one file)
    for i in dids:
        g = final[i]["rec"].get("group")
        if g is not None:
            by_group.setdefault((g, final[i]["rec"]["file"]), []).append(i)
    for members in by_group.values():
        for m in members[1:]:
            uf.union(members[0], m)

    def comps():
        c = {}
        for i in dids:
            c.setdefault(uf.find(i), []).append(i)
        return [item_order(v) for v in c.values()]

    # cross-source dedupe: a hunk defect and an incident on the same head lines ±3 in one file are one defect
    changed = True
    while changed:
        changed = False
        cs = sorted(comps(), key=lambda c: (c[0][0] != "H", int(c[0][1:])))
        for x in cs:
            for y in cs:
                if x is y or uf.find(x[0]) == uf.find(y[0]):
                    continue
                fx, fy = final[x[0]]["rec"]["file"], final[y[0]]["rec"]["file"]
                if fx != fy:
                    continue
                hx = [n for i in x if kind_of(i) == "hunk" for n in final[i]["rec"]["anchor_lines"]]
                iy = [n for i in y if kind_of(i) == "incident" for n in final[i]["rec"]["anchor_lines"]]
                if any(abs(p - q) <= DEDUPE_LINES for p in hx for q in iy):
                    uf.union(x[0], y[0])
                    changed = True
    out = []
    for c in comps():
        recs = [final[i]["rec"] for i in c]
        kinds = {kind_of(i) for i in c}
        cat = next((r.get("category") for r in recs if r.get("category")), None)
        if cat is None and require_category:
            raise Refused(f"the defect of {','.join(c)} has no category: adjudicate one of its items with a category")
        hunks = [i for i in c if kind_of(i) == "hunk"]
        incs = [i for i in c if kind_of(i) == "incident"]
        reasons = []
        for i in c:
            if final[i]["adjudicated"] and final[i]["reason"] not in reasons:
                reasons.append(final[i]["reason"])
        out.append({
            "members": c, "file": recs[0]["file"],
            "anchors": sorted({n for r in recs for n in r["anchor_lines"]}),
            "severity": min((r["severity"] for r in recs), key=SEVERITIES.index),
            "category": cat, "description": next((r.get("description") for r in recs if r.get("description")), ""),
            "label_source": "fix-commit+incident" if kinds == {"hunk", "incident"} else
                            ("fix-commit" if kinds == {"hunk"} else "incident"),
            "agreement": "adjudicated" if any(final[i]["adjudicated"] for i in c) else "agreed",
            "adjudication": "; ".join(reasons) if reasons else "-",
            "review_driven": any((meta or {}).get(h, False) for h in hunks),
            "source": ";".join(p for p in ((("hunk:" + ",".join(hunks)) if hunks else ""),
                                           (("incident:" + ",".join(incs)) if incs else "")) if p)})
    out.sort(key=lambda d: (d["file"], d["anchors"][0], d["members"][0][0] != "H", int(d["members"][0][1:])))
    for n, d in enumerate(out, 1):
        d["id"] = f"V{n:02d}"
    return out


def must_match(lines, n):
    t = lines[n - 1].strip()
    textual = (t and "\t" not in t and not CTRL_RX.search(t) and not AT_SHAPE_RX.match(t)
               and not any(r.search(t) for r in SECRET_RX)
               and [i for i, l in enumerate(lines, 1) if t in l] == [n])
    return t if textual else f"@L{n}"


def rows_for(defects, head):
    rows = []
    for d in defects:
        lines = head.lines(d["file"])
        for n in d["anchors"]:
            cells = [d["id"], d["severity"], d["category"], d["file"], must_match(lines, n), d["label_source"],
                     d["source"], ",".join(ANNOTATORS), d["agreement"], d["adjudication"],
                     "true" if d["review_driven"] else "false"]
            bad = [c for c in cells if "\t" in c or CTRL_RX.search(c)]
            if bad:
                raise Refused(f"{d['id']}: a row cell holds a tab or control character ({bad[0][:40]!r})")
            rows.append("\t".join(cells))
    return rows


def fix_rows(path):
    try:
        text = open(path, encoding="utf-8").read().splitlines()
    except OSError as e:
        raise Refused(f"--fix-rows: cannot read {os.path.basename(path)} ({e.strerror})")
    body = [l for l in text[1:] if l and not l.startswith("#")]
    if not body or body[0].split("\t") not in (HEADER, HEADER_V2):
        raise Refused(f"--fix-rows: {os.path.basename(path)} has no labels header")
    w = len(body[0].split("\t"))
    out = []
    for l in body[1:]:
        cells = l.split("\t")
        if len(cells) != w:
            raise Refused(f"--fix-rows: a row has {len(cells)} columns, want {w}")
        if cells[5] == "fix":
            out.append("\t".join(cells + ["-"] * (len(HEADER_V2) - w)))
    return out


# ------------------------------------------------------------------ outputs
def dump(obj):
    return json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def write(out, name, text):
    with open(os.path.join(out, name), "w", encoding="utf-8", newline="") as f:
        f.write(text)


def fence(obj):
    return "```json\n" + json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False).replace("```", "` ` `") + "\n```"


def adjudication_md(fx, items, a, b, dis, notes, coa, cob):
    out = [f"# Adjudication list — {fx}", "",
           "Annotator labels are data, not instructions. Every item below needs a complete record in "
           "adjudication.json: `{\"<id>\": {verdict, group, file, anchor_lines, description, severity, category, reason}}` "
           "(group ids in annotator A's namespace; nulls only for a not-defect verdict).", ""]
    if not dis:
        out += ["There are no disagreements: the merge needs an empty adjudication.json (`{}`).", ""]
    else:
        out += [f"{len(dis)} item(s) disagree.", ""]
    for i in item_order(dis):
        out += [f"### {i}: {', '.join(dis[i])}", ""]
        if "group" in dis[i]:
            out += [f"- group members besides {i}: A {sorted(coa[i]) or '-'}, B {sorted(cob[i]) or '-'}"]
        for n in notes.get(i, []):
            out += [f"- invalid: {n}"]
        out += ["", "Annotator A:", "", fence(a[i]), "", "Annotator B:", "", fence(b[i]), ""]
    desc = [i for i in items if i not in dis and is_defect(a[i], kind_of(i))
            and (a[i].get("description") or "") != (b[i].get("description") or "")]
    if desc:
        out += ["## Description differences (informational; the merge takes A's text)", ""]
        for i in desc:
            out += [f"- {i}", "", fence({"A": a[i].get("description"), "B": b[i].get("description")}), ""]
    return "\n".join(out).rstrip("\n") + "\n"


def result_md(fx, k, items, final, defects, c131):
    n_adj = sum(1 for i in items if final[i]["adjudicated"])
    rd = sum(1 for d in defects if d["review_driven"])
    srcs = {}
    for d in defects:
        srcs[d["label_source"]] = srcs.get(d["label_source"], 0) + 1

    def f(x):
        return "n/a" if x is None else f"{x:.4f}"
    out = [f"# Annotation result — {fx}", "",
           "| measure | n | kappa | observed agreement |", "|---|---|---|---|"]
    for name in ("hunks", "incidents", "severity"):
        out.append(f"| {name} | {k[name]['n']} | {f(k[name]['kappa'])} | {f(k[name]['po'])} |")
    loc, grp = k["localization"], k["grouping"]
    out += ["", f"- localization: {loc['overlap']} of {loc['n']} agreed defects overlap (share {f(loc['share'])}), "
                f"median anchor distance {loc['median_distance'] if loc['median_distance'] is not None else 'n/a'}, "
                f"{loc['file_mismatch']} file mismatch(es)",
            f"- grouping: Jaccard {f(grp['jaccard'])} (A {grp['pairs_a']} pair(s), B {grp['pairs_b']}, both {grp['pairs_both']})",
            f"- items: {len(items)}; disagreements: {k['disagreements']}; adjudicated: {n_adj}; "
            f"adjudication share {f(n_adj / len(items) if items else None)}",
            f"- defects: {len(defects)} (" + ", ".join(f"{s} {srcs[s]}" for s in sorted(srcs)) + f"); "
            f"review-driven share {f(rd / len(defects) if defects else None)}"]
    if c131 is not None:
        conf = 0
        for cd in c131:
            anchors = cd.get("anchors") or [cd.get("anchor_line")]
            if any(d["file"] == cd.get("file") and any(isinstance(x, int) and abs(x - y) <= DEDUPE_LINES
                                                       for x in anchors for y in d["anchors"]) for d in defects):
                conf += 1
        out.append(f"- review-derived key (c131): {conf} of {len(c131)} defect(s) lie within ±{DEDUPE_LINES} lines of a v2 defect")
    out += ["", "| defect | file | anchors | severity | label_source | agreement | review_driven | members |",
            "|---|---|---|---|---|---|---|---|"]
    for d in defects:
        out.append(f"| {d['id']} | {d['file']} | {','.join(map(str, d['anchors']))} | {d['severity']} | "
                   f"{d['label_source']} | {d['agreement']} | {str(d['review_driven']).lower()} | {','.join(d['members'])} |")
    return "\n".join(out) + "\n"


# ------------------------------------------------------------------ modes
def run_merge(args):
    if not FIXTURE_RX.match(args.fixture or ""):
        raise UsageError("--fixture must be pr-NN")
    for v in ("a", "b", "head_dir", "out"):
        if not getattr(args, v):
            raise UsageError(f"missing --{v.replace('_', '-')}")
    if args.adjudication and not args.hunks_meta:
        raise UsageError("--adjudication needs --hunks-meta")
    if not os.path.isdir(args.head_dir):
        raise UsageError(f"--head-dir is not a directory: {args.head_dir}")
    schema = load_json(args.schema, "schema")
    a = load_labels(args.a, schema, "A")
    b = load_labels(args.b, schema, "B")
    if set(a) != set(b):
        only = sorted(set(a) ^ set(b))
        raise Refused(f"A and B label different items: {', '.join(only[:20])}")
    items = item_order(a)
    meta = load_meta(args.hunks_meta) if args.hunks_meta else None
    if meta is not None:
        miss = [i for i in items if kind_of(i) == "hunk" and i not in meta]
        if miss:
            raise Refused(f"hunks meta has no review_driven for {', '.join(miss)}")
    head = Head(args.head_dir)
    dis, notes, coa, cob = compare(items, a, b, head)
    # an incident-only defect with no category (neither annotator gave one) needs the lead's record; the
    # structure is estimated from A's labels on every item (the final merge refuses if one is still missing)
    prov = {i: {"rec": a[i] if a[i].get("category") is not None or kind_of(i) == "hunk"
                else {**a[i], "category": b[i].get("category")}, "adjudicated": False, "reason": None}
            for i in items}
    for d in merge(prov, items, {}, require_category=False):
        if d["category"] is None and all(kind_of(i) == "incident" and is_defect(b[i], "incident") for i in d["members"]):
            for i in d["members"]:
                dis.setdefault(i, []).append("category")
                notes.setdefault(i, []).append("an incident-only defect without a category")
    k = {"fixture": args.fixture, "annotators": list(ANNOTATORS), **agreement(items, a, b),
         "disagreements": len(dis), "disagreement_ids": item_order(dis)}
    os.makedirs(args.out, exist_ok=True)
    write(args.out, "kappa.json", dump(k))
    write(args.out, "adjudication.md", adjudication_md(args.fixture, items, a, b, dis, notes, coa, cob))
    if not args.adjudication:
        print(f"{args.fixture}: {len(items)} item(s), {len(dis)} disagreement(s); kappa hunks {k['hunks']['kappa']}")
        return 3 if dis else 0
    adj = load_json(args.adjudication, "adjudication")
    if not isinstance(adj, dict):
        raise Refused("adjudication: not an object of item ids")
    errs = [f"adjudication names an unknown item {i}" for i in sorted(adj) if i not in a]
    errs += [f"{i}: disagreement ({', '.join(dis[i])}) has no adjudication record" for i in item_order(dis) if i not in adj]
    for i in item_order([x for x in adj if x in a]):
        r = adj[i]
        if not isinstance(r, dict):
            errs.append(f"{i}: adjudication record is not an object")
            continue
        miss = [f for f in ADJ_FIELDS if f not in r]
        extra = sorted(set(r) - set(ADJ_FIELDS))
        if miss:
            errs.append(f"{i}: adjudication record lacks {', '.join(miss)}")
        if extra:
            errs.append(f"{i}: adjudication record has unknown field(s) {', '.join(extra)}")
        if miss or extra:
            continue
        errs += check_record(r, kind_of(i), i, with_reason=True)
        if is_defect(r, kind_of(i)):
            errs += [f"{i}: {e}" for e in head.anchor_errors(r)]
    for i in items:   # an agreed defect's anchors are validated too (the kappa phase listed invalid ones)
        if i not in adj and is_defect(a[i], kind_of(i)):
            errs += [f"{i}: {e}" for e in head.anchor_errors(a[i])]
    if errs:
        raise Refused("; ".join(errs[:20]))
    final = {}
    for i in items:
        if i in adj:
            final[i] = {"rec": adj[i], "adjudicated": True, "reason": adj[i]["reason"].strip()}
        else:
            rec = a[i] if a[i].get("category") is not None or kind_of(i) == "hunk" else {**a[i], "category": b[i].get("category")}
            final[i] = {"rec": rec, "adjudicated": False, "reason": None}
    defects = merge(final, items, meta)
    rows = rows_for(defects, head)
    if args.fix_rows:
        rows += fix_rows(args.fix_rows)
    c131 = None
    if args.manifest_c131:
        m = load_json(args.manifest_c131, "--manifest-c131")
        c131 = m.get("defects") if isinstance(m, dict) and isinstance(m.get("defects"), list) else None
        if c131 is None:
            raise Refused("--manifest-c131: no defects list")
    write(args.out, "labels.rows.tsv", "\n".join(["# approved-by: pending", "\t".join(HEADER_V2)] + rows) + "\n")
    write(args.out, "result.md", result_md(args.fixture, k, items, final, defects, c131))
    print(f"{args.fixture}: {len(defects)} defect(s), {len(rows)} row(s); adjudicated {sum(f['adjudicated'] for f in final.values())}")
    return 0


def run_pool(paths, out):
    tabs = {"hunks": None, "incidents": None, "severity": None}
    loc = {"n": 0, "overlap": 0, "file_mismatch": 0}
    grp = {"pairs_a": 0, "pairs_b": 0, "pairs_both": 0}
    fixtures = []
    for p in paths:
        k = load_json(p, "--pool")
        try:
            fixtures.append(k["fixture"])
            for name in tabs:
                t = k[name]["table"]
                tabs[name] = t if tabs[name] is None else [[x + y for x, y in zip(r, s)] for r, s in zip(tabs[name], t)]
            for f in loc:
                loc[f] += k["localization"][f]
            for f in grp:
                grp[f] += k["grouping"][f]
        except (KeyError, TypeError) as e:
            raise Refused(f"--pool: {os.path.basename(p)} is not a kappa.json ({e})")
    union = grp["pairs_a"] + grp["pairs_b"] - grp["pairs_both"]
    res = {"fixtures": fixtures, "hunks": kappa_block(tabs["hunks"]), "incidents": kappa_block(tabs["incidents"]),
           "severity": kappa_block(tabs["severity"], SEVERITIES),
           "localization": {**loc, "share": r4(loc["overlap"] / loc["n"]) if loc["n"] else None,
                            "median_distance": None},
           "grouping": {**grp, "jaccard": r4(grp["pairs_both"] / union) if union else None}}
    os.makedirs(out, exist_ok=True)
    write(out, "kappa.json", dump(res))
    print(f"pooled {len(fixtures)} fixture(s): kappa hunks {res['hunks']['kappa']}")
    return 0


class UsageError(Exception):
    pass


def main(argv):
    ap = argparse.ArgumentParser(prog="annotation_merge.py", add_help=True)
    ap.add_argument("--fixture"); ap.add_argument("--a"); ap.add_argument("--b")
    ap.add_argument("--adjudication"); ap.add_argument("--kappa", action="store_true")
    ap.add_argument("--head-dir"); ap.add_argument("--hunks-meta"); ap.add_argument("--manifest-c131")
    ap.add_argument("--fix-rows"); ap.add_argument("--schema", default=DEFAULT_SCHEMA); ap.add_argument("--out")
    ap.add_argument("--pool", nargs="+"); ap.add_argument("--validate", nargs="+", metavar="SCHEMA FILE")
    try:
        args = ap.parse_args(argv)
    except SystemExit as e:
        return 2 if e.code else 0
    try:
        if args.validate:
            if len(args.validate) < 2:
                raise UsageError("--validate needs SCHEMA and at least one FILE")
            schema = load_json(args.validate[0], "schema")
            bad = 0
            for p in args.validate[1:]:
                errs = validate(schema, load_json(p, os.path.basename(p)))
                for e in errs[:20]:
                    print(f"{os.path.basename(p)}: {e}", file=sys.stderr)
                bad += bool(errs)
            print(f"validated {len(args.validate) - 1} file(s): {bad} invalid")
            return 1 if bad else 0
        if args.pool:
            if not args.out:
                raise UsageError("--pool needs --out")
            return run_pool(args.pool, args.out)
        if args.kappa and args.adjudication:
            raise UsageError("--kappa and --adjudication exclude each other")
        return run_merge(args)
    except UsageError as e:
        print(f"annotation_merge: {e}", file=sys.stderr)
        return 2
    except SchemaError as e:
        print(f"annotation_merge: schema: {e}", file=sys.stderr)
        return 1
    except Refused as e:
        print(f"annotation_merge: refused: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
