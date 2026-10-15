#!/usr/bin/env bats
# =============================================================================
# evals/tests/freeze.bats — cycle-130 Sprint 258 Task 1.11 (PRD AC-5.1, sprint
# AC-1.13, SDD §5.13, DEC-0414)
#
# freeze.sh writes MANIFEST.sha256 over every file under tasks/ (smoke/ with
# --smoke) after validate-suite.sh passes; --check recomputes and fails on any
# drift, one changed byte included, naming the path.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  FZ="$REPO_ROOT/evals/harness/freeze.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/fz.XXXXXX")"
  R="$T/suite"; mkdir -p "$R"
  export LOA_EVAL_PHASE_PROMPTS_DIR="$T/no-prompts"
  # shellcheck source=fixtures/ablation/suite-lib.bash
  source "$TESTS_DIR/fixtures/ablation/suite-lib.bash"
  # shellcheck source=../../.claude/scripts/compat-lib.sh
  source "$REPO_ROOT/.claude/scripts/compat-lib.sh"
  make_task "$R" tasks bug-fix-01 bug-fix
  make_task "$R" tasks review-catch-01 review-catch
}

teardown() {
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

@test "FZ-1 freeze writes one sorted '<sha256>  <relpath>' line per file under tasks/; --check then passes" {
  run "$FZ" --root "$R" --allow-partial
  [ "$status" -eq 0 ]
  grep -q '^freeze: wrote MANIFEST.sha256 (' <<<"$output"
  M="$R/MANIFEST.sha256"
  [ "$(grep -c . "$M")" -eq "$(cd "$R" && find tasks -type f | wc -l | tr -d ' ')" ]
  [ "$(awk '{print $2}' "$M")" = "$(awk '{print $2}' "$M" | LC_ALL=C sort)" ]
  ! grep -qv '^[0-9a-f]\{64\}  tasks/' "$M"
  want="$(cd "$R" && sha256_portable tasks/bug-fix-01/task.yaml)"
  grep -qxF "$want" "$M"
  run "$FZ" --root "$R" --allow-partial --check
  [ "$status" -eq 0 ]
  grep -q '^freeze: OK — ' <<<"$output"
}

@test "FZ-2 one changed byte under tasks/ is drift: --check exits 1 and names the path; added and removed files too" {
  "$FZ" --root "$R" --allow-partial >/dev/null
  f="$R/tasks/bug-fix-01/hidden/tests/test_slug.py"
  printf 'X' | dd of="$f" bs=1 seek=0 count=1 conv=notrunc 2>/dev/null
  run "$FZ" --root "$R" --allow-partial --check
  [ "$status" -eq 1 ]
  grep -q 'changed  tasks/bug-fix-01/hidden/tests/test_slug.py' <<<"$output"
  "$FZ" --root "$R" --allow-partial >/dev/null
  echo extra > "$R/tasks/bug-fix-01/hidden/tests/extra.txt"
  run "$FZ" --root "$R" --allow-partial --check
  [ "$status" -eq 1 ]
  grep -q 'added    tasks/bug-fix-01/hidden/tests/extra.txt' <<<"$output"
  rm "$R/tasks/bug-fix-01/hidden/tests/extra.txt"
  "$FZ" --root "$R" --allow-partial >/dev/null
  rm "$R/tasks/bug-fix-01/hidden/reference.patch"
  yq -i '.reference_patch = null | .type = "refactor" | .structural_check = "hidden/tests/test_slug.py"' "$R/tasks/bug-fix-01/task.yaml"
  run "$FZ" --root "$R" --allow-partial --check
  [ "$status" -eq 1 ]
  grep -q 'removed  tasks/bug-fix-01/hidden/reference.patch' <<<"$output"
  grep -q 'changed  tasks/bug-fix-01/task.yaml' <<<"$output"
}

@test "FZ-3 an invalid suite is never frozen: exit 1, no manifest written" {
  echo "uses hidden tests" >> "$R/tasks/bug-fix-01/TASK.md"
  run "$FZ" --root "$R" --allow-partial
  [ "$status" -eq 1 ]
  grep -q 'refused — the suite does not validate' <<<"$output"
  [ ! -e "$R/MANIFEST.sha256" ]
}

@test "FZ-4 --smoke covers smoke/; without it smoke files are outside the manifest" {
  make_task "$R" smoke smoke-x bug-fix
  "$FZ" --root "$R" --allow-partial >/dev/null
  ! grep -q '  smoke/' "$R/MANIFEST.sha256"
  "$FZ" --root "$R" --allow-partial --smoke >/dev/null
  grep -q '  smoke/smoke-x/task.yaml$' "$R/MANIFEST.sha256"
  echo y >> "$R/smoke/smoke-x/fixture/src/textkit/__init__.py"
  run "$FZ" --root "$R" --allow-partial --smoke --check
  [ "$status" -eq 1 ]
  grep -q 'changed  smoke/smoke-x/fixture/src/textkit/__init__.py' <<<"$output"
}

@test "FZ-5 --check without a manifest is exit 1; usage errors are exit 2" {
  run "$FZ" --root "$R" --allow-partial --check
  [ "$status" -eq 1 ]
  grep -q 'no MANIFEST.sha256' <<<"$output"
  run "$FZ" --bogus
  [ "$status" -eq 2 ]
  run "$FZ" --root "$T/absent"
  [ "$status" -eq 2 ]
}

@test "FZ-6 the committed suite root's MANIFEST.sha256 matches its smoke tasks" {
  run "$FZ" --smoke --allow-partial --check
  [ "$status" -eq 0 ]
}
