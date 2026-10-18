import pytest

import taskgraph

BUILD = """
# a small build
fetch: 10m
compile: 1h needs fetch priority 1
lint: 15 needs fetch
test: 45m needs compile
docs: 30m needs fetch priority -1
package: 5 needs test, lint   # last
"""


def test_order_prefers_priority_then_name():
    assert taskgraph.order(BUILD) == ["fetch", "compile", "lint", "test", "package", "docs"]
    assert taskgraph.order("b: 1\na: 1\nc: 1 priority 1") == ["c", "a", "b"]


def test_levels():
    assert taskgraph.levels(BUILD) == [["fetch"], ["compile", "docs", "lint"], ["test"], ["package"]]


def test_critical_path():
    assert taskgraph.critical_path(BUILD) == (120, ["fetch", "compile", "test", "package"])


def test_critical_path_ties_pick_the_smallest_name():
    assert taskgraph.critical_path("b: 5\na: 5\nc: 1 needs a, b") == (6, ["a", "c"])


def test_schedule_on_two_workers():
    assert taskgraph.schedule(BUILD, 2) == [
        ("fetch", 0, 10, 1),
        ("compile", 10, 70, 1),
        ("lint", 10, 25, 2),
        ("docs", 25, 55, 2),
        ("test", 70, 115, 1),
        ("package", 115, 120, 1),
    ]


def test_schedule_on_one_worker_is_the_order():
    slots = taskgraph.schedule(BUILD, 1)
    assert [s[0] for s in slots] == taskgraph.order(BUILD)
    assert slots[-1][2] == 165


def test_zero_length_tasks_release_their_worker_at_once():
    assert taskgraph.schedule("gate: 0\nwork: 10 needs gate\nside: 3", 1) == [
        ("gate", 0, 0, 1), ("side", 0, 3, 1), ("work", 3, 13, 1)]


def test_worker_count_is_checked():
    for bad in (0, 65, True, "2"):
        with pytest.raises(taskgraph.ArgumentError, match=r"^workers must be 1-64, got "):
            taskgraph.schedule(BUILD, bad)


def test_report():
    assert taskgraph.report("a: 1h\nb: 30m needs a\nc: 2h", 2) == "\n".join([
        "a  0-60   w1",
        "c  0-120  w2",
        "b  60-90  w1",
        "",
        "tasks: 3",
        "work: 3h30m",
        "makespan: 2h",
        "critical: c (2h)",
    ])


def test_slack():
    assert taskgraph.slack(BUILD) == {"fetch": 0, "compile": 0, "lint": 90, "test": 0, "docs": 80, "package": 0}


def test_to_dot():
    assert taskgraph.to_dot("a: 90\nb: 1h needs a") == "\n".join([
        "digraph tasks {", '  "a" [label="a (1h30m)"];', '  "b" [label="b (1h)"];', '  "a" -> "b";', "}"])


def test_negative_priority_waits_for_equal_ready_tasks():
    assert taskgraph.order("z: 1\nm: 1 priority -1\na: 1") == ["a", "z", "m"]


def test_levels_of_a_single_task():
    assert taskgraph.levels("solo: 5") == [["solo"]]
