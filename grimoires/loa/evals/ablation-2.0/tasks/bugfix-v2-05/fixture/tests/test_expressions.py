from datetime import datetime

import pytest

from cronzone import CronError, CronExpr


def test_simple_fields():
    expr = CronExpr("5 9-17/4 * * MON-FRI")
    assert expr.minutes == (5,)
    assert expr.hours == (9, 13, 17)
    assert expr.dow.values == frozenset({1, 2, 3, 4, 5})


def test_lists_and_names():
    expr = CronExpr("0,30 0 1,15 jan,Jul *")
    assert expr.minutes == (0, 30)
    assert expr.months == (1, 7)
    assert expr.dom.values == frozenset({1, 15})


def test_sunday_is_zero_and_seven():
    assert CronExpr("0 0 * * 7").dow.values == frozenset({0})
    assert CronExpr("0 0 * * 5-7").dow.values == frozenset({5, 6, 0})


def test_step_from_a_value():
    assert CronExpr("10/20 * * * *").minutes == (10, 30, 50)
    assert CronExpr("*/20 * * * *").minutes == (0, 20, 40)


def test_macros():
    assert CronExpr("@daily").minutes == (0,) and CronExpr("@daily").hours == (0,)
    assert CronExpr("@hourly").hours == tuple(range(24))


def test_matches_wall_time():
    expr = CronExpr("30 8 * * 1")
    assert expr.matches(datetime(2026, 3, 2, 8, 30))
    assert not expr.matches(datetime(2026, 3, 3, 8, 30))
    assert not expr.matches(datetime(2026, 3, 2, 8, 31))


def test_day_specials():
    expr = CronExpr("0 0 L * *")
    assert expr.days(2026, 4) == (30,)
    assert CronExpr("0 0 * * 5L").days(2026, 1) == (30,)
    assert CronExpr("0 0 * * MON#2").days(2026, 3) == (9,)
    assert CronExpr("0 0 15W * *").days(2026, 3) == (16,)
    assert CronExpr("0 0 LW * *").days(2026, 5) == (29,)


def test_either_day_field():
    expr = CronExpr("0 0 13 * FRI")
    days = expr.days(2026, 2)
    assert 13 in days and 6 in days and 20 in days and 14 not in days


@pytest.mark.parametrize("text, message", [
    ("* * * *", "expected 5 fields, got 4"),
    ("60 * * * *", "minute value out of range: '60'"),
    ("* * * FOO *", "invalid month value: 'FOO'"),
    ("* 5-2 * * *", "invalid hour range: '5-2'"),
    ("*/0 * * * *", "invalid minute step: '*/0'"),
    ("@sometimes", "unknown macro: '@sometimes'"),
])
def test_errors(text, message):
    with pytest.raises(CronError) as info:
        CronExpr(text)
    assert str(info.value) == message
