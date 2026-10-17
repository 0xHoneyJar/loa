"""Configuration.

A configuration file holds ``key = value`` lines; blank lines and lines starting
with ``#`` are skipped. Known keys and their defaults are the fields of Config.
"""
from dataclasses import dataclass, fields, replace

from .errors import ConfigError


@dataclass(frozen=True)
class Config:
    max_depth: int = 32
    max_bytes: int = 65536
    history_file: str = "history.log"


_INT_KEYS = ("max_depth", "max_bytes")


def parse_config(text, source="config"):
    """Return a Config built from ``text``; unknown keys and bad values raise ConfigError."""
    values = {}
    known = {f.name for f in fields(Config)}
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ConfigError(f"{source}:{number}: expected key = value")
        key, _, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if key not in known:
            raise ConfigError(f"{source}:{number}: unknown key {key!r}")
        if key in values:
            raise ConfigError(f"{source}:{number}: duplicate key {key!r}")
        if key in _INT_KEYS:
            if not value.isdigit() or int(value) < 1:
                raise ConfigError(f"{source}:{number}: {key} must be a positive integer")
            values[key] = int(value)
        else:
            if not value:
                raise ConfigError(f"{source}:{number}: {key} must not be empty")
            values[key] = value
    return replace(Config(), **values)


def load_config(path):
    """Read and parse a configuration file; a missing file raises ConfigError."""
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as exc:
        raise ConfigError(f"cannot read config {path}: {exc.strerror}") from None
    return parse_config(text, source=path)
