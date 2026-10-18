import pytest

import cronplan
from cronplan import CronError


@pytest.mark.parametrize("text,want", [
    ("* * * * *", "* * * * *"),
    ("*/15 9-17 * * MON-FRI", "0-45/15 9-17 * * 1-5"),
    ("0 0 1,15,L * *", "0 0 1,15,L * *"),
    ("5,6,7,9 0 * jan-mar *", "5-7,9 0 * 1-3 *"),
    ("0 12 ? * 1#2,5L", "0 12 * * 5L,1#2"),
    ("0 0 15W,L-3,LW,L-3 * *", "0 0 LW,L-3,15W * *"),
    ("@weekly", "0 0 * * 0"),
    ("@Hourly", "0 * * * *"),
    ("0 0 * * 7", "0 0 * * 0"),
    ("0 0 * * 5-7", "0 0 * * 0,5,6"),
    ("10/20 * * * *", "10-50/20 * * * *"),
    ("0 0 * * */2", "0 0 * * 0-6/2"),
])
def test_normalize(text, want):
    assert cronplan.normalize(text) == want


@pytest.mark.parametrize("text,message", [
    ("* * * *", "expected 5 fields, got 4"),
    ("@reboot", "unknown macro: '@reboot'"),
    ("60 * * * *", "field 'minute': value 60 out of range 0-59"),
    ("* 5-2 * * *", "field 'hour': range 5-2 is reversed"),
    ("*/0 * * * *", "field 'minute': step 0 is not allowed"),
    ("? * * * *", "field 'minute': bad item '?'"),
    ("* * * FOO *", "field 'month': bad value 'FOO'"),
    ("* * L-31 * *", "field 'day-of-month': offset 31 out of range 0-30"),
    ("* * * * 1#6", "field 'day-of-week': nth 6 out of range 1-5"),
    ("* * 1,,2 * *", "field 'day-of-month': bad item ''"),
])
def test_parse_errors(text, message):
    with pytest.raises(CronError) as info:
        cronplan.parse(text)
    assert str(info.value) == message


def test_error_classes():
    assert issubclass(CronError, ValueError)
    with pytest.raises(cronplan.RangeError):
        cronplan.parse("0 24 * * *")
    with pytest.raises(cronplan.ParseError):
        cronplan.parse(42)


def test_parse_returns_a_schedule():
    schedule = cronplan.parse("0 9 * * 1")
    assert isinstance(schedule, cronplan.Schedule)
    assert schedule.hour.values == frozenset({9})
    assert schedule.weekday.starred is False and schedule.day.starred is True
