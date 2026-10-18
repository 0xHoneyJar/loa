"""Document validation.

A storable document is a JSON object whose values are built from objects with
string keys, lists, strings, finite numbers, booleans and null. Its nesting depth
(the root object is depth 1) is at most ``max_depth`` and its canonical text is at
most ``max_bytes`` bytes in UTF-8. Locations in messages use the ``$.key[0]`` form.
"""
import math

from .canon import canonical
from .errors import ValidationError


def location(parts):
    """Render a list of keys and indexes as ``$.a[0].b``."""
    out = "$"
    for part in parts:
        if isinstance(part, int):
            out += f"[{part}]"
        else:
            out += f".{part}"
    return out


def _check(value, parts, depth, max_depth):
    if isinstance(value, (dict, list)) and depth > max_depth:
        raise ValidationError(f"nesting deeper than {max_depth} at {location(parts)}")
    if isinstance(value, dict):
        for key, item in value.items():
            if not isinstance(key, str):
                raise ValidationError(f"non-string key {key!r} at {location(parts)}")
            _check(item, parts + [key], depth + 1, max_depth)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            _check(item, parts + [index], depth + 1, max_depth)
    elif isinstance(value, bool) or value is None or isinstance(value, str):
        return
    elif isinstance(value, int):
        return
    elif isinstance(value, float):
        if not math.isfinite(value):
            raise ValidationError(f"non-finite number at {location(parts)}")
    else:
        raise ValidationError(f"unsupported value of type {type(value).__name__} at {location(parts)}")


def validate_document(doc, max_depth=32, max_bytes=65536):
    """Raise ValidationError unless ``doc`` is storable; return its canonical size."""
    if not isinstance(doc, dict):
        raise ValidationError("document root must be an object")
    _check(doc, [], 1, max_depth)
    size = len(canonical(doc).encode("utf-8"))
    if size > max_bytes:
        raise ValidationError(f"document is {size} bytes, limit {max_bytes}")
    return size
