#!/usr/bin/env bash
# =============================================================================
# build-review-corpus.sh — build the 10-PR review-recall corpus from this
# repository's own history (cycle-124 Sprint 3, PRD FR-9 / SDD §3.6)
#
# Every planted defect is a real shipped fix, inverted: for a `defect` row the
# PR under review turns the FIXED code (base/) back into the BUGGY code
# (head/ = the fix commit's parent), so each defect has a real failing test in
# history and a reviewer must reason about the code, not read a changelog.
# Comment-only lines the fix ADDED (the "why this was wrong" prose) are removed
# from base/ before diffing, so the inverted diff removes code, never a
# confession. `clean` rows are forward fix commits (base = parent, head = fix,
# tests included): a PR with nothing planted, so false positives are measurable.
#
# Inputs (committed):
#   review-prs/corpus.tsv   fixture  kind  commit  file  defect_id  severity  category  must_match
#   review-prs/prs.tsv      fixture  title  description
# Outputs (committed, frozen by SHA256SUMS):
#   review-prs/pr-NN/{PR.md,head.diff,base/…,head/…,fixture.yaml,
#                     REVIEW-INSTRUCTIONS.md,AUDIT-INSTRUCTIONS.md}
#   review-prs/manifests/pr-NN.json   HIDDEN — never copied into a sandbox
#   review-prs/SHA256SUMS             the freeze; compare.sh pins its hash
#
# `must_match` is a literal substring that must occur on exactly ONE line of
# the head/ file: that line is the defect's anchor (the grader accepts ±3).
#
# Usage:
#   build-review-corpus.sh            # (re)build everything + SHA256SUMS
#   build-review-corpus.sh --verify   # sha256sum -c against the committed freeze
# Exit: 0 ok, 1 verify failed / spec error, 2 usage
# =============================================================================
set -euo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
CORPUS="$HERE/review-prs"
SPEC="$CORPUS/corpus.tsv"
PRS="$CORPUS/prs.tsv"

if [[ "${1:-}" == "--verify" ]]; then
  [[ -f "$CORPUS/SHA256SUMS" ]] || { echo "ERROR: $CORPUS/SHA256SUMS missing" >&2; exit 1; }
  ( cd "$CORPUS" && sha256sum -c --quiet SHA256SUMS ) && echo "corpus OK: $(wc -l < "$CORPUS/SHA256SUMS") files match SHA256SUMS"
  exit $?
fi
[[ $# -eq 0 ]] || { echo "usage: $0 [--verify]" >&2; exit 2; }
[[ -f "$SPEC" && -f "$PRS" ]] || { echo "ERROR: corpus.tsv / prs.tsv missing under $CORPUS" >&2; exit 1; }

python3 - "$REPO_ROOT" "$CORPUS" "$SPEC" "$PRS" <<'PY'
import csv, json, os, re, shutil, subprocess, sys
repo, corpus, spec, prs = sys.argv[1:5]

def git(*args, text=True):
    return subprocess.run(["git", "-C", repo, *args], check=True, capture_output=True, text=text).stdout

def show(rev, path):
    try:
        return subprocess.run(["git", "-C", repo, "show", f"{rev}:{path}"], check=True, capture_output=True, text=True).stdout
    except subprocess.CalledProcessError:
        return None

COMMENT = {
    ".sh": re.compile(r"^\s*#"), ".bash": re.compile(r"^\s*#"), ".py": re.compile(r"^\s*#"),
    ".yaml": re.compile(r"^\s*#"), ".yml": re.compile(r"^\s*#"),
    ".ts": re.compile(r"^\s*(//|/\*|\*)"), ".js": re.compile(r"^\s*(//|/\*|\*)"),
}

def added_comment_lines(commit, path):
    """Line numbers (1-based, in the fixed file) of comment-only lines the fix added."""
    ext = os.path.splitext(path)[1]
    rx = COMMENT.get(ext)
    if rx is None:
        return set()
    diff = git("diff", "-U0", f"{commit}^", commit, "--", path)
    out, new_no = set(), None
    for line in diff.splitlines():
        m = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", line)
        if m:
            new_no = int(m.group(1)); continue
        if new_no is None or line.startswith("+++") or line.startswith("---"):
            continue
        if line.startswith("+"):
            if rx.match(line[1:]):
                out.add(new_no)
            new_no += 1
        # '-' lines do not advance the new-file counter
    return out

rows = list(csv.DictReader(open(spec, encoding="utf-8"), delimiter="\t", quoting=csv.QUOTE_NONE))
prmeta = {r["fixture"]: r for r in csv.DictReader(open(prs, encoding="utf-8"), delimiter="\t", quoting=csv.QUOTE_NONE)}
fixtures = {}
for r in rows:
    fixtures.setdefault(r["fixture"], []).append(r)

REVIEW_INSTR = """# Review instructions

This workspace holds one pull request against the Loa framework repository, frozen for evaluation.

- `PR.md` — the PR title and description
- `head.diff` — the complete change (unified diff, base → head)
- `base/` — every touched file before the change
- `head/` — every touched file after the change

Review the change as the senior technical reviewer for this repository. There is no sprint plan, beads database, implementation report or `grimoires/loa/a2a/` directory here — the PR files above are the entire input; skip any pre-flight step that needs them and do not ask questions.

Write your review to `review.md` in this directory using the Write tool. Cite every finding as `head/<path>:<line>` with line numbers taken from the `head/` files. Follow your reviewer skill's output format and end the file with its machine-readable verdict trailer.
"""
AUDIT_INSTR = REVIEW_INSTR.replace("# Review instructions", "# Audit instructions") \
    .replace("Review the change as the senior technical reviewer", "Audit the change as the security auditor") \
    .replace("Write your review to `review.md`", "Write your audit to `audit.md`") \
    .replace("your reviewer skill's output format", "your auditor skill's output format")

manifests_dir = os.path.join(corpus, "manifests")
os.makedirs(manifests_dir, exist_ok=True)
errors = []
built = []
for fx, frows in fixtures.items():
    fdir = os.path.join(corpus, fx)
    for sub in ("base", "head"):
        shutil.rmtree(os.path.join(fdir, sub), ignore_errors=True)
    os.makedirs(fdir, exist_ok=True)
    defects, files = [], []
    seen_files = set()
    for r in frows:
        kind, commit, path = r["kind"], r["commit"], r["file"]
        if path in seen_files:
            errors.append(f"{fx}: {path} listed twice (two commits on one file cannot compose)"); continue
        seen_files.add(path)
        if kind == "defect":
            fixed, buggy = show(commit, path), show(f"{commit}^", path)
            if fixed is None or buggy is None:
                errors.append(f"{fx}: {commit}:{path} or its parent is missing"); continue
            drop = added_comment_lines(commit, path)
            base_lines = [l for i, l in enumerate(fixed.splitlines(keepends=True), 1) if i not in drop]
            base_text, head_text = "".join(base_lines), buggy
        elif kind == "clean":
            base_text, head_text = show(f"{commit}^", path), show(commit, path)
            if head_text is None:
                errors.append(f"{fx}: {commit}:{path} missing"); continue
        else:
            errors.append(f"{fx}: unknown kind {kind}"); continue
        if base_text is not None:
            bp = os.path.join(fdir, "base", path); os.makedirs(os.path.dirname(bp), exist_ok=True)
            open(bp, "w", encoding="utf-8").write(base_text)
        hp = os.path.join(fdir, "head", path); os.makedirs(os.path.dirname(hp), exist_ok=True)
        open(hp, "w", encoding="utf-8").write(head_text)
        files.append((path, base_text is not None))
        if kind == "defect":
            needle = r["must_match"]
            hits = [i for i, l in enumerate(head_text.splitlines(), 1) if needle in l]
            if len(hits) != 1:
                errors.append(f"{fx}/{r['defect_id']}: must_match {needle!r} matched {len(hits)} lines in head/{path} (need exactly 1)"); continue
            defects.append({
                "id": r["defect_id"], "file": path, "anchor_line": hits[0], "must_match": needle,
                "severity": r["severity"], "category": r["category"], "source_commit": commit, "synthetic": False,
            })
    # head.diff — one unified diff per file, a/<path> b/<path>
    parts = []
    for path, has_base in files:
        bp = os.path.join(fdir, "base", path) if has_base else "/dev/null"
        hp = os.path.join(fdir, "head", path)
        p = subprocess.run(["diff", "-u", "--label", f"a/{path}", "--label", f"b/{path}", bp, hp], capture_output=True, text=True)
        if p.returncode not in (0, 1):
            errors.append(f"{fx}: diff failed for {path}: {p.stderr.strip()}"); continue
        if p.stdout:
            parts.append(f"diff --git a/{path} b/{path}\n" + p.stdout)
    open(os.path.join(fdir, "head.diff"), "w", encoding="utf-8").write("".join(parts))
    meta = prmeta.get(fx, {"title": fx, "description": ""})
    open(os.path.join(fdir, "PR.md"), "w", encoding="utf-8").write(f"# {meta['title']}\n\n{meta['description']}\n")
    open(os.path.join(fdir, "REVIEW-INSTRUCTIONS.md"), "w", encoding="utf-8").write(REVIEW_INSTR)
    open(os.path.join(fdir, "AUDIT-INSTRUCTIONS.md"), "w", encoding="utf-8").write(AUDIT_INSTR)
    open(os.path.join(fdir, "fixture.yaml"), "w", encoding="utf-8").write(
        f'name: {fx}\nversion: "1.0.0"\nlanguage: mixed\nruntime: none\ndependency_strategy: none\n'
        f'description: "review-recall corpus PR {fx} (cycle-124 FR-9); planted defects live in the hidden manifest"\n'
        f'difficulty: intermediate\ndomain: framework\ndeprecated: false\n')
    json.dump({"fixture": fx, "defects": defects}, open(os.path.join(manifests_dir, f"{fx}.json"), "w"), indent=2)
    built.append((fx, len(files), len(defects)))

if errors:
    print("\n".join("ERROR: " + e for e in errors), file=sys.stderr)
    sys.exit(1)

# freeze
entries = []
for root, _dirs, fnames in os.walk(corpus):
    for f in fnames:
        rel = os.path.relpath(os.path.join(root, f), corpus)
        if rel in ("SHA256SUMS",):
            continue
        entries.append(rel)
import hashlib
lines = []
for rel in sorted(entries):
    h = hashlib.sha256(open(os.path.join(corpus, rel), "rb").read()).hexdigest()
    lines.append(f"{h}  {rel}")
open(os.path.join(corpus, "SHA256SUMS"), "w").write("\n".join(lines) + "\n")
total = sum(d for _, _, d in built)
for fx, nf, nd in built:
    print(f"{fx}: {nf} file(s), {nd} planted defect(s)")
print(f"built {len(built)} fixtures, {total} planted defects, {len(lines)} files frozen in SHA256SUMS")
PY
