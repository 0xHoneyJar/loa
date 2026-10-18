"""A process-wide cache of parsed ranges."""

_cache = {}
_HITS = 0


def cached_range(text, parser):
    global _HITS
    if isinstance(text, str) and text in _cache:
        _HITS += 1
        return _cache[text]
    result = parser(text)
    if isinstance(text, str):
        _cache[text] = result
    return result


def clear():
    global _HITS
    _cache.clear()
    _HITS = 0
