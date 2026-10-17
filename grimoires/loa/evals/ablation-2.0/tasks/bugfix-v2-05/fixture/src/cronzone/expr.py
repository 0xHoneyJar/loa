"""A parsed cron expression."""
from .days import matching_days, month_shape
from .errors import CronError
from .fields import parse_field
from .names import DOM, DOW, FIELDS, HOUR, MACROS, MINUTE, MONTH


class CronExpr:
    """Five fields: minute, hour, day of month, month, day of week."""

    def __init__(self, text):
        if not isinstance(text, str):
            raise CronError(f"expected 5 fields, got {text!r}")
        self.text = text
        source = text
        if source.startswith("@"):
            if source not in MACROS:
                raise CronError(f"unknown macro: {source!r}")
            source = MACROS[source]
        parts = source.split()
        if len(parts) != 5:
            raise CronError(f"expected 5 fields, got {len(parts)}")
        self.minute, self.hour, self.dom, self.month, self.dow = (
            parse_field(part, spec) for part, spec in zip(parts, FIELDS))
        self.minutes = tuple(sorted(self.minute.values))
        self.hours = tuple(sorted(self.hour.values))
        self.months = tuple(sorted(self.month.values))
        self._days = {}

    def days(self, year, month):
        """The sorted matching days of ``year``-``month`` (empty if the month is not selected)."""
        if month not in self.month.values:
            return ()
        shape = month_shape(year, month)
        key = (month, shape[1])
        if key not in self._days:
            self._days[key] = matching_days(self.dom, self.dow, *shape)
        return self._days[key]

    def matches(self, wall):
        """True when the naive wall-clock datetime ``wall`` is selected."""
        return (wall.minute in self.minute.values and wall.hour in self.hour.values
                and wall.day in self.days(wall.year, wall.month))

    def __repr__(self):
        return f"CronExpr({self.text!r})"


__all__ = ["CronExpr", "DOM", "DOW", "HOUR", "MINUTE", "MONTH"]
