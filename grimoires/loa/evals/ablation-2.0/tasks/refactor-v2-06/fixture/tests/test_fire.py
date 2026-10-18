import datetime as dt

import pytest

import cronplan


def at(*parts):
    return dt.datetime(*parts)


def test_next_fire_is_strictly_after():
    assert cronplan.next_fire("30 9 * * *", at(2026, 10, 17, 9, 30)) == at(2026, 10, 18, 9, 30)
    assert cronplan.next_fire("30 9 * * *", at(2026, 10, 17, 9, 29, 59)) == at(2026, 10, 17, 9, 30)


def test_next_fire_crosses_the_year():
    assert cronplan.next_fire("0 0 1 1 *", at(2026, 12, 31, 23, 59)) == at(2027, 1, 1, 0, 0)


def test_day_fields_are_ored_when_both_are_restricted():
    times = cronplan.fires("0 0 13 * 5", at(2026, 2, 1), 4)
    assert times == [at(2026, 2, 6), at(2026, 2, 13), at(2026, 2, 20), at(2026, 2, 27)]


def test_a_starred_step_makes_the_day_fields_anded():
    times = cronplan.fires("0 0 */2 * 1", at(2026, 3, 1), 3)
    assert times == [at(2026, 3, 9), at(2026, 3, 23), at(2026, 4, 13)]


def test_last_day_and_offsets():
    assert cronplan.fires("0 0 L * *", at(2024, 1, 15), 3) == [at(2024, 1, 31), at(2024, 2, 29), at(2024, 3, 31)]
    assert cronplan.next_fire("0 0 L-1 2 *", at(2025, 1, 1)) == at(2025, 2, 27)


def test_nearest_weekday_stays_in_the_month():
    assert cronplan.next_fire("0 0 1W * *", at(2026, 7, 2)) == at(2026, 8, 3)
    assert cronplan.next_fire("0 0 31W * *", at(2026, 10, 1)) == at(2026, 10, 30)
    assert cronplan.next_fire("0 0 LW * *", at(2026, 5, 1)) == at(2026, 5, 29)


def test_nth_and_last_weekday():
    assert cronplan.next_fire("0 0 * * 1#2", at(2026, 10, 1)) == at(2026, 10, 12)
    assert cronplan.next_fire("0 0 * * 5L", at(2026, 10, 1)) == at(2026, 10, 30)


def test_impossible_schedule_gives_up():
    with pytest.raises(cronplan.SearchError, match=r"^no fire time within 5 years$"):
        cronplan.next_fire("0 0 30 2 *", at(2026, 1, 1))


def test_arguments_are_checked():
    with pytest.raises(cronplan.ArgumentError, match=r"^datetime must be naive$"):
        cronplan.next_fire("* * * * *", dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc))
    with pytest.raises(cronplan.ArgumentError, match=r"^count must be 1-1000, got 0$"):
        cronplan.fires("* * * * *", at(2026, 1, 1), 0)
    with pytest.raises(cronplan.ArgumentError, match=r"^not a datetime: '2026'$"):
        cronplan.matches("* * * * *", "2026")


def test_matches():
    assert cronplan.matches("*/5 * * * *", at(2026, 1, 1, 0, 10))
    assert not cronplan.matches("*/5 * * * *", at(2026, 1, 1, 0, 10, 1))
    assert not cronplan.matches("0 0 * 2 *", at(2026, 1, 1))


def test_month_report():
    assert cronplan.month_report("0 9,17 * * 6", 2026, 10).splitlines() == [
        "2026-10-03  2", "2026-10-10  2", "2026-10-17  2", "2026-10-24  2", "2026-10-31  2", "total  10"]
    with pytest.raises(cronplan.ArgumentError, match=r"^month must be 1-12, got 13$"):
        cronplan.month_report("* * * * *", 2026, 13)
