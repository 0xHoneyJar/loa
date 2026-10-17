# Fairness review — bugfix-v2-03

**Reviewer:** fairness session R2 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer D2 · **Verdict:** PASS

## 1. No solution leak

PASS. `grep -ril hidden` over `TASK.md` and `fixture/` is empty. A second grep for `acceptance`, the hidden file name, test-name stems and arm ids over the same paths is also empty. The fixture docstrings describe current behaviour only. The `order_key` docstring says "ties broken deterministically", which is the defect, not a hint at the fix. The `Job` docstring documents `seq` as the submission number, which a careful implementer needs and which the brief's "submission position" names in words.

Every hidden assertion in `hidden/tests/test_dispatch_order.py` traces to a brief sentence:

- `test_equal_priority_drains_in_submission_order` (lines 22–24) traces to the first observed bullet, `zeta, alpha, mid` drained as `alpha, mid, zeta`, and to "among equal priorities the job submitted earlier goes first".
- `test_ready_lists_ties_by_submission` (lines 27–31) traces to "`ready()` lists the ready jobs in exactly that order" and "sorting jobs with `order_key` gives the same order". `Scheduler.job(name)` is fixture API.
- `test_released_job_takes_its_submission_place` (lines 34–40) traces to the `root`, `t1`, `t2` example in the observed bug and to "A job's submission position is fixed when it is submitted".
- `test_next_always_returns_the_first_ready_job` (lines 43–51) traces to "`next()` starts and returns the first of them". The expected order `m, k, q, c, b` follows mechanically from priority then submission.
- `test_priority_round_trip_keeps_submission_position` (lines 54–60) traces to "Raising a job's priority and lowering it back sends it behind…" and "reprioritising … never change it".
- `test_pause_and_resume_keep_submission_position` (lines 63–68) traces to "so does pausing and resuming it" and "pausing and resuming never change it".
- `test_reprioritising_a_waiting_job_does_not_start_it` (lines 71–78) traces to "a job still waiting keeps waiting" and "`None` when nothing is ready".
- `test_reprioritising_a_paused_job_keeps_it_paused` (lines 81–89) traces to "a paused job stays paused" and "Paused jobs … are left pending". `pending()` keeps its fixture contract of submission order.
- `test_pause_from_fn_counts_for_the_next_dispatch` (lines 92–100) traces to the third observed bullet and to "a pause … that happens while a job runs counts for the very next dispatch. Paused jobs, and the jobs waiting for them, are left pending."
- `test_released_high_priority_job_runs_next` (lines 103–105) traces to "a high-priority job released by a completion waits…" and "a release … counts for the very next dispatch".
- `test_reprioritise_from_fn_counts_for_the_next_dispatch` (lines 108–115) traces to "a reprioritise … counts for the very next dispatch" and "a ready job takes its new place at once".
- `test_each_job_runs_once_and_empty_drains_to_nothing` (lines 118–127) traces to "An empty scheduler drains to `[]`", "`None` when nothing is ready", "Each job runs at most once" and "The existing errors and their messages are unchanged". The message `job b is done` is the fixture's current `_require_pending` text.

**No arbitrary choice is tested.** I wrote an independent fix from the brief alone on a fresh copy. It changes three files: `order_key` uses `seq`, `reprioritise` no longer pushes into the queue, `next()` starts `ready()[0]`, and `drain` loops on `next()`. It does not use the reference's heap. It passes 26 of 26. The reference's added `job … is paused` error in `start` is not asserted.

## 2. Red then green

PASS. The runner was host Python 3.13.5 with pytest 9.0.2, using `PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`. Each side used a fresh `fixture/` copy under `mktemp -d`, with the manifest file at `tests/acceptance/test_dispatch_order.py`. The reference applied with `patch -p1 --batch --forward` after a clean dry run, touching four files, and left no `.orig` or `.rej`. The copies were deleted afterwards.

```
[base] pytest -q tests                              => 11 failed, 15 passed in 0.05s
[base] pytest -q tests --ignore=tests/acceptance    => 14 passed in 0.02s
  patching file src/jobq/keys.py
  patching file src/jobq/queue.py
  patching file src/jobq/runner.py
  patching file src/jobq/scheduler.py
[ref]  pytest -q tests                              => 26 passed in 0.03s
[ref]  pytest -q tests --ignore=tests/acceptance    => 14 passed in 0.02s
```

The counts match `success_criterion`. At base 11 hidden cases fail and `test_each_job_runs_once_and_empty_drains_to_nothing` passes, which gives 11 failed and 15 passed. The reference gives 12 of 12 hidden and 26 of 26 overall. The 14-case fixture suite is green at both ends.

## 3. Criterion mechanical

PASS. `success_criterion` is one line. It names the file, the overlay path, the counts at both ends and the regression condition. `criterion` is behavioural and names no path or test. `grader_protected` lists `tests/conftest.py`, `tests/test_queue_runner.py` and `tests/test_scheduler.py`, which are every fixture test file. The fixture has no ini, pyproject or setup.cfg. `bounds` are `{max_turns: {IMPLEMENT: 80, BARE: 190}, timeout_min: {IMPLEMENT: 35, BARE: 80}}`, which the lead's dispatch states are correct (DEC-0580). `suite_version: 2`, `source.kind: synthetic` with the date 2026-10-17, `type: bug-fix` and `structural_check: null` match the suite rules. The fixture is 60K and holds no cache, nothing named `hidden*`, no dot-entries, `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/`, `.run/` or `.git/`.

## Notes

- **Advisory: the fixture queue test pins push order within a priority.** `test_queue_orders_by_priority_and_keeps_push_order_within_one` pushes jobs whose `seq` matches push order, so an implementation keyed by `seq` passes it. An agent that keeps `ReadyQueue` push-ordered and re-sorts elsewhere also passes it. Neither reading is trapped.
- **Hardness:** moderate. The correct change touches three or four files with three separate defects: the name tie-break in `order_key`, the requeue in `reprioritise` that ignores paused and waiting state, and `drain` dispatching from a `ready()` snapshot. A bare agent that fixes only the visible tie-break fails the `fn`-driven drain cases and the paused or waiting reprioritise cases, but the brief names all three symptoms, so a careful agent probably passes.
