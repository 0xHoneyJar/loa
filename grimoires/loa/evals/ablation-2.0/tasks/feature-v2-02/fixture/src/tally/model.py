"""The table model: named columns and rows of string cells."""

from dataclasses import dataclass, field
from typing import List

from .errors import UsageError


@dataclass
class Table:
    columns: List[str]
    rows: List[List[str]] = field(default_factory=list)

    def index(self, name):
        """The position of column `name`; an unknown name is a usage error."""
        try:
            return self.columns.index(name)
        except ValueError:
            raise UsageError(f"unknown field: {name}") from None

    def column(self, name):
        i = self.index(name)
        return [row[i] for row in self.rows]

    def with_rows(self, rows):
        return Table(list(self.columns), rows)
