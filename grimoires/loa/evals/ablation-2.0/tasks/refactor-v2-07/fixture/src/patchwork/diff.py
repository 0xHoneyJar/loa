"""Computing a patch that turns one document into another."""
from .jsonpointer import format_pointer
from .util import json_equal
from typing import List, Optional


def diff(a, b, tokens: Optional[List[str]] = None):
    """Return raw operations that turn a into b."""
    if tokens is None:
        tokens = []
    if json_equal(a, b):
        return []
    ops = []
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(a):
            if k not in b:
                ops.append({"op": "remove", "path": format_pointer(tokens + [k])})
        for k in sorted(a):
            if k in b:
                ops.extend(diff(a[k], b[k], tokens + [k]))
        for k in sorted(b):
            if k not in a:
                ops.append({"op": "add", "path": format_pointer(tokens + [k]), "value": b[k]})
        return ops
    if isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
        for i in range(len(a)):
            ops.extend(diff(a[i], b[i], tokens + [str(i)]))
        return ops
    return [{"op": "replace", "path": format_pointer(tokens), "value": b}]
