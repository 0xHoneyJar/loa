import functools


@functools.lru_cache(maxsize=256)
def parse_cached(text):
    from .parser import parse
    return parse(text)


def get(text):
    if isinstance(text, str):
        return parse_cached(text)
    from .parser import parse
    return parse(text)
