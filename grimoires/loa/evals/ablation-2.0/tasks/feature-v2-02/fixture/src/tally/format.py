"""The table layout.

Every cell, the header included, is padded to its column's width: the widest
of the header and the cells (and at least 3 in markdown). Numeric columns (see
tally.numbers) are right-justified, every other column is left-justified.

plain     cells separated by two spaces, trailing spaces removed
markdown  `| a | b |` lines; under the header a separator of dashes as wide as
          the column, whose last dash is `:` for a numeric column

The footer line follows the table.
"""

from .errors import UsageError
from .numbers import numeric_column

FORMATS = ("plain", "markdown")


def _layout(table, minimum):
    numeric = [numeric_column(table.column(name)) for name in table.columns]
    widths = [max([len(name), minimum] + [len(row[i]) for row in table.rows])
              for i, name in enumerate(table.columns)]
    return numeric, widths


def _pad(cells, numeric, widths):
    return [cell.rjust(w) if num else cell.ljust(w) for cell, num, w in zip(cells, numeric, widths)]


def render(table, fmt):
    if fmt not in FORMATS:
        raise UsageError(f"unknown format: {fmt}")
    if fmt == "plain":
        numeric, widths = _layout(table, 0)
        lines = [table.columns] + table.rows
        return ["  ".join(_pad(cells, numeric, widths)).rstrip() for cells in lines]
    numeric, widths = _layout(table, 3)
    sep = ["-" * (w - 1) + (":" if num else "-") for num, w in zip(numeric, widths)]
    lines = [_pad(table.columns, numeric, widths), sep] + [_pad(r, numeric, widths) for r in table.rows]
    return ["| " + " | ".join(cells) + " |" for cells in lines]


def plural(count, word):
    return f"{count} {word}" if count == 1 else f"{count} {word}s"


def footer(rows):
    return plural(rows, "row")
