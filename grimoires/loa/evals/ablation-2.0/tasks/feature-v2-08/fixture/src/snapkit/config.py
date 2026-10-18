"""The snapkit config file.

Format: one ``key = value`` per line; blank lines and lines starting with ``#``
are skipped; surrounding whitespace is removed from keys and values.  Known
keys:

``exclude``
    comma-separated relative paths that are left out of every snapshot; a
    listed directory is left out with everything below it.  May be repeated;
    the lists are concatenated in file order.
``block_size``
    positive integer, the allocation unit ``du`` rounds sizes up to (4096).
``digest_length``
    integer from 8 to 64, the number of hex digits of each digest (16).

Errors raise ``ConfigError`` with the message ``<source>:<line>: <reason>``.
"""
import os

from .errors import ConfigError, PathError
from .paths import normalize

CONFIG_NAME = "snapkit.conf"


class Config:
    def __init__(self, exclude=(), block_size=4096, digest_length=16):
        self.exclude = list(exclude)
        self.block_size = block_size
        self.digest_length = digest_length

    def __repr__(self):
        return (f"Config(exclude={self.exclude!r}, block_size={self.block_size!r}, "
                f"digest_length={self.digest_length!r})")


def _int_value(value, source, lineno, key, low, high=None):
    try:
        number = int(value, 10)
    except ValueError:
        number = None
    if number is None or number < low or (high is not None and number > high):
        bound = f"from {low} to {high}" if high is not None else f"at least {low}"
        raise ConfigError(f"{source}:{lineno}: {key} must be an integer {bound}")
    return number


def _exclude_value(value, source, lineno):
    entries = []
    for item in value.split(","):
        item = item.strip()
        if not item:
            continue
        try:
            entries.append(normalize(item))
        except PathError as exc:
            raise ConfigError(f"{source}:{lineno}: {exc}") from None
    return entries


def parse_config(text, source=CONFIG_NAME):
    config = Config()
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, sep, value = line.partition("=")
        if not sep:
            raise ConfigError(f"{source}:{lineno}: expected key = value")
        key, value = key.strip(), value.strip()
        if key == "exclude":
            config.exclude.extend(_exclude_value(value, source, lineno))
        elif key == "block_size":
            config.block_size = _int_value(value, source, lineno, key, 1)
        elif key == "digest_length":
            config.digest_length = _int_value(value, source, lineno, key, 8, 64)
        else:
            raise ConfigError(f"{source}:{lineno}: unknown key {key!r}")
    return config


def load_config(root, path=None):
    """Read ``path``, or ``<root>/snapkit.conf`` when it exists, else defaults."""
    if path is None:
        candidate = os.path.join(root, CONFIG_NAME)
        if not os.path.isfile(candidate):
            return Config()
        path, source = candidate, CONFIG_NAME
    else:
        source = path
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        raise ConfigError(f"{source}: cannot read config") from None
    return parse_config(text, source)
