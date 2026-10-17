# Fairness review — feature-v2-02

**Reviewer:** fairness session R2 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer D2 · **Verdict:** PASS

## 1. No solution leak

PASS. `grep -ril hidden` over TASK.md and `fixture/` is empty (only task.yaml, which is grader-side, names `hidden/`). TASK.md and the fixture docstrings name no overlay path, test name, defect id or arm id. TASK.md names the public entry point `tally.cli.main`, which is spec, not fix.

Every assertion of the overlaid file traces to a TASK.md sentence or to a fixture module docstring that TASK.md says stays as it is:

| test (line) | traces to |
|---|---|
| `test_default_aggregate_is_count_in_first_appearance_order` (36) | "Without `--agg`, the only aggregate is `count`"; "groups appear in the order their first row appears"; footer "`<g> groups from <n> rows`"; format.py layout (numeric right-justified). |
| `test_two_keys_and_several_aggregates_in_markdown` (46) | "Output columns are the keys in the order given, then the aggregates"; headers `count`, `sum(FIELD)`, `max(FIELD)`; "When every cell of the field in a group is empty, the aggregate is the empty string"; markdown separator rule in format.py. |
| `test_sums_are_exact_decimals_and_an_all_empty_group_is_empty` (60) | "keeps as many decimal places as its most precise input" (1.50+2.25+0.75 = 4.50); `min` prints the cell as written; empty-group rule; plain "trailing spaces removed" gives the bare `apple` line. |
| `test_min_and_max_print_the_first_winning_cell_as_written` (76) | "among cells of equal value the first in input order wins" (1.5 over 1.50, 2 over 2.0); sum 2+2.0 = 4.0 by the precision sentence. |
| `test_only_rows_kept_by_where_are_read` (86) | "Only rows kept by `--where` are read" (the `n/a` row is never checked); "1 group from 2 rows" by the singular rule. |
| `test_sorting_groups_by_an_aggregate_keeps_ties_in_first_appearance_order` (95) | "Grouped rows are sorted with the existing sort rules"; sorting.py "Rows whose values are equal keep their input order" with grouped input order = first appearance. |
| `test_sorting_groups_follows_the_sort_rules_and_names_output_columns` (103) | "`--sort` names an output column (a key or an aggregate header); any other name is an unknown field"; sorting.py "Empty cells come last in either direction" (south/pear last both ways). |
| `test_limit_after_sort_keeps_rows_tied_with_the_last_one` (115) | "every further row whose sort-column value equals the value of the Nth row is kept"; footer "`<k> of <g> groups from <n> rows`". |
| `test_limit_ties_on_empty_cells_and_ungrouped_rows` (125) | "empty cells equal each other"; "(grouped or not)"; "`<k> of <n> rows` when the limit drops rows" (limit 3 keeps all 4, so plain "4 rows"). |
| `test_limit_without_sort_keeps_exactly_n` (133) | "Without `--sort`, exactly N rows are kept"; "A limit at or above the number of rows keeps them all". |
| `test_invalid_limit_values` (142) | "a positive integer written in ASCII digits" covers `0`, `-1`, `1.5`, empty, `+2`, ` 2`, `two`, `٣`; message `invalid --limit value: <value>`. |
| `test_group_by_errors` (147) | "not one or two distinct non-empty names separated by a comma"; unknown field message. |
| `test_agg_errors` (153) | "not one of the four shapes" (`avg:units`, `count:units`, `sum`, `SUM:units`, `min`); unknown field for `max:colour`; "`--agg` without `--group-by`". |
| `test_non_numeric_cell_names_the_field_and_line` (160) | the non-numeric message with "the line number counts the header as line 1"; the second case (`sum:region` under `--where region=south`) uses the original input line 3. |
| `test_layout_rules_apply_to_grouped_rows` (166) | "aggregate columns follow the same numeric rule as any other column" plus numbers.py "at least one non-empty cell" (zero groups gives left-aligned `------`/`----------`); "0 groups from 0 rows" by "plural otherwise"; numeric key `year` right-aligned. |

One reading is implied rather than stated: `sum:` (empty FIELD) at line 154 must be `invalid --agg value`, not `unknown field: `. The `FIELD` placeholder names a field, and the fixture's own `parse_where` treats an empty field as an invalid value, so a careful implementer lands on the tested reading. This is not judged a FAIL.

## 2. Red then green

Runner: `timeout 120 env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider` on fresh `mktemp -d` copies of `fixture/`, with `hidden/tests/test_grouping.py` overlaid at `tests/acceptance/test_grouping.py`. The reference was applied with `patch -p1 --batch --forward`; it touches `src/tally/aggregate.py` (new), `cli.py`, `format.py` and `sorting.py`, and no test file.

| run | `pytest -q tests` | `pytest -q tests --ignore=tests/acceptance` |
|-----|-------------------|---------------------------------------------|
| base | `15 failed, 14 passed in 0.06s` | `14 passed in 0.01s` |
| reference | `29 passed in 0.03s` | `14 passed in 0.01s` |

All 15 overlaid cases fail at base and pass at the reference. The counts match `success_criterion` exactly.

## 3. Criterion mechanical

PASS.
- `success_criterion` names the file, the overlay path, 15/15 and 29/29, base red 15 failed / 14 passed, and the regression command green with 14 cases at both ends. Two graders would apply it identically.
- `criterion` is behavioural and names no path or test.
- `grader_protected` is `tests/conftest.py`, `tests/test_sort.py`, `tests/test_table.py`. These are every fixture test file; the fixture has no ini, `pyproject.toml` or `setup.cfg`.
- `bounds` is `{max_turns: {IMPLEMENT: 80, BARE: 190}, timeout_min: {IMPLEMENT: 35, BARE: 80}}`, the values the lead confirmed for suite v2 (DEC-0580).
- `suite_version: 2`; `source: {kind: synthetic, date: "2026-10-17"}`; `post_cutoff: true`; `structural_check: null` for a feature-build.
- Fixture hygiene: 64K, 12 files; no `__pycache__`/`.pyc`, nothing named `hidden*`, no dotfiles, no `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/`, `.run/` or `.git/`.

## Notes

- Hardness: the correct change touches four modules (a new grouping step, the argument parser, the footer signature and the sort module's limit) and must thread original input line numbers past `--where`, so a bare Opus 5.5 agent will likely pass most cases. The likely misses are the implied edges: tie-keeping on empty cells, the "`<k> of`" prefix only when rows are actually dropped, the zero-group markdown alignment, decimal-place preservation (`4.0`, `3.50`) and the exact error precedence, so a perfect 15/15 is plausible but not assured.
- The reference compares limit ties with the sort key function, so numeric ties compare by value (`2` ties `2.0`). No test exercises that, and the brief's "values compare as the sort compares them" states it.
