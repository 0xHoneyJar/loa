"""The job record."""
from dataclasses import dataclass, field

PENDING = "pending"
RUNNING = "running"
DONE = "done"


@dataclass
class Job:
    """One job.

    ``seq`` is the job's submission number (0 for the first job submitted to a
    scheduler, then 1, 2, ...).  ``state`` is ``pending`` until the job starts,
    ``running`` while it runs and ``done`` once it has completed.  ``paused`` is
    independent of ``state``: only a pending job can be paused.
    """

    name: str
    priority: int
    seq: int
    after: tuple = field(default_factory=tuple)
    state: str = PENDING
    paused: bool = False

    @property
    def finished(self):
        return self.state == DONE
