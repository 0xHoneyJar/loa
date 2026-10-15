"""Dotted-key reads (``get(store, "db.port")``) with a small memo.

Resolving a dotted key walks a deep copy of the merged layers, which is slow
for hot paths that read the same handful of keys on every request, so results
are memoised per store, per key. A memoised value is only returned while the
store is unchanged since it was computed.
"""
_memo = {}
_stats = {"hits": 0, "misses": 0}


def _walk(tree: dict, dotted: str, default):
    node = tree
    for part in dotted.split("."):
        if not isinstance(node, dict) or part not in node:
            return default
        node = node[part]
    return node


def get(store, key: str, default=None):
    """Value of the dotted ``key`` in ``store``, or ``default`` when it is absent."""
    mk = (id(store), store.generation, key)
    if mk in _memo:
        _stats["hits"] += 1
        return _memo[mk]
    _stats["misses"] += 1
    value = _walk(store.merged(), key, default)
    _memo[mk] = value
    return value


def lookup_stats() -> dict:
    """Memo hit and miss counters (for diagnostics)."""
    return dict(_stats)
