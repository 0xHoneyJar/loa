# Reviewer concerns — sprint-1 (PR: sprint-260 batch runner, report, grader calibration)

Scope: `pr/head.diff` (17 files). Cite `head/<path>:<line>`.

## Verified by the reviewer

1. `evals/harness/ablation-grade.sh` HEREDOC regex (`strip_heredocs`, ~line 1376): nested lazy quantifier under `re.S`
   backtracks exponentially on a Bash command that contains `<<word` with no matching terminator line
   (measured: 20 lines 1 s, 22 lines 4 s, 24 lines 15 s, ×4 per two lines). The scan runs in-process with no
   timeout; `run-ablation.sh` removes the watchdog `.pgid` file before `post_run` (grade), so a hang there
   blocks the trial job and the driver's final `reap 1` forever.
2. `after_closing_quote` (~line 1364) treats a backslash before a quote as a glued closing quote, so an
   absolute outside path inside an escaped double-quoted string (`bash -c "… \"/outside/path\""`,
   `python3 -c "open(\"…\")"`) is no longer a candidate. The base grader flagged it. False negative in the
   contamination detector.
3. `in_quotes` (~line 1371) counts every `'` and `"` in the whole command text; a single apostrophe in
   earlier prose (`echo "it's"; cd /root && …`) hides a later single-component sensitive word. Base flagged it.

## Open questions for the dissenter

- `run-ablation.sh` `collect`/`replace_row_try`: any path where a rerun row lands twice or the rows file is
  left partially written (flock scope, `mv` of the whole tracked file)?
- Resume reconciliation (lines ~1299-1352): spend double counting between `ledger_usd`, `rows_usd`, and the
  rerun-flagged rows' reported cost?
- `drift_check`: a phase with `model_requested` null and an empty `models_used` — anything missed?
- `ablation-report.py` `decide()`: predicate order vs the suite's `rules.predicates`; None handling in `r9`
  comparisons when a comparison has `n == 0`.
- `lib/arms-common.sh` extraction from `run-arms.sh`: any behaviour change (`est_record` keyed by arm, pool "all")?
- Grader `HIDDEN_TOKEN`, `"=" in w`, `/.` prefix skips: other realistic false negatives?
