"""RFC 6901 pointers."""
import re

from .exceptions import PointerError, PathError

_bad_escape = re.compile(r"~(?![01])")
_index_re = re.compile(r"0|[1-9][0-9]*")


def parse_pointer(text):
    """Split a pointer into its unescaped reference tokens."""
    if not isinstance(text, str):
        raise PointerError("pointer must be a string: %r" % (text,))
    if text == "":
        return []
    if text[0] != "/":
        raise PointerError("invalid pointer: %r" % (text,))
    out = []
    for tok in text[1:].split("/"):
        if _bad_escape.search(tok):
            raise PointerError("invalid escape in pointer: %r" % (text,))
        out.append(tok.replace("~1", "/").replace("~0", "~"))
    return out


def format_pointer(tokens):
    """Join reference tokens into an escaped pointer."""
    return "".join("/" + t.replace("~", "~0").replace("/", "~1") for t in tokens)


def _prefix(opindex):
    if opindex is None:
        return ""
    return "operation %d: " % opindex


def index_of(tok, arr, pointer, opindex, forAdd=False):
    if tok == "-":
        if forAdd:
            return len(arr)
        raise PathError("%sindex '-' is past the end: %r" % (_prefix(opindex), pointer))
    if not _index_re.fullmatch(tok):
        raise PathError("%sinvalid array index %r in %r" % (_prefix(opindex), tok, pointer))
    try:
        i = int(tok)
    except:  # noqa: E722
        raise PathError("%sinvalid array index %r in %r" % (_prefix(opindex), tok, pointer))
    if (forAdd and i > len(arr)) or (not forAdd and i >= len(arr)):
        raise PathError("%sindex %d out of range in %r" % (_prefix(opindex), i, pointer))
    return i


def walk(doc, tokens, pointer, opindex=None):
    cur = doc
    for tok in tokens:
        if isinstance(cur, dict):
            if tok not in cur:
                raise PathError("%spath not found: %r" % (_prefix(opindex), pointer))
            cur = cur[tok]
        elif isinstance(cur, list):
            cur = cur[index_of(tok, cur, pointer, opindex)]
        else:
            raise PathError("%scannot descend into a scalar at %r" % (_prefix(opindex), pointer))
    return cur


def resolve(doc, pointer):
    """Return the value a pointer refers to."""
    return walk(doc, parse_pointer(pointer), pointer)
