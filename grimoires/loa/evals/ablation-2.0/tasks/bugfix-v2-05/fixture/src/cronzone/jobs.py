"""Several named schedules together."""
from dataclasses import dataclass

from .errors import CronError
from .schedule import Schedule
from .timeutil import require_aware

POLICIES = ("all", "latest", "skip")


@dataclass
class Job:
    name: str
    schedule: Schedule

    @classmethod
    def create(cls, name, expression, zone="utc"):
        return cls(name, Schedule(expression, zone))


def upcoming(jobs, after, count):
    """The next ``count`` (instant, job name) pairs over all jobs.

    Ordered by instant; equal instants keep the order of ``jobs``.  A job
    that never fires within the horizon contributes nothing.
    """
    events = []
    for position, job in enumerate(jobs):
        moment = after
        for _ in range(count):
            try:
                moment = job.schedule.next_fire(moment)
            except CronError:
                break
            events.append((moment, position, job.name))
    events.sort(key=lambda e: (e[0], e[2]))
    return [(instant, name) for instant, _, name in events[:count]]


def catch_up(job, last_run, now, policy="all"):
    """Fire times missed since ``last_run``: ``last_run < t <= now``.

    ``all`` returns every one (ascending), ``latest`` only the last one
    (or nothing), ``skip`` nothing.
    """
    require_aware(last_run)
    require_aware(now)
    if policy not in POLICIES:
        raise CronError(f"unknown policy: {policy!r}")
    if policy == "skip":
        return []
    missed = job.schedule.fires_between(last_run, now)
    return missed if policy == "all" else missed[-1:]
