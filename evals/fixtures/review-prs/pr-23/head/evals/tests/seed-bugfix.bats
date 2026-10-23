#!/usr/bin/env bats
# =============================================================================
# evals/tests/seed-bugfix.bats — cycle-130 Sprint 259 Task 2.2 (SDD §5.14,
# sprint AC-2.9)
#
# seed-bugfix-tasks.sh over a throwaway git repo: a clean fix commit (a Python
# module + its test, red at the parent, green at the commit) becomes a task
# whose every field validates; a fix touching .claude/ is refused by name and
# writes nothing; --dry-run writes nothing; a fix whose test is already green
# at the parent fails its proof (exit 1, nothing written); a fix outside the
# allowed roots is skipped; usage errors are exit 2.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  SEED="$REPO_ROOT/evals/harness/seed-bugfix-tasks.sh"
  VS="$REPO_ROOT/evals/harness/validate-suite.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/sb.XXXXXX")"
  G="$T/repo"; S="$T/suite"
  export LOA_EVAL_PHASE_PROMPTS_DIR="$T/no-prompts"
  python3 -m pytest --version >/dev/null 2>&1 || skip "pytest not importable by python3"
  git init -q -b main "$G"
  mkdir -p "$G/tools/mathx/tests" "$G/docs"
  cat > "$G/tools/mathx/rounding.py" <<'PY'
def round_half(x):
    """Round to the nearest integer, halves away from zero."""
    return int(x + 0.5)
PY
  cat > "$G/tools/mathx/tests/conftest.py" <<'PY'
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
PY
  cat > "$G/tools/mathx/tests/test_rounding.py" <<'PY'
from rounding import round_half

def test_positive():
    assert round_half(2.5) == 3
PY
  echo "notes" > "$G/docs/README"
  gc add -A; gc commit -q -m "chore: initial"
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

gc() { git -C "$G" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

# the clean fix: negative halves round away from zero; two new test cases
commit_clean_fix() {
  cat > "$G/tools/mathx/rounding.py" <<'PY'
import math


def round_half(x):
    """Round to the nearest integer, halves away from zero."""
    return int(math.copysign(math.floor(abs(x) + 0.5), x))
PY
  cat >> "$G/tools/mathx/tests/test_rounding.py" <<'PY'

def test_negative_half():
    assert round_half(-2.5) == -3

def test_negative():
    assert round_half(-1.6) == -2
PY
  gc add -A; gc commit -q -m "fix(mathx): negative halves round away from zero"
}

commit_claude_fix() {
  mkdir -p "$G/.claude"
  echo 'echo hi' > "$G/.claude/x.sh"
  printf '\ndef test_again():\n    assert round_half(1.5) == 2\n' >> "$G/tools/mathx/tests/test_rounding.py"
  gc add -A; gc commit -q -m "fix: the framework hook"
}

@test "SB-1 a clean fix commit becomes a task: fixture from the parent, hidden tests from the commit, proof printed, validate-suite passes" {
  commit_clean_fix
  FIX="$(git -C "$G" rev-parse HEAD)"; BASE="$(git -C "$G" rev-parse HEAD~1)"
  run "$SEED" --since 2000-01-01 --select 4 --out "$S" --repo "$G"
  [ "$status" -eq 0 ]
  grep -q "^candidate ${FIX:0:12} " <<<"$output"
  grep -qx "proof bugfix-01 ${FIX:0:12}: red 2 failed / green 3 passed" <<<"$output"
  grep -q 'selected 1, written 1, proof failed 0' <<<"$output"
  D="$S/tasks/bugfix-01"
  # fixture = the parent's module, the base test, the conftest; nothing else, no history
  [ "$(cd "$D/fixture" && find . -type f | sort | tr '\n' ' ')" = "./tools/mathx/rounding.py ./tools/mathx/tests/conftest.py ./tools/mathx/tests/test_rounding.py " ]
  grep -q 'int(x + 0.5)' "$D/fixture/tools/mathx/rounding.py"
  [ ! -e "$D/fixture/.git" ]
  # hidden = the commit's test + manifest + the non-test diff
  grep -q 'test_negative_half' "$D/hidden/tests/tools/mathx/tests/test_rounding.py"
  [ "$(jq -c . "$D/hidden/manifest.json")" = '{"files":[{"src":"tests/tools/mathx/tests/test_rounding.py","dest":"tools/mathx/tests/test_rounding.py"}]}' ]
  grep -q '^--- a/tools/mathx/rounding.py' "$D/hidden/reference.patch"
  ! grep -q 'test_rounding' "$D/hidden/reference.patch" || false
  # every field
  [ "$(yq -r .type "$D/task.yaml")" = "bug-fix" ]
  [ "$(yq -r .source.kind "$D/task.yaml")" = "loa-history" ]
  [ "$(yq -r .source.fix_commit "$D/task.yaml")" = "$FIX" ]
  [ "$(yq -r .source.base_commit "$D/task.yaml")" = "$BASE" ]
  [ "$(yq -r .source.date "$D/task.yaml")" = "$(git -C "$G" log -1 --format=%cs "$FIX")" ]
  [ "$(yq -r .fixture "$D/task.yaml")" = "tasks/bugfix-01/fixture" ]
  [ "$(yq -o=json -I=0 .test_command "$D/task.yaml")" = '["python3","-m","pytest","-q","tools/mathx/tests"]' ]
  [ "$(yq -o=json -I=0 .grader_protected "$D/task.yaml")" = '["tools/mathx/tests/conftest.py"]' ]
  [ "$(yq -r .reference_patch "$D/task.yaml")" = "hidden/reference.patch" ]
  grep -q 'passes 3 of 3' "$D/task.yaml"
  # TASK.md: subject, failure count, command; no diff, no test name
  grep -q '^# Task: negative halves round away from zero$' "$D/TASK.md"
  grep -q '2 of 3 checks' "$D/TASK.md"
  grep -q 'python3 -m pytest -q tools/mathx/tests' "$D/TASK.md"
  ! grep -qE 'test_|copysign|hidden' "$D/TASK.md" || false
  # the written suite validates
  run "$VS" --root "$S" --allow-partial
  [ "$status" -eq 0 ]
  # no stray staging dir, no caches
  [ -z "$(find "$S" -name __pycache__ -o -name .pytest_cache)" ]
}

@test "SB-2 a fix touching .claude/ is refused by name and nothing is written for it" {
  commit_claude_fix
  SHA="$(git -C "$G" rev-parse HEAD)"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G"
  [ "$status" -eq 0 ]
  grep -qx "refused ${SHA:0:12}: .claude/x.sh" <<<"$output"
  ! grep -q '^candidate' <<<"$output" || false
  [ ! -e "$S/tasks" ]
  # alongside a clean fix, only the clean one is written
  commit_clean_fix
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G"
  [ "$status" -eq 0 ]
  grep -qx "refused ${SHA:0:12}: .claude/x.sh" <<<"$output"
  [ "$(ls "$S/tasks")" = "bugfix-01" ]
  [ "$(yq -r .source.fix_commit "$S/tasks/bugfix-01/task.yaml")" != "$SHA" ]
}

@test "SB-3 --dry-run lists candidates and refusals and writes nothing" {
  commit_clean_fix
  commit_claude_fix
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --dry-run
  [ "$status" -eq 0 ]
  grep -q '^candidate ' <<<"$output"
  grep -q '^refused .*: .claude/x.sh$' <<<"$output"
  grep -q '1 candidate(s), 1 refused, 0 skipped; dry run, nothing written' <<<"$output"
  [ ! -e "$S" ]
}

@test "SB-4 a fix whose test is already green at the parent fails its proof: exit 1, nothing written" {
  printf '\ndef test_more():\n    assert round_half(0.2) == 0\n' >> "$G/tools/mathx/tests/test_rounding.py"
  echo '# comment' >> "$G/tools/mathx/rounding.py"
  gc add -A; gc commit -q -m "fix: a cosmetic change"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G"
  [ "$status" -eq 1 ]
  grep -q '^proof-failed .*: not red at base' <<<"$output"
  [ ! -e "$S/tasks" ]
}

@test "SB-5 a fix outside the allowed roots, one without a test and a non-fix subject are not candidates" {
  echo "more" >> "$G/docs/README"
  printf '\ndef test_docs():\n    assert True\n' >> "$G/tools/mathx/tests/test_rounding.py"
  gc add -A; gc commit -q -m "fix: docs and a test"
  DOCS="$(git -C "$G" rev-parse HEAD)"
  echo '# x' >> "$G/tools/mathx/rounding.py"; gc add -A; gc commit -q -m "fix: no test"
  NOTEST="$(git -C "$G" rev-parse HEAD)"
  echo '# y' >> "$G/tools/mathx/rounding.py"; gc add -A; gc commit -q -m "feat: not a fix"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --dry-run
  [ "$status" -eq 0 ]
  grep -qx "skipped ${DOCS:0:12}: outside the allowed roots: docs/README" <<<"$output"
  grep -qx "skipped ${NOTEST:0:12}: no test file touched" <<<"$output"
  grep -q '0 candidate(s), 0 refused, 2 skipped' <<<"$output"
  # --paths widens the roots; a mount-owned root is a usage error
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --dry-run --paths tools,docs
  grep -q "^candidate ${DOCS:0:12} " <<<"$output"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --dry-run --paths tools,grimoires
  [ "$status" -eq 2 ]
}

@test "SB-6 usage: no arguments, a missing --since, a bad date, a non-repository are exit 2; --help is exit 0" {
  run "$SEED"
  [ "$status" -eq 2 ]
  run "$SEED" --out "$S" --repo "$G"
  [ "$status" -eq 2 ]
  run "$SEED" --since 2026-13-01 --out "$S" --repo "$G"
  [ "$status" -eq 2 ]
  grep -q 'since must be YYYY-MM-DD' <<<"$output"
  run "$SEED" --since 2026-08-01 --out "$S" --repo "$T"
  [ "$status" -eq 2 ]
  run "$SEED" --since 2026-08-01 --out "$S" --repo "$G" --select 0
  [ "$status" -eq 2 ]
  run "$SEED" --help
  [ "$status" -eq 0 ]
  grep -q 'Exit: 0 done' <<<"$output"
}
