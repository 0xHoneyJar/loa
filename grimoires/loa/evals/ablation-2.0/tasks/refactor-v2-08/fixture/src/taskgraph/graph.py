"""Graph algorithms over parsed manifests."""
from typing import List

from .parser import PlanError


class GraphError(PlanError):
    pass


class CycleError(GraphError):
    pass


def check(graph):
    """Reject unknown dependencies, then cycles; return the graph."""
    names = set(t.name for t in graph.tasks)
    for t in graph.tasks:
        for dep in t.needs:
            if dep not in names:
                raise GraphError("task %r needs unknown task %r" % (t.name, dep))
    needs = dict((t.name, t.needs) for t in graph.tasks)
    done = set()
    stack = []

    def visit(name):
        stack.append(name)
        for dep in needs[name]:
            if dep in stack:
                return stack[stack.index(dep):]
            if dep not in done:
                found = visit(dep)
                if found:
                    return found
        done.add(stack.pop())
        return None

    for t in graph.tasks:
        if t.name in done:
            continue
        cycle = visit(t.name)
        if cycle:
            i = cycle.index(min(cycle))
            cycle = cycle[i:] + cycle[:i]
            cycle.append(cycle[0])
            raise CycleError("cycle: " + " -> ".join(cycle))
    return graph


def order(graph) -> List[str]:
    """Return every task after its dependencies, picking ready tasks by key."""
    users = dict((t.name, []) for t in graph.tasks)
    for t in graph.tasks:
        for dep in t.needs:
            users[dep].append(t.name)
    waiting = dict((t.name, len(t.needs)) for t in graph.tasks)
    ready = [t for t in graph.tasks if len(t.needs) == 0]
    out = []
    while len(ready) > 0:
        best = None
        for t in ready:
            if best is None or (-t.priority, t.name) < (-best.priority, best.name):
                best = t
        ready.remove(best)
        out.append(best.name)
        for u in users[best.name]:
            waiting[u] -= 1
            if waiting[u] == 0:
                ready.append(graph.get(u))
    return out


def levels(graph):
    """Group tasks by depth: no dependencies is level 0; names sorted."""
    depth = {}
    for name in order(graph):
        t = graph.get(name)
        if not t.needs:
            depth[name] = 0
        else:
            depth[name] = 1 + max(depth[d] for d in t.needs)
    result = []
    for lvl in range(max(depth.values()) + 1):
        result.append(sorted(n for n in depth if depth[n] == lvl))
    return result


def finish_times(graph):
    finish = {}
    for name in order(graph):
        t = graph.get(name)
        start = 0
        for d in t.needs:
            if finish[d] > start:
                start = finish[d]
        finish[name] = start + t.duration
    return finish


def critical_path(graph):
    """Return the length and the tasks of the critical path."""
    finish = finish_times(graph)
    end = sorted(finish, key=lambda n: (-finish[n], n))[0]
    path = [end]
    cur = graph.get(end)
    while cur.needs:
        nxt = sorted(cur.needs, key=lambda n: (-finish[n], n))[0]
        path.append(nxt)
        cur = graph.get(nxt)
    path.reverse()
    return finish[end], path


def slack(graph):
    """Return how many minutes each task can slip without delaying the end."""
    finish = finish_times(graph)
    total = max(finish.values())
    users = dict((t.name, []) for t in graph.tasks)
    for t in graph.tasks:
        for dep in t.needs:
            users[dep].append(t.name)
    latest = {}
    for name in reversed(order(graph)):
        if users[name]:
            latest[name] = min(latest[u] - graph.get(u).duration for u in users[name])
        else:
            latest[name] = total
    return dict((t.name, latest[t.name] - finish[t.name]) for t in graph.tasks)
