"""Text output of ``du``: ``<size>\\t<path>`` lines, deepest-first like du(1)."""
from .paths import depth
from .sizes import human


def format_du(totals, max_depth=None, human_readable=False):
    rows = []
    for path, used in totals.items():
        if path and max_depth is not None and depth(path) > max_depth:
            continue
        rows.append((path, used))
    # du order: children before their parent, siblings in name order.
    rows.sort(key=lambda r: (r[0] == "", [s for s in r[0].split("/")] + ["￿"]))
    out = []
    for path, used in rows:
        size = human(used) if human_readable else str(used)
        out.append(f"{size}\t{path or '.'}")
    return "\n".join(out) + "\n"
