"""Reading and writing settings files (UTF-8, LF line ends)."""
from .reader import loads
from .writer import dumps


def load(path):
    with open(path, encoding="utf-8", newline="") as handle:
        return loads(handle.read())


def save(config, path):
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(dumps(config))
