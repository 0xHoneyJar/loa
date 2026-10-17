# Task: one order-line check for orderdesk

`orderdesk` (under `src/orderdesk/`) handles orders, returns, stock transfers and price quotes for a small warehouse. Every operation takes order lines, a list of `(sku, qty)` pairs, and checks each line first. A SKU is a string of three capital letters, a hyphen and four digits (`ABC-0042`). A quantity is an `int` (a `bool` is not a quantity) from 1 to a limit. A bad SKU is reported before a bad quantity.

That check is written out seven times across `orders`, `returns`, `transfers` and `quotes`. The copies differ in two ways that the suite pins. `returns.return_items` strips and upper-cases the SKU before checking it, so its messages name the cleaned SKU. `quotes.bulk_quote` allows quantities up to 9999 where every other operation allows 999.

**Refactor:**
- Add the module `orderdesk.validation`. It defines the module-level constants `MAX_QTY = 999` and `MAX_BULK_QTY = 9999` and the one function `validate_line(sku, qty, *, normalise=False, max_qty=MAX_QTY)`; `normalise` and `max_qty` are keyword-only.
- `validate_line` returns `(sku, qty)`, with the cleaned SKU when `normalise` is true; cleaning only applies to a string. On a bad line it raises `ValueError` with the message the copies use today: `invalid sku: <repr of the sku>` or `invalid quantity for <sku>: <repr of the qty>`.
- `orderdesk.validation` imports nothing from the rest of the package.
- Each of these eight functions calls `validate_line` itself, in its own body, not through a helper of its module: `orders.place_order`, `orders.order_total`, `returns.return_items`, `returns.exchange`, `transfers.plan_transfer`, `transfers.split_transfer`, `quotes.quote` and `quotes.bulk_quote`.
- When you are done, `validate_line` is defined exactly once in the package and no copy of the check is left anywhere else. Outside `orderdesk.validation`, no module calls `re.compile`, `re.match` or `re.fullmatch` (or the `match`/`fullmatch` method of a compiled pattern), refers to the built-in `bool`, contains the number 999 or 9999, or builds the `invalid sku` / `invalid quantity for` messages. A module that needs a limit imports the constant.

**Unchanged behaviour:** every public function keeps its signature, results and error messages. The existing suite must stay green without edits. Run it with `python3 -m pytest -q tests`.
