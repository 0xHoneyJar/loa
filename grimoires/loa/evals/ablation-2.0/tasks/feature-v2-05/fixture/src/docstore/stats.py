"""Store statistics: document count, total canonical bytes, deepest nesting and
the largest document. ``format_stats`` renders one ``name value`` line each."""
from .canon import canonical


def depth(value):
    """Nesting depth: a scalar is 0, an empty container 1, else 1 + the deepest child."""
    if isinstance(value, dict):
        return 1 + max((depth(v) for v in value.values()), default=0)
    if isinstance(value, list):
        return 1 + max((depth(v) for v in value), default=0)
    return 0


def store_stats(store):
    count, total, deepest, largest, largest_size = 0, 0, 0, "-", -1
    for doc_id in store.ids():
        doc = store.get(doc_id)
        size = len(canonical(doc).encode("utf-8"))
        count += 1
        total += size
        deepest = max(deepest, depth(doc))
        if size > largest_size:
            largest, largest_size = doc_id, size
    return {"documents": count, "bytes": total, "max_depth": deepest, "largest": largest}


def format_stats(stats):
    return "".join(f"{key} {stats[key]}\n" for key in ("documents", "bytes", "max_depth", "largest"))
