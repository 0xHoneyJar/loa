#!/usr/bin/env bash
# ablation-grade-stub.sh — stand-in for ablation-grade.sh in evals/tests/run-ablation.bats.
#   ablation-grade-stub.sh <run-dir> <task-id> --suite-root R [--tasks-dir T] [--executor …]
#     [--image …] [--docker-bin …] [--allow-partial] [--suite-file F]
# Writes <run-dir>/grade.json: build tasks {hidden_tests 3/4, regressions none}, review-catch
# {recall 1 of 2, verdict CHANGES_REQUIRED}. STUB_GRADE_LOG gets the argv (one line; " --allow-partial"
# appended when given, then " --suite-file <basename>" when given — the runner passes its suite file through);
# a run_id matching the glob in STUB_GRADE_FAIL exits 2 without writing; one matching the glob
# in STUB_GRADE_HANG sleeps 600 s before writing (the runner's grade deadline, Sprint 260 LOW-4).
# cycle-132: a run_id matching STUB_GRADE_CONTAM gets contaminated {phase, pattern: network_egress}; --union <cell>
# --task-id T (the matched cell) writes <cell>/grade.json from meta/cell.json (recall 0.5 of 2, the valid count,
# session-1 figures) and logs "union <cell basename> <task> --tasks-dir <T>[ --allow-partial]"; STUB_GRADE_UNION_FAIL=1
# makes the union exit 2.
set -euo pipefail
export LC_ALL=C
UNION="" UTASK=""
if [[ "${1:-}" == --union ]]; then UNION="$2" UTASK=""; shift 2; RD="$UNION" TASK=""
else RD="$1" TASK="$2"; shift 2; fi
ROOT="" TD=tasks AP=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite-root) ROOT="$2"; shift 2 ;;
    --suite-file) AP="$AP --suite-file $(basename "$2")"; shift 2 ;;
    --tasks-dir) TD="$2"; shift 2 ;;
    --task-id) TASK="$2"; shift 2 ;;
    --executor|--image|--docker-bin) shift 2 ;;
    --allow-partial) AP=" --allow-partial"; shift ;;   # cycle-131 FR-3 (a): the runner passes it on a partial suite root
    *) echo "grade-stub: unknown flag $1" >&2; exit 2 ;;
  esac
done
if [[ -n "$UNION" ]]; then
  [[ -n "${STUB_GRADE_LOG:-}" ]] && printf 'union %s %s --tasks-dir %s%s\n' "$(basename "$RD")" "$TASK" "$TD" "$AP" >> "$STUB_GRADE_LOG"
  [[ "${STUB_GRADE_UNION_FAIL:-0}" == 1 ]] && { echo "grade-stub: union refused" >&2; exit 2; }
  jq '{union: true, bare_sessions: .k, sessions_valid: ([.sessions[] | select(.valid)] | length),
       recall: (if ([.sessions[] | select(.valid)] | length) > 0 then {defects_seeded: 2, defects_caught: 1, recall: 0.5} else null end),
       false_positives: 0, false_positive_rule: "pm3", verdict: null, verdict_accuracy: null, contaminated: null,
       recall_session1: (if .sessions[0].valid then 0.5 else null end), precision_session1: (if .sessions[0].valid then 1 else null end),
       label_set: "v2", grader_version: "stub"}' "$RD/meta/cell.json" > "$RD/grade.json"
  exit 0
fi
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
contam=null
if [[ -n "${STUB_GRADE_CONTAM:-}" ]]; then
  # shellcheck disable=SC2254
  case "$rid" in $STUB_GRADE_CONTAM) contam='{"phase":"BARE","pattern":"network_egress","excerpt_id":"BARE:1"}' ;; esac
fi
if [[ "$type" == review-catch ]]; then
  jq -n --argjson c "$contam" '{recall: {defects_seeded: 2, defects_caught: 1, recall: 0.5}, false_positives: 0,
          verdict: {value: "CHANGES_REQUIRED"}, verdict_accuracy: true, grader_version: "stub", contaminated: $c}' > "$RD/grade.json"
else
  jq -n '{hidden_tests: {passed: 3, total: 4}, regressions: {newly_failing: []}, diff_lines: 10, files_changed: 1,
          grader_version: "stub"}' > "$RD/grade.json"
fi
