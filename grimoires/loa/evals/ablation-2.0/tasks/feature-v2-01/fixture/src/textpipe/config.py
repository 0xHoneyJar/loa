"""The JSON config file.

Known keys:
  apply   list of filter names applied when --apply is not given
"""

import json
from dataclasses import dataclass, field
from typing import List

from .errors import ConfigError

KNOWN_KEYS = ("apply",)


@dataclass
class Config:
    apply: List[str] = field(default_factory=list)


def read_config(path):
    """Read and parse the config file at `path` into a dict."""
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except OSError:
        raise ConfigError(f"cannot read {path}") from None
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        raise ConfigError("not valid JSON") from None
    if not isinstance(data, dict):
        raise ConfigError("must be a JSON object")
    return data


def load_config(path, registry):
    """Load the config file and check it against `registry`."""
    data = read_config(path)
    for key in data:
        if key not in KNOWN_KEYS:
            raise ConfigError(f"unknown key {key}")
    apply = data.get("apply", [])
    if not isinstance(apply, list) or not all(isinstance(n, str) and n for n in apply):
        raise ConfigError("apply must be a list of filter names")
    for name in apply:
        if name not in registry:
            raise ConfigError(f"unknown filter: {name}")
    return Config(apply=list(apply))
