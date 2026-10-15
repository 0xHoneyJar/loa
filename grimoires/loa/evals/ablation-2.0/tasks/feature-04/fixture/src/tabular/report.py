"""Render a list of row mappings as a table.

    render(rows, columns, fmt="text") -> str

`rows` is a list of mappings; `columns` a non-empty list of Column. A column
reads `row[column.key]` (the key defaults to the column name); a missing key
is an empty cell. Every line of the result ends with a newline.

Formats:
  text   the header line, a line of dashes under each column, one line per
         row; columns are separated by two spaces and padded to the widest
         cell (header included) by their alignment; trailing spaces are
         stripped from each line.
"""
from dataclasses import dataclass
from typing import Optional

ALIGNMENTS = ("left", "right", "center")


@dataclass(frozen=True)
class Column:
    name: str
    key: Optional[str] = None
    align: str = "left"

    def __post_init__(self):
        if self.align not in ALIGNMENTS:
            raise ValueError(f"unknown alignment: {self.align}")

    @property
    def source(self):
        return self.name if self.key is None else self.key


def format_cell(value) -> str:
    """None is empty, booleans are true/false, floats have two decimals."""
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        return f"{value:.2f}"
    return str(value)


def _pad(text, width, align):
    if align == "right":
        return text.rjust(width)
    if align == "center":
        return text.center(width)
    return text.ljust(width)


def _cells(rows, columns):
    return [[format_cell(row.get(c.source)) for c in columns] for row in rows]


def _render_text(rows, columns):
    body = _cells(rows, columns)
    widths = [max([len(c.name)] + [len(r[i]) for r in body]) for i, c in enumerate(columns)]
    lines = [[c.name for c in columns], ["-" * w for w in widths]] + body
    out = []
    for cells in lines:
        padded = [_pad(text, widths[i], columns[i].align) for i, text in enumerate(cells)]
        out.append("  ".join(padded).rstrip() + "\n")
    return "".join(out)


FORMATS = {"text": _render_text}


def render(rows, columns, fmt="text"):
    if not columns:
        raise ValueError("no columns")
    if fmt not in FORMATS:
        raise ValueError(f"unknown format: {fmt}")
    return FORMATS[fmt](list(rows), list(columns))
