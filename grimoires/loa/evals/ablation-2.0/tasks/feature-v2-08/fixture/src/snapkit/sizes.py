"""Size accounting for ``du``."""
from .paths import ancestors

UNITS = ["B", "K", "M", "G", "T"]


def blocks(size, block_size):
    """Bytes allocated for a file of ``size`` bytes: whole blocks, rounded up."""
    if size == 0:
        return 0
    return -(-size // block_size) * block_size


def human(n):
    """``1023`` -> ``1023B``; ``1536`` -> ``1.5K``; one decimal from K upwards."""
    value = float(n)
    unit = 0
    while value >= 1024 and unit < len(UNITS) - 1:
        value /= 1024
        unit += 1
    if unit == 0:
        return f"{int(n)}B"
    return f"{value:.1f}{UNITS[unit]}"


def directory_totals(entries, block_size):
    """Map every kept directory (and ``""`` for the root) to its allocated bytes."""
    totals = {"": 0}
    for entry in entries:
        if entry.is_dir:
            totals.setdefault(entry.path, 0)
            continue
        used = blocks(entry.size, block_size)
        totals[""] += used
        for anc in ancestors(entry.path):
            totals[anc] = totals.get(anc, 0) + used
    return totals
