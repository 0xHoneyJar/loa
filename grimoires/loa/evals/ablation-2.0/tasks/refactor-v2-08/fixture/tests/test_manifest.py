import pytest

import taskgraph
from taskgraph import CycleError, GraphError, ParseError

BUILD = """
# a small build
fetch: 10m
compile: 1h needs fetch priority 1
lint: 15 needs fetch
test: 45m needs compile
docs: 30m needs fetch priority -1
package: 5 needs test, lint   # last
"""


def test_parse_fields():
    graph = taskgraph.parse(BUILD)
    names = [t.name for t in graph.tasks]
    assert names == ["fetch", "compile", "lint", "test", "docs", "package"]
    compile_task = graph.tasks[1]
    assert (compile_task.duration, compile_task.needs, compile_task.priority, compile_task.line) == (60, ("fetch",), 1, 4)


@pytest.mark.parametrize("text,message", [
    ("", "manifest has no tasks"),
    ("# only\n\n", "manifest has no tasks"),
    ("a 5", "line 1: expected 'name: duration'"),
    ("A: 5", "line 1: bad task name 'A'"),
    ("a:", "line 1: missing duration"),
    ("a: 5s", "line 1: bad duration '5s'"),
    ("a: 200h", "line 1: duration '200h' is over 10000 minutes"),
    ("a: 5\nb: 5 needs a,,a", "line 2: empty dependency"),
    ("a: 5\nb: 5 needs a, a", "line 2: duplicate dependency 'a'"),
    ("a: 5 priority high", "line 1: bad clause 'priority high'"),
    ("a: 5\n\na: 6", "line 3: task 'a' already defined on line 1"),
])
def test_parse_errors(text, message):
    with pytest.raises(ParseError) as info:
        taskgraph.parse(text)
    assert str(info.value) == message


def test_unknown_dependency():
    with pytest.raises(GraphError, match=r"^task 'b' needs unknown task 'ghost'$"):
        taskgraph.parse("a: 1\nb: 1 needs a, ghost")


def test_cycles_are_reported_from_their_smallest_name():
    with pytest.raises(CycleError, match=r"^cycle: b -> c -> d -> b$"):
        taskgraph.parse("a: 1 needs c\nc: 1 needs d\nd: 1 needs b\nb: 1 needs c")
    with pytest.raises(CycleError, match=r"^cycle: a -> a$"):
        taskgraph.parse("a: 1 needs a")


def test_cycle_errors_are_graph_errors():
    assert issubclass(CycleError, GraphError) and issubclass(GraphError, taskgraph.PlanError)
    assert issubclass(taskgraph.PlanError, ValueError)


@pytest.mark.parametrize("minutes,text", [(0, "0m"), (45, "45m"), (60, "1h"), (90, "1h30m"), (601, "10h1m")])
def test_format_duration(minutes, text):
    assert taskgraph.format_duration(minutes) == text


def test_comments_blank_lines_and_spacing():
    graph = taskgraph.parse("\n  # header\nx:5   # five\n\ny :  2h needs x , z priority -3\nz: 0m\n")
    assert [(t.name, t.duration, t.needs, t.priority, t.line) for t in graph.tasks] == [
        ("x", 5, (), 0, 3), ("y", 120, ("x", "z"), -3, 5), ("z", 0, (), 0, 6)]


def test_unknown_dependencies_are_found_before_cycles():
    with pytest.raises(GraphError, match=r"^task 'c' needs unknown task 'q'$"):
        taskgraph.parse("a: 1 needs b\nb: 1 needs a\nc: 1 needs q")


def test_non_string_manifest():
    with pytest.raises(ParseError, match=r"^manifest must be a string$"):
        taskgraph.parse(None)
