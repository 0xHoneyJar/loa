from datetime import datetime, timezone

import pytest

from cronzone import CronError, ZONES, get_zone

UTC = timezone.utc


def test_fixed_zones():
    assert get_zone("utc").offset(datetime(2026, 7, 1, tzinfo=UTC)) == 0
    assert get_zone("plus0530").wall(datetime(2026, 7, 1, 12, 0, tzinfo=UTC)) == datetime(2026, 7, 1, 17, 30)
    assert get_zone("utc").transitions(2026) == []


def test_north_offsets():
    north = get_zone("north")
    assert north.offset(datetime(2026, 1, 15, tzinfo=UTC)) == 60
    assert north.offset(datetime(2026, 7, 15, tzinfo=UTC)) == 120
    assert north.offset(datetime(2026, 3, 29, 0, 59, tzinfo=UTC)) == 60
    assert north.offset(datetime(2026, 3, 29, 1, 0, tzinfo=UTC)) == 120


def test_west_transitions():
    west = get_zone("west")
    assert west.transitions(2026) == [(datetime(2026, 3, 8, 7, 0, tzinfo=UTC), -240),
                                      (datetime(2026, 11, 1, 6, 0, tzinfo=UTC), -300)]


def test_instants_of_an_ordinary_wall_time():
    assert get_zone("north").instants(datetime(2026, 6, 1, 12, 0)) == [datetime(2026, 6, 1, 10, 0, tzinfo=UTC)]


def test_instants_in_a_gap():
    assert get_zone("north").instants(datetime(2026, 3, 29, 2, 30)) == []


def test_unknown_zone():
    with pytest.raises(CronError) as info:
        get_zone("mars")
    assert str(info.value) == "unknown zone: 'mars'"
    assert sorted(ZONES) == ["midnight", "north", "plus0530", "south", "utc", "west"]
