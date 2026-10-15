# Task: settings reads go stale

`layercfg` (under `src/layercfg/`) keeps layered settings (defaults, a loaded file layer, single-key overrides) and reads dotted keys such as `db.port` through a memo, so hot paths that read the same keys stay fast.

**Bug (observed):**
- After `get(store, "db.port")` returns `6543`, calling `store.load({"db": {"port": 7000}})` and reading again still returns `6543`.
- After `store.set("debug", True)` and a read, `store.unset("debug")` leaves `get(store, "debug")` returning `True`.
- `get(store, "db.user", "alice")` returns `"alice"`, and a later `get(store, "db.user", "bob")` on the same store also returns `"alice"`.
- A service that builds a fresh store per request sometimes reads a value that belongs to an earlier store it has already discarded.

`store.set(...)` followed by a read already behaves correctly.

**Expected:** a read always reflects the current layers of the store it is given, whatever changed them (`load`, `set` or `unset`), and never a value from another store. An absent key returns the default passed to that call, and any value may serve as a default, including a list. Repeated reads of a store that has not changed are still answered from the memo: one miss, then hits, as `lookup_stats()` counts them.

Fix the bug in place and add regression tests of your own. Run the suite with `python3 -m pytest -q tests`.
