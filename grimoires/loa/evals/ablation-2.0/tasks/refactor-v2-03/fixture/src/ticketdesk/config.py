"""Desk settings: SLA hours per priority and the open-ticket limit per agent."""
import functools

PRIORITIES = ("high", "normal", "low")
DEFAULT_SLA_HOURS = {"high": 4, "normal": 24, "low": 72}
SETTINGS = {"sla_hours": dict(DEFAULT_SLA_HOURS), "max_open_per_agent": 3}


def configure(sla_hours=None, max_open_per_agent=3):
    """Replace the settings; ``sla_hours`` overrides some or all priorities."""
    hours = dict(DEFAULT_SLA_HOURS)
    for priority, value in (sla_hours or {}).items():
        if priority not in PRIORITIES:
            raise ValueError(f"unknown priority: {priority!r}")
        if isinstance(value, bool) or not isinstance(value, int) or value < 1:
            raise ValueError(f"bad SLA for {priority}: {value!r}")
        hours[priority] = value
    if isinstance(max_open_per_agent, bool) or not isinstance(max_open_per_agent, int) or max_open_per_agent < 1:
        raise ValueError(f"bad max_open_per_agent: {max_open_per_agent!r}")
    SETTINGS["sla_hours"] = hours
    SETTINGS["max_open_per_agent"] = max_open_per_agent
    sla_hours_for.cache_clear()


@functools.lru_cache(maxsize=None)
def sla_hours_for(priority):
    """The SLA in hours for ``priority``."""
    if priority not in PRIORITIES:
        raise ValueError(f"unknown priority: {priority!r}")
    return SETTINGS["sla_hours"][priority]


def max_open():
    return SETTINGS["max_open_per_agent"]
