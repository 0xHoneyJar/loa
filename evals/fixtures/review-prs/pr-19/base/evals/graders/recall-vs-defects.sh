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
# Clean fixtures (0 planted defects) measure FALSE POSITIVES: the LOA-VERDICT
# trailer's critical+high counts; without a trailer, every file:line citation
# counts as one.
#
# Output: {"pass", "score", "details":{recall, planted, detected[], missed[],
#          false_positives, severity_counts, model, effort, tokens}, "grader_version"}
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

err() { printf '{"pass":false,"score":0,"details":{"error":%s},"grader_version":"1.1.2"}\n' "$(jq -Rn --arg m "$1" '$m')"; exit 2; }

[[ -n "$workspace" && -d "$workspace" ]] || err "invalid workspace"
[[ -n "$fixture" && "$fixture" =~ ^[A-Za-z0-9._-]+$ ]] || err "invalid fixture id"
manifest="$MANIFEST_DIR/$fixture.json"
[[ -f "$manifest" ]] || err "manifest not found: $manifest"
case "$review_name" in */*|..*) err "review file must be a bare name" ;; esac

review="$workspace/$review_name"
executor="$workspace/.eval/executor.json"

if [[ ! -f "$review" ]]; then
  printf '{"pass":false,"score":0,"details":{"error":"review file not found: %s","planted":%s,"detected":[],"recall":0},"grader_version":"1.1.2"}\n' \
    "$review_name" "$(jq '.defects | length' "$manifest")"
  exit 1
fi

python3 -I - "$manifest" "$review" "$executor" <<'PY'
import json, re, sys
manifest_path, review_path, executor_path = sys.argv[1:4]
man = json.load(open(manifest_path))
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

detected, missed = [], []
for d in man.get("defects", []):
    sites = d.get("anchors") or [d["anchor_line"]]
    hit = any(path_matches(p, d["file"]) and not (b < s - 3 or a > s + 3)
              for p, a, b in cites for s in sites)
    (detected if hit else missed).append(d["id"])

planted = len(man.get("defects", []))
recall = round(len(detected) / planted, 4) if planted else None

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
        "false_positives": false_positives, "severity_counts": sev,
        "citations": len(cites), "model": model, "effort": effort, "tokens": tokens,
    },
    "grader_version": "1.1.2",
}
print(json.dumps(out))
sys.exit(0 if ok else 1)
PY
