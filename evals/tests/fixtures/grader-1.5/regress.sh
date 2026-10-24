#!/usr/bin/env bash
# =============================================================================
# regress.sh — grader 1.5.0's full-suite regression run (cycle-133 Sprint 274 Task 3.2; SDD C-11; sprint.md Task 3.2:
# "every 1.4 fixture grades identically except the judge cases"). Runs evals/tests/ablation-grade.bats with every grade
# call graded by both the 1.4.0 grader of a pin (default de366cc63, the Sprint 273 head) and the working tree's grader
# (../grader-1.4/regress-wrap.sh), then compares each pair of grade.json files with grader_version dropped.
#
# Usage: evals/tests/fixtures/grader-1.5/regress.sh [--pin SHA] [--work DIR] [--filter REGEX]
#   --pin SHA      the commit whose evals/harness/ablation-grade.sh is the reference grader (default de366cc63)
#   --work DIR     scratch directory (default a mktemp -d, kept and printed)
#   --filter RE    passed to bats -f (default: every test)
# Output: one line per differing pair and a summary; pairs.tsv in the work directory (test, call, verdict, keys).
# Under the wrapper AG-24's wall-clock bound fails by construction (the older grader runs the same hung command
# first); its pairs are still compared.
# Expected differences: only tests whose name starts with AG-c133-J (the judge cases: every call passes --judge-verdicts,
# which the 1.4.0 grader refuses, or reads the judge fields). Exit 0 when every other pair is identical (and the exit
# statuses agree); 1 on any other difference; 2 on usage or a missing tool.
# =============================================================================
set -euo pipefail
export LC_ALL=C
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
PIN=de366cc63 WORK="" FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pin) PIN="${2:?}"; shift 2 ;;
    --work) WORK="${2:?}"; shift 2 ;;
    --filter) FILTER="${2:?}"; shift 2 ;;
    -h|--help) sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "regress.sh: unknown option $1" >&2; exit 2 ;;
  esac
done
git -C "$ROOT" cat-file -e "$PIN^{commit}" 2>/dev/null || { echo "regress.sh: pin $PIN is not in this clone (fetch it)" >&2; exit 2; }
[[ -n "$WORK" ]] || WORK="$(mktemp -d "${TMPDIR:-/tmp}/grader-regress-1.5.XXXXXX")"
mkdir -p "$WORK/old" "$WORK/pairs"
git -C "$ROOT" archive "$PIN" evals/harness/ablation-grade.sh evals/harness/freeze.sh evals/harness/validate-suite.sh \
  evals/harness/took-effect.sh evals/harness/lib evals/graders/recall-vs-defects.sh | tar -x -C "$WORK/old"
# both graders read the same inputs: a grader looks a task's key up under its own repository root (the review
# corpus) and its freeze check reads the suite file beside it (evals/suites)
mkdir -p "$WORK/old/evals/fixtures" && cp -a "$ROOT/evals/fixtures/review-prs" "$WORK/old/evals/fixtures/"
cp -a "$ROOT/evals/suites" "$WORK/old/evals/"
if [[ -n "${BATS_ROOT:-}" && -x "$BATS_ROOT/bin/bats" ]]; then BATS=("$BATS_ROOT/bin/bats")
elif command -v bats >/dev/null 2>&1; then BATS=(bats)
else BATS=(npx --no-install bats); fi
args=(); [[ -n "$FILTER" ]] && args=(-f "$FILTER")
rc=0
AG_REGRESS_OLD="$WORK/old/evals/harness/ablation-grade.sh" AG_REGRESS_DIR="$WORK/pairs" \
  "${BATS[@]}" ${args[@]+"${args[@]}"} "$ROOT/evals/tests/ablation-grade.bats" > "$WORK/bats.tap" 2>&1 || rc=$?
echo "bats exit $rc: $(grep -c '^ok' "$WORK/bats.tap" || true) ok, $(grep -c '^not ok' "$WORK/bats.tap" || true) not ok (TAP: $WORK/bats.tap)"
python3 -I - "$WORK" <<'PY'
import json, os, re, sys
work = sys.argv[1]; pairs = os.path.join(work, "pairs")
names = {}
for line in open(os.path.join(pairs, "tests.tsv"), encoding="utf-8"):
    num, _, desc = line.rstrip("\n").partition("\t")
    names[num] = desc
rows, bad = [], 0
ids = sorted({f.rsplit(".", 2)[0] for f in os.listdir(pairs) if f.endswith(".old.rc")},
             key=lambda s: tuple(int(x) for x in s.split("-")))
def load(p):
    try:
        return json.load(open(p, encoding="utf-8"))
    except (OSError, ValueError):
        return None
for i in ids:
    t = i.split("-")[0]; desc = names.get(t, "?"); expected = desc.startswith("AG-c133-J")
    orc = open(os.path.join(pairs, i + ".old.rc")).read().strip()
    nrc = (open(os.path.join(pairs, i + ".new.rc")).read().strip() if os.path.exists(os.path.join(pairs, i + ".new.rc")) else "?")
    o, n = load(os.path.join(pairs, i + ".old.json")), load(os.path.join(pairs, i + ".new.json"))
    if orc != nrc:
        verdict, keys = "exit_differs", f"{orc}!={nrc}"
    elif orc != "0" or o is None or n is None:
        verdict, keys = "both_refused", f"rc {orc}"
    else:
        o.pop("grader_version", None); n.pop("grader_version", None)
        diff = sorted(k for k in set(o) | set(n) if o.get(k, "<absent>") != n.get(k, "<absent>"))
        verdict = "identical" if not diff else "differs"
        keys = ",".join(diff)
    ok = verdict in ("identical", "both_refused") or expected
    if not ok:
        bad += 1
    if verdict not in ("identical", "both_refused"):
        print(f"{'expected' if ok else 'UNEXPECTED'}\t{i}\t{verdict}\t{keys}\t{desc[:90]}")
    rows.append((i, verdict, keys, "ok" if ok else "unexpected", desc))
with open(os.path.join(work, "pairs.tsv"), "w", encoding="utf-8") as f:
    f.write("call\tverdict\tkeys\tcheck\ttest\n")
    for r in rows:
        f.write("\t".join(r) + "\n")
from collections import Counter
c = Counter(r[1] for r in rows)
tests = len({r[0].split("-")[0] for r in rows})
print(f"pairs {len(rows)} over {tests} tests: " + ", ".join(f"{k} {v}" for k, v in sorted(c.items()))
      + f"; unexpected {bad}")
sys.exit(1 if bad else 0)
PY
