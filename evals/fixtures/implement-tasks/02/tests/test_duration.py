import pytest
from timekit.duration import parse_duration


def test_seconds():
    assert parse_duration("90s") == 90


def test_minutes_and_hours():
    assert parse_duration("5m") == 300
    assert parse_duration("2h") == 7200


def test_invalid():
    with pytest.raises(ValueError):
        parse_duration("ten")
    with pytest.raises(ValueError):
        parse_duration("")
