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
# allowed roots is skipped; usage errors are exit 2; --id-prefix names the ids
# (bugfix-v3-01) and refuses a prefix outside [a-z0-9][a-z0-9-]{0,60}; a failed proof
# leaves nothing staged, so the next candidate takes the freed id (SB-8); --fixture-scope
# roots carries the whole allowed-roots slice and names the changed test files (SB-9); a
# fixture file of git mode 100755 keeps its executable bit (SB-10).
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
  # the written suite is validated against the real suite file below: seed its suite_version
  run "$SEED" --since 2000-01-01 --select 4 --out "$S" --repo "$G" --suite-version "$(yq -r .suite_version "$REPO_ROOT/evals/suites/ablation-2.0.yaml")"
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

@test "SB-3 --dry-run lists candidates and refusals and writes nothing; --rev bounds the listing to a revision" {
  commit_clean_fix
  commit_claude_fix
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --dry-run
  [ "$status" -eq 0 ]
  grep -q '^candidate ' <<<"$output"
  grep -q '^refused .*: .claude/x.sh$' <<<"$output"
  grep -q '1 candidate(s), 1 refused, 0 skipped; dry run, nothing written' <<<"$output"
  [ ! -e "$S" ]
  # --rev lists the commits reachable from a revision: HEAD~1 leaves out the newest (the .claude/ fix)
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --dry-run --rev HEAD~1
  [ "$status" -eq 0 ]
  grep -q '^candidate ' <<<"$output"
  ! grep -q '^refused' <<<"$output" || false
  grep -q '1 candidate(s), 0 refused, 0 skipped; dry run, nothing written' <<<"$output"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --dry-run --rev no-such-branch
  [ "$status" -eq 2 ]
  grep -q 'rev is not a commit' <<<"$output"
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

@test "SB-7 --id-prefix names the task ids (a version-bearing id, bugfix-v3-01); a prefix outside the grammar is exit 2" {
  commit_clean_fix
  FIX="$(git -C "$G" rev-parse HEAD)"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --id-prefix bugfix-v3 --suite-version 3
  [ "$status" -eq 0 ]
  grep -qx "proof bugfix-v3-01 ${FIX:0:12}: red 2 failed / green 3 passed" <<<"$output"
  grep -q "^wrote $S/tasks/bugfix-v3-01\$" <<<"$output"
  [ "$(ls "$S/tasks")" = "bugfix-v3-01" ]
  [ "$(yq -r .id "$S/tasks/bugfix-v3-01/task.yaml")" = "bugfix-v3-01" ]
  [ "$(yq -r .fixture "$S/tasks/bugfix-v3-01/task.yaml")" = "tasks/bugfix-v3-01/fixture" ]
  [ "$(yq -r .suite_version "$S/tasks/bugfix-v3-01/task.yaml")" = "3" ]
  # the next free number continues the prefix, the default prefix is untouched
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --id-prefix bugfix-v3 --suite-version 3
  [ "$status" -eq 0 ]
  grep -q "^wrote $S/tasks/bugfix-v3-02\$" <<<"$output"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G"
  [ "$status" -eq 0 ]
  grep -q "^wrote $S/tasks/bugfix-01\$" <<<"$output"
  # grammar: lower-case letters, digits and hyphens, a letter or digit first
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --dry-run --id-prefix Bugfix
  [ "$status" -eq 2 ]
  grep -q 'id-prefix must match' <<<"$output"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --dry-run --id-prefix -v3
  [ "$status" -eq 2 ]
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --dry-run --id-prefix 'a/b'
  [ "$status" -eq 2 ]
}

@test "SB-8 a failed proof leaves nothing staged: the next candidate takes the freed id instead of dying on EEXIST" {
  commit_clean_fix
  CLEAN="$(git -C "$G" rev-parse HEAD)"
  # the newer candidate (tried first) fails its proof: its test is already green at the parent
  printf '\ndef test_more():\n    assert round_half(0.2) == 0\n' >> "$G/tools/mathx/tests/test_rounding.py"
  echo '# comment' >> "$G/tools/mathx/rounding.py"
  gc add -A; gc commit -q -m "fix: a cosmetic change"
  GREEN="$(git -C "$G" rev-parse HEAD)"
  run "$SEED" --since 2000-01-01 --select 2 --out "$S" --repo "$G"
  [ "$status" -eq 1 ]
  grep -q "^proof-failed ${GREEN:0:12}: not red at base" <<<"$output"
  ! grep -q 'File exists' <<<"$output" || false
  grep -qx "proof bugfix-01 ${CLEAN:0:12}: red 2 failed / green 3 passed" <<<"$output"
  grep -q "^wrote $S/tasks/bugfix-01\$" <<<"$output"
  grep -q 'selected 2, written 1, proof failed 1' <<<"$output"
  [ "$(ls "$S/tasks")" = "bugfix-01" ]
  [ "$(yq -r .source.fix_commit "$S/tasks/bugfix-01/task.yaml")" = "$CLEAN" ]
}

@test "SB-9 --fixture-scope roots: the fixture is the whole allowed-roots slice, the command names the changed test file, the brief names no test" {
  # a helper in another directory, present at the parent and untouched by the fix: the touched-scope fixture misses it
  mkdir -p "$G/tools/common"
  cat > "$G/tools/common/util.py" <<'PY'
import math


def half_away(x):
    return int(math.copysign(math.floor(abs(x) + 0.5), x))
PY
  gc add -A; gc commit -q -m "chore: a shared helper"
  cat > "$G/tools/mathx/rounding.py" <<'PY'
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "common"))
from util import half_away  # noqa: E402


def round_half(x):
    """Round to the nearest integer, halves away from zero."""
    return half_away(x)
PY
  cat >> "$G/tools/mathx/tests/test_rounding.py" <<'PY'

def test_negative_half():
    assert round_half(-2.5) == -3
PY
  gc add -A; gc commit -q -m "fix(mathx): negative halves round away from zero"
  FIX="$(git -C "$G" rev-parse HEAD)"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G"
  [ "$status" -eq 1 ]
  grep -q "^proof-failed ${FIX:0:12}: not green at reference" <<<"$output"
  [ ! -e "$S/tasks" ]
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --fixture-scope roots --suite-version "$(yq -r .suite_version "$REPO_ROOT/evals/suites/ablation-2.0.yaml")"
  [ "$status" -eq 0 ]
  grep -qx "proof bugfix-01 ${FIX:0:12}: red 1 failed / green 2 passed" <<<"$output"
  D="$S/tasks/bugfix-01"
  # the roots slice: the helper's directory is in, docs/ (outside the roots) is out
  [ "$(cd "$D/fixture" && find . -type f | sort | tr '\n' ' ')" = "./tools/common/util.py ./tools/mathx/rounding.py ./tools/mathx/tests/conftest.py ./tools/mathx/tests/test_rounding.py " ]
  [ "$(yq -o=json -I=0 .test_command "$D/task.yaml")" = '["python3","-m","pytest","-q","tools/mathx/tests/test_rounding.py"]' ]
  [ "$(yq -o=json -I=0 .grader_protected "$D/task.yaml")" = '["tools/mathx/tests/conftest.py"]' ]
  grep -q 'Run the tests under `tools/mathx/tests` that cover the code you change, with `python3 -m pytest -q <file>`' "$D/TASK.md"
  ! grep -qE 'test_rounding|half_away|hidden' "$D/TASK.md" || false
  run "$VS" --root "$S" --allow-partial
  [ "$status" -eq 0 ]
}

@test "SB-10 a fixture file of git mode 100755 keeps its executable bit (a shell tool the hidden bats test runs)" {
  export LOA_SEED_BATS="${LOA_SEED_BATS:-$BATS_ROOT/bin/bats}"
  [ -x "$LOA_SEED_BATS" ] || skip "no bats binary for the proof"
  mkdir -p "$G/tools/greet/tests"
  printf '#!/usr/bin/env bash\necho "hello $1"\n' > "$G/tools/greet/greet.sh"; chmod +x "$G/tools/greet/greet.sh"
  cat > "$G/tools/greet/tests/greet.bats" <<'B'
setup() { T="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/greet.sh"; }
@test "greets" { run "$T" world; [ "$status" -eq 0 ]; [ "$output" = "hello world" ]; }
B
  gc add -A; gc commit -q -m "chore: a greeter"
  printf '#!/usr/bin/env bash\necho "hello ${1:-stranger}"\n' > "$G/tools/greet/greet.sh"
  cat >> "$G/tools/greet/tests/greet.bats" <<'B'
@test "greets a stranger" { run "$T"; [ "$status" -eq 0 ]; [ "$output" = "hello stranger" ]; }
B
  gc add -A; gc commit -q -m "fix(greet): a missing name is a stranger"
  FIX="$(git -C "$G" rev-parse HEAD)"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --rev HEAD
  [ "$status" -eq 0 ]
  grep -qx "proof bugfix-01 ${FIX:0:12}: red 1 failed / green 2 passed" <<<"$output"
  [ -x "$S/tasks/bugfix-01/fixture/tools/greet/greet.sh" ]
  [ ! -x "$S/tasks/bugfix-01/fixture/tools/greet/tests/greet.bats" ]
  [ "$(yq -o=json -I=0 .test_command "$S/tasks/bugfix-01/task.yaml")" = '["bats","tools/greet/tests"]' ]
}
