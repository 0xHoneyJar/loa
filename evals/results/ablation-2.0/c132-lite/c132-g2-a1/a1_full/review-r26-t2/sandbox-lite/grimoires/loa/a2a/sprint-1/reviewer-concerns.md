# Reviewer concerns — sprint-1 (PR: sprint-262 ablation-row.sh 1.2 / ablation-report.py 1.2.0)

Files: evals/harness/ablation-report.py, evals/harness/ablation-row.sh, evals/tests/ablation-report.bats,
evals/tests/ablation-row.bats, evals/tests/fixtures/ablation-report/gen-fixtures.py.

1. batch_record() grader_versions sort key mixes int and str list elements
   (re.split on "." then int() for digit parts) -> TypeError on any grader_version that is
   not purely dotted digits next to a numeric one (e.g. "1.2.11" beside "1.2.11-rc1" or "dev").
   Uncaught -> traceback instead of a Fail. head/evals/harness/ablation-report.py ~L1080.
2. batch_record() joins r["arm"] from the row into a filesystem path with no grammar check
   (the row writer validates arms; the report does not) -> listdir outside the batch dir.
3. version_key(): a non-integer float suite_version (1.5) returns None, i.e. "absent";
   --suite-version "1.0" is not normalised like row values are.
4. assess(): inconclusive_by_degradation is tested before no_pair, so an arm whose few
   cells are all excluded reads "decided" (H1 inconclusive by degradation) and --partial exits 0.
5. budget_matched(): header says rate fallback applies when a0 rows carry no ids, but the code
   falls back when ANY a0 trial lacks ids (mixed case loses the ids).
6. arm_metrics precision: null false_positives counted as 0 -> precision 1.0 for arms that
   never recorded false positives; the md hides the line when false_positives_per_task is empty
   while JSON still carries precision 1.0.
7. AR-20 does not run --validate over the new `present` fixture.
8. ablation-row.sh --help range 2,101p: still stops one line before "Tested by" (as base did).
9. Anything in the degenerate-pair logic (compare/decide/usable) that changes an existing decision?
10. Any hidden pooling across suite versions (batch_record uses all rows; header sha list).
