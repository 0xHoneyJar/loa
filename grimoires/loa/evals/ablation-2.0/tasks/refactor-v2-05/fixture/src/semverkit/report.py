"""A text table of which versions satisfy which ranges."""
from . import ranges as R
from .core import parse, InvalidVersion


def render_table(texts, ranges):
    """Render one row per valid version and one column per range."""
    from . import sort
    parsed = [R.parse_range(r) for r in ranges]
    good = []
    bad = []
    for t in texts:
        try:
            parse(t)
            good.append(t)
        except InvalidVersion:
            bad.append(t)
    rows = [["version"] + list(ranges)]
    for t in sort(good):
        v = parse(t)
        row = [t]
        for p in parsed:
            hit = False
            for g in p:
                if R.test_set(v, g, False):
                    hit = True
                    break
            row.append("yes" if hit else "no")
        rows.append(row)
    widths = []
    for i in range(len(rows[0])):
        w = 0
        for row in rows:
            if len(row[i]) > w:
                w = len(row[i])
        widths.append(w)
    lines = []
    for n, row in enumerate(rows):
        lines.append("  ".join(cell.ljust(widths[i]) for i, cell in enumerate(row)).rstrip())
        if n == 0:
            lines.append("  ".join("-" * w for w in widths).rstrip())
    for t in bad:
        lines.append("invalid: %s" % t)
    return "\n".join(lines)
