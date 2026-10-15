#!/usr/bin/env bats
# =============================================================================
# evals/tests/validate-suite.bats — cycle-130 Sprint 258 Task 1.11 (DEC-0424,
# sprint AC-1.13, SDD §3.2)
#
# validate-suite.sh on fixture suites built from the committed smoke tasks
# (fixtures/ablation/suite-lib.bash): each check's pass and fail — schema, the
# four-by-four counts (relaxed by --allow-partial), the test_command allowlist,
# hidden/manifest.json destinations, the fixture path rule, leakage strings in
# TASK.md / criterion / phase prompts, the suite file's task_types.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  VS="$REPO_ROOT/evals/harness/validate-suite.sh"
  SUITE="$REPO_ROOT/evals/suites/ablation-2.0.yaml"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/vs.XXXXXX")"
  R="$T/suite"; mkdir -p "$R"
  # no phase prompts unless a test supplies them
  export LOA_EVAL_PHASE_PROMPTS_DIR="$T/no-prompts"
  # shellcheck source=fixtures/ablation/suite-lib.bash
  source "$TESTS_DIR/fixtures/ablation/suite-lib.bash"
}

teardown() {
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

@test "VS-1 the committed suite (tasks/ and smoke/) validates with --allow-partial; without it, every type short of four tasks is one counts line" {
  CR="$REPO_ROOT/grimoires/loa/evals/ablation-2.0"
  n="$(find "$CR/tasks" "$CR/smoke" -mindepth 2 -maxdepth 2 -name task.yaml 2>/dev/null | wc -l | tr -d ' ')"
  short=0
  for ty in feature-build bug-fix refactor review-catch; do
    c="$(cat "$CR"/tasks/*/task.yaml 2>/dev/null | grep -c "^type: $ty\$" || true)"
    [ "$c" -eq 4 ] || short=$((short + 1))
  done
  run "$VS" --smoke --allow-partial
  [ "$status" -eq 0 ]
  grep -q "OK — $n task(s) valid" <<<"$output"
  run "$VS" --smoke
  [ "$(grep -c 'counts:' <<<"$output")" -eq "$short" ]
  if [ "$short" -gt 0 ]; then [ "$status" -eq 1 ]; else [ "$status" -eq 0 ]; fi
}

@test "VS-2 a four-by-four suite validates; one task short fails the counts unless --allow-partial; smoke tasks never count" {
  make_full_suite "$R"
  run "$VS" --root "$R"
  [ "$status" -eq 0 ]
  grep -q 'OK — 16 task(s) valid' <<<"$output"
  find "$R/tasks/refactor-04" -delete
  run "$VS" --root "$R"
  [ "$status" -eq 1 ]
  grep -q 'suite: counts: 3 refactor task(s) under tasks/, want 4' <<<"$output"
  run "$VS" --root "$R" --allow-partial
  [ "$status" -eq 0 ]
  make_task "$R" smoke smoke-refactor-x refactor
  run "$VS" --root "$R" --smoke
  [ "$status" -eq 1 ]
  grep -q '3 refactor task(s)' <<<"$output"
}

@test "VS-3 leakage: 'hidden', a hidden test stem, an arm id or a defect key in TASK.md, and a path in the criterion, are each listed" {
  make_task "$R" tasks bug-fix-01 bug-fix
  make_task "$R" tasks review-catch-01 review-catch
  echo "The grader keeps hidden tests." >> "$R/tasks/bug-fix-01/TASK.md"
  echo "See test_slug for the cases." >> "$R/tasks/bug-fix-01/TASK.md"
  echo "This run is the a1_full arm." >> "$R/tasks/review-catch-01/TASK.md"
  echo "Key: D01-decoy-flag-reanchor" >> "$R/tasks/review-catch-01/TASK.md"
  yq -i '.criterion = "fix src/textkit/slug.py"' "$R/tasks/bug-fix-01/task.yaml"
  run "$VS" --root "$R" --allow-partial
  [ "$status" -eq 1 ]
  grep -q "tasks/bug-fix-01: leak: TASK.md contains the string 'hidden'" <<<"$output"
  grep -q "tasks/bug-fix-01: leak: TASK.md names the grader file stem 'test_slug'" <<<"$output"
  grep -q "tasks/bug-fix-01: schema: criterion names a path or file" <<<"$output"
  grep -q "tasks/review-catch-01: leak: TASK.md names arm id 'a1_full'" <<<"$output"
  grep -q "tasks/review-catch-01: leak: TASK.md names defect id 'D01-decoy-flag-reanchor'" <<<"$output"
  grep -q "tasks/review-catch-01: leak: TASK.md carries a defect key pattern 'D01-'" <<<"$output"
  # the clean templates pass the same checks
  make_task "$T/clean" tasks bug-fix-01 bug-fix
  run "$VS" --root "$T/clean" --allow-partial
  [ "$status" -eq 0 ]
}

@test "VS-4 leakage in a phase prompt is listed for every task" {
  make_task "$R" tasks bug-fix-01 bug-fix
  mkdir -p "$T/prompts"; echo "Do not look for the hidden tests." > "$T/prompts/IMPLEMENT.md"
  LOA_EVAL_PHASE_PROMPTS_DIR="$T/prompts" run "$VS" --root "$R" --allow-partial
  [ "$status" -eq 1 ]
  grep -q "tasks/bug-fix-01: leak: phase-prompts/IMPLEMENT.md contains the string 'hidden'" <<<"$output"
}

@test "VS-5 allowlist: a test_command or regression_command outside python3|pytest|bats|bash|node|npx is refused" {
  make_task "$R" tasks bug-fix-01 bug-fix
  yq -i '.test_command = ["curl", "http://example.invalid"]' "$R/tasks/bug-fix-01/task.yaml"
  yq -i '.regression_command = ["sh", "-c", "true"]' "$R/tasks/bug-fix-01/task.yaml"
  run "$VS" --root "$R" --allow-partial
  [ "$status" -eq 1 ]
  grep -q "allowlist: test_command\[0\] 'curl'" <<<"$output"
  grep -q "allowlist: regression_command\[0\] 'sh'" <<<"$output"
}

@test "VS-6 hidden/manifest.json: a '..' dest, an absolute dest, a missing src and a mount-owned dest are refused" {
  make_task "$R" tasks bug-fix-01 bug-fix
  printf '%s\n' '{"files": [{"src": "tests/test_slug.py", "dest": "../escape.py"},' \
    '{"src": "tests/test_slug.py", "dest": "/etc/x.py"},' \
    '{"src": "tests/absent.py", "dest": "tests/a.py"},' \
    '{"src": "tests/test_slug.py", "dest": ".claude/x.py"}]}' > "$R/tasks/bug-fix-01/hidden/manifest.json"
  run "$VS" --root "$R" --allow-partial
  [ "$status" -eq 1 ]
  grep -q 'hidden: manifest dest must be a relative path inside the tree: ../escape.py' <<<"$output"
  grep -q 'hidden: manifest dest must be a relative path inside the tree: /etc/x.py' <<<"$output"
  grep -q 'hidden: manifest src not found under hidden/: tests/absent.py' <<<"$output"
  grep -q 'hidden: manifest dest lands on a mount-owned path: .claude/x.py' <<<"$output"
}

@test "VS-7 fixture path rule: a fixture holding .claude/ or grimoires/, or a reference patch touching .claude/, is refused" {
  make_task "$R" tasks bug-fix-01 bug-fix
  make_task "$R" tasks bug-fix-02 bug-fix
  mkdir -p "$R/tasks/bug-fix-01/fixture/.claude/scripts"; echo x > "$R/tasks/bug-fix-01/fixture/.claude/scripts/x.sh"
  mkdir -p "$R/tasks/bug-fix-02/fixture/grimoires/loa"; echo x > "$R/tasks/bug-fix-02/fixture/grimoires/loa/NOTES.md"
  sed -i 's|^+++ b/src/textkit/slug.py|+++ b/.claude/scripts/slug.py|' "$R/tasks/bug-fix-02/hidden/reference.patch"
  run "$VS" --root "$R" --allow-partial
  [ "$status" -eq 1 ]
  grep -q 'tasks/bug-fix-01: fixture path rule: .*holds paths the Loa mount owns: .claude' <<<"$output"
  grep -q 'tasks/bug-fix-02: fixture path rule: .*holds paths the Loa mount owns: grimoires' <<<"$output"
  grep -q 'tasks/bug-fix-02: fixture path rule: reference patch touches a mount-owned path: .claude/scripts/slug.py' <<<"$output"
}

@test "VS-8 schema: a missing field, an unknown type, a suite_version mismatch, a review-catch without review_catch and a refactor without structural_check are all listed" {
  make_task "$R" tasks bug-fix-01 bug-fix
  make_task "$R" tasks review-catch-01 review-catch
  make_task "$R" tasks refactor-01 refactor
  make_task "$R" tasks odd-01 bug-fix
  yq -i 'del(.success_criterion)' "$R/tasks/bug-fix-01/task.yaml"
  yq -i '.suite_version = 2' "$R/tasks/bug-fix-01/task.yaml"
  yq -i '.review_catch = null' "$R/tasks/review-catch-01/task.yaml"
  yq -i '.structural_check = null' "$R/tasks/refactor-01/task.yaml"
  yq -i '.type = "chore" | .post_cutoff = "yes"' "$R/tasks/odd-01/task.yaml"
  run "$VS" --root "$R" --allow-partial
  [ "$status" -eq 1 ]
  grep -q "tasks/bug-fix-01: schema: missing field 'success_criterion'" <<<"$output"
  grep -q "tasks/bug-fix-01: schema: suite_version 2 differs from the suite file's 1" <<<"$output"
  grep -q "tasks/review-catch-01: schema: review_catch {fixture, manifest} is required for review-catch" <<<"$output"
  grep -q "tasks/refactor-01: schema: structural_check is required for refactor" <<<"$output"
  grep -q "tasks/odd-01: schema: type 'chore' not in" <<<"$output"
  grep -q "tasks/odd-01: schema: post_cutoff must be a boolean" <<<"$output"
  [ "$(grep -c ': schema: ' <<<"$output")" -ge 6 ]
}

@test "VS-9 suite file: an arm whose task_types names an unknown type is refused; the committed suite file passes" {
  make_task "$R" tasks bug-fix-01 bug-fix
  cp "$SUITE" "$T/suite.yaml"
  yq -i '(.arms[] | select(.id == "a4_no_gates") | .task_types) = ["builds"]' "$T/suite.yaml"
  run "$VS" --root "$R" --allow-partial --suite-file "$T/suite.yaml"
  [ "$status" -eq 1 ]
  grep -q "suite: arm a4_no_gates task_types names unknown type 'builds'" <<<"$output"
  run "$VS" --root "$R" --allow-partial --suite-file "$SUITE"
  [ "$status" -eq 0 ]
}

@test "VS-10 usage: an unknown option, a missing root or suite file is exit 2" {
  run "$VS" --bogus
  [ "$status" -eq 2 ]
  run "$VS" --root "$T/absent"
  [ "$status" -eq 2 ]
  run "$VS" --root "$R" --suite-file "$T/absent.yaml"
  [ "$status" -eq 2 ]
}

@test "VS-11 source.churn (Sprint 259 refactor tasks): {files, insertions, deletions} of non-negative integers validates; a missing key, a negative count or a non-mapping is listed" {
  make_task "$R" tasks refactor-01 refactor
  yq -i '.source.churn = {"files": 2, "insertions": 30, "deletions": 41}' "$R/tasks/refactor-01/task.yaml"
  run "$VS" --root "$R" --allow-partial
  [ "$status" -eq 0 ]
  yq -i '.source.churn = {"files": 2, "insertions": 30}' "$R/tasks/refactor-01/task.yaml"
  run "$VS" --root "$R" --allow-partial
  [ "$status" -eq 1 ]
  grep -q 'tasks/refactor-01: schema: source.churn must be {files, insertions, deletions}' <<<"$output"
  yq -i '.source.churn = {"files": 2, "insertions": -1, "deletions": 0}' "$R/tasks/refactor-01/task.yaml"
  run "$VS" --root "$R" --allow-partial
  [ "$status" -eq 1 ]
  yq -i '.source.churn = "big"' "$R/tasks/refactor-01/task.yaml"
  run "$VS" --root "$R" --allow-partial
  [ "$status" -eq 1 ]
  grep -q 'source.churn must be' <<<"$output"
  # any other unknown source key is still refused
  yq -i 'del(.source.churn) | .source.size = 3' "$R/tasks/refactor-01/task.yaml"
  run "$VS" --root "$R" --allow-partial
  [ "$status" -eq 1 ]
  grep -q 'schema: source.size is not a known key' <<<"$output"
}
