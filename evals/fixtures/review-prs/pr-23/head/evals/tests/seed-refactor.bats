#!/usr/bin/env bats
# =============================================================================
# evals/tests/seed-refactor.bats — cycle-130 Sprint 259 Task 2.3 (SDD §5.14,
# sprint AC-2.3, AC-2.9)
#
# seed-refactor-tasks.sh over a throwaway git repo: a refactor commit touching
# two source files with the tests unchanged and green becomes a task with the
# churn recorded (task.yaml source.churn and the printed churn line, equal to
# git diff --numstat), the suite green at both ends, the structural check left
# to author; a candidate touching a test file is skipped with the reason; one
# touching grimoires/ is refused by name; a one-file change is skipped;
# --dry-run writes nothing; a refactor that breaks the suite fails its proof.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  SEED="$REPO_ROOT/evals/harness/seed-refactor-tasks.sh"
  VS="$REPO_ROOT/evals/harness/validate-suite.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/sr.XXXXXX")"
  G="$T/repo"; S="$T/suite"
  export LOA_EVAL_PHASE_PROMPTS_DIR="$T/no-prompts"
  python3 -m pytest --version >/dev/null 2>&1 || skip "pytest not importable by python3"
  git init -q -b main "$G"
  mkdir -p "$G/tools/fmt/tests"
  cat > "$G/tools/fmt/left.py" <<'PY'
def left(s, width):
    s = str(s)
    if len(s) >= width:
        return s
    return s + " " * (width - len(s))
PY
  cat > "$G/tools/fmt/right.py" <<'PY'
def right(s, width):
    s = str(s)
    if len(s) >= width:
        return s
    return " " * (width - len(s)) + s
PY
  cat > "$G/tools/fmt/tests/conftest.py" <<'PY'
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
PY
  cat > "$G/tools/fmt/tests/test_fmt.py" <<'PY'
from left import left
from right import right

def test_left():
    assert left("ab", 4) == "ab  "
    assert left("abcde", 4) == "abcde"

def test_right():
    assert right(7, 3) == "  7"
PY
  gc add -A; gc commit -q -m "chore: initial"
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

gc() { git -C "$G" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

commit_refactor() {
  cat > "$G/tools/fmt/pad.py" <<'PY'
def gap(s, width):
    """The padding that brings str(s) up to width (empty when it is already wider)."""
    return " " * max(0, width - len(str(s)))
PY
  printf 'from pad import gap\n\n\ndef left(s, width):\n    return str(s) + gap(s, width)\n' > "$G/tools/fmt/left.py"
  printf 'from pad import gap\n\n\ndef right(s, width):\n    return gap(s, width) + str(s)\n' > "$G/tools/fmt/right.py"
  gc add -A; gc commit -q -m "refactor(fmt): share the padding helper"
}

@test "SR-1 a two-source refactor with unchanged green tests becomes a task with churn recorded and printed" {
  commit_refactor
  SHA="$(git -C "$G" rev-parse HEAD)"; BASE="$(git -C "$G" rev-parse HEAD~1)"
  read -r F I D < <(git -C "$G" diff --numstat "$BASE" "$SHA" | awk '{f++; i+=$1; d+=$2} END {print f, i, d}')
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G"
  [ "$status" -eq 0 ]
  grep -q "^candidate ${SHA:0:12} " <<<"$output"
  grep -qx "proof refactor-01 ${SHA:0:12}: green at base (2 passed) / green at reference (2 passed)" <<<"$output"
  grep -qx "churn refactor-01: files $F, insertions $I, deletions $D" <<<"$output"
  grep -q '^todo refactor-01: author the structural check' <<<"$output"
  K="$S/tasks/refactor-01"
  [ "$(yq -o=json -I=0 .source.churn "$K/task.yaml")" = "{\"files\":$F,\"insertions\":$I,\"deletions\":$D}" ]
  [ "$F" -eq 3 ]
  [ "$(yq -r .type "$K/task.yaml")" = "refactor" ]
  [ "$(yq -r .source.kind "$K/task.yaml")" = "loa-history" ]
  [ "$(yq -r .source.fix_commit "$K/task.yaml")" = "$SHA" ]
  [ "$(yq -r .source.base_commit "$K/task.yaml")" = "$BASE" ]
  [ "$(yq -r .structural_check "$K/task.yaml")" = "null" ]
  [ "$(yq -o=json -I=0 .test_command "$K/task.yaml")" = '["python3","-m","pytest","-q","tools/fmt/tests"]' ]
  [ "$(yq -o=json -I=0 .grader_protected "$K/task.yaml")" = '["tools/fmt/tests/conftest.py"]' ]
  # fixture = the parent's sources and the covering test, a plain tree; the reference patch applies to it
  [ "$(cd "$K/fixture" && find . -type f | sort | tr '\n' ' ')" = "./tools/fmt/left.py ./tools/fmt/right.py ./tools/fmt/tests/conftest.py ./tools/fmt/tests/test_fmt.py " ]
  [ ! -e "$K/fixture/.git" ]
  cp -R "$K/fixture" "$T/applied"
  (cd "$T/applied" && patch -s -p1 < "$K/hidden/reference.patch")
  [ -f "$T/applied/tools/fmt/pad.py" ]
  grep -q '^# Task: share the padding helper$' "$K/TASK.md"
  # the only violations validate-suite reports are the structural check still to author (and its manifest entry)
  run "$VS" --root "$S" --allow-partial
  [ "$status" -eq 1 ]
  [ "$(grep -c '^tasks/' <<<"$output")" -eq 2 ]
  grep -qx 'tasks/refactor-01: schema: structural_check is required for refactor' <<<"$output"
  grep -qx 'tasks/refactor-01: hidden: manifest.json must be {"files": \[{src, dest}, ...\]}' <<<"$output"
}

@test "SR-2 a candidate touching a test file is skipped with the reason; a one-source change is skipped; grimoires/ is refused by name" {
  printf '\ndef test_more():\n    assert left("", 1) == " "\n' >> "$G/tools/fmt/tests/test_fmt.py"
  echo '# a' >> "$G/tools/fmt/left.py"; echo '# b' >> "$G/tools/fmt/right.py"
  gc add -A; gc commit -q -m "refactor: tidy and test"
  WITH_TEST="$(git -C "$G" rev-parse HEAD)"
  echo '# c' >> "$G/tools/fmt/left.py"; gc add -A; gc commit -q -m "style: one file"
  ONE="$(git -C "$G" rev-parse HEAD)"
  mkdir -p "$G/grimoires/loa"; echo n > "$G/grimoires/loa/NOTES.md"
  echo '# d' >> "$G/tools/fmt/left.py"; echo '# e' >> "$G/tools/fmt/right.py"
  gc add -A; gc commit -q -m "chore: notes and code"
  MOUNT="$(git -C "$G" rev-parse HEAD)"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G"
  [ "$status" -eq 0 ]
  grep -qx "skipped ${WITH_TEST:0:12}: touches a test file: tools/fmt/tests/test_fmt.py" <<<"$output"
  grep -qx "skipped ${ONE:0:12}: touches 1 source file(s), want at least 2" <<<"$output"
  grep -qx "refused ${MOUNT:0:12}: grimoires/loa/NOTES.md" <<<"$output"
  grep -q '0 candidate(s), 1 refused, 3 skipped; selected 0, written 0' <<<"$output"
  grep -q 'skipped .*: not a single-parent commit' <<<"$output"
  [ ! -e "$S/tasks" ]
}

@test "SR-3 --dry-run writes nothing; a refactor that breaks the suite fails its proof with exit 1" {
  commit_refactor
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --dry-run
  [ "$status" -eq 0 ]
  grep -q '1 candidate(s), 0 refused, 1 skipped; dry run, nothing written' <<<"$output"
  [ ! -e "$S" ]
  printf 'def gap(s, width):\n    return ""\n' > "$G/tools/fmt/pad.py"
  echo '# f' >> "$G/tools/fmt/right.py"
  gc add -A; gc commit -q -m "perf: skip the padding"
  BROKEN="$(git -C "$G" rev-parse HEAD)"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --select 1
  [ "$status" -eq 1 ]
  grep -q "^proof-failed ${BROKEN:0:12}: suite not green at reference" <<<"$output"
  [ ! -e "$S/tasks" ]
}

@test "SR-4 a refactor no test names is skipped; usage errors are exit 2" {
  mkdir -p "$G/tools/other"
  echo 'A = 1' > "$G/tools/other/a.py"; echo 'B = 2' > "$G/tools/other/b.py"
  gc add -A; gc commit -q -m "chore: add"
  echo 'A = 3' > "$G/tools/other/a.py"; echo 'B = 4' > "$G/tools/other/b.py"
  gc add -A; gc commit -q -m "refactor: renumber"
  SHA="$(git -C "$G" rev-parse HEAD)"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --select 1
  [ "$status" -eq 0 ]
  grep -qx "skipped ${SHA:0:12}: no test at the parent names a touched file" <<<"$output"
  run "$SEED" --since yesterday --out "$S" --repo "$G"
  [ "$status" -eq 2 ]
  run "$SEED" --since 2026-08-01 --repo "$G"
  [ "$status" -eq 2 ]
}
