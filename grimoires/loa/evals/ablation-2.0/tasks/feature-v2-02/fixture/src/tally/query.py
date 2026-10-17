"""Row filters: --where FIELD=VALUE keeps rows whose cell equals VALUE exactly."""

from .errors import UsageError


def parse_where(value):
    field, sep, wanted = value.partition("=")
    if not sep or not field:
        raise UsageError(f"invalid --where value: {value}")
    return field, wanted


def apply_where(table, conditions):
    """Keep the rows that satisfy every condition (AND), in input order."""
    checks = [(table.index(field), wanted) for field, wanted in conditions]
    rows = [row for row in table.rows if all(row[i] == wanted for i, wanted in checks)]
    return table.with_rows(rows)
