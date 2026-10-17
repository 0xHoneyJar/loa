"""Reference behaviour of the package, flattened into one module (grader side)."""

import enum
from dataclasses import dataclass
import datetime
import re


# ---- errors ----

class CronError(ValueError):
    """Base class of every error the package raises."""


class ParseError(CronError):
    """An expression or field does not follow the grammar."""


class RangeError(CronError):
    """A value, offset or ordinal lies outside its allowed range."""


class SearchError(CronError):
    """No fire time exists within the search horizon."""


class ArgumentError(CronError):
    """A datetime, count or month argument is unusable."""


# ---- model ----

class FieldKind(enum.Enum):
    """One of the five fields of an expression."""

    MINUTE = "minute"
    HOUR = "hour"
    DAY = "day-of-month"
    MONTH = "month"
    WEEKDAY = "day-of-week"


class Special(enum.Enum):
    """A day item that is not a plain number."""

    MONTH_END = "L"
    MONTH_END_WEEKDAY = "LW"
    MONTH_END_OFFSET = "L-"
    NEAREST_WEEKDAY = "W"
    LAST_WEEKDAY = "dL"
    NTH_WEEKDAY = "#"


@dataclass(frozen=True, slots=True)
class SpecialDay:
    """A special item with its number and, for NTH_WEEKDAY, its ordinal."""

    kind: Special
    number: int
    nth: int = 0


@dataclass(frozen=True, slots=True)
class Field:
    """One parsed field."""

    kind: FieldKind
    values: frozenset[int]
    specials: tuple[SpecialDay, ...] = ()
    starred: bool = False


@dataclass(frozen=True, slots=True)
class Schedule:
    """A parsed five-field expression."""

    minute: Field
    hour: Field
    day: Field
    month: Field
    weekday: Field


# ---- limits ----

def limits(kind: FieldKind) -> tuple[int, int]:
    """Return the lowest and highest number a field accepts."""
    match kind:
        case FieldKind.MINUTE:
            return (0, 59)
        case FieldKind.HOUR:
            return (0, 23)
        case FieldKind.DAY:
            return (1, 31)
        case FieldKind.MONTH:
            return (1, 12)
        case FieldKind.WEEKDAY:
            return (0, 7)


def label(kind: FieldKind) -> str:
    """Return the name a field has in messages."""
    return kind.value


def full_values(kind: FieldKind) -> frozenset[int]:
    """Return every value a field can match; weekday 7 is Sunday, 0."""
    low, high = limits(kind)
    return frozenset(v % 7 if kind is FieldKind.WEEKDAY else v for v in range(low, high + 1))


# ---- names ----

MONTHS = ("JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC")


WEEKDAYS = ("SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT")


def month_number(text: str) -> int | None:
    """Return 1-12 for a month name in any case, or None."""
    upper = text.upper()
    return MONTHS.index(upper) + 1 if upper in MONTHS else None


def weekday_number(text: str) -> int | None:
    """Return 0-6 for a weekday name in any case, or None."""
    upper = text.upper()
    return WEEKDAYS.index(upper) if upper in WEEKDAYS else None


# ---- dates ----

def cron_weekday(day: datetime.date) -> int:
    """Return the weekday with Sunday as 0."""
    return day.isoweekday() % 7


def last_day(year: int, month: int) -> int:
    """Return the number of days in a month."""
    following = datetime.date(year + month // 12, month % 12 + 1, 1)
    return (following - datetime.timedelta(days=1)).day


def last_weekday(year: int, month: int) -> int:
    """Return the day of the last Monday-to-Friday day of a month."""
    day = datetime.date(year, month, last_day(year, month))
    while cron_weekday(day) in (0, 6):
        day -= datetime.timedelta(days=1)
    return day.day


def nearest_weekday(year: int, month: int, number: int) -> int | None:
    """Return the weekday nearest to a day without leaving the month."""
    end = last_day(year, month)
    if number > end:
        return None
    weekday = cron_weekday(datetime.date(year, month, number))
    if weekday == 6:
        return number + 2 if number == 1 else number - 1
    if weekday == 0:
        return number - 2 if number == end else number + 1
    return number


# ---- items ----

_PLAIN = r"^(\*|\?|[0-9A-Za-z]+(?:-[0-9A-Za-z]+)?)(?:/([0-9]+))?$"


def _checked(kind: FieldKind, value: int) -> int:
    low, high = limits(kind)
    if not low <= value <= high:
        raise RangeError(f"field {label(kind)!r}: value {value} out of range {low}-{high}")
    return value


def parse_value(text: str, kind: FieldKind) -> int:
    """Read a number or, for months and weekdays, a name."""
    if text.isascii() and text.isdigit():
        return _checked(kind, int(text))
    named = month_number(text) if kind is FieldKind.MONTH else None
    if kind is FieldKind.WEEKDAY:
        named = weekday_number(text)
    if named is None:
        raise ParseError(f"field {label(kind)!r}: bad value {text!r}")
    return named


def _day_special(item: str) -> SpecialDay | None:
    if item in ("L", "LW"):
        return SpecialDay(Special.MONTH_END if item == "L" else Special.MONTH_END_WEEKDAY, 0)
    offset = re.match(r"^L-([0-9]+)$", item)
    if offset is not None:
        number = int(offset.group(1))
        if number > 30:
            raise RangeError(f"field 'day-of-month': offset {number} out of range 0-30")
        return SpecialDay(Special.MONTH_END_OFFSET, number)
    nearest = re.match(r"^([0-9]+)W$", item)
    if nearest is None:
        return None
    return SpecialDay(Special.NEAREST_WEEKDAY, _checked(FieldKind.DAY, int(nearest.group(1))))


def _weekday_special(item: str) -> SpecialDay | None:
    last = re.match(r"^([0-9A-Za-z]+)L$", item)
    if last is not None:
        return SpecialDay(Special.LAST_WEEKDAY, parse_value(last.group(1), FieldKind.WEEKDAY) % 7)
    nth = re.match(r"^([0-9A-Za-z]+)#([0-9]+)$", item)
    if nth is None:
        return None
    ordinal = int(nth.group(2))
    if not 1 <= ordinal <= 5:
        raise RangeError(f"field 'day-of-week': nth {ordinal} out of range 1-5")
    return SpecialDay(Special.NTH_WEEKDAY, parse_value(nth.group(1), FieldKind.WEEKDAY) % 7, ordinal)


def parse_special(item: str, kind: FieldKind) -> SpecialDay | None:
    """Return the special day an item names, or None for a plain item."""
    if kind is FieldKind.DAY:
        return _day_special(item)
    if kind is FieldKind.WEEKDAY:
        return _weekday_special(item)
    return None


def _bounds(base: str, kind: FieldKind, stepped: bool) -> tuple[int, int]:
    if base in ("*", "?"):
        return limits(kind)
    low_text, _, high_text = base.partition("-")
    low = parse_value(low_text, kind)
    high = parse_value(high_text, kind) if high_text else (limits(kind)[1] if stepped else low)
    if low > high:
        raise ParseError(f"field {label(kind)!r}: range {low}-{high} is reversed")
    return low, high


def _step(text: str | None, kind: FieldKind) -> int:
    if text is None:
        return 1
    if int(text) == 0:
        raise ParseError(f"field {label(kind)!r}: step 0 is not allowed")
    return int(text)


def parse_item(item: str, kind: FieldKind) -> frozenset[int]:
    """Return the numbers a plain item stands for."""
    match = re.match(_PLAIN, item)
    question = item.startswith("?") and kind not in (FieldKind.DAY, FieldKind.WEEKDAY)
    if match is None or question:
        raise ParseError(f"field {label(kind)!r}: bad item {item!r}")
    step = _step(match.group(2), kind)
    low, high = _bounds(match.group(1), kind, match.group(2) is not None)
    wrap = kind is FieldKind.WEEKDAY
    return frozenset(v % 7 if wrap else v for v in range(low, high + 1, step))


# ---- render ----

def _run_length(numbers: list[int], start: int) -> int:
    if start + 1 >= len(numbers):
        return 1
    step = numbers[start + 1] - numbers[start]
    end = start + 1
    while end + 1 < len(numbers) and numbers[end + 1] - numbers[end] == step:
        end += 1
    return end - start + 1


def _run_text(numbers: list[int], start: int, length: int) -> str:
    first, last = numbers[start], numbers[start + length - 1]
    step = numbers[start + 1] - first
    return f"{first}-{last}" if step == 1 else f"{first}-{last}/{step}"


def format_numbers(numbers: list[int]) -> list[str]:
    """Render sorted numbers, folding runs of three or more into ranges."""
    out: list[str] = []
    start = 0
    while start < len(numbers):
        length = _run_length(numbers, start)
        if length >= 3:
            out.append(_run_text(numbers, start, length))
            start += length
        else:
            out.append(str(numbers[start]))
            start += 1
    return out


def format_special(special: SpecialDay) -> str:
    """Render one special day item."""
    match special.kind:
        case Special.MONTH_END:
            return "L"
        case Special.MONTH_END_WEEKDAY:
            return "LW"
        case Special.MONTH_END_OFFSET:
            return f"L-{special.number}"
        case Special.NEAREST_WEEKDAY:
            return f"{special.number}W"
        case Special.LAST_WEEKDAY:
            return f"{special.number}L"
        case Special.NTH_WEEKDAY:
            return f"{special.number}#{special.nth}"


def format_field(field: Field) -> str:
    """Render one field: its numbers, then its special items."""
    if field.values == full_values(field.kind):
        parts = ["*"]
    else:
        parts = format_numbers(sorted(field.values))
    parts.extend(format_special(s) for s in field.specials)
    return ",".join(parts)


def format_schedule(schedule: Schedule) -> str:
    """Render all five fields separated by single spaces."""
    fields = (schedule.minute, schedule.hour, schedule.day, schedule.month, schedule.weekday)
    return " ".join(format_field(f) for f in fields)


# ---- days ----

def _is_last_weekday(special: SpecialDay, day: datetime.date, end: int) -> bool:
    return cron_weekday(day) == special.number and day.day + 7 > end


def _is_nth_weekday(special: SpecialDay, day: datetime.date) -> bool:
    return cron_weekday(day) == special.number and (day.day - 1) // 7 + 1 == special.nth


def special_matches(special: SpecialDay, day: datetime.date) -> bool:
    """Tell whether a special item selects a day."""
    end = last_day(day.year, day.month)
    match special.kind:
        case Special.MONTH_END:
            return day.day == end
        case Special.MONTH_END_WEEKDAY:
            return day.day == last_weekday(day.year, day.month)
        case Special.MONTH_END_OFFSET:
            return day.day == end - special.number
        case Special.NEAREST_WEEKDAY:
            return day.day == nearest_weekday(day.year, day.month, special.number)
        case Special.LAST_WEEKDAY:
            return _is_last_weekday(special, day, end)
        case Special.NTH_WEEKDAY:
            return _is_nth_weekday(special, day)


def _field_hits(field: Field, number: int, day: datetime.date) -> bool:
    return number in field.values or any(special_matches(s, day) for s in field.specials)


def day_matches(schedule: Schedule, day: datetime.date) -> bool:
    """Tell whether a day passes the month and both day fields."""
    if day.month not in schedule.month.values:
        return False
    by_date = _field_hits(schedule.day, day.day, day)
    by_weekday = _field_hits(schedule.weekday, cron_weekday(day), day)
    if schedule.day.starred or schedule.weekday.starred:
        return by_date and by_weekday
    return by_date or by_weekday


# ---- fields ----

def special_key(special: SpecialDay) -> tuple[int, int, int]:
    """Order special items by kind, then number, then ordinal."""
    return (list(Special).index(special.kind), special.number, special.nth)


def parse_field(text: str, kind: FieldKind) -> Field:
    """Parse a comma-separated field into its numbers and special days."""
    values: set[int] = set()
    specials: set[SpecialDay] = set()
    for item in text.split(","):
        special = parse_special(item, kind)
        if special is None:
            values |= parse_item(item, kind)
        else:
            specials.add(special)
    ordered = tuple(sorted(specials, key=special_key))
    return Field(kind, frozenset(values), ordered, text[:1] in ("*", "?"))


# ---- expressions ----

MACROS = (
    ("@yearly", "0 0 1 1 *"),
    ("@annually", "0 0 1 1 *"),
    ("@monthly", "0 0 1 * *"),
    ("@weekly", "0 0 * * 0"),
    ("@daily", "0 0 * * *"),
    ("@midnight", "0 0 * * *"),
    ("@hourly", "0 * * * *"),
)


def expand_macro(text: str) -> str:
    """Return the five fields a macro stands for."""
    for name, fields in MACROS:
        if text.lower() == name:
            return fields
    raise ParseError(f"unknown macro: {text!r}")


def parse_expression(text: str) -> Schedule:
    """Parse a five-field expression or a macro."""
    if not isinstance(text, str):
        raise ParseError(f"not a string: {text!r}")
    body = text.strip()
    if body.startswith("@"):
        body = expand_macro(body)
    parts = body.split()
    if len(parts) != 5:
        raise ParseError(f"expected 5 fields, got {len(parts)}")
    kinds = list(FieldKind)
    return Schedule(*(parse_field(part, kind) for part, kind in zip(parts, kinds)))


# ---- search ----

HORIZON_YEARS = 5


MAX_COUNT = 1000


def check_naive(when: datetime.datetime) -> None:
    """Reject anything but a naive datetime."""
    if not isinstance(when, datetime.datetime):
        raise ArgumentError(f"not a datetime: {when!r}")
    if when.tzinfo is not None:
        raise ArgumentError("datetime must be naive")


def _next_month(t: datetime.datetime) -> datetime.datetime:
    return datetime.datetime(t.year + t.month // 12, t.month % 12 + 1, 1)


def _advance(schedule: Schedule, t: datetime.datetime) -> datetime.datetime | None:
    if t.month not in schedule.month.values:
        return _next_month(t)
    if not day_matches(schedule, t.date()):
        return datetime.datetime(t.year, t.month, t.day) + datetime.timedelta(days=1)
    if t.hour not in schedule.hour.values:
        return t.replace(minute=0) + datetime.timedelta(hours=1)
    if t.minute not in schedule.minute.values:
        return t + datetime.timedelta(minutes=1)
    return None


def next_fire(schedule: Schedule, after: datetime.datetime) -> datetime.datetime:
    """Return the first fire time strictly after a moment."""
    check_naive(after)
    t = after.replace(second=0, microsecond=0) + datetime.timedelta(minutes=1)
    while t.year <= after.year + HORIZON_YEARS:
        following = _advance(schedule, t)
        if following is None:
            return t
        t = following
    raise SearchError(f"no fire time within {HORIZON_YEARS} years")


def fires(schedule: Schedule, after: datetime.datetime, count: int) -> list[datetime.datetime]:
    """Return the next count fire times after a moment."""
    if not isinstance(count, int) or not 1 <= count <= MAX_COUNT:
        raise ArgumentError(f"count must be 1-{MAX_COUNT}, got {count!r}")
    out: list[datetime.datetime] = []
    for _ in range(count):
        after = next_fire(schedule, after)
        out.append(after)
    return out


def matches(schedule: Schedule, when: datetime.datetime) -> bool:
    """Tell whether a schedule fires at exactly this moment."""
    check_naive(when)
    if when.second or when.microsecond:
        return False
    if when.minute not in schedule.minute.values or when.hour not in schedule.hour.values:
        return False
    return day_matches(schedule, when.date())


# ---- report ----

def _check_month(year: int, month: int) -> None:
    if not isinstance(month, int) or not 1 <= month <= 12:
        raise ArgumentError(f"month must be 1-12, got {month!r}")
    if not isinstance(year, int) or not 1 <= year <= 9998:
        raise ArgumentError(f"year must be 1-9998, got {year!r}")


def month_grid(schedule: Schedule, year: int, month: int) -> str:
    """List each day of a month that fires, with its number of fire times."""
    _check_month(year, month)
    per_day = len(schedule.hour.values) * len(schedule.minute.values)
    lines = []
    for number in range(1, last_day(year, month) + 1):
        day = datetime.date(year, month, number)
        if day_matches(schedule, day):
            lines.append(f"{day.isoformat()}  {per_day}")
    total = per_day * len(lines)
    lines.append(f"total  {total}")
    return "\n".join(lines)


# ---- facade ----

def parse(expression: str) -> Schedule:
    """Parse an expression string."""
    return parse_expression(expression)


def normalize(expression: str) -> str:
    """Return the canonical form of an expression string."""
    return format_schedule(parse_expression(expression))


def next_fire_text(expression: str, after: datetime.datetime) -> datetime.datetime:
    """Return the first fire time of an expression after a moment."""
    return next_fire(parse_expression(expression), after)


def fires_text(expression: str, after: datetime.datetime, count: int = 5) -> list[datetime.datetime]:
    """Return the next fire times of an expression after a moment."""
    return fires(parse_expression(expression), after, count)


def matches_text(expression: str, when: datetime.datetime) -> bool:
    """Tell whether an expression fires at exactly this moment."""
    return matches(parse_expression(expression), when)


def month_report(expression: str, year: int, month: int) -> str:
    """Render the per-day fire counts of an expression for one month."""
    return month_grid(parse_expression(expression), year, month)

