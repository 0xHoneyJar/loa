# Task: Markdown table output for tabular

`tabular` (the package under `src/tabular/`) renders a list of row mappings as a table with `render(rows, columns, fmt="text")`; `Column(name, key=None, align="left")` reads `row[key or name]` and `align` is `left`, `right` or `center`. Cells are formatted by `format_cell` (empty for `None`, `true`/`false`, two decimals for floats). Add a second format, `fmt="markdown"`, that renders a GitHub-flavoured Markdown table. The text format, `format_cell` and the existing errors stay as they are.

## Output

Lines, each ending with a newline, in this order: the header line (the column names), the separator line, then one line per row. With no rows the result is the header and separator lines only. `rows` may be any iterable.

Every line has the shape `| c1 | c2 | … |`: a `|` and a space, the padded cells joined by ` | `, then a space and a `|`.

Cell text is `format_cell(value)` (a missing key is an empty cell); header text is the column name. Before measuring or padding, both are escaped: every line break (`\r\n`, `\n` or `\r`) becomes one space, then every `|` becomes `\|`.

A column's width is the longest escaped text in it (header included), but at least 3. Each text is padded with spaces to the width by the column's alignment: `left` pads on the right, `right` pads on the left, `center` splits the padding with the odd space on the right (`ab` centred in 7 is two spaces, `ab`, three spaces).

The separator cell for a column of width `w` is exactly `w` characters: `left` is `:` and `w-1` dashes, `right` is `w-1` dashes and `:`, `center` is `:`, `w-2` dashes and `:`.

Example, with columns `name` (center) and `price` (right) over the rows `{"name": "alpha", "price": 1.5}` and `{"name": "beta", "price": None}`:

```
| name  | price |
| :---: | ----: |
| alpha |  1.50 |
| beta  |       |
```

## Errors

As for the text format: no columns raises `ValueError`, and an unknown `fmt` raises `ValueError`.

Update the module docstring's list of formats. Run the suite with `python3 -m pytest -q tests`, and add tests of your own for the new format.
