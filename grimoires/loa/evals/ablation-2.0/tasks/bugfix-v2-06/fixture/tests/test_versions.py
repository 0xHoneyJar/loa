import pytest

from semrange import InvalidVersion, Version, compare, parse, sort_versions, valid


def test_parse_full_version():
    v = parse("1.2.3-rc.1+build.5")
    assert (v.major, v.minor, v.patch) == (1, 2, 3)
    assert v.prerelease == ("rc", "1")
    assert v.build == ("build", "5")
    assert str(v) == "1.2.3-rc.1+build.5"


def test_parse_strips_one_leading_v():
    assert str(parse("v2.0.0")) == "2.0.0"


def test_invalid_versions_raise():
    for text in ["1.2", "a.b.c", "1.2.3.4", "1.2.x", ""]:
        with pytest.raises(InvalidVersion):
            parse(text)


def test_invalid_version_message():
    with pytest.raises(InvalidVersion) as e:
        parse("1.x.0")
    assert str(e.value) == "invalid version: '1.x.0'"


def test_valid_returns_canonical_or_none():
    assert valid(" v1.0.0 ") == "1.0.0"
    assert valid("nope") is None


def test_core_numbers_compare_numerically():
    assert compare("1.10.0", "1.9.0") == 1
    assert compare("2.0.0", "10.0.0") == -1
    assert compare("1.2.3", "1.2.3") == 0


def test_prerelease_is_lower_than_release():
    assert compare("1.0.0-alpha", "1.0.0") == -1
    assert compare("1.0.0", "1.0.0-rc.1") == 1


def test_prerelease_identifiers_compare():
    assert compare("1.0.0-alpha", "1.0.0-beta") == -1
    assert compare("1.0.0-1", "1.0.0-2") == -1
    assert compare("1.0.0-1", "1.0.0-alpha") == -1


def test_version_objects_order():
    assert parse("1.0.0") < parse("1.0.1")
    assert parse("2.0.0") > parse("1.9.9")
    assert parse("1.0.0") == Version(1, 0, 0)


def test_sort_versions():
    items = ["1.10.0", "1.2.0", "1.2.0-beta", "0.9.0"]
    assert [str(v) for v in sort_versions(items)] == [
        "0.9.0", "1.2.0-beta", "1.2.0", "1.10.0"]
    assert [str(v) for v in sort_versions(items, reverse=True)] == [
        "1.10.0", "1.2.0", "1.2.0-beta", "0.9.0"]
