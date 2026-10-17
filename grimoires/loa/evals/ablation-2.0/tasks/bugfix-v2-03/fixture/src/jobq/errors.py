"""Errors raised by the scheduler."""


class SchedulerError(Exception):
    """A request the scheduler cannot honour in the job's current state."""


class UnknownJob(SchedulerError, KeyError):
    """A job name that was never submitted."""

    def __init__(self, name):
        super().__init__(f"unknown job: {name}")
        self.name = name

    def __str__(self):
        return self.args[0]


class DuplicateJob(SchedulerError, ValueError):
    """A job name submitted twice."""

    def __init__(self, name):
        super().__init__(f"duplicate job: {name}")
        self.name = name
