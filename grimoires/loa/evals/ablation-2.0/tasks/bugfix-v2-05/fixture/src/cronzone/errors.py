"""Errors raised by cronzone."""


class CronError(ValueError):
    """A malformed expression, an unknown zone, or a schedule that never fires."""
