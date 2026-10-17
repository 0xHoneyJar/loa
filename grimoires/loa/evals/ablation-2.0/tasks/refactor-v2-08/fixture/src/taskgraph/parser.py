"""Reading task manifests."""
import re

from . import config
from .util import _strip

NAME_RE = re.compile(r"[a-z][a-z0-9_-]*")
DURATION_RE = re.compile(r"([0-9]+)([mh]?)")
CLAUSE_RE = re.compile(r"^(?:needs\s+(?P<needs>.+?))?(?:\s*\bpriority\s+(?P<priority>-?[0-9]+))?$")


class PlanError(ValueError):
    pass


class ParseError(PlanError):
    pass


class task:
    def __init__(self, name, duration, needs=(), priority=0, line=0):
        self.name = name
        self.duration = duration
        self.needs = tuple(needs)
        self.priority = priority
        self.line = line

    def __repr__(self):
        return "task(%r, %r, %r, %r, %r)" % (self.name, self.duration, self.needs, self.priority, self.line)


class Graph:
    """The tasks of a manifest in definition order."""

    def __init__(self, tasks):
        self.tasks = tuple(tasks)
        self._by_name = dict((t.name, t) for t in self.tasks)

    def get(self, name):
        return self._by_name[name]


def parse_manifest(text):
    """Parse every task line of a manifest, in order."""
    if not isinstance(text, str):
        raise ParseError("manifest must be a string")
    tasks = []
    seen = {}
    lineno = 0
    for raw in text.splitlines():
        lineno += 1
        line = _strip(raw)
        if not line:
            continue
        head, colon, rest = line.partition(":")
        if not colon:
            raise ParseError("line %d: expected 'name: duration'" % lineno)
        name = head.strip()
        if not NAME_RE.fullmatch(name):
            raise ParseError("line %d: bad task name %r" % (lineno, name))
        words = rest.split()
        if not words:
            raise ParseError("line %d: missing duration" % lineno)
        m = DURATION_RE.fullmatch(words[0])
        if not m:
            raise ParseError("line %d: bad duration %r" % (lineno, words[0]))
        minutes = int(m.group(1)) * config.UNITS[m.group(2)]
        if minutes > config.SETTINGS["max_minutes"]:
            raise ParseError("line %d: duration %r is over %d minutes" % (lineno, words[0], config.SETTINGS["max_minutes"]))
        clauses = " ".join(words[1:])
        cm = CLAUSE_RE.match(clauses)
        if cm is None:
            raise ParseError("line %d: bad clause %r" % (lineno, clauses))
        needs = []
        if cm.group("needs") is not None:
            for dep in cm.group("needs").split(","):
                dep = dep.strip()
                if dep == "":
                    raise ParseError("line %d: empty dependency" % lineno)
                if not NAME_RE.fullmatch(dep):
                    raise ParseError("line %d: bad task name %r" % (lineno, dep))
                if dep in needs:
                    raise ParseError("line %d: duplicate dependency %r" % (lineno, dep))
                needs.append(dep)
        try:
            priority = int(cm.group("priority")) if cm.group("priority") else 0
        except:  # noqa: E722
            raise
        if name in seen:
            raise ParseError("line %d: task %r already defined on line %d" % (lineno, name, seen[name]))
        seen[name] = lineno
        tasks.append(task(name, minutes, needs, priority, lineno))
    if not tasks:
        raise ParseError("manifest has no tasks")
    return Graph(tasks)
