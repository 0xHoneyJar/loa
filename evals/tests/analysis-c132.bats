#!/usr/bin/env bats
# =============================================================================
# evals/tests/analysis-c132.bats — cycle-132 Sprint 1 Task 1.8 (FR-5, FR-6; SDD §1.4, §5.2, §5.3)
#
# Runs the stdlib unit tests of evals/analysis/c132/ (python3 -m unittest discover) and pins the
# case count (tests/COUNT), then drives each CLI as CI and the lead will: python3 -I from a foreign working
# directory (reads-c132.py --make-inputs / --placebo / --look / --final on a synthetic batch,
# power.py on the frozen mini fixture, judge_agree.py usage) — byte-identical across two runs.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  A="$REPO_ROOT/evals/analysis/c132"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/ac.XXXXXX")"
}

teardown() { rm -rf "$T"; }

synth() {  # synth <dir> — a synthetic 8-PR batch (tests/synth.py)
  python3 -I - "$A/tests" "$1" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import synth
synth.build(sys.argv[2])
PY
}

@test "AC-1 the unit tests pass and the case count is pinned" {
  # the count lives in tests/COUNT (one line: the unittest-collected case count); a change that adds or drops a
  # case updates it deliberately, so a silently lost test fails here instead of passing with fewer cases
  # (Sprint 272 CI fix: the literal 129 had been stale since Sprint 270; design by Sprint 273 implementer B)
  local want
  want="$(tr -d '[:space:]' < "$A/tests/COUNT")"
  [[ "$want" =~ ^[0-9]+$ ]]
  run python3 -m unittest discover -s "$A/tests"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran $want tests"* ]]
  [[ "$output" == *$'\nOK'* ]]
}

@test "AC-2 reads-c132.py under python3 -I from another cwd: inputs, placebo, looks, final; byte-identical" {
  synth "$T/b"
  cd /
  run python3 -I "$A/reads-c132.py" --rows "$T/b/rows.jsonl" --results-root "$T/b/results" --make-inputs --out "$T/in" --pin "$(printf 'a%.0s' $(seq 40))" --label-set v2
  [ "$status" -eq 0 ]
  for mode in "--placebo --placebo-n 10" "--look 1" "--look 2" "--final"; do
    for i in 1 2; do
      # shellcheck disable=SC2086
      run python3 -I "$A/reads-c132.py" --rows "$T/b/rows.jsonl" --results-root "$T/b/results" --inputs "$T/in/INPUTS.json" \
        --registration "$T/b/REGISTRATION.json" $mode --out "$T/o$i"
      [ "$status" -eq 0 ]
    done
    cmp "$T/o1/reads.json" "$T/o2/reads.json"
    cmp "$T/o1/reads.md" "$T/o2/reads.md"
  done
  run jq -r '.mode' "$T/o1/reads.json"
  [ "$output" = final ]
  ! grep -q "$T" "$T/o1/reads.json" "$T/o1/reads.md"
}

@test "AC-3 reads-c132.py refuses changed inputs with exit 1 and no output" {
  synth "$T/b"
  python3 -I "$A/reads-c132.py" --rows "$T/b/rows.jsonl" --results-root "$T/b/results" --make-inputs --out "$T/in"
  printf ' ' >> "$T/b/results/c132-g1/a1_full/review-s03-t2/grade.json"
  run python3 -I "$A/reads-c132.py" --rows "$T/b/rows.jsonl" --results-root "$T/b/results" --inputs "$T/in/INPUTS.json" \
    --registration "$T/b/REGISTRATION.json" --final --out "$T/o"
  [ "$status" -eq 1 ]
  [[ "$output" == *"grade.json sha256 differs"* ]]
  [ ! -e "$T/o" ]
  run python3 -I "$A/reads-c132.py" --rows "$T/b/rows.jsonl" --final --out "$T/o"
  [ "$status" -eq 2 ]
}

@test "AC-4 power.py under python3 -I: seeded, byte-identical, the chosen N from the frozen mini inputs" {
  M="$A/tests/fixtures/power-mini"
  # the head.diff fixtures are generated (bd-qxwrm), not committed
  python3 -I "$A/tests/synth.py" power-mini-diffs --seed 20261023 --out "$T/fx"
  cd /
  for i in 1 2; do
    run python3 -I "$A/power.py" --rows "$M/rows.jsonl" --fixtures-dir "$T/fx" --suite-root "$M/suite" \
      --candidates "$M/candidates.tsv" --seed 20261021 --out "$T/p$i" --grid 6 --studies 40 --se-method linear --no-sensitivities
    [ "$status" -eq 0 ]
  done
  cmp "$T/p1/power.json" "$T/p2/power.json"
  cmp "$T/p1/power.md" "$T/p2/power.md"
  run jq -r '.reference_n' "$T/p1/power.json"
  [ "$output" = 6 ]
  # round 1: chosen only when P(YES | MDE) and P(NO | 0) both reach 0.80, else null + decision_required
  run jq -r 'if .per_n[0].meets_both then (.chosen_n == 6 and (.decision_required | not)) else (.chosen_n == null and .decision_required) end' "$T/p1/power.json"
  [ "$output" = true ]
  grep -q 'pr-11 (flagged)' "$T/p1/power.md"
}

@test "AC-5 judge_agree.py usage exits 2" {
  run python3 -I "$A/judge_agree.py" --key x
  [ "$status" -eq 2 ]
}
