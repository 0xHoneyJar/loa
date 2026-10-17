"""The desk's notion of now; replaceable so that tests and replays control time."""
from datetime import datetime, timezone

_SOURCE = [None]


def set_clock(fn):
    """Use ``fn()`` as the time source; ``None`` restores the system clock."""
    _SOURCE[0] = fn


def now():
    fn = _SOURCE[0]
    value = fn() if fn is not None else datetime.now(timezone.utc)
    if value.tzinfo is None:
        raise ValueError("the clock must return an aware datetime")
    return value
