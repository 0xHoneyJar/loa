#!/usr/bin/env bash
# =============================================================================
# evals/harness/lib/corpus-seed.sh — the review-recall corpus seeding library
# (cycle-133 Sprint 3 Task 3.3; SDD C-12, D-3.3 DEC-0851)
#
# Extracted from seed-corpus-from-record.sh so that seed-corpus-from-external.sh
# writes the same fixture: the fixture layout (pr-NN/{fixture.yaml, head.diff,
# PR.md, REVIEW-INSTRUCTIONS.md, AUDIT-INSTRUCTIONS.md, base/, head/}, the two
# recall tasks), the labels grammar (v1 and v2 headers, `@L<n>`, the manifest
# build, --sync-labels), the exposure block (MODEL_AVAILABILITY, the cutoff
# table), the SHA256SUMS freeze and check, the corpus.tsv row, the secret
# redaction of verbatim copies and the no-secrets pass. Byte-identity with the
# pre-extraction seeder: evals/tests/corpus-seed-lib.bats.
#
# Shape: the library is Python source held in a shell variable; a caller sources
# this file (a literal path, the eval.yml trust boundary) and feeds
# `corpus_seed_python` followed by its own Python main to `python3 -I -`. The
# definitions read the caller's globals REPO, CORPUS, NO_SECRETS, LABELS_DIR and
# MANIFESTS_DIR (defined by the main before any call) and SEED_TAG, the message
# prefix (default seed-corpus). Sourcing defines one variable and one function and
# changes no shell option.
#
# Function:
#   corpus_seed_python    print the library's Python source (stdout)
# =============================================================================

IFS= read -r -d '' _CORPUS_SEED_PY <<'PY' || true
import argparse, csv, fnmatch, hashlib, io, json, os, re, shutil, subprocess, sys, tempfile

FX_RX = re.compile(r"^pr-[0-9]{2}$")
HEADER = ["defect_id", "severity", "category", "file", "must_match", "label_source", "source"]
# cycle-132 D-2.3: the v2 header adds four trailing columns for annotated (fix-commit / incident) rows
HEADER_V2 = HEADER + ["annotators", "agreement", "adjudication", "review_driven"]
LABEL_SOURCES = ("review", "audit", "bridgebuilder", "fix")
LABEL_SOURCES_V2 = ("fix-commit", "incident", "fix-commit+incident")
ANNOTATORS_RX = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*(,[A-Za-z0-9][A-Za-z0-9_-]*)*$")
SHA_RX = re.compile(r"^[0-9a-f]{7,64}$")

SEED_TAG = "seed-corpus"   # the message prefix; a caller may rebind it after this library

def fail(msg, code=1):
    print(f"{SEED_TAG}: {msg}", file=sys.stderr)
    sys.exit(code)

def git(*a, binary=False, check=True):
    p = subprocess.run(["git", "-C", REPO, *a], capture_output=True, text=not binary)
    if check and p.returncode != 0:
        fail(f"git {' '.join(a[:3])} failed: {(p.stderr if not binary else p.stderr.decode('utf-8', 'replace')).strip()[:300]}")
    return p.stdout

def rev(r):
    p = subprocess.run(["git", "-C", REPO, "rev-parse", "--verify", "--quiet", f"{r}^{{commit}}"], capture_output=True, text=True)
    if p.returncode != 0:
        fail(f"missing commit: {r}")
    return p.stdout.strip()

def show(r, path):
    p = subprocess.run(["git", "-C", REPO, "show", f"{r}:{path}"], capture_output=True)
    return p.stdout if p.returncode == 0 else None

# cycle-132 FR-1: what each model could have seen (SDD §3.2 `exposure`). The Fable 5.1
# knowledge cutoff is the published month; Opus 5.5's vendor cutoff is not published and
# its catalog date is only an upper bound, so its exposure is never claimed either way.
MODEL_AVAILABILITY = {
    "fable_5_1": {"model": "claude-fable-5-1", "knowledge_cutoff": "2026-06"},
    "opus_5_5": {"model": "claude-opus-5-5", "catalog_date": "2026-10-05", "cutoff": None},
}
RETRIEVAL = "public-repository"
RETRIEVAL_PRIVATE = "private-repository"

def head_date(commit):
    """The head commit's committer date, UTC, YYYY-MM-DD."""
    p = subprocess.run(["git", "-C", REPO, "log", "-1", "--date=format-local:%Y-%m-%d", "--format=%cd", commit],
                       capture_output=True, text=True, env={**os.environ, "TZ": "UTC"})
    d = p.stdout.strip()
    if p.returncode != 0 or not re.match(r"^\d{4}-\d{2}-\d{2}$", d):
        fail(f"cannot date head commit {commit[:12]} in {REPO}")
    return d

def exposure_values(commit):
    d = head_date(commit)
    fable = "post-cutoff" if d[:7] > MODEL_AVAILABILITY["fable_5_1"]["knowledge_cutoff"] else "pre-cutoff"
    oc = MODEL_AVAILABILITY["opus_5_5"]["cutoff"]
    opus = "unverified" if oc is None else ("post-cutoff" if d[:7] > oc else "pre-cutoff")
    return d, fable, opus

def exposure_block(commit, retrieval=RETRIEVAL):
    """retrieval: public-repository (the default; the record seeder and public external sources) or
    private-repository (seed-corpus-from-external.sh --private-source: the head was never retrievable)"""
    d, fable, opus = exposure_values(commit)
    return ("exposure:\n"
            f"  fable_5_1: {fable}      # knowledge cutoff {MODEL_AVAILABILITY['fable_5_1']['knowledge_cutoff']}; head committed {d} (UTC)\n"
            f"  opus_5_5: {opus}        # vendor cutoff not published; the catalog date {MODEL_AVAILABILITY['opus_5_5']['catalog_date']} is an upper bound only\n"
            f"  retrieval: {retrieval}\n"
            f'contamination_note: "fix commits on main since {d}; sandbox has network; egress scanned (grader class 9)"\n')

def stamp_exposure(fx):
    """--stamp-exposure: drop any earlier exposure block / contamination_note, append the fresh block."""
    fy = os.path.join(CORPUS, fx, "fixture.yaml")
    if not os.path.isfile(fy):
        fail(f"{fx}: no fixture.yaml under {CORPUS}")
    raw = open(fy, encoding="utf-8", newline="").read()
    m = re.search(r'^head_commit:\s*"?([0-9a-f]{7,64})"?\s*$', raw, re.M)
    if not m:
        fail(f"{fx}: fixture.yaml has no head_commit (not a record fixture); left unchanged")
    blk = exposure_block(rev(m.group(1)))
    keep, in_blk = [], False
    for l in raw.splitlines(keepends=True):
        if in_blk and (l.startswith((" ", "\t")) or not l.strip()):
            continue
        in_blk = False
        if re.match(r"^exposure:\s*(#.*)?$", l.rstrip("\r\n")):
            in_blk = True; continue
        if l.startswith("contamination_note:"):
            continue
        keep.append(l)
    if keep and not keep[-1].endswith("\n"):
        keep[-1] += "\n"
    new = "".join(keep) + blk
    if new != raw:
        open(fy, "w", encoding="utf-8", newline="").write(new)
    fable = re.search(r"fable_5_1: (\S+)", blk).group(1)
    print(f"{fx}: exposure {'stamped' if new != raw else 'unchanged'} (fable_5_1 {fable}); run --freeze to refresh SHA256SUMS")

CTRL = re.compile(r"[\x00-\x1f\x7f-\x9f  ]")
def clean(s, cap=160):
    s = CTRL.sub(" ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s if len(s) <= cap else s[: cap - 1].rstrip() + "…"

# audit r1 DISS-C-007: shapes beyond the original nine (PEM blocks, JWTs, GitHub
# fine-grained/app/user tokens, Google and Stripe keys, generic key/token assignments);
# the generic patterns stay on ONE line so a redaction never joins lines.
SECRET_RX = [re.compile(p) for p in (
    r"AKIA[0-9A-Z]{16}", r"sk-[a-zA-Z0-9]{20,}", r"ghp_[a-zA-Z0-9]{36}", r"gho_[a-zA-Z0-9]{36}",
    r"github_pat_[A-Za-z0-9_]{20,}", r"gh[su]_[a-zA-Z0-9]{36}",
    r"glpat-[a-zA-Z0-9\-]{20,}", r"xox[bpors]-[a-zA-Z0-9\-]+", r"sk-ant-[a-zA-Z0-9\-]{20,}",
    r"AIza[0-9A-Za-z\-_]{35}", r"(?:sk|rk)_(?:live|test)_[0-9a-zA-Z]{20,}",
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----[^-]*-----END [A-Z ]*PRIVATE KEY-----",
    r"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}",
    r"password[ \t]*[:=][ \t]*[\"'][^\"'\n]{8,}", r"secret[ \t]*[:=][ \t]*[\"'][^\"'\n]{8,}",
    r"(?:api[_-]?key|access[_-]?token|auth[_-]?token)[ \t]*[:=][ \t]*[\"'][^\"'\n]{16,}")]
def has_secret(s):
    return any(r.search(s) for r in SECRET_RX)

REDACTED = [0]
def redact(b, count=True):
    """Secret-shaped strings in verbatim copies of tracked files (fake test keys)
    become a fixed marker, identically in base/, head/ and head.diff; line
    numbers never move. Counted in the dropped report."""
    if b is None:
        return None
    t = b.decode("utf-8", "replace") if isinstance(b, bytes) else b
    for r in SECRET_RX:
        t, n = r.subn("REDACTED-TEST-SECRET", t)
        REDACTED[0] += n if count else 0
    return t.encode("utf-8") if isinstance(b, bytes) else t

def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()

def freeze():
    entries = []
    for root, _d, files in os.walk(CORPUS):
        for f in files:
            rel = os.path.relpath(os.path.join(root, f), CORPUS)
            if rel != "SHA256SUMS":
                entries.append(rel)
    lines = [f"{sha(os.path.join(CORPUS, rel))}  {rel}" for rel in sorted(entries)]
    open(os.path.join(CORPUS, "SHA256SUMS"), "w").write("\n".join(lines) + "\n")
    return len(lines)

def check():
    bad, n = [], 0
    for line in open(os.path.join(CORPUS, "SHA256SUMS"), encoding="utf-8"):
        if not line.strip():
            continue
        n += 1
        d, rel = line.rstrip("\n").split("  ", 1)
        p = os.path.join(CORPUS, rel)
        if not os.path.isfile(p) or sha(p) != d:
            bad.append(rel)
    listed = {l.rstrip("\n").split("  ", 1)[1] for l in open(os.path.join(CORPUS, "SHA256SUMS"), encoding="utf-8") if l.strip()}
    for root, _d, files in os.walk(CORPUS):
        for f in files:
            rel = os.path.relpath(os.path.join(root, f), CORPUS)
            if rel != "SHA256SUMS" and rel not in listed:
                bad.append(rel + " (not listed)")
    if bad:
        fail("SHA256SUMS mismatch: " + ", ".join(bad[:20]))
    print(f"corpus OK: {n} files match SHA256SUMS")

# ---------------------------------------------------------------- labels I/O
def read_labels(fx, content=None):
    """content: labels text to parse instead of the file (--sync-labels verifies before it writes)."""
    path = os.path.join(LABELS_DIR, f"{fx}.tsv")
    if content is None and not os.path.isfile(path):
        fail(f"labels not found: {path}")
    text = (open(path, encoding="utf-8").read() if content is None else content).splitlines()
    if not text or not re.match(r"^# approved-by: \S", text[0]):
        fail(f"{path}: the first line must be '# approved-by: <who> <date>' (or 'pending')")
    approved_by = text[0][len("# approved-by: "):].strip()
    body = [l for l in text[1:] if l and not l.startswith("#")]
    hdr = body[0].split("\t") if body else None
    if hdr not in (HEADER, HEADER_V2):
        fail(f"{path}: header must be: " + "\t".join(HEADER) + " (v2: + " + " ".join(HEADER_V2[len(HEADER):]) + ")")
    rows = []
    for i, l in enumerate(body[1:], 2):
        cells = l.split("\t")
        if len(cells) != len(hdr):
            fail(f"{path}: row {i} has {len(cells)} columns, want {len(hdr)}")
        rows.append(dict(zip(hdr, cells)))
    return approved_by, rows, text

def v2_row_error(r):
    """why a v2 row's four trailing columns are malformed, else None. An annotated row (label_source
    fix-commit / incident / fix-commit+incident) names its annotators, agreement and review_driven; any
    row may hold `-` in a column it does not use; an adjudicated row carries its reason."""
    annotated = r["label_source"] in LABEL_SOURCES_V2
    a, g, j, rd = r["annotators"], r["agreement"], r["adjudication"], r["review_driven"]
    if not ANNOTATORS_RX.match(a) and not (a == "-" and not annotated):
        return f"annotators {a!r} is not a comma list of annotator ids" + (" (an annotated row names them)" if a == "-" else "")
    if g not in ("agreed", "adjudicated") and not (g == "-" and not annotated):
        return f"agreement {g!r} is not agreed|adjudicated" + ("" if annotated else "|-")
    if rd not in ("true", "false") and not (rd == "-" and not annotated):
        return f"review_driven {rd!r} is not true|false" + ("" if annotated else "|-")
    if g == "adjudicated" and j in ("", "-"):
        return "an adjudicated row carries the reason in adjudication"
    return None

def v2_fields(r):
    """the manifest form of a primary row's v2 columns (`-` → empty list / null)"""
    return {"annotators": [] if r["annotators"] == "-" else r["annotators"].split(","),
            "agreement": None if r["agreement"] == "-" else r["agreement"],
            "adjudication": None if r["adjudication"] in ("", "-") else r["adjudication"],
            "review_driven": {"true": True, "false": False}.get(r["review_driven"])}

# bd-8o5rx: generated artefacts are never fix regions (see the header for the list)
GENERATED_NAMES = {"checksums.json", "REPO-MAP.md", ".build-manifest.json"}
GENERATED_SUFFIXES = (".map", ".d.ts", ".checksum")
def generated_path(p):
    parts = p.split("/")
    return "dist" in parts[:-1] or parts[-1] in GENERATED_NAMES or parts[-1].endswith(GENERATED_SUFFIXES)

EXCLUDED_SEEN = set()
def note_excluded(p):
    if p not in EXCLUDED_SEEN:
        EXCLUDED_SEEN.add(p)
        print(f"excluded generated path: {p}", file=sys.stderr)

def unique_line(lines, needle):
    hits = [i for i, l in enumerate(lines, 1) if needle in l]
    return hits[0] if len(hits) == 1 else None

def head_path(fx, f):
    """(path, None) for a labels `file` inside <corpus>/<fx>/head, else (None, why): no absolute
    path, `..` component, backslash or NUL, and the resolved path (symlinks followed) stays under head/."""
    if not f or os.path.isabs(f) or "\\" in f or "\x00" in f or ".." in f.split("/"):
        return None, "an absolute path, a `..` component, a backslash or a NUL"
    base = os.path.realpath(os.path.join(CORPUS, fx, "head"))
    hp = os.path.join(base, f)
    if not os.path.realpath(hp).startswith(base + os.sep):
        return None, "it resolves outside head/"
    return hp, None

# bd-y4pqj: `@L<n>` names head line n (1-based) for a curated anchor whose text is not unique
# only an `@L`-shaped value (one word of letters, digits, `-`) is the line grammar: `@L12`
# resolves, `@L0`/`@Lx`/`@L4x`/`@L-1` are refused; longer text such as `@Lazy foo` stays text
AT_LINE_RX = re.compile(r"^@L([1-9][0-9]*)$")
AT_SHAPE_RX = re.compile(r"^@L[0-9A-Za-z-]*$")
def resolve_anchor(lines, must_match, fname):
    """(line, None) when the must_match resolves, else (None, why)."""
    if AT_SHAPE_RX.match(must_match):
        m = AT_LINE_RX.match(must_match)
        if not m:
            return None, "is not @L<n> with n a positive integer"
        if int(m.group(1)) > len(lines):
            return None, f"is past the end of head/{fname} ({len(lines)} lines)"
        return int(m.group(1)), None
    at = unique_line(lines, must_match)
    return (at, None) if at is not None else (None, f"is not on exactly one line of head/{fname}")

def build_manifest(fx, write=True, labels_content=None):
    approved_by, rows, _ = read_labels(fx, labels_content)
    fyaml = os.path.join(CORPUS, fx, "fixture.yaml")
    meta = {}
    for l in open(fyaml, encoding="utf-8"):
        m = re.match(r"^(sprint|head_commit|fix_commit|record_ref):\s*\"?([^\"\n]*)\"?$", l)
        if m:
            meta[m.group(1)] = m.group(2)
    defects, regions, errors, order, extra = {}, [], [], [], {}
    for r in rows:
        if r["label_source"] in LABEL_SOURCES_V2 and "review_driven" not in r:
            errors.append(f"{r['defect_id']}: label_source {r['label_source']!r} needs the v2 header "
                          f"(+ {' '.join(HEADER_V2[len(HEADER):])})"); continue
        if r["label_source"] not in LABEL_SOURCES + LABEL_SOURCES_V2:
            errors.append(f"{r['defect_id']}: label_source {r['label_source']!r}"); continue
        if "review_driven" in r:
            why = v2_row_error(r)
            if why:
                errors.append(f"{r['defect_id']}: {why}"); continue
        hp, why = head_path(fx, r["file"])
        if hp is None:
            errors.append(f"{r['defect_id']}: file {r['file']!r} is not a path inside head/ ({why})"); continue
        if not os.path.isfile(hp):
            errors.append(f"{r['defect_id']}: head/{r['file']} missing"); continue
        lines = open(hp, encoding="utf-8", errors="replace").read().splitlines()
        if r["label_source"] == "fix" and generated_path(r["file"]):
            note_excluded(r["file"]); continue
        if r["label_source"] == "fix":
            m = re.match(r"^fix/[0-9a-f]+:(\d+)-(\d+)$", r["source"])
            if not m:
                errors.append(f"{r['defect_id']}: fix source must be fix/<sha>:<start>-<end>"); continue
            regions.append({"id": r["defect_id"], "file": r["file"], "start": int(m.group(1)), "end": int(m.group(2)),
                            "source": r["source"]})
            continue
        at, why = resolve_anchor(lines, r["must_match"], r["file"])
        if at is None:
            errors.append(f"{r['defect_id']}: must_match {r['must_match']!r} {why}"); continue
        d = defects.get(r["defect_id"])
        if d is None:
            order.append(r["defect_id"])
            defects[r["defect_id"]] = {"id": r["defect_id"], "file": r["file"], "anchor_line": at, "anchors": [at],
                                       "must_match": r["must_match"], "severity": r["severity"], "category": r["category"],
                                       "label_source": r["label_source"], "source": r["source"],
                                       "source_commit": meta.get("head_commit", "")[:8], "synthetic": False}
            if "review_driven" in r:
                extra[r["defect_id"]] = (r["label_source"] in LABEL_SOURCES_V2, v2_fields(r))
        else:
            if d["file"] != r["file"]:
                errors.append(f"{r['defect_id']}: extra anchor rows must name the same file"); continue
            d["anchors"].append(at)
    if errors:
        fail(f"{fx}: " + "; ".join(errors))
    # cycle-132 D-2.3: an annotated defect makes the manifest v2 (label_set, the four columns per defect,
    # the incident scan's main_sha); a labels file without one builds today's manifest byte for byte
    v2 = any(annotated for annotated, _f in extra.values())
    out = []
    for k in order:
        d = defects[k]
        d["anchors"] = sorted(set(d["anchors"]))
        if len(d["anchors"]) == 1:
            del d["anchors"]
        if v2:
            d.update(extra[k][1] if k in extra else v2_fields(dict.fromkeys(HEADER_V2[len(HEADER):], "-")))
        out.append(d)
    record = {"sprint": meta.get("sprint"), "record_ref": meta.get("record_ref"),
              "head_commit": meta.get("head_commit"), "fix_commit": meta.get("fix_commit")}
    if v2:
        ipath = os.path.join(CORPUS, "incidents", f"{fx}.meta.json")
        if os.path.isfile(ipath):
            try:
                im = json.load(open(ipath, encoding="utf-8"))
            except ValueError as e:
                fail(f"{fx}: {ipath} does not parse ({e})")
            if not isinstance(im, dict) or not isinstance(im.get("main_sha"), str) or not SHA_RX.match(im["main_sha"]):
                fail(f"{fx}: {ipath} has no main_sha (hex)")
            record["incidents_meta"] = {"main_sha": im["main_sha"]}
    man = {"fixture": fx, **({"label_set": "v2"} if v2 else {}), "approved": approved_by != "pending",
           "approved_by": approved_by, "record": record, "defects": out, "fix_regions": regions}
    if write:
        os.makedirs(MANIFESTS_DIR, exist_ok=True)
        json.dump(man, open(os.path.join(MANIFESTS_DIR, f"{fx}.json"), "w"), indent=2)
    return man

def manifest_diff(got, want):
    """Where a rebuilt manifest differs from the tracked one (for the --sync-labels refusal)."""
    out = [k for k in sorted(set(got) | set(want)) if k != "defects" and got.get(k) != want.get(k)]
    gd = {d.get("id"): d for d in got.get("defects", [])}
    if [d.get("id") for d in got.get("defects", [])] != [d.get("id") for d in want.get("defects", [])]:
        out.append("defect ids or order")
    for d in want.get("defects", []):
        g = gd.get(d.get("id"))
        if g is not None and g != d:
            out.append(f"defect {d['id']}: " + ", ".join(sorted(k for k in set(g) | set(d) if g.get(k) != d.get(k)) or ["key order"]))
    return "; ".join(out[:8]) or "formatting or key order"

def sync_labels(fx):
    """bd-y4pqj: add a labels row for every manifest anchor no row resolves to; copy approved_by (see the header)."""
    mpath = os.path.join(MANIFESTS_DIR, f"{fx}.json")
    lpath = os.path.join(LABELS_DIR, f"{fx}.tsv")
    if not os.path.isfile(mpath):
        fail(f"manifest not found: {mpath}")
    mraw = open(mpath, encoding="utf-8").read()
    man = json.loads(mraw)
    approved_by = man.get("approved_by")
    if (not isinstance(approved_by, str) or not approved_by or approved_by != approved_by.strip()
            or len(approved_by.splitlines()) != 1 or re.search(r"[\x00-\x1f\x7f-\x9f\u2028\u2029]", approved_by)):
        fail(f"{mpath}: approved_by must be a one-line non-empty string without surrounding space")
    if man.get("approved") is not (approved_by != "pending"):
        fail(f"{mpath}: approved {man.get('approved')!r} disagrees with approved_by {approved_by!r}")
    read_labels(fx)  # validates the header and every row's shape
    raw = open(lpath, encoding="utf-8", newline="").read()
    tl = raw.splitlines(keepends=True)
    heads, have, last, primary = {}, {}, {}, {}
    def head(f, who):
        if f not in heads:
            hp, why = head_path(fx, f)
            if hp is None:
                fail(f"{fx}: {who}: file {f!r} is not a path inside head/ ({why})")
            if not os.path.isfile(hp):
                fail(f"{fx}: head/{f} missing")
            heads[f] = open(hp, encoding="utf-8", errors="replace").read().splitlines()
        return heads[f]
    hdr = None   # HEADER or HEADER_V2 (read_labels validated it)
    for i, l in enumerate(tl[1:], 1):
        l = l.rstrip("\r\n")
        if not l or l.startswith("#"):
            continue
        if hdr is None:
            hdr = l.split("\t"); continue
        r = dict(zip(hdr, l.split("\t")))
        if r["label_source"] == "fix":
            continue
        at, why = resolve_anchor(head(r["file"], r["defect_id"]), r["must_match"], r["file"])
        if at is None:
            fail(f"{fx}: {r['defect_id']}: must_match {r['must_match']!r} {why}")
        primary.setdefault(r["defect_id"], r)
        have.setdefault(r["defect_id"], set()).add(at)
        last[r["defect_id"]] = i
    ids = [d.get("id") for d in man.get("defects", [])]
    for k in primary:
        if k not in ids:
            fail(f"{fx}: label {k} is not a defect of manifests/{fx}.json")
    adds, n_text, n_at = {}, 0, 0
    for d in man.get("defects", []):
        p = primary.get(d.get("id"))
        if p is None:
            fail(f"{fx}: manifest defect {d.get('id')!r} has no labels row")
        if d.get("file") != p["file"]:
            fail(f"{fx}: manifest defect {d['id']} names {d.get('file')!r}, its labels rows {p['file']!r}")
        want = d.get("anchors", [d.get("anchor_line")])
        lines = head(p["file"], d["id"])
        for n in sorted(set(want)):
            if not isinstance(n, int) or isinstance(n, bool) or not 1 <= n <= len(lines):
                fail(f"{fx}: manifest defect {d['id']} anchor {n!r} is not a line of head/{p['file']}")
            if n in have[d["id"]]:
                continue
            t = lines[n - 1].strip()
            textual = (t and "\t" not in t and not AT_SHAPE_RX.match(t) and len(t.splitlines()) == 1
                       and not has_secret(t) and unique_line(lines, t) == n)
            mm = t if textual else f"@L{n}"
            n_text, n_at = n_text + bool(textual), n_at + (not textual)
            adds.setdefault(last[d["id"]], []).append(
                (d["id"], mm, "\t".join(mm if c == "must_match" else p[c] for c in hdr)))
            have[d["id"]].add(n)
    out = [f"# approved-by: {approved_by}\n"]
    for i, l in enumerate(tl[1:], 1):
        if i in adds and not l.endswith("\n"):
            l += "\n"
        out.append(l)
        out.extend(row + "\n" for _k, _m, row in adds.get(i, []))
    new = "".join(out)
    header_changed = tl[0].rstrip("\r\n") != out[0].rstrip("\n")
    # verify before writing, on every run (a no-op sync proves the labels too): any refusal or
    # error while rebuilding from the new content leaves the labels file untouched
    try:
        rebuilt = build_manifest(fx, write=False, labels_content=new)
    except SystemExit:
        fail(f"{fx}: the synced labels do not build (see above); labels left unchanged")
    except Exception as e:
        fail(f"{fx}: rebuilding from the synced labels failed ({type(e).__name__}: {e}); labels left unchanged")
    if json.dumps(rebuilt, indent=2) != mraw:
        fail(f"{fx}: the synced labels would not rebuild manifests/{fx}.json byte for byte "
             f"({manifest_diff(rebuilt, man)}); labels left unchanged")
    if new != raw:
        # atomic: a temp file beside the target, then os.replace (never an in-place truncation)
        fd, tmp = tempfile.mkstemp(dir=LABELS_DIR, prefix=f".{fx}.tsv.", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
                fh.write(new); fh.flush(); os.fsync(fh.fileno())
            os.chmod(tmp, os.stat(lpath).st_mode & 0o7777)
            os.replace(tmp, lpath)
        except BaseException:
            if os.path.exists(tmp):
                os.remove(tmp)
            raise
    print(f"{fx}: added {n_text + n_at} row(s) ({n_text} text, {n_at} @L<n>); approved-by "
          + (f"set to {approved_by!r}" if header_changed else "unchanged")
          + ("; run --freeze to refresh SHA256SUMS" if new != raw else ""))
    for i in sorted(adds):
        for k, mm, _row in adds[i]:
            print(f"  + {k}\t{mm}")

# ------------------------------------------------- fixture layout (both seeders; cycle-133 C-12)
INSTRUCTION_FILES = ("REVIEW-INSTRUCTIONS.md", "AUDIT-INSTRUCTIONS.md")

def corpus_set(fx, line):
    """<corpus>/corpus.tsv: drop fx's row and its `# fx …` gap comment, then append `line`."""
    spec = os.path.join(CORPUS, "corpus.tsv")
    keep = [l for l in open(spec, encoding="utf-8").read().splitlines() if not (l.startswith(fx + "\t") or l.startswith(f"# {fx} "))]
    open(spec, "w", encoding="utf-8").write("\n".join(keep + [line]) + "\n")

def corpus_row(fx, kind, commit):
    """the fixture's corpus.tsv row: fixture, kind (record | external), the head commit's first 8, its labels file."""
    corpus_set(fx, "\t".join([fx, kind, commit[:8], f"labels/{fx}.tsv", "-", "-", "-", "-"]))

def write_layout(fdir, base_files, head_files, diff_text, pr_md):
    """the sandbox-copied fixture directory, rebuilt from nothing: base/<path> and head/<path> from the
    (path, bytes) lists, head.diff, PR.md and the pr-01 instruction templates. fixture.yaml is the caller's."""
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    for sub, files in (("base", base_files), ("head", head_files)):
        for rel, data in files:
            dest = os.path.join(fdir, sub, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            open(dest, "wb").write(data)
    open(os.path.join(fdir, "head.diff"), "w", encoding="utf-8").write(diff_text)
    open(os.path.join(fdir, "PR.md"), "w", encoding="utf-8").write(pr_md)
    tmpl = os.path.join(CORPUS, "pr-01")
    for name in INSTRUCTION_FILES:
        shutil.copyfile(os.path.join(tmpl, name), os.path.join(fdir, name))

def write_tasks(fx, what, tags, tasks_dir):
    """one review-recall and one audit-recall task per fixture, mirroring the pr-01 tasks; `what` ends the
    description, `tags` is a tuple whose None entry becomes the suite name."""
    for suite, kind, skill, art, verb in (("review-recall", "review", "reviewing-code", "review.md", "review recall on"),
                                          ("audit-recall", "audit", "auditing-security", "audit.md", "audit planted-defect detection on")):
        instr = "REVIEW-INSTRUCTIONS.md" if kind == "review" else "AUDIT-INSTRUCTIONS.md"
        tdir = os.path.join(tasks_dir, suite); os.makedirs(tdir, exist_ok=True)
        tag_list = ", ".join(json.dumps(suite if t is None else t) for t in tags)
        open(os.path.join(tdir, f"{kind}-{fx}.yaml"), "w", encoding="utf-8").write(
            f'id: {kind}-{fx}\nschema_version: 1\nskill: {skill}\ncategory: skill-quality\nfixture: review-prs/{fx}\n'
            f'description: "{verb} {what}"\n'
            f'prompt: "Read {instr} in this directory and carry it out."\nagent:\n  skill: {skill}\n  artifacts: [{art}]\n'
            # record PRs carry 66-383 KB diffs (pr-01 … pr-08: ~7 KB): an hour, not 25 min
            f'trials: 3\ntimeout:\n  per_trial: 3600\n  per_grader: 60\ngraders:\n  - type: code\n    script: recall-vs-defects.sh\n'
            f'    args: ["{fx}", "{art}"]\n    weight: 1.0\n  - type: code\n    script: verdict-consistency.sh\n'
            f'    args: ["{art}", "{kind}"]\n    weight: 0.5\ndifficulty: advanced\ntags: [{tag_list}]\n')

def no_secrets_scan(d):
    """evals/graders/no-secrets.sh over a directory: (clean, its stdout)."""
    p = subprocess.run(["bash", NO_SECRETS, d], capture_output=True, text=True)
    return p.returncode == 0, p.stdout.strip()
PY

corpus_seed_python() { printf '%s\n' "$_CORPUS_SEED_PY"; }
