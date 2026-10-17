"""The runner: on every tick, each job that became due since the previous tick
gets ONE log entry.

Catch-up rule: all the fire instants of a job in ``(previous tick, this tick]``
coalesce into a single entry whose time is the latest of them and whose
``fires`` is their number.  Entries of one tick are ordered by time, then by
the jobs' file order.
"""
from .errors import CronqError
from .runlog import Entry, RunLog


class Runner:
    def __init__(self, jobs, start, log=None):
        self.jobs = list(jobs)
        self.log = log if log is not None else RunLog()
        self.last = {job.name: start for job in self.jobs}
        self.now = start

    def _fires(self, job, after, until):
        fires = []
        instant = job.next_after(after)
        while instant <= until:
            fires.append(instant)
            instant = job.next_after(instant)
        return fires

    def tick(self, now):
        if now < self.now:
            raise CronqError("clock cannot move backwards")
        due = []
        for index, job in enumerate(self.jobs):
            fires = self._fires(job, self.last[job.name], now)
            self.last[job.name] = now
            if fires:
                due.append((fires[-1], index, Entry(fires[-1], job.name, len(fires))))
        self.now = now
        entries = [entry for _, _, entry in sorted(due, key=lambda item: item[:2])]
        self.log.extend(entries)
        return entries

    def run(self, clock, until, step_minutes):
        """Tick the clock in steps of ``step_minutes`` up to ``until``; return every entry."""
        entries = []
        for now in clock.ticks(until, step_minutes):
            entries.extend(self.tick(now))
        return entries
