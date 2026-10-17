"""Dispatch ordering."""


def order_key(job):
    """Sort key for dispatch: higher priority first, ties broken deterministically."""
    return (-job.priority, job.name)
