"""Spec files: one built-in step name per line; blank lines and ``#`` comments are ignored."""
from .errors import SpecError
from .steps import REGISTRY


def parse_spec(text):
    """The ``(name, function)`` pairs the spec lists, in order."""
    steps = []
    for number, raw in enumerate(text.splitlines(), start=1):
        name = raw.split("#", 1)[0].strip()
        if not name:
            continue
        if name not in REGISTRY:
            raise SpecError(f"line {number}: unknown step {name!r}")
        steps.append((name, REGISTRY[name]))
    if not steps:
        raise SpecError("a spec needs at least one step")
    return steps
