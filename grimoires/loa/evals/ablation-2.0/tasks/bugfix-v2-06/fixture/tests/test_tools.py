import pytest

from semrange import (InvalidIncrement, LockError, check_lock, dump_lock,
                      filter_satisfying, format_report, inc, max_satisfying,
                      min_satisfying, parse_lock, resolve)


def test_max_and_min_satisfying():
    items = ["1.0.0", "1.4.0", "2.0.0", "1.2.0"]
    assert max_satisfying(items, "^1.0.0") == "1.4.0"
    assert min_satisfying(items, "^1.0.0") == "1.0.0"
    assert max_satisfying(items, "^3.0.0") is None


def test_filter_keeps_input_order():
    items = ["1.4.0", "2.0.0", "1.0.0"]
    assert filter_satisfying(items, "1.x") == ["1.4.0", "1.0.0"]


def test_release_increments():
    assert inc("1.2.3", "major") == "2.0.0"
    assert inc("1.2.3", "minor") == "1.3.0"
    assert inc("1.2.3", "patch") == "1.2.4"


def test_pre_increments():
    assert inc("1.2.3", "premajor", "beta") == "2.0.0-beta.0"
    assert inc("1.2.3", "prepatch") == "1.2.4-0"
    assert inc("1.2.3-alpha.1", "prerelease") == "1.2.3-alpha.2"


def test_unknown_increment():
    with pytest.raises(InvalidIncrement) as e:
        inc("1.2.3", "huge")
    assert str(e.value) == "unknown increment: 'huge'"


def test_resolve_picks_highest():
    picked = resolve({"a": "^1.0.0", "b": "^9.0.0"},
                     {"a": ["1.0.0", "1.1.0"], "b": ["1.0.0"]})
    assert picked == {"a": "1.1.0", "b": None}


def test_format_report():
    text = format_report({"b": "~1.2.0", "a": "*"},
                         {"a": ["0.1.0"], "b": ["1.2.9", "1.3.0"]})
    assert text == "a * -> 0.1.0\nb ~1.2.0 -> 1.2.9\n"


def test_lock_round_trip():
    text = "# deps\nalpha = 1.0.0\nbeta = 2.1.0-rc.1\n"
    lock = parse_lock(text)
    assert lock == {"alpha": "1.0.0", "beta": "2.1.0-rc.1"}
    assert dump_lock(lock) == "alpha = 1.0.0\nbeta = 2.1.0-rc.1\n"


def test_lock_errors():
    with pytest.raises(LockError) as e:
        parse_lock("a = 1.0.0\na = 1.0.1\n")
    assert str(e.value) == "line 2: duplicate name a"
    with pytest.raises(LockError) as e:
        parse_lock("a 1.0.0\n")
    assert str(e.value) == "line 1: expected name = version"


def test_check_lock():
    problems = check_lock({"a": "^1.0.0", "b": "^2.0.0"},
                          {"a": "2.0.0", "c": "1.0.0"})
    assert problems == ["a: 2.0.0 is outside ^1.0.0", "b: not locked",
                        "c: not required"]


def test_index_answers_like_the_list_functions():
    from semrange import VersionIndex
    items = ["1.0.0", "1.4.0", "2.0.0", "1.2.0", "0.9.0"]
    ix = VersionIndex(items)
    assert ix.max_satisfying("^1.0.0") == "1.4.0"
    assert ix.min_satisfying("^1.0.0") == "1.0.0"
    assert ix.filter_satisfying("1.x") == ["1.0.0", "1.4.0", "1.2.0"]
    assert ix.max_satisfying("^3.0.0") is None


def test_index_counts_valid_entries():
    from semrange import VersionIndex
    assert len(VersionIndex(["1.0.0", "junk", "2.0.0"])) == 2


def test_index_inclusive_bounds():
    from semrange import VersionIndex
    ix = VersionIndex(["1.0.0", "1.5.0", "2.0.0"])
    assert ix.filter_satisfying(">=1.0.0 <=2.0.0") == ["1.0.0", "1.5.0", "2.0.0"]
    assert ix.max_satisfying("<=1.5.0") == "1.5.0"
