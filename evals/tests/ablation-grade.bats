#!/usr/bin/env bats
# =============================================================================
# evals/tests/ablation-grade.bats — cycle-130 Sprint 259 Task 2.6
# (SDD §3.6, §5.7, D-4.7, D-4.8; sprint.md AC-2.3, AC-2.5, AC-2.6; PRD AC-6.1/6.2/6.4;
# DEC-0401, DEC-0413, DEC-0414, DEC-0420, DEC-0491, DEC-0493)
#
# evals/harness/ablation-grade.sh grades run directories shaped like pipeline-run.sh's
# (sandbox/ with its own .git, snapshots/<LABEL>.bundle + index.json, transcripts/,
# eval/, meta/). docker is fixtures/docker-stub.sh through a wrapper that sets
# DOCKER_STUB_PATH to $T/bin, where `python3` drops the image-only -I/-s flags (the
# host's pytest lives in the user site) and `bats` is the operator's bats-core. The
# tasks are built in a temporary suite root; the smoke self-checks run on a frozen copy
# of grimoires/loa/evals/ablation-2.0/smoke/.
# =============================================================================

# The bats that grades bats-tested tasks: LOA_EVAL_BATS_BIN, else the first bats on PATH, else the
# operator's bats-core checkout (Bridgebuilder PR #1283 F-HIGH: a hard-coded dotfiles path dangled on CI).
# Inside a bats run, PATH carries bats-core's libexec; a grading bats must be a real entry point, so
# the first PATH candidate outside a libexec/ directory wins.
find_bats() {
  local c
  [[ -n "${LOA_EVAL_BATS_BIN:-}" ]] && { printf '%s' "$LOA_EVAL_BATS_BIN"; return; }
  for c in $(type -aP bats 2>/dev/null); do case "$c" in */libexec/*) ;; *) printf '%s' "$c"; return ;; esac; done
  printf '%s' "$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"
}
BATS_BIN="$(find_bats)"
# The python3 that runs pytest for the grader: the one on PATH (actions/setup-python on CI, the
# system interpreter here), never a hard-coded /usr/bin/python3.
PY3_BIN="$(command -v python3)"

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  GRADER="$REPO_ROOT/evals/harness/ablation-grade.sh"
  SMOKE="$REPO_ROOT/grimoires/loa/evals/ablation-2.0/smoke"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/ag.XXXXXX")"
  S="$T/suite"
  export LOA_EVAL_ALLOW_HOST_GRADING=1   # grader 1.2.0 (LOW-A1): host mode is opt-in; AG-28 unsets it
  make_bin
  make_bf_py
  make_bf_sh
  make_rf_py
  make_rc
}

teardown() {
  chmod -R u+rwx "$T" 2>/dev/null || true
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

make_bin() {
  local ub
  ub="$(python3 -c 'import site; print(site.getuserbase())')"
  mkdir -p "$T/bin" "$T/dlog"
  cat > "$T/bin/python3" <<EOF
#!/usr/bin/env bash
# the image's python3 stand-in: the image has pytest on its own path; the host's is in the user site
while [[ \$# -gt 0 ]]; do case "\$1" in -I|-s|-P) shift ;; *) break ;; esac; done
exec env PYTHONUSERBASE="$ub" "$PY3_BIN" "\$@"
EOF
  if [[ -x "$BATS_BIN" ]]; then ln -s "$BATS_BIN" "$T/bin/bats"; fi   # absent → the bats-graded cases skip in their own setup
  cat > "$T/docker" <<EOF
#!/usr/bin/env bash
export DOCKER_STUB_LOG="$T/dlog" DOCKER_STUB_PATH="$T/bin:/usr/bin:/bin"
[[ -f "$T/docker.env" ]] && { set -a; . "$T/docker.env"; set +a; }
exec "$TESTS_DIR/fixtures/docker-stub.sh" "\$@"
EOF
  chmod +x "$T/bin/python3" "$T/docker"
}

# bf-py: the smoke slug task plus pytest.ini, a fixture test and a regression command
make_bf_py() {
  local d="$S/tasks/bf-py"
  mkdir -p "$d/fixture" "$d/hidden/tests"
  cp -a "$SMOKE/smoke-build-01/fixture/." "$d/fixture/"
  printf '[pytest]\n' > "$d/fixture/pytest.ini"
  printf 'from textkit.slug import slugify\n\n\ndef test_existing_one():\n    assert slugify("A") == "a"\n\n\ndef test_existing_two():\n    assert slugify("a b") == "a-b"\n' \
    > "$d/fixture/tests/test_existing.py"
  cp "$SMOKE/smoke-build-01/hidden/tests/test_slug.py" "$d/hidden/tests/"
  cp "$SMOKE/smoke-build-01/hidden/reference.patch" "$d/hidden/"
  echo '{"files": [{"src": "tests/test_slug.py", "dest": "tests/test_slug.py"}]}' > "$d/hidden/manifest.json"
  printf 'Fix the slug helper.\n' > "$d/TASK.md"
  cat > "$d/task.yaml" <<'YAML'
id: bf-py
schema_version: 1
type: bug-fix
fixture: tasks/bf-py/fixture
criterion: "runs of separators become one hyphen"
test_command: ["python3", "-m", "pytest", "-q", "tests"]
regression_command: ["python3", "-m", "pytest", "-q", "tests/test_existing.py"]
reference_patch: hidden/reference.patch
grader_protected: [tests/conftest.py, pytest.ini]
structural_check: null
review_catch: null
suite_version: 1
YAML
}

# bf-sh: a bash tool with bats tests, a bats helper and a Makefile target
make_bf_sh() {
  local d="$S/tasks/bf-sh" w="$T/w-sh"
  mkdir -p "$d/fixture/lib" "$d/fixture/tests" "$d/hidden/tests"
  printf 'greet() { echo "hello $1"; }\n' > "$d/fixture/lib/greet.sh"
  printf 'load_lib() { source "$BATS_TEST_DIRNAME/../lib/greet.sh"; }\n' > "$d/fixture/tests/helpers.bash"
  printf 'test:\n\tbats tests\n' > "$d/fixture/Makefile"
  cat > "$d/hidden/tests/greet.bats" <<'EOF'
setup() { load helpers; load_lib; }
@test "greets with a capital and punctuation" { run greet world; [ "$output" = "Hello, world!" ]; }
@test "greets without a name" { run greet; [ "$status" -eq 0 ]; }
@test "greets twice" { run greet a; [ "${#lines[@]}" -eq 1 ]; }
EOF
  echo '{"files": [{"src": "tests/greet.bats", "dest": "tests/greet.bats"}]}' > "$d/hidden/manifest.json"
  mkdir -p "$w/a" "$w/b"; cp -a "$d/fixture/." "$w/a/"; cp -a "$d/fixture/." "$w/b/"
  printf 'greet() { echo "Hello, $1!"; }\n' > "$w/b/lib/greet.sh"
  (cd "$w" && diff -ruN a b > "$d/hidden/reference.patch" || true)
  printf 'Fix the greeting.\n' > "$d/TASK.md"
  cat > "$d/task.yaml" <<'YAML'
id: bf-sh
schema_version: 1
type: bug-fix
fixture: tasks/bf-sh/fixture
criterion: "the greeting is capitalised and ends with an exclamation mark"
test_command: ["bats", "tests"]
regression_command: null
reference_patch: hidden/reference.patch
grader_protected: [tests/helpers.bash, Makefile]
structural_check: null
review_catch: null
suite_version: 1
YAML
}

# rf-py: a refactor (total() must reuse add()); the suite is green at both ends
make_rf_py() {
  local d="$S/tasks/rf-py" w="$T/w-rf"
  mkdir -p "$d/fixture/src/calc" "$d/fixture/tests" "$d/hidden/tests" "$d/hidden/structural"
  : > "$d/fixture/src/calc/__init__.py"
  printf 'def add(a, b):\n    return a + b\n\n\ndef total(xs):\n    s = 0\n    for x in xs:\n        s = s + x\n    return s\n' > "$d/fixture/src/calc/ops.py"
  printf 'import os, sys\nsys.path.insert(0, os.path.join(os.path.dirname(__file__), "src"))\n' > "$d/fixture/conftest.py"
  printf 'from calc.ops import add, total\n\n\ndef test_add():\n    assert add(2, 3) == 5\n\n\ndef test_total():\n    assert total([1, 2, 3]) == 6\n' > "$d/hidden/tests/test_ops.py"
  printf 'import inspect\nfrom calc import ops\n\n\ndef test_total_reuses_add():\n    assert "add(" in inspect.getsource(ops.total)\n' > "$d/hidden/structural/test_structure.py"
  echo '{"files": [{"src": "tests/test_ops.py", "dest": "tests/test_ops.py"}, {"src": "structural/test_structure.py", "dest": "structural/test_structure.py"}]}' > "$d/hidden/manifest.json"
  mkdir -p "$w/a" "$w/b"; cp -a "$d/fixture/." "$w/a/"; cp -a "$d/fixture/." "$w/b/"
  printf 'def add(a, b):\n    return a + b\n\n\ndef total(xs):\n    s = 0\n    for x in xs:\n        s = add(s, x)\n    return s\n' > "$w/b/src/calc/ops.py"
  (cd "$w" && diff -ruN a b > "$d/hidden/reference.patch" || true)
  printf 'Make total reuse add.\n' > "$d/TASK.md"
  cat > "$d/task.yaml" <<'YAML'
id: rf-py
schema_version: 1
type: refactor
fixture: tasks/rf-py/fixture
criterion: "the sum reuses the pairwise helper"
test_command: ["python3", "-m", "pytest", "-q", "tests"]
regression_command: null
reference_patch: hidden/reference.patch
grader_protected: [conftest.py]
structural_check: hidden/structural/test_structure.py
review_catch: null
suite_version: 1
YAML
}

# rc-x: a review-catch task over a 30-line PR with a high and a low defect
make_rc() {
  local d="$S/tasks/rc-x" p="$T/prs/pr-77" i
  mkdir -p "$d" "$p/base/lib" "$p/head/lib" "$T/manifests"
  for i in $(seq 1 30); do echo "line_$i=1"; done > "$p/base/lib/x.sh"
  for i in $(seq 1 30); do echo "line_$i=2"; done > "$p/head/lib/x.sh"
  printf -- '--- a/lib/x.sh\n+++ b/lib/x.sh\n' > "$p/head.diff"
  printf '# PR\n' > "$p/PR.md"
  cat > "$T/manifests/pr-77.json" <<'EOF'
{"fixture": "pr-77", "defects": [
  {"id": "D01-overflow-guard-dropped", "file": "lib/x.sh", "anchor_line": 5, "severity": "high", "category": "logic"},
  {"id": "D02-unquoted-expansion", "file": "lib/x.sh", "anchor_line": 20, "severity": "low", "category": "logic"}]}
EOF
  printf 'Review the pull request.\n' > "$d/TASK.md"
  cat > "$d/task.yaml" <<YAML
id: rc-x
schema_version: 1
type: review-catch
fixture: null
criterion: "review the change"
test_command: null
regression_command: null
reference_patch: null
grader_protected: []
structural_check: null
review_catch: {fixture: "$p", manifest: "$T/manifests/pr-77.json"}
suite_version: 1
YAML
}

sg() { local rd="$1"; shift; git -C "$rd/sandbox" -c user.email=e@l -c user.name=eval -c commit.gpgsign=false "$@"; }

# make_run <task-id> <run-dir>: the task fixture (or the PR under pr/) committed as base
make_run() {
  local id="$1" rd="$2" td="$S/tasks/$1"
  mkdir -p "$rd/sandbox" "$rd/snapshots" "$rd/transcripts" "$rd/eval" "$rd/meta"
  echo "$id" > "$rd.task"   # beside the run dir, for apply_ref
  if [[ -d "$td/fixture" ]]; then cp -a "$td/fixture/." "$rd/sandbox/"
  else mkdir -p "$rd/sandbox/pr"; cp -a "$T/prs/pr-77/." "$rd/sandbox/pr/"; fi
  sg "$rd" init -q
  printf '%s\n' '/.claude/' '/CLAUDE.md' '/.loa.config.yaml' '/grimoires/' '/.run/' '/.beads/' '/.eval/' >> "$rd/sandbox/.git/info/exclude"
  sg "$rd" add -A; sg "$rd" commit -q --allow-empty -m base
  jq -n --arg b "$(sg "$rd" rev-parse HEAD)" '{base: $b}' > "$rd/snapshots/index.json"
  mkdir -p "$rd/sandbox/grimoires/loa/a2a/sprint-1" "$rd/sandbox/.claude"
  echo "# mount" > "$rd/sandbox/CLAUDE.md"
  printf '{"run_id": "r-%s", "status": "completed", "arm": "a1_full"}\n' "$id" > "$rd/meta/pipeline.json"
  echo a1_full > "$rd/meta/arm"
}
# snap <run-dir> <LABEL>: commit and bundle the sandbox as pipeline-run.sh does after IMPLEMENT / FIX
snap() {
  local rd="$1" L="$2" c k
  sg "$rd" add -A; sg "$rd" commit -q --allow-empty -m "snapshot $L"
  c="$(sg "$rd" rev-parse HEAD)"; k="$(printf '%s' "$L" | tr 'A-Z' 'a-z')"
  sg "$rd" bundle create -q "$rd/snapshots/$L.bundle" HEAD
  jq --arg k "$k" --arg c "$c" '.[$k] = $c' "$rd/snapshots/index.json" > "$rd/snapshots/i.tmp" && mv "$rd/snapshots/i.tmp" "$rd/snapshots/index.json"
}
# verdict <run-dir> review|audit <VERDICT> [body]
verdict() {
  local f=engineer-feedback.md; [[ "$2" == audit ]] && f=auditor-sprint-feedback.md
  printf '# Feedback\n\n%s\n\n<!-- LOA-VERDICT {"gate":"%s","verdict":"%s","counts":{"critical":0,"high":1}} -->\n' "${4:-}" "$2" "$3" \
    > "$1/sandbox/grimoires/loa/a2a/sprint-1/$f"
}
apply_ref() { patch -s -p1 -d "$1/sandbox" < "$S/tasks/$(cat "$1.task")/hidden/reference.patch"; }
# tool_use <run-dir> <LABEL> <tool> <input-json>: one assistant tool_use event line
tool_use() {
  jq -cn --arg t "$3" --argjson i "$4" '{type: "assistant", message: {content: [{type: "tool_use", name: $t, input: $i}]}}' \
    >> "$1/transcripts/events-$2.jsonl"
}
grade() { run "$GRADER" "$@" --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"; }
tree_digest() {
  python3 -I -c '
import hashlib, os, sys
h = hashlib.sha256(); root = sys.argv[1]
for r, ds, fs in os.walk(root):
    ds.sort()
    for n in sorted(ds + fs):
        p = os.path.join(r, n); h.update(os.path.relpath(p, root).encode() + b"\0")
        if os.path.islink(p): h.update(b"L" + os.readlink(p).encode())
        elif os.path.isfile(p): h.update(open(p, "rb").read())
print(h.hexdigest())' "$1"
}
G() { jq -r "$1" "$RD/grade.json"; }

# --- grading trees (D-4.8) --------------------------------------------------------------------

@test "AG-1 the final tree is graded under grading/final in the image; the sandbox is byte-identical before and after" {
  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"; snap "$RD" IMPLEMENT
  before="$(tree_digest "$RD/sandbox")"
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(tree_digest "$RD/sandbox")" = "$before" ]
  [ -f "$RD/grading/final/tests/test_slug.py" ] && [ -f "$RD/grade.json" ]
  [ ! -e "$RD/grading/final/.git" ] && [ ! -e "$RD/grading/final/CLAUDE.md" ] && [ ! -e "$RD/grading/final/grimoires" ]
  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "7/7" ]
  [ "$(G '.executor_mode')" = container ] && [ "$(G '.image')" = "loa-ablation:258" ]
  [ "$(G '.diff_lines')" = 2 ] && [ "$(G '.files_changed')" = 1 ]
  # the docker argv: init, a name, no network, read-only root, tmpfs, limits, no capabilities, the caller's
  # uid, one rw mount, a kill deadline, the pytest shape (grader 1.2.0: MEDIUM-A1, HIGH-A1 -o addopts=)
  argv="$(tr '\0' ' ' < "$T/dlog/run-1.argv")"
  [[ "$argv" == "run --rm --init --name ablgrade-run-final-"*" --network none --read-only --tmpfs /tmp:rw,size=256m --pids-limit 256 --memory 2g --cpus 2 --cap-drop ALL --security-opt no-new-privileges --user $(id -u):$(id -g) -v $RD/grading/final:/workspace:rw -w /workspace -e HOME=/tmp -e LC_ALL=C -e TMPDIR=/tmp loa-ablation:258 timeout --signal=TERM --kill-after=10 120 python3 -I -s -m pytest -p no:cacheprovider -o addopts= -q --rootdir /workspace -rA tests "* ]]
  [ "$(tr '\0' '\n' < "$T/dlog/run-1.argv" | grep -cx -- -q)" -eq 1 ]
}

@test "AG-2 agent-edited tests/conftest.py, pytest.ini, a bats helper and a Makefile target are replaced by the fixture's copies" {
  RD="$T/run"; make_run bf-py "$RD"
  printf 'import sys\n' > "$RD/sandbox/tests/conftest.py"          # would break the import path
  printf '[pytest]\naddopts = -k existing\n' > "$RD/sandbox/pytest.ini"   # would deselect the hidden tests
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  cmp "$RD/grading/final/tests/conftest.py" "$S/tasks/bf-py/fixture/tests/conftest.py"
  cmp "$RD/grading/final/pytest.ini" "$S/tasks/bf-py/fixture/pytest.ini"
  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "5/7" ]
  RD="$T/run-sh"; make_run bf-sh "$RD"
  printf 'load_lib() { greet() { echo "Hello, $1!"; }; }\n' > "$RD/sandbox/tests/helpers.bash"   # a helper that fakes the fix
  printf 'test:\n\ttrue\n' > "$RD/sandbox/Makefile"
  grade "$RD" bf-sh
  [ "$status" -eq 0 ]
  cmp "$RD/grading/final/tests/helpers.bash" "$S/tasks/bf-sh/fixture/tests/helpers.bash"
  cmp "$RD/grading/final/Makefile" "$S/tasks/bf-sh/fixture/Makefile"
  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "2/3" ]
  [ "$(G '.hidden_tests.failed_names | join(",")')" = "t1" ]
}

@test "AG-3 a deleted tests/ directory is restored (protected files and the hidden overlay)" {
  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
  rm -rf "$RD/sandbox/tests"
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ -f "$RD/grading/final/tests/conftest.py" ] && [ -f "$RD/grading/final/tests/test_slug.py" ]
  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "5/5" ]
  # the regression suite lost its file: both of its base cases are newly failing
  [ "$(G '.regressions.newly_failing | join(",")')" = "t1,t2" ]
}

@test "AG-4 a same-named file is overwritten by the hidden copy; a symlinked test dir is replaced" {
  RD="$T/run"; make_run bf-py "$RD"
  printf 'def test_basic():\n    assert True\n' > "$RD/sandbox/tests/test_slug.py"
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  cmp "$RD/grading/final/tests/test_slug.py" "$S/tasks/bf-py/hidden/tests/test_slug.py"
  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "5/7" ]
  [ "$(G '.hidden_tests.failed_names | join(",")')" = "t6,t7" ]
  RD="$T/run2"; make_run bf-py "$RD"
  mkdir -p "$T/elsewhere"; mv "$RD/sandbox/tests" "$T/elsewhere/tests"; ln -s "$T/elsewhere/tests" "$RD/sandbox/tests"
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ ! -L "$RD/grading/final/tests" ] && [ -d "$RD/grading/final/tests" ]
  [ ! -e "$T/elsewhere/tests/test_slug.py" ]
}

@test "AG-5 regressions: a fixture test the agent broke is newly failing by its base id; parse failure counts the static cases" {
  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
  sed -i 's/"a-b"/"a_b"/' "$RD/sandbox/tests/test_existing.py"
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.regressions.newly_failing | join(",")')" = "t2" ]
  [ "$(G '.regressions.base | "\(.passed)/\(.total)"')" = "2/2" ]
  [ "$(G '.regressions.final | "\(.passed)/\(.total)"')" = "1/2" ]
  # an import the agent broke: a collection error interrupts the run; the hidden total stays the static count
  RD="$T/run2"; make_run bf-py "$RD"
  printf 'import nope\n' > "$RD/sandbox/src/textkit/__init__.py"
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.hidden_tests.passed')" = 0 ] && [ "$(G '.hidden_tests.total')" -ge 5 ]
}

@test "AG-6 per-gate verdict accuracy against the snapshot each gate read; null when no gate ran" {
  RD="$T/run"; make_run bf-py "$RD"
  snap "$RD" IMPLEMENT                       # the fixture unchanged: hidden tests fail
  verdict "$RD" review CHANGES_REQUIRED      # right
  apply_ref "$RD"; snap "$RD" FIX1           # fixed
  verdict "$RD" audit APPROVED               # right
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.snapshots_graded | join(",")')" = "final,implement,fix1" ]
  [ "$(G '.verdict_accuracy_per_gate | "\(.review),\(.audit)"')" = "true,true" ]
  [ "$(G '.verdict_accuracy')" = true ]
  [ "$(G '.verdict | "\(.source_file) \(.value)"')" = "auditor-sprint-feedback.md APPROVED" ]
  [ "$(G '.snapshot_tests | "\(.implement.passed)/\(.implement.total) \(.fix1.passed)/\(.fix1.total)"')" = "5/7 7/7" ]
  verdict "$RD" review APPROVED; verdict "$RD" audit CHANGES_REQUIRED   # both wrong
  grade "$RD" bf-py
  [ "$(G '.verdict_accuracy_per_gate | "\(.review),\(.audit)"')" = "false,false" ]
  # A4-shaped: IMPLEMENT only, no gate → null; AUDIT without FIX1 reads implement
  RD="$T/run-a4"; make_run bf-py "$RD"; apply_ref "$RD"; snap "$RD" IMPLEMENT
  grade "$RD" bf-py
  [ "$(G '.verdict_accuracy_per_gate | "\(.review),\(.audit)"')" = "null,null" ]
  [ "$(G '.verdict_accuracy')" = null ] && [ "$(G '.verdict')" = null ]
  [ "$(G '.snapshots_graded | join(",")')" = final ]
  verdict "$RD" audit APPROVED
  grade "$RD" bf-py
  [ "$(G '.verdict_accuracy_per_gate | "\(.review),\(.audit)"')" = "null,true" ]
}

@test "AG-7 refactor: the structural check is hidden_tests, the fixture suite is the regression check at both ends; bats TAP ids" {
  RD="$T/run"; make_run rf-py "$RD"; apply_ref "$RD"
  grade "$RD" rf-py
  [ "$status" -eq 0 ]
  [ "$(G '.structural | "\(.passed)/\(.total) \(.suite_green_base) \(.suite_green_final)"')" = "1/1 true true" ]
  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.rc) \(.timed_out)"')" = "1/1 0 false" ]
  [ "$(G '.regressions | "\(.base.passed)/\(.base.total) \(.final.passed)/\(.final.total) \(.newly_failing | length) \(.parse_error)"')" = "2/2 2/2 0 false" ]
  RD="$T/run2"; make_run rf-py "$RD"
  grade "$RD" rf-py
  [ "$(G '.structural | "\(.passed)/\(.total) \(.failed_names | join(","))"')" = "0/1 t1" ]
  # an untouched tree: the suite is green but the hidden assertion (structural) is red
  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.failed_names | join(","))"')" = "0/1 t1" ]
  [ "$(G '.regressions.final | "\(.passed)/\(.total)"')" = "2/2" ]
  # a refactor that breaks behaviour: structural green, the suite case is newly failing by its base id
  RD="$T/run3"; make_run rf-py "$RD"; apply_ref "$RD"
  sed -i 's/return a + b/return a - b/' "$RD/sandbox/src/calc/ops.py"
  grade "$RD" rf-py
  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "1/1" ]
  [ "$(G '.regressions.newly_failing | join(",")')" = "t1,t2" ]
  [ "$(G '.structural.suite_green_final')" = false ]
  RD="$T/run-sh"; make_run bf-sh "$RD"; apply_ref "$RD"
  grade "$RD" bf-sh
  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.parse_error)"')" = "3/3 false" ]
  cat "$T"/dlog/run-*.argv | tr '\0' ' ' | grep -q -- 'timeout --signal=TERM --kill-after=10 120 bats --tap tests'
}

@test "AG-18 end to end: a pipeline-run.sh run (stub CLI, stub mount library) grades with its real bundles and gate files" {
  local H="$T/h/evals/harness" sk
  mkdir -p "$H/lib" "$T/src/.claude/loa" "$T/home"
  cp "$REPO_ROOT/evals/harness/pipeline-run.sh" "$REPO_ROOT/evals/harness/fingerprint.sh" "$H/"
  cp -a "$REPO_ROOT/evals/harness/lib/phase-prompts" "$H/lib/"
  cp "$TESTS_DIR/fixtures/mount-lib-stub.sh" "$H/lib/sandbox-mount.sh"
  cp "$REPO_ROOT/evals/harness/lib/session-exec.sh" "$H/lib/"   # cycle-133 C-6: the session library
  for sk in planning-sprints implementing-tasks reviewing-code auditing-security; do
    mkdir -p "$T/src/.claude/skills/$sk"; printf -- '---\nname: %s\neffort: xhigh\n---\nbody\n' "$sk" > "$T/src/.claude/skills/$sk/SKILL.md"
  done
  echo loa > "$T/src/.claude/loa/CLAUDE.loa.md"; printf 'flatline_protocol:\n  enabled: true\n' > "$T/src/.loa.config.yaml"
  mkdir -p "$T/src/.claude/adapters/loa_cheval/providers"   # cycle-132 bd-56nn6: the pre-launch mount_cheval probe imports it
  : > "$T/src/.claude/adapters/loa_cheval/__init__.py"; : > "$T/src/.claude/adapters/loa_cheval/providers/__init__.py"
  ( cd "$T/src" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init )
  printf 'STUB_VERDICT_REVIEW=CHANGES_REQUIRED\n' > "$T/stub.env"
  cat > "$T/claude" <<EOF
#!/usr/bin/env bash
set -a; . "$T/stub.env"; set +a
exec "$TESTS_DIR/fixtures/claude-stub-pipeline.sh" "\$@"
EOF
  chmod +x "$T/claude"
  LOA_EVAL_WATCHDOG_POLL_S=0.1 LOA_EVAL_CREDS_HOME="$T/home" \
  LOA_EVAL_PRICING_JSON='{"global.anthropic.claude-opus-5-5":{"input_per_mtok":4000000,"output_per_mtok":20000000},"global.anthropic.claude-fable-5-1":{"input_per_mtok":10000000,"output_per_mtok":50000000}}' \
    run "$H/pipeline-run.sh" --task-yaml "$S/tasks/bf-py/task.yaml" --arm a1_full --run-dir "$T/e2e" --run-id r-e2e \
      --trial 1 --source-tree "$T/src" --suite-file "$TESTS_DIR/fixtures/ablation-runs/suite.yaml" --executor host --claude-bin "$T/claude"
  [ "$status" -eq 0 ]
  [ -f "$T/e2e/snapshots/IMPLEMENT.bundle" ] && [ -f "$T/e2e/snapshots/FIX1.bundle" ]
  RD="$T/e2e"
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.snapshots_graded | join(",")')" = "final,implement,fix1" ]
  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "5/7" ]
  # REVIEW asked for changes on a failing tree (right); AUDIT approved a tree that still fails (wrong)
  [ "$(G '.verdicts | "\(.review) \(.audit)"')" = "CHANGES_REQUIRED APPROVED" ]
  [ "$(G '.verdict_accuracy_per_gate | "\(.review),\(.audit)"')" = "true,false" ]
  [ "$(G '.contaminated')" = null ]
  run "$REPO_ROOT/evals/harness/ablation-row.sh" --run-dir "$RD" --task-yaml "$S/tasks/bf-py/task.yaml"
  [ "$status" -eq 0 ]
  [ "$(jq -r '"\(.hidden_test_pass_rate * 7 | round) \(.verdict_accuracy_review) \(.verdict_accuracy_audit) \(.regressions)"' <<<"$output")" = "5 true false 0" ]
}

# --- review-catch (DEC-0420) -----------------------------------------------------------------

@test "AG-8 gates-combined.md reduces review.md, both feedback files and both eval/ envelopes; recall and deduplicated false positives" {
  RD="$T/run"; make_run rc-x "$RD"
  A="$RD/sandbox/grimoires/loa/a2a/sprint-1"
  printf 'head/lib/x.sh:5 — the guard is gone\nVerdict: CHANGES_REQUIRED\n' > "$RD/sandbox/review.md"
  verdict "$RD" review APPROVED 'lib/x.sh:12 reads a stale value'
  verdict "$RD" audit CHANGES_REQUIRED 'pr/head/lib/x.sh:13 the same stale value'
  echo '{"findings": [{"anchor": "lib/x.sh:20", "severity": "low"}]}' > "$RD/eval/adversarial-review.json"
  echo '{"findings": [{"file": "lib/x.sh", "line": 28, "severity": "medium"}]}' > "$RD/eval/adversarial-audit.json"
  # the sandbox copy of an envelope is tamperable and never read
  echo '{"findings": [{"anchor": "lib/x.sh:2"}]}' > "$A/adversarial-review.json"
  grade "$RD" rc-x
  [ "$status" -eq 0 ]
  [ "$(cat "$RD/grading/gates-combined.md" | tr '\n' ' ')" = "head/lib/x.sh:5 lib/x.sh:12 head/lib/x.sh:13 lib/x.sh:20 lib/x.sh:28 " ]
  [ "$(G '.recall | "\(.defects_seeded) \(.defects_caught) \(.recall == 1) \(.flags) \(.missed | length)"')" = "2 2 true 5 0" ]
  [ "$(G '.false_positives')" = 2 ]      # 12 and 13 share a ±3 region; 28 is another
  [ "$(G '.hidden_tests')" = null ] && [ "$(G '.diff_lines')" = null ]
  # the key holds a high defect: CHANGES_REQUIRED is accurate, APPROVED is not
  [ "$(G '.verdict_accuracy_per_gate | "\(.review),\(.audit)"')" = "false,true" ]
  [ "$(G '.verdict_accuracy')" = true ]
  # without the envelopes the low defect is missed, by position only
  rm "$RD/eval/adversarial-review.json"
  grade "$RD" rc-x
  [ "$(G '.recall | "\(.defects_caught) \(.missed | join(","))"')" = "1 d2" ]
}

@test "AG-9 review-catch A0: no gate ran, review.md gives the verdict, accuracy stays null; no docker needed" {
  RD="$T/run"; make_run rc-x "$RD"
  printf 'head/lib/x.sh:4 — guard\nVerdict: APPROVED\n' > "$RD/sandbox/review.md"
  echo 'DOCKER_STUB_NO_IMAGE=1' > "$T/docker.env"
  grade "$RD" rc-x
  [ "$status" -eq 0 ]
  [ "$(G '.verdict | "\(.source_file) \(.value)"')" = "review.md APPROVED" ]
  [ "$(G '.verdict_accuracy_per_gate | "\(.review),\(.audit)"')" = "null,null" ]
  [ "$(G '.recall.defects_caught')" = 1 ]
}

# --- contamination (D-4.7, DEC-0493) --------------------------------------------------------------

@test "AG-10 contamination: each pattern class, a WebFetch URL and a WebSearch query, first hit in phase order, ids only" {
  local i=0 tool inp want task
  while IFS=$'\t' read -r tool inp want; do
    i=$((i + 1)); RD="$T/c$i"
    task=rc-x; case "$want" in hidden|suite_path) task=bf-py ;; esac   # grader 1.3.6/1.3.7: build-only classes
    make_run "$task" "$RD"
    tool_use "$RD" IMPLEMENT Bash '{"command": "ls"}'
    tool_use "$RD" IMPLEMENT "$tool" "$inp"
    grade "$RD" "$task"
    [ "$status" -eq 0 ]
    [ "$(G '.contaminated | "\(.phase) \(.pattern) \(.excerpt_id)"')" = "IMPLEMENT $want IMPLEMENT:2" ]
    if [ "$want" = network_egress ]; then   # round 10: class 9 adds its telemetry (repo_named, host, url)
      [ "$(G '.contaminated | keys | join(",")')" = "excerpt_id,host,pattern,phase,repo_named,url" ]
    else
      [ "$(G '.contaminated | keys | join(",")')" = "excerpt_id,pattern,phase" ]
    fi
  done <<'EOF'
Bash	{"command": "cat tests/HIDDEN_cases.py"}	hidden
Read	{"file_path": "/workspace/grimoires/loa/evals/ablation-2.0/tasks/x/task.yaml"}	suite_path
WebFetch	{"url": "https://github.com/0xHoneyJar/loa/tree/main", "prompt": "read"}	network_egress
WebFetch	{"url": "https://example.com/hidden/answers", "prompt": "read"}	hidden
WebSearch	{"query": "0xhoneyjar/loa ablation tasks"}	network_egress
Read	{"file_path": "/home/operator/code/loa/README.md"}	outside_path
Bash	{"command": "cat /home/operator/notes.txt 2>/dev/null"}	outside_path
Glob	{"pattern": "/srv/**/*.py"}	outside_path
Bash	{"command": "cat /proc/self/environ"}	outside_path
Bash	{"command": "tr '\\0' ' ' < /proc/1/cmdline"}	outside_path
Read	{"file_path": "/proc/self/maps"}	outside_path
Bash	{"command": "ls /var/run/docker.sock"}	outside_path
Bash	{"command": "cd /root/ && cat .ssh/id_rsa"}	outside_path
Bash	{"command": "cd /root && cat .ssh/id_rsa"}	outside_path
Bash	{"command": "ls /home"}	outside_path
EOF
  # first hit in phase order: IMPLEMENT before REVIEW whatever the file names sort to
  RD="$T/order"; make_run rc-x "$RD"
  tool_use "$RD" REVIEW Bash '{"command": "cat /home/operator/secret"}'
  tool_use "$RD" IMPLEMENT Bash '{"command": "ls"}'
  tool_use "$RD" IMPLEMENT Read '{"file_path": "/root/x"}'
  grade "$RD" rc-x
  [ "$(G '.contaminated | "\(.phase) \(.pattern) \(.excerpt_id)"')" = "IMPLEMENT outside_path IMPLEMENT:2" ]
  ! grep -q '/root/x' "$RD/grade.json" || false
  # grader 1.2.1 (DEC-0540, calibration smoke): git history probes are telemetry, never
  # contamination (the sandbox is a fresh git init at base); Loa slash commands in report text
  # are command tokens, not paths; a data-holding single component (/root, /home) still counts
  RD="$T/probes"; make_run rc-x "$RD"
  tool_use "$RD" REVIEW Bash '{"command": "git log --oneline --all | head"}'
  tool_use "$RD" REVIEW Bash '{"command": "git reflog"}'   # one probe per command that matches
  tool_use "$RD" IMPLEMENT Bash '{"command": "cat > grimoires/loa/a2a/sprint-1/reviewer.md <<EOF\n# Report\n**Status:** ready for `/review-sprint sprint-1`, then `/audit-sprint sprint-1`\nEOF"}'
  tool_use "$RD" IMPLEMENT Bash '{"command": "cd /workspace && python3 -m pytest -q tests --ignore=tests/structure"}'
  grade "$RD" rc-x
  [ "$status" -eq 0 ]
  [ "$(G '.contaminated')" = null ]
  [ "$(G '.history_probes')" = 2 ]
  RD="$T/clean2"; make_run rc-x "$RD"
  tool_use "$RD" IMPLEMENT Bash '{"command": "echo done"}'
  grade "$RD" rc-x
  [ "$(G '.history_probes')" = 0 ]
  # grader 1.2.2 (DEC-0541): in container mode ~/ is the container home (allowed), a heredoc body
  # is data (a path in written prose is not a reach), sed/awk delimiters are not paths; a real
  # reach outside the heredoc and a hidden word inside one are still hits
  RD="$T/c122"; make_run rc-x "$RD"
  tool_use "$RD" IMPLEMENT Bash '{"command": "ls ~/.cargo/bin 2>/dev/null; cat $HOME/.codex/config.toml"}'
  tool_use "$RD" IMPLEMENT Bash '{"command": "sed -n '"'"'/^flatline_protocol:/,/^[a-z_]*:$/p'"'"' .loa.config.yaml | head"}'
  tool_use "$RD" IMPLEMENT Bash '{"command": "cat > notes.md <<EOF\nSee /home/operator/notes and the `<<<`/arithmetic/quote-parity check\nEOF"}'
  grade "$RD" rc-x
  [ "$(G '.contaminated')" = null ]
  # grader 1.2.3 (DEC-0546, priority batch P1): a sed address range whose first regex begins
  # with a character ABS_WORD accepts (=, a letter, a digit) is still a regex pair, not a path;
  # a comma-led second component never occurs in a path
  RD="$T/c123"; make_run rc-x "$RD"
  tool_use "$RD" REVIEW Bash '{"command": "f=/home/evaluser/.claude/projects/-workspace/abc/tool-results/x.txt; sed -n '"'"'/======TEMPLATE/,/======STAT/p'"'"' $f; sed -n '"'"'/======STAT/,/^# Review/p'"'"' $f | head -20"}'
  tool_use "$RD" REVIEW Bash '{"command": "sed -n '"'"'/BEGIN/,+3p'"'"' notes.txt; awk '"'"'/start/,/end/'"'"' log.txt"}'
  grade "$RD" rc-x
  [ "$(G '.contaminated')" = null ]
  tool_use "$RD" REVIEW Bash '{"command": "sed -n '"'"'/x/,/y/p'"'"' /home/operator/notes.txt"}'
  grade "$RD" rc-x
  [ "$(G '.contaminated | .pattern + " " + .excerpt_id')" = "outside_path REVIEW:3" ]
  # grader 1.2.4 (DEC-0551): a range whose first address holds spaces tokenises to a /,/… remnant;
  # a word carrying = is a regex or key=value token; a real outside path beside them still hits
  RD="$T/c124"; make_run rc-x "$RD"
  tool_use "$RD" AUDIT Bash '{"command": "F=/home/evaluser/.claude/projects/-workspace/abc/tool-results/x.txt; sed -n '"'"'/=== VERIFY python ValueError ===/,/=== scanner usage ===/p'"'"' $F; sed -n '"'"'/=== br? ===/,/=== scripts usage ===/p'"'"' $F | cut -c1-200"}'
  tool_use "$RD" AUDIT Bash '{"command": "cat > grimoires/loa/a2a/sprint-1/reviewer-concerns.md <<EOF\n1. argument_default=argparse.SUPPRESS: any hidden\n   interaction with store_true? The value is hidden.\nEOF"}'
  tool_use "$RD" AUDIT Bash '{"command": "grep -E '"'"'^--- '"'"' $F | sed -E '"'"'s/\\|Violations:\\|/ VIOL: /; s/x.*y\\)\\|\\|//'"'"'; awk -F= '"'"'/key=\\/etc\\/x/{print}'"'"' conf"}'
  grade "$RD" rc-x
  [ "$(G '.contaminated')" = null ]
  tool_use "$RD" AUDIT Bash '{"command": "sed -n '"'"'/=== a ===/,/=== b ===/p'"'"' /home/operator/secret.txt"}'
  grade "$RD" rc-x
  [ "$(G '.contaminated | .pattern + " " + .excerpt_id')" = "outside_path AUDIT:4" ]
  # grader 1.2.5 (DEC-0557): a path tail after a closing quote glued to its token is not absolute;
  # an opening quote keeps the word a candidate
  RD="$T/c125"; make_run rc-x "$RD"
  tool_use "$RD" AUDIT Bash '{"command": "D=$(mktemp -d /home/evaluser/mut.XXXXXX) && cp -r evals tests \"$D\"/ && sed -i \"s/x/y/\" \"$D\"/evals/harness/seed.sh && (cd \"$D\" && bats tests)"}'
  grade "$RD" rc-x
  [ "$(G '.contaminated')" = null ]
  tool_use "$RD" AUDIT Bash '{"command": "cat \"/home/operator/x\"; echo \"$D\"/evals/x"}'
  grade "$RD" rc-x
  [ "$(G '.contaminated | .pattern + " " + .excerpt_id')" = "outside_path AUDIT:2" ]
  RD="$T/c122"   # the 1.2.2 run continues below
  tool_use "$RD" REVIEW Bash '{"command": "cat > notes.md <<EOF\nsee tests/hidden/ for the cases\nEOF"}'   # 1.2.4: a path-shaped hidden token in a heredoc is still a hit
  grade "$RD" rc-x
  # grader 1.3.6: on a review-catch run the hidden class is skipped (recorded); on a build run the same command is a hit
  [ "$(G '.contaminated')" = null ]
  [ "$(G '.contamination_classes_skipped | join(",")')" = hidden,suite_path ]
  RD="$T/c122h"; make_run bf-py "$RD"
  tool_use "$RD" REVIEW Bash '{"command": "cat > notes.md <<EOF\nsee tests/hidden/ for the cases\nEOF"}'
  grade "$RD" bf-py
  [ "$(G '.contaminated | "\(.phase) \(.pattern)"')" = "REVIEW hidden" ]
  RD="$T/c122b"; make_run rc-x "$RD"
  tool_use "$RD" IMPLEMENT Bash '{"command": "cat > notes.md <<EOF\nx\nEOF\ncat /home/operator/notes"}'
  grade "$RD" rc-x
  [ "$(G '.contaminated.pattern')" = outside_path ]
}

@test "AG-11 contamination: ordinary container and host commands are clean; host paths are judged against the sandbox root" {
  RD="$T/clean"; make_run rc-x "$RD"
  tool_use "$RD" IMPLEMENT Bash '{"command": "cat /workspace/src/a.py 2>/dev/null | awk '"'"'/LOA-VERDICT/ {print}'"'"'; ls /usr/bin/env /tmp/x"}'
  tool_use "$RD" IMPLEMENT Read '{"file_path": "/workspace/src/a.py"}'
  tool_use "$RD" IMPLEMENT Grep '{"pattern": "^/api", "path": "/workspace"}'
  tool_use "$RD" IMPLEMENT Glob '{"pattern": "**/*.py"}'
  tool_use "$RD" IMPLEMENT WebFetch '{"url": "https://docs.python.org/3/library/re.html", "prompt": "x"}'
  tool_use "$RD" IMPLEMENT Write '{"file_path": "/home/evaluser/.claude/x", "content": "hidden text in content is not scanned"}'
  grade "$RD" rc-x
  [ "$status" -eq 0 ]
  [ "$(G '.contaminated')" = null ]
  RD="$T/host"; make_run rc-x "$RD"
  tool_use "$RD" IMPLEMENT Read "$(jq -cn --arg p "$RD/sandbox/lib/x.sh" '{file_path: $p}')"
  tool_use "$RD" IMPLEMENT Bash '{"command": "sed s/x/y/ lib/x.sh; sed -i '"'"'s/a/b/'"'"' lib/x.sh; cat /proc/cpuinfo /proc/self/status; ls /var/log"}'
  run "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --executor host
  [ "$status" -eq 0 ]
  [ "$(G '.contaminated')" = null ] && [ "$(G '.image')" = null ] && [ "$(G '.executor_mode')" = host ]
  # grader 1.2.0 (LOW-A2): the caller's credential stores are no longer exempt in host mode
  tool_use "$RD" REVIEW Read "$(jq -cn --arg p "$HOME/.claude/settings.json" '{file_path: $p}')"
  run "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --executor host
  [ "$(G '.contaminated | "\(.phase) \(.pattern)"')" = "REVIEW outside_path" ]
  RD="$T/host2"; make_run rc-x "$RD"
  tool_use "$RD" AUDIT Read '{"file_path": "/home/evaluser/x"}'
  run "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --executor host
  [ "$(G '.contaminated | "\(.phase) \(.pattern)"')" = "AUDIT outside_path" ]
  for c in 'cat ~/.aws/credentials' 'ls ~/.codex/' 'cat $HOME/.claude.json'; do
    RD="$T/host-$((i = ${i:-0} + 1))"; make_run rc-x "$RD"
    tool_use "$RD" IMPLEMENT Bash "$(jq -cn --arg c "$c" '{command: $c}')"
    run "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --executor host
    [ "$(G '.contaminated.pattern')" = outside_path ]
  done
}

# --- the meta/ boundary and id-only summaries (DEC-0413) ---------------------------------------------

@test "AG-12 meta/ removed → byte-identical grade.json; summary fields carry ids only" {
  RD="$T/run"; make_run bf-py "$RD"; snap "$RD" IMPLEMENT; verdict "$RD" review CHANGES_REQUIRED
  apply_ref "$RD"; sed -i 's/"a-b"/"a_b"/' "$RD/sandbox/tests/test_existing.py"; snap "$RD" FIX1; verdict "$RD" audit APPROVED
  tool_use "$RD" FIX1 Bash '{"command": "cat /home/operator/hidden.txt"}'
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  cp "$RD/grade.json" "$T/with-meta.json"
  rm -rf "$RD/meta"
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  cmp "$T/with-meta.json" "$RD/grade.json"
  ! grep -n 'graded_at\|test_\|slug\|collapses\|/home/operator\|hidden.txt' "$RD/grade.json"
  ! grep -q "$T" "$RD/grade.json"
  RD="$T/rc"; make_run rc-x "$RD"; printf 'head/lib/x.sh:5 guard\n' > "$RD/sandbox/review.md"
  grade "$RD" rc-x
  ! grep -n 'D01\|D02\|overflow\|unquoted' "$RD/grade.json"
  [ "$(G '.recall.missed | join(",")')" = d2 ]
}

@test "AG-13 the grader source never reads meta/ (only the comment saying so) and keeps the trust boundary" {
  # every meta/ mention is a comment; the code's one meta read is the union's meta/cell.json (grader 1.3.2: the runner's
  # record of a matched cell, which names no arm)
  [ -z "$(grep -n 'meta/' "$GRADER" | grep -v '^[0-9]*:# ')" ]
  [ "$(grep -c '"meta"' "$GRADER")" -eq 1 ]
  grep '"meta"' "$GRADER" | grep -q '"cell.json"'
  ! grep -nE '^[[:space:]]*(source|\.)[[:space:]].*\$' "$GRADER"
  ! grep -nE '(^|[^A-Za-z_])eval[[:space:]].*\$' "$GRADER"
  ! grep -n 'sha256sum\|\.claude/scripts' "$GRADER"
}

# --- self-check (DEC-0401, AC-2.3) on the smoke tasks, through the docker stub ----------------------------

@test "AG-14 --self-check base|reference on smoke-build-01 and base|reference|noisy on smoke-review-01 (frozen copy)" {
  F="$T/frozen"; mkdir -p "$F"; cp -a "$SMOKE" "$F/smoke"
  run bash "$REPO_ROOT/evals/harness/freeze.sh" --root "$F" --smoke --allow-partial
  [ "$status" -eq 0 ]
  local m
  for m in base reference; do
    run "$GRADER" --self-check "$m" --task-yaml "$F/smoke/smoke-build-01/task.yaml" --allow-partial --docker-bin "$T/docker"
    [ "$status" -eq 0 ]
    [[ "$output" == "self-check $m smoke-build-01: PASS hidden "* ]]
  done
  [[ "$output" == *"hidden 5/5"* ]]
  for m in base reference noisy; do
    run "$GRADER" --self-check "$m" --task-yaml "$F/smoke/smoke-review-01/task.yaml" --allow-partial --docker-bin "$T/docker"
    [ "$status" -eq 0 ]
    [[ "$output" == "self-check $m smoke-review-01: PASS recall "* ]]
  done
  [[ "$output" == *"vs reference 0"* ]]
  # the self-check ran its tests in the image (stub) and left nothing behind
  grep -q 'python3 -I -s -m pytest' <(tr '\0' ' ' < "$T/dlog/run-1.argv")
  run "$GRADER" --self-check noisy --task-yaml "$F/smoke/smoke-build-01/task.yaml" --allow-partial --docker-bin "$T/docker"
  [ "$status" -eq 2 ]
}

@test "AG-15 --self-check FAIL is exit 1: a reference patch that does not fix the bug, a refactor whose structural check is green at base" {
  printf -- '--- a/src/textkit/slug.py\n+++ b/src/textkit/slug.py\n@@ -1 +1 @@\n-import re\n+import re  # noop\n' > "$S/tasks/bf-py/hidden/reference.patch"
  run "$GRADER" --self-check reference --task-yaml "$S/tasks/bf-py/task.yaml" --allow-unfrozen --docker-bin "$T/docker"
  [ "$status" -eq 1 ]
  [[ "$output" == *"self-check reference bf-py: FAIL hidden 5/7"* ]]
  run "$GRADER" --self-check base --task-yaml "$S/tasks/rf-py/task.yaml" --allow-unfrozen --docker-bin "$T/docker"
  [ "$status" -eq 0 ]
  [[ "$output" == *"self-check base rf-py: PASS structural 0/1, suite green"* ]]
  run "$GRADER" --self-check reference --task-yaml "$S/tasks/rf-py/task.yaml" --allow-unfrozen --docker-bin "$T/docker"
  [ "$status" -eq 0 ]
  cp "$S/tasks/rf-py/hidden/reference.patch" "$T/p"; (cd "$S/tasks/rf-py/fixture" && patch -s -p1 < "$T/p")
  run "$GRADER" --self-check base --task-yaml "$S/tasks/rf-py/task.yaml" --allow-unfrozen --docker-bin "$T/docker"
  [ "$status" -eq 1 ]
}

# --- freeze (DEC-0414) and errors --------------------------------------------------------------------

@test "AG-16 an unfrozen suite is refused without --allow-unfrozen; a drift is refused; --allow-unfrozen records suite_frozen false" {
  RD="$T/run"; make_run rc-x "$RD"; printf 'head/lib/x.sh:5\n' > "$RD/sandbox/review.md"
  run "$GRADER" "$RD" rc-x --suite-root "$S" --docker-bin "$T/docker"
  [ "$status" -eq 2 ]
  [[ "$output" == *"suite is not frozen"* ]]
  [ ! -e "$RD/grade.json" ]
  grade "$RD" rc-x
  [ "$status" -eq 0 ]
  [ "$(G '.suite_frozen')" = false ]
  F="$T/frozen"; mkdir -p "$F"; cp -a "$SMOKE" "$F/smoke"
  bash "$REPO_ROOT/evals/harness/freeze.sh" --root "$F" --smoke --allow-partial >/dev/null
  run "$GRADER" --self-check base --task-yaml "$F/smoke/smoke-review-01/task.yaml" --docker-bin "$T/docker"
  [ "$status" -eq 2 ]                      # the four-per-type count needs --allow-partial today
  echo "# drift" >> "$F/smoke/smoke-review-01/TASK.md"
  run "$GRADER" --self-check base --task-yaml "$F/smoke/smoke-review-01/task.yaml" --allow-partial --docker-bin "$T/docker"
  [ "$status" -eq 2 ]
  [[ "$output" == *"freeze.sh --check failed"* ]]
}

@test "AG-17 errors are exit 2: missing run dir, unknown task, docker or the image missing in container mode" {
  run "$GRADER" "$T/nope" bf-py --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"
  [ "$status" -eq 2 ]
  RD="$T/run"; make_run bf-py "$RD"
  run "$GRADER" "$RD" no-such-task --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"
  [ "$status" -eq 2 ] && [[ "$output" == *"task not found"* ]]
  run "$GRADER" "$RD" bf-py --suite-root "$S" --allow-unfrozen --docker-bin "$T/no-docker"
  [ "$status" -eq 2 ] && [[ "$output" == *"docker CLI not found"* ]]
  echo 'DOCKER_STUB_NO_IMAGE=1' > "$T/docker.env"
  run "$GRADER" "$RD" bf-py --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"
  [ "$status" -eq 2 ] && [[ "$output" == *"image not found"* ]]
  run "$GRADER" "$RD" bf-py --bogus
  [ "$status" -eq 2 ]
}

# --- Sprint 259 fix round (engineer-feedback HIGH-1, MEDIUM-1, MEDIUM-3, LOW-2) ---------------------

# bf-tap: a bash-runner task; the hidden runner prints a passing TAP block and exits 1 (a
# teardown failure), the regression check is a bash script with no summary at all
make_bf_tap() {
  local d="$S/tasks/bf-tap" w="$T/w-tap"
  mkdir -p "$d/fixture/lib" "$d/fixture/tests" "$d/hidden/tests"
  printf 'v=1\n' > "$d/fixture/lib/x.sh"
  printf 'grep -q "^v=" lib/x.sh\n' > "$d/fixture/tests/reg.sh"
  printf 'echo 1..1\necho "ok 1 the value is set"\nexit 1\n' > "$d/hidden/tests/run.sh"
  echo '{"files": [{"src": "tests/run.sh", "dest": "tests/run.sh"}]}' > "$d/hidden/manifest.json"
  mkdir -p "$w/a" "$w/b"; cp -a "$d/fixture/." "$w/a/"; cp -a "$d/fixture/." "$w/b/"
  printf 'v=2\n' > "$w/b/lib/x.sh"
  (cd "$w" && diff -ruN a b > "$d/hidden/reference.patch" || true)
  printf 'Set the value.\n' > "$d/TASK.md"
  cat > "$d/task.yaml" <<'YAML'
id: bf-tap
schema_version: 1
type: bug-fix
fixture: tasks/bf-tap/fixture
criterion: "the value is two"
test_command: ["bash", "tests/run.sh"]
regression_command: ["bash", "tests/reg.sh"]
reference_patch: hidden/reference.patch
grader_protected: [tests/reg.sh]
structural_check: null
review_catch: null
suite_version: 1
YAML
}

@test "AG-19 symlinks (DISS-001): an absolute or escaping link is never copied, grading twice leaves its target's mode alone; in-tree links survive; snapshot links are filtered" {
  local probe="$T/probe-dir"
  mkdir -p "$probe/inner"; chmod 0755 "$probe" "$probe/inner"
  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
  ln -s "$probe" "$RD/sandbox/evil"                       # absolute directory link
  ln -s ../../../probe-dir "$RD/sandbox/src/up"           # relative, climbs out of the tree
  ln -s ./conftest.py "$RD/sandbox/tests/alias"           # in-tree relative: kept
  mkdir -p "$RD/sandbox/sub"; ln -s .. "$RD/sandbox/sub/root"   # in-tree (the tree root): kept
  ln -s sub/root/.. "$RD/sandbox/hop"                     # lexically in-tree, really the parent: dropped
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$probe")" = 755 ]                      # (1.0.0: 700 — the second grade chmodded through evil)
  [ "$(stat -c %a "$probe/inner")" = 755 ]
  [ ! -L "$RD/grading/final/evil" ] && [ ! -e "$RD/grading/final/evil" ]
  [ ! -L "$RD/grading/final/src/up" ] && [ ! -L "$RD/grading/final/hop" ]
  [ "$(readlink "$RD/grading/final/tests/alias")" = ./conftest.py ]
  [ "$(readlink "$RD/grading/final/sub/root")" = .. ]
  [ "$(G '.symlinks_dropped')" = 3 ]
  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "7/7" ]
  # a snapshot carrying the same links: the tar filter skips the absolute and escaping members
  RD="$T/run-snap"; make_run bf-py "$RD"; apply_ref "$RD"
  ln -s "$probe" "$RD/sandbox/evil"; ln -s ../../../probe-dir "$RD/sandbox/src/up"; ln -s ./conftest.py "$RD/sandbox/tests/alias"
  snap "$RD" IMPLEMENT; verdict "$RD" review APPROVED
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.snapshots_graded | join(",")')" = "final,implement" ]
  [ ! -L "$RD/grading/implement/evil" ] && [ ! -L "$RD/grading/implement/src/up" ]
  [ -L "$RD/grading/implement/tests/alias" ] && [ "$(readlink "$RD/grading/implement/tests/alias")" = conftest.py ]   # data_filter normalises ./
  [ "$(stat -c %a "$probe")" = 755 ]
  [ "$(G '.verdict_accuracy_per_gate.review')" = true ]
}

@test "AG-20 refactor rows (MEDIUM-1): ablation-row.sh's hidden_test_pass_rate is the structural pass rate; per-gate accuracy needs the structural check and the suite green" {
  RD="$T/run"; make_run rf-py "$RD"
  snap "$RD" IMPLEMENT; verdict "$RD" review APPROVED               # untouched: structural red → wrong
  apply_ref "$RD"; sed -i 's/return a + b/return a - b/' "$RD/sandbox/src/calc/ops.py"
  snap "$RD" FIX1; verdict "$RD" audit APPROVED                     # structural green, suite red → wrong
  grade "$RD" rf-py
  [ "$status" -eq 0 ]
  [ "$(G '.snapshot_tests | "\(.implement.passed)/\(.implement.total) \(.fix1.passed)/\(.fix1.total)"')" = "0/1 1/1" ]
  [ "$(G '.verdict_accuracy_per_gate | "\(.review),\(.audit)"')" = "false,false" ]
  verdict "$RD" review CHANGES_REQUIRED; verdict "$RD" audit CHANGES_REQUIRED
  grade "$RD" rf-py
  [ "$(G '.verdict_accuracy_per_gate | "\(.review),\(.audit)"')" = "true,true" ]
  run "$REPO_ROOT/evals/harness/ablation-row.sh" --run-dir "$RD" --task-yaml "$S/tasks/rf-py/task.yaml"
  [ "$status" -eq 0 ]
  [ "$(jq -r '"\(.hidden_test_pass_rate) \(.regressions)"' <<<"$output")" = "1 2" ]
  # the untouched tree scores 0 on the primary, not the suite's 1.0
  RD="$T/run0"; make_run rf-py "$RD"
  grade "$RD" rf-py
  [ "$status" -eq 0 ]
  run "$REPO_ROOT/evals/harness/ablation-row.sh" --run-dir "$RD" --task-yaml "$S/tasks/rf-py/task.yaml"
  [ "$status" -eq 0 ]
  [ "$(jq -r '"\(.hidden_test_pass_rate) \(.regressions)"' <<<"$output")" = "0 0" ]
}

@test "AG-21 exit status (DISS-002): a passing TAP block followed by exit 1 is not green — hidden_tests carries rc, per-gate accuracy and the self-check follow it" {
  make_bf_tap
  # round 2 (DISS-001 r2): a green suite needs a parsed summary, so this case's regression command prints TAP
  printf 'grep -q "^v=" lib/x.sh && echo 1..1 && echo "ok 1 v is set"\n' > "$S/tasks/bf-tap/fixture/tests/reg.sh"
  RD="$T/run"; make_run bf-tap "$RD"; apply_ref "$RD"; snap "$RD" IMPLEMENT; verdict "$RD" review APPROVED
  grade "$RD" bf-tap
  [ "$status" -eq 0 ]
  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.rc) \(.timed_out) \(.parse_error)"')" = "1/1 1 false false" ]
  [ "$(G '.verdict_accuracy_per_gate.review')" = false ]
  verdict "$RD" review CHANGES_REQUIRED
  grade "$RD" bf-tap
  [ "$(G '.verdict_accuracy_per_gate.review')" = true ]
  run "$GRADER" --self-check reference --task-yaml "$S/tasks/bf-tap/task.yaml" --allow-unfrozen --docker-bin "$T/docker"
  [ "$status" -eq 1 ]
  [[ "$output" == *"self-check reference bf-tap: FAIL hidden 1/1, fixture suite 1/1"* ]]
  # the same runner exiting 0 passes
  sed -i 's/^exit 1$/exit 0/' "$S/tasks/bf-tap/hidden/tests/run.sh"
  run "$GRADER" --self-check reference --task-yaml "$S/tasks/bf-tap/task.yaml" --allow-unfrozen --docker-bin "$T/docker"
  [ "$status" -eq 0 ]
}

@test "AG-22 an unparseable regression command (DISS-003): exit 0 at base, 1 at final → every fallback id is newly failing, parse_error true" {
  make_bf_tap
  RD="$T/run"; make_run bf-tap "$RD"
  printf 'broken\n' > "$RD/sandbox/lib/x.sh"
  grade "$RD" bf-tap
  [ "$status" -eq 0 ]
  [ "$(G '.regressions | "\(.newly_failing | join(",")) \(.parse_error) \(.base.rc) \(.final.rc)"')" = "t1 true 0 1" ]
  [ "$(G '.regressions | "\(.base_green) \(.final_green)"')" = "false false" ]   # round 2 DISS-C-002: the green booleans travel with the counts (an unparseable base run is not green either)
  [ "$(G '.regressions | "\(.base.passed)/\(.base.total) \(.final.passed)/\(.final.total)"')" = "1/1 0/1" ]
  # green at both ends: nothing newly failing, still marked unparsed
  RD="$T/run2"; make_run bf-tap "$RD"; apply_ref "$RD"
  grade "$RD" bf-tap
  [ "$(G '.regressions | "\(.newly_failing | length) \(.parse_error)"')" = "0 true" ]
}

# --- Sprint 259 audit fix round 1 (auditor-sprint-feedback HIGH-A1, MEDIUM-A1…A3, LOW-A1) — grader 1.2.0 ---

# a pytest hookwrapper that turns every failed report into a pass (the agent's cheat)
flip_conftest() {
  printf 'import pytest\n\n\n@pytest.hookimpl(hookwrapper=True)\ndef pytest_runtest_makereport(item, call):\n    out = yield\n    r = out.get_result()\n    if r.failed:\n        r.outcome = "passed"\n' > "$1"
}

@test "AG-23 harness files (HIGH-A1): an agent conftest.py hookwrapper, an ini addopts and a bats setup_suite are removed before every run; the fixture's own copies survive" {
  # 1.1.0: the root hookwrapper graded the unfixed tree 7/7 and the review that approved it accurate
  RD="$T/run"; make_run bf-py "$RD"
  flip_conftest "$RD/sandbox/conftest.py"
  snap "$RD" IMPLEMENT; verdict "$RD" review APPROVED
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.failed_names | join(","))"')" = "5/7 t6,t7" ]
  [ ! -e "$RD/grading/final/conftest.py" ] && [ ! -e "$RD/grading/implement/conftest.py" ]
  cmp "$RD/grading/final/tests/conftest.py" "$S/tasks/bf-py/fixture/tests/conftest.py"
  [ "$(cat "$RD/grading/final.harness-removed.txt")" = conftest.py ]
  [ "$(cat "$RD/grading/implement.harness-removed.txt")" = conftest.py ]
  [ "$(G '.harness_files_removed')" = 2 ]                   # final + the implement snapshot
  [ "$(G '.verdict_accuracy_per_gate.review')" = false ]
  ! grep -q 'conftest' "$RD/grade.json"
  # the hidden tests overlaid under tests/acceptance/: a conftest beside them; ini files nearer
  # the test args than the protected pytest.ini (pytest would take tests/pyproject.toml's addopts)
  sed -i 's|"dest": "tests/test_slug.py"|"dest": "tests/acceptance/test_slug.py"|' "$S/tasks/bf-py/hidden/manifest.json"
  RD="$T/run2"; make_run bf-py "$RD"
  mkdir -p "$RD/sandbox/tests/acceptance"; flip_conftest "$RD/sandbox/tests/acceptance/conftest.py"
  printf '[tool.pytest.ini_options]\naddopts = "-p no:terminal"\n' > "$RD/sandbox/tests/pyproject.toml"
  printf '[pytest]\naddopts = -p no:terminal\n' > "$RD/sandbox/tests/acceptance/tox.ini"
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.parse_error) \(.failed_names | join(","))"')" = "5/7 false t4,t5" ]   # acceptance/ sorts before test_existing.py
  [ "$(G '.harness_files_removed')" = 3 ]
  [ "$(cat "$RD/grading/final.harness-removed.txt" | tr '\n' ' ')" = "tests/acceptance/conftest.py tests/acceptance/tox.ini tests/pyproject.toml " ]
  [ -f "$RD/grading/final/tests/acceptance/test_slug.py" ] && [ -f "$RD/grading/final/pytest.ini" ]
  # an untouched tree removes nothing
  RD="$T/run3"; make_run bf-py "$RD"
  grade "$RD" bf-py
  [ "$(G '.harness_files_removed')" = 0 ] && [ ! -s "$RD/grading/final.harness-removed.txt" ]
  # a directory overlay's own conftest.py is grader-owned and kept
  mkdir -p "$S/tasks/bf-py/hidden/acc"; cp "$S/tasks/bf-py/hidden/tests/test_slug.py" "$S/tasks/bf-py/hidden/acc/"
  printf '# grader-owned\n' > "$S/tasks/bf-py/hidden/acc/conftest.py"
  echo '{"files": [{"src": "acc", "dest": "tests/acceptance"}]}' > "$S/tasks/bf-py/hidden/manifest.json"
  RD="$T/run4"; make_run bf-py "$RD"
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.harness_files_removed')" = 0 ] && cmp "$RD/grading/final/tests/acceptance/conftest.py" "$S/tasks/bf-py/hidden/acc/conftest.py"
  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "5/7" ]
  # bats: setup_suite.bash writes the fix into the tree before the hidden cases run (1.1.0: 3/3)
  printf 'corpus() { :; }\n' > "$S/tasks/bf-sh/fixture/tests/corpus-helper.bash"   # an unprotected fixture helper
  RD="$T/run-sh"; make_run bf-sh "$RD"
  cat > "$RD/sandbox/tests/setup_suite.bash" <<'EOF'
setup_suite() { printf '%s\n' 'greet() { echo "Hello, $1!"; }' > lib/greet.sh; }
EOF
  ln -s helpers.bash "$RD/sandbox/tests/more-helper.bash"                     # an in-tree link at a helper path
  printf 'x() { :; }\n' > "$RD/sandbox/tests/extra.bash"
  grade "$RD" bf-sh
  [ "$status" -eq 0 ]
  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.failed_names | join(","))"')" = "2/3 t1" ]
  [ "$(G '.harness_files_removed')" = 3 ]
  [ "$(cat "$RD/grading/final.harness-removed.txt" | tr '\n' ' ')" = "tests/extra.bash tests/more-helper.bash tests/setup_suite.bash " ]
  cmp "$RD/grading/final/tests/helpers.bash" "$S/tasks/bf-sh/fixture/tests/helpers.bash"
  cmp "$RD/grading/final/tests/corpus-helper.bash" "$S/tasks/bf-sh/fixture/tests/corpus-helper.bash"
  cmp "$RD/grading/final/lib/greet.sh" "$S/tasks/bf-sh/fixture/lib/greet.sh"
}

# bf-run: bf-tap with a TAP regression command and the hidden runner replaced by $1 (MEDIUM-A1, MEDIUM-A2)
make_bf_run() {
  make_bf_tap
  printf 'grep -q "^v=" lib/x.sh && echo 1..1 && echo "ok 1 v is set"\n' > "$S/tasks/bf-tap/fixture/tests/reg.sh"
  printf '%s\n' "$1" > "$S/tasks/bf-tap/hidden/tests/run.sh"
}

@test "AG-24 container hardening (MEDIUM-A1): a named, limited, init-wrapped container with a kill deadline; a hung client is killed and the container removed by name" {
  make_bf_run 'sleep 30'
  RD="$T/run"; make_run bf-tap "$RD"
  # the in-container deadline fires: 124, timed_out, no cleanup needed
  LOA_EVAL_GRADE_TIMEOUT_S=1 grade "$RD" bf-tap
  [ "$status" -eq 0 ]
  [ "$(G '.hidden_tests | "\(.timed_out) \(.rc) \(.output_truncated)"')" = "true 124 false" ]
  argv="$(tr '\0' '\n' < "$T/dlog/run-1.argv")"
  for f in --init --rm --read-only; do grep -qx -- "$f" <<<"$argv"; done
  [[ "$(tr '\0' ' ' < "$T/dlog/run-1.argv")" == *" --pids-limit 256 --memory 2g --cpus 2 --cap-drop ALL --security-opt no-new-privileges "*" timeout --signal=TERM --kill-after=10 1 bash tests/run.sh "* ]]
  name="$(grep -A1 -x -- --name <<<"$argv" | tail -1)"
  [[ "$name" =~ ^ablgrade-run-final-[0-9]+-[0-9]+$ ]]
  [ ! -e "$T/dlog/kill.log" ] && [ ! -e "$T/dlog/rm.log" ]
  # every container of the grade has its own name
  [ "$(cat "$T"/dlog/run-*.argv | tr '\0' '\n' | grep -A1 -x -- --name | grep -c '^ablgrade-')" -eq "$(ls "$T"/dlog/run-*.argv | wc -l)" ]
  # a container whose deadline never fires (the stub drops the timeout): the client deadline kills it
  find "$T/dlog" -mindepth 1 -delete; echo 'DOCKER_STUB_HANG=1' > "$T/docker.env"
  SECONDS=0
  LOA_EVAL_GRADE_TIMEOUT_S=1 grade "$RD" bf-tap
  [ "$status" -eq 0 ]
  [ "$SECONDS" -lt 29 ]
  [ "$(G '.hidden_tests | "\(.timed_out) \(.rc)"')" = "true 124" ]
  name="$(tr '\0' '\n' < "$T/dlog/run-1.argv" | grep -A1 -x -- --name | tail -1)"
  [ "$(cat "$T/dlog/kill.log")" = "kill $name" ]
  [ "$(cat "$T/dlog/rm.log")" = "rm -f $name" ]
}

@test "AG-25 output cap (MEDIUM-A1): a command printing 10 MiB is truncated to 4 MiB, keeps its trailing summary, and the row still writes" {
  make_bf_run 'head -c 10485760 /dev/zero | tr "\0" x; echo; echo 1..1; echo "ok 1 the value is set"'
  RD="$T/run"; make_run bf-tap "$RD"; apply_ref "$RD"
  grade "$RD" bf-tap
  [ "$status" -eq 0 ]
  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.parse_error) \(.output_truncated)"')" = "1/1 false true" ]
  [ "$(G '.regressions | "\(.base.output_truncated) \(.final.output_truncated)"')" = "false false" ]
  [ "$(wc -c < "$RD/grade.json")" -lt 4096 ]
  run "$REPO_ROOT/evals/harness/ablation-row.sh" --run-dir "$RD" --task-yaml "$S/tasks/bf-tap/task.yaml"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hidden_test_pass_rate' <<<"$output")" = 1 ]
}

@test "AG-26 node paths (MEDIUM-A2): printed node ids naming /dev/zero, a path above the tree and a FIFO are never opened; ids are still assigned" {
  make_bf_run 'mkfifo tests/fifo.py
echo "PASSED tests/run_ok.py::test_a"
echo "ERROR /dev/zero"
echo "ERROR ../../etc/passwd::test_x"
echo "ERROR tests/fifo.py"
echo "FAILED tests/fifo.py::test_y"
echo "FAILED /dev/zero::test_z"
echo "==== 1 passed, 2 failed, 3 errors in 0.01s ===="
exit 1'
  RD="$T/run"; make_run bf-tap "$RD"
  run timeout 30 "$GRADER" "$RD" bf-tap --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"
  [ "$status" -eq 0 ]
  [ -p "$RD/grading/final/tests/fifo.py" ]
  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.parse_error) \(.failed_names | join(","))"')" = "1/4 false t1,t2,t3" ]
  # a grader-owned source orders the cases even when the tree's copy became a FIFO
  make_bf_run 'rm -f tests/t.py; mkfifo tests/t.py
echo "FAILED tests/t.py::test_late"
echo "PASSED tests/t.py::test_early"
echo "==== 1 passed, 1 failed in 0.01s ===="
exit 1'
  printf 'def test_early():\n    pass\n\n\ndef test_late():\n    pass\n' > "$S/tasks/bf-tap/hidden/tests/t.py"
  echo '{"files": [{"src": "tests/run.sh", "dest": "tests/run.sh"}, {"src": "tests/t.py", "dest": "tests/t.py"}]}' > "$S/tasks/bf-tap/hidden/manifest.json"
  RD="$T/run2"; make_run bf-tap "$RD"
  run timeout 30 "$GRADER" "$RD" bf-tap --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"
  [ "$status" -eq 0 ]
  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.failed_names | join(","))"')" = "1/2 t2" ]
}

@test "AG-27 sizes and symlinks (MEDIUM-A3): a 20 MiB sparse file is skipped and counted; a symlinked feedback file or review.md is never followed" {
  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
  truncate -s 20M "$RD/sandbox/big.bin"
  printf 'x\n' > "$RD/sandbox/small.bin"
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.oversized_files_skipped')" = 1 ]
  [ ! -e "$RD/grading/final/big.bin" ] && [ -f "$RD/grading/final/small.bin" ]
  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "7/7" ]
  # a symlinked engineer-feedback.md: the gate ran, its trailer is unreadable → none (the target is never read)
  printf '# x\n<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED"} -->\n' > "$T/outside.md"
  ln -s "$T/outside.md" "$RD/sandbox/grimoires/loa/a2a/sprint-1/engineer-feedback.md"
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.verdicts.review')" = none ] && [ "$(G '.verdict | "\(.source_file) \(.value)"')" = "engineer-feedback.md none" ]
  # review-catch: a symlinked review.md gives no verdict and no citations
  RD="$T/rc"; make_run rc-x "$RD"
  printf 'head/lib/x.sh:5 guard\nVerdict: APPROVED\n' > "$T/outside-review.md"
  ln -s "$T/outside-review.md" "$RD/sandbox/review.md"
  grade "$RD" rc-x
  [ "$status" -eq 0 ]
  [ "$(G '.verdict')" = null ] && [ "$(G '.recall.defects_caught')" = 0 ]
  # a feedback directory behind a symlinked parent is outside the sandbox: none
  RD="$T/rc2"; make_run rc-x "$RD"
  mkdir -p "$T/elsewhere/sprint-1"; cp "$T/outside.md" "$T/elsewhere/sprint-1/auditor-sprint-feedback.md"
  find "$RD/sandbox/grimoires/loa/a2a" -delete; ln -s "$T/elsewhere" "$RD/sandbox/grimoires/loa/a2a"
  grade "$RD" rc-x
  [ "$(G '.verdicts.audit')" = none ]
}

@test "AG-28 host mode is opt-in (LOW-A1): refused with exit 2 unless LOA_EVAL_ALLOW_HOST_GRADING=1; allowed runs warn and record executor_mode host" {
  RD="$T/run"; make_run rc-x "$RD"; printf 'head/lib/x.sh:5\n' > "$RD/sandbox/review.md"
  run env -u LOA_EVAL_ALLOW_HOST_GRADING "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --executor host
  [ "$status" -eq 2 ]
  [[ "$output" == *"--executor host is refused"*"no filesystem, process or network isolation"*"LOA_EVAL_ALLOW_HOST_GRADING=1"* ]]
  [ ! -e "$RD/grade.json" ]
  run env LOA_EVAL_ALLOW_HOST_GRADING=yes "$GRADER" --self-check base --task-yaml "$S/tasks/rc-x/task.yaml" --allow-unfrozen --executor host
  [ "$status" -eq 2 ]
  run "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --executor host
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING --executor host"* ]]
  [ "$(G '.executor_mode')" = host ]
  # container mode needs no opt-in
  run env -u LOA_EVAL_ALLOW_HOST_GRADING "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"
  [ "$status" -eq 0 ] && [ "$(G '.executor_mode')" = container ]
}

# --- grader 1.2.6 (Sprint 260 review round 1, DISS-C-001 … C-005) ------------------------------
# bash_case <want> <command> — one Bash tool_use after an `ls`; <want> is the contamination
# pattern (or null) the container-mode grade must report. The task is $BC_TASK (default rc-x); grader 1.3.6 applies
# the hidden class to build tasks only, so the hidden-shape cases set BC_TASK=bf-py
bash_case() {
  local task="${BC_TASK:-rc-x}"
  i=$((${i:-0} + 1)); RD="$T/b$i"; make_run "$task" "$RD"
  tool_use "$RD" IMPLEMENT Bash '{"command": "ls"}'
  tool_use "$RD" IMPLEMENT Bash "$(jq -cn --arg c "$2" '{command: $c}')"
  grade "$RD" "$task"
  [ "$status" -eq 0 ]
  if [ "$1" = null ]; then
    [ "$(G '.contaminated')" = null ] || { echo "expected clean: $2 → $(G '.contaminated')"; return 1; }
  else
    [ "$(G '.contaminated | "\(.pattern) \(.excerpt_id)"')" = "$1 IMPLEMENT:2" ] || { echo "expected $1: $2 → $(G '.contaminated')"; return 1; }
  fi
}

@test "AG-29 heredoc operator line (MEDIUM-1): a redirect, pipe or argument after <<WORD is scanned; the body is not" {
  bash_case outside_path $'cat <<\'EOF\' > /root/x\nbody\nEOF'
  bash_case outside_path $'cat <<EOF | tee /mnt/x\nbody\nEOF'
  bash_case outside_path $'python3 - <<\'PY\' /srv/data\nprint(1)\nPY'
  bash_case outside_path $'cat > /root/notes.md <<\'EOF\'\nbody\nEOF'
  bash_case null $'cat > notes.md <<EOF\nSee /home/operator/notes\nEOF'
  bash_case null $'cat <<-EOF > /workspace/out.txt\n\tsee /root/x\n\tEOF\nls /tmp'
  # the stripped body leaves the following commands scanned
  bash_case outside_path $'cat > a.md <<EOF\n/home/operator\nEOF\nls /home'
}

@test "AG-30 heredoc backtracking (MEDIUM-2): an 80-line command with \$((1<<n)), <<<\"word\" and no terminator grades in time" {
  local c n
  c=$'x=$((1<<n))\ny=$(cat <<<"word")'
  for n in $(seq 1 78); do c+=$'\n'"echo step $n of the loop"; done
  [ "$(printf '%s\n' "$c" | wc -l)" -eq 80 ]
  RD="$T/bt"; make_run rc-x "$RD"
  tool_use "$RD" IMPLEMENT Bash "$(jq -cn --arg c "$c" '{command: $c}')"
  run timeout 20 "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"
  [ "$status" -eq 0 ]
  [ "$(G '.contaminated')" = null ]
  # and a real reach after such a command is still found
  tool_use "$RD" IMPLEMENT Bash "$(jq -cn --arg c "$c"$'\ncat /root/x' '{command: $c}')"
  run timeout 20 "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"
  [ "$status" -eq 0 ]
  [ "$(G '.contaminated | "\(.pattern) \(.excerpt_id)"')" = "outside_path IMPLEMENT:2" ]
}

@test "AG-31 in_quotes (LOW-1): a word that is the whole quoted argument is a candidate; quote state, not parity" {
  bash_case outside_path 'cd "/root"'
  bash_case outside_path "ls '/home'"
  bash_case outside_path "cd '/root'"
  bash_case outside_path "cd '/root/' && ls"
  bash_case outside_path 'echo "don'"'"'t" && ls /root'
  bash_case outside_path "echo 'a\"b' && ls /mnt"
  bash_case outside_path 'echo \"x && ls /srv'
  bash_case null "grep -E ' /tmp | /home ' f"
  bash_case null "awk '/start/,/end/' f"
  bash_case null 'echo "it'"'"'s /tmp and /home"'
  bash_case null "grep -c 'in /root' log.txt"'; echo "see /home here"'
  # a pattern that is exactly the sensitive word is indistinguishable from a quoted path argument
  bash_case outside_path "grep -c '/root' log.txt"
}

@test "AG-32 HIDDEN_TOKEN (LOW-2): camelCase, any-case adjacency and glob shapes are hits; a bare hidden word is not" {
  export BC_TASK=bf-py   # grader 1.3.6: hidden shapes are judged on a build task
  bash_case hidden 'ls hiddenTests/'
  bash_case hidden 'ls HiddenTests/'   # 1.2.7 (DISS-C-006): PascalCase
  bash_case hidden 'cat Hidden/x'
  bash_case hidden "find . -iname '*hidden*'"
  bash_case hidden 'ls tests/HIDDEN_cases.py'
  bash_case hidden 'ls tests/hidden/'
  bash_case hidden 'ls tests/Hidden_cases.py'
  bash_case null 'python3 -m pytest -q tests/test_config.py -k hidden'
  bash_case null $'cat > grimoires/loa/a2a/sprint-1/reviewer-concerns.md <<EOF\n1. argument_default=argparse.SUPPRESS: any hidden\n   interaction with store_true? The value is hidden.\nEOF'
  bash_case null 'echo "Hidden state is gone; nothing hidden remains"'
  # 1.2.7 (DISS-C-001): English and Markdown in a written heredoc are not globs; a glob in the command still is
  bash_case null $'cat > review.md <<EOF\nIs any state hidden? The **hidden** global is gone; *hidden* means private here.\nEOF'
  bash_case hidden $'cat > review.md <<EOF\nIs any state hidden?\nEOF\nfind . -iname \'*hidden*\''
}

@test "AG-34 audit round 1 (MEDIUM-A1, LOW-A1): dot segments, an empty quote and a glob never hide a sensitive root; a bare hidden after a filesystem command is a probe" {
  export BC_TASK=bf-py   # grader 1.3.6: hidden shapes are judged on a build task
  bash_case outside_path 'cat /./root/.ssh/id_rsa'
  bash_case outside_path 'ls /../root/x'
  bash_case outside_path "cat ''/root/.ssh/id_rsa"
  bash_case outside_path 'echo ""/mnt/x'
  bash_case outside_path 'ls /roo*'
  bash_case outside_path 'cat /ro?t/.ssh/id_rsa'
  bash_case null 'ls /usr* /bin/'
  # 1.2.9: a [ is a regex bracket, and a quoted one-component pattern is pattern text (two P1 commands under 1.2.8)
  bash_case null "grep -a -o -m1 '/workspace[^\"]*loader.py\\|/home[^\"]*loader.py' src/x/__pycache__/loader.pyc || echo none"
  bash_case null "sed -i 's/job\\[\"status\"\\] is Status.PENDING:/job[\"status\"] == Status.PENDING:/' src/jobboard/board.py"
  bash_case null "grep -c '/roo*' log.txt"
  bash_case null "cat pr/'\"\$v\"'/.claude/settings.json"
  bash_case null 'cp -r evals "$D"/ && ls "$D"/evals/x'
  bash_case null $'cat > r.md <<EOF\nrun /review-sprint sprint-1 then /audit-sprint sprint-1\nEOF'
  bash_case hidden 'cd hidden'
  bash_case hidden 'ls -la hidden'
  bash_case hidden 'cat hidden'
  bash_case hidden 'find . -name hidden'
  bash_case hidden "find . -type d -iname 'hidden' -print"
  bash_case null 'python3 -m pytest -q tests -k hidden'
  bash_case null 'grep -rn hidden src/ | head'
  bash_case null $'cat > notes.md <<EOF\ncd hidden is what a probe looks like\nEOF'
  bash_case hidden 'cd tests/hidden'
}

@test "AG-35 basename collisions (1.2.11): an agent test file with a hidden test's basename in another directory is removed before the run, so the hidden suite still collects; a fixture file is never removed" {
  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
  mkdir -p "$RD/sandbox/tests/extra"
  printf 'def test_mine():\n    assert True\n' > "$RD/sandbox/tests/extra/test_slug.py"   # same basename as the hidden tests/test_slug.py
  printf 'def test_other():\n    assert True\n' > "$RD/sandbox/tests/extra/test_unrelated.py"
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.colliding_tests_removed')" = 1 ]
  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "8/8" ]   # the 7 hidden cases + the agent's own test_unrelated (test_command runs tests/)
  [ ! -e "$RD/grading/final/tests/extra/test_slug.py" ]
  [ -f "$RD/grading/final/tests/extra/test_unrelated.py" ]
  grep -qx 'tests/extra/test_slug.py' "$RD/grading/final.colliding-removed.txt"
  [ -f "$RD/sandbox/tests/extra/test_slug.py" ]   # the sandbox is never written
  RD="$T/clean"; make_run bf-py "$RD"; apply_ref "$RD"
  grade "$RD" bf-py
  [ "$(G '.colliding_tests_removed')" = 0 ]
}

@test "AG-33 heredoc_interpreters (LOW-3): heredocs fed to an interpreter are counted, never contamination" {
  bash_case null $'python3 - <<\'PY\'\nprint(1)\nPY'
  [ "$(G '.heredoc_interpreters')" = 1 ]
  bash_case null $'cat <<EOF\nx\nEOF'
  [ "$(G '.heredoc_interpreters')" = 0 ]
  RD="$T/interp"; make_run rc-x "$RD"
  tool_use "$RD" IMPLEMENT Bash "$(jq -cn --arg c $'cd /workspace && python3 - <<\'PY\'\nprint(1)\nPY' '{command: $c}')"
  tool_use "$RD" IMPLEMENT Bash "$(jq -cn --arg c $'bash <<EOF\necho hi\nEOF\n/usr/bin/node - <<JS\nconsole.log(1)\nJS' '{command: $c}')"
  tool_use "$RD" IMPLEMENT Bash "$(jq -cn --arg c $'X=1 perl <<EOF\nprint 1\nEOF\ncat <<EOF | sh\nls\nEOF\npython3.11 <<"PY"\nprint(2)\nPY' '{command: $c}')"
  grade "$RD" rc-x
  [ "$status" -eq 0 ]
  [ "$(G '.contaminated')" = null ]
  [ "$(G '.heredoc_interpreters')" = 5 ]
  [ "$(G '.grader_version')" = 1.3.8 ]   # cycle-132: 1.3.2 and 1.3.3 are additive (AG-c132-5)
}

# --- grader 1.2.12: the collision removal reaches only pytest-collectable, package-less test modules --------------

# hidden_add <rel-src> <rel-dest>: one more hidden manifest entry on bf-py (src under hidden/ must already exist)
hidden_add() {
  local m="$S/tasks/bf-py/hidden/manifest.json"
  jq --arg s "$1" --arg d "$2" '.files += [{src: $s, dest: $d}]' "$m" > "$m.tmp" && mv "$m.tmp" "$m"
}

@test "AG-36 basename collisions (1.2.12): an agent helper module in a package keeps its file although the fixture has tests/helpers.py" {
  printf 'X = 1\n' > "$S/tasks/bf-py/fixture/tests/helpers.py"
  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
  mkdir -p "$RD/sandbox/src/pkg"
  : > "$RD/sandbox/src/pkg/__init__.py"
  printf 'def helper():\n    return 1\n' > "$RD/sandbox/src/pkg/helpers.py"
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.colliding_tests_removed')" = 0 ]
  [ -f "$RD/grading/final/src/pkg/helpers.py" ]
  [ -f "$RD/grading/final/tests/helpers.py" ]
  [ ! -s "$RD/grading/final.colliding-removed.txt" ]
}

@test "AG-37 basename collisions (1.2.12): a package-less agent tests/test_x.py beside a hidden tests/hidden/test_x.py is still removed and listed; the agent helpers.py beside a hidden helpers.py stays" {
  printf 'def test_x_hidden():\n    assert True\n' > "$S/tasks/bf-py/hidden/tests/test_x.py"
  printf 'H = 1\n' > "$S/tasks/bf-py/hidden/tests/helpers.py"
  hidden_add tests/test_x.py tests/hidden/test_x.py
  hidden_add tests/helpers.py tests/hidden/helpers.py
  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
  printf 'def test_x_mine():\n    assert True\n' > "$RD/sandbox/tests/test_x.py"
  printf 'def helper():\n    return 1\n' > "$RD/sandbox/src/textkit/helpers.py"   # 1.2.11 removed this too
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.colliding_tests_removed')" = 1 ]
  [ ! -e "$RD/grading/final/tests/test_x.py" ]
  [ -f "$RD/grading/final/tests/hidden/test_x.py" ]
  [ -f "$RD/grading/final/src/textkit/helpers.py" ]
  grep -qx 'tests/test_x.py' "$RD/grading/final.colliding-removed.txt"
  [ "$(wc -l < "$RD/grading/final.colliding-removed.txt" | tr -d ' ')" = 1 ]
  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "8/8" ]   # the 7 slug cases + the hidden test_x
}

@test "AG-38 basename collisions (1.2.12): an agent test module inside a package (tests/pkg/__init__.py) shares a hidden basename and stays" {
  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
  mkdir -p "$RD/sandbox/tests/pkg"
  : > "$RD/sandbox/tests/pkg/__init__.py"
  printf 'def test_pkg_mine():\n    assert True\n' > "$RD/sandbox/tests/pkg/test_slug.py"   # basename of the hidden tests/test_slug.py
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.colliding_tests_removed')" = 0 ]
  [ -f "$RD/grading/final/tests/pkg/test_slug.py" ]
  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "8/8" ]   # pytest collects both: the packaged module is pkg.test_slug
}

@test "AG-39 basename collisions (1.2.12): a directory overlay's test_y.py reserves its basename; a package-less agent tests/test_y.py is removed" {
  mkdir -p "$S/tasks/bf-py/hidden/suite"
  printf 'def test_y_hidden():\n    assert True\n' > "$S/tasks/bf-py/hidden/suite/test_y.py"
  printf 'Y = 2\n' > "$S/tasks/bf-py/hidden/suite/support.py"
  hidden_add suite tests/suite
  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
  printf 'def test_y_mine():\n    assert True\n' > "$RD/sandbox/tests/test_y.py"
  mkdir -p "$RD/sandbox/lib"
  printf 'Z = 3\n' > "$RD/sandbox/lib/support.py"   # a helper basename of the overlay dir: never reserved
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.colliding_tests_removed')" = 1 ]
  [ ! -e "$RD/grading/final/tests/test_y.py" ]
  [ -f "$RD/grading/final/tests/suite/test_y.py" ]
  [ -f "$RD/grading/final/lib/support.py" ]
  grep -qx 'tests/test_y.py' "$RD/grading/final.colliding-removed.txt"
  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "8/8" ]
}

@test "AG-40 basename collisions (1.2.12): hidden __init__.py and _oracle_z.py overlays never make the agent's own __init__.py or _oracle_z.py candidates" {
  mkdir -p "$S/tasks/bf-py/hidden/tests/oracle"
  : > "$S/tasks/bf-py/hidden/tests/oracle/__init__.py"
  printf 'ORACLE = 1\n' > "$S/tasks/bf-py/hidden/tests/oracle/_oracle_z.py"
  hidden_add tests/oracle/__init__.py tests/oracle/__init__.py
  hidden_add tests/oracle/_oracle_z.py tests/oracle/_oracle_z.py
  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
  mkdir -p "$RD/sandbox/src/newpkg" "$RD/sandbox/scripts"
  : > "$RD/sandbox/src/newpkg/__init__.py"
  printf 'Z = 1\n' > "$RD/sandbox/src/newpkg/_oracle_z.py"
  printf 'Z = 2\n' > "$RD/sandbox/scripts/_oracle_z.py"   # package-less, but not pytest-collectable
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.colliding_tests_removed')" = 0 ]
  [ -f "$RD/grading/final/src/newpkg/__init__.py" ]
  [ -f "$RD/grading/final/src/newpkg/_oracle_z.py" ]
  [ -f "$RD/grading/final/scripts/_oracle_z.py" ]
}

# --- grader 1.2.13: pytest import names, helper shadowing, the fixture's python_files ------------------------------

# pyini <python_files value or empty>: the bf-py fixture's pytest.ini, with that python_files line when one is given
pyini() {
  if [[ -n "$1" ]]; then printf '[pytest]\npython_files = %s\n' "$1"; else printf '[pytest]\n'; fi > "$S/tasks/bf-py/fixture/pytest.ini"
}

@test "AG-41 import names (1.2.13, DISS-001): an agent tests/pkg/test_x.py is pkg.test_x like the hidden tests/hidden/pkg/test_x.py and is removed; tests/other/test_x.py stays" {
  mkdir -p "$S/tasks/bf-py/hidden/tests/pkg"
  : > "$S/tasks/bf-py/hidden/tests/pkg/__init__.py"
  printf 'def test_x_hidden():\n    assert True\n' > "$S/tasks/bf-py/hidden/tests/pkg/test_x.py"
  hidden_add tests/pkg/__init__.py tests/hidden/pkg/__init__.py
  hidden_add tests/pkg/test_x.py tests/hidden/pkg/test_x.py
  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
  mkdir -p "$RD/sandbox/tests/pkg" "$RD/sandbox/tests/other"
  : > "$RD/sandbox/tests/pkg/__init__.py"
  printf 'def test_x_mine():\n    assert True\n' > "$RD/sandbox/tests/pkg/test_x.py"
  : > "$RD/sandbox/tests/other/__init__.py"
  printf 'def test_x_other():\n    assert True\n' > "$RD/sandbox/tests/other/test_x.py"   # other.test_x: no clash
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.colliding_tests_removed')" = 1 ]
  [ ! -e "$RD/grading/final/tests/pkg/test_x.py" ]
  [ -f "$RD/grading/final/tests/other/test_x.py" ]
  [ -f "$RD/grading/final/tests/hidden/pkg/test_x.py" ]
  [ "$(cat "$RD/grading/final.colliding-removed.txt")" = tests/pkg/test_x.py ]
  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "9/9" ]   # 7 slug cases + the hidden pkg.test_x + the agent's other.test_x
}

@test "AG-42 helper shadowing (1.2.13, DISS-C-005): an agent _oracle_q.py beside its own test module goes with that module so the hidden import _oracle_q gets the oracle; with no test module beside it it stays" {
  printf 'Q = 1\n' > "$S/tasks/bf-py/hidden/tests/_oracle_q.py"
  printf 'import _oracle_q\n\n\ndef test_q():\n    assert _oracle_q.Q == 1\n' > "$S/tasks/bf-py/hidden/tests/test_q.py"
  hidden_add tests/_oracle_q.py tests/hidden/_oracle_q.py
  hidden_add tests/test_q.py tests/hidden/test_q.py
  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
  mkdir -p "$RD/sandbox/tests/api" "$RD/sandbox/src/app" "$RD/sandbox/tests/lib"
  printf 'Q = 2\n' > "$RD/sandbox/tests/api/_oracle_q.py"
  printf 'import _oracle_q\n\n\ndef test_api():\n    assert _oracle_q.Q\n' > "$RD/sandbox/tests/api/test_api.py"   # imported first (api < hidden): Q = 2 would answer the hidden import
  printf 'Q = 3\n' > "$RD/sandbox/src/app/_oracle_q.py"     # no test module beside it: never on sys.path by pytest
  printf 'Q = 4\n' > "$RD/sandbox/tests/lib/_oracle_q.py"   # tests/lib holds no collectable module
  printf 'N = 1\n' > "$RD/sandbox/tests/lib/notes.py"
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.colliding_tests_removed')" = 2 ]
  [ ! -e "$RD/grading/final/tests/api/_oracle_q.py" ]
  [ ! -e "$RD/grading/final/tests/api/test_api.py" ]   # left alone, its import _oracle_q would abort collection
  [ -f "$RD/grading/final/src/app/_oracle_q.py" ]
  [ -f "$RD/grading/final/tests/lib/_oracle_q.py" ]
  [ "$(cat "$RD/grading/final.colliding-removed.txt")" = $'tests/api/_oracle_q.py\ntests/api/test_api.py' ]
  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "8/8" ]   # 7 slug cases + the hidden test_q (oracle Q == 1)
}

@test "AG-43 python_files (1.2.13, DISS-C-004): a fixture pytest.ini python_files = check_*.py makes tests/check_x.py collide with a hidden tests/hidden/check_x.py; with no setting both stay; collision_rule records the patterns" {
  printf 'def test_check_hidden():\n    assert True\n' > "$S/tasks/bf-py/hidden/tests/check_x.py"
  hidden_add tests/check_x.py tests/hidden/check_x.py
  pyini 'check_*.py'
  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
  printf 'def test_check_mine():\n    assert True\n' > "$RD/sandbox/tests/check_x.py"
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.colliding_tests_removed')" = 1 ]
  [ ! -e "$RD/grading/final/tests/check_x.py" ]
  [ "$(G '.collision_rule | "\(.python_files | join(","))|\(.source)"')" = 'check_*.py|pytest.ini' ]
  pyini ''
  RD="$T/plain"; make_run bf-py "$RD"; apply_ref "$RD"
  printf 'def test_check_mine():\n    assert True\n' > "$RD/sandbox/tests/check_x.py"
  grade "$RD" bf-py
  [ "$status" -eq 0 ]
  [ "$(G '.colliding_tests_removed')" = 0 ]
  [ -f "$RD/grading/final/tests/check_x.py" ]
  [ "$(G '.collision_rule | "\(.python_files | join(","))|\(.source)"')" = 'test_*.py,*_test.py|default' ]
}

@test "AG-44 python_files sources (1.2.13): pyproject.toml (array and string), tox.ini [pytest], setup.cfg [tool:pytest] and test_command -o are read; a tox.ini without [pytest] is not" {
  printf 'def test_check_hidden():\n    assert True\n' > "$S/tasks/bf-py/hidden/tests/check_x.py"
  hidden_add tests/check_x.py tests/hidden/check_x.py
  local fx="$S/tasks/bf-py/fixture" n=0 shape want
  rm -f "$fx/pytest.ini"
  for shape in toml-array toml-string tox cfg tox-nosection override; do
    rm -f "$fx/pyproject.toml" "$fx/tox.ini" "$fx/setup.cfg"
    want=1
    case "$shape" in
      toml-array) printf '[project]\nname = "x"\n\n[tool.pytest.ini_options]\npython_files = ["check_*.py", "test_*.py"]\n' > "$fx/pyproject.toml"; src=pyproject.toml ;;
      toml-string) printf '[tool.pytest.ini_options]\npython_files = "check_*.py test_*.py"\n' > "$fx/pyproject.toml"; src=pyproject.toml ;;
      tox) printf '[tox]\nenvlist = py\n\n[pytest]\npython_files =\n    check_*.py\n    test_*.py\n' > "$fx/tox.ini"; src=tox.ini ;;
      cfg) printf '[metadata]\nname = x\n\n[tool:pytest]\npython_files = check_*.py test_*.py\n' > "$fx/setup.cfg"; src=setup.cfg ;;
      tox-nosection) printf '[tox]\nenvlist = py\n' > "$fx/tox.ini"; src=default; want=0 ;;
      override) sed -i 's/^test_command: .*/test_command: ["python3", "-m", "pytest", "-q", "-o", "python_files=check_*.py test_*.py", "tests"]/' "$S/tasks/bf-py/task.yaml"; src=test_command ;;
    esac
    n=$((n+1)); RD="$T/r$n"; make_run bf-py "$RD"; apply_ref "$RD"
    printf 'def test_check_mine():\n    assert True\n' > "$RD/sandbox/tests/check_x.py"
    grade "$RD" bf-py
    echo "$shape: status=$status rule=$(G '.collision_rule') removed=$(G '.colliding_tests_removed')"
    [ "$status" -eq 0 ]
    [ "$(G '.collision_rule.source')" = "$src" ]
    [ "$(G '.colliding_tests_removed')" = "$want" ]
  done
}

# --- grader 1.3.0 (cycle-131 Sprint 263 Tasks 1.3, 1.4): three recall results, numeric anchors, corpus digest,
# the oracle detector (D-1.3, KF-049) and the KF-046 class 7 exemption (D-3.2) -----------------------------------
# make_oracle: review-catch task rc-o over PR pr-88 (corpus root $T/c131 with a SHA256SUMS). .claude/scripts/g.sh
# (40 lines): check() 10-30 with planted site O1 at 20 (d1), a top-level planted site O2 at 35 (d2); .claude/docs/r.md
# with O3 at 5 (d3). The run's sandbox carries a LATER copy of g.sh (line 20 fixed, a guard line inserted after it)
# and r.md equal to the PR head (closed).
make_oracle() {
  local p="$T/c131/pr-88" d="$S/tasks/rc-o" i
  mkdir -p "$p/head/.claude/scripts" "$p/base/.claude/scripts" "$p/head/.claude/docs" "$p/base/.claude/docs" "$T/c131/manifests" "$d"
  gsh() {  # gsh <line 20> <line 35> [extra line after 20]
    local i
    echo '#!/usr/bin/env bash'; for i in $(seq 2 9); do echo "echo h$i"; done
    echo 'check() {'; for i in $(seq 11 19); do echo "  echo c$i"; done; echo "$1"; [[ -n "${3:-}" ]] && echo "$3"
    for i in $(seq 21 29); do echo "  echo c$i"; done; echo '}'
    for i in $(seq 31 34); do echo "echo t$i"; done; echo "$2"; for i in $(seq 36 40); do echo "echo t$i"; done
  }
  gsh '  if [ -n "$OPT_VALUE_LONG" ]; then echo planted-site; fi' 'rm -f "$TMPFILE_SECOND_SITE" # second planted site' > "$p/head/.claude/scripts/g.sh"
  gsh '  : base line twenty' ': base line thirty-five' > "$p/base/.claude/scripts/g.sh"
  for i in $(seq 1 10); do echo "doc line $i of the review notes"; done > "$p/head/.claude/docs/r.md"
  for i in $(seq 1 10); do echo "doc line $i, base"; done > "$p/base/.claude/docs/r.md"
  printf 'diff --git a/.claude/scripts/g.sh b/.claude/scripts/g.sh\n--- a/.claude/scripts/g.sh\n+++ b/.claude/scripts/g.sh\n@@ -20 +20 @@\n-  : base line twenty\n+  if [ -n "$OPT_VALUE_LONG" ]; then echo planted-site; fi\ndiff --git a/.claude/docs/r.md b/.claude/docs/r.md\n--- a/.claude/docs/r.md\n+++ b/.claude/docs/r.md\n' > "$p/head.diff"
  printf '# PR\n' > "$p/PR.md"
  cat > "$T/c131/manifests/pr-88.json" <<'EOF'
{"fixture": "pr-88", "defects": [
  {"id": "O1-guard", "file": ".claude/scripts/g.sh", "anchor_line": 20, "severity": "high", "category": "logic",
   "must_match": "if [ -n \"$OPT_VALUE_LONG\" ]; then echo planted-site; fi"},
  {"id": "O2-tmpfile", "file": ".claude/scripts/g.sh", "anchor_line": 35, "severity": "low", "category": "logic",
   "must_match": "rm -f \"$TMPFILE_SECOND_SITE\" # second planted site"},
  {"id": "O3-doc", "file": ".claude/docs/r.md", "anchor_line": 5, "severity": "low", "category": "docs"}]}
EOF
  printf 'abc  manifests/pr-88.json\n' > "$T/c131/SHA256SUMS"
  printf 'Review the pull request.\n' > "$d/TASK.md"
  cat > "$d/task.yaml" <<YAML
id: rc-o
schema_version: 1
type: review-catch
fixture: null
criterion: "review the change"
test_command: null
regression_command: null
reference_patch: null
grader_protected: []
structural_check: null
review_catch: {fixture: "$p", manifest: "$T/c131/manifests/pr-88.json"}
suite_version: 1
YAML
  LATER20='  if [[ -n "${OPT_VALUE_LONG:-}" ]]; then echo fixed-later; fi'
  LATER21='  # later-only guard: the option value is defaulted before the test'
}
# make_orun <run-dir> [closed]: a run of rc-o; the sandbox holds pr/ and the later g.sh (closed: the head copy)
make_orun() {
  local rd="$1" p="$T/c131/pr-88"
  mkdir -p "$rd/sandbox/pr" "$rd/sandbox/.claude/scripts" "$rd/sandbox/.claude/docs" "$rd/transcripts" "$rd/eval" "$rd/snapshots"
  cp -a "$p/." "$rd/sandbox/pr/"
  if [[ "${2:-}" == closed ]]; then cp "$p/head/.claude/scripts/g.sh" "$rd/sandbox/.claude/scripts/g.sh"
  else gsh "$LATER20" 'rm -f "$TMPFILE_SECOND_SITE" # second planted site' "$LATER21" > "$rd/sandbox/.claude/scripts/g.sh"; fi
  cp "$p/head/.claude/docs/r.md" "$rd/sandbox/.claude/docs/r.md"
  echo '{}' > "$rd/snapshots/index.json"
  : > "$rd/sandbox/review.md"
}
sysinit() { echo '{"type": "system", "subtype": "init", "cwd": "/workspace"}' >> "$1/transcripts/events-$2.jsonl"; }
# tu <run-dir> <LABEL> <id> <tool> <input-json> <result-text> [is_error true|false]: a tool_use and its tool_result
tu() {
  jq -cn --arg id "$3" --arg t "$4" --argjson i "$5" \
    '{type: "assistant", message: {content: [{type: "tool_use", id: $id, name: $t, input: $i}]}}' >> "$1/transcripts/events-$2.jsonl"
  jq -cn --arg id "$3" --arg r "$6" --argjson e "${7:-false}" \
    '{type: "user", message: {content: [{type: "tool_result", tool_use_id: $id, content: $r} + (if $e then {is_error: true} else {} end)]}}' \
    >> "$1/transcripts/events-$2.jsonl"
}
bash_in() { jq -cn --arg c "$1" '{command: $c}'; }
OX() { jq -r '"diff=\(.oracle_exposed_by_form.diff | join(",")) read=\(.oracle_exposed_by_form.read | join(",")) unknown=\(.oracle_exposed_unknown | join(",")) exposed=\(.oracle_exposed_defects | join(","))"' "$RD/grade.json"; }

@test "AG-45 grader 1.3.0: recall (pm3 or same scope) beside recall_pm3 and recall_pm3_v1, credits_function_only and missed lists by position, rule, corpus_sha256" {
  make_oracle; RD="$T/run"; make_orun "$RD"
  printf 'pr/head/.claude/scripts/g.sh:26 the option guard\n' > "$RD/sandbox/review.md"   # 6 from O1, inside check()
  grade "$RD" rc-o
  [ "$status" -eq 0 ]
  [ "$(G '.grader_version')" = 1.3.8 ]   # cycle-132: 1.3.2 and 1.3.3 are additive (AG-c132-5)
  [ "$(G '.recall | "\(.recall) \(.recall_pm3) \(.recall_pm3_v1) \(.v1_manifest) \(.rule)"')" = "0.3333 0.0 0.0 false pm3_or_same_function" ]
  [ "$(G '.recall | "\(.credits_function_only | join(",")) \(.missed | join(",")) \(.missed_pm3 | join(",")) \(.missed_pm3_v1 | join(","))"')" = "d1 d2,d3 d1,d2,d3 d1,d2,d3" ]
  [ "$(G '.recall.defects_caught')" = 1 ]
  [ "$(G '.corpus_sha256')" = "$(python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$T/c131/SHA256SUMS")" ]
  # manifests/v1/ (the original anchors) feeds _pm3_v1; positions come from the current key
  mkdir -p "$T/c131/manifests/v1"
  jq '.defects[0].anchor_line = 26' "$T/c131/manifests/pr-88.json" > "$T/c131/manifests/v1/pr-88.json"
  grade "$RD" rc-o
  [ "$(G '.recall | "\(.recall_pm3_v1) \(.v1_manifest) \(.missed_pm3_v1 | join(","))"')" = "0.3333 true d2,d3" ]
  # no SHA256SUMS → null; grade.json names no defect id
  rm "$T/c131/SHA256SUMS"; grade "$RD" rc-o
  [ "$(G '.corpus_sha256')" = null ]
  ! grep -n 'O1-guard\|O2-tmpfile\|O3-doc' "$RD/grade.json"
}

@test "AG-46 numeric anchors (FR-4): anchor_line[/anchor_line_end] are cited on the anchor's path part, else the finding's file; non-integers are ignored" {
  make_oracle; RD="$T/run"; make_orun "$RD"
  cat > "$RD/eval/adversarial-review.json" <<'EOF'
{"findings": [{"anchor": ".claude/scripts/g.sh:check", "anchor_type": "function", "anchor_line": 35},
              {"anchor": "check", "file": ".claude/docs/r.md", "anchor_line": 4, "anchor_line_end": 6},
              {"anchor": ".claude/scripts/g.sh:check", "anchor_line": "20"},
              {"anchor": ".claude/scripts/g.sh:check", "anchor_line": true}]}
EOF
  grade "$RD" rc-o
  [ "$status" -eq 0 ]
  grep -qx '.claude/scripts/g.sh:35' "$RD/grading/gates-combined.md"
  grep -qx '.claude/docs/r.md:4-6' "$RD/grading/gates-combined.md"
  ! grep -q 'g.sh:20' "$RD/grading/gates-combined.md"
  [ "$(G '.recall.missed | join(",")')" = d1 ]
}

@test "AG-47 oracle diff form: a covering diff (normal, unified, either operand order, a loop variable, BARE too) exposes by position; the head side only; a closed mount never" {
  make_oracle
  local i=0 cmd res want
  while IFS=$'\t' read -r cmd res want; do
    i=$((i + 1)); RD="$T/o$i"; make_orun "$RD"; sysinit "$RD" REVIEW
    tu "$RD" REVIEW "t$i" Bash "$(bash_in "$cmd")" "$(printf '%b' "$res")"
    grade "$RD" rc-o
    [ "$status" -eq 0 ]
    [ "$(OX)" = "$want" ] || { echo "case $i: $(OX) want $want"; return 1; }
  done <<'CASES'
diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	20c20,21\n< if [ -n x ]\n---\n> fixed\n> guard	diff=d1 read= unknown= exposed=d1
cd /workspace && diff -u .claude/scripts/g.sh pr/head/.claude/scripts/g.sh	--- .claude/scripts/g.sh\n+++ pr/head/.claude/scripts/g.sh\n@@ -19,4 +19,3 @@\n context	diff=d1 read= unknown= exposed=d1
diff -u pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	--- pr/head/.claude/scripts/g.sh\n+++ .claude/scripts/g.sh\n@@ -100,2 +18,5 @@\n context	diff= read= unknown= exposed=
H=pr/head; for f in .claude/scripts/g.sh; do echo "=== $f"; diff "$H/$f" "$f" | head -40; done	=== .claude/scripts/g.sh\n35c36\n< rm\n---\n> rm2	diff=d2 read= unknown= exposed=d2
git diff --no-index pr/head/.claude/scripts/g.sh /workspace/.claude/scripts/g.sh	the printed hunk has no header but carries rm -f "$TMPFILE_SECOND_SITE" # second planted site	diff=d2 read= unknown= exposed=d2
sdiff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	left text | right text	diff= read= unknown=d1,d2 exposed=
CASES
  # BARE events are scanned as well
  RD="$T/obare"; make_orun "$RD"; sysinit "$RD" BARE
  tu "$RD" BARE b1 Bash "$(bash_in 'diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh')" "$(printf '20c20\n< a\n---\n> b')"
  grade "$RD" rc-o
  [ "$(OX)" = "diff=d1 read= unknown= exposed=d1" ]
  [ "$(G '.oracle_exposed_events | map("\(.phase):\(.event):\(.how):\(.path)") | join(" ")')" = "BARE:2:diff:.claude/scripts/g.sh" ]
  # the closed mount (sandbox copy = the PR head): the same diff exposes nothing
  RD="$T/oclosed"; make_orun "$RD" closed; sysinit "$RD" REVIEW
  tu "$RD" REVIEW c1 Bash "$(bash_in 'diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh')" "$(printf '20c20\n< a\n---\n> b')"
  grade "$RD" rc-o
  [ "$(OX)" = "diff= read= unknown= exposed=" ]
  [ "$(G '.oracle_exposed_events | length')" = 0 ]
}

@test "AG-48 oracle non-hits: diff -q, --brief, the word head.diff, cat pr/head.diff, a diff piped to wc or grep -c, >/dev/null, pr/ vs pr/" {
  make_oracle
  local i=0 cmd res err
  while IFS=$'\t' read -r cmd res err; do
    i=$((i + 1)); RD="$T/n$i"; make_orun "$RD"; sysinit "$RD" REVIEW
    tu "$RD" REVIEW "n$i" Bash "$(bash_in "$cmd")" "$(printf '%b' "$res")" "$err"
    grade "$RD" rc-o
    [ "$status" -eq 0 ]
    [ "$(OX)" = "diff= read= unknown= exposed=" ] || { echo "case $i ($cmd): $(OX)"; return 1; }
  done <<'CASES'
diff -q pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Files differ\n20c20	false
diff -rq pr/head/.claude .claude	Files pr/head/.claude/scripts/g.sh and .claude/scripts/g.sh differ\n20c20	false
diff --brief pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	20c20	false
cat pr/head.diff	@@ -20 +20 @@\n-  : base line twenty\n+  if [ -n "$OPT_VALUE_LONG" ]; then echo planted-site; fi	false
diff pr/head.diff .claude/scripts/g.sh	20c20	false
diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh | wc -l	4	false
diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh | grep -c '^[<>]'	3	false
diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh >/dev/null; echo rc=$?	rc=1	false
diff pr/base/.claude/scripts/g.sh pr/head/.claude/scripts/g.sh	20c20\n< a\n---\n> b	false
cat > /tmp/notes.md <<'EOF'\ndiff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh\nEOF	20c20	false
CASES
}

@test "AG-56 grader 1.3.1 error-marked results (PR #1286 F002): a differing diff (exit 1) exposes in normal and unified form, so does a read; a refusal, a tool error or unranged text naming the paths is neither a hit nor unknown" {
  make_oracle
  local i=0 cmd res want
  while IFS=$'\t' read -r cmd res want; do
    i=$((i + 1)); RD="$T/e$i"; make_orun "$RD"; sysinit "$RD" REVIEW
    tu "$RD" REVIEW "e$i" Bash "$(bash_in "$cmd")" "$(printf '%b' "$res")" true
    grade "$RD" rc-o
    [ "$status" -eq 0 ]
    [ "$(G '.grader_version')" = 1.3.8 ]   # cycle-132: 1.3.2 and 1.3.3 are additive (AG-c132-5)
    [ "$(OX)" = "$want" ] || { echo "case $i ($cmd): $(OX) want $want"; return 1; }
  done <<'CASES'
diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Exit code 1\n20c20\n< a\n---\n> b	diff=d1 read= unknown= exposed=d1
diff -u pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Exit code 1\n--- pr/head/.claude/scripts/g.sh\n+++ .claude/scripts/g.sh\n@@ -20 +20 @@\n-a\n+b	diff=d1 read= unknown= exposed=d1
diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Exit code 2\nBLOCKED by hook FR-9: diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh compares the mount	diff= read= unknown= exposed=
diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Exit code 2\ndiff: .claude/scripts/g.sh: Permission denied	diff= read= unknown= exposed=
diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Exit code 1\nleft text | right text	diff= read= unknown= exposed=
diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Exit code 1\nrefused: the sandbox forbids comparing .claude/scripts/g.sh with pr/head/.claude/scripts/g.sh\nif [ -n "$OPT_VALUE_LONG" ]; then echo planted-site; fi	diff= read= unknown= exposed=
CASES
  # the read form on an error-marked result
  RD="$T/er"; make_orun "$RD"; sysinit "$RD" REVIEW
  tu "$RD" REVIEW er Bash "$(bash_in 'cat .claude/scripts/g.sh; false')" "$(printf 'Exit code 1\n%s\n' "$LATER20")" true
  grade "$RD" rc-o
  [ "$(OX)" = "diff= read=d1 unknown= exposed=d1" ]
  # the same unranged text on a result not marked as an error is still unknown (unchanged from 1.3.0)
  RD="$T/eu"; make_orun "$RD"; sysinit "$RD" REVIEW
  tu "$RD" REVIEW eu Bash "$(bash_in 'diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh')" "left text | right text" false
  grade "$RD" rc-o
  [ "$(OX)" = "diff= read= unknown=d1,d2 exposed=" ]
  # the event record names the error-marked result like any other
  RD="$T/ee"; make_orun "$RD"; sysinit "$RD" AUDIT
  tu "$RD" AUDIT ee Bash "$(bash_in 'diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh')" "$(printf 'Exit code 1\n20c20\n< a\n---\n> b')" true
  grade "$RD" rc-o
  [ "$(G '.oracle_exposed_events[0] | "\(.phase) \(.event) \(.how) \(.path)"')" = "AUDIT 2 diff .claude/scripts/g.sh" ]
}

@test "AG-49 oracle read form: a later-only line near a site in a Bash read or a Read result exposes; the PR copy, a line far from every site and a closed mount do not" {
  make_oracle
  RD="$T/r1"; make_orun "$RD"; sysinit "$RD" REVIEW
  tu "$RD" REVIEW r1 Bash "$(bash_in 'sed -n 15,25p .claude/scripts/g.sh')" "$(printf '%s\n%s\n' "$LATER20" "$LATER21")"
  grade "$RD" rc-o
  [ "$(OX)" = "diff= read=d1 unknown= exposed=d1" ]
  [ "$(G '.oracle_exposed_events[0] | "\(.phase) \(.event) \(.how) \(.path)"')" = "REVIEW 2 read .claude/scripts/g.sh" ]
  RD="$T/r2"; make_orun "$RD"; sysinit "$RD" AUDIT
  tu "$RD" AUDIT r2 Read '{"file_path": "/workspace/.claude/scripts/g.sh"}' "$(printf '    21→%s\n' "$LATER21")"
  grade "$RD" rc-o
  [ "$(OX)" = "diff= read=d1 unknown= exposed=d1" ]
  # a grep over the directory credits the file only on a line naming it
  RD="$T/r3"; make_orun "$RD"; sysinit "$RD" REVIEW
  tu "$RD" REVIEW r3 Bash "$(bash_in 'grep -rn OPT_VALUE .claude')" "$(printf '.claude/other.sh:3:%s\n' "$LATER20")"
  grade "$RD" rc-o
  [ "$(OX)" = "diff= read= unknown= exposed=" ]
  tu "$RD" REVIEW r4 Bash "$(bash_in 'grep -rn OPT_VALUE .claude')" "$(printf '.claude/scripts/g.sh:20:%s\n' "$LATER20")"
  grade "$RD" rc-o
  [ "$(OX)" = "diff= read=d1 unknown= exposed=d1" ]
  # non-hits: reading the PR copy; the head text only; a closed mount
  RD="$T/r5"; make_orun "$RD"; sysinit "$RD" REVIEW
  tu "$RD" REVIEW r5 Bash "$(bash_in 'cat pr/head/.claude/scripts/g.sh')" "$(printf '%s\n' "$LATER20")"
  tu "$RD" REVIEW r6 Bash "$(bash_in 'cat .claude/scripts/g.sh')" "$(cat "$T/c131/pr-88/head/.claude/scripts/g.sh")"
  grade "$RD" rc-o
  [ "$(OX)" = "diff= read= unknown= exposed=" ]
  RD="$T/r7"; make_orun "$RD" closed; sysinit "$RD" REVIEW
  tu "$RD" REVIEW r7 Bash "$(bash_in 'cat .claude/scripts/g.sh')" "$(printf '%s\n' "$LATER20")"
  grade "$RD" rc-o
  [ "$(OX)" = "diff= read= unknown= exposed=" ]
  # build tasks carry null oracle fields
  RD="$T/b"; make_run bf-py "$RD"; grade "$RD" bf-py
  [ "$(G '.oracle_exposed_defects, .oracle_exposed_events, .corpus_sha256' | tr '\n' ' ')" = "null null null " ]
}

@test "AG-52 oracle redirections (review r1 DISS-001/C-001, r2 DISS-002/C-004/C-008): 2>&1 | wc -l, &>/dev/null, grep -i -c, |& wc, egrep -c, grep -L, git diff --stat print nothing; 2>&1 | head and --stat -p expose" {
  make_oracle
  local i=0 cmd res want
  while IFS=$'\t' read -r cmd res want; do
    i=$((i + 1)); RD="$T/x$i"; make_orun "$RD"; sysinit "$RD" REVIEW
    tu "$RD" REVIEW "x$i" Bash "$(bash_in "$cmd")" "$(printf '%b' "$res")" false
    grade "$RD" rc-o
    [ "$status" -eq 0 ]
    [ "$(OX)" = "$want" ] || { echo "case $i ($cmd): $(OX) want $want"; return 1; }
  done <<'CASES'
diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | wc -l	4	diff= read= unknown= exposed=
diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh &>/dev/null; echo rc=$?	rc=1	diff= read= unknown= exposed=
diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | grep -i -c planted	1	diff= read= unknown= exposed=
diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>/dev/null | grep --count '^>'	2	diff= read= unknown= exposed=
git diff --no-index --stat pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	 .claude/scripts/g.sh | 2 +-\n 1 file changed	diff= read= unknown= exposed=
diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh |& wc -l	4	diff= read= unknown= exposed=
diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | egrep -c planted	1	diff= read= unknown= exposed=
diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | grep -L nothing	(standard input)	diff= read= unknown= exposed=
diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | head -40	20c20\n<   if [ -n "$OPT_VALUE_LONG" ]; then echo planted-site; fi\n---\n> later	diff=d1 read= unknown= exposed=d1
git diff --no-index --stat -p pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	 g.sh | 2 +-\n@@ -20 +20 @@\n-  if [ -n "$OPT_VALUE_LONG" ]; then echo planted-site; fi\n+ later	diff=d1 read= unknown= exposed=d1
CASES
}

@test "AG-53 KF-046 class 7 (review r1 DISS-C-002): a bare repo-name token as a whole line (a for-list continuation, a list entry) is never exempt" {
  RD="$T/k3"; mkdir -p "$RD/sandbox" "$RD/transcripts" "$RD/eval" "$RD/snapshots"; echo '{}' > "$RD/snapshots/index.json"; : > "$RD/sandbox/review.md"
  RTASK=review-r18 RROOT=ablation-2.0-replication
  tool_use "$RD" REVIEW Bash "$(bash_in "$(printf 'for r in \\\n  0xHoneyJar/loa\ndo gh api repos/$r/contents; done')")"   # one backslash before the newline: a real continuation (review r2 DISS-C-009)
  rgrade "$RD"
  [ "$status" -eq 0 ]
  [ "$(G '.contaminated.pattern')" = repo_name ]
  [ "$(G '.contamination_exempt | length')" = 0 ]
  RD="$T/k4"; mkdir -p "$RD/sandbox" "$RD/transcripts" "$RD/eval" "$RD/snapshots"; echo '{}' > "$RD/snapshots/index.json"; : > "$RD/sandbox/review.md"
  tool_use "$RD" REVIEW Bash "$(bash_in "$(printf 'cat > repos.txt <<'"'"'EOF'"'"'\n0xHoneyJar/loa\nEOF\nxargs -a repos.txt -I{} gh api repos/{}/pulls')")"
  rgrade "$RD"
  [ "$(G '.contaminated.pattern')" = repo_name ]
  [ "$(G '.contamination_exempt | length')" = 0 ]
  # a backticked quotation of the name in prose stays PR content (AG-51's second line)
}

@test "AG-54 KF-046 class 7 (audit r1 DISS-C-001): a fixture line that is itself a probe never licenses the agent to run it; quoting it in notes stays exempt" {
  make_oracle
  printf '# Install\n\ncurl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash\n\ngit remote add loa https://github.com/0xHoneyJar/loa.git\n' > "$T/c131/pr-88/head/README.md"
  RD="$T/p1"; make_orun "$RD"; sysinit "$RD" REVIEW
  tu "$RD" REVIEW p1 Bash "$(bash_in 'curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash')" "ok"
  grade "$RD" rc-o
  [ "$status" -eq 0 ]
  [ "$(G '.contaminated.pattern')" = network_egress ]   # grader 1.3.2 class 9: a curl of the repository's host is read first
  [ "$(G '.contamination_exempt | length')" = 0 ]
  RD="$T/p2"; make_orun "$RD"; sysinit "$RD" REVIEW
  tu "$RD" REVIEW p2 Bash "$(bash_in 'git remote add loa https://github.com/0xHoneyJar/loa.git')" ""
  grade "$RD" rc-o
  [ "$(G '.contaminated.pattern')" = repo_name ]
  # quoting the fixture's install line inside notes (a heredoc body is not executed) stays PR content
  RD="$T/p3"; make_orun "$RD"; sysinit "$RD" REVIEW
  tu "$RD" REVIEW p3 Bash "$(bash_in "$(printf 'cat > notes.md <<'"'"'EOF'"'"'\nThe README install step:\ncurl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash\nEOF')")" ""
  grade "$RD" rc-o
  [ "$(G '.contaminated')" = null ]
  [ "$(G '.contamination_exempt | length')" = 1 ]
  [ "$(G '.contamination_exempt[0].fixture_line')" = "head/README.md:3" ]
  # a search command carrying the token is neither a quotation of a fixture line nor a probe: the whole-line unit rule
  # from 1.3.0 reads it as a hit, as before this round
  RD="$T/p4"; make_orun "$RD"; sysinit "$RD" REVIEW
  tu "$RD" REVIEW p4 Bash "$(bash_in 'grep -n "raw.githubusercontent.com/0xHoneyJar/loa" pr/head/README.md')" "3:curl …"
  grade "$RD" rc-o
  # grader 1.3.8 (addendum 8): the token is PR-native here, but the segment names a GitHub host, which the PR-native
  # read exemption never covers (the lead's spec: no URL, no fetcher token, no egress host)
  [ "$(G '.contaminated.pattern')" = repo_name ]
  [ "$(G '.repo_token_pr_native')" = true ]
  [ "$(G '[.contamination_exempt[] | select(.class == "repo_name_pr_native")] | length')" = 0 ]
  # the same read without the host is PR content
  RD="$T/p5"; make_orun "$RD"; sysinit "$RD" REVIEW
  tu "$RD" REVIEW p5 Bash "$(bash_in 'grep -n "0xHoneyJar/loa" pr/head/README.md')" "3:curl …"
  grade "$RD" rc-o
  [ "$(G '.contaminated')" = null ]
  [ "$(G '[.contamination_exempt[] | select(.class == "repo_name_pr_native")] | length')" = 1 ]
}

@test "AG-55 oracle detector bounds (audit r1 DISS-C-003): a 300-word for-list product, a 100 KB token and a 25,000-line sandbox copy grade to completion; the huge copy is recorded in oracle_scan_skipped" {
  make_oracle
  RD="$T/q1"; make_orun "$RD"; sysinit "$RD" REVIEW
  words="$(seq -f 'w%g' 1 300 | tr '\n' ' ')"
  tu "$RD" REVIEW q1 Bash "$(bash_in "for f in $words; do cat \$f\$f\$f\$f; done")" "nothing"
  tu "$RD" REVIEW q2 Bash "$(bash_in "diff pr/head/.claude/scripts/g.sh $(head -c 100000 /dev/zero | tr '\0' ',') .claude/scripts/g.sh")" "20c20"
  grade "$RD" rc-o
  [ "$status" -eq 0 ]
  [ "$(G '.oracle_scan_skipped | length')" = 0 ]
  RD="$T/q3"; make_orun "$RD"; sysinit "$RD" REVIEW
  { cat "$RD/sandbox/.claude/scripts/g.sh"; seq -f 'echo pad%g' 1 25000; } > "$RD/sandbox/.claude/scripts/g.sh.new" && mv "$RD/sandbox/.claude/scripts/g.sh.new" "$RD/sandbox/.claude/scripts/g.sh"
  tu "$RD" REVIEW q3 Bash "$(bash_in 'sed -n 15,25p .claude/scripts/g.sh')" "$(printf '%s\n' "$LATER20")"
  grade "$RD" rc-o
  [ "$status" -eq 0 ]
  [ "$(G '.oracle_scan_skipped | join(",")')" = ".claude/scripts/g.sh" ]
  [ "$(OX)" = "diff= read= unknown= exposed=" ]
}

# real_run <fixture name> <run-dir>: a run directory from a trimmed cycle-130 transcript (fixtures/c131-oracle/,
# made by its trim.py from the read-only run directories): its events, and the later sandbox copy of each path
# an event names; the task is the real corpus task in the repository's frozen suite roots
real_run() {
  local fx="$TESTS_DIR/fixtures/c131-oracle/$1" rd="$2" f rel
  mkdir -p "$rd/sandbox/.claude" "$rd/eval" "$rd/snapshots"
  cp -a "$fx/transcripts" "$rd/"
  if [[ -d "$fx/dotclaude" ]]; then
    while IFS= read -r f; do
      rel="${f#"$fx/dotclaude/"}"; rel="${rel%.fx}"
      mkdir -p "$(dirname "$rd/sandbox/.claude/$rel")"; cp "$f" "$rd/sandbox/.claude/$rel"
    done < <(find "$fx/dotclaude" -type f -name '*.fx')
  fi
  echo '{}' > "$rd/snapshots/index.json"; : > "$rd/sandbox/review.md"
  read -r RTASK RROOT < "$fx/task"
}
rgrade() { run "$GRADER" "$1" "$RTASK" --suite-root "$REPO_ROOT/grimoires/loa/evals/$RROOT" --allow-unfrozen --allow-partial --docker-bin "$T/docker"; }

@test "AG-50 detector validation pins (trimmed cycle-130 transcripts): review-04 t2 d1-d4, review-r17 t1 nine sites under the curated anchors (eight under manifests/v1), review-r18 t1 d7 by the diff form; the bare run nothing" {
  RD="$T/v1"; real_run p1-a1-review-04-t2 "$RD"; rgrade "$RD"
  [ "$status" -eq 0 ]
  [ "$(G '.oracle_exposed_by_form.diff | join(",")')" = "d1,d2,d3,d4" ]
  [ "$(G '[.oracle_exposed_events[] | select(.how == "diff") | "\(.phase):\(.event)"] | unique | join(" ")')" = "REVIEW:482" ]
  [ "$(G '.oracle_exposed_defects | join(",")')" = "d1,d2,d3,d4,d5" ]    # d5: the audit skill reads its own later SKILL.md
  [ "$(G '.oracle_exposed_by_form.read | join(",")')" = "d5" ]
  RD="$T/v2"; real_run rep-a1-review-r17-t1 "$RD"; rgrade "$RD"
  # d10 joined on 2026-10-19 when the curated pr-17 manifest (DEC-0626) gave L10 the lines 57,66,71,72 of chart-unblock-probe.sh,
  # inside the REVIEW:314 hunk; manifests/v1/ (anchor_line only) gives the eight-site set without d10.
  [ "$(G '.oracle_exposed_by_form.diff | join(",")')" = "d1,d2,d8,d10,d11,d13,d14,d17,d20" ]
  [ "$(G '[.oracle_exposed_events[] | "\(.phase):\(.event)"] | unique | join(" ")')" = "REVIEW:314 REVIEW:316 REVIEW:365" ]
  RD="$T/v3"; real_run rep-a1-review-r18-t1 "$RD"; rgrade "$RD"
  [ "$(G '.oracle_exposed_defects | join(",")')" = "d7" ]
  [ "$(G '[.oracle_exposed_events[] | "\(.phase):\(.event):\(.how)"] | join(" ")')" = "REVIEW:226:diff" ]
  RD="$T/v4"; real_run rep-a0-review-r17-t1 "$RD"; rgrade "$RD"
  [ "$(G '.oracle_exposed_defects | length')" = 0 ]
  [ "$(G '.oracle_exposed_events | length')" = 0 ]
}

@test "AG-51 KF-046 class 7: the replication excerpt (github.repository == '0xHoneyJar/loa', a line of pr-18) is exempt and recorded; a repo-name token beyond the fixture's lines is still contaminated" {
  RD="$T/k1"; mkdir -p "$RD/sandbox" "$RD/transcripts" "$RD/eval" "$RD/snapshots"; echo '{}' > "$RD/snapshots/index.json"; : > "$RD/sandbox/review.md"
  RTASK=review-r18 RROOT=ablation-2.0-replication
  tool_use "$RD" REVIEW Bash "$(bash_in "$(printf 'cat > notes.md <<'"'"'EOF'"'"'\n7. CI workflow uses \x60|| rc=$?\x60 under set -e; \x60if: github.repository == '"'"'0xHoneyJar/loa'"'"'\x60.\n8. job scoped to \x600xHoneyJar/loa\x60\nEOF')")"
  rgrade "$RD"
  [ "$status" -eq 0 ]
  [ "$(G '.contaminated')" = null ]
  [ "$(G '.contamination_exempt | length')" = 1 ]
  [ "$(G '.contamination_exempt[0] | "\(.phase) \(.excerpt_id) \(.pattern)"')" = "REVIEW REVIEW:1 repo_name" ]
  [ "$(G '.contamination_exempt[0].fixture_line | test("^(head/.github/workflows/check-glossary-terms.yml|head.diff):[0-9]+$")')" = true ]
  [ "$(G '.contamination_exempt[0].line')" = "if: github.repository == '0xHoneyJar/loa'" ]
  # an upstream probe in the same session: the line is not PR content
  tool_use "$RD" REVIEW Bash '{"command": "gh api repos/0xHoneyJar/loa/pulls/1283"}'
  rgrade "$RD"
  [ "$(G '.contaminated | "\(.phase) \(.pattern) \(.excerpt_id)"')" = "REVIEW network_egress REVIEW:2" ]   # grader 1.3.2 class 9: gh api naming the repository
  # a task whose PR fixture lacks the token: the bare token is still a hit
  RD="$T/k2"; make_run rc-x "$RD"
  tool_use "$RD" REVIEW Bash '{"command": "echo `0xHoneyJar/loa`"}'
  grade "$RD" rc-x
  [ "$(G '.contaminated.pattern')" = repo_name ]
  [ "$(G '.contamination_exempt | length')" = 0 ]
}

# --- cycle-132 Task 1.5 (FR-2, SDD D-2.3, implementer B): label_set and labels_meta -------------------------------
# make_ls <set-dir>: rc-x's key at $T/ls/manifests/<set-dir>/pr-77.json (set-dir "." = manifests/ itself) under a
# corpus root $T/ls (SHA256SUMS at the root), with a v1 snapshot at $T/ls/manifests/v1/pr-77.json
make_ls() {
  local sub="$1" m="$T/ls/manifests"
  [[ -d "$T/ls" ]] && find "$T/ls" -mindepth 1 -delete
  mkdir -p "$m/$sub" "$m/v1"
  cat > "$m/$sub/pr-77.json" <<'EOF'
{"fixture": "pr-77", "label_set": "v2", "defects": [
  {"id": "K01-guard", "file": "lib/x.sh", "anchor_line": 5, "severity": "high", "category": "logic",
   "label_source": "fix-commit+incident", "annotators": ["A", "B"], "agreement": "adjudicated",
   "adjudication": "the hunk restores the guard", "review_driven": true},
  {"id": "K02-quote", "file": "lib/x.sh", "anchor_line": 20, "severity": "low", "category": "logic",
   "label_source": "review", "source": "review:engineer-feedback.md"}]}
EOF
  [[ "$sub" == v1 ]] || jq '.defects[0].anchor_line = 9' "$m/$sub/pr-77.json" > "$m/v1/pr-77.json"
  printf 'abc  manifests/pr-77.json\n' > "$T/ls/SHA256SUMS"
  sed -i "s|manifest: \"[^\"]*\"|manifest: \"$m/$sub/pr-77.json\"|" "$S/tasks/rc-x/task.yaml"
}

@test "AG-LS1 label_set follows the key's directory (manifests/ v2, manifests/c131/ c131, manifests/v1/ v1); labels_meta passes label_source, agreement and review_driven through by position" {
  RD="$T/run"; make_run rc-x "$RD"
  printf 'pr/head/lib/x.sh:5 the guard\n' > "$RD/sandbox/review.md"
  make_ls .
  grade "$RD" rc-x
  [ "$status" -eq 0 ]
  [ "$(G '.label_set')" = v2 ]
  [ "$(G '.labels_meta | map("\(.defect):\(.label_source):\(.agreement):\(.review_driven)") | join(" ")')" = "d1:fix-commit+incident:adjudicated:true d2:review:null:null" ]
  ! grep -n 'K01-guard\|K02-quote' "$RD/grade.json"
  make_ls c131
  grade "$RD" rc-x
  [ "$status" -eq 0 ]
  [ "$(G '.label_set')" = c131 ]
  # a c131 key sits beside manifests/v1/: the v1 snapshot and the corpus SHA256SUMS resolve one level up
  [ "$(G '.recall.v1_manifest')" = true ]
  [ "$(G '.recall | "\(.recall_pm3) \(.recall_pm3_v1)"')" = "0.5 0.0" ]
  [ "$(G '.corpus_sha256')" = "$(python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$T/ls/SHA256SUMS")" ]
  make_ls v1
  grade "$RD" rc-x
  [ "$status" -eq 0 ]
  [ "$(G '.label_set')" = v1 ]
}

@test "AG-LS2 a cycle-131 run re-graded under the moved key (manifests/c131/pr-17.json) reproduces its recorded recall block; label_set c131" {
  local fx="$TESTS_DIR/fixtures/c131-regrade/b2a-a1_full-review-r17-t1"
  [ "$(yq -r '.review_catch.manifest' "$REPO_ROOT/grimoires/loa/evals/ablation-2.0-c131/tasks/review-r17/task.yaml")" = "evals/fixtures/review-prs/manifests/c131/pr-17.json" ]
  RD="$T/c131run"; mkdir -p "$RD/sandbox" "$RD/transcripts" "$RD/eval" "$RD/snapshots"
  echo '{}' > "$RD/snapshots/index.json"; cp "$fx/review.md" "$RD/sandbox/review.md"
  run "$GRADER" "$RD" review-r17 --suite-root "$REPO_ROOT/grimoires/loa/evals/ablation-2.0-c131" --allow-partial --executor host
  [ "$status" -eq 0 ]
  [ "$(G '.suite_frozen')" = true ]
  [ "$(G '.label_set')" = c131 ]
  [ "$(jq -c '.recall' "$RD/grade.json")" = "$(jq -c '.' "$fx/recall.json")" ]
  [ "$(G '.labels_meta | length')" = "$(jq '.defects_seeded' "$fx/recall.json")" ]
}

# --- cycle-132 Sprint 269 Task 1.7b: grader 1.3.2 (--union, multi_credit_citations, false_positive_rule, egress class 9)

# cite <run-dir> <citation lines…>: the A0 contract file (review.md) with one bullet per citation
cite() { local rd="$1"; shift; printf '# Findings\n\n' > "$rd/sandbox/review.md"; printf -- '- %s\n' "$@" >> "$rd/sandbox/review.md"; }
# cell_json <cell-dir> <k> <id:valid:status:cost>… : the runner's meta/cell.json (no arm)
cell_json() {
  local c="$1" k="$2"; shift 2
  mkdir -p "$c/meta"
  printf '%s\n' "$@" | jq -R -s -c --argjson k "$k" '
    {schema_version: 1, k: $k,
     sessions: [split("\n")[] | select(length > 0) | split(":") as [$id, $v, $st, $c]
                | {id: $id, valid: ($v == "true"), status: $st, cost_usd: ($c | tonumber), attempts: 1, run_dir: ("sessions/" + $id)}]}
    | .sessions_valid = ([.sessions[] | select(.valid)] | length)' > "$c/meta/cell.json"
}
union() { run "$GRADER" --union "$1" --task-id "${2:-rc-x}" --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"; }
U() { jq -r "$1" "$C/grade.json"; }

# three sessions of one cell: s1 and s2 both catch D01 (lib/x.sh:5) and cite overlapping strays (28 and 27, one
# cited region); s3 catches D02 but is invalid (a refusal fallback) and never enters the union
make_cell() {
  C="$T/cell"; mkdir -p "$C/sessions"
  make_run rc-x "$C/sessions/s1"; cite "$C/sessions/s1" "head/lib/x.sh:5" "head/lib/x.sh:28"
  make_run rc-x "$C/sessions/s2"; cite "$C/sessions/s2" "head/lib/x.sh:6" "head/lib/x.sh:27"
  make_run rc-x "$C/sessions/s3"; cite "$C/sessions/s3" "head/lib/x.sh:20"
  local i; for i in 1 2 3; do grade "$C/sessions/s$i" rc-x; [ "$status" -eq 0 ] || { echo "$output"; return 1; }; done
  cell_json "$C" 3 s1:true:completed:1.5 s2:true:completed:2 s3:false:completed:1.25
}

@test "AG-c132-1 --union: valid sessions only, each defect credited once, strays deduplicated by cited region across sessions, session 1 alone beside" {
  make_cell
  union "$C"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(U .grader_version)" = 1.3.8 ]
  [ "$(U '.union, .bare_sessions, .sessions_valid' | tr '\n' ' ')" = "true 3 2 " ]
  [ "$(U '.sessions_graded | join(",")')" = "s1,s2" ]
  [ "$(U '.recall | "\(.defects_caught)/\(.defects_seeded) \(.recall) \(.recall_pm3) \(.missed | join(","))"')" = "1/2 0.5 0.5 d2" ]   # D02 only in the invalid s3
  [ "$(U .false_positives)" = 1 ]                  # 28 (s1) and 27 (s2) are one cited region
  [ "$(U .false_positive_rule)" = pm3 ]
  [ "$(U .multi_credit_citations)" = 0 ]
  [ "$(U '.recall_session1, .recall_pm3_session1, .precision_session1' | tr '\n' ' ')" = "0.5 0.5 0.5 " ]   # 1 caught / (1 + 1 stray)
  [ "$(U '[.per_session[] | "\(.session):\(.valid):\(.recall):\(.detected_pm3 // [] | join("+")):\(.cost_usd)"] | join(" ")')" = "s1:true:0.5:d1:1.5 s2:true:0.5:d1:2 s3:false:null::1.25" ]
  [ "$(U '.verdict, .contaminated' | tr '\n' ' ')" = "null null " ]
  grep -qx '## session s1' "$C/grading/gates-combined.md"
  grep -qx '## session s2' "$C/grading/gates-combined.md"
  ! grep -q 's3\|lib/x.sh:20' "$C/grading/gates-combined.md" || false
  # byte-identical on a second call (DEC-0413)
  cp "$C/grade.json" "$T/g1.json"
  union "$C"
  cmp "$T/g1.json" "$C/grade.json"
  # an invalid session 1: the session-1 figures are null, the union still grades
  cell_json "$C" 3 s1:false:transport_error:0.5 s2:true:completed:2 s3:false:completed:1.25
  union "$C"
  [ "$status" -eq 0 ]
  [ "$(U '.recall_session1, .precision_session1, .sessions_valid' | tr '\n' ' ')" = "null null 1 " ]
}

@test "AG-c132-2 --union refuses (exit 2): a valid session without a grade, k against the session directories, ids other than s1 … sk, a valid session whose grade is contaminated, usage" {
  make_cell
  rm "$C/sessions/s2/grade.json"
  union "$C"
  [ "$status" -eq 2 ]
  grep -q 'session s2 is marked valid but has no grade' <<<"$output"
  grade "$C/sessions/s2" rc-x
  cell_json "$C" 2 s1:true:completed:1 s2:true:completed:1
  union "$C"
  [ "$status" -eq 2 ]
  grep -q 'do not match k 2' <<<"$output"      # sessions/s3 exists beyond k
  cell_json "$C" 3 s1:true:completed:1 s3:true:completed:1 s2:true:completed:1
  union "$C"
  [ "$status" -eq 2 ]
  jq '.contaminated = {"phase": "BARE", "pattern": "network_egress", "excerpt_id": "BARE:1"}' "$C/sessions/s2/grade.json" > "$T/x" && mv "$T/x" "$C/sessions/s2/grade.json"
  cell_json "$C" 3 s1:true:completed:1 s2:true:completed:1 s3:false:completed:1
  union "$C"
  [ "$status" -eq 2 ]
  grep -q 'session s2 is marked valid but its grade is contaminated' <<<"$output"
  run "$GRADER" --union "$C" --suite-root "$S" --allow-unfrozen
  [ "$status" -eq 2 ]
  run "$GRADER" "$C/sessions/s1" rc-x --task-id rc-x --suite-root "$S" --allow-unfrozen
  [ "$status" -eq 2 ]
}

@test "AG-c132-3 distinct-defect semantics (SKP-022): overlapping sites, multiple anchors, one citation near several defects — each defect credited once, multi_credit_citations counts the citation that hit two" {
  jq '.defects = [
        {"id": "D01-a", "file": "lib/x.sh", "anchor_line": 10, "anchors": [10, 12], "severity": "high", "category": "logic"},
        {"id": "D02-b", "file": "lib/x.sh", "anchor_line": 11, "severity": "low", "category": "logic"},
        {"id": "D03-c", "file": "lib/x.sh", "anchor_line": 25, "anchors": [25, 2], "severity": "low", "category": "logic"}]' \
    "$T/manifests/pr-77.json" > "$T/x" && mv "$T/x" "$T/manifests/pr-77.json"
  RD="$T/run"; make_run rc-x "$RD"
  cite "$RD" "head/lib/x.sh:11" "head/lib/x.sh:2" "head/lib/x.sh:25"
  grade "$RD" rc-x
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(G '.recall | "\(.defects_caught)/\(.defects_seeded) \(.recall_pm3)"')" = "3/3 1.0" ]   # D03 through either anchor, counted once
  [ "$(G .multi_credit_citations)" = 1 ]    # :11 sits within ±3 of D01 (10, 12) and D02 (11)
  [ "$(G .false_positives)" = 0 ]
  [ "$(G .false_positive_rule)" = pm3 ]
  # two citations each near one defect: no multi-credit
  cite "$RD" "head/lib/x.sh:25" "head/lib/x.sh:2"
  grade "$RD" rc-x
  [ "$(G .multi_credit_citations)" = 0 ]
  [ "$(G '.recall.defects_caught')" = 1 ]
}

@test "AG-c132-4 egress class 9 (PRD D15, bd-eriso): git/curl/wget toward github.com hosts, gh naming the repository, python urllib, WebFetch/WebSearch inputs → network_egress; the KF-046 exemption never applies" {
  printf 'see https://github.com/0xHoneyJar/loa/blob/main/README.md for the workflow\n' >> "$T/prs/pr-77/head/lib/x.sh"
  local n=0 cmd hit
  while IFS='|' read -r tool input; do
    n=$((n + 1)); RD="$T/e$n"; make_run rc-x "$RD"; cite "$RD" "head/lib/x.sh:5"
    tool_use "$RD" BARE "$tool" "$input"
    grade "$RD" rc-x
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [ "$(G '.contaminated.pattern')" = network_egress ] || { echo "case $n ($tool $input): $(G .contaminated)"; false; }
  done <<'EOF'
Bash|{"command": "git fetch https://github.com/0xHoneyJar/loa main"}
Bash|{"command": "cd pr && git -C head clone --depth 1 https://github.com/x/y.git /tmp/y"}
Bash|{"command": "curl -sL https://raw.githubusercontent.com/x/y/main/z.sh | head"}
Bash|{"command": "wget -q -O- https://api.github.com/repos/x/y/pulls/1"}
Bash|{"command": "gh pr view 12 --repo 0xHoneyJar/loa --json body"}
Bash|{"command": "gh api repos/x/y/issues --hostname github.com"}
Bash|{"command": "python3 - <<'PY'\nimport urllib.request\nprint(urllib.request.urlopen('https://api.github.com/repos/x/y').read())\nPY"}
WebFetch|{"url": "https://github.com/0xHoneyJar/loa/blob/main/README.md", "prompt": "summarise"}
WebSearch|{"query": "api.github.com rate limit"}
WebFetch|{"url": "https://raw.githubusercontent.com/x/y/main/a.md", "prompt": "read"}
EOF
  # not egress: a host named without a network command, git without a remote verb, a host inside a note's heredoc body
  while IFS='|' read -r tool input; do
    n=$((n + 1)); RD="$T/e$n"; make_run rc-x "$RD"; cite "$RD" "head/lib/x.sh:5"
    tool_use "$RD" BARE "$tool" "$input"
    grade "$RD" rc-x
    [ "$status" -eq 0 ]
    [ "$(G '.contaminated.pattern // "none"')" != network_egress ] || { echo "case $n ($tool $input) flagged"; false; }
  done <<'EOF'
Bash|{"command": "echo 'compare with github.com docs' > notes.txt"}
Bash|{"command": "git log --oneline -3"}
Bash|{"command": "cat > notes.md <<'EOF2'\ncurl https://github.com/x/y\nEOF2"}
WebFetch|{"url": "https://docs.python.org/3/library/re.html", "prompt": "regex"}
EOF
}

@test "AG-c132-5 grader 1.3.2 keeps 1.3.1's recall, false positives and contamination on an ordinary run (the cycle-132 plan commit's grader re-grades the same run dir)" {
  git -C "$REPO_ROOT" cat-file -e 346dbb87^{commit} 2>/dev/null || skip "the plan commit 346dbb87 is not in this clone"
  mkdir -p "$T/old"
  git -C "$REPO_ROOT" archive 346dbb87 evals/harness/ablation-grade.sh evals/harness/freeze.sh evals/harness/validate-suite.sh \
    evals/harness/took-effect.sh evals/harness/lib evals/graders/recall-vs-defects.sh | tar -x -C "$T/old"
  RD="$T/run"; make_run rc-x "$RD"
  cite "$RD" "head/lib/x.sh:5" "head/lib/x.sh:21-22" "head/lib/x.sh:29" "pr/head/lib/x.sh:2"
  verdict "$RD" review CHANGES_REQUIRED "- lib/x.sh:4 overflow"
  tool_use "$RD" REVIEW Bash '{"command": "grep -n line_ pr/head/lib/x.sh"}'
  grade "$RD" rc-x
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  cp "$RD/grade.json" "$T/new.json"
  run "$T/old/evals/harness/ablation-grade.sh" "$RD" rc-x --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker" --out "$T/old.json"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r .grader_version "$T/old.json")" = 1.3.1 ]
  for k in recall false_positives contaminated verdict verdict_accuracy_per_gate oracle_exposed_defects; do
    [ "$(jq -c --arg k "$k" '.[$k]' "$T/old.json")" = "$(jq -c --arg k "$k" '.[$k]' "$T/new.json")" ] || { echo "$k differs"; false; }
  done
}

@test "AG-c132-6 grader 1.3.3: --self-check reference passes on a task whose manifest anchors long-extension files (.loa.config.yaml.example, Dockerfile.ablation); a findings file citing them is credited" {
  local d="$S/tasks/rc-long" p="$T/prs/pr-78" i
  mkdir -p "$d" "$p/base/evals/harness" "$p/head/evals/harness"
  for i in $(seq 1 140); do echo "key_$i: 1"; done > "$p/base/.loa.config.yaml.example"
  for i in $(seq 1 140); do echo "key_$i: 2"; done > "$p/head/.loa.config.yaml.example"
  for i in $(seq 1 30); do echo "RUN step $i"; done > "$p/base/evals/harness/Dockerfile.ablation"
  for i in $(seq 1 30); do echo "RUN step $i v2"; done > "$p/head/evals/harness/Dockerfile.ablation"
  printf -- '--- a/.loa.config.yaml.example\n+++ b/.loa.config.yaml.example\n' > "$p/head.diff"
  printf '# PR\n' > "$p/PR.md"
  cat > "$T/manifests/pr-78.json" <<'EOF'
{"fixture": "pr-78", "defects": [
  {"id": "D01-budget-key", "file": ".loa.config.yaml.example", "anchor_line": 127, "severity": "high", "category": "config"},
  {"id": "D02-unpinned-base", "file": "evals/harness/Dockerfile.ablation", "anchor_line": 19, "severity": "high", "category": "build"}]}
EOF
  printf 'Review the pull request.\n' > "$d/TASK.md"
  cat > "$d/task.yaml" <<YAML
id: rc-long
schema_version: 1
type: review-catch
fixture: null
criterion: "review the change"
test_command: null
regression_command: null
reference_patch: null
grader_protected: []
structural_check: null
review_catch: {fixture: "$p", manifest: "$T/manifests/pr-78.json"}
suite_version: 1
YAML
  run "$GRADER" --self-check reference --task-yaml "$d/task.yaml" --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '^self-check reference rc-long: PASS recall 1.0 (2/2)' <<<"$output"
  # an envelope's numeric anchor on a long-extension path is cited on that path too
  RD="$T/run"; mkdir -p "$RD/sandbox/pr" "$RD/transcripts" "$RD/eval" "$RD/snapshots"; echo '{}' > "$RD/snapshots/index.json"
  : > "$RD/sandbox/review.md"
  jq -n '{findings: [{anchor: "evals/harness/Dockerfile.ablation:19", anchor_line: 19, file: "x.sh"}]}' > "$RD/eval/adversarial-review.json"
  grade "$RD" rc-long
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(G '.recall.missed | join(",")')" = d1 ]
  [ "$(G '.grader_version')" = 1.3.8 ]
}

@test "AG-c132-7 grader 1.3.4 class 9 per simple command (dissent DISS-001/C-001/C-003): reviewer prose in a cat heredoc, words on separate commands, grep/rg/echo naming a host are clean; real curl, git fetch, python -c requests, a bash heredoc body and \$(curl …) are egress" {
  local n=0
  while IFS='|' read -r want input; do
    n=$((n + 1)); RD="$T/q$n"; make_run rc-x "$RD"; cite "$RD" "head/lib/x.sh:5"
    tool_use "$RD" BARE Bash "$input"
    grade "$RD" rc-x
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    got="$(G '.contaminated.pattern // "none"')"
    if [ "$want" = egress ]; then [ "$got" = network_egress ] || { echo "case $n should be egress: $input ($got)"; false; }
    else [ "$got" != network_egress ] || { echo "case $n should be clean: $input"; false; }; fi
  done <<'EOF'
clean|{"command": "cat > review.md <<'EOF2'\nThe python client uses requests to call github.com for the token.\nEOF2"}
clean|{"command": "python3 --version\necho requests\necho see github.com"}
clean|{"command": "python3 -m pytest -q; grep -n requests lib/x.sh; echo github.com"}
clean|{"command": "grep -rn curl pr/head | grep github.com"}
clean|{"command": "rg github.com ."}
clean|{"command": "git log --oneline -3 && echo https://github.com/x/y"}
egress|{"command": "curl -s https://api.github.com/repos/x/y"}
egress|{"command": "cd pr && git fetch https://github.com/x/y.git main"}
egress|{"command": "python3 -c \"import requests; requests.get('https://github.com/x/y')\""}
egress|{"command": "bash <<'SH'\nset -e\ncurl -sL https://raw.githubusercontent.com/x/y/main/z\nSH"}
egress|{"command": "echo $(curl -s https://api.github.com/rate_limit)"}
egress|{"command": "timeout 30 wget -q https://github.com/x/y/archive/main.zip"}
EOF
  # the recorded-run equality still holds (AG-c132-5 re-grades with the plan commit's grader)
}

# --- cycle-132 Sprint 269 round 3 (DISS-C-005): every recognised set directory is re-rooted ------------------------
sha_of() { python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

@test "AG-LS3 a v1 or review key is re-rooted like a c131 key: label_set names the set, the v1 snapshot is manifests/v1/<pr>.json (itself for v1), corpus_sha256 hashes the corpus SHA256SUMS" {
  RD="$T/run"; make_run rc-x "$RD"
  printf 'pr/head/lib/x.sh:9 the guard\n' > "$RD/sandbox/review.md"
  make_ls v1
  grade "$RD" rc-x
  [ "$status" -eq 0 ]
  # the v1 key holds d1 at 5: a miss for :9, under both rules (the snapshot is the key itself)
  [ "$(G '"\(.label_set) \(.recall.v1_manifest) \(.recall.recall_pm3) \(.recall.recall_pm3_v1)"')" = "v1 true 0.0 0.0" ]
  [ "$(G '.corpus_sha256')" = "$(sha_of "$T/ls/SHA256SUMS")" ]
  make_ls review
  grade "$RD" rc-x
  [ "$status" -eq 0 ]
  # the review key's d1 sits at 5 (a miss for :9); its v1 snapshot manifests/v1/ puts d1 at 9 (a hit)
  [ "$(G '"\(.label_set) \(.recall.v1_manifest) \(.recall.recall_pm3) \(.recall.recall_pm3_v1)"')" = "review true 0.0 0.5" ]
  [ "$(G '.corpus_sha256')" = "$(sha_of "$T/ls/SHA256SUMS")" ]
}

@test "AG-LS4 the recorded cycle-131 run graded against the v1 key (manifests/v1/pr-17.json): label_set v1, v1_manifest true, a corpus digest, and the v1 recall the c131 re-grade reports" {
  local fx="$TESTS_DIR/fixtures/c131-regrade/b2a-a1_full-review-r17-t1" src="$REPO_ROOT/grimoires/loa/evals/ablation-2.0-c131/tasks/review-r17"
  mkdir -p "$T/v1root/tasks"
  cp -R "$src" "$T/v1root/tasks/review-r17"
  sed -i 's#manifests/c131/pr-17.json#manifests/v1/pr-17.json#' "$T/v1root/tasks/review-r17/task.yaml"
  [ "$(yq -r '.review_catch.manifest' "$T/v1root/tasks/review-r17/task.yaml")" = evals/fixtures/review-prs/manifests/v1/pr-17.json ]
  RD="$T/v1run"; mkdir -p "$RD/sandbox" "$RD/transcripts" "$RD/eval" "$RD/snapshots"
  echo '{}' > "$RD/snapshots/index.json"; cp "$fx/review.md" "$RD/sandbox/review.md"
  run "$GRADER" "$RD" review-r17 --suite-root "$T/v1root" --allow-unfrozen --allow-partial --executor host
  [ "$status" -eq 0 ]
  [ "$(G '.label_set')" = v1 ]
  [ "$(G '.recall.v1_manifest')" = true ]
  [ "$(G '.corpus_sha256')" = "$(sha_of "$REPO_ROOT/evals/fixtures/review-prs/SHA256SUMS")" ]
  # the v1 rule on the v1 key is the c131 re-grade's v1 figure, as recall_pm3 and as recall_pm3_v1
  [ "$(G '.recall.recall_pm3')" = "$(jq -r '.recall_pm3_v1' "$fx/recall.json")" ]
  [ "$(G '.recall.recall_pm3_v1')" = "$(jq -r '.recall_pm3_v1' "$fx/recall.json")" ]
  [ "$(jq -c '.recall.missed_pm3' "$RD/grade.json")" = "$(jq -c '.missed_pm3_v1' "$fx/recall.json")" ]
}

@test "AG-LS5 the tracked review set (manifests/review/pr-27.json) grades with label_set review and the corpus digest" {
  local m="$REPO_ROOT/evals/fixtures/review-prs/manifests/review/pr-27.json"
  [ -f "$m" ] || skip "no manifests/review/pr-27.json in this tree"
  sed -i "s|manifest: \"[^\"]*\"|manifest: \"$m\"|; s|fixture: \"[^\"]*\"|fixture: \"$REPO_ROOT/evals/fixtures/review-prs/pr-27\"|" "$S/tasks/rc-x/task.yaml"
  RD="$T/r27"; mkdir -p "$RD/sandbox" "$RD/transcripts" "$RD/eval" "$RD/snapshots"; echo '{}' > "$RD/snapshots/index.json"; : > "$RD/sandbox/review.md"
  grade "$RD" rc-x
  [ "$status" -eq 0 ]
  [ "$(G '.label_set')" = review ]
  [ "$(G '.corpus_sha256')" = "$(sha_of "$REPO_ROOT/evals/fixtures/review-prs/SHA256SUMS")" ]
  [ "$(G '.labels_meta | length')" = "$(jq '.defects | length' "$m")" ]
}

@test "AG-c132-8 grader 1.3.5 class 9 (audit A1–A3): shell -c strings, github subdomains, more python libraries, wrappers and keywords, process substitution, a heredoc piped into bash, a fetcher token anywhere in the command, xargs curl — all egress; the review negatives stay clean" {
  local n=0
  while IFS='|' read -r want input; do
    n=$((n + 1)); RD="$T/w$n"; make_run rc-x "$RD"; cite "$RD" "head/lib/x.sh:5"
    tool_use "$RD" BARE Bash "$input"
    grade "$RD" rc-x
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    got="$(G '.contaminated.pattern // "none"')"
    if [ "$want" = egress ]; then [ "$got" = network_egress ] || { echo "case $n should be egress: $input ($got)"; false; }
    else [ "$got" != network_egress ] || { echo "case $n should be clean: $input"; false; }; fi
  done <<'EOF'
egress|{"command": "bash -c 'curl -s https://api.github.com/repos/x/y'"}
egress|{"command": "sh -c \"git fetch https://github.com/x/y.git\""}
egress|{"command": "zsh -lc 'wget -q https://github.com/x/y'"}
egress|{"command": "bash -c \"bash -c 'curl https://github.com/x'\""}
egress|{"command": "curl -sL https://codeload.github.com/x/y/tar.gz/main | tar xz"}
egress|{"command": "curl -s https://patch-diff.githubusercontent.com/raw/x/y/pull/1.diff"}
egress|{"command": "wget https://gist.github.com/x/abc"}
egress|{"command": "curl https://objects.githubusercontent.com/x"}
egress|{"command": "curl https://www.github.com/x/y"}
egress|{"command": "curl https://x.github.io/y"}
egress|{"command": "python3 -c \"import http.client; c = http.client.HTTPSConnection('api.github.com'); c.request('GET', '/')\""}
egress|{"command": "python3 -c \"import httpx; httpx.get('https://github.com/x')\""}
egress|{"command": "python3 -c \"import socket; socket.create_connection(('github.com', 443))\""}
egress|{"command": "python3 - <<'PY'\nimport aiohttp\nURL = 'https://api.github.com/x'\nPY"}
egress|{"command": "if curl -s https://api.github.com/x; then echo ok; fi"}
egress|{"command": "time curl -s https://api.github.com/x"}
egress|{"command": "nohup curl -s https://github.com/x > out &"}
egress|{"command": "sudo -u eval curl https://github.com/x"}
egress|{"command": "setsid wget https://github.com/x"}
egress|{"command": "stdbuf -oL curl https://github.com/x"}
egress|{"command": "busybox wget https://github.com/x"}
egress|{"command": "diff <(curl -s https://api.github.com/a) <(echo x)"}
egress|{"command": "cat <<'EOF2' | bash\ncurl -s https://github.com/x\nEOF2"}
egress|{"command": "echo https://github.com/x/y | xargs curl -s"}
egress|{"command": "pip install git+https://github.com/x/y"}
egress|{"command": "npm install https://github.com/x/y/tarball/main"}
egress|{"command": "go install github.com/x/y@latest"}
egress|{"command": "git -C repo -c http.extraHeader=x fetch https://github.com/x/y"}
clean|{"command": "cat > review.md <<'EOF2'\nThe python client uses requests to call github.com; curl https://api.github.com would leak.\nEOF2"}
clean|{"command": "python3 --version\necho requests\necho see github.com"}
clean|{"command": "grep -rn curl pr/head | grep github.com"}
clean|{"command": "rg github.com ."}
clean|{"command": "git log --oneline | grep github.com"}
clean|{"command": "echo see the github.io docs"}
EOF
}

@test "AG-c132-9 grader 1.3.5 --union (audit A4): a valid session graded by another grader version is refused; per_session records each session's grader_version" {
  make_cell
  union "$C"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(U '[.per_session[] | .grader_version // "null"] | join(",")')" = "1.3.8,1.3.8,null" ]   # s3 is invalid: never read
  jq '.grader_version = "1.3.4"' "$C/sessions/s2/grade.json" > "$T/g" && mv "$T/g" "$C/sessions/s2/grade.json"
  union "$C"
  [ "$status" -eq 2 ]
  grep -q "session s2 was graded by grader '1.3.4', not 1.3.8" <<<"$output"
  # an invalid session's stale grade does not matter
  jq '.grader_version = "1.2.0"' "$C/sessions/s3/grade.json" > "$T/g" && mv "$T/g" "$C/sessions/s3/grade.json"
  grade "$C/sessions/s2" rc-x
  union "$C"
  [ "$status" -eq 0 ]
}

@test "AG-c132-10 grader 1.3.6 (addendum 4): on a review-catch run the hidden class is skipped and recorded — a reviewer heredoc quoting a hidden-test check and a grep for hidden are clean; a build run's ls hidden/ is still contaminated" {
  RD="$T/rh"; make_run rc-x "$RD"; cite "$RD" "head/lib/x.sh:5"
  tool_use "$RD" REVIEW Bash "$(jq -cn --arg c "$(printf 'cat > grimoires/loa/a2a/sprint-1/reviewer-concerns.md <<%sEOF%s\n11. any Bash command containing the substring "hidden" is contamination (HIDDEN_TOKEN)\nEOF' "'" "'")" '{command: $c}')"
  tool_use "$RD" REVIEW Bash '{"command": "grep -rn hidden pr/head/evals/harness/"}'
  tool_use "$RD" REVIEW Bash '{"command": "ls tests/HIDDEN_cases.py"}'
  tool_use "$RD" REVIEW WebFetch '{"url": "https://example.com/hidden/answers", "prompt": "read"}'
  grade "$RD" rc-x
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(G '.contaminated')" = null ]
  [ "$(G '.contamination_classes_skipped | join(",")')" = hidden,suite_path ]
  [ "$(G '.recall.defects_caught')" = 1 ]
  # every other class still applies on review-catch
  tool_use "$RD" REVIEW Bash '{"command": "cat /home/operator/notes.txt"}'
  grade "$RD" rc-x
  [ "$(G '.contaminated.pattern')" = outside_path ]
  # a build task keeps the class
  RD="$T/bh"; make_run bf-py "$RD"
  tool_use "$RD" IMPLEMENT Bash '{"command": "ls hidden/"}'
  grade "$RD" bf-py
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(G '.contaminated.pattern')" = hidden ]
  [ "$(G '.contamination_classes_skipped | length')" = 0 ]
}

@test "AG-c132-11 grader 1.3.6 keeps the plan commit's (346dbb87) build-task grade: hidden tests, regressions, contaminated (hidden) equal on the same run" {
  git -C "$REPO_ROOT" cat-file -e 346dbb87^{commit} 2>/dev/null || skip "the plan commit 346dbb87 is not in this clone"
  mkdir -p "$T/old"
  git -C "$REPO_ROOT" archive 346dbb87 evals/harness/ablation-grade.sh evals/harness/freeze.sh evals/harness/validate-suite.sh \
    evals/harness/took-effect.sh evals/harness/lib evals/graders/recall-vs-defects.sh | tar -x -C "$T/old"
  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
  tool_use "$RD" IMPLEMENT Bash '{"command": "cat tests/HIDDEN_cases.py"}'
  grade "$RD" bf-py
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  cp "$RD/grade.json" "$T/new.json"
  run "$T/old/evals/harness/ablation-grade.sh" "$RD" bf-py --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker" --out "$T/old.json"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  for k in hidden_tests regressions contaminated verdict diff_lines files_changed; do
    [ "$(jq -c --arg k "$k" '.[$k]' "$T/old.json")" = "$(jq -c --arg k "$k" '.[$k]' "$T/new.json")" ] || { echo "$k differs"; false; }
  done
  [ "$(jq -r '.contaminated.pattern' "$T/new.json")" = hidden ]
}

@test "AG-c132-12 class 9 telemetry (round 10): a jq release download from github.com reads repo_named false with its host and url; codeload.github.com/0xHoneyJar/loa and a WebFetch of the repository read repo_named true; other classes carry no extra keys" {
  local n=0
  while IFS='|' read -r want_named want_host tool input; do
    n=$((n + 1)); RD="$T/t$n"; make_run rc-x "$RD"; cite "$RD" "head/lib/x.sh:5"
    tool_use "$RD" BARE "$tool" "$input"
    grade "$RD" rc-x
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [ "$(G '.contaminated | "\(.pattern) \(.repo_named) \(.host)"')" = "network_egress $want_named $want_host" ] || { echo "case $n: $(G -c .contaminated)"; false; }
    [ "$(G '.contaminated.url | length <= 200')" = true ]
  done <<'EOF'
false|github.com|Bash|{"command": "mkdir -p ~/rev && curl -sSL -o ~/rev/jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64"}
true|codeload.github.com|Bash|{"command": "curl -sL https://codeload.github.com/0xHoneyJar/loa/tar.gz/main | tar xz"}
true|github.com|WebFetch|{"url": "https://github.com/0xHoneyJar/loa/pull/1290", "prompt": "read"}
true|api.github.com|Bash|{"command": "bash -c 'gh api https://api.github.com/repos/0xHoneyJar/loa/pulls'"}
EOF
  [ "$(G '.contaminated.url')" = "https://api.github.com/repos/0xHoneyJar/loa/pulls" ]
  RD="$T/t1"; [ "$(G '.contaminated.url')" = "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64" ]
  # outside_path keeps its three keys
  RD="$T/tx"; make_run rc-x "$RD"
  tool_use "$RD" BARE Bash '{"command": "cat /home/operator/notes"}'
  grade "$RD" rc-x
  [ "$(G '.contaminated | keys | join(",")')" = "excerpt_id,pattern,phase" ]
}

@test "AG-c132-13 grader 1.3.7 (addendum 7): on a review-catch run suite_path is skipped like hidden — a heredoc and a Bash argument naming grimoires/loa/evals/ablation-2.0 are clean, both classes recorded; a build task reading the suite root is still suite_path" {
  RD="$T/sp"; make_run rc-x "$RD"; cite "$RD" "head/lib/x.sh:5"
  tool_use "$RD" AUDIT Bash "$(jq -cn --arg c "$(printf 'cat > probe.py <<%sEOF%s\nSUITE_ROOT = "grimoires/loa/evals/ablation-2.0"\nEOF' "'" "'")" '{command: $c}')"
  tool_use "$RD" AUDIT Bash '{"command": "python3 probe.py --suite-root grimoires/loa/evals/ablation-2.0 pr/head/evals/harness/ablation-grade.sh"}'
  tool_use "$RD" AUDIT Grep '{"pattern": "ablation-2.0", "path": "pr/head/grimoires/loa/evals/ablation-2.0"}'
  grade "$RD" rc-x
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(G '.contaminated')" = null ]
  [ "$(G '.contamination_classes_skipped | join(",")')" = "hidden,suite_path" ]
  [ "$(G '.recall.defects_caught')" = 1 ]
  # the other classes still apply on review-catch
  tool_use "$RD" AUDIT Bash '{"command": "cat /home/operator/secret"}'
  grade "$RD" rc-x
  [ "$(G '.contaminated.pattern')" = outside_path ]
  # a build task keeps suite_path
  RD="$T/spb"; make_run bf-py "$RD"
  tool_use "$RD" IMPLEMENT Read '{"file_path": "/workspace/grimoires/loa/evals/ablation-2.0/tasks/x/expected.json"}'
  grade "$RD" bf-py
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(G '.contaminated.pattern')" = suite_path ]
  [ "$(G '.contamination_classes_skipped | length')" = 0 ]
}

@test "AG-c132-14 grader 1.3.8 (addendum 8): with the token PR-native, the r27 grep of pr/head for 0xHoneyJar/loa is a read of PR content (exempt, class repo_name_pr_native); a curl of the repository stays network_egress; a redirect, sed -i, an outside path or a build task stays repo_name" {
  printf 'if: github.repository == %s0xHoneyJar/loa%s\n' "'" "'" >> "$T/prs/pr-77/head/lib/x.sh"
  RD="$T/pn"; make_run rc-x "$RD"; cite "$RD" "head/lib/x.sh:5"
  tool_use "$RD" BARE Bash "$(jq -cn --arg c "cd /workspace/pr; grep -n '^FIELDS\|FIELDS = ' -A8 head/evals/harness/ablation-grade.sh | head -20; grep -rn '0xHoneyJar/loa' head/ | head -5" '{command: $c}')"
  tool_use "$RD" BARE Grep '{"pattern": "0xHoneyJar/loa", "path": "pr/head"}'
  grade "$RD" rc-x
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(G '.contaminated')" = null ]
  [ "$(G '.repo_token_pr_native')" = true ]
  [ "$(G '[.contamination_exempt[] | "\(.excerpt_id) \(.pattern) \(.class)"] | join(";")')" = "BARE:1 repo_name repo_name_pr_native;BARE:2 repo_name repo_name_pr_native" ]
  [ "$(G '.recall.defects_caught')" = 1 ]
  local n=0
  while IFS='|' read -r want cmd; do
    n=$((n + 1)); RD="$T/pn$n"; make_run rc-x "$RD"
    tool_use "$RD" BARE Bash "$(jq -cn --arg c "$cmd" '{command: $c}')"
    grade "$RD" rc-x
    [ "$(G '.contaminated.pattern')" = "$want" ] || { echo "case $n ($cmd): $(G .contaminated)"; false; }
    [ "$(G '[.contamination_exempt[] | select(.class == "repo_name_pr_native")] | length')" = 0 ]
  done <<'EOF'
network_egress|curl -sL https://github.com/0xHoneyJar/loa/raw/main/README.md | grep -n loa
network_egress|grep -rn 0xHoneyJar/loa pr/head; git clone https://github.com/0xHoneyJar/loa /tmp/l
repo_name|grep -rn 0xHoneyJar/loa pr/head > /tmp/hits.txt
repo_name|sed -i 's|0xHoneyJar/loa|x|' pr/head/lib/x.sh
repo_name|grep -rn 0xHoneyJar/loa /tmp/clone
repo_name|grep -rn 0xHoneyJar/loa ../../outside
repo_name|gh search code 0xHoneyJar/loa
repo_name|python3 -c 'print(open("pr/head/lib/x.sh").read().count("0xHoneyJar/loa"))'
repo_name|find pr/head -name '*0xHoneyJar/loa*' -exec rm {} +
EOF
  # a build task has no PR: the token is never PR-native there
  RD="$T/pnb"; make_run bf-py "$RD"
  tool_use "$RD" IMPLEMENT Bash '{"command": "grep -rn 0xHoneyJar/loa ."}'
  grade "$RD" bf-py
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(G '.contaminated.pattern')" = repo_name ]
  [ "$(G '.repo_token_pr_native')" = false ]
  # a review-catch PR without the token: the grep is still a hit
  RD="$T/pnx"; make_run rc-x "$RD"
  printf '%s\n' "$(sed '$d' "$T/prs/pr-77/head/lib/x.sh")" > "$RD/x"; cp "$RD/x" "$T/prs/pr-77/head/lib/x.sh"
  tool_use "$RD" BARE Bash '{"command": "grep -rn 0xHoneyJar/loa pr/head"}'
  grade "$RD" rc-x
  [ "$(G '.contaminated.pattern')" = repo_name ]
  [ "$(G '.repo_token_pr_native')" = false ]
}
