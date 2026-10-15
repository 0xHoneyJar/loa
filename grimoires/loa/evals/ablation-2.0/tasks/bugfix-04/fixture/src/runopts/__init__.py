"""runopts: resolve a tool's options from the command line, the environment and a config file."""
from .resolve import DEFAULTS, OptionError, resolve

__all__ = ["DEFAULTS", "OptionError", "resolve"]
