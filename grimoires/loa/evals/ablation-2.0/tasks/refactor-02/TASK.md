# Task: split the report builder along its three concerns

`salesreport` (under `src/salesreport/`) turns a CSV-like sales export into a plain-text weekly summary. All of the work happens in one long function, `build_report` in `salesreport.report`: it parses and checks the input lines, adds up the totals, and formats the text. A change to any one of those steps means reading the whole function.

**Refactor:** split it into three module-level functions in `salesreport.report`, one per concern:
- `parse_lines(text)` returns the list of sales in the text (an empty list when there are none) and raises `ReportError` for a malformed line, exactly as today.
- `aggregate(sales, top=3)` returns a summary object holding the totals, the revenue per region and the top products. It produces no text.
- `render_report(summary, currency="EUR")` returns the report text. It does no parsing.

`build_report(text, *, currency="EUR", top=3)` keeps its signature and only composes the three: `render_report(aggregate(parse_lines(text), top=top), currency=currency)` must equal `build_report(text, currency=currency, top=top)`. None of the three steps calls another. `build_report` itself is at most eight statements, and no function in the module has more than forty statements (statements inside loops, branches and `try` blocks count; the bodies of nested functions do not). The shape of the summary object is up to you.

**Unchanged behaviour:** the report text, the `ReportError` messages and the `top` check are exactly as today. The existing suite must stay green without edits. Run it with `python3 -m pytest -q tests`.
