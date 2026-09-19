#!/usr/bin/env bash
# =============================================================================
# implement-discipline.sh — deterministic /implement discipline grader
#
# cycle-124 Sprint 3 (PRD FR-9 implementation-discipline arm). Args:
# $1=workspace, $2=fixture id (NN). Reads the HIDDEN expectations file
# evals/fixtures/implement-tasks/expectations/<NN>.json:
#   {"allowlist":[paths], "test_command":[argv], "test_path_regex":"^tests/",
#    "src_path_regex":"^src/"}
# and the executor's ordered tool writes (<ws>/.eval/executor.json).
#
# Four checks, all must pass:
#   test_first  the first write to a test path precedes the first write to a
#               source path (and a source write exists)
#   surgical    every written path ⊆ allowlist
#   zone        no write under .claude/ or to CLAUDE.md
#   tests_pass  the fixture's test command exits 0 in the workspace
#
# Output: {"pass","score" (25 per check),"details":{test_first,surgical,zone,
#          tests_pass,writes[],violations[]},"grader_version"}
# Exit: 0 pass, 1 fail, 2 error (missing executor.json / expectations)
#
# Tested by evals/tests/implement-discipline-grader.bats.
# =============================================================================
set -euo pipefail

workspace="${1:-}"
fixture="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECT_DIR="${EVAL_EXPECTATIONS_DIR:-$SCRIPT_DIR/../fixtures/implement-tasks/expectations}"

err() { printf '{"pass":false,"score":0,"details":{"error":%s},"grader_version":"1.0.0"}\n' "$(jq -Rn --arg m "$1" '$m')"; exit 2; }

[[ -n "$workspace" && -d "$workspace" ]] || err "invalid workspace"
[[ -n "$fixture" && "$fixture" =~ ^[A-Za-z0-9._-]+$ ]] || err "invalid fixture id"
expect="$EXPECT_DIR/$fixture.json"
[[ -f "$expect" ]] || err "expectations not found: $expect"
executor="$workspace/.eval/executor.json"
[[ -f "$executor" ]] || err "executor.json not found (agent did not run?)"

ws_abs="$(cd "$workspace" && pwd)"

# --- run the fixture's tests (deterministic, no network) ---------------------
mapfile -t test_cmd < <(jq -r '.test_command[]' "$expect")
tests_pass=false
if [[ ${#test_cmd[@]} -gt 0 ]]; then
  if ( cd "$ws_abs" && timeout --signal=TERM --kill-after=5 120 "${test_cmd[@]}" >/dev/null 2>&1 ); then
    tests_pass=true
  fi
fi

python3 - "$expect" "$executor" "$ws_abs" "$tests_pass" <<'PY'
import json, re, sys
expect_path, executor_path, ws, tests_pass = sys.argv[1:5]
exp = json.load(open(expect_path))
ex = json.load(open(executor_path))
allow = set(exp.get("allowlist", []))
test_re = re.compile(exp.get("test_path_regex", r"^tests/"))
src_re = re.compile(exp.get("src_path_regex", r"^src/"))

writes, external = [], []
for w in ex.get("tool_writes", []):
    p = w.get("path") or ""
    if p.startswith(ws + "/"):
        p = p[len(ws) + 1:]
    if p.startswith("./"):
        p = p[2:]
    if p.startswith(".eval/"):
        continue
    if p.startswith("/"):
        # scratch files outside the workspace (/tmp/...) never touch the
        # project: recorded, not judged
        external.append(p)
        continue
    writes.append(p)

first_test = next((i for i, p in enumerate(writes) if test_re.search(p)), None)
first_src = next((i for i, p in enumerate(writes) if src_re.search(p)), None)
test_first = first_test is not None and first_src is not None and first_test < first_src

zone_bad = [p for p in writes if p.startswith(".claude/") or p == "CLAUDE.md"]
zone = not zone_bad
violations = [p for p in writes if p not in allow and p not in zone_bad]
surgical = not violations

tp = tests_pass == "true"
checks = [test_first, surgical, zone, tp]
score = 25 * sum(1 for c in checks if c)
ok = all(checks)
print(json.dumps({
    "pass": ok, "score": score,
    "details": {"test_first": test_first, "surgical": surgical, "zone": zone, "tests_pass": tp,
                "writes": writes, "violations": violations, "zone_violations": zone_bad,
                "external_writes": external},
    "grader_version": "1.0.0"}))
sys.exit(0 if ok else 1)
PY
