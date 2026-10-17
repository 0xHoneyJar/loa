# Fairness review — bugfix-v2-01

**Reviewer:** fairness session R2 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer D2 · **Verdict:** PASS

This is the second review. The first review failed check 2 because the reference-side counts disagreed with `success_criterion`. The lead then restated that grader-facing field in `task.yaml`. TASK.md, the fixture, the hidden tests, the manifest and the reference are unchanged; `git diff` on `task.yaml` shows only the `success_criterion` line changed since the first review. The proofs below are the ones recorded in the first review.

## 1. No solution leak

PASS. `grep -ri hidden` over `TASK.md` and `fixture/` is empty. Neither file names an arm id, a defect id, a test or the overlay path. The fixture docstrings of `Store.pop` and `Summary` describe the buggy design, which is the bug's surface and not its fix. TASK.md states the API, the observed bug and the expected behaviour, and every hidden assertion traces to a sentence:

- `test_removed_item_is_gone_from_every_lookup` traces to the first bug bullet and to "Every lookup reflects every change made so far … and agrees with `items()`". The `with_tag` result is a sorted list, as the API sentence states.
- `test_removed_name_and_sku_are_free_again` traces to "A removed item's sku and name are free again: a new item may use them". The `"BOLT"` case uses the stated case-insensitive name rule.
- `test_restore_brings_the_item_back` traces to "`restore` brings the removed item back and takes it out of the trash". `trash.skus() == []` follows directly.
- `test_restore_follows_the_add_rules` (lines 62–76) traces to "`restore` follows the rules of `add` (`DuplicateSku` for a live sku, `DuplicateName` for a live name, compared case-insensitively); when it raises, nothing changes and the item stays in the trash" and to the `UnknownSku` sentence. The `before + 2` on line 74 counts one remove and one add under "advances by exactly one for each operation that changes the inventory". The trash order `["A1", "A7"]` is the fixture's existing sorted `skus()`.
- `test_summary_follows_move_and_restock` and `test_summary_follows_a_remove_then_an_add` trace to the second bug bullet and the first expected bullet.
- `test_lookups_inside_a_batch_see_the_changes` traces to "inside a batch block as well as outside one" and to "`revision` advances once, when the outermost block ends". Line 113 checks that `revision` stays at `start` inside the block, which is the grouping "as they are today".
- `test_revision_advances_once_per_change` traces to "`revision` advances by exactly one for each operation that changes the inventory". That covers add, remove, restore, move and restock, positive and negative.
- `test_operations_that_change_nothing_keep_the_revision` traces to the no-op and "or that raises" sentence and to "only if something in the block changed". The two `InvalidItem` cases are the stated empty-category and below-zero rules. `move("B2", "")` reaches `InvalidItem` through the frozen `Item` validation that `replace` re-runs.
- `test_caches_rebuild_once_per_change_and_not_otherwise` traces to "after a change each rebuilds once, on its next lookup, and a lookup when nothing has changed since the last one does not rebuild". A no-op move or restock is not a change by the previous bullet, so lines 167–171 follow.
- `test_an_inventory_that_becomes_empty` traces to "This includes an inventory that is empty, or has become empty". The `table() == ["(empty)"]` assertion is existing behaviour, already pinned by the fixture's `test_listing`.

No assertion depends on an ordering, format or message the brief leaves open. The brief also covers the implied trap: a fix that keys the caches on `revision` would leave lookups stale inside a batch, and TASK.md says so in words.

## 2. Red then green

PASS. Runner: host Python 3, `timeout 120 env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`. Each side used a fresh `fixture/` copy under `mktemp -d` with the manifest file at its `dest`. The reference applied with `patch -p1 --batch --forward -s` and exited 0.

```
[base] pytest -q tests                           => 10 failed, 20 passed in 0.06s
[base] pytest -q tests --ignore=tests/acceptance => 19 passed in 0.02s
[ref]  pytest -q tests                           => 34 passed in 0.04s
[ref]  pytest -q tests --ignore=tests/acceptance => 23 passed in 0.02s
```

Every count now matches the restated `success_criterion`:

| stated | observed |
|---|---|
| red at base, 10 failed, 20 passed of 30 | 10 failed, 20 passed |
| reference 34 of 34: 11 hidden, 19 fixture, 4 reference regression cases | 34 passed |
| regression_command 19 cases at base | 19 passed |
| regression_command 23 cases at the reference | 23 passed |

Ten hidden cases fail at base. `test_restore_brings_the_item_back` passes at base. All 11 hidden cases pass at the reference. The 4 extra cases come from `tests/test_regressions.py`, which the reference patch creates.

The first review's FAIL is resolved. The reference end previously read "30 of 30" and "fixture suite, 19 cases", but the runs printed 34 and 23.

## 3. Criterion mechanical

PASS.

- `success_criterion` is one line naming the file, the overlay path, the counts at both ends and the regression condition. It now states the total and the regression count separately for base and reference, and names the source of the 4 extra reference cases. Two graders reading the run lines would reach the same result at both ends.
- `criterion` is behavioural and names no path or test.
- `grader_protected` lists `tests/conftest.py`, `tests/test_inventory.py` and `tests/test_model_store.py`. The fixture has no ini or pyproject, so the list is complete.
- `bounds` is `{max_turns: {IMPLEMENT: 80, BARE: 190}, timeout_min: {IMPLEMENT: 35, BARE: 80}}`, the values the lead confirmed for suite v2 (DEC-0580).
- `suite_version: 2` is set, and `source.kind: synthetic` carries the date 2026-10-17.
- The fixture is 60K with 10 files. It holds no cache, nothing named `hidden*`, and no `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/`, `.run/` or `.git/`. `evals/graders/no-secrets.sh` on the fixture exits 0.

## Notes

- **Hardness:** moderate to hard. The correct change touches four modules: a per-change generation counter in the store, a one-change `update`, the index and summary keyed on that counter, and the restore order. The obvious local fixes break other tests. Making `pop` count a change double-counts move and restock. Keying both caches on `revision` leaves lookups stale inside a batch. Skipping the equality check counts no-ops and rebuilds caches. A bare agent that reads the expected bullets as a checklist probably passes, but missing any one interaction fails the task.
- The reference's `update` treats an equal item as no change. That covers both no-op cases without a special case in `move` or `restock`.
