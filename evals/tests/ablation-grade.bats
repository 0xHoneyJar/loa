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

BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  GRADER="$REPO_ROOT/evals/harness/ablation-grade.sh"
  SMOKE="$REPO_ROOT/grimoires/loa/evals/ablation-2.0/smoke"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/ag.XXXXXX")"
  S="$T/suite"
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
exec env PYTHONUSERBASE="$ub" /usr/bin/python3 "\$@"
EOF
  ln -s "$BATS_BIN" "$T/bin/bats"
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
  # the docker argv: no network, read-only root, tmpfs, the caller's uid, one rw mount, the pytest shape
  argv="$(tr '\0' ' ' < "$T/dlog/run-1.argv")"
  [[ "$argv" == *"run --rm --network none --read-only --tmpfs /tmp:rw,size=256m --user $(id -u):$(id -g) -v $RD/grading/final:/workspace:rw -w /workspace -e HOME=/tmp -e LC_ALL=C -e TMPDIR=/tmp loa-ablation:258 timeout 120 python3 -I -s -m pytest -p no:cacheprovider -q --rootdir /workspace -rA tests "* ]]
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
  cat "$T"/dlog/run-*.argv | tr '\0' ' ' | grep -q -- 'timeout 120 bats --tap tests'
}

@test "AG-18 end to end: a pipeline-run.sh run (stub CLI, stub mount library) grades with its real bundles and gate files" {
  local H="$T/h/evals/harness" sk
  mkdir -p "$H/lib" "$T/src/.claude/loa" "$T/home"
  cp "$REPO_ROOT/evals/harness/pipeline-run.sh" "$REPO_ROOT/evals/harness/fingerprint.sh" "$H/"
  cp -a "$REPO_ROOT/evals/harness/lib/phase-prompts" "$H/lib/"
  cp "$TESTS_DIR/fixtures/mount-lib-stub.sh" "$H/lib/sandbox-mount.sh"
  for sk in planning-sprints implementing-tasks reviewing-code auditing-security; do
    mkdir -p "$T/src/.claude/skills/$sk"; printf -- '---\nname: %s\neffort: xhigh\n---\nbody\n' "$sk" > "$T/src/.claude/skills/$sk/SKILL.md"
  done
  echo loa > "$T/src/.claude/loa/CLAUDE.loa.md"; printf 'flatline_protocol:\n  enabled: true\n' > "$T/src/.loa.config.yaml"
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
  local i=0 tool inp want
  while IFS=$'\t' read -r tool inp want; do
    i=$((i + 1)); RD="$T/c$i"; make_run rc-x "$RD"
    tool_use "$RD" IMPLEMENT Bash '{"command": "ls"}'
    tool_use "$RD" IMPLEMENT "$tool" "$inp"
    grade "$RD" rc-x
    [ "$status" -eq 0 ]
    [ "$(G '.contaminated | "\(.phase) \(.pattern) \(.excerpt_id)"')" = "IMPLEMENT $want IMPLEMENT:2" ]
    [ "$(G '.contaminated | keys | join(",")')" = "excerpt_id,pattern,phase" ]
  done <<'EOF'
Bash	{"command": "cat tests/HIDDEN_cases.py"}	hidden
Read	{"file_path": "/workspace/grimoires/loa/evals/ablation-2.0/tasks/x/task.yaml"}	suite_path
WebFetch	{"url": "https://github.com/0xHoneyJar/loa/tree/main", "prompt": "read"}	repo_name
WebFetch	{"url": "https://example.com/hidden/answers", "prompt": "read"}	hidden
WebSearch	{"query": "0xhoneyjar/loa ablation tasks"}	repo_name
Bash	{"command": "git log --oneline --all | head"}	git_history
Bash	{"command": "git reflog"}	git_history
Read	{"file_path": "/home/operator/code/loa/README.md"}	outside_path
Bash	{"command": "cat /home/operator/notes.txt 2>/dev/null"}	outside_path
Glob	{"pattern": "/srv/**/*.py"}	outside_path
EOF
  # first hit in phase order: IMPLEMENT before REVIEW whatever the file names sort to
  RD="$T/order"; make_run rc-x "$RD"
  tool_use "$RD" REVIEW Bash '{"command": "git reflog"}'
  tool_use "$RD" IMPLEMENT Bash '{"command": "ls"}'
  tool_use "$RD" IMPLEMENT Read '{"file_path": "/root/x"}'
  grade "$RD" rc-x
  [ "$(G '.contaminated | "\(.phase) \(.pattern) \(.excerpt_id)"')" = "IMPLEMENT outside_path IMPLEMENT:2" ]
  ! grep -q '/root/x' "$RD/grade.json"
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
  tool_use "$RD" IMPLEMENT Read "$(jq -cn --arg p "$HOME/.claude/settings.json" '{file_path: $p}')"
  run "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --executor host
  [ "$status" -eq 0 ]
  [ "$(G '.contaminated')" = null ] && [ "$(G '.image')" = null ] && [ "$(G '.executor_mode')" = host ]
  tool_use "$RD" AUDIT Read '{"file_path": "/home/evaluser/x"}'
  run "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --executor host
  [ "$(G '.contaminated | "\(.phase) \(.pattern)"')" = "AUDIT outside_path" ]
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
  [ "$(grep -c 'meta/' "$GRADER")" -eq 1 ]
  grep -n 'meta/' "$GRADER" | grep -q '^[0-9]*:# '
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
  [ "$(G '.regressions | "\(.base.passed)/\(.base.total) \(.final.passed)/\(.final.total)"')" = "1/1 0/1" ]
  # green at both ends: nothing newly failing, still marked unparsed
  RD="$T/run2"; make_run bf-tap "$RD"; apply_ref "$RD"
  grade "$RD" bf-tap
  [ "$(G '.regressions | "\(.newly_failing | length) \(.parse_error)"')" = "0 true" ]
}
