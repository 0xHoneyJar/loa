"""The sort rules.

`--sort COLUMN` orders rows by that column ascending, `--sort -COLUMN`
descending. A numeric column (see tally.numbers) compares by value, any other
column compares as strings. Empty cells come last in either direction. Rows
whose values are equal keep their input order.
"""

from .numbers import numeric_column, to_decimal


def parse_sort(spec):
    """Split a --sort value into (column, descending)."""
    if spec.startswith("-"):
        return spec[1:], True
    return spec, False


def sort_key_function(table, column):
    """A function mapping a row to a comparable value, or None for an empty cell."""
    i = table.index(column)
    convert = to_decimal if numeric_column(table.column(column)) else str
    return lambda row: None if row[i] == "" else convert(row[i])


def sort_rows(table, spec):
    column, descending = parse_sort(spec)
    key = sort_key_function(table, column)
    filled = [row for row in table.rows if key(row) is not None]
    empty = [row for row in table.rows if key(row) is None]
    filled.sort(key=key, reverse=descending)
    return table.with_rows(filled + empty)
