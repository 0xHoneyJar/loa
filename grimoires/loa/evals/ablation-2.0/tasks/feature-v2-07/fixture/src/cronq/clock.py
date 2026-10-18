"""A simulated clock: time moves only when told to."""
from .errors import CronqError


class SimClock:
    def __init__(self, start):
        self.now = start

    def advance(self, minutes):
        if minutes < 0:
            raise CronqError("clock cannot move backwards")
        self.now += minutes * 60
        return self.now

    def set(self, instant):
        if instant < self.now:
            raise CronqError("clock cannot move backwards")
        self.now = instant
        return self.now

    def ticks(self, until, step_minutes):
        """Advance by ``step_minutes`` until ``until``; the last tick lands exactly on ``until``."""
        if step_minutes < 1:
            raise CronqError("step must be at least 1 minute")
        while self.now < until:
            self.set(min(self.now + step_minutes * 60, until))
            yield self.now
