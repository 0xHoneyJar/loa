import pytest

import semverkit
from semverkit import InvalidRange, InvalidVersion, Version


def test_parse_fields():
    v = semverkit.parse("1.2.3-beta.11+build.7")
    assert (v.major, v.minor, v.patch) == (1, 2, 3)
    assert v.prerelease == ("beta", 11)
    assert v.build == ("build", "7")


def test_parse_accepts_prefixes_and_whitespace():
    assert semverkit.parse(" =v1.0.0 ") == Version(1, 0, 0)
    assert semverkit.valid("V2.3.4") == "2.3.4"


@pytest.mark.parametrize("text", ["1.2", "01.2.3", "1.2.3-01", "1.2.3-", "1.2.3+", "", "a.b.c", "1.2.3.4"])
def test_parse_rejects(text):
    with pytest.raises(InvalidVersion, match=r"^invalid version: "):
        semverkit.parse(text)


def test_parse_rejects_non_strings_and_long_input():
    with pytest.raises(InvalidVersion, match=r"^not a string: 5$"):
        semverkit.parse(5)
    with pytest.raises(InvalidVersion, match=r"^version too long$"):
        semverkit.parse("1." * 200 + "0")


def test_errors_are_value_errors():
    assert issubclass(InvalidVersion, ValueError) and issubclass(InvalidRange, ValueError)


def test_valid_returns_none_on_garbage():
    assert semverkit.valid("nope") is None
    assert semverkit.valid(None) is None


def test_compare_prerelease_precedence():
    chain = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2",
             "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"]
    for low, high in zip(chain, chain[1:]):
        assert semverkit.compare(low, high) == -1
        assert semverkit.compare(high, low) == 1


def test_compare_ignores_build():
    assert semverkit.compare("1.0.0+a", "1.0.0+b") == 0


def test_sort_keeps_spelling_and_orders_ties_by_canonical_text():
    assert semverkit.sort(["v1.0.0", "1.0.0-rc.1", "0.9.0", "1.0.0+b", "=1.0.0"]) == [
        "0.9.0", "1.0.0-rc.1", "v1.0.0", "=1.0.0", "1.0.0+b"]


def test_sort_raises_on_a_bad_version():
    with pytest.raises(InvalidVersion):
        semverkit.sort(["1.0.0", "x"])


@pytest.mark.parametrize("text,part,ident,want", [
    ("1.2.3", "major", None, "2.0.0"),
    ("1.0.0-rc.1", "major", None, "1.0.0"),
    ("1.2.0-rc.1", "major", None, "2.0.0"),
    ("1.2.3", "minor", None, "1.3.0"),
    ("1.2.0-rc.1", "minor", None, "1.2.0"),
    ("1.2.3-rc.1", "patch", None, "1.2.3"),
    ("1.2.3+b", "patch", None, "1.2.4"),
    ("1.2.3", "prerelease", None, "1.2.4-0"),
    ("1.2.3", "prerelease", "beta", "1.2.4-beta.0"),
    ("1.2.4-beta.1", "prerelease", "beta", "1.2.4-beta.2"),
    ("1.2.4-beta.1", "prerelease", "rc", "1.2.4-rc.0"),
    ("1.2.4-beta", "prerelease", None, "1.2.4-beta.0"),
    ("1.2.4-rc.1", "release", None, "1.2.4"),
])
def test_bump(text, part, ident, want):
    assert semverkit.bump(text, part, ident) == want


def test_bump_errors():
    with pytest.raises(ValueError, match=r"^unknown part: 'huge'$"):
        semverkit.bump("1.0.0", "huge")
    with pytest.raises(ValueError, match=r"^identifier only applies to prerelease$"):
        semverkit.bump("1.0.0", "minor", "beta")
    with pytest.raises(ValueError, match=r"^invalid identifier: '12'$"):
        semverkit.bump("1.0.0", "prerelease", "12")
    with pytest.raises(ValueError, match=r"^already a release: '1.0.0\+b'$"):
        semverkit.bump("1.0.0+b", "release")
