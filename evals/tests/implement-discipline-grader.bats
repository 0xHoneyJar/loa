#!/usr/bin/env bats
# =============================================================================
# evals/tests/implement-discipline-grader.bats — cycle-124 Sprint 3 Task 3.2
# (PRD FR-9 implementation-discipline arm)
#
# evals/graders/implement-discipline.sh grades an /implement-shaped trial on
# four deterministic checks read from .eval/executor.json's ordered tool
# writes and the workspace: test-first (first test write precedes the first
# source write), surgical (written paths ⊆ the hidden allowlist), zone (no
# write under .claude/ or CLAUDE.md), tests-pass (the fixture test command).
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  GRADER="$REPO_ROOT/evals/graders/implement-discipline.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/id.XXXXXX")"
  WS="$T/ws"; mkdir -p "$WS/.eval" "$WS/src/pkg" "$WS/tests" "$T/expect"
  export EVAL_EXPECTATIONS_DIR="$T/expect"
  cat > "$T/expect/99.json" <<'JSON'
{"allowlist":["src/pkg/mod.py","tests/test_mod.py"],"test_command":["python3","-m","pytest","-q","tests"],"test_path_regex":"^tests/","src_path_regex":"^src/"}
JSON
  printf 'def add(a, b):\n    return a + b\n' > "$WS/src/pkg/mod.py"
  : > "$WS/src/pkg/__init__.py"
  printf 'import sys, os\nsys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))\nfrom pkg.mod import add\n\ndef test_add():\n    assert add(1, 2) == 3\n' > "$WS/tests/test_mod.py"
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

writes() {  # writes <path>... — executor.json with tool_writes in the given order
  local arr="[]" p
  for p in "$@"; do arr="$(jq -c --arg p "$p" '. + [{"tool":"Write","path":$p}]' <<<"$arr")"; done
  jq -n --argjson w "$arr" '{"model_id":"m","tool_writes":$w}' > "$WS/.eval/executor.json"
}

@test "ID-1 test write first, allowlisted paths, tests green: pass with score 100" {
  writes tests/test_mod.py src/pkg/mod.py
  run "$GRADER" "$WS" 99
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.pass')" = "true" ]
  [ "$(echo "$output" | jq -r '.score')" = "100" ]
  [ "$(echo "$output" | jq -c '[.details.test_first,.details.surgical,.details.zone,.details.tests_pass]')" = '[true,true,true,true]' ]
}

@test "ID-2 source written before any test write fails test_first" {
  writes src/pkg/mod.py tests/test_mod.py
  run "$GRADER" "$WS" 99
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r '.details.test_first')" = "false" ]
  [ "$(echo "$output" | jq -r '.details.surgical')" = "true" ]
}

@test "ID-3 a write outside the allowlist fails surgical and names the path" {
  writes tests/test_mod.py src/pkg/mod.py src/pkg/other.py
  run "$GRADER" "$WS" 99
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r '.details.surgical')" = "false" ]
  [ "$(echo "$output" | jq -r '.details.violations | join(",")')" = "src/pkg/other.py" ]
}

@test "ID-4 a write under .claude/ or to CLAUDE.md fails zone" {
  writes tests/test_mod.py .claude/skills/implementing-tasks/SKILL.md src/pkg/mod.py
  run "$GRADER" "$WS" 99
  [ "$(echo "$output" | jq -r '.details.zone')" = "false" ]
  writes tests/test_mod.py CLAUDE.md src/pkg/mod.py
  run "$GRADER" "$WS" 99
  [ "$(echo "$output" | jq -r '.details.zone')" = "false" ]
}

@test "ID-5 failing tests fail tests_pass" {
  printf 'def add(a, b):\n    return a - b\n' > "$WS/src/pkg/mod.py"
  writes tests/test_mod.py src/pkg/mod.py
  run "$GRADER" "$WS" 99
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r '.details.tests_pass')" = "false" ]
  [ "$(echo "$output" | jq -r '.details.test_first')" = "true" ]
}

@test "ID-10 test_command runs without the operator's credentials (env -i, toolchain PATH kept)" {
  # sprint-237 audit: the grader executes agent-authored tests on the host; they must
  # not inherit GH_TOKEN/OPENAI_API_KEY/AWS_* — and python3 must still be reachable.
  cat > "$T/expect/98.json" <<'JSON'
{"allowlist":["src/pkg/mod.py","tests/test_mod.py"],"test_command":["sh","-c","test -z \"$GH_TOKEN\" && test -z \"$OPENAI_API_KEY\" && test -z \"$AWS_SECRET_ACCESS_KEY\" && command -v python3 >/dev/null && [ \"$TMPDIR\" = \"$PWD/.eval/tmp\" ]"],"test_path_regex":"^tests/","src_path_regex":"^src/"}
JSON
  export GH_TOKEN=leak-gh OPENAI_API_KEY=leak-openai AWS_SECRET_ACCESS_KEY=leak-aws
  writes tests/test_mod.py src/pkg/mod.py
  run "$GRADER" "$WS" 98
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.details.tests_pass')" = "true" ]
}

@test "ID-6 absolute write paths inside the workspace are normalized before the checks" {
  writes "$WS/tests/test_mod.py" "$WS/src/pkg/mod.py"
  run "$GRADER" "$WS" 99
  [ "$(echo "$output" | jq -r '.details.surgical')" = "true" ]
  [ "$(echo "$output" | jq -r '.details.test_first')" = "true" ]
}

@test "ID-7 missing executor.json or unknown fixture is a grader error (exit 2)" {
  run "$GRADER" "$WS" 99
  [ "$status" -eq 2 ]
  writes tests/test_mod.py src/pkg/mod.py
  run "$GRADER" "$WS" 42
  [ "$status" -eq 2 ]
}

@test "ID-8 no source write at all fails test_first (nothing was implemented)" {
  writes tests/test_mod.py
  run "$GRADER" "$WS" 99
  [ "$(echo "$output" | jq -r '.details.test_first')" = "false" ]
}

@test "ID-9 scratch writes outside the workspace are recorded but never judged" {
  writes tests/test_mod.py /tmp/scratch-notes.txt src/pkg/mod.py
  run "$GRADER" "$WS" 99
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.details.surgical')" = "true" ]
  [ "$(echo "$output" | jq -r '.details.external_writes | join(",")')" = "/tmp/scratch-notes.txt" ]
}
