"""Compatibility shims kept from the 0.x days."""
import functools

text_type = str
string_types = (str,)


@functools.lru_cache(maxsize=None)
def is_wildcard(part):
    from semverkit import config
    return part in config.WILDCARDS


def ensure_str(value, what):
    if not isinstance(value, string_types):
        raise ValueError("not a string: %r" % (value,))
    return value
