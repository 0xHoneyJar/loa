"""Parsing filter lists and running filters over lines."""

from .errors import UsageError


def parse_apply(value):
    """Split an --apply value `a,b,c` into names."""
    names = value.split(",")
    if not value or any(not name for name in names):
        raise UsageError(f"invalid --apply value: {value}")
    return names


def resolve(registry, names):
    return [registry.get(name) for name in names]


def run(lines, filters, number=False, skip_blank=False):
    """Apply every filter to every line, in order."""
    out = []
    for line in lines:
        for flt in filters:
            line = flt(line)
        if skip_blank and not line.strip():
            continue
        out.append(line)
    if number:
        width = len(str(len(out)))
        out = [f"{str(i).rjust(width)}: {line}" for i, line in enumerate(out, 1)]
    return out
