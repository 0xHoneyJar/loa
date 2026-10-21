#!/usr/bin/env bash
# ablation-grade-stub.sh — stand-in for ablation-grade.sh in evals/tests/run-ablation.bats.
#   ablation-grade-stub.sh <run-dir> <task-id> --suite-root R [--tasks-dir T] [--executor …]
#     [--image …] [--docker-bin …] [--allow-partial]
# Writes <run-dir>/grade.json: build tasks {hidden_tests 3/4, regressions none}, review-catch
# {recall 1 of 2, verdict CHANGES_REQUIRED}. STUB_GRADE_LOG gets the argv (one line; " --allow-partial"
# appended when given);
# a run_id matching the glob in STUB_GRADE_FAIL exits 2 without writing; one matching the glob
# in STUB_GRADE_HANG sleeps 600 s before writing (the runner's grade deadline, Sprint 260 LOW-4).
set -euo pipefail
export LC_ALL=C
RD="$1" TASK="$2"; shift 2
ROOT="" TD=tasks AP=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite-root) ROOT="$2"; shift 2 ;;
    --tasks-dir) TD="$2"; shift 2 ;;
    --executor|--image|--docker-bin) shift 2 ;;
    --allow-partial) AP=" --allow-partial"; shift ;;   # cycle-131 FR-3 (a): the runner passes it on a partial suite root
    *) echo "grade-stub: unknown flag $1" >&2; exit 2 ;;
  esac
done
[[ -n "${STUB_GRADE_LOG:-}" ]] && printf '%s %s --tasks-dir %s%s\n' "$(basename "$RD")" "$TASK" "$TD" "$AP" >> "$STUB_GRADE_LOG"
rid="$(jq -r '.run_id' "$RD/meta/pipeline.json")"
if [[ -n "${STUB_GRADE_FAIL:-}" ]]; then
  # shellcheck disable=SC2254
  case "$rid" in $STUB_GRADE_FAIL) echo "grade-stub: refused" >&2; exit 2 ;; esac
fi
if [[ -n "${STUB_GRADE_HANG:-}" ]]; then
  # shellcheck disable=SC2254
  case "$rid" in $STUB_GRADE_HANG) echo "grade-stub: hanging" >&2; sleep 600 ;; esac
fi
type="$(yq -r '.type' "$ROOT/$TD/$TASK/task.yaml")"
if [[ "$type" == review-catch ]]; then
  jq -n '{recall: {defects_seeded: 2, defects_caught: 1, recall: 0.5}, false_positives: 0,
          verdict: {value: "CHANGES_REQUIRED"}, verdict_accuracy: true, grader_version: "stub"}' > "$RD/grade.json"
else
  jq -n '{hidden_tests: {passed: 3, total: 4}, regressions: {newly_failing: []}, diff_lines: 10, files_changed: 1,
          grader_version: "stub"}' > "$RD/grade.json"
fi
