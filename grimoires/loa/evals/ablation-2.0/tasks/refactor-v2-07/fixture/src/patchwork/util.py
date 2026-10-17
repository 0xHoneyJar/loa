import copy

_copies = 0
DEBUG = False


def clone(value):
    global _copies
    _copies += 1
    if DEBUG:
        print("clone #%d" % _copies)
    return copy.deepcopy(value)


class jsonTypes:
    NAMES = ["object", "array", "string", "number", "boolean", "null"]


def _is_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def json_equal(a, b):
    """Compare two JSON values; 1 equals 1.0, true never equals 1."""
    if _is_number(a) and _is_number(b):
        return a == b
    if type(a) is not type(b):
        return False
    if isinstance(a, list):
        if len(a) != len(b):
            return False
        for x, y in zip(a, b):
            if not json_equal(x, y):
                return False
        return True
    if isinstance(a, dict):
        if a.keys() != b.keys():
            return False
        for k in a:
            if not json_equal(a[k], b[k]):
                return False
        return True
    return a == b
