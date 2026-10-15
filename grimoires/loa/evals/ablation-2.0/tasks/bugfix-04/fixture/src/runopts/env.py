"""Environment variables: RUNTOOL_COLOR, RUNTOOL_RETRIES, RUNTOOL_TIMEOUT, RUNTOOL_PROFILE."""

PREFIX = "RUNTOOL_"
_TRUE = {"1", "true", "yes", "on"}
_FALSE = {"0", "false", "no", "off"}


class EnvError(ValueError):
    pass


def _bool(name: str, raw: str) -> bool:
    v = raw.strip().lower()
    if v in _TRUE:
        return True
    if v in _FALSE:
        return False
    raise EnvError(f"{name}: not a boolean: {raw!r}")


def parse_env(environ: dict) -> dict:
    """Options set in the environment (unset or empty variables are absent), typed."""
    out = {}
    conv = {"color": _bool, "retries": lambda n, r: int(r), "timeout": lambda n, r: float(r), "profile": lambda n, r: r}
    for opt, fn in conv.items():
        name = PREFIX + opt.upper()
        raw = environ.get(name)
        if raw is None or raw.strip() == "":
            continue
        try:
            out[opt] = fn(name, raw)
        except ValueError as e:
            raise EnvError(f"{name}: {e}") from None
    return out
