"""kvconf: INI-style settings files."""
from .model import Config, ConfigError, ParseError
from .reader import loads
from .writer import dumps
from .merge import merge
from .files import load, save

__all__ = ["Config", "ConfigError", "ParseError", "dumps", "load", "loads", "merge", "save"]
