# Task: grouped aggregation and a limit for tally

`tally` (the package under `src/tally/`) prints CSV records as a table. Its entry point is `tally.cli.main(argv, stdin=None, stdout=None, stderr=None)`, which returns the exit status; it reads the file argument, or standard input without one. It already has `--where FIELD=VALUE` (repeatable; keeps rows whose cell equals the value exactly), `--sort [-]COLUMN` (ascending, or descending with `-`), `--format plain|markdown` and a footer line; the numeric rule, the sort rules, the table layout and the error format are described in the module docstrings and stay as they are. Add grouping, aggregates and a limit.

## Grouping

- `--group-by KEY` or `--group-by KEY1,KEY2` groups the rows kept by `--where` by the values of one or two distinct input fields. Each group is one output row.
- `--agg SPEC`, repeatable, adds an aggregate column per group, in the order given. SPEC is `count`, or `sum:FIELD`, `min:FIELD` or `max:FIELD`. The column headers are `count`, `sum(FIELD)`, `min(FIELD)`, `max(FIELD)`. Without `--agg`, the only aggregate is `count`.
- Output columns are the keys in the order given, then the aggregates. Without `--sort`, groups appear in the order their first row appears in the input.
- `count` is the number of rows in the group. `sum`, `min` and `max` skip empty cells; every other cell they read must be numeric (the existing numeric rule). Only rows kept by `--where` are read. When every cell of the field in a group is empty, the aggregate is the empty string.
- A sum is exact decimal arithmetic and keeps as many decimal places as its most precise input (`1.5` and `2.25` sum to `3.75`; `1.50` and `2` sum to `3.50`). `min` and `max` print the winning cell exactly as written; among cells of equal value the first in input order wins.
- With `--group-by`, `--sort` names an output column (a key or an aggregate header); any other name is an unknown field. Grouped rows are sorted with the existing sort rules.
- The table layout and alignment rules are unchanged and apply to grouped rows; aggregate columns follow the same numeric rule as any other column.

## Limit

`--limit N`, with N a positive integer written in ASCII digits, keeps the first N output rows (grouped or not), after sorting. When `--sort` is given, every further row whose sort-column value equals the value of the Nth row is kept as well (values compare as the sort compares them; empty cells equal each other). Without `--sort`, exactly N rows are kept. A limit at or above the number of rows keeps them all.

## Footer

The footer counts rows after `--where`, with `row`/`group` singular for one and plural otherwise:

- ungrouped: `<n> rows`, or `<k> of <n> rows` when the limit drops rows;
- grouped: `<g> groups from <n> rows`, or `<k> of <g> groups from <n> rows` when the limit drops groups.

## Errors

Errors keep the existing format: exit status 2, nothing on standard output, exactly one line on standard error, `tally: <message>`. With `<value>` as given:

- an unknown field in `--group-by`, `--agg` or `--sort`: `tally: unknown field: <name>`;
- a `--group-by` value that is not one or two distinct non-empty names separated by a comma: `tally: invalid --group-by value: <value>`;
- an `--agg` value that is not one of the four shapes: `tally: invalid --agg value: <value>`;
- `--agg` without `--group-by`: `tally: --agg needs --group-by`;
- a non-numeric cell read by `sum`, `min` or `max`: `tally: field <name> is not numeric: <cell> (line <number>)`, where the line number counts the header as line 1;
- an invalid `--limit` value: `tally: invalid --limit value: <value>`.

Update the usage text in the module docstring of `tally.cli`. Run the suite with `python3 -m pytest -q tests`, and add tests of your own for the new options.
