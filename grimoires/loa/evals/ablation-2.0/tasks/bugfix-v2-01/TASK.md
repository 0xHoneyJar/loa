# Task: lookups in the stockroom go stale after some changes

`stockroom` (under `src/stockroom/`) keeps an inventory of items. `Inventory()` holds a `Store` of live items (`inv.store`), a name and tag `Index` (`inv.index`), a per-category `Summary` (`inv.summary`) and a `Trash` of removed items (`inv.trash`). An `Item(sku, name, category, qty=0, tags=())` is immutable. The operations are `add(item)`, `remove(sku)` (the item goes to the trash), `move(sku, category)`, `restock(sku, delta)` and `restore(sku)` (back from the trash); the lookups are `find(name)` (case-insensitive, `None` when absent), `with_tag(tag)` (sorted skus), `counts()` (items per category), `total_qty()`, `items()` (live items sorted by sku), `listing()` and `table()`. `inv.store.get(sku)` returns a live item and `inv.trash.skus()` lists the trash. `inv.revision` counts the changes, and `with inv.batch():` groups the changes made inside the block. The index and the summary are caches; each has a `rebuilds` counter. Errors: `UnknownSku`, `DuplicateSku`, `DuplicateName`, `InvalidItem`.

**Bug (observed):**
- After `remove("A1")`, `find` still returns the removed item and `with_tag` still lists `A1`. Adding a new item with the removed item's name raises `DuplicateName`, and so does `restore("A1")`.
- After `move` or `restock`, `counts()` and `total_qty()` disagree with `items()`; so do they after one item is removed and another is added.
- Inside a `batch()` block, `find` does not see an item added earlier in the same block, and still finds one removed earlier in it.
- A move to the category the item is already in, and a restock by 0, advance `revision` although nothing changed.

**Expected:**
- Every lookup reflects every change made so far, inside a batch block as well as outside one, and agrees with `items()`. This includes an inventory that is empty, or has become empty.
- A removed item's sku and name are free again: a new item may use them, and `restore` brings the removed item back and takes it out of the trash. `restore` follows the rules of `add` (`DuplicateSku` for a live sku, `DuplicateName` for a live name, compared case-insensitively); when it raises, nothing changes and the item stays in the trash. `restore` of an sku that is not in the trash raises `UnknownSku`.
- `revision` advances by exactly one for each operation that changes the inventory. An operation that changes nothing (a move to the item's own category, a restock by 0) or that raises leaves `revision` unchanged. Inside a `batch()` block the changes are grouped as they are today: `revision` advances once, when the outermost block ends, and only if something in the block changed.
- The existing validation and messages are unchanged: an empty category, or a restock that would take a quantity below zero, raises `InvalidItem`.
- The index and the summary stay caches: after a change each rebuilds once, on its next lookup, and a lookup when nothing has changed since the last one does not rebuild.

Fix the bug in place and add regression tests of your own. Run the suite with `python3 -m pytest -q tests`.
