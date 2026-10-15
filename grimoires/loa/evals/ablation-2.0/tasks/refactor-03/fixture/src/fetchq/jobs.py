"""Batches of requests."""
from . import core


def plan_batch(paths: list) -> list:
    """One request plan per distinct path, in first-seen order."""
    seen, out = set(), []
    for p in paths:
        if p in seen:
            continue
        seen.add(p)
        out.append(core.request_plan(p))
    return out


def simulate(path: str, statuses: list) -> list:
    """Replay a sequence of response statuses for ``path``: ``(attempt, status, action)`` rows.

    The action is ``retry`` (after the delay), ``done`` or ``give-up``; statuses
    after the last attempt are ignored.
    """
    url = core.build_url(path)
    delays = core.backoff_delays()
    rows = []
    for attempt, status in enumerate(statuses):
        if core.should_retry(attempt, status):
            rows.append((attempt, status, f"retry in {delays[attempt]:g}s"))
            continue
        rows.append((attempt, status, "done" if status < 400 else "give-up"))
        break
    return [{"url": url, "attempt": a, "status": s, "action": act} for a, s, act in rows]
