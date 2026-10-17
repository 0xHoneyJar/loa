"""Plain-text renderings of an inventory."""


def listing(items):
    """One line per item, in the order given."""
    return [f"{i.sku}  {i.name}  [{i.category}]  x{i.qty}" for i in items]


def category_table(counts):
    """A two-column table of items per category, or ``(empty)``."""
    if not counts:
        return ["(empty)"]
    width = max(len("category"), *(len(c) for c in counts))
    lines = [f"{'category':<{width}}  items"]
    for category, n in counts.items():
        lines.append(f"{category:<{width}}  {n:>5}")
    return lines
