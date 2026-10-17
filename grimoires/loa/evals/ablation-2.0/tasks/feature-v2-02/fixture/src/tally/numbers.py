"""The numeric rule.

A cell is numeric when it is an optional minus sign, one or more ASCII digits,
and optionally a dot followed by one or more ASCII digits (`3`, `-2`, `0.75`).
A column is numeric when it has at least one non-empty cell and every
non-empty cell is numeric. Numeric values are exact decimals.
"""

import re
from decimal import Decimal

_NUMERIC = re.compile(r"-?[0-9]+(\.[0-9]+)?")


def is_numeric(cell):
    return bool(_NUMERIC.fullmatch(cell))


def to_decimal(cell):
    return Decimal(cell)


def numeric_column(cells):
    filled = [cell for cell in cells if cell != ""]
    return bool(filled) and all(is_numeric(cell) for cell in filled)
