"""Reference behaviour of the package, flattened into one module (grader side)."""

import enum
from dataclasses import dataclass
import re


# ---- errors ----

class PlanError(ValueError):
    """Base class of every error the package raises."""


class ParseError(PlanError):
    """A manifest line does not follow the grammar."""


class GraphError(PlanError):
    """The tasks of a manifest do not form a usable graph."""


class CycleError(GraphError):
    """The dependencies of a manifest form a cycle."""


class ArgumentError(PlanError):
    """A worker count or input file is unusable."""


# ---- model ----

class Unit(enum.Enum):
    """A duration unit; a bare number is minutes."""

    MINUTES = "m"
    HOURS = "h"


class Command(enum.Enum):
    """A command-line action."""

    ORDER = "order"
    LEVELS = "levels"
    CRITICAL = "critical"
    SCHEDULE = "schedule"
    CHECK = "check"
    SLACK = "slack"
    DOT = "dot"


@dataclass(frozen=True, slots=True)
class Task:
    """One task: its duration in minutes, its dependencies and priority."""

    name: str
    duration: int
    needs: tuple[str, ...] = ()
    priority: int = 0
    line: int = 0


@dataclass(frozen=True, slots=True)
class Graph:
    """The tasks of a manifest in definition order."""

    tasks: tuple[Task, ...]


@dataclass(frozen=True, slots=True)
class Slot:
    """One task placed on a worker."""

    name: str
    start: int
    end: int
    worker: int


# ---- names ----

NAME_PATTERN = r"[a-z][a-z0-9_-]*"


def check_name(text: str, line: int) -> str:
    """Return a valid task name or raise for its line."""
    if not re.fullmatch(NAME_PATTERN, text):
        raise ParseError(f"line {line}: bad task name {text!r}")
    return text


# ---- durations ----

MAX_MINUTES = 10000


def unit_minutes(unit: Unit) -> int:
    """Return the minutes one unit stands for."""
    match unit:
        case Unit.MINUTES:
            minutes = 1
        case Unit.HOURS:
            minutes = 60
    return minutes


def parse_duration(text: str, line: int) -> int:
    """Read a duration such as 90, 45m or 2h as minutes."""
    match = re.fullmatch(r"([0-9]+)([mh]?)", text)
    if match is None:
        raise ParseError(f"line {line}: bad duration {text!r}")
    minutes = int(match.group(1)) * unit_minutes(Unit(match.group(2) or "m"))
    if minutes > MAX_MINUTES:
        raise ParseError(f"line {line}: duration {text!r} is over {MAX_MINUTES} minutes")
    return minutes


def format_duration(minutes: int) -> str:
    """Render minutes as 1h30m, 2h or 45m."""
    hours, rest = divmod(minutes, 60)
    if hours and rest:
        text = f"{hours}h{rest}m"
    elif hours:
        text = f"{hours}h"
    else:
        text = f"{rest}m"
    return text


# ---- index ----

def by_name(graph: Graph) -> dict[str, Task]:
    """Map each task name to its task."""
    return {task.name: task for task in graph.tasks}


def dependents(graph: Graph) -> dict[str, list[str]]:
    """Map each task name to the tasks that need it, in definition order."""
    return {task.name: [user.name for user in graph.tasks if task.name in user.needs] for task in graph.tasks}


# ---- lines ----

_CLAUSES = r"^(?:needs\s+(?P<needs>.+?))?(?:\s*\bpriority\s+(?P<priority>-?[0-9]+))?$"


def parse_needs(text: str | None, line: int) -> tuple[str, ...]:
    """Split a needs clause into distinct, valid task names."""
    items = tuple(part.strip() for part in text.split(",")) if text is not None else ()
    for position, item in enumerate(items):
        if not item:
            raise ParseError(f"line {line}: empty dependency")
        if check_name(item, line) in items[:position]:
            raise ParseError(f"line {line}: duplicate dependency {item!r}")
    return items


def _clauses(words: list[str], line: int) -> tuple[tuple[str, ...], int]:
    rest = " ".join(words)
    match = re.match(_CLAUSES, rest)
    if match is None:
        raise ParseError(f"line {line}: bad clause {rest!r}")
    priority = match.group("priority")
    return parse_needs(match.group("needs"), line), int(priority) if priority else 0


def parse_line(text: str, line: int) -> Task:
    """Parse 'name: duration [needs a, b] [priority n]'."""
    head, colon, rest = text.partition(":")
    if not colon:
        raise ParseError(f"line {line}: expected 'name: duration'")
    name = check_name(head.strip(), line)
    words = rest.split()
    if not words:
        raise ParseError(f"line {line}: missing duration")
    duration = parse_duration(words[0], line)
    needs, priority = _clauses(words[1:], line)
    return Task(name, duration, needs, priority, line)


# ---- validate ----

def _unknown(graph: Graph) -> None:
    names = by_name(graph)
    for task, dep in ((t, d) for t in graph.tasks for d in t.needs):
        if dep not in names:
            raise GraphError(f"task {task.name!r} needs unknown task {dep!r}")


def _advance(frames: tuple[tuple[str, int], ...], done: frozenset[str], dep: str) -> tuple[tuple[tuple[str, int], ...], frozenset[str], list[str] | None]:
    name, index = frames[-1]
    frames = frames[:-1] + ((name, index + 1),)
    names = [frame[0] for frame in frames]
    if dep in names:
        result = (frames, done, names[names.index(dep):])
    elif dep in done:
        result = (frames, done, None)
    else:
        result = (frames + ((dep, 0),), done, None)
    return result


def _step(frames: tuple[tuple[str, int], ...], done: frozenset[str], needs: dict[str, tuple[str, ...]]) -> tuple[tuple[tuple[str, int], ...], frozenset[str], list[str] | None]:
    name, index = frames[-1]
    deps = needs[name]
    if index == len(deps):
        result = (frames[:-1], done | {name}, None)
    else:
        result = _advance(frames, done, deps[index])
    return result


def _search(start: str, needs: dict[str, tuple[str, ...]], done: frozenset[str]) -> tuple[list[str] | None, frozenset[str]]:
    frames, cycle = ((start, 0),), None
    while frames and cycle is None:
        frames, done, cycle = _step(frames, done, needs)
    return cycle, done


def find_cycle(graph: Graph) -> list[str] | None:
    """Return the first cycle a depth-first walk in definition order meets."""
    needs = {task.name: task.needs for task in graph.tasks}
    done: frozenset[str] = frozenset()
    cycle = None
    for task in graph.tasks:
        if cycle is None and task.name not in done:
            cycle, done = _search(task.name, needs, done)
    return cycle


def rotate_cycle(cycle: list[str]) -> list[str]:
    """Start a cycle at its smallest name and close it."""
    start = cycle.index(min(cycle))
    turned = cycle[start:] + cycle[:start]
    return turned + [turned[0]]


def check_graph(graph: Graph) -> Graph:
    """Reject unknown dependencies, then cycles; return the graph."""
    _unknown(graph)
    cycle = find_cycle(graph)
    if cycle is not None:
        raise CycleError("cycle: " + " -> ".join(rotate_cycle(cycle)))
    return graph


# ---- ordering ----

def ready_key(task: Task) -> tuple[int, str]:
    """Order ready tasks: higher priority first, then by name."""
    return (-task.priority, task.name)


def _release(waiting: dict[str, int], users: list[str]) -> tuple[dict[str, int], list[str]]:
    left = {name: count - (1 if name in users else 0) for name, count in waiting.items()}
    return left, [user for user in users if left[user] == 0]


def topological_order(graph: Graph) -> list[str]:
    """Return every task after its dependencies, picking ready tasks by key."""
    tasks, users = by_name(graph), dependents(graph)
    waiting = {task.name: len(task.needs) for task in graph.tasks}
    ready = [task for task in graph.tasks if not task.needs]
    order: list[str] = []
    while ready:
        current = min(ready, key=ready_key)
        waiting, freed = _release(waiting, users[current.name])
        ready = [t for t in ready if t is not current] + [tasks[name] for name in freed]
        order = order + [current.name]
    return order


def levels(graph: Graph) -> list[list[str]]:
    """Group tasks by depth: no dependencies is level 0; names sorted."""
    tasks = by_name(graph)
    depth: dict[str, int] = {}
    for name in topological_order(graph):
        depth = {**depth, name: 1 + max((depth[d] for d in tasks[name].needs), default=-1)}
    top = max(depth.values())
    return [sorted(name for name, level in depth.items() if level == wanted) for wanted in range(top + 1)]


# ---- manifest ----

def strip_comment(raw: str) -> str:
    """Drop a # comment and surrounding blanks from one line."""
    return raw.split("#", 1)[0].strip()


def _added(tasks: tuple[Task, ...], task: Task) -> tuple[Task, ...]:
    for seen in tasks:
        if seen.name == task.name:
            raise ParseError(f"line {task.line}: task {task.name!r} already defined on line {seen.line}")
    return tasks + (task,)


def parse_manifest(text: str) -> Graph:
    """Parse every task line of a manifest, in order."""
    if not isinstance(text, str):
        raise ParseError("manifest must be a string")
    tasks: tuple[Task, ...] = ()
    for number, raw in enumerate(text.splitlines(), 1):
        body = strip_comment(raw)
        if body:
            tasks = _added(tasks, parse_line(body, number))
    if not tasks:
        raise ParseError("manifest has no tasks")
    return Graph(tasks)


# ---- critical ----

def finish_times(graph: Graph) -> dict[str, int]:
    """Return each task's earliest finish with unlimited workers."""
    tasks = by_name(graph)
    finish: dict[str, int] = {}
    for name in topological_order(graph):
        task = tasks[name]
        finish = {**finish, name: task.duration + max((finish[d] for d in task.needs), default=0)}
    return finish


def _latest(names: list[str], finish: dict[str, int]) -> str:
    return min(names, key=lambda n: (-finish[n], n))


def critical_path(graph: Graph) -> tuple[int, list[str]]:
    """Return the length and the tasks of the critical path."""
    finish, tasks = finish_times(graph), by_name(graph)
    current: Task = tasks[_latest(list(finish), finish)]
    path = [current.name]
    while current.needs:
        current = tasks[_latest(list(current.needs), finish)]
        path = path + [current.name]
    return finish[path[0]], path[::-1]


def _latest_finish(graph: Graph, total: int) -> dict[str, int]:
    tasks, users = by_name(graph), dependents(graph)
    latest: dict[str, int] = {}
    for name in reversed(topological_order(graph)):
        starts = [latest[u] - tasks[u].duration for u in users[name]]
        latest = {**latest, name: min(starts) if starts else total}
    return latest


def slack_times(graph: Graph) -> dict[str, int]:
    """Return how many minutes each task can slip without delaying the end."""
    finish = finish_times(graph)
    latest = _latest_finish(graph, max(finish.values()))
    return {task.name: latest[task.name] - finish[task.name] for task in graph.tasks}


# ---- simulate ----

MAX_WORKERS = 64


def check_workers(workers: int) -> int:
    """Return a usable worker count or raise."""
    if isinstance(workers, bool) or not isinstance(workers, int) or not 1 <= workers <= MAX_WORKERS:
        raise ArgumentError(f"workers must be 1-{MAX_WORKERS}, got {workers!r}")
    return workers


def _waiting(graph: Graph, slots: tuple[Slot, ...]) -> list[Task]:
    started = {s.name for s in slots}
    return [t for t in graph.tasks if t.name not in started]


def _ready(graph: Graph, slots: tuple[Slot, ...], now: int) -> list[Task]:
    finished = {s.name for s in slots if s.end <= now}
    return sorted((t for t in _waiting(graph, slots) if finished.issuperset(t.needs)), key=ready_key)


def _free(slots: tuple[Slot, ...], now: int, workers: int) -> list[int]:
    busy = {s.worker for s in slots if s.end > now}
    return [w for w in range(1, workers + 1) if w not in busy]


def _place(graph: Graph, slots: tuple[Slot, ...], clock: tuple[int, int]) -> Slot | None:
    now, workers = clock
    ready, free = _ready(graph, slots, now), _free(slots, now, workers)
    placed = None
    if ready and free:
        placed = Slot(ready[0].name, now, now + ready[0].duration, free[0])
    return placed


def _fill(graph: Graph, slots: tuple[Slot, ...], clock: tuple[int, int]) -> tuple[Slot, ...]:
    placed = _place(graph, slots, clock)
    while placed is not None:
        slots = slots + (placed,)
        placed = _place(graph, slots, clock)
    return slots


def simulate(graph: Graph, workers: int) -> list[Slot]:
    """Place every task on the lowest free worker as soon as it is ready."""
    check_workers(workers)
    slots: tuple[Slot, ...] = ()
    now = 0
    while len(slots) < len(graph.tasks):
        slots = _fill(graph, slots, (now, workers))
        later = [s.end for s in slots if s.end > now]
        now = min(later) if later else now
    return sorted(slots, key=lambda s: (s.start, s.worker, s.name))


# ---- render ----

def format_schedule(slots: list[Slot]) -> str:
    """Render one line per slot: name, start-end and worker, in columns."""
    spans = [f"{s.start}-{s.end}" for s in slots]
    name_width = max(len(s.name) for s in slots)
    span_width = max(len(span) for span in spans)
    lines = [f"{s.name.ljust(name_width)}  {span.ljust(span_width)}  w{s.worker}" for s, span in zip(slots, spans)]
    return "\n".join(lines)


def summary(graph: Graph, slots: list[Slot]) -> str:
    """Render the task count, total work, makespan and critical path."""
    total, path = critical_path(graph)
    work = sum(task.duration for task in graph.tasks)
    makespan = max(s.end for s in slots)
    return "\n".join([
        f"tasks: {len(graph.tasks)}",
        f"work: {format_duration(work)}",
        f"makespan: {format_duration(makespan)}",
        f"critical: {' > '.join(path)} ({format_duration(total)})",
    ])


def to_dot(graph: Graph) -> str:
    """Render a graph in Graphviz dot syntax."""
    nodes = [f'  "{t.name}" [label="{t.name} ({format_duration(t.duration)})"];' for t in graph.tasks]
    edges = [f'  "{d}" -> "{t.name}";' for t in graph.tasks for d in t.needs]
    return "\n".join(["digraph tasks {"] + nodes + edges + ["}"])


# ---- facade ----

def plan(text: str) -> Graph:
    """Parse a manifest and check its graph."""
    return check_graph(parse_manifest(text))


def order_text(text: str) -> list[str]:
    """Return the task names of a manifest in topological order."""
    return topological_order(plan(text))


def levels_text(text: str) -> list[list[str]]:
    """Return the task names of a manifest grouped by level."""
    return levels(plan(text))


def critical_text(text: str) -> tuple[int, list[str]]:
    """Return the critical path of a manifest."""
    return critical_path(plan(text))


def schedule_text(text: str, workers: int = 2) -> list[tuple[str, int, int, int]]:
    """Return (name, start, end, worker) for every task of a manifest."""
    return [(s.name, s.start, s.end, s.worker) for s in simulate(plan(text), workers)]


def report(text: str, workers: int = 2) -> str:
    """Render a manifest's schedule and its summary."""
    graph = plan(text)
    slots = simulate(graph, workers)
    return format_schedule(slots) + "\n\n" + summary(graph, slots)


def slack_text(text: str) -> dict[str, int]:
    """Return the slack of every task of a manifest."""
    return slack_times(plan(text))


def dot_text(text: str) -> str:
    """Render a manifest's graph in dot syntax."""
    return to_dot(plan(text))

