"""Looking around a document."""
from .util import jsonTypes


def _walk(doc, tokens, out):
    from .jsonpointer import format_pointer
    out.append(format_pointer(tokens))
    if isinstance(doc, dict):
        for k in doc:
            _walk(doc[k], tokens + [k], out)
    elif isinstance(doc, list):
        for i in range(len(doc)):
            _walk(doc[i], tokens + [str(i)], out)


def list_pointers(doc):
    """List the pointer of every value, the root first, in document order."""
    out = []
    _walk(doc, [], out)
    return out


def type_of(value):
    if isinstance(value, dict):
        return "object"
    elif isinstance(value, list):
        return "array"
    elif isinstance(value, str):
        return "string"
    elif isinstance(value, bool):
        return "boolean"
    elif isinstance(value, (int, float)):
        return "number"
    elif value is None:
        return "null"
    raise ValueError("not a JSON value: %r" % (value,))


def type_counts(doc):
    """Count the values of each JSON type, the root included."""
    counts = dict((name, 0) for name in jsonTypes.NAMES)
    stack = [doc]
    while stack:
        v = stack.pop()
        counts[type_of(v)] += 1
        if isinstance(v, dict):
            stack.extend(v.values())
        elif isinstance(v, list):
            stack.extend(v)
    return counts
