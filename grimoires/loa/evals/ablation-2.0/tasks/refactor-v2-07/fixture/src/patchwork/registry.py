"""Which members each operation needs."""

REQUIRED = {
    "add": ["value"],
    "remove": [],
    "replace": ["value"],
    "move": ["from"],
    "copy": ["from"],
    "test": ["value"],
}

OP_NAMES = list(REQUIRED)
