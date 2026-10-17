"""Acceptance cases for the semrange specification.

Each hand-written case is a table crossing several rules of the brief.  The
conformance cases at the end draw deterministic samples (fixed seeds) from a
large part of the public surface and compare every answer with a reference
model of the brief; a single deviation anywhere in a case's scope fails it.
"""
import random
import time

import pytest

import semrange as S
from semrange import (InvalidIncrement, InvalidRange, InvalidVersion, Range,
                      VersionError, VersionIndex, compare, filter_satisfying,
                      inc, max_satisfying, min_satisfying, parse, satisfies,
                      sort_versions, valid)

import _oracle_semver as O


def impl(fn, *args, **kw):
    try:
        return ("ok", fn(*args, **kw))
    except VersionError as e:
        return ("err", type(e).__name__, str(e))


def check(rows):
    """rows: (context, got, want); the first mismatches, if any."""
    bad = [r for r in rows if r[1] != r[2]]
    assert bad[:5] == []


def rs(text):
    return impl(lambda: str(Range(text)))


# ----------------------------------------------------------- scenario tables
def test_version_validity_table():
    table = {
        "1.0.0-01": None, "1.0.0-alpha.007": None, "01.2.3": None,
        "1.02.3": None, "1.2.03": None, "-1.2.3": None, "1.2": None,
        "1.0.0-0a": "1.0.0-0a", "1.0.0+001.0002": "1.0.0+001.0002",
        "1.0.0-0+00": "1.0.0-0+00", "1.0.0-a..b": None, "1.0.0+": None,
        "1.0.0+a.": None, "v1.2.3": "1.2.3", "vv1.2.3": None, "V1.2.3": None,
        "=1.2.3": None, " \t1.2.3-rc.1+b \n": "1.2.3-rc.1+b",
        "10.200.3000": "10.200.3000", "0.0.0": "0.0.0",
    }
    check([(t, valid(t), w) for t, w in table.items()])
    for t in ["1.0.0-01", " 1.2 ", "01.0.0"]:
        check([(t, impl(parse, t), ("err", "InvalidVersion",
                                    f"invalid version: {t!r}"))])


def test_precedence_table():
    chain = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.2",
             "1.0.0-alpha.10", "1.0.0-alpha.beta", "1.0.0-beta",
             "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0",
             "1.0.1-0", "1.0.1-9", "1.0.1-10", "1.0.1-0a", "1.0.1", "1.10.0",
             "2.0.0"]
    rows = []
    for i, a in enumerate(chain):
        for j, b in enumerate(chain):
            rows.append(((a, b), compare(a, b), (i > j) - (i < j)))
    for a, b in [("1.0.0+a", "1.0.0+b"), ("1.0.0-rc.1+zzz", "1.0.0-rc.1"),
                 ("1.0.0-alpha.1.0", "1.0.0-alpha.1.0+q")]:
        rows.append(((a, b), compare(a, b), 0))
        rows.append(((a, b, "=="), parse(a) == parse(b), True))
        rows.append(((a, b, "hash"), hash(parse(a)) == hash(parse(b)), True))
    rows.append(("Beta<alpha", compare("1.0.0-Beta", "1.0.0-alpha"), -1))
    check(rows)


def test_sorting_table():
    items = ["1.0.0-rc.10", "2.0.0+z", "1.0.0+b", "1.0.0-rc.9", "1.0.0",
             "2.0.0+a", "1.0.0-rc", "1.0.0+a", "0.9.0", "1.0.0-rc.9+x"]
    up = ["0.9.0", "1.0.0-rc", "1.0.0-rc.9", "1.0.0-rc.9+x", "1.0.0-rc.10",
          "1.0.0+b", "1.0.0", "1.0.0+a", "2.0.0+z", "2.0.0+a"]
    down = ["2.0.0+z", "2.0.0+a", "1.0.0+b", "1.0.0", "1.0.0+a",
            "1.0.0-rc.10", "1.0.0-rc.9", "1.0.0-rc.9+x", "1.0.0-rc", "0.9.0"]
    check([("up", [str(v) for v in sort_versions(items)], up),
           ("down", [str(v) for v in sort_versions(items, reverse=True)], down)])


def test_caret_table():
    table = {
        "^1.2.3": ">=1.2.3 <2.0.0-0", "^0.2.3": ">=0.2.3 <0.3.0-0",
        "^0.0.3": ">=0.0.3 <0.0.4-0", "^0.0.3-beta": ">=0.0.3-beta <0.0.4-0",
        "^0.0": ">=0.0.0 <0.1.0-0", "^0.0.x": ">=0.0.0 <0.1.0-0",
        "^0": ">=0.0.0 <1.0.0-0", "^0.x": ">=0.0.0 <1.0.0-0",
        "^1.x": ">=1.0.0 <2.0.0-0", "^1.2": ">=1.2.0 <2.0.0-0",
        "^*": ">=0.0.0", "^0.0.0": ">=0.0.0 <0.0.1-0",
    }
    rows = [(r, rs(r), ("ok", w)) for r, w in table.items()]
    rows += [("0.0.4 in ^0.0.3", satisfies("0.0.4", "^0.0.3"), False),
             ("0.0.3 in ^0.0.3", satisfies("0.0.3", "^0.0.3"), True),
             ("0.0.4-0 in ^0.0.3", satisfies("0.0.4-0", "^0.0.3"), False)]
    check(rows)


def test_tilde_table():
    table = {"~1": ">=1.0.0 <2.0.0-0", "~0": ">=0.0.0 <1.0.0-0",
             "~1.x": ">=1.0.0 <2.0.0-0", "~1.2": ">=1.2.0 <1.3.0-0",
             "~1.2.3-beta.2": ">=1.2.3-beta.2 <1.3.0-0", "~x": ">=0.0.0"}
    rows = [(r, rs(r), ("ok", w)) for r, w in table.items()]
    for v, w in [("1.2.3-beta.4", True), ("1.2.3-beta.10", True),
                 ("1.2.3-beta.1", False), ("1.2.4-beta", False),
                 ("1.2.4", True), ("1.3.0-0", False)]:
        rows.append((v, satisfies(v, "~1.2.3-beta.2"), w))
    check(rows)


def test_partials_under_operators_table():
    table = {">1.2": ">=1.3.0", ">1": ">=2.0.0", ">=1.2": ">=1.2.0",
             ">=1": ">=1.0.0", "<1.2": "<1.2.0-0", "<1": "<1.0.0-0",
             "<=1.2": "<1.3.0-0", "<=1": "<2.0.0-0", "=1.2": ">=1.2.0 <1.3.0-0",
             "1.2": ">=1.2.0 <1.3.0-0", ">1.2 <=2": ">=1.3.0 <3.0.0-0"}
    rows = [(r, rs(r), ("ok", w)) for r, w in table.items()]
    rows += [("1.2.5 >1.2", satisfies("1.2.5", ">1.2"), False),
             ("1.2.5 <=1.2", satisfies("1.2.5", "<=1.2"), True),
             ("1.3.0-0 <=1.2", satisfies("1.3.0-0", "<=1.2"), False)]
    check(rows)


def test_wildcards_and_x_ranges_table():
    table = {"*": ("ok", ">=0.0.0"), "x": ("ok", ">=0.0.0"),
             ">=*": ("ok", ">=0.0.0"), "<=X": ("ok", ">=0.0.0"),
             "<*": ("ok", "<0.0.0-0"), ">x": ("ok", "<0.0.0-0"),
             "> x": ("ok", "<0.0.0-0"), "1.2.x": ("ok", ">=1.2.0 <1.3.0-0"),
             "1.X": ("ok", ">=1.0.0 <2.0.0-0"), "1.*.*": ("ok", ">=1.0.0 <2.0.0-0"),
             "v1.2.3+b.7": ("ok", "1.2.3")}
    for bad in ["1.x.3", "x.1", "*.1.2", "1.x.0-rc", "1.2-beta"]:
        table[bad] = ("err", "InvalidRange", f"invalid range: {bad!r}")
    check([(r, rs(r), w) for r, w in table.items()])


def test_hyphen_table():
    table = {"1.2 - 2.3": ">=1.2.0 <2.4.0-0", "1 - 2": ">=1.0.0 <3.0.0-0",
             "1.2.3 - 2.x": ">=1.2.3 <3.0.0-0", "1.2.3 - *": ">=1.2.3",
             "* - 1.2.3": ">=0.0.0 <=1.2.3", "1.2.3 - 2.3.4": ">=1.2.3 <=2.3.4",
             "1.2.3-rc.1 - 2.3.4-beta": ">=1.2.3-rc.1 <=2.3.4-beta"}
    rows = [(r, rs(r), ("ok", w)) for r, w in table.items()]
    for v, r, w in [("2.3.9", "1.2 - 2.3", True), ("2.4.0", "1.2 - 2.3", False),
                    ("2.3.4-alpha", "1.2.3 - 2.3.4-beta", True),
                    ("2.3.4", "1.2.3 - 2.3.4-beta", False),
                    ("2.9.9", "1 - 2", True)]:
        rows.append(((v, r), satisfies(v, r), w))
    check(rows)


def test_prerelease_rule_table():
    r = ">=1.2.3-alpha <1.2.3-beta || >=1.0.0"
    table = [("1.2.3-alpha.5", r, True), ("1.2.3-rc", r, False),
             ("1.2.3", r, True), ("3.0.0", r, True),
             ("1.2.3-beta", ">=1.2.3-alpha", True),
             ("1.2.4-alpha", ">=1.2.3-alpha", False),
             ("2.0.0", ">=1.2.3-alpha", True),
             ("1.2.4-beta", "^1.2.3-alpha", False),
             ("1.0.0-rc", "*", False), ("1.0.0-rc", "", False),
             ("1.0.0", "", True), ("1.0.0-rc", "1.x", False),
             ("1.0.0-rc", "1.0.0-rc", True), ("1.0.0-rc.2", "1.0.0-rc.1 || 1.x", False)]
    check([((v, rr), satisfies(v, rr), w) for v, rr, w in table])


def test_whitespace_and_empty_sets_table():
    table = {">= 1.2.3": ">=1.2.3", "~ 1.2": ">=1.2.0 <1.3.0-0",
             "^\t0.1": ">=0.1.0 <0.2.0-0", "> 1.2  <=\t2": ">=1.3.0 <3.0.0-0",
             "": ">=0.0.0", "   ": ">=0.0.0",
             "1.x ||": ">=1.0.0 <2.0.0-0 || >=0.0.0",
             "||": ">=0.0.0 || >=0.0.0",
             "1.x||2.x": ">=1.0.0 <2.0.0-0 || >=2.0.0 <3.0.0-0",
             "^1.2\t||\t~0.3": ">=1.2.0 <2.0.0-0 || >=0.3.0 <0.4.0-0"}
    rows = [(r, rs(r), ("ok", w)) for r, w in table.items()]
    for bad in [">=", "1.2.3 <", ">= <1", "~ ^1"]:
        rows.append((bad, rs(bad), ("err", "InvalidRange", f"invalid range: {bad!r}")))
    rows.append(("7.0.0 in 1.x ||", satisfies("7.0.0", "1.x ||"), True))
    check(rows)


def test_malformed_ranges_table():
    rows = []
    for text in ["1.2.3 -2", "1 - 2 - 3", "- 1", "1 -", "~>1", "a.b",
                 "1.2.3 | 2", "==1", "1.2.3-01", "1..2", ">=1 - 2"]:
        try:
            Range(text)
            got = "accepted"
        except InvalidRange as e:
            got = (str(e), isinstance(e, VersionError), isinstance(e, ValueError))
        rows.append((text, got, (f"invalid range: {text!r}", True, True)))
    for text in ["> 1", "1.2.3 - 2", "1 2", "<= 1.x"]:
        rows.append((text, rs(text)[0], "ok"))
    check(rows)


def test_index_ties_table():
    items = ["1.2.3+b", "1.0.0", "1.2.3+a", "1.2.3", "1.0.0+c", "0.9.0",
             "1.2.3-rc.1", "1.2.3-rc.1+z"]
    ix = VersionIndex(items)
    table = [("^1", ix.max_satisfying, "1.2.3+b"),
             ("^1", ix.min_satisfying, "1.0.0"),
             (">=1.2.3-rc.1", ix.min_satisfying, "1.2.3-rc.1"),
             (">=1.2.3-rc.1 <1.2.3", ix.max_satisfying, "1.2.3-rc.1"),
             ("<1.2.3", ix.max_satisfying, "1.0.0"),
             ("*", ix.max_satisfying, "1.2.3+b")]
    rows = [((r, f.__name__), f(r), w) for r, f, w in table]
    rows.append(("module max", max_satisfying(items, "1.x"), "1.2.3+b"))
    rows.append(("module min", min_satisfying(list(reversed(items)), "1.x"), "1.0.0+c"))
    rows.append(("v kept", max_satisfying(["v1.2.3", "1.2.3"], "1.x"), "v1.2.3"))
    check(rows)


def test_index_exclusive_bounds_table():
    items = ["1.2.2", "1.2.3", "1.2.3+b", "1.2.4", "2.0.0-0", "2.0.0-0+q",
             "2.0.0", "1.9.9"]
    ix = VersionIndex(items)
    table = [("<1.2.3", "filter", ["1.2.2"]),
             (">1.2.3", "filter", ["1.2.4", "2.0.0", "1.9.9"]),
             ("<=1.2.3", "filter", ["1.2.2", "1.2.3", "1.2.3+b"]),
             (">=1.2.3", "min", "1.2.3"), (">1.2.3", "min", "1.2.4"),
             (">1.2.2", "min", "1.2.3"), ("<2.0.0-0", "max", "1.9.9"),
             ("^1", "max", "1.9.9"), (">1.2.3 <2.0.0", "max", "1.9.9"),
             (">2.0.0-0", "min", "2.0.0"), (">1.2.0 <1.2.3", "max", "1.2.2"),
             (">1.2.2 <1.2.4", "filter", ["1.2.3", "1.2.3+b"])]
    fns = {"filter": ix.filter_satisfying, "min": ix.min_satisfying,
           "max": ix.max_satisfying}
    check([((r, k), fns[k](r), w) for r, k, w in table])


def test_index_equal_bounds_table():
    items = ["1.2.2", "1.2.3", "1.2.3+b", "1.2.4"]
    ix = VersionIndex(items)
    table = [(">=1.2.3 >1.2.3", ["1.2.4"]), (">1.2.3 >=1.2.3", ["1.2.4"]),
             ("<=1.2.3 <1.2.3", ["1.2.2"]), ("<1.2.3 <=1.2.3", ["1.2.2"]),
             ("1.2.3 <1.2.3", []), ("1.2.3 >1.2.3", []),
             ("1.2.3 <=1.2.3", ["1.2.3", "1.2.3+b"]),
             (">=1.2.2 >1.2.2 <=1.2.4 <1.2.4", ["1.2.3", "1.2.3+b"])]
    rows = [(r, ix.filter_satisfying(r), w) for r, w in table]
    rows += [(r + " max", ix.max_satisfying(r), (w[0] if w else None))
             for r, w in table]
    check(rows)


def test_index_several_sets_table():
    items = ["0.1.5", "1.4.0", "0.1.0", "1.0.0", "3.0.0", "0.1.9", "1.4.0+b"]
    ix = VersionIndex(items)
    table = [("^1 || ^0.1", "filter", ["0.1.5", "1.4.0", "0.1.0", "1.0.0", "0.1.9", "1.4.0+b"]),
             ("^0.1 || ^1", "filter", ["0.1.5", "1.4.0", "0.1.0", "1.0.0", "0.1.9", "1.4.0+b"]),
             ("3.x || 0.1.0 || 1.0.0", "filter", ["0.1.0", "1.0.0", "3.0.0"]),
             ("^0.1 || ^1", "max", "1.4.0"), ("^1 || ^0.1", "min", "0.1.0"),
             ("1.4.0 || 1.4.0+b", "max", "1.4.0"),
             ("^1 || ^1", "filter", ["1.4.0", "1.0.0", "1.4.0+b"])]
    fns = {"filter": ix.filter_satisfying, "min": ix.min_satisfying,
           "max": ix.max_satisfying}
    rows = [((r, k), fns[k](r), w) for r, k, w in table]
    rows.append(("module", filter_satisfying(items, "^1 || ^0.1"), table[0][2]))
    check(rows)


def test_index_prerelease_lines_table():
    items = ["1.2.3-rc", "1.2.3-alpha.5", "1.2.3", "2.0.0-beta", "2.0.0",
             "1.0.0", "1.2.4-alpha"]
    ix = VersionIndex(items)
    r = ">=1.2.3-alpha <1.2.3-beta || >=1.0.0"
    table = [(r, "filter", ["1.2.3-alpha.5", "1.2.3", "2.0.0", "1.0.0"]),
             (r, "max", "2.0.0"),
             (">=1.2.3-rc <2 || >=2.0.0-alpha <2.0.0", "filter",
              ["1.2.3-rc", "1.2.3", "2.0.0-beta"]),
             ("<2.0.0-0 || 2.0.0-beta", "filter",
              ["1.2.3", "2.0.0-beta", "1.0.0"]),
             (">=1.2.3-alpha <1.2.4 || >=1.2.4-alpha <1.2.4", "min", "1.2.3-alpha.5"),
             ("~1.2.3-alpha || ~1.2.4", "max", "1.2.3"),
             ("*", "filter", ["1.2.3", "2.0.0", "1.0.0"])]
    fns = {"filter": ix.filter_satisfying, "min": ix.min_satisfying,
           "max": ix.max_satisfying}
    check([((q, k), fns[k](q), w) for q, k, w in table])


def test_index_repeated_queries_table():
    items = ["1.2.3-2", "1.2.3", "1.5.0", "2.0.0", "12.0.0", "1.0.0", "2.5.0"]
    ix = VersionIndex(items)
    seq = [("1.2.3 - 2", ["1.2.3", "1.5.0", "2.0.0", "2.5.0"]),
           ("1.2.3-2", ["1.2.3-2"]),
           ("1.2.3  -\t2", ["1.2.3", "1.5.0", "2.0.0", "2.5.0"]),
           ("1 2", []), ("12", ["12.0.0"]), ("1 2", []),
           (">=1.0.0 <2", ["1.2.3", "1.5.0", "1.0.0"]),
           (">=1.0.0<2", "err"), (">= 1.0.0 <2", ["1.2.3", "1.5.0", "1.0.0"])]
    rows = []
    for q, want in seq:
        got = impl(ix.filter_satisfying, q)
        rows.append((q, got[0] if want == "err" else got,
                     "err" if want == "err" else ("ok", want)))
    rows.append(("Range", ix.max_satisfying(Range("^1")), "1.5.0"))
    check(rows)


def test_index_entries_table():
    items = ["1.0.0", "junk", "1.2", "1.0.0-01", "01.0.0", "2.0.0", ""]
    ix = VersionIndex(items)
    items.append("3.0.0")
    rows = [("len", len(ix), 2),
            ("after append", ix.max_satisfying("*"), "2.0.0"),
            ("module max", max_satisfying(items, "*"), "3.0.0"),
            ("min", ix.min_satisfying(">=0.0.0-0"), "1.0.0"),
            ("none", ix.max_satisfying("^9"), None),
            ("empty", VersionIndex([]).max_satisfying("*"), None),
            ("filter", ix.filter_satisfying("<3"), ["1.0.0", "2.0.0"]),
            ("generator", VersionIndex(v for v in ["1.0.0", "0.5.0"]).min_satisfying("*"), "0.5.0")]
    with pytest.raises(InvalidRange):
        ix.max_satisfying("1.x.3")
    check(rows)


def test_increment_table():
    table = [(("1.2.3-beta.1", "patch"), "1.2.3"), (("1.2.0-beta", "minor"), "1.2.0"),
             (("1.2.3-beta", "minor"), "1.3.0"), (("1.0.0-rc", "major"), "1.0.0"),
             (("1.1.0-rc", "major"), "2.0.0"), (("1.0.1-rc", "major"), "2.0.0"),
             (("1.2.3", "prerelease"), "1.2.4-0"),
             (("1.2.3", "prerelease", "rc"), "1.2.4-rc.0"),
             (("1.2.3-alpha", "prerelease"), "1.2.3-alpha.0"),
             (("1.2.3-alpha.1.beta", "prerelease"), "1.2.3-alpha.2.beta"),
             (("1.2.3-0", "prerelease"), "1.2.3-1"),
             (("1.2.3-alpha.9", "prerelease", "alpha"), "1.2.3-alpha.10"),
             (("1.2.3-alpha.9", "prerelease", "beta"), "1.2.3-beta.0"),
             (("1.2.3-1", "prerelease", "beta"), "1.2.3-beta.0"),
             (("1.2.3-beta", "prerelease", "beta"), "1.2.3-beta.0"),
             (("1.2.3+b.1", "patch"), "1.2.4"), (("1.2.3-rc+b", "prerelease"), "1.2.3-rc.0"),
             (("1.2.3", "premajor"), "2.0.0-0"), (("1.2.3-x", "preminor", "beta"), "1.3.0-beta.0"),
             (("1.2.3", "prepatch", "rc"), "1.2.4-rc.0"), (("1.2.3", "major", "rc"), "2.0.0")]
    rows = [(a, impl(inc, *a), ("ok", w)) for a, w in table]
    rows.append(("kind", impl(inc, "1.2.3", "release"),
                 ("err", "InvalidIncrement", "unknown increment: 'release'")))
    for preid in ["", "1", "a.b", "a_b"]:
        rows.append((preid, impl(inc, "1.2.3", "prerelease", preid),
                     ("err", "InvalidIncrement", f"invalid preid: {preid!r}")))
    rows.append(("version first", impl(inc, "1.2", "release")[1], "InvalidVersion"))
    check(rows)


def test_report_and_lock_scenario():
    requirements = {"left-pad": "^0.0.3", "widget": ">1.2", "gizmo": "~2",
                    "core": "^1.0.0-rc.1 || ^2", "util": ">= 1.0.0 <1.0.0"}
    available = {
        "left-pad": ["0.0.3", "0.0.9", "0.1.0"],
        "widget": ["1.2.9", "1.3.0-rc.1", "1.3.0+b2", "1.3.0+b1"],
        "gizmo": ["2.9.0", "3.0.0-0", "junk"],
        "core": ["1.0.0-rc.2", "1.0.0-rc.10", "2.0.0-beta", "1.9.0+x", "1.9.0"],
        "util": ["1.0.0"],
    }
    want = ("core ^1.0.0-rc.1 || ^2 -> 1.9.0+x\n"
            "gizmo ~2 -> 2.9.0\n"
            "left-pad ^0.0.3 -> 0.0.3\n"
            "util >= 1.0.0 <1.0.0 -> unresolved\n"
            "widget >1.2 -> 1.3.0+b2\n")
    lock = S.parse_lock("left-pad = 0.0.9\nwidget = 1.2.9\ngizmo = 2.0.0\n"
                        "core = 2.0.0-beta\nutil = 1.0.0\n")
    check([("report", S.format_report(requirements, available), want),
           ("core pick", S.resolve(requirements, available)["core"], "1.9.0+x"),
           ("lock", S.check_lock(requirements, lock), [
               "core: 2.0.0-beta is outside ^1.0.0-rc.1 || ^2",
               "left-pad: 0.0.9 is outside ^0.0.3",
               "util: 1.0.0 is outside >= 1.0.0 <1.0.0",
               "widget: 1.2.9 is outside >1.2"])])


def test_index_answers_quickly():
    items, ranges = O.gen_perf_case(random.Random(6199))
    ix = VersionIndex(items)
    start = time.perf_counter()
    for i, r in enumerate(ranges):
        ix.max_satisfying(r)
        ix.min_satisfying(r)
        assert time.perf_counter() - start < 5.0, f"too slow after {i} ranges"


# --------------------------------------------------------------- conformance
def _version_rows(rng, n):
    rows = []
    for _ in range(n):
        op = rng.randrange(4)
        if op == 0:
            t = O.gen_version_text(rng)
            rows.append((t, impl(lambda: str(parse(t))),
                         O.outcome(lambda: O.o_str(O.o_parse(t)))))
            rows.append((t, valid(t), O.o_valid(t)))
        elif op == 1:
            a, b = O.gen_near_version(rng), O.gen_near_version(rng)
            rows.append(((a, b), compare(a, b), O.o_compare(a, b)))
            pa, pb = parse(a), parse(b)
            rows.append(((a, b, "ops"), (pa < pb, pa == pb, pa > pb),
                         (O.o_compare(a, b) < 0, O.o_compare(a, b) == 0,
                          O.o_compare(a, b) > 0)))
        else:
            items = [O.gen_near_version(rng) for _ in range(rng.randint(0, 12))]
            items += [i.split("+")[0] + "+r" + str(k) for k, i in enumerate(items[:3])]
            rng.shuffle(items)
            rev = op == 3
            rows.append((items, [str(v) for v in sort_versions(items, reverse=rev)],
                         O.o_sort(items, reverse=rev)))
    return rows


def _range_rows(rng, n, sets=None):
    rows = []
    for _ in range(n):
        r = O.gen_range(rng, bad=rng.random() < 0.25, sets=sets)
        want = O.outcome(O.o_range_str, r)
        rows.append((r, rs(r), want))
        if want[0] == "ok":
            for _ in range(3):
                v = O.gen_version_for(rng, r)
                rows.append(((v, r), satisfies(v, r), O.o_satisfies(v, r)))
                rows.append(((v, r, "test"), Range(r).test(v), O.o_satisfies(v, r)))
    return rows


def _index_rows(rng, n):
    rows = []
    for _ in range(n):
        items, queries = O.gen_index_case(rng)
        ix = VersionIndex(items)
        rows.append(("len", len(ix), len(O._valid_items(items))))
        for q in queries:
            for name, fn, ofn in (("max", ix.max_satisfying, O.o_max),
                                  ("min", ix.min_satisfying, O.o_min),
                                  ("filter", ix.filter_satisfying, O.o_filter)):
                rows.append(((items, q, name), impl(fn, q), O.outcome(ofn, items, q)))
    return rows


def _list_rows(rng, n):
    rows = []
    for _ in range(n):
        items, queries = O.gen_index_case(rng)
        q = rng.choice(queries)
        for name, fn, ofn in (("max", max_satisfying, O.o_max),
                              ("min", min_satisfying, O.o_min),
                              ("filter", filter_satisfying, O.o_filter)):
            rows.append(((items, q, name), impl(fn, items, q), O.outcome(ofn, items, q)))
    return rows


def _inc_rows(rng, n):
    rows = []
    for _ in range(n):
        v, k, p = O.gen_inc_args(rng)
        rows.append(((v, k, p), impl(inc, v, k, p), O.outcome(O.o_inc, v, k, p)))
        current = O.gen_near_version(rng)
        for _ in range(rng.randint(1, 4)):
            kind = rng.choice(O.KINDS)
            preid = rng.choice([None, None, "alpha", "beta", "rc"])
            want = O.o_inc(current, kind, preid)
            rows.append(((current, kind, preid), inc(current, kind, preid), want))
            for spec in ("^" + want, "~" + want, ">" + want, "<=" + want):
                rows.append(((current, spec), satisfies(current, spec),
                             O.o_satisfies(current, spec)))
            current = want
    return rows


def _project_rows(rng, n):
    rows = []
    for _ in range(n):
        reqs, avail, lock = O.gen_project(rng)
        rows.append(((reqs, avail), S.format_report(reqs, avail), O.o_report(reqs, avail)))
        text = "".join(f"{k} = {v}\n" for k, v in lock.items())
        rows.append(((reqs, lock), S.check_lock(reqs, S.parse_lock(text)),
                     O.o_check_lock(reqs, lock)))
    return rows


_ALL = (_version_rows, _range_rows, _index_rows, _list_rows, _inc_rows, _project_rows)


def _mixed_rows(rng, n):
    rows = []
    for _ in range(n):
        rows += rng.choice(_ALL)(rng, 1)
    return rows


def test_conformance_versions_a():
    check(_version_rows(random.Random(6201), 1500))


def test_conformance_versions_b():
    check(_version_rows(random.Random(6202), 1500))


def test_conformance_ranges_one_set():
    check(_range_rows(random.Random(6203), 800, sets=1))


def test_conformance_ranges_several_sets():
    check(_range_rows(random.Random(6204), 800))


def test_conformance_index_a():
    check(_index_rows(random.Random(6205), 150))


def test_conformance_index_b():
    check(_index_rows(random.Random(6206), 150))


def test_conformance_index_c():
    check(_index_rows(random.Random(6207), 150))


def test_conformance_list_functions():
    check(_list_rows(random.Random(6208), 400))


def test_conformance_increments():
    check(_inc_rows(random.Random(6209), 600))


def test_conformance_projects():
    check(_project_rows(random.Random(6210), 300))


def test_conformance_whole_package_a():
    check(_mixed_rows(random.Random(6211), 400))


def test_conformance_whole_package_b():
    check(_mixed_rows(random.Random(6212), 400))


def test_conformance_whole_package_c():
    check(_mixed_rows(random.Random(6213), 400))


def test_conformance_whole_package_d():
    check(_mixed_rows(random.Random(6214), 400))


def test_conformance_whole_package_e():
    check(_mixed_rows(random.Random(6215), 400))
