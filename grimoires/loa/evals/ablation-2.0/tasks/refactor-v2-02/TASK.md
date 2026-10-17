# Task: split invoicer's pricing module into three layers

`invoicer` (under `src/invoicer/`) reads a plain-text invoice format (`customer:`, `currency:`, `item: name | qty | unit price | tax class`, `discount:`), prices the invoice and renders it as text. `invoicer.api`, `invoicer.batch` and `invoicer.cli` are its callers. All three jobs live in `invoicer.pricing`, where the code first grew. The parsing code checks tax classes against the pricing table, the pricing code formats money for an error message, and two functions run to dozens of statements.

**Refactor:**
- `invoicer.parsing` defines `ParseError`, `Item`, `Discount`, `Invoice`, `parse_amount` and `parse_invoice`.
- `invoicer.rendering` defines `format_money`, `render_invoice` and `render_summary`.
- `invoicer.pricing` keeps `TAX_RATES`, `PricingError`, `Totals`, `line_total` and `invoice_totals`. Each name in these three lists is defined (a `def`, a `class` or an assignment at module level) in exactly one module of the package: the one it is listed under.
- `invoicer.pricing` keeps re-exporting the six parsing names by importing them, so `from invoicer.pricing import parse_invoice` gives the very same object as `invoicer.parsing.parse_invoice`. It does not provide any rendering name.
- The layers import in one direction only. `parsing` imports nothing from the package. `pricing` imports from `parsing` and from no other package module. `rendering` imports only from `parsing` and `pricing`.
- `api`, `batch` and `cli` get every name from the module that defines it. Nothing they import from `invoicer.pricing`, or read as `pricing.<name>`, is a parsing or rendering name.
- No function in `parsing`, `pricing` or `rendering` has more than 15 statements. Count every statement inside the function at any depth: the statements inside an `if`, `for`, `while`, `try` or `with` block count, and so do a nested function and the statements inside it. Split long functions into helpers.

**Unchanged behaviour:** every public function keeps its signature, results, error types and messages. An unknown tax class is still a `ParseError` that names its line. A discount above the subtotal is still a `PricingError` with the same message. The existing suite must stay green without edits. Run it with `python3 -m pytest -q tests`.
