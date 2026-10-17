import pytest

import semverkit
from semverkit import InvalidRange


@pytest.mark.parametrize("text,want", [
    ("^1.2.3", ">=1.2.3 <2.0.0-0"),
    ("^0.2.3", ">=0.2.3 <0.3.0-0"),
    ("^0.0.3", ">=0.0.3 <0.0.4-0"),
    ("^0.0", ">=0.0.0 <0.1.0-0"),
    ("~1.2.3", ">=1.2.3 <1.3.0-0"),
    ("~>1", ">=1.0.0 <2.0.0-0"),
    ("1.x", ">=1.0.0 <2.0.0-0"),
    ("*", ">=0.0.0"),
    ("", ">=0.0.0"),
    (">1.2", ">=1.3.0"),
    ("<=1.2", "<1.3.0-0"),
    ("<1", "<1.0.0-0"),
    ("1.2 - 2", ">=1.2.0 <3.0.0-0"),
    ("1.2.3 - 2.3.4", ">=1.2.3 <=2.3.4"),
    (">= 1.0.0 < 2 || =3.1.4", ">=1.0.0 <2.0.0-0 || 3.1.4"),
])
def test_normalize(text, want):
    assert semverkit.normalize_range(text) == want


@pytest.mark.parametrize("text", ["1.2.x-pre", "!1.0.0", ">=", "1.2.3-01", "1 -2"])
def test_bad_ranges(text):
    with pytest.raises(InvalidRange, match=r"^invalid comparator: "):
        semverkit.normalize_range(text)


def test_range_errors_for_non_strings_and_length():
    with pytest.raises(InvalidRange, match=r"^not a string: None$"):
        semverkit.normalize_range(None)
    with pytest.raises(InvalidRange, match=r"^range too long$"):
        semverkit.normalize_range("1" * 1025)


def test_satisfies_basic_and_union():
    assert semverkit.satisfies("1.5.0", "^1.2.3")
    assert not semverkit.satisfies("2.0.0", "^1.2.3")
    assert semverkit.satisfies("3.1.4", "<1 || 3.x")


def test_prerelease_needs_a_matching_tuple():
    assert semverkit.satisfies("1.2.3-beta.2", ">=1.2.3-beta.1 <2")
    assert not semverkit.satisfies("1.2.4-beta.2", ">=1.2.3-beta.1 <2")
    assert semverkit.satisfies("1.2.4-beta.2", ">=1.2.3-beta.1 <2", include_prerelease=True)


def test_satisfies_bad_version_is_false_but_bad_range_raises():
    assert semverkit.satisfies("garbage", "*") is False
    with pytest.raises(InvalidRange):
        semverkit.satisfies("1.0.0", ">>1")


def test_max_and_min_satisfying():
    texts = ["1.2.3", "v1.4.0", "nope", "1.4.0", "2.0.0", "1.0.0-rc.1"]
    assert semverkit.max_satisfying(texts, "^1") == "v1.4.0"
    assert semverkit.min_satisfying(texts, "^1") == "1.2.3"
    assert semverkit.max_satisfying(texts, ">=3") is None
    assert semverkit.min_satisfying(texts, "*", include_prerelease=True) == "1.0.0-rc.1"


def test_render_table():
    out = semverkit.render_table(["1.2.3", "2.0.0-rc.1", "bad", "v1.0.0"], ["^1", ">=2.0.0-0"])
    assert out.splitlines() == [
        "version     ^1   >=2.0.0-0",
        "----------  ---  ---------",
        "v1.0.0      yes  no",
        "1.2.3       yes  no",
        "2.0.0-rc.1  no   yes",
        "invalid: bad",
    ]


def test_render_table_empty():
    assert semverkit.render_table([], ["*"]) == "version  *\n-------  -"
