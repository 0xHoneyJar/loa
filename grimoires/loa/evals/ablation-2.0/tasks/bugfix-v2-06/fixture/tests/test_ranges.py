import pytest

from semrange import InvalidRange, Range, satisfies


def test_exact_and_primitive_comparators():
    assert str(Range("1.2.3")) == "1.2.3"
    assert str(Range(">=1.2.3 <2.0.0")) == ">=1.2.3 <2.0.0"
    assert satisfies("1.5.0", ">=1.2.3 <2.0.0")
    assert not satisfies("2.0.0", ">=1.2.3 <2.0.0")


def test_caret_ranges():
    assert str(Range("^1.2.3")) == ">=1.2.3 <2.0.0-0"
    assert str(Range("^0.2.3")) == ">=0.2.3 <0.3.0-0"
    assert satisfies("1.9.9", "^1.2.3")
    assert not satisfies("2.0.0", "^1.2.3")


def test_tilde_ranges():
    assert str(Range("~1.2.3")) == ">=1.2.3 <1.3.0-0"
    assert str(Range("~1.2")) == ">=1.2.0 <1.3.0-0"
    assert not satisfies("1.3.0", "~1.2.3")


def test_x_ranges():
    assert str(Range("1.2.x")) == ">=1.2.0 <1.3.0-0"
    assert str(Range("1")) == ">=1.0.0 <2.0.0-0"
    assert str(Range("*")) == ">=0.0.0"


def test_hyphen_range_full_ends():
    assert str(Range("1.2.3 - 2.3.4")) == ">=1.2.3 <=2.3.4"
    assert satisfies("2.3.4", "1.2.3 - 2.3.4")


def test_or_of_sets():
    r = Range("^1.0.0 || ^3.0.0")
    assert str(r) == ">=1.0.0 <2.0.0-0 || >=3.0.0 <4.0.0-0"
    assert r.test("3.1.0")
    assert not r.test("2.1.0")


def test_full_partial_comparators():
    assert str(Range(">=1.2")) == ">=1.2.0"
    assert str(Range("<1.2")) == "<1.2.0-0"


def test_prerelease_admitted_through_its_own_comparator():
    assert satisfies("1.2.3-beta", ">=1.2.3-alpha <1.3.0")
    assert not satisfies("1.2.4-beta", ">=1.2.3-alpha <1.3.0")


def test_release_range_excludes_prereleases():
    assert not satisfies("1.5.0-rc.1", "^1.0.0")


def test_invalid_ranges_raise():
    for text in ["1.2.3.4", "a", ">=1.y", "1 - 2 - 3"]:
        with pytest.raises(InvalidRange):
            Range(text)


def test_invalid_range_message():
    with pytest.raises(InvalidRange) as e:
        Range("~>1")
    assert str(e.value) == "invalid range: '~>1'"
