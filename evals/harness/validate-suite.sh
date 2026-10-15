#!/usr/bin/env bash
# =============================================================================
# validate-suite.sh — cycle-130 ablation task-suite validator (SDD §3.2, DEC-0424)
#
# Checks every task of the ablation-2.0 suite before it is frozen, run or graded.
#
# Usage:
#   validate-suite.sh [--root DIR] [--smoke] [--allow-partial] [--suite-file F]
#
#   --root DIR        suite root (default grimoires/loa/evals/ablation-2.0); the
#                     tasks are <root>/tasks/<id>/task.yaml
#   --smoke           also validate <root>/smoke/<id>/task.yaml (never counted)
#   --allow-partial   skip the four-by-four type count (Sprint 258 state)
#   --suite-file F    suite yaml (default evals/suites/ablation-2.0.yaml): arm ids
#                     for the leakage check, arms' task_types, suite_version
#
# Checks (each violation is one stdout line `<task-id>: <reason>`):
#   1. schema: id (= directory name), schema_version 1, type (feature-build |
#      bug-fix | refactor | review-catch), source {kind, date, fix_commit?,
#      base_commit?, bead?, origin?, churn?} (churn: {files, insertions,
#      deletions}, non-negative integers; Sprint 259), post_cutoff (bool), fixture (dir under the
#      root; null only for review-catch), criterion (agent-facing; no path, file
#      name or test name), success_criterion, test_command (array; null only for
#      review-catch), regression_command (array | null), reference_patch (hidden/…
#      | null; required for bug-fix and feature-build), grader_protected (array of
#      relative paths present in the fixture), structural_check (hidden/… | null;
#      required for refactor), bounds {max_turns{}, timeout_min{}} (phase → positive
#      int), review_catch (null, or {fixture, manifest, labels?} for review-catch,
#      both present), suite_version (= the suite file's), TASK.md present
#   2. counts: four tasks of each type under tasks/ (unless --allow-partial)
#   3. allowlist: test_command[0] and regression_command[0] in python3 | pytest |
#      bats | bash | node | npx
#   4. hidden/manifest.json (build types): {"files": [{src, dest}]}; every src
#      exists under hidden/; every dest is relative, inside the tree, no `..`
#   5. fixture path rule (build types): check_fixture_path_rule from
#      lib/sandbox-mount.sh — no .claude/, CLAUDE.md, .loa.config.yaml, grimoires/
#      or .run/ at the fixture's top level; the reference patch touches none either
#   6. leakage: TASK.md and criterion (the task-brief text is built from these)
#      and every phase prompt under evals/harness/lib/phase-prompts/ contain none
#      of: the string `hidden` (any case), a hidden test file's stem, a defect id
#      of the review manifest, a `D[0-9]{2}-` key, an arm id of the suite file
#   7. suite file: every non-absent arm's task_types are known (all | build |
#      review-catch | feature-build | bug-fix | refactor)
#
# Exit: 0 valid; 1 violations (every one listed); 2 usage / unreadable input.
# Tested by evals/tests/validate-suite.bats.
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROOT="$REPO_ROOT/grimoires/loa/evals/ablation-2.0"
SUITE_FILE="$REPO_ROOT/evals/suites/ablation-2.0.yaml"
PROMPTS_DIR="${LOA_EVAL_PHASE_PROMPTS_DIR:-$SCRIPT_DIR/lib/phase-prompts}"
SMOKE=false ALLOW_PARTIAL=false

usage() { sed -n '2,/^# =====.*$/p' "$0" | sed -n '2,45p' | sed 's/^# \{0,1\}//' >&2; exit 2; }
die() { echo "validate-suite: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --smoke) SMOKE=true; shift ;;
    --allow-partial) ALLOW_PARTIAL=true; shift ;;
    --suite-file) SUITE_FILE="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done
[[ -n "$ROOT" && -d "$ROOT" ]] || die "suite root not found: ${ROOT:-<empty>}"
ROOT="$(cd "$ROOT" && pwd)"
[[ -f "$SUITE_FILE" ]] || die "suite file not found: $SUITE_FILE"
for tool in yq jq python3; do command -v "$tool" >/dev/null 2>&1 || die "missing tool: $tool"; done
# eval.yml trust boundary: a literal in-tree path, no variable on the source line
pushd "$SCRIPT_DIR" >/dev/null
# shellcheck source=lib/sandbox-mount.sh
source ./lib/sandbox-mount.sh
popd >/dev/null

WORK="$(mktemp -d "${TMPDIR:-/tmp}/validate-suite.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
yq -o=json '.' "$SUITE_FILE" > "$WORK/suite.json" 2>/dev/null || die "suite file is not valid YAML: $SUITE_FILE"

# Collect task directories: tasks/* (counted) and smoke/* (with --smoke).
: > "$WORK/tasks.tsv"
for group in tasks smoke; do
  [[ "$group" == "smoke" && "$SMOKE" != "true" ]] && continue
  [[ -d "$ROOT/$group" ]] || continue
  for d in "$ROOT/$group"/*/; do
    [[ -d "$d" ]] || continue
    d="${d%/}"
    n="$(basename "$d")"
    j="$WORK/$group.$n.json"
    if [[ ! -f "$d/task.yaml" ]]; then
      printf '%s\t%s\t%s\t%s\n' "$group" "$n" "$d" "-" >> "$WORK/tasks.tsv"; continue
    fi
    if yq -o=json '.' "$d/task.yaml" > "$j" 2>/dev/null && jq -e 'type == "object"' "$j" >/dev/null 2>&1; then
      printf '%s\t%s\t%s\t%s\n' "$group" "$n" "$d" "$j" >> "$WORK/tasks.tsv"
    else
      printf '%s\t%s\t%s\t%s\n' "$group" "$n" "$d" "!" >> "$WORK/tasks.tsv"
    fi
  done
done

# Python does the schema, counts, allowlist, manifest, leakage and suite checks;
# it prints violations, and `FIXTURE\t<id>\t<dir>` lines for the path rule below.
python3 -I - "$WORK/tasks.tsv" "$WORK/suite.json" "$ROOT" "$REPO_ROOT" "$ALLOW_PARTIAL" "$PROMPTS_DIR" > "$WORK/out.txt" <<'PY' || { cat "$WORK/out.txt" >&2 2>/dev/null; die "validator crashed"; }
import json, os, re, sys

tasks_tsv, suite_json, root, repo, allow_partial, prompts_dir = sys.argv[1:7]
allow_partial = allow_partial == "true"
suite = json.load(open(suite_json))
out = []
def bad(tid, msg): out.append(f"{tid}: {msg}")

TYPES = ["feature-build", "bug-fix", "refactor", "review-catch"]
BUILD = {"feature-build", "bug-fix", "refactor"}
ALLOW = {"python3", "pytest", "bats", "bash", "node", "npx"}
KNOWN_TASK_TYPES = {"all", "build", "review-catch", "feature-build", "bug-fix", "refactor"}
MOUNT_OWNED = (".claude", "CLAUDE.md", ".loa.config.yaml", "grimoires", ".run")
REQUIRED = ["id", "schema_version", "type", "source", "post_cutoff", "fixture", "criterion",
            "success_criterion", "test_command", "regression_command", "reference_patch",
            "grader_protected", "structural_check", "bounds", "review_catch", "suite_version"]

arms = [a for a in (suite.get("arms") or []) if isinstance(a, dict)]
arm_ids = sorted({a.get("id") for a in arms if isinstance(a.get("id"), str)})
for a in arms:
    if a.get("absent") is True:
        continue
    tt = a.get("task_types")
    if not isinstance(tt, list) or not tt:
        bad("suite", f"arm {a.get('id')} has no task_types list")
        continue
    for t in tt:
        if t not in KNOWN_TASK_TYPES:
            bad("suite", f"arm {a.get('id')} task_types names unknown type '{t}'")
suite_version = suite.get("suite_version")

def rel_ok(p):
    return isinstance(p, str) and p and not p.startswith("/") and ".." not in p.split("/") and "\\" not in p

def is_str_list(v):
    return isinstance(v, list) and all(isinstance(x, str) and x for x in v)

def read(p):
    try:
        return open(p, encoding="utf-8", errors="replace").read()
    except OSError:
        return None

prompt_texts = []
if os.path.isdir(prompts_dir):
    for f in sorted(os.listdir(prompts_dir)):
        if f.endswith(".md"):
            prompt_texts.append((f"phase-prompts/{f}", read(os.path.join(prompts_dir, f)) or ""))

def leak_scan(tid, label, text, stems, defect_ids):
    low = text.lower()
    if "hidden" in low:
        bad(tid, f"leak: {label} contains the string 'hidden'")
    for s in stems:
        if s and re.search(r"(?<![A-Za-z0-9_])" + re.escape(s.lower()) + r"(?![A-Za-z0-9_])", low):
            bad(tid, f"leak: {label} names the grader file stem '{s}'")
    for d in defect_ids:
        if d in text:
            bad(tid, f"leak: {label} names defect id '{d}'")
    m = re.search(r"\bD[0-9]{2}-", text)
    if m:
        bad(tid, f"leak: {label} carries a defect key pattern '{m.group(0)}'")
    for a in arm_ids:
        if re.search(r"(?<![A-Za-z0-9_])" + re.escape(a) + r"(?![A-Za-z0-9_])", text):
            bad(tid, f"leak: {label} names arm id '{a}'")

counts = {t: 0 for t in TYPES}
seen = {}
for line in open(tasks_tsv, encoding="utf-8"):
    line = line.rstrip("\n")
    if not line:
        continue
    group, name, tdir, jpath = line.split("\t")
    tid = f"{group}/{name}"
    if jpath == "-":
        bad(tid, "no task.yaml"); continue
    if jpath == "!":
        bad(tid, "task.yaml is not a YAML mapping"); continue
    t = json.load(open(jpath))
    for k in REQUIRED:
        if k not in t:
            bad(tid, f"schema: missing field '{k}'")
    if t.get("id") != name:
        bad(tid, f"schema: id '{t.get('id')}' differs from the directory name")
    if not isinstance(t.get("id"), str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", t.get("id") or ""):
        bad(tid, "schema: id must match [a-z0-9][a-z0-9-]{0,63}")
    elif t["id"] in seen:
        bad(tid, f"schema: duplicate id (also {seen[t['id']]})")
    else:
        seen[t["id"]] = tid
    if t.get("schema_version") != 1:
        bad(tid, "schema: schema_version must be 1")
    ttype = t.get("type")
    if ttype not in TYPES:
        bad(tid, f"schema: type '{ttype}' not in {'|'.join(TYPES)}")
    elif group == "tasks":
        counts[ttype] += 1
    src = t.get("source")
    if not isinstance(src, dict):
        bad(tid, "schema: source must be a mapping")
    else:
        if not isinstance(src.get("kind"), str) or not src.get("kind"):
            bad(tid, "schema: source.kind must be a non-empty string")
        if not isinstance(src.get("date"), str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", src.get("date") or ""):
            bad(tid, "schema: source.date must be YYYY-MM-DD")
        for k in ("fix_commit", "base_commit"):
            if k in src and src[k] is not None and not (isinstance(src[k], str) and re.fullmatch(r"[0-9a-f]{7,40}", src[k])):
                bad(tid, f"schema: source.{k} must be a hex commit id")
        for k in src:
            if k not in ("kind", "date", "fix_commit", "base_commit", "bead", "origin", "churn"):
                bad(tid, f"schema: source.{k} is not a known key")
        if "churn" in src:
            ch = src["churn"]
            if not (isinstance(ch, dict) and set(ch) == {"files", "insertions", "deletions"}
                    and all(isinstance(v, int) and not isinstance(v, bool) and v >= 0 for v in ch.values())):
                bad(tid, "schema: source.churn must be {files, insertions, deletions} (non-negative integers)")
    if not isinstance(t.get("post_cutoff"), bool):
        bad(tid, "schema: post_cutoff must be a boolean")
    build = ttype in BUILD
    fx = t.get("fixture")
    fixture_dir = None
    if fx is None:
        if build:
            bad(tid, "schema: fixture is required for build types")
    elif not rel_ok(fx):
        bad(tid, "schema: fixture must be a relative path inside the root")
    elif not os.path.isdir(os.path.join(root, fx)):
        bad(tid, f"schema: fixture directory not found: {fx}")
    else:
        fixture_dir = os.path.join(root, fx)
        if build:
            print(f"FIXTURE\t{tid}\t{fixture_dir}")
    crit = t.get("criterion")
    if not isinstance(crit, str) or not crit.strip():
        bad(tid, "schema: criterion must be a non-empty string")
        crit = ""
    else:
        if "/" in crit or re.search(r"\b[\w.-]+\.(py|sh|bats|js|ts|mjs|json|ya?ml|md|toml|cfg|ini|txt|patch)\b", crit):
            bad(tid, "schema: criterion names a path or file (agent-facing behaviour only)")
        if re.search(r"\btest_\w+", crit):
            bad(tid, "schema: criterion names a test")
    if not isinstance(t.get("success_criterion"), str) or not t.get("success_criterion", "").strip():
        bad(tid, "schema: success_criterion must be a non-empty string")
    for key in ("test_command", "regression_command"):
        v = t.get(key)
        if v is None:
            if key == "test_command" and ttype != "review-catch":
                bad(tid, "schema: test_command is required for build types")
            continue
        if not is_str_list(v) or not v:
            bad(tid, f"schema: {key} must be a non-empty array of strings or null")
        elif v[0] not in ALLOW:
            bad(tid, f"allowlist: {key}[0] '{v[0]}' not in {'|'.join(sorted(ALLOW))}")
    for key, must in (("reference_patch", ttype in ("bug-fix", "feature-build")), ("structural_check", ttype == "refactor")):
        v = t.get(key)
        if v is None:
            if must:
                bad(tid, f"schema: {key} is required for {ttype}")
            continue
        if not rel_ok(v) or not v.startswith("hidden/"):
            bad(tid, f"schema: {key} must be a relative path under hidden/")
        elif not os.path.isfile(os.path.join(tdir, v)):
            bad(tid, f"schema: {key} not found: {v}")
    gp = t.get("grader_protected")
    if not isinstance(gp, list) or not all(isinstance(x, str) for x in gp):
        bad(tid, "schema: grader_protected must be an array of paths")
    else:
        for p in gp:
            if not rel_ok(p):
                bad(tid, f"schema: grader_protected path '{p}' is not a relative path inside the tree")
            elif fixture_dir and not os.path.exists(os.path.join(fixture_dir, p)):
                bad(tid, f"schema: grader_protected path '{p}' is not in the fixture")
    bounds = t.get("bounds")
    if not isinstance(bounds, dict) or set(bounds) != {"max_turns", "timeout_min"}:
        bad(tid, "schema: bounds must be {max_turns: {}, timeout_min: {}}")
    else:
        for k in ("max_turns", "timeout_min"):
            m = bounds[k]
            if not isinstance(m, dict) or not all(isinstance(x, int) and not isinstance(x, bool) and x > 0 for x in m.values()):
                bad(tid, f"schema: bounds.{k} must map phases to positive integers")
            elif any(p not in ("PLAN", "IMPLEMENT", "REVIEW", "FIX", "AUDIT", "BARE") for p in m):
                bad(tid, f"schema: bounds.{k} names an unknown phase")
    rc = t.get("review_catch")
    defect_ids = []
    if ttype == "review-catch":
        if not isinstance(rc, dict):
            bad(tid, "schema: review_catch {fixture, manifest} is required for review-catch")
        else:
            for k in rc:
                if k not in ("fixture", "manifest", "labels"):
                    bad(tid, f"schema: review_catch.{k} is not a known key")
            rf, rm = rc.get("fixture"), rc.get("manifest")
            if not rel_ok(rf) or not os.path.isdir(os.path.join(repo, "evals", "fixtures", rf)):
                bad(tid, f"schema: review_catch.fixture not found under evals/fixtures: {rf}")
            if not rel_ok(rm) or not os.path.isfile(os.path.join(repo, rm)):
                bad(tid, f"schema: review_catch.manifest not found: {rm}")
            else:
                try:
                    defect_ids = [d.get("id") for d in json.load(open(os.path.join(repo, rm))).get("defects", []) if d.get("id")]
                except (OSError, ValueError, AttributeError):
                    bad(tid, f"schema: review_catch.manifest is not a defect manifest: {rm}")
    elif rc is not None:
        bad(tid, "schema: review_catch must be null for build types")
    sv = t.get("suite_version")
    if not isinstance(sv, int) or isinstance(sv, bool) or sv < 1:
        bad(tid, "schema: suite_version must be a positive integer")
    elif suite_version is not None and sv != suite_version:
        bad(tid, f"schema: suite_version {sv} differs from the suite file's {suite_version}")

    stems = []
    hm = os.path.join(tdir, "hidden", "manifest.json")
    if build:
        if not os.path.isfile(hm):
            bad(tid, "hidden: hidden/manifest.json is missing")
        else:
            try:
                files = json.load(open(hm)).get("files")
            except (OSError, ValueError, AttributeError):
                files = None
            if not isinstance(files, list) or not files:
                bad(tid, "hidden: manifest.json must be {\"files\": [{src, dest}, ...]}")
            else:
                for e in files:
                    s_, d_ = (e or {}).get("src"), (e or {}).get("dest")
                    if not rel_ok(s_) or not os.path.isfile(os.path.join(tdir, "hidden", s_)):
                        bad(tid, f"hidden: manifest src not found under hidden/: {s_}")
                    if not rel_ok(d_):
                        bad(tid, f"hidden: manifest dest must be a relative path inside the tree: {d_}")
                    elif d_.split("/")[0] in MOUNT_OWNED:
                        bad(tid, f"hidden: manifest dest lands on a mount-owned path: {d_}")
                    if isinstance(s_, str) and s_:
                        stems.append(os.path.splitext(os.path.basename(s_))[0])
        sc = t.get("structural_check")
        if isinstance(sc, str) and sc:
            stems.append(os.path.splitext(os.path.basename(sc))[0])
        rp = t.get("reference_patch")
        if isinstance(rp, str) and os.path.isfile(os.path.join(tdir, rp)):
            for pl in (read(os.path.join(tdir, rp)) or "").splitlines():
                m = re.match(r"^(?:\+\+\+|---) (?:[ab]/)?(\S+)", pl)
                if m and m.group(1) != "/dev/null" and m.group(1).split("/")[0] in MOUNT_OWNED:
                    bad(tid, f"fixture path rule: reference patch touches a mount-owned path: {m.group(1)}")
    task_md = read(os.path.join(tdir, "TASK.md"))
    if task_md is None:
        bad(tid, "schema: TASK.md is missing")
        task_md = ""
    leak_scan(tid, "TASK.md", task_md, stems, defect_ids)
    leak_scan(tid, "criterion", crit, stems, defect_ids)
    for label, text in prompt_texts:
        leak_scan(tid, label, text, stems, defect_ids)

if not allow_partial:
    for ty in TYPES:
        if counts[ty] != 4:
            bad("suite", f"counts: {counts[ty]} {ty} task(s) under tasks/, want 4 (pass --allow-partial before the freeze)")

for o in out:
    print(o)
PY

violations=0
: > "$WORK/report.txt"
while IFS= read -r line; do
  if [[ "$line" == FIXTURE$'\t'* ]]; then
    IFS=$'\t' read -r _ tid fdir <<<"$line"
    if ! check_fixture_path_rule "$fdir" 2>"$WORK/rule.err"; then
      printf '%s: fixture path rule: %s\n' "$tid" "$(tr '\n' ' ' < "$WORK/rule.err" | sed 's/ *$//')" >> "$WORK/report.txt"
    fi
  else
    printf '%s\n' "$line" >> "$WORK/report.txt"
  fi
done < "$WORK/out.txt"
violations="$(grep -c . "$WORK/report.txt" || true)"
ntasks="$(grep -c . "$WORK/tasks.tsv" || true)"
if [[ "$violations" -gt 0 ]]; then
  cat "$WORK/report.txt"
  echo "validate-suite: $violations violation(s) over $ntasks task(s) in $ROOT" >&2
  exit 1
fi
echo "validate-suite: OK — $ntasks task(s) valid in $ROOT$([[ "$ALLOW_PARTIAL" == "true" ]] && echo " (partial: type counts not enforced)")"
exit 0
