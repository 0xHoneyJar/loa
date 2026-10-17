# Fairness review — bugfix-v2-04

**Reviewer:** fairness session R2 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer D2 · **Verdict:** PASS

## 1. No solution leak

PASS. `grep -rni hidden TASK.md fixture/` is empty, and neither the brief nor the fixture names the overlay path, a test name, a defect id or an arm id. The fixture docstrings describe the current, buggy contract only (`run_batch`: "A refused item ends the batch"; `lease`: "Lock every distinct name in sorted order for the duration of the block"). Every hidden assertion traces to a TASK.md sentence:

| hidden test (line) | assertion | TASK.md sentence |
|---|---|---|
| `test_failed_batch_releases_its_locks` (19–20) | `locked() == []`, both holders `None` | "`run_batch` holds its lease for exactly the duration of the call: when it returns or raises, none of its accounts is locked." |
| `test_next_batch_after_a_failure_runs` (27–28) | second owner commits; `{"a": 10, "b": 1}` | the same sentence plus "every change this batch made to balances … is undone" |
| `test_failed_batch_undoes_its_changes` (34–35) | balances restored; `journal.ids() == []` | "every change this batch made to balances and to the journal is undone" |
| `test_failed_batch_report` (41–46) | status `rolled back`, `applied == []`, `skipped == []`, `failed == "i3"`, `error` = the Overdraft text, summary | "returns a report with status `rolled back`, `applied` empty, `failed` the refused item's id, `error` its error message, and `skipped` listing the items skipped before the failure"; "`summary()` reads … `rolled back at <id>: <error>`"; "The existing errors and their messages are unchanged" (the Overdraft text is the fixture's `model.py` message) |
| `test_retry_after_the_cause_is_fixed_applies_each_item_once` (54–57) | commits, applied `i1,i2,i3`, `{"a": 5, "b": 3}`, journal `i1,i2,i3` | "So a retry of a rolled-back batch applies each of its items exactly once"; "every applied id recorded in the journal"; Journal keeps record order (fixture docstring) |
| `test_repeated_id_in_one_batch_is_applied_once` (64–67) | balance 16, applied `["i1","i2"]`, skipped `["i1"]`, `committed: 2 applied, 1 skipped` | "An item whose id the journal has already recorded, by an earlier batch or earlier in the same batch, is skipped"; "`applied` and `skipped` in item order"; summary format |
| `test_rollback_keeps_ids_of_earlier_batches` (75–80) | rolled back, skipped `["i0"]`, applied `[]`, summary with `unknown account: zz`, journal `["i0"]`, balances, no lock | "`skipped` listing the items skipped before the failure"; "Ids recorded by earlier batches stay recorded"; error messages unchanged; lease released |
| `test_failure_on_the_first_item` (86–88) | failed `i1`, applied `[]`, summary, balance 0, no lock | rollback report sentence; summary format; lease sentence |
| `test_refused_batch_changes_nothing_and_leaves_no_lock` (95–100) | raises `ResourceBusy` "resource b is locked by other"; `locked() == ["b"]`; `holder("a") is None`; nothing changed | "A refused batch raises `ResourceBusy` and changes nothing"; "the names this lease has already locked are released before `ResourceBusy` propagates"; messages unchanged |
| `test_lease_that_cannot_lock_a_name_releases_the_rest` (106–110) | raises with the message; `locked() == ["b"]`, holder `y` | "`ResourcePool.lease(names, owner)` locks each distinct name in sorted order … If a name cannot be locked, the names this lease has already locked are released" |
| `test_empty_batch_commits` (116–119) | commits, `committed: 0 applied, 0 skipped`, `failed`/`error` `None`, no lock | "An empty batch commits as `committed: 0 applied, 0 skipped`"; "`failed` and `error` set to `None`" |

No assertion depends on an open choice. The report fields are compared as lists, which the fixture's own `test_batch.py` already does, so the type is not an arbitrary choice. The summary formats and error texts are stated or pre-existing. I found no contradiction between the brief and the tests, and no trick wording.

## 2. Red then green

PASS. Each run used a fresh `mktemp -d` copy of `fixture/`, with `hidden/tests/test_batch_failure.py` overlaid at `tests/acceptance/test_batch_failure.py`. The reference was applied with `patch -p1 --batch --forward`, which patched six files cleanly (rc 0). Runner: `timeout 120 env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`. Copies were deleted afterwards.

| run | `pytest -q tests` | `pytest -q tests --ignore=tests/acceptance` |
|-----|-------------------|---------------------------------------------|
| base | `10 failed, 12 passed in 0.05s` | `11 passed in 0.02s` |
| reference | `22 passed in 0.03s` | `11 passed in 0.02s` |

At base, the 10 failures are all overlaid tests. `test_empty_batch_commits` passes at base, which is expected because an empty batch never reaches the bug. All counts match `success_criterion` exactly: 11 of 11 overlaid, 22 of 22 total, red 10 failed and 12 passed, and the regression suite 11 green at both ends.

## 3. Criterion mechanical

PASS.
- `success_criterion` is one line. It names the file, the overlay path, the counts at both ends, the reference, and the regression condition with its case count. Two graders would apply it the same way.
- `criterion` describes behaviour only. It names no path and no test.
- `grader_protected` is `[tests/conftest.py, tests/test_batch.py, tests/test_parts.py]`. That is the conftest plus every fixture test file. The fixture has no `pytest.ini`, `pyproject.toml`, `setup.cfg` or `tox.ini`, so the list is complete.
- `bounds` are `{max_turns: {IMPLEMENT: 80, BARE: 190}, timeout_min: {IMPLEMENT: 35, BARE: 80}}`. These are the lead-confirmed values: the IMPLEMENT keys match the brief, and the BARE keys come from DEC-0580.
- `suite_version: 2` is set. `source` is `{kind: synthetic, date: "2026-10-17"}` with an origin line. `type` is `bug-fix`.
- The `test_command` and `regression_command` match the runs above.
- **Fixture hygiene:** the fixture is 60K and holds 11 files, all under `src/batchkit/` and `tests/`. It has no `__pycache__`, `*.pyc` or `.pytest_cache`. It has nothing named `hidden*`, and no `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/`, `.run/` or `.git/`.

## Notes

- **Hardness read:** the correct change touches four to six modules. A fix confined to `run_batch` does not pass: `lease` has to release on a part-way refusal, and the journal has to record per item so that repeated ids are skipped. Undoing on rollback needs a balance snapshot plus a journal undo. The fixture's derived `Report.applied` property also drops a repeated id from `applied`, so it has to become a stored list. A bare Opus agent that reads the brief carefully should pass in roughly 15–30 turns. The likely misses are the repeated-id `applied == ["i1","i2"]` case, which falls to the `Report.applied` property trap, and the direct-`lease` partial-release case, which a fix that only switches `run_batch` to `with pool.lease(...)` leaves broken.
- The reference releases names in reverse order and snapshots balances as a dict copy. No test depends on either choice.
- A batch that touches an unknown account still leases that name, because the pool locks any name. It is released afterwards, which `test_rollback_keeps_ids_of_earlier_batches` checks. The brief allows this.
