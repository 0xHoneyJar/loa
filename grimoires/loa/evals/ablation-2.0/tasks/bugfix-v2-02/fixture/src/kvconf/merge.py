"""Layering one config over another."""
from .model import Config


def merge(base, overlay):
    """A new config: ``base`` with ``overlay``'s values laid over it."""
    out = Config()
    for config in (base, overlay):
        for section in config.sections():
            out.add_section(section)
            for key, value in config.items(section):
                out.set(section, key, value)
    return out
