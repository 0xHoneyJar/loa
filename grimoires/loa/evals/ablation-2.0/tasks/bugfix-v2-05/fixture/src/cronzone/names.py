"""Month and weekday names, macros and the field table."""
from collections import namedtuple

MONTHS = {name: i + 1 for i, name in enumerate(
    ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"])}
WEEKDAYS = {name: i for i, name in enumerate(["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"])}

MACROS = {
    "@yearly": "0 0 1 1 *",
    "@annually": "0 0 1 1 *",
    "@monthly": "0 0 1 * *",
    "@weekly": "0 0 * * 0",
    "@daily": "0 0 * * *",
    "@midnight": "0 0 * * *",
    "@hourly": "0 * * * *",
}

Field = namedtuple("Field", "name lo hi names")

MINUTE = Field("minute", 0, 59, {})
HOUR = Field("hour", 0, 23, {})
DOM = Field("day-of-month", 1, 31, {})
MONTH = Field("month", 1, 12, MONTHS)
DOW = Field("day-of-week", 0, 7, WEEKDAYS)

FIELDS = (MINUTE, HOUR, DOM, MONTH, DOW)
