# Task: a failed batch leaves the ledger half-applied and locked

`batchkit` (under `src/batchkit/`) applies batches of ledger items under account locks. `run_batch(pool, ledger, journal, items, owner="batch")` leases every account the batch touches from a `ResourcePool`, applies each `Item(id, account, amount)` to the `Ledger` through `apply_item`, records the applied ids in the `Journal`, and returns a `Report` with `status`, `applied`, `skipped`, `failed`, `error` and `summary()`. `Ledger.apply` refuses an item with `Overdraft` or `UnknownAccount`; a lock held by another owner raises `ResourceBusy`.

**Bug (observed):**
- After a batch fails on an overdraft, its accounts stay locked, so the next batch on any of them raises `ResourceBusy`. The items applied before the failure stay applied, and the report counts the failing item as applied.
- Retrying the same batch once the cause is fixed applies the items before the failure a second time. An item id that appears twice in one batch is applied twice.
- When a batch is refused because one of its accounts is locked by another owner, the accounts it had locked before reaching that one stay locked. `ResourcePool.lease` used directly does the same.

**Expected:**
- `ResourcePool.lease(names, owner)` locks each distinct name in sorted order and releases them all when the block ends, normally or by an exception. If a name cannot be locked, the names this lease has already locked are released before `ResourceBusy` propagates. `run_batch` holds its lease for exactly the duration of the call: when it returns or raises, none of its accounts is locked. A refused batch raises `ResourceBusy` and changes nothing.
- A batch is all-or-nothing. Items are applied in order. An item whose id the journal has already recorded, by an earlier batch or earlier in the same batch, is skipped. If the ledger refuses an item, every change this batch made to balances and to the journal is undone, and `run_batch` returns a report with status `rolled back`, `applied` empty, `failed` the refused item's id, `error` its error message, and `skipped` listing the items skipped before the failure. Ids recorded by earlier batches stay recorded.
- A batch that completes has status `committed`, `applied` and `skipped` in item order, `failed` and `error` set to `None`, and every applied id recorded in the journal. So a retry of a rolled-back batch applies each of its items exactly once.
- `summary()` reads `committed: <n> applied, <m> skipped` or `rolled back at <id>: <error>`. An empty batch commits as `committed: 0 applied, 0 skipped`.
- The existing errors and their messages are unchanged.

Fix the bug in place and add regression tests of your own. Run the suite with `python3 -m pytest -q tests`.
