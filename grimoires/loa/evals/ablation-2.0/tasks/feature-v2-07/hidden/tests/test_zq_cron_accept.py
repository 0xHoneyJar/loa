import datetime
import io
import os
import random
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import _oracle_zq_cron as oracle  # noqa: E402
from cronq import cli  # noqa: E402
from cronq.agenda import build_agenda, format_agenda  # noqa: E402
from cronq.clock import SimClock  # noqa: E402
from cronq.config import parse_config  # noqa: E402
from cronq.errors import JobsError, ScheduleError  # noqa: E402
from cronq.jobs import parse_jobs  # noqa: E402
from cronq.runner import Runner  # noqa: E402
from cronq.schedule import parse_schedule  # noqa: E402
from cronq.timeutil import format_local, format_utc, parse_instant  # noqa: E402
from cronq.errors import ZoneError  # noqa: E402
from cronq.zones import parse_zones  # noqa: E402

ZONES_TEXT = """\
zone Lakeland
  initial +01:00
  2026-03-29T01:00Z +02:00
  2026-10-25T01:00Z +01:00
  2027-03-28T01:00Z +02:00
  2027-10-31T01:00Z +01:00
zone Westport
  initial -05:00
  2026-03-08T07:00Z -04:00
  2026-11-01T06:00Z -05:00
zone Halfway
  initial +05:30
  2026-04-01T00:00Z +04:45
  2026-04-01T12:00Z +05:45
"""
ZONES = parse_zones(ZONES_TEXT)
UTC, LAKE, WEST = ZONES["UTC"], ZONES["Lakeland"], ZONES["Westport"]


def cron():
    from cronq.cron import parse_cron

    return parse_cron


def cron_error():
    from cronq.errors import CronError

    return CronError


def t(text):
    return parse_instant(text)


def fires(expr, after, zone=UTC, count=3, horizon=1830):
    schedule = cron()(expr, horizon)
    out, instant = [], t(after)
    for _ in range(count):
        instant = schedule.next_after(instant, zone)
        out.append(format_utc(instant))
    return out


def local_fires(expr, after, zone, count=3):
    schedule = cron()(expr)
    out, instant = [], t(after)
    for _ in range(count):
        instant = schedule.next_after(instant, zone)
        out.append(format_local(instant, zone.offset_at(instant)))
    return out


def error_of(expr, horizon=1830):
    with pytest.raises(cron_error()) as info:
        cron()(expr, horizon)
    return str(info.value)


# ---------------------------------------------------------------- cron syntax and next fire


def test_api_exports_and_error_class():
    import cronq
    from cronq.cron import CronSchedule

    assert cronq.CronError is cron_error() and cronq.parse_cron is cron() and cronq.CronSchedule is CronSchedule
    assert issubclass(cron_error(), ScheduleError)
    assert isinstance(cron()("* * * * *"), CronSchedule)
    from cronq.zones import parse_tz

    assert cronq.parse_tz is parse_tz
    for name in ("next_after", "prev_before", "count_between", "nth_after", "matches", "describe"):
        assert callable(getattr(cron()("* * * * *"), name))


def test_strictly_after_steps_ranges_and_lists():
    every = cron()("* * * * *")
    assert format_utc(every.next_after(t("2026-05-04T10:15:00Z"), UTC)) == "2026-05-04T10:16:00Z"
    assert format_utc(every.next_after(t("2026-05-04T10:15:30Z"), UTC)) == "2026-05-04T10:16:00Z"
    assert format_utc(every.next_after(t("2026-05-04T10:15:59Z"), UTC)) == "2026-05-04T10:16:00Z"
    assert fires("*/15 * * * *", "2026-05-04T10:07:30Z") == [
        "2026-05-04T10:15:00Z", "2026-05-04T10:30:00Z", "2026-05-04T10:45:00Z"]
    assert fires("10/20 * * * *", "2026-05-04T10:00:00Z") == [
        "2026-05-04T10:10:00Z", "2026-05-04T10:30:00Z", "2026-05-04T10:50:00Z"]
    assert fires("5-20/7 9 * * *", "2026-05-04T00:00:00Z", count=4) == [
        "2026-05-04T09:05:00Z", "2026-05-04T09:12:00Z", "2026-05-04T09:19:00Z", "2026-05-05T09:05:00Z"]
    assert fires("0 20/2 * * *", "2026-05-04T00:00:00Z") == [
        "2026-05-04T20:00:00Z", "2026-05-04T22:00:00Z", "2026-05-05T20:00:00Z"]
    assert fires("*/100 3,1 * * *", "2026-05-04T00:30:00Z") == [
        "2026-05-04T01:00:00Z", "2026-05-04T03:00:00Z", "2026-05-05T01:00:00Z"]
    assert fires("05 07 * * *", "2026-05-04T00:00:00Z", count=1) == ["2026-05-04T07:05:00Z"]


def test_names_dow_seven_and_matches():
    s = cron()("0 12 * feb-Apr mon-FRI")
    assert s.matches(datetime.datetime(2026, 3, 2, 12, 0))      # Monday in March
    assert not s.matches(datetime.datetime(2026, 3, 1, 12, 0))  # Sunday
    assert not s.matches(datetime.datetime(2026, 5, 4, 12, 0))  # May
    assert fires("0 0 1 Jun *", "2026-01-01T00:00:00Z", count=2) == ["2026-06-01T00:00:00Z", "2027-06-01T00:00:00Z"]
    assert fires("0 0 * * 7", "2026-05-01T00:00:00Z", count=2) == ["2026-05-03T00:00:00Z", "2026-05-10T00:00:00Z"]
    assert fires("0 0 * * 5-7", "2026-05-04T00:00:00Z", count=4) == [
        "2026-05-08T00:00:00Z", "2026-05-09T00:00:00Z", "2026-05-10T00:00:00Z", "2026-05-15T00:00:00Z"]
    assert fires("0 0 * * 1-7/3", "2026-05-04T00:00:00Z", count=3) == [
        "2026-05-07T00:00:00Z", "2026-05-10T00:00:00Z", "2026-05-11T00:00:00Z"]
    s = cron()("30 2 * * *")
    assert s.matches(datetime.datetime(2026, 3, 29, 2, 30, 45))
    assert not s.matches(datetime.datetime(2026, 3, 29, 2, 31))


def test_macros_describe_and_unknown_macros():
    assert cron()("@DAILY").describe() == "cron @DAILY"
    assert cron()("  0   9\t* * MON-FRI ").describe() == "cron 0 9 * * MON-FRI"
    assert fires("@yearly", "2026-03-01T00:00:00Z", count=1) == ["2027-01-01T00:00:00Z"]
    assert fires("@annually", "2026-03-01T00:00:00Z", count=1) == ["2027-01-01T00:00:00Z"]
    assert fires("@monthly", "2026-03-01T00:00:00Z", count=1) == ["2026-04-01T00:00:00Z"]
    assert fires("@weekly", "2026-03-01T00:00:00Z", count=1) == ["2026-03-08T00:00:00Z"]
    assert fires("@midnight", "2026-03-01T00:00:00Z", count=1) == ["2026-03-02T00:00:00Z"]
    assert fires("@Hourly", "2026-03-01T00:00:00Z", count=1) == ["2026-03-01T01:00:00Z"]
    assert error_of("@daily x") == "unknown macro '@daily x'"
    assert error_of(" @reboot ") == "unknown macro '@reboot'"
    assert error_of("@") == "unknown macro '@'"


def test_expression_and_value_errors():
    assert error_of("") == "empty expression"
    assert error_of(" \t ") == "empty expression"
    assert error_of("* * * *") == "expected 5 fields, got 4"
    assert error_of("* * * * * *") == "expected 5 fields, got 6"
    assert error_of("60 * * * *") == "field 1 (minute): value 60 out of range 0-59"
    assert error_of("* 24 * * *") == "field 2 (hour): value 24 out of range 0-23"
    assert error_of("* * 0 * *") == "field 3 (dom): value 0 out of range 1-31"
    assert error_of("* * 32 * *") == "field 3 (dom): value 32 out of range 1-31"
    assert error_of("* * * 13 *") == "field 4 (month): value 13 out of range 1-12"
    assert error_of("* * * 0 *") == "field 4 (month): value 0 out of range 1-12"
    assert error_of("* * * * 8") == "field 5 (dow): value 8 out of range 0-7"
    assert cron()("* * * * 007").matches(datetime.datetime(2026, 5, 3, 0, 0))  # 007 is 7, a Sunday
    assert error_of("MON * * * *") == "field 1 (minute): bad value 'MON'"
    assert error_of("* * * * JAN") == "field 5 (dow): bad value 'JAN'"
    assert error_of("* * ? * *") == "field 3 (dom): bad value '?'"
    assert error_of("1.5 * * * *") == "field 1 (minute): bad value '1.5'"
    assert error_of("-5 * * * *") == "field 1 (minute): bad value ''"
    assert error_of("*-5 * * * *") == "field 1 (minute): bad value '*'"
    assert error_of("1-2-3 * * * *") == "field 1 (minute): bad value '2-3'"
    assert error_of("* * * MONDAY *") == "field 4 (month): bad value 'MONDAY'"


def test_range_step_item_errors_and_order():
    assert error_of("* * * * FRI-MON") == "field 5 (dow): reversed range 'FRI-MON'"
    assert error_of("30-10 * * * *") == "field 1 (minute): reversed range '30-10'"
    assert error_of("* * * * 7-1") == "field 5 (dow): reversed range '7-1'"
    assert error_of("* * * dec-jan *") == "field 4 (month): reversed range 'dec-jan'"
    assert error_of("*/ * * * *") == "field 1 (minute): bad step ''"
    assert error_of("* * * * */MON") == "field 5 (dow): bad step 'MON'"
    assert error_of("*/0 * * * *") == "field 1 (minute): step must be at least 1"
    assert error_of("1-5/x * * * *") == "field 1 (minute): bad step 'x'"
    assert error_of("* 1/2/3 * * *") == "field 2 (hour): bad step '2/3'"
    assert error_of("1,,2 * * * *") == "field 1 (minute): empty item"
    assert error_of("* 5, * * *") == "field 2 (hour): empty item"
    assert error_of("* * * * ,1") == "field 5 (dow): empty item"
    assert error_of("61 25 * * *") == "field 1 (minute): value 61 out of range 0-59"
    assert error_of("* 25 32 * *") == "field 2 (hour): value 25 out of range 0-23"
    assert error_of("1,99,x * * * *") == "field 1 (minute): value 99 out of range 0-59"
    assert error_of("x/0 * * * *") == "field 1 (minute): bad value 'x'"
    assert error_of("5-3/0 * * * *") == "field 1 (minute): reversed range '5-3'"
    assert error_of("70-x * * * *") == "field 1 (minute): value 70 out of range 0-59"
    assert error_of("@nope 99") == "unknown macro '@nope 99'"
    assert error_of("99 * *") == "expected 5 fields, got 3"


def test_special_item_errors():
    assert error_of("* * 0W * *") == "field 3 (dom): value 0 out of range 1-31"
    assert error_of("* * 32w * *") == "field 3 (dom): value 32 out of range 1-31"
    assert error_of("* * * * 8L") == "field 5 (dow): value 8 out of range 0-7"
    assert error_of("* * * * XYZL") == "field 5 (dow): bad value 'XYZ'"
    assert error_of("* * * * 1#6") == "field 5 (dow): occurrence 6 out of range 1-5"
    assert error_of("* * * * mon#0") == "field 5 (dow): occurrence 0 out of range 1-5"
    assert error_of("* * * * 9#6") == "field 5 (dow): value 9 out of range 0-7"
    assert error_of("* * * * L") == "field 5 (dow): bad value 'L'"
    assert error_of("* * L/2 * *") == "field 3 (dom): bad value 'L'"
    assert error_of("* * 5L * *") == "field 3 (dom): bad value '5L'"
    assert error_of("* * * * MON#x") == "field 5 (dow): bad value 'MON#x'"
    assert error_of("* * * L *") == "field 4 (month): bad value 'L'"
    assert error_of("L * * * *") == "field 1 (minute): bad value 'L'"


# ---------------------------------------------------------------- days


def test_last_and_nearest_weekday_days():
    assert fires("0 0 L * *", "2026-01-15T00:00:00Z", count=4) == [
        "2026-01-31T00:00:00Z", "2026-02-28T00:00:00Z", "2026-03-31T00:00:00Z", "2026-04-30T00:00:00Z"]
    assert fires("0 0 l 2 *", "2027-03-01T00:00:00Z", count=1) == ["2028-02-29T00:00:00Z"]
    assert fires("0 0 LW * *", "2026-01-01T00:00:00Z", count=3) == [
        "2026-01-30T00:00:00Z", "2026-02-27T00:00:00Z", "2026-03-31T00:00:00Z"]
    assert fires("0 0 lw 5 *", "2026-01-01T00:00:00Z", count=1) == ["2026-05-29T00:00:00Z"]
    # 2026-02-15 and 2026-03-15 are Sundays, 2026-08-15 a Saturday
    assert fires("0 0 15W 2,3,8 *", "2026-01-01T00:00:00Z", count=3) == [
        "2026-02-16T00:00:00Z", "2026-03-16T00:00:00Z", "2026-08-14T00:00:00Z"]
    # 2026-08-01 is a Saturday: the Monday after; 2026-02-01 a Sunday: the Monday after
    assert fires("0 0 1W 2,8 *", "2026-01-01T00:00:00Z", count=2) == ["2026-02-02T00:00:00Z", "2026-08-03T00:00:00Z"]
    # 2026-05-31 is a Sunday and the month's last day: the Friday before
    assert fires("0 0 31W 5 *", "2026-01-01T00:00:00Z", count=1) == ["2026-05-29T00:00:00Z"]
    # 2026-08-30 is a Sunday but not the last day: the Monday after
    assert fires("0 0 30W 8 *", "2026-01-01T00:00:00Z", count=1) == ["2026-08-31T00:00:00Z"]
    # April, June have no 31st: 31W picks nothing there
    assert fires("0 0 31W 4-7 *", "2026-01-01T00:00:00Z", count=2) == ["2026-05-29T00:00:00Z", "2026-07-31T00:00:00Z"]
    assert fires("0 0 31 * *", "2026-04-01T00:00:00Z", count=1) == ["2026-05-31T00:00:00Z"]


def test_last_and_nth_weekday_of_month():
    assert fires("0 0 * * 5L", "2026-01-01T00:00:00Z", count=3) == [
        "2026-01-30T00:00:00Z", "2026-02-27T00:00:00Z", "2026-03-27T00:00:00Z"]
    assert fires("0 0 * * friL", "2026-01-01T00:00:00Z", count=1) == ["2026-01-30T00:00:00Z"]
    assert fires("0 0 * * 7L", "2026-05-01T00:00:00Z", count=1) == ["2026-05-31T00:00:00Z"]
    assert fires("0 0 * * MON#2", "2026-01-01T00:00:00Z", count=3) == [
        "2026-01-12T00:00:00Z", "2026-02-09T00:00:00Z", "2026-03-09T00:00:00Z"]
    # fifth Friday: January and May 2026 have one, February to April do not
    assert fires("0 0 * * 5#5", "2026-01-01T00:00:00Z", count=2) == ["2026-01-30T00:00:00Z", "2026-05-29T00:00:00Z"]
    assert fires("0 0 * * 7#1,1#1", "2026-05-01T00:00:00Z", count=2) == ["2026-05-03T00:00:00Z", "2026-05-04T00:00:00Z"]


def test_day_field_combination():
    assert fires("0 0 13 * 5", "2026-05-01T00:00:00Z", count=4) == [
        "2026-05-08T00:00:00Z", "2026-05-13T00:00:00Z", "2026-05-15T00:00:00Z", "2026-05-22T00:00:00Z"]
    assert fires("0 0 L * 1#1", "2026-05-01T00:00:00Z", count=3) == [
        "2026-05-04T00:00:00Z", "2026-05-31T00:00:00Z", "2026-06-01T00:00:00Z"]
    # dom */1 is restricted, so with a restricted dow either one matching is enough: every day
    assert fires("0 0 */1 * 1", "2026-05-04T00:00:00Z", count=3) == [
        "2026-05-05T00:00:00Z", "2026-05-06T00:00:00Z", "2026-05-07T00:00:00Z"]
    assert fires("0 0 1 * 0-7", "2026-05-04T00:00:00Z", count=2) == ["2026-05-05T00:00:00Z", "2026-05-06T00:00:00Z"]
    assert fires("0 0 * * 1", "2026-05-04T00:00:00Z", count=2) == ["2026-05-11T00:00:00Z", "2026-05-18T00:00:00Z"]
    assert fires("0 0 1 * *", "2026-05-04T00:00:00Z", count=2) == ["2026-06-01T00:00:00Z", "2026-07-01T00:00:00Z"]
    assert fires("0 0 * * SAT", "2026-05-04T00:00:00Z", count=2) == ["2026-05-09T00:00:00Z", "2026-05-16T00:00:00Z"]
    assert fires("0 0 13 FEB 5", "2026-01-01T00:00:00Z", count=4) == [
        "2026-02-06T00:00:00Z", "2026-02-13T00:00:00Z", "2026-02-20T00:00:00Z", "2026-02-27T00:00:00Z"]


# ---------------------------------------------------------------- zones


def test_wall_time_gap_and_overlap():
    assert local_fires("0 9 * * *", "2026-01-10T00:00:00Z", WEST, count=1) == ["2026-01-10T09:00-05:00"]
    assert fires("0 9 * * *", "2026-01-10T00:00:00Z", WEST, count=1) == ["2026-01-10T14:00:00Z"]
    assert local_fires("30 2 * * *", "2026-03-28T12:00:00Z", LAKE, count=2) == [
        "2026-03-30T02:30+02:00", "2026-03-31T02:30+02:00"]
    assert local_fires("*/30 * * * *", "2026-03-29T00:15:00Z", LAKE, count=3) == [
        "2026-03-29T01:30+01:00", "2026-03-29T03:00+02:00", "2026-03-29T03:30+02:00"]
    assert local_fires("30 2 * * *", "2026-03-07T12:00:00Z", WEST, count=2) == [
        "2026-03-09T02:30-04:00", "2026-03-10T02:30-04:00"]
    assert fires("30 2 * * *", "2026-10-24T12:00:00Z", LAKE, count=2) == ["2026-10-25T00:30:00Z", "2026-10-26T01:30:00Z"]
    assert local_fires("*/30 1-2 * * *", "2026-10-24T23:00:00Z", LAKE, count=4) == [
        "2026-10-25T01:30+02:00", "2026-10-25T02:00+02:00", "2026-10-25T02:30+02:00", "2026-10-26T01:00+01:00"]
    assert fires("30 1 * * *", "2026-10-31T12:00:00Z", WEST, count=2) == ["2026-11-01T05:30:00Z", "2026-11-02T06:30:00Z"]
    # 01:10Z is 02:10+01:00, the second pass of 02:00-02:59; those wall times already occurred
    assert local_fires("*/15 * * * *", "2026-10-25T01:10:00Z", LAKE, count=2) == [
        "2026-10-25T03:00+01:00", "2026-10-25T03:15+01:00"]
    assert local_fires("10 2 * * *", "2026-10-25T00:30:00Z", LAKE, count=1) == ["2026-10-26T02:10+01:00"]


def test_horizon():
    assert error_of_next("0 0 30 2 *", "2026-01-01T00:00:00Z") == "no fire time within 1830 days"
    assert error_of_next("0 0 1 1 *", "2026-02-01T00:00:00Z", horizon=30) == "no fire time within 30 days"
    # exactly horizon_days x 86400 seconds later is still a candidate
    assert fires("0 0 1 * *", "2026-01-01T00:00:00Z", count=1, horizon=31) == ["2026-02-01T00:00:00Z"]
    assert error_of_next("0 0 1 * *", "2026-01-01T00:00:00Z", horizon=30) == "no fire time within 30 days"
    assert fires("0 0 29 2 *", "2026-01-01T00:00:00Z", count=1) == ["2028-02-29T00:00:00Z"]


def error_of_next(expr, after, zone=UTC, horizon=1830):
    schedule = cron()(expr, horizon)
    with pytest.raises(cron_error()) as info:
        schedule.next_after(t(after), zone)
    return str(info.value)


def test_schedule_jobs_and_config_integration():
    s = parse_schedule("  cron   */5 * * * * ")
    assert s.describe() == "cron */5 * * * *"
    assert format_utc(s.next_after(t("2026-05-04T10:01:00Z"), UTC)) == "2026-05-04T10:05:00Z"
    with pytest.raises(cron_error()) as info:
        parse_schedule("cron")
    assert str(info.value) == "empty expression"
    with pytest.raises(cron_error()):
        parse_schedule("cron 0 0 1 1 *", 5).next_after(t("2026-02-01T00:00:00Z"), UTC)
    with pytest.raises(JobsError) as info:
        parse_jobs("a | - | every 5m | x\nb | - | cron 0 0 32 * * | y\n", ZONES)
    assert str(info.value) == "jobs:2: bad schedule: field 3 (dom): value 32 out of range 1-31"
    with pytest.raises(JobsError) as info:
        parse_jobs("b | - | cron | y\n", ZONES)
    assert str(info.value) == "jobs:1: bad schedule: empty expression"
    jobs = parse_jobs("b | Lakeland | cron 0 0 1 1 * | y\n", ZONES, parse_config("horizon_days = 10\n"))
    with pytest.raises(cron_error()) as info:
        jobs[0].next_after(t("2026-02-01T00:00:00Z"))
    assert str(info.value) == "no fire time within 10 days"


def test_agenda_with_cron_jobs():
    jobs = parse_jobs("backup | Lakeland | cron 30 2 * * * | b\nping | - | every 1d | p\n", ZONES)
    lines = format_agenda(build_agenda(jobs, t("2026-03-28T00:00:00Z"), 4))
    assert lines == [
        "2026-03-28T02:30+01:00 backup",
        "2026-03-29T00:00+00:00 ping",
        "2026-03-30T00:00+00:00 ping",
        "2026-03-30T02:30+02:00 backup",
    ]
    config = parse_config("horizon_days = 400\n")
    jobs = parse_jobs("never | - | cron 0 0 30 2 * | n\nleap | - | cron 0 0 29 2 * | m\n", ZONES, config)
    # the leap-day job fires on 2028-02-29 and then has nothing within 400 days
    assert format_agenda(build_agenda(jobs, t("2027-06-01T00:00:00Z"), 5)) == ["2028-02-29T00:00+00:00 leap"]
    assert format_agenda(build_agenda(jobs[:1], t("2027-06-01T00:00:00Z"), 5)) == ["no upcoming runs"]
    start = t("2028-02-28T23:00:00Z")
    runner = Runner(jobs, start)
    entries = runner.run(SimClock(start), t("2028-02-29T02:00:00Z"), 30)
    assert [entry.format() for entry in entries] == ["2028-02-29T00:00:00Z leap fires=1"]


def test_runner_with_cron_jobs():
    jobs = parse_jobs("hourly | - | cron 0 * * * * | h\n", ZONES)
    start = t("2026-05-04T00:30:00Z")
    runner = Runner(jobs, start)
    entries = runner.run(SimClock(start), t("2026-05-04T03:30:00Z"), 180)
    assert [entry.format() for entry in entries] == ["2026-05-04T03:00:00Z hourly fires=3"]
    jobs = parse_jobs("half | Lakeland | cron */30 * * * * | h\n", ZONES)
    start = t("2026-10-24T23:45:00Z")
    runner = Runner(jobs, start)
    entries = runner.tick(t("2026-10-25T02:15:00Z"))
    assert [entry.format() for entry in entries] == ["2026-10-25T02:00:00Z half fires=3"]


def run_cli(argv, tmp_path):
    zones = tmp_path / "zones.txt"
    zones.write_text(ZONES_TEXT)
    argv = [str(zones) if arg == "ZONES" else arg for arg in argv]
    out, err = io.StringIO(), io.StringIO()
    status = cli.main(argv, stdout=out, stderr=err)
    return status, out.getvalue(), err.getvalue()


def test_cli_next_and_validate(tmp_path):
    status, out, err = run_cli(
        ["next", "--zones", "ZONES", "--zone", "Lakeland", "--after", "2026-03-28T00:00Z", "--count", "3", "30 2 * * *"],
        tmp_path)
    assert (status, err) == (0, "")
    assert out == "2026-03-28T02:30+01:00\n2026-03-30T02:30+02:00\n2026-03-31T02:30+02:00\n"
    status, out, err = run_cli(["next", "--after", "2026-05-04T10:07:30Z", "*/15 * * * *"], tmp_path)
    assert (status, out, err) == (0, "2026-05-04T10:15+00:00\n", "")
    status, out, err = run_cli(["next", "--after", "2026-05-04T10:00Z", "* * 32 * *"], tmp_path)
    assert (status, out, err) == (2, "", "cronq: field 3 (dom): value 32 out of range 1-31\n")
    status, out, err = run_cli(["next", "--zone", "Lakeland", "--after", "2026-05-04T10:00Z", "* * * * *"], tmp_path)
    assert (status, out, err) == (2, "", "cronq: unknown zone 'Lakeland'\n")
    status, out, err = run_cli(["next", "--after", "2026-05-04T10:00Z", "--horizon", "0", "* * * * *"], tmp_path)
    assert (status, out, err) == (2, "", "cronq: horizon must be an integer 1..36600, got '0'\n")
    status, out, err = run_cli(
        ["next", "--after", "2026-06-01T00:00Z", "--count", "3", "--horizon", "300", "0 0 1 1 *"], tmp_path)
    assert (status, out, err) == (2, "2027-01-01T00:00+00:00\n", "cronq: no fire time within 300 days\n")
    jobs = tmp_path / "jobs.txt"
    jobs.write_text("backup | Lakeland | cron  30 2 * *   SUN | b\nping | - | every 15m | p\n")
    status, out, err = run_cli(["validate", "--jobs", str(jobs), "--zones", "ZONES"], tmp_path)
    assert (status, err) == (0, "")
    assert out == "backup Lakeland cron 30 2 * * SUN\nping UTC every 15m\nok 2 jobs\n"


# ---------------------------------------------------------------- conformance against the reference model

ZONE_LIST = [UTC, LAKE, WEST, ZONES["Halfway"]]
TRANSITIONS = [when for zone in ZONE_LIST for when, _ in zone.changes]


# ---------------------------------------------------------------- earlier fires, counts, n-th fire


def prevs(expr, before, zone=UTC, count=3, horizon=1830):
    schedule = cron()(expr, horizon)
    out, instant = [], t(before)
    for _ in range(count):
        instant = schedule.prev_before(instant, zone)
        out.append(format_utc(instant))
    return out


def error_of_prev(expr, before, zone=UTC, horizon=1830):
    schedule = cron()(expr, horizon)
    with pytest.raises(cron_error()) as info:
        schedule.prev_before(t(before), zone)
    return str(info.value)


def test_prev_before_is_strictly_before():
    assert prevs("*/15 * * * *", "2026-05-04T10:15:30Z") == [
        "2026-05-04T10:15:00Z", "2026-05-04T10:00:00Z", "2026-05-04T09:45:00Z"]
    assert prevs("*/15 * * * *", "2026-05-04T10:00:01Z", count=1) == ["2026-05-04T10:00:00Z"]
    assert prevs("0 9 * * *", "2026-05-04T09:00:00Z", count=2) == ["2026-05-03T09:00:00Z", "2026-05-02T09:00:00Z"]
    assert prevs("0 0 L * *", "2026-03-15T00:00:00Z", count=2) == ["2026-02-28T00:00:00Z", "2026-01-31T00:00:00Z"]


def test_prev_before_returns_the_first_occurrence_of_a_repeated_wall_time():
    assert prevs("30 2 * * *", "2026-10-25T03:00:00Z", LAKE, count=2) == ["2026-10-25T00:30:00Z", "2026-10-24T00:30:00Z"]
    assert prevs("30 1 * * *", "2026-11-01T12:00:00Z", WEST, count=1) == ["2026-11-01T05:30:00Z"]


def test_prev_before_across_the_repeated_stretch():
    assert prevs("*/15 * * * *", "2026-10-25T01:40:00Z", LAKE, count=2) == ["2026-10-25T00:45:00Z", "2026-10-25T00:30:00Z"]
    assert prevs("*/15 * * * *", "2026-10-25T02:10:00Z", LAKE, count=3) == [
        "2026-10-25T02:00:00Z", "2026-10-25T00:45:00Z", "2026-10-25T00:30:00Z"]


def test_prev_before_skips_the_gap():
    assert prevs("30 2 * * *", "2026-03-30T12:00:00Z", LAKE, count=2) == ["2026-03-30T00:30:00Z", "2026-03-28T01:30:00Z"]
    assert prevs("*/30 * * * *", "2026-03-29T01:10:00Z", LAKE, count=3) == [
        "2026-03-29T01:00:00Z", "2026-03-29T00:30:00Z", "2026-03-29T00:00:00Z"]


def test_prev_before_horizon():
    assert prevs("0 0 1 * *", "2026-02-01T00:00:00Z", count=1, horizon=31) == ["2026-01-01T00:00:00Z"]
    assert error_of_prev("0 0 1 * *", "2026-02-01T00:00:00Z", horizon=30) == "no fire time within 30 days before"
    assert error_of_prev("0 0 30 2 *", "2026-02-01T00:00:00Z") == "no fire time within 1830 days before"


def count(expr, start, end, zone=UTC):
    return cron()(expr).count_between(t(start), t(end), zone)


def test_count_between_bounds():
    assert count("*/15 * * * *", "2026-05-04T10:00:00Z", "2026-05-04T11:00:00Z") == 4
    assert count("*/15 * * * *", "2026-05-04T10:00:30Z", "2026-05-04T11:00:30Z") == 4
    assert count("*/15 * * * *", "2026-05-04T10:00:00Z", "2026-05-04T10:00:00Z") == 0
    assert count("*/15 * * * *", "2026-05-04T09:59:59Z", "2026-05-04T10:00:00Z") == 1
    assert count("0 0 13 * 5", "2026-05-01T00:00:00Z", "2026-06-01T00:00:00Z") == 5


def test_count_between_across_offset_changes():
    assert count("*/30 * * * *", "2026-10-24T22:00:00Z", "2026-10-25T04:00:00Z", LAKE) == 10
    assert count("*/30 * * * *", "2026-03-28T22:00:00Z", "2026-03-29T04:00:00Z", LAKE) == 12
    assert count("30 2 * * *", "2026-03-27T00:00:00Z", "2026-03-31T00:00:00Z", LAKE) == 3
    assert count("0 * * * *", "2026-01-01T00:00:00Z", "2027-01-01T00:00:00Z", LAKE) == 8759


def test_count_between_errors_and_the_span_limit():
    start = t("2026-01-01T00:00:00Z")
    every = cron()("* * * * *", 5)
    assert every.count_between(start, start + 1096 * 86400, UTC) == 1578240
    with pytest.raises(cron_error()) as info:
        every.count_between(start, start + 1096 * 86400 + 1, UTC)
    assert str(info.value) == "span longer than 1096 days"
    with pytest.raises(cron_error()) as info:
        every.count_between(start, start - 1, UTC)
    assert str(info.value) == "end before start"
    with pytest.raises(cron_error()) as info:
        every.count_between(start + 2000 * 86400, start, UTC)
    assert str(info.value) == "end before start"


def test_nth_after():
    s = cron()("0 9 * * *")
    after = t("2026-05-04T10:00:00Z")
    assert s.nth_after(after, 1, UTC) == s.next_after(after, UTC) == t("2026-05-05T09:00:00Z")
    assert s.nth_after(after, 3, UTC) == t("2026-05-07T09:00:00Z")
    assert cron()("*/30 * * * *").nth_after(t("2026-10-24T23:45:00Z"), 3, LAKE) == t("2026-10-25T02:00:00Z")
    # horizon_days plays no part
    assert cron()("0 0 1 1 *", 30).nth_after(t("2026-02-01T00:00:00Z"), 2, UTC) == t("2028-01-01T00:00:00Z")
    daily = cron()("0 0 * * *", 1)
    assert daily.nth_after(t("2026-01-01T00:00:00Z"), 1096, UTC) == t("2029-01-01T00:00:00Z")


def test_nth_after_errors():
    leap = cron()("0 0 29 2 *")
    assert leap.nth_after(t("2026-01-01T00:00:00Z"), 1, UTC) == t("2028-02-29T00:00:00Z")
    for n, message in [(0, "n must be at least 1"), (-3, "n must be at least 1"), (2, "fewer than 2 fire times within 1096 days")]:
        with pytest.raises(cron_error()) as info:
            leap.nth_after(t("2026-01-01T00:00:00Z"), n, UTC)
        assert str(info.value) == message
    with pytest.raises(cron_error()) as info:
        cron()("0 0 * * *").nth_after(t("2026-01-01T00:00:00Z"), 1097, UTC)
    assert str(info.value) == "fewer than 1097 fire times within 1096 days"


def test_cli_prev_and_count(tmp_path):
    status, out, err = run_cli(
        ["prev", "--tz", "CET-1CEST,M3.5.0,M10.5.0/3", "--before", "2026-10-26T00:00Z", "--count", "3", "30 2 * * *"], tmp_path)
    assert (status, out, err) == (0, "2026-10-25T02:30+02:00\n2026-10-24T02:30+02:00\n2026-10-23T02:30+02:00\n", "")
    status, out, err = run_cli(["prev", "--before", "2026-01-20T00:00Z", "--count", "2", "--horizon", "40", "0 0 1 1 *"], tmp_path)
    assert (status, out, err) == (2, "2026-01-01T00:00+00:00\n", "cronq: no fire time within 40 days before\n")
    status, out, err = run_cli(
        ["count", "--zones", "ZONES", "--zone", "Lakeland", "--from", "2026-10-24T22:00Z", "--to", "2026-10-25T04:00Z", "*/30 * * * *"],
        tmp_path)
    assert (status, out, err) == (0, "10\n", "")
    status, out, err = run_cli(["count", "--from", "2026-05-04T00:00Z", "--to", "2026-05-03T00:00Z", "* * * * *"], tmp_path)
    assert (status, out, err) == (2, "", "cronq: end before start\n")


# ---------------------------------------------------------------- rule zones


def tz(text, name="TZ"):
    from cronq.zones import parse_tz

    return parse_tz(text, name)


def tz_error(text):
    with pytest.raises(ZoneError) as info:
        tz(text)
    return str(info.value)


def changes_in(zone, year):
    low, high = t(f"{year}-01-01T00:00Z"), t(f"{year + 1}-01-01T00:00Z")
    return [(format_utc(when), offset) for when, offset in zone.changes if low <= when < high]


def test_tz_standard_only_zones_and_the_sign():
    assert (tz("EST5").initial, tuple(tz("EST5").changes)) == (-300, ())
    assert tz("<+0330>-3:30").initial == 210
    assert tz("UTC0").initial == 0
    assert tz("<-03>3").initial == -180
    assert tz("AAA+2").initial == -120 and tz("BBB-14").initial == 840
    assert tz(" ABC-05:45:00 ").initial == 345
    assert tz("EST5").name == "TZ" and tz("EST5", "Eastern").name == "Eastern"


def test_tz_month_week_day_rules():
    us = tz("EST5EDT,M3.2.0/2,M11.1.0/2")
    assert len(us.changes) == 460 and us.initial == -300
    assert tuple(us.changes[0]) == (t("1970-03-08T07:00Z"), -240)
    assert changes_in(us, 2026) == [("2026-03-08T07:00:00Z", -240), ("2026-11-01T06:00:00Z", -300)]
    eu = tz("CET-1CEST,M3.5.0,M10.5.0/3")
    assert changes_in(eu, 2026) == [("2026-03-29T01:00:00Z", 120), ("2026-10-25T01:00:00Z", 60)]
    assert changes_in(eu, 2027) == [("2027-03-28T01:00:00Z", 120), ("2027-10-31T01:00:00Z", 60)]
    last = tz("AAA0BBB,M2.5.0/0,M5.5.6/0")  # February 2026 has four Sundays
    assert changes_in(last, 2026) == [("2026-02-22T00:00:00Z", 60), ("2026-05-29T23:00:00Z", 0)]
    assert changes_in(tz("AAA0BBB,M03.2.0,M11.1.0"), 2026)[0] == ("2026-03-08T02:00:00Z", 60)


def test_tz_explicit_daylight_offset():
    zone = tz("AAA-1BBB-3,M3.5.0,M10.5.0")
    assert changes_in(zone, 2026) == [("2026-03-29T01:00:00Z", 180), ("2026-10-24T23:00:00Z", 60)]
    assert changes_in(tz("<-02>2<+01>-1,M3.5.0,M10.5.0"), 2026) == [("2026-03-29T04:00:00Z", 60), ("2026-10-25T01:00:00Z", -120)]


def test_tz_julian_and_zero_based_days():
    julian = tz("AAA0BBB,J60/0,J300/0")
    assert changes_in(julian, 2026) == [("2026-03-01T00:00:00Z", 60), ("2026-10-26T23:00:00Z", 0)]
    assert changes_in(julian, 2028) == [("2028-03-01T00:00:00Z", 60), ("2028-10-26T23:00:00Z", 0)]
    zero = tz("AAA0BBB,59/0,365/0")
    assert ("2026-03-01T00:00:00Z", 60) in changes_in(zero, 2026)
    assert ("2026-12-31T23:00:00Z", 0) in changes_in(zero, 2026)
    assert changes_in(zero, 2028) == [("2028-02-29T00:00:00Z", 60), ("2028-12-30T23:00:00Z", 0)]


def test_tz_transition_times_beyond_the_day():
    zone = tz("AAA0BBB,M3.2.0/-1,M11.1.0/26")
    assert changes_in(zone, 2026) == [("2026-03-07T23:00:00Z", 60), ("2026-11-02T01:00:00Z", 0)]
    zone = tz("AAA0BBB,M3.2.0/167,M11.1.0/-2:30")
    assert changes_in(zone, 2026) == [("2026-03-14T23:00:00Z", 60), ("2026-10-31T20:30:00Z", 0)]
    assert changes_in(tz("AAA0BBB,M3.2.0/2:30:00,M11.1.0/+1"), 2026) == [("2026-03-08T02:30:00Z", 60), ("2026-11-01T00:00:00Z", 0)]


def test_tz_southern_hemisphere():
    zone = tz("<+10>-10<+11>,M10.1.0,M4.1.0/3")
    assert changes_in(zone, 2026) == [("2026-04-04T16:00:00Z", 600), ("2026-10-03T16:00:00Z", 660)]
    assert zone.offset_at(t("2026-01-15T00:00Z")) == 660 and zone.offset_at(t("2026-07-01T00:00Z")) == 600


def test_tz_errors_in_names_and_offsets():
    cases = {
        "": "empty rule", "  ": "empty rule",
        "E5": "bad std name", "<AB>5": "bad std name", "<ABC5": "bad std name", "<A_B>5": "bad std name",
        "5EST": "bad std name",
        "EST": "bad std offset", "EST25": "bad std offset", "EST5:3": "bad std offset", "EST5:30:01": "bad std offset",
        "EST123": "bad std offset", "EST5,M3.2.0,M11.1.0": "bad std offset", "EST 5": "bad std offset",
        "EST5ED": "bad dst name", "EST5<ED>": "bad dst name",
        "EST5EDT4:5,M3.2.0,M11.1.0": "bad dst offset", "EST5EDT;": "bad dst offset", "EST5EDT4x": "bad dst offset",
        "EST5EDT": "dst rules required", "EST5EDT4": "dst rules required",
    }
    assert {text: tz_error(text) for text in cases} == cases


def test_tz_errors_in_rules_and_times():
    cases = {
        "EST5EDT,M3.2.0": "bad start rule", "EST5EDT,M13.2.0,M11.1.0": "bad start rule",
        "EST5EDT,M3.6.0,M11.1.0": "bad start rule", "EST5EDT,M3.2.7,M11.1.0": "bad start rule",
        "EST5EDT,J0,J300": "bad start rule", "EST5EDT,J366,J300": "bad start rule", "EST5EDT,366,1": "bad start rule",
        "EST5EDT,M3.2.07,M11.1.0": "bad start rule", "EST5EDT, M3.2.0,M11.1.0": "bad start rule",
        "EST5EDT,M3.2.0/168,M11.1.0": "bad start time", "EST5EDT,M3.2.0/,M11.1.0": "bad start time",
        "EST5EDT,M3.2.0/2x,M11.1.0": "bad start time",
        "EST5EDT,M3.2.0,": "bad end rule", "EST5EDT,M3.2.0,M11.1": "bad end rule",
        "EST5EDT,M3.2.0,M11.1.0,": "bad end rule", "EST5EDT,M3.2.0/2,M11.1.0x": "bad end rule",
        "EST5EDT,M3.2.0,M11.1.0/-168": "bad end time", "EST5EDT,M3.2.0,M11.1.0/2,": "bad end time",
        "EST5EDT,M3.2.0,M11.1.0/2:5": "bad end time",
    }
    assert {text: tz_error(text) for text in cases} == cases


def test_zone_file_rule_entries():
    zones = parse_zones("zone Eastern\n  rule EST5EDT,M3.2.0/2,M11.1.0/2\nzone Fixed\n  initial +01:00\n")
    eastern = zones["Eastern"]
    assert eastern.name == "Eastern" and eastern.offset_at(t("2026-07-01T00:00Z")) == -240
    assert changes_in(eastern, 2026) == changes_in(tz("EST5EDT,M3.2.0/2,M11.1.0/2"), 2026)
    jobs = parse_jobs("late | Eastern | cron 30 1 * * * | x\n", zones)
    assert format_utc(jobs[0].next_after(t("2026-11-01T00:00:00Z"))) == "2026-11-01T05:30:00Z"
    for text, message in [
        ("zone A\n rule EST5\n rule EST5\n", "zones:3: second rule"),
        ("zone A\n initial +01:00\n rule EST5\n", "zones:3: rule and table entries cannot be mixed"),
        ("zone A\n rule EST5\n 2026-01-01T00:00Z +01:00\n", "zones:3: rule and table entries cannot be mixed"),
        ("zone A\n rule EST5\n initial +01:00\n", "zones:3: rule and table entries cannot be mixed"),
        ("zone A\n rule EST5EDT\n", "zones:2: dst rules required"),
    ]:
        with pytest.raises(ZoneError) as info:
            parse_zones(text)
        assert str(info.value) == message


def test_cron_in_rule_zones():
    eu = tz("CET-1CEST,M3.5.0,M10.5.0/3")
    assert local_fires("30 2 * * *", "2026-03-28T12:00:00Z", eu, count=2) == ["2026-03-30T02:30+02:00", "2026-03-31T02:30+02:00"]
    assert fires("30 2 * * *", "2026-10-24T12:00:00Z", eu, count=2) == ["2026-10-25T00:30:00Z", "2026-10-26T01:30:00Z"]
    chatham = tz("<+1245>-12:45<+1345>,M9.5.0/2:45,M4.1.0/3:45")
    assert fires("0 3 * * *", "2026-04-04T12:00:00Z", chatham, count=2) == ["2026-04-04T13:15:00Z", "2026-04-05T14:15:00Z"]
    assert prevs("0 3 * * *", "2026-04-04T14:00:00Z", chatham, count=1) == ["2026-04-04T13:15:00Z"]


def test_cli_tz_option(tmp_path):
    status, out, err = run_cli(
        ["next", "--tz", "EST5EDT,M3.2.0/2,M11.1.0/2", "--after", "2026-03-07T12:00Z", "--count", "2", "30 2 * * *"], tmp_path)
    assert (status, out, err) == (0, "2026-03-09T02:30-04:00\n2026-03-10T02:30-04:00\n", "")
    status, out, err = run_cli(["next", "--zone", "UTC", "--tz", "EST5", "--after", "2026-03-07T12:00Z", "* * * * *"], tmp_path)
    assert (status, out, err) == (2, "", "cronq: --zone and --tz are exclusive\n")
    status, out, err = run_cli(["count", "--tz", "EST5EDT", "--from", "2026-03-07T12:00Z", "--to", "2026-03-08T12:00Z", "* * * * *"], tmp_path)
    assert (status, out, err) == (2, "", "cronq: dst rules required\n")


# ---------------------------------------------------------------- conformance against the reference model

ZONE_LIST = [UTC, LAKE, WEST, ZONES["Halfway"]]
TRANSITIONS = [when for zone in ZONE_LIST for when, _ in zone.changes]


def implementation(expr, instant, zone, horizon, count, backward=False):
    try:
        schedule = cron()(expr, horizon)
    except cron_error() as exc:
        return ("error", str(exc), [])
    found = []
    for _ in range(count):
        try:
            instant = schedule.prev_before(instant, zone) if backward else schedule.next_after(instant, zone)
        except cron_error() as exc:
            return ("error", str(exc), found)
        found.append(instant)
    return ("ok", None, found)


def pick(rng, choices, most=3):
    return ",".join(rng.choice(choices) for _ in range(rng.choice([1, 1, 1, 2, most])))


MINUTES = ["*", "*/5", "*/7", "0", "15", "30", "45", "0-10", "10-20/3", "5/15", "59", "7", "0-59/13", "*/1", "*/20", "07"]
HOURS = ["*", "0", "1", "2", "3", "9", "12", "23", "1-3", "*/6", "8-17/2", "22/1", "*/1", "02"]


def gen_numeric(rng):
    return " ".join([pick(rng, MINUTES), pick(rng, HOURS), pick(rng, ["*", "1", "15", "*/10", "1-7", "28", "31", "29-31"]),
                     pick(rng, ["*", "1", "*/3", "6-8", "2", "4/4"]), pick(rng, ["*", "0", "1-5", "6", "*/2", "0-7/2", "7"])])


def gen_names(rng):
    return " ".join([pick(rng, MINUTES), pick(rng, HOURS), "*",
                     pick(rng, ["jan", "FEB-apr", "Jun", "*/2", "oct-DEC", "SEP", "mAr-May/2", "Nov"]),
                     pick(rng, ["mon-fri", "SAT", "sun", "Tue-Thu", "wed", "Fri-sat", "SUN-SAT/2", "thu"])])


def gen_dom_special(rng):
    return " ".join([pick(rng, ["0", "30"]), pick(rng, ["0", "12"]),
                     pick(rng, ["L", "LW", "lw", "1W", "15W", "30W", "31W", "29W", "l", "2w", "6W", "13", "28w"]),
                     pick(rng, ["*", "2", "*/2", "4-6", "9", "feb-apr", "8"]), "*"])


def gen_dow_special(rng):
    return " ".join([pick(rng, ["0", "30"]), pick(rng, ["0", "12"]), "*",
                     pick(rng, ["*", "2", "*/2", "4-6", "9", "1-3"]),
                     pick(rng, ["5L", "FRIL", "0L", "7l", "1#1", "MON#2", "5#5", "0#3", "7#4", "sat#5", "thu#1", "3L", "2#5", "6"])])


def gen_domdow(rng):
    return " ".join([rng.choice(["0", "30"]), rng.choice(["0", "6"]),
                     pick(rng, ["*", "*/1", "13", "1-7", "L", "15W", "*/2", "1", "31", "LW"]) if rng.random() < 0.8 else "*",
                     rng.choice(["*", "*/1", "2", "*/2", "5-7"]),
                     pick(rng, ["*", "*/1", "5", "MON", "1#1", "5L", "0-6", "7", "sat"]) if rng.random() < 0.8 else "*"])


BAD_ITEMS = ["", "60", "x", "*/0", "*/", "5-3", "MON", "L", "LW", "0W", "8L", "1#6", "a-b", "-", "/", "1-", "*-1",
             "07", "1/x", "32W", "XYZL", "jan", "Mon#2", "#", "w", "2W/3", "*/MON", "5", "*", "1-5/2", "24", "13",
             "fri-mon", "7-0", "0#0", "1#1", "LW,L", "99", "?", "1.0", "+1", "2/0", "sun", "l/1", "3#", "#2"]


def gen_errors(rng):
    count = rng.choice([5, 5, 5, 5, 4, 6, 1])
    fields = [pick(rng, BAD_ITEMS, 2) if rng.random() < 0.4 else rng.choice(["*", "1", "*/2", "1-3"]) for _ in range(count)]
    text = rng.choice([" ", "\t", "  "]).join(fields)
    if rng.random() < 0.1:
        text = rng.choice(["@", "@daily", "@DAILY ", "@weekly x", "@reboot", " @Monthly", "@hour"])
    return text


def gen_sparse(rng):
    return rng.choice(["0 0 30 2 *", "0 0 29 2 *", "0 0 31 * *", "0 0 * * 1#5", "0 0 31W 2 *", "0 0 L 2 *", "@yearly",
                       "0 0 13 * 5", "0 0 1 1 1", "0 0 29 2 1", "30 2 1 1 *", "0 0 15W 6 *", "0 0 * 2 5#5", "@monthly"])


def gen_macro(rng):
    name = rng.choice(["@yearly", "@annually", "@monthly", "@weekly", "@daily", "@midnight", "@hourly", "@week", "@reboot"])
    name = "".join(c.upper() if rng.random() < 0.3 else c for c in name)
    return rng.choice(["", " ", "\t"]) + name + rng.choice(["", " ", "  \t"])


def gen_mixed(rng):
    return rng.choice([gen_numeric, gen_names, gen_dom_special, gen_dow_special, gen_domdow])(rng)


def near_transition(rng):
    return rng.choice(TRANSITIONS) + rng.randrange(-2 * 86400, 2 * 86400)


def anywhere(rng):
    return t("2026-01-01T00:00:00Z") + rng.randrange(0, 700 * 86400)


def gen_names_or_numeric(rng):
    return gen_names(rng) if rng.random() < 0.5 else gen_numeric(rng)


def gen_day_specials(rng):
    return gen_dom_special(rng) if rng.random() < 0.5 else gen_dow_special(rng)


def gen_errors_or_macros(rng):
    return gen_macro(rng) if rng.random() < 0.25 else gen_errors(rng)


def forward_case(generate, zone_of, instant_of, samples, horizon_of, backward=False):
    def check(rng):
        for _ in range(samples):
            expr, zone, instant, horizon = generate(rng), zone_of(rng), instant_of(rng), horizon_of(rng)
            expected = oracle.outcome(expr, instant, zone.initial, zone.changes, horizon, 3, backward)
            actual = implementation(expr, instant, zone, horizon, 3, backward)
            assert actual == expected, (expr, zone.name, format_utc(instant), horizon)
    return check


def fixed(value):
    return lambda rng: value


def table_zone(rng):
    return rng.choice(ZONE_LIST[1:])


def any_zone(rng):
    return rng.choice(ZONE_LIST)


# rule strings ---------------------------------------------------------------

def gen_name(rng):
    if rng.random() < 0.3:
        return "<" + "".join(rng.choice("+-0123456789ABZ") for _ in range(rng.randint(3, 5))) + ">"
    return "".join(rng.choice("ABCDEFGHXYZabcxyz") for _ in range(rng.randint(3, 5)))


def gen_offset(rng):
    sign = rng.choice(["", "", "+", "-"])
    hours = rng.randint(0, 14)
    text = sign + (("%02d" % hours) if rng.random() < 0.3 else str(hours))
    if rng.random() < 0.4:
        text += ":" + rng.choice(["00", "30", "45", "15"])
        if rng.random() < 0.3:
            text += ":00"
    return text


def gen_date(rng):
    kind = rng.random()
    if kind < 0.6:
        return "M%d.%d.%d" % (rng.randint(1, 12), rng.randint(1, 5), rng.randint(0, 6))
    if kind < 0.8:
        return "J%d" % rng.randint(1, 365)
    return "%d" % rng.randint(0, 365)


def gen_time(rng):
    if rng.random() < 0.3:
        return ""
    sign = rng.choice(["", "", "", "+", "-"])
    hours = rng.choice([0, 1, 2, 3, 23, 24, 25, 26, 47, 100, 167, rng.randint(0, 167)])
    text = "/" + sign + str(hours)
    if rng.random() < 0.3:
        text += ":" + rng.choice(["00", "30", "59"])
    return text


def gen_rule(rng):
    std = gen_name(rng) + gen_offset(rng)
    if rng.random() < 0.15:
        return std
    dst = gen_name(rng) + (gen_offset(rng) if rng.random() < 0.4 else "")
    return std + dst + "," + gen_date(rng) + gen_time(rng) + "," + gen_date(rng) + gen_time(rng)


def gen_bad_rule(rng):
    text = gen_rule(rng)
    for _ in range(rng.choice([1, 1, 2])):
        pos = rng.randrange(len(text) + 1)
        action = rng.random()
        char = rng.choice(list(",/.:<>JM+-9087x ") + ["", "00", "168", "25"])
        if action < 0.35:
            text = text[:pos] + char + text[pos:]
        elif action < 0.7:
            text = text[:pos] + char + text[pos + 1:]
        else:
            text = text[:pos]
    return text


def tz_outcome_impl(text):
    try:
        zone = tz(text)
    except ZoneError as exc:
        return ("error", str(exc))
    return ("ok", zone.initial, tuple(tuple(change) for change in zone.changes))


def tz_outcome_oracle(text):
    try:
        initial, changes = oracle.tz_timeline(text)
    except oracle.OracleError as exc:
        return ("error", str(exc))
    return ("ok", initial, tuple(changes))


def tz_parse_case(generate, samples):
    def check(rng):
        for _ in range(samples):
            text = generate(rng)
            assert tz_outcome_impl(text) == tz_outcome_oracle(text), text
    return check


def tz_cron_case(backward, samples):
    def check(rng):
        done = 0
        while done < samples:
            text = gen_rule(rng)
            try:
                initial, changes = oracle.tz_timeline(text)
            except oracle.OracleError:
                continue
            done += 1
            zone = tz(text)
            instant = (rng.choice(changes)[0] if changes and rng.random() < 0.85 else anywhere(rng)) + rng.randrange(-86400, 86400)
            expr = gen_mixed(rng)
            expected = oracle.outcome(expr, instant, initial, changes, 1830, 3, backward)
            assert implementation(expr, instant, zone, 1830, 3, backward) == expected, (text, expr, format_utc(instant))
    return check


def count_case(generate, zone_of, instant_of, span_of, samples):
    def check(rng):
        for _ in range(samples):
            expr, zone, start = generate(rng), zone_of(rng), instant_of(rng)
            end = start + span_of(rng)
            try:
                spec = oracle.parse(expr)
            except oracle.OracleError:
                continue
            expected = oracle.run(oracle.count_between, spec, start, end, zone.initial, zone.changes)
            try:
                actual = ("ok", cron()(expr).count_between(start, end, zone))
            except cron_error() as exc:
                actual = ("error", str(exc))
            assert actual == expected, (expr, zone.name, format_utc(start), end - start)
    return check


def nth_case(generate, zone_of, instant_of, n_of, horizon_of, samples):
    def check(rng):
        for _ in range(samples):
            expr, zone, start, n, horizon = generate(rng), zone_of(rng), instant_of(rng), n_of(rng), horizon_of(rng)
            try:
                spec = oracle.parse(expr)
            except oracle.OracleError:
                continue
            expected = oracle.run(oracle.nth_after, spec, start, n, zone.initial, zone.changes)
            try:
                actual = ("ok", cron()(expr, horizon).nth_after(start, n, zone))
            except cron_error() as exc:
                actual = ("error", str(exc))
            assert actual == expected, (expr, zone.name, format_utc(start), n)
    return check


def short_span(rng):
    return rng.choice([0, 1, 59, 60, 61, 3600, 5400]) if rng.random() < 0.3 else rng.randrange(-3600, 3 * 86400)


CASES = {
    # cron syntax and next fire
    "next_numeric_and_names": forward_case(gen_names_or_numeric, fixed(UTC), anywhere, 400, fixed(1830)),
    "next_day_specials": forward_case(gen_day_specials, fixed(UTC), anywhere, 400, fixed(1830)),
    "next_dom_dow_combination": forward_case(gen_domdow, fixed(UTC), anywhere, 400, fixed(1830)),
    "next_zone_changes": forward_case(gen_mixed, table_zone, near_transition, 500, fixed(1830)),
    "next_malformed_and_macros": forward_case(gen_errors_or_macros, any_zone, anywhere, 1000, fixed(1830)),
    "next_horizon": forward_case(gen_sparse, any_zone, anywhere, 300, lambda rng: rng.randrange(1, 400)),
    # earlier fires
    "prev_numeric_and_names": forward_case(gen_names_or_numeric, fixed(UTC), anywhere, 400, fixed(1830), True),
    "prev_day_specials_and_combination": forward_case(
        lambda rng: gen_day_specials(rng) if rng.random() < 0.5 else gen_domdow(rng), fixed(UTC), anywhere, 400, fixed(1830), True),
    "prev_zone_changes": forward_case(gen_mixed, table_zone, near_transition, 600, fixed(1830), True),
    "prev_horizon": forward_case(gen_sparse, any_zone, anywhere, 300, lambda rng: rng.randrange(1, 400), True),
    # counts and n-th fire
    "count_zone_changes": count_case(gen_numeric, table_zone, near_transition, short_span, 400),
    "count_mixed_spans": count_case(gen_mixed, any_zone, anywhere, lambda rng: rng.randrange(-86400, 40 * 86400), 200),
    "nth_zone_changes": nth_case(gen_mixed, table_zone, near_transition, lambda rng: rng.randint(-1, 40), lambda rng: rng.randint(1, 3), 400),
    "nth_sparse": nth_case(gen_sparse, any_zone, anywhere, lambda rng: rng.randint(1, 4), lambda rng: rng.randint(1, 60), 300),
    # rule zones
    "tz_valid_rules": tz_parse_case(gen_rule, 500),
    "tz_malformed_rules": tz_parse_case(gen_bad_rule, 1000),
    "tz_next": tz_cron_case(False, 250),
    "tz_prev": tz_cron_case(True, 250),
}


@pytest.mark.parametrize("name", sorted(CASES))
def test_conformance(name):
    CASES[name](random.Random("cronq-zq-" + name))
