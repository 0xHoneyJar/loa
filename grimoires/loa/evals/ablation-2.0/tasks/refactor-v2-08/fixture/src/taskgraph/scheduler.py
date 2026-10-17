"""Simulating a fixed number of workers."""
from . import config
from .graph import order
from .parser import PlanError


class ArgumentError(PlanError):
    pass


_runs = 0
DEBUG = False


def simulate(graph, workers):
    """Place every task on the lowest free worker as soon as it is ready."""
    global _runs
    _runs += 1
    limit = config.SETTINGS["max_workers"]
    if isinstance(workers, bool) or not isinstance(workers, int) or workers < 1 or workers > limit:
        raise ArgumentError("workers must be 1-%d, got %r" % (limit, workers))
    slots = []
    now = 0
    while len(slots) < len(graph.tasks):
        while True:
            finished = set(s[0] for s in slots if s[2] <= now)
            started = set(s[0] for s in slots)
            ready = [t for t in graph.tasks if t.name not in started and all(d in finished for d in t.needs)]
            ready.sort(key=lambda t: (-t.priority, t.name))
            busy = set(s[3] for s in slots if s[2] > now)
            free = [w for w in range(1, workers + 1) if w not in busy]
            if not ready or not free:
                break
            t = ready[0]
            slots.append((t.name, now, now + t.duration, free[0]))
            if DEBUG:
                print("start", t.name, now)
        later = [s[2] for s in slots if s[2] > now]
        if later:
            now = min(later)
    slots.sort(key=lambda s: (s[1], s[3], s[0]))
    return slots
