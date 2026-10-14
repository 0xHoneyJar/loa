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
# manifest anchor.
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

err() { printf '{"pass":false,"score":0,"details":{"error":%s},"grader_version":"1.0.0"}\n' "$(jq -Rn --arg m "$1" '$m')"; exit 2; }

[[ -n "$workspace" && -d "$workspace" ]] || err "invalid workspace"
[[ -n "$fixture" && "$fixture" =~ ^[A-Za-z0-9._-]+$ ]] || err "invalid fixture id"
manifest="$MANIFEST_DIR/$fixture.json"
[[ -f "$manifest" ]] || err "manifest not found: $manifest"
case "$review_name" in */*|..*) err "review file must be a bare name" ;; esac

review="$workspace/$review_name"
executor="$workspace/.eval/executor.json"

if [[ ! -f "$review" ]]; then
  printf '{"pass":false,"score":0,"details":{"error":"review file not found: %s","planted":%s,"detected":[],"recall":0},"grader_version":"1.0.0"}\n' \
    "$review_name" "$(jq '.defects | length' "$manifest")"
  exit 1
fi

python3 - "$manifest" "$review" "$executor" <<'PY'
import json, re, sys
manifest_path, review_path, executor_path = sys.argv[1:4]
man = json.load(open(manifest_path))
text = open(review_path, encoding="utf-8", errors="replace").read()

# path:line[-line] citations. Path = something with a file extension; the
# optional trailing range keeps `file.py:10-14` in one token.
CITE = re.compile(r'([A-Za-z0-9_./+()-]+\.[A-Za-z0-9]{1,6}):(\d{1,6})(?:\s*[-–]\s*(\d{1,6}))?')
cites = []
for m in CITE.finditer(text):
    p, a, b = m.group(1), int(m.group(2)), m.group(3)
    b = int(b) if b else a
    if b < a:
        a, b = b, a
    if p.startswith("./"):
        p = p[2:]
    cites.append((p, a, b))

def path_matches(cited, defect_file):
    cited = cited.split("head/", 1)[1] if cited.startswith("head/") else cited
    cited = cited.split("base/", 1)[1] if cited.startswith("base/") else cited
    if cited == defect_file or defect_file.endswith("/" + cited):
        return True
    return cited == defect_file.rsplit("/", 1)[-1]

detected, missed = [], []
for d in man.get("defects", []):
    lo, hi = d["anchor_line"] - 3, d["anchor_line"] + 3
    hit = any(path_matches(p, d["file"]) and not (b < lo or a > hi) for p, a, b in cites)
    (detected if hit else missed).append(d["id"])

planted = len(man.get("defects", []))
recall = round(len(detected) / planted, 4) if planted else None

# trailer → severity counts (false positives on clean fixtures)
sev = None
tm = re.search(r'<!-- LOA-VERDICT (\{.*\}) -->', text)
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
    "grader_version": "1.0.0",
}
print(json.dumps(out))
sys.exit(0 if ok else 1)
PY
