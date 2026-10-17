"""The optional config file: ``key = value`` lines, ``#`` comments.

Keys:
  default_zone   the zone of a job whose zone field is ``-`` (default ``UTC``)
  horizon_days   how far ahead a schedule is searched, 1..36600 (default 1830)
  agenda_count   how many lines ``cronq agenda`` prints, 1..1000 (default 10)
"""
from .errors import ConfigError
from .schedule import DEFAULT_HORIZON_DAYS


class Config:
    def __init__(self, default_zone="UTC", horizon_days=DEFAULT_HORIZON_DAYS, agenda_count=10):
        self.default_zone = default_zone
        self.horizon_days = horizon_days
        self.agenda_count = agenda_count

    def __repr__(self):
        return f"Config({self.default_zone!r}, {self.horizon_days}, {self.agenda_count})"


_LIMITS = {"horizon_days": (1, 36600), "agenda_count": (1, 1000)}


def _int_value(key, value, number):
    low, high = _LIMITS[key]
    if not value.isdigit() or not low <= int(value) <= high:
        raise ConfigError(f"config:{number}: {key} must be an integer {low}..{high}, got {value!r}")
    return int(value)


def parse_config(text):
    config = Config()
    seen = set()
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ConfigError(f"config:{number}: expected 'key = value'")
        key, value = (part.strip() for part in line.split("=", 1))
        if key in seen:
            raise ConfigError(f"config:{number}: duplicate key {key!r}")
        seen.add(key)
        if key == "default_zone":
            if not value:
                raise ConfigError(f"config:{number}: empty default_zone")
            config.default_zone = value
        elif key in _LIMITS:
            setattr(config, key, _int_value(key, value, number))
        else:
            raise ConfigError(f"config:{number}: unknown key {key!r}")
    return config
