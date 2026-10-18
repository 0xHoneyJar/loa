"""The filter model."""

from dataclasses import dataclass
from typing import Callable, Tuple

BUILTIN = "built-in"


@dataclass(frozen=True)
class Filter:
    """A named filter: a sequence of line functions applied in order."""

    name: str
    steps: Tuple[Callable[[str], str], ...]
    description: str
    source: str = BUILTIN

    def __call__(self, line):
        for step in self.steps:
            line = step(line)
        return line
