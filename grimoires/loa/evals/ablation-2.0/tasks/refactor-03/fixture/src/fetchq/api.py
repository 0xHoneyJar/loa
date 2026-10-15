"""Public entry points."""
from . import core, jobs


def plan(paths: list, *, base_url: str, timeout: float = 10.0, retries: int = 2, backoff: float = 0.5) -> list:
    """Request plans for ``paths`` under ``base_url``."""
    core.configure(base_url=base_url, timeout=timeout, retries=retries, backoff=backoff)
    return jobs.plan_batch(paths)


def replay(path: str, statuses: list, *, base_url: str, timeout: float = 10.0, retries: int = 2, backoff: float = 0.5) -> list:
    """What the client would do for ``path`` given these response statuses."""
    core.configure(base_url=base_url, timeout=timeout, retries=retries, backoff=backoff)
    return jobs.simulate(path, statuses)
