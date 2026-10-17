"""The scheduler: submission, readiness, dispatch and state changes."""
from .errors import DuplicateJob, SchedulerError, UnknownJob
from .keys import order_key
from .model import DONE, PENDING, RUNNING, Job
from .queue import ReadyQueue


class Scheduler:
    """Hands out jobs one at a time, by priority, once their ``after`` jobs are done."""

    def __init__(self):
        self._jobs = {}
        self._queue = ReadyQueue()
        self._seq = 0

    # -- submission ---------------------------------------------------------
    def submit(self, name, priority=0, after=()):
        """Submit a job; every name in ``after`` must already be submitted."""
        if not isinstance(name, str) or not name:
            raise ValueError("job name must be a non-empty string")
        if isinstance(priority, bool) or not isinstance(priority, int):
            raise TypeError("priority must be an int")
        if name in self._jobs:
            raise DuplicateJob(name)
        after = tuple(after)
        for dep in after:
            if dep not in self._jobs:
                raise UnknownJob(dep)
        job = Job(name=name, priority=priority, seq=self._seq, after=after)
        self._seq += 1
        self._jobs[name] = job
        self._refresh(job)
        return job

    def job(self, name):
        """The ``Job`` called ``name``."""
        try:
            return self._jobs[name]
        except KeyError:
            raise UnknownJob(name) from None

    # -- readiness ----------------------------------------------------------
    def _deps_done(self, job):
        return all(self._jobs[dep].state == DONE for dep in job.after)

    def _is_ready(self, job):
        return job.state == PENDING and not job.paused and self._deps_done(job)

    def _refresh(self, job):
        if self._is_ready(job):
            if job.name not in self._queue:
                self._queue.push(job)
        else:
            self._queue.discard(job.name)

    def _require_pending(self, job):
        if job.state != PENDING:
            raise SchedulerError(f"job {job.name} is {job.state}")

    # -- changes ------------------------------------------------------------
    def reprioritise(self, name, priority):
        """Give a pending job a new priority."""
        if isinstance(priority, bool) or not isinstance(priority, int):
            raise TypeError("priority must be an int")
        job = self.job(name)
        self._require_pending(job)
        job.priority = priority
        self._queue.push(job)

    def pause(self, name):
        """Hold a pending job back until it is resumed."""
        job = self.job(name)
        self._require_pending(job)
        job.paused = True
        self._queue.discard(name)

    def resume(self, name):
        """Let a paused job run again once it is ready."""
        job = self.job(name)
        self._require_pending(job)
        job.paused = False
        self._refresh(job)

    # -- dispatch -----------------------------------------------------------
    def ready(self):
        """Names of the jobs that may start now, in dispatch order."""
        names = list(self._queue.names())
        return sorted(names, key=lambda n: order_key(self._jobs[n]))

    def start(self, name):
        """Start a specific pending job."""
        job = self.job(name)
        self._require_pending(job)
        if not self._deps_done(job):
            raise SchedulerError(f"job {name} is waiting")
        job.state = RUNNING
        self._queue.discard(name)
        return job

    def next(self):
        """Start and return the next job's name, or None when nothing is ready."""
        name = self._queue.pop()
        if name is None:
            return None
        self._jobs[name].state = RUNNING
        return name

    def complete(self, name):
        """Mark a running job done and release the jobs waiting for it."""
        job = self.job(name)
        if job.state != RUNNING:
            raise SchedulerError(f"job {name} is {job.state}")
        job.state = DONE
        for other in self._jobs.values():
            if name in other.after:
                self._refresh(other)

    def pending(self):
        """Names of the jobs not yet done, in submission order."""
        return [j.name for j in self._jobs.values() if j.state != DONE]
