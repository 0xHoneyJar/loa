import io
from datetime import datetime, timedelta, timezone

import pytest

from cronzone import CronError, Job, Schedule, catch_up, upcoming
from cronzone.cli import main

UTC = timezone.utc


def at(*args):
    return datetime(*args, tzinfo=UTC)


def test_next_fire_utc():
    s = Schedule("0 9 * * MON-FRI")
    assert s.next_fire(at(2026, 3, 6, 9, 0)) == at(2026, 3, 9, 9, 0)
    assert s.next_fire(at(2026, 3, 9, 8, 59, 30)) == at(2026, 3, 9, 9, 0)


def test_next_fires_every_quarter_hour():
    s = Schedule("*/15 * * * *")
    assert s.next_fires(at(2026, 5, 1, 10, 7), 3) == [at(2026, 5, 1, 10, 15), at(2026, 5, 1, 10, 30),
                                                    at(2026, 5, 1, 10, 45)]


def test_next_fire_in_a_zone():
    s = Schedule("0 9 * * *", "west")
    assert s.next_fire(at(2026, 7, 1, 0, 0)) == at(2026, 7, 1, 13, 0)
    assert s.next_fire(at(2026, 12, 1, 0, 0)) == at(2026, 12, 1, 14, 0)


def test_skipped_wall_time_does_not_fire():
    s = Schedule("30 2 * * *", "north")
    assert s.next_fire(at(2026, 3, 28, 12, 0)) == at(2026, 3, 30, 0, 30)


def test_prev_fire():
    s = Schedule("0 12 * * *")
    assert s.prev_fire(at(2026, 5, 2, 11, 0)) == at(2026, 5, 1, 12, 0)


def test_fires_between_is_half_open():
    s = Schedule("0 * * * *")
    assert s.fires_between(at(2026, 5, 1, 10, 30), at(2026, 5, 1, 13, 0)) == [at(2026, 5, 1, 11, 0),
                                                                            at(2026, 5, 1, 12, 0)]


def test_never_fires():
    with pytest.raises(CronError) as info:
        Schedule("0 0 30 2 *").next_fire(at(2026, 1, 1))
    assert str(info.value) == "no fire time within 8 years"


def test_naive_datetime_refused():
    with pytest.raises(ValueError) as info:
        Schedule("* * * * *").next_fire(datetime(2026, 1, 1))
    assert str(info.value).startswith("expected a timezone-aware datetime, got ")


def test_upcoming_merges_jobs():
    jobs = [Job.create("a", "0 * * * *"), Job.create("b", "30 * * * *")]
    assert upcoming(jobs, at(2026, 5, 1, 10, 10), 3) == [(at(2026, 5, 1, 10, 30), "b"), (at(2026, 5, 1, 11, 0), "a"),
                                                       (at(2026, 5, 1, 11, 30), "b")]


def test_catch_up_policies():
    job = Job.create("j", "0 * * * *")
    assert catch_up(job, at(2026, 5, 1, 9, 30), at(2026, 5, 1, 11, 30), "latest") == [at(2026, 5, 1, 11, 0)]
    assert catch_up(job, at(2026, 5, 1, 9, 30), at(2026, 5, 1, 11, 30), "skip") == []


def test_matches():
    s = Schedule("0 3 * * *", "north")
    assert s.matches(at(2026, 6, 1, 1, 0))
    assert not s.matches(at(2026, 6, 1, 3, 0))


def test_cli_next():
    out, err = io.StringIO(), io.StringIO()
    assert main(["next", "0 9 * * *", "north", "2026-06-01T00:00+00:00", "2"], out, err) == 0
    assert out.getvalue() == "2026-06-01T07:00Z 2026-06-01T09:00+02:00\n2026-06-02T07:00Z 2026-06-02T09:00+02:00\n"


def test_cli_errors():
    out, err = io.StringIO(), io.StringIO()
    assert main(["next", "0 9 * *", "north", "2026-06-01T00:00+00:00"], out, err) == 1
    assert err.getvalue() == "error: expected 5 fields, got 4\n"
    assert main(["help"], out, io.StringIO()) == 2
