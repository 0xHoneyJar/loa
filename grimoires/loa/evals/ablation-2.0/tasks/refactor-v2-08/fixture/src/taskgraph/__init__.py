"""Task manifests: checks, ordering, critical paths and schedules."""
from .parser import PlanError, ParseError, parse_manifest
from .graph import GraphError, CycleError, check, order as _order, levels as _levels, critical_path as _critical, slack as _slack
from .scheduler import ArgumentError, simulate
from .report import render, toDot as _to_dot
from .util import format_duration


def parse(text):
    """Parse a manifest and check its graph."""
    return check(parse_manifest(text))


def order(text):
    """Return the task names of a manifest in topological order."""
    return _order(parse(text))


def levels(text):
    """Return the task names of a manifest grouped by level."""
    return _levels(parse(text))


def critical_path(text):
    """Return the critical path of a manifest."""
    return _critical(parse(text))


def schedule(text, workers=2):
    """Return (name, start, end, worker) for every task of a manifest."""
    return simulate(parse(text), workers)


def report(text, workers=2):
    """Render a manifest's schedule and its summary."""
    g = parse(text)
    return render(g, simulate(g, workers))


def slack(text):
    """Return the slack of every task of a manifest."""
    return _slack(parse(text))


def to_dot(text):
    """Render a manifest's graph in dot syntax."""
    return _to_dot(parse(text))
