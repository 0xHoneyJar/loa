"""Reading CSV text into a Table. The first record is the header (line 1)."""

import csv
import io

from .errors import UsageError
from .model import Table


def read_table(text):
    records = [rec for rec in csv.reader(io.StringIO(text)) if rec]
    if not records:
        raise UsageError("input has no header")
    columns = records[0]
    if len(set(columns)) != len(columns):
        raise UsageError("duplicate column in header")
    rows = []
    for line, rec in enumerate(records[1:], start=2):
        if len(rec) != len(columns):
            raise UsageError(f"line {line} has {len(rec)} fields, expected {len(columns)}")
        rows.append(rec)
    return Table(columns, rows)
