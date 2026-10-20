#!/usr/bin/env bash
# =============================================================================
# recall-vs-defects.sh — deterministic planted-defect recall grader
#
# cycle-124 Sprint 3 (PRD FR-9). Args: $1=workspace, $2=fixture id (pr-NN),
# $3=review file (default review.md). Reads the HIDDEN manifest
# evals/fixtures/review-prs/manifests/<id>.json (never copied into the
# sandbox) and the agent's review.
#
# Rule (PRD FR-9 A/B protocol, no fuzzy adjudication): a defect is DETECTED
# when the review contains a `path:line` (or `path:line-line`) citation whose
# path ends with the defect's file (repo-relative, `head/`-prefixed, or the
# bare basename) and whose line, or line range, falls within ±3 of the
# manifest anchor — `anchor_line`, or any line in `anchors[]` for a defect
# with more than one site.
#
# Parser (1.1.0, bd-ewrc): a leading `(` is not part of the path; comma
# continuations (`path:776,807`, `path:10, 118-121`) and a later bare `:N` or
# `head:N` / `base:N` bind to the most recent cited path. A `:N` glued to a
# word or a number (`note:40`, `10:40`), or with no cited path before it,
# credits nothing.
#
# Parser 1.1.1 (sprint-250 review run 1, n40-n42): the LOA-VERDICT trailer is
# removed before citations are parsed, and a bare `:N` after a quote, bracket,
# brace or `*` (JSON such as `"high":3`) credits nothing; a backtick- or
# bold-wrapped path (`` `b.sh`:40 ``, `**b.sh**:40`) binds its own line; a comma
# continuation or range stays on its line, and a continuation must end at a
# number boundary (no dates);
# a path containing `//` (a URL) is not a citation.
# Run 2 (#11/#13-#15): a match inside any URL token (`scheme://...`) is not a
# citation; a range dash is unspaced and every number (first, continuation,
# bare) ends at a boundary (no further `-N` / `–N`: no dates); the
# quote/bracket guard applies only to the fully bare `:N` (plus a closing
# backtick), so `"head:40"` binds as in 1.1.0; one trailer pattern strips and
# reads the LOA-VERDICT comment and never crosses another comment's bounds.
# Parser 1.1.2 (the run 2 changes above, plus sprint-250 review run 3): the
# URL look-back takes the text after the last whitespace — one linear split —
# so a citation that opens a line never inherits the previous line's URL.
# The parser runs as `python3 -I -` (audit dissent run 1, n32): a module planted
# in the invoker's cwd (a forging json.py) is never imported (RG-27).
#
# Grader 1.2.0 (cycle-129 FR-2, SDD D-2.3): adds the refuted-share figure;
# the recall rule and the pass/score contract are unchanged. A FINDING is one
# distinct cited (path, line-range); it is MATCHED when it overlaps (±3) a
# defect site or a manifest `fix_regions[]` entry ({file, start, end}: the
# head-side lines a record fixture's fix commit touched). details gain
# findings_cited, findings_refuted and refuted_share (refuted / cited; null
# when nothing is cited).
#
# Grader 1.3.0 (cycle-131 FR-2, SDD §5.2, D-2.1; rule "pm3_or_same_function"):
#   Citation validity first (both clauses of the new rule): a cited line is positive;
#   a cited range is ordered (a <= b, the parser orders it); when the defect's file
#   exists under the head directory the range must lie inside it (1 <= a <= b <= its
#   line count), else it credits nothing. A cited range wider than 25 lines credits
#   only through its first line. The two _pm3 results keep the 1.2.0 rule exactly (no
#   validity rule, no range cap), so recall_pm3_v1 reproduces a 1.2.x grade.
#   Detection: a valid citation (path, a, b) detects defect d when its path matches d's
#   file and (i) [a, b] lies within ±3 of any site (unchanged), OR (ii) same scope: the
#   enclosing definition of the site in head/<file>, identified by its HEADER LINE
#   NUMBER (never its name), equals the enclosing definition of any cited line in
#   [a, b]. Definition headers: bash (.sh, .bash, or a bash/sh shebang)
#   `^\s*(function\s+)?NAME\s*\(\)\s*\{?` and `^\s*function\s+NAME\s*\{`; python
#   `^\s*def NAME\(`; bats `^@test "…"` plus the bash forms; markdown `#` headings
#   (the nearest preceding heading's section). A definition runs from its header to
#   the line before the next header at the same or lower indentation (markdown: the
#   same or a higher heading level), else to the end of the file, and no further than
#   its own end (end-of-definition detection): bash and bats — the first `}` line at
#   the header's indentation (a one-line `f() { …; }` ends on its header); python —
#   the last line before the first later non-blank, non-comment line indented no
#   deeper than the def. Nested definitions resolve to the innermost (the latest
#   header whose definition holds the line); a line after a definition's end and
#   before the next header is top-level.
#   Caps: a definition longer than 400 lines, or a file type with no definition
#   regex (yaml, json, txt, tsv, …), falls back to ±20 lines around the site (and a
#   cited line in such a definition has no scope); a site outside every definition
#   (top-level code, text before the first heading) has no scope (±3 only).
#   Head directory: $EVAL_HEAD_DIR, else <manifest dir>/../<fixture>/head, else — only under
#   EVAL_ALLOW_WORKSPACE_HEAD=1 — <workspace>/pr/head (the graded agent's own copy; details.head_dir_source
#   says which was used); with none, or a file absent from it, (ii) never credits.
#   Three results in details, each with detected[] / missed[] (defect ids):
#     recall_pm3_v1  the 1.2.0 rule against <manifest dir>/v1/<fixture>.json (the
#                    original anchors); the current manifest when v1/ has none
#                    (v1_manifest false)
#     recall_pm3     the 1.2.0 rule against the current manifest
#     recall         (i) or (ii) on valid citations against the current manifest —
#                    pass and score follow it
#   credits_function_only: ids in detected and not in detected_pm3; rule:
#   "pm3_or_same_function". findings_cited / findings_refuted / false_positives read
#   the parsed citations before the validity rules, as in 1.2.0.
#
# Clean fixtures (0 planted defects) measure FALSE POSITIVES: the LOA-VERDICT
# trailer's critical+high counts; without a trailer, every file:line citation
# counts as one.
#
# Output: {"pass", "score", "details":{recall, planted, detected[], missed[],
#          recall_pm3, detected_pm3[], missed_pm3[], recall_pm3_v1, detected_pm3_v1[],
#          missed_pm3_v1[], planted_v1, v1_manifest, credits_function_only[], rule,
#          false_positives, severity_counts, model, effort, tokens, …}, "grader_version"}
#   pass  = every planted defect detected (defect fixture) / zero false
#           positives (clean fixture); score = recall*100 or 100/0.
# Exit: 0 pass, 1 fail, 2 error (missing manifest / bad args)
#
# Tested by evals/tests/eval-recall-grader.bats.
# =============================================================================
set -euo pipefail

workspace="${1:-}"
fixture="${2:-}"
review_name="${3:-review.md}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="${EVAL_MANIFEST_DIR:-$SCRIPT_DIR/../fixtures/review-prs/manifests}"

err() { printf '{"pass":false,"score":0,"details":{"error":%s},"grader_version":"1.3.0"}\n' "$(jq -Rn --arg m "$1" '$m')"; exit 2; }

[[ -n "$workspace" && -d "$workspace" ]] || err "invalid workspace"
[[ -n "$fixture" && "$fixture" =~ ^[A-Za-z0-9._-]+$ ]] || err "invalid fixture id"
manifest="$MANIFEST_DIR/$fixture.json"
[[ -f "$manifest" ]] || err "manifest not found: $manifest"
case "$review_name" in */*|..*) err "review file must be a bare name" ;; esac

review="$workspace/$review_name"
executor="$workspace/.eval/executor.json"

if [[ ! -f "$review" ]]; then
  printf '{"pass":false,"score":0,"details":{"error":"review file not found: %s","planted":%s,"detected":[],"recall":0},"grader_version":"1.3.0"}\n' \
    "$review_name" "$(jq '.defects | length' "$manifest")"
  exit 1
fi

manifest_v1="$MANIFEST_DIR/v1/$fixture.json"
[[ -f "$manifest_v1" && ! -L "$manifest_v1" ]] || manifest_v1=""
head_dir="${EVAL_HEAD_DIR:-}"; head_src="env"
if [[ -z "$head_dir" ]]; then
  head_src="none"
  if [[ -d "$MANIFEST_DIR/../$fixture/head" ]]; then head_dir="$MANIFEST_DIR/../$fixture/head"; head_src="fixture"
  elif [[ "${EVAL_ALLOW_WORKSPACE_HEAD:-}" == 1 && -d "$workspace/pr/head" ]]; then head_dir="$workspace/pr/head"; head_src="workspace"
  fi   # the workspace copy is the graded agent's own writable tree: never the default (audit r1 DISS-C-002)
fi

python3 -I - "$manifest" "$review" "$executor" "$manifest_v1" "$head_dir" "$head_src" <<'PY'
import json, os, re, stat, sys
manifest_path, review_path, executor_path, manifest_v1_path, head_dir, head_src = sys.argv[1:7]
man = json.load(open(manifest_path))
man_v1 = json.load(open(manifest_v1_path)) if manifest_v1_path else man
text = open(review_path, encoding="utf-8", errors="replace").read()

# path:line[-line] citations. Path = something with a file extension; the
# optional trailing range keeps `file.py:10-14` in one token, and the comma
# list after it (`:776,807`) belongs to the same path. A bare `:N` (or
# `head:N` / `base:N`) not glued to a word binds to the most recent path.
# a range dash is unspaced (`a.sh:12 - 40 rows` is prose, not a range) and
# every number ends at a boundary: no letter or digit, and no hyphen / en dash
# before another digit, after it (dates such as 2026-10-05 / 2026–10–05 never
# parse; an open `:369-...` still cites 369) — sprint-250 review run 2, #13
RNG = r'(\d{1,6})(?:[-–](\d{1,6}))?(?![A-Za-z0-9]|[-–]\d)'
CITE = re.compile(
    r'(?P<path>[A-Za-z0-9_./+()-]+\.[A-Za-z0-9]{1,6})[`*)]{0,3}:(?P<first>' + RNG
    + r'(?:[ \t]*,[ \t]*' + RNG + r')*)'
    # head:N / base:N keep the 1.1.0 boundary set ("head:40" binds); the JSON
    # punctuation set, plus a CLOSING backtick (one after a token character:
    # `rows`:40, `"high"`:3), guards only the fully bare :N — an opening
    # backtick (`:7`, (`:212`)) still binds (RG-13) — run 2, #14
    r'|(?:(?<![A-Za-z0-9_./:])(?:head|base)|(?<![A-Za-z0-9_./:"\'{}\[\]*])(?<![A-Za-z0-9_"\'}\]]`)):(?P<bare>' + RNG + r')')
ONE = re.compile(RNG)
cites = []
last = None
# the trailer is machine output (its counts are read below), never a citation.
# One pattern strips and reads it (tolerant whitespace, line breaks); the body
# may not contain another comment's `<!--` or `-->`, so an unterminated
# `<!-- LOA-VERDICT` strips nothing — sprint-250 review run 2, #15
TRAILER = re.compile(r'<!--\s*LOA-VERDICT\s*(\{(?:(?!<!--|-->).)*\})\s*-->', re.S)
body = TRAILER.sub('', text)
URL = re.compile(r'[A-Za-z][A-Za-z0-9+.-]*://|^//')
for m in CITE.finditer(body):
    if m.group("path") is not None:
        # a URL (https://h/x.js:8080, //host.com:8080) is not a path, nor is a
        # partial match that starts later inside the URL token
        # (https://u@h.com/x.js:8080 matches `h.com/x.js`) — run 2, #11
        # the token so far is the window's text after its last whitespace —
        # one linear split ("" when the window ends in whitespace); `\S*$`
        # also matched before a final newline, so a line-leading citation
        # inherited the previous line's URL, and was O(k^2) — run 3
        tok = re.split(r'\s', body[max(0, m.start() - 4096):m.start()])[-1] + m.group("path")
        if "//" in m.group("path") or URL.search(tok):
            continue
        p = m.group("path").lstrip("(")
        if p.startswith("./"):
            p = p[2:]
        last, spans = p, m.group("first")
    elif last is not None:
        p, spans = last, m.group("bare")
    else:
        continue
    for r in ONE.finditer(spans):
        a = int(r.group(1)); b = int(r.group(2)) if r.group(2) else a
        if b < a:
            a, b = b, a
        cites.append((p, a, b))

def path_matches(cited, defect_file):
    cited = cited.split("head/", 1)[1] if cited.startswith("head/") else cited
    cited = cited.split("base/", 1)[1] if cited.startswith("base/") else cited
    if cited == defect_file or defect_file.endswith("/" + cited):
        return True
    return cited == defect_file.rsplit("/", 1)[-1]

# ---- 1.3.0: head files, definition scopes, citation validity --------------------------
RANGE_CAP = 25      # a wider cited range credits only through its first line
SPAN_CAP = 400      # a longer definition falls back to ±FALLBACK around the site
FALLBACK = 20
BASH_HDR = (re.compile(r'^(\s*)(?:function\s+)?[A-Za-z_][A-Za-z0-9_.:-]*\s*\(\)\s*\{?'),
            re.compile(r'^(\s*)function\s+[A-Za-z_][A-Za-z0-9_.:-]*\s*\{'))
PY_HDR = re.compile(r'^(\s*)def\s+[A-Za-z_][A-Za-z0-9_]*\s*\(')
BATS_HDR = re.compile(r'^()@test\s+"')
MD_HDR = re.compile(r'^(#{1,6})(?:\s|$)')
FILE_CAP = 4 * 1024 * 1024
_files = {}


def head_lines(rel):
    """the head/<rel> file's lines (a regular file, no symlink, inside head_dir), else None"""
    if rel in _files:
        return _files[rel]
    out = None
    if head_dir and rel and not rel.startswith("/") and ".." not in rel.split("/"):
        p = os.path.join(head_dir, *rel.split("/"))
        root = os.path.realpath(head_dir)
        try:
            if os.path.realpath(p).startswith(root + os.sep):
                fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
                try:
                    st = os.fstat(fd)
                    if stat.S_ISREG(st.st_mode) and st.st_size <= FILE_CAP:
                        data = b""
                        while True:
                            chunk = os.read(fd, 1 << 20)
                            if not chunk:
                                break
                            data += chunk
                        out = data.decode("utf-8", "replace").split("\n")
                        if out and out[-1] == "":
                            out.pop()
                finally:
                    os.close(fd)
        except OSError:
            out = None
    _files[rel] = out
    return out


def lang(rel, lines):
    base = rel.rsplit("/", 1)[-1]
    ext = base.rsplit(".", 1)[-1].lower() if "." in base else ""
    if ext in ("sh", "bash"):
        return "bash"
    if ext == "py":
        return "python"
    if ext == "bats":
        return "bats"
    if ext in ("md", "markdown"):
        return "markdown"
    if not ext and lines and re.match(r'^#!\s*\S*(?:/env\s+)?(?:ba)?sh\b|^#!\s*\S*/(?:ba)?sh\b', lines[0]):
        return "bash"
    return None


def headers(kind, lines):
    """[(line, level)]: each definition header's 1-based line and its indentation (markdown: level)"""
    out = []
    fence = None
    for i, l in enumerate(lines, 1):
        m = None
        if kind == "markdown":
            fm = re.match(r"^\s{0,3}(`{3,}|~{3,})(.*)$", l)   # a fenced block's `#` lines are code, not headings (review r1 DISS-C-004)
            if fm:
                tok, rest = fm.group(1), fm.group(2)
                if fence is None:
                    if not (tok[0] == "`" and "`" in rest):   # CommonMark: a backtick opener's info string holds no backtick
                        fence = (tok[0], len(tok))
                    continue
                if tok[0] == fence[0] and len(tok) >= fence[1] and not rest.strip():
                    fence = None      # the closer is at least as long as the opener, with nothing after it (review r2 DISS-003)
                continue
            if fence is not None:
                continue
            m = MD_HDR.match(l)
            if m:
                out.append((i, len(m.group(1))))
            continue
        if kind == "python":
            m = PY_HDR.match(l)
        else:
            m = BASH_HDR[0].match(l) or BASH_HDR[1].match(l)
            if m is None and kind == "bats":
                m = BATS_HDR.match(l)
        if m:
            out.append((i, len(m.group(1).expandtabs(8))))
    return out


CLOSE_ONE = re.compile(r'\{.*\}\s*(?:#.*)?$')


def close_line(kind, lines, h, lv, end):
    """end-of-definition detection: bash/bats — the first line after the header that is `}` at the
    header's indentation (a one-line `f() { …; }` ends on its header); python — the line before the first
    later non-blank, non-comment line indented at most as far as the def; markdown — none (next heading)"""
    if kind in ("bash", "bats"):
        if CLOSE_ONE.search(lines[h - 1]) and "{" in lines[h - 1]:
            return h
        for L in range(h + 1, end + 1):
            t = lines[L - 1].expandtabs(8)     # the same width headers() measured (review r1 DISS-C-006)
            if t.strip().startswith("}") and len(t) - len(t.lstrip()) == lv:
                return L
        return end
    if kind == "python":
        # skip a multi-line signature: the header ends on the line that closes its parentheses and ends with
        # a colon (review r1 DISS-C-005); the indentation rule then binds the body
        j, depth = h, 0
        while j <= end:
            t = re.sub(r"#.*$", "", lines[j - 1])
            depth += t.count("(") - t.count(")")
            rest = t[t.rfind(")") + 1:] if depth <= 0 and ")" in t else ""
            if depth <= 0 and ":" in rest:
                break                 # the colon after the closing parenthesis ends the header (a one-liner
            j += 1                    # `def f(): return 1` ends on its own line; review r2 DISS-001)
        if j > end:
            j = h                     # no terminating colon found (a `(` or `#` inside a string default): one-line header
        last = j
        for L in range(j + 1, end + 1):
            t = lines[L - 1]
            if not t.strip() or t.lstrip().startswith("#"):
                continue
            if len(t.expandtabs(8)) - len(t.expandtabs(8).lstrip()) <= lv:
                return last
            last = L
        return end
    return end


_scopes = {}
HEADERS_CAP = 5000


def scope_map(rel):
    """→ (kind, [scope per line, 1-based; index 0 unused]) where a scope is the innermost
    definition's header line, "long" (a definition above SPAN_CAP lines) or None (no
    definition); kind None = no regex for the file type, or no head file"""
    if rel in _scopes:
        return _scopes[rel]
    lines = head_lines(rel)
    kind = lang(rel, lines) if lines is not None else None
    res = (kind, None)
    if kind is not None:
        n = len(lines)
        hs = headers(kind, lines)
        if len(hs) > HEADERS_CAP:
            _scopes[rel] = (None, None)   # an unterminated 4 MB file gets the ±20 fallback, not a quadratic scan (audit r1 DISS-C-002)
            return _scopes[rel]
        spans = []
        for k, (h, lv) in enumerate(hs):
            end = n
            for h2, lv2 in hs[k + 1:]:
                if lv2 <= lv:
                    end = h2 - 1
                    break
            end = min(end, close_line(kind, lines, h, lv, end))
            spans.append((h, end))
        sc = [None] * (n + 1)
        for h, end in spans:            # later (inner) headers overwrite earlier (outer) ones
            tag = "long" if end - h + 1 > SPAN_CAP else h
            for L in range(h, end + 1):
                sc[L] = tag
        res = (kind, sc)
    _scopes[rel] = res
    return res


def valid_cite(a, b, rel):
    """the cited range after the validity rules, or None: positive, ordered, inside the head
    file when it exists; wider than RANGE_CAP → its first line only"""
    if a < 1 or b < a:
        return None
    lines = head_lines(rel)
    if lines is not None and b > len(lines):
        return None
    if b - a + 1 > RANGE_CAP:
        b = a
    return a, b


def sites_of(d):
    return [s for s in (d.get("anchors") or [d.get("anchor_line")]) if isinstance(s, int) and not isinstance(s, bool)]


def hit_pm3(d):
    """the 1.2.0 rule, unchanged (no validity rules): a cited range within ±3 of any site"""
    return any(path_matches(p, d["file"]) and not (b < s - 3 or a > s + 3)
               for p, a, b in cites for s in sites_of(d))


def hit_new(d):
    """the 1.3.0 rule on valid citations: (i) ±3 of any site, or (ii) the same scope"""
    kind, sc = scope_map(d["file"])
    for p, a, b in cites:
        if not path_matches(p, d["file"]):
            continue
        v = valid_cite(a, b, d["file"])
        if v is None:
            continue
        if any(not (v[1] < s - 3 or v[0] > s + 3) for s in sites_of(d)):
            return True
        for s in sites_of(d):
            if kind is None:
                if sc is None and head_lines(d["file"]) is None:
                    continue          # no head file: no scope clause
                if not (v[1] < s - FALLBACK or v[0] > s + FALLBACK):
                    return True
                continue
            site_scope = sc[s] if 1 <= s < len(sc) else None
            if site_scope is None:
                continue              # a top-level site has no scope
            if site_scope == "long":
                if not (v[1] < s - FALLBACK or v[0] > s + FALLBACK):
                    return True
                continue
            if any(sc[L] == site_scope for L in range(v[0], v[1] + 1) if L < len(sc)):
                return True
    return False


def split(mf, rule):
    det, mis = [], []
    for d in mf.get("defects", []):
        (det if rule(d) else mis).append(d["id"])
    return det, mis


def rate(det, mf):
    n = len(mf.get("defects", []))
    return round(len(det) / n, 4) if n else None


det_v1, mis_v1 = split(man_v1, hit_pm3)
det_pm3, mis_pm3 = split(man, hit_pm3)
detected, missed = split(man, hit_new)
function_only = [x for x in detected if x not in det_pm3]

planted = len(man.get("defects", []))
recall = rate(detected, man)

# refuted share (1.2.0): distinct cited findings that touch no defect site and
# no fix region. Regions are (file, lo, hi) on head/ line numbers, widened ±3.
regions = []
for d in man.get("defects", []):
    for s in (d.get("anchors") or [d["anchor_line"]]):
        regions.append((d["file"], s - 3, s + 3))
for fr in man.get("fix_regions", []) or []:
    try:
        regions.append((fr["file"], int(fr["start"]) - 3, int(fr["end"]) + 3))
    except (KeyError, TypeError, ValueError):
        continue
findings = sorted(set(cites))
refuted = [c for c in findings
           if not any(path_matches(c[0], f) and not (c[2] < lo or c[1] > hi) for f, lo, hi in regions)]
refuted_share = round(len(refuted) / len(findings), 4) if findings else None

# trailer → severity counts (false positives on clean fixtures)
sev = None
tm = TRAILER.search(text)
if tm:
    try:
        sev = json.loads(tm.group(1)).get("counts")
    except Exception:
        sev = None
if isinstance(sev, dict):
    fp = int(sev.get("critical", 0) or 0) + int(sev.get("high", 0) or 0)
else:
    fp = len({(p, a, b) for p, a, b in cites})
false_positives = fp if planted == 0 else 0

model = effort = None
tokens = None
try:
    ex = json.load(open(executor_path))
    model, effort = ex.get("model_id"), ex.get("effort")
    u = ex.get("usage") or {}
    # every token the call consumed: uncached input, cache writes, cache
    # reads and output — the prompt surface is mostly CACHED input, so
    # input_tokens alone (30 on a real run) would hide the very thing the
    # prompt diet changes
    tokens = sum(int(u.get(k, 0) or 0) for k in
                 ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"))
except Exception:
    pass

if planted:
    ok = len(missed) == 0
    score = int(round(recall * 100))
else:
    ok = false_positives == 0
    score = 100 if ok else 0

out = {
    "pass": ok,
    "score": score,
    "details": {
        "recall": recall, "planted": planted, "detected": detected, "missed": missed,
        "recall_pm3": rate(det_pm3, man), "detected_pm3": det_pm3, "missed_pm3": mis_pm3,
        "recall_pm3_v1": rate(det_v1, man_v1), "detected_pm3_v1": det_v1, "missed_pm3_v1": mis_v1,
        "planted_v1": len(man_v1.get("defects", [])), "v1_manifest": bool(manifest_v1_path),
        "credits_function_only": function_only, "rule": "pm3_or_same_function", "head_dir_source": head_src,
        "false_positives": false_positives, "severity_counts": sev,
        "citations": len(cites), "model": model, "effort": effort, "tokens": tokens,
        "findings_cited": len(findings), "findings_refuted": len(refuted),
        "refuted_share": refuted_share,
    },
    "grader_version": "1.3.0",
}
print(json.dumps(out))
sys.exit(0 if ok else 1)
PY
