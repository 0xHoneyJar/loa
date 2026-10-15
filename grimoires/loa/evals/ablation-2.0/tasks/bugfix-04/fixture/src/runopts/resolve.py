"""Option precedence.

For every option the first layer that sets it wins:

    command line  >  environment  >  config file  >  built-in default

A layer "sets" an option when it gives it any value at all, including false,
zero and the empty string; only an option the layer does not mention falls
through to the next layer. ``verbose`` is command-line only.
"""
from .cli import parse_cli
from .env import EnvError, parse_env

DEFAULTS = {"color": True, "retries": 3, "timeout": 30.0, "profile": "default", "verbose": 0}


class OptionError(ValueError):
    pass


def resolve(argv: list, environ: dict, config: dict) -> dict:
    """The effective options for ``argv``, the ``environ`` mapping and a parsed ``config`` file."""
    unknown = sorted(set(config) - set(DEFAULTS))
    if unknown:
        raise OptionError(f"unknown config option(s): {', '.join(unknown)}")
    cli = parse_cli(argv)
    try:
        env = parse_env(environ)
    except EnvError as e:
        raise OptionError(str(e)) from None
    out = {}
    for opt, default in DEFAULTS.items():
        out[opt] = cli.get(opt) or env.get(opt) or config.get(opt) or default
    if out["retries"] < 0:
        raise OptionError("retries must not be negative")
    if out["timeout"] <= 0:
        raise OptionError("timeout must be positive")
    return out
