"""The agenda: the next fire times of every job, merged.

Each line is ``<local time> <job>`` where the local time is the fire instant
in the job's zone, ``YYYY-MM-DDTHH:MM+HH:MM``.  Lines are ordered by fire
instant, then by the jobs' file order.  At most ``count`` lines.
"""
import heapq

from .timeutil import format_local


def upcoming(job, after, count):
    """The next ``count`` fire instants of ``job`` strictly after ``after``."""
    result, instant = [], after
    while len(result) < count:
        instant = job.next_after(instant)
        result.append(instant)
    return result


def build_agenda(jobs, now, count):
    """``[(instant, job), ...]``: the first ``count`` fires after ``now`` over all jobs."""
    candidates = []
    for index, job in enumerate(jobs):
        for instant in upcoming(job, now, count):
            candidates.append((instant, index, job))
    return [(instant, job) for instant, _, job in heapq.nsmallest(count, candidates, key=lambda item: item[:2])]


def format_agenda(rows):
    if not rows:
        return ["no upcoming runs"]
    return [f"{format_local(instant, job.zone.offset_at(instant))} {job.name}" for instant, job in rows]
