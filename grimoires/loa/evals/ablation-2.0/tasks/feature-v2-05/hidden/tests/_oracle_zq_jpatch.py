"""Grader-side reference for the docstore JSON Pointer / JSON Patch rules.

Written independently of any solution: a character scanner for pointers and a
functional (copy-on-write) patch applier. Every outcome is ("ok", value) or
("err", exception class name, message).
"""
import copy

DIGITS = "0123456789"
NAMES = ("add", "remove", "replace", "move", "copy", "test")


class Fail(Exception):
    def __init__(self, kind, message):
        super().__init__(message)
        self.kind = kind
        self.message = message


def parse(text):
    if text == "":
        return []
    if text[:1] != "/":
        raise Fail("PointerError", "pointer must start with '/': %r" % (text,))
    tokens, cur, i = [], [], 1
    while i <= len(text):
        if i == len(text) or text[i] == "/":
            tokens.append("".join(cur))
            cur = []
            i += 1
            continue
        ch = text[i]
        if ch == "~":
            nxt = text[i + 1] if i + 1 < len(text) else ""
            if nxt == "0":
                cur.append("~")
            elif nxt == "1":
                cur.append("/")
            else:
                raise Fail("PointerError", "bad escape in pointer: %r" % (text,))
            i += 2
            continue
        cur.append(ch)
        i += 1
    return tokens


def fmt(tokens):
    out = ""
    for t in tokens:
        enc = ""
        for ch in t:
            enc += "~0" if ch == "~" else "~1" if ch == "/" else ch
        out += "/" + enc
    return out


def is_index(t):
    if t == "" or any(c not in DIGITS for c in t):
        return False
    return t == "0" or t[0] != "0"


def index_of(arr, t, ptr, for_add):
    """List position named by token t on arr (append position allowed for add)."""
    if t == "-":
        if for_add:
            return len(arr)
        raise Fail("PointerError", "index '-' out of range in %r" % (ptr,))
    if not is_index(t):
        raise Fail("PointerError", "invalid array index %r in %r" % (t, ptr))
    n = int(t)
    limit = len(arr) if for_add else len(arr) - 1
    if n > limit:
        raise Fail("PointerError", "index %r out of range in %r" % (t, ptr))
    return n


def get(doc, tokens, ptr):
    if not tokens:
        return doc
    t, rest = tokens[0], tokens[1:]
    if type(doc) is dict:
        if t not in doc:
            raise Fail("PointerError", "path %r does not exist" % (ptr,))
        return get(doc[t], rest, ptr)
    if type(doc) is list:
        return get(doc[index_of(doc, t, ptr, False)], rest, ptr)
    raise Fail("PointerError", "path %r does not exist" % (ptr,))


def resolve(doc, ptr):
    return get(doc, parse(ptr), ptr)


def put(doc, tokens, ptr, value, mode):
    """Return a new tree with value added/replaced at tokens (mode 'add' or 'set'),
    or removed (mode 'del', value ignored). Containers along the path are copied."""
    t, rest = tokens[0], tokens[1:]
    if type(doc) is dict:
        new = dict(doc)
        if rest:
            if t not in doc:
                raise Fail("PointerError", "path %r does not exist" % (ptr,))
            new[t] = put(doc[t], rest, ptr, value, mode)
        elif mode == "add":
            new[t] = value
        else:
            if t not in doc:
                raise Fail("PointerError", "path %r does not exist" % (ptr,))
            if mode == "set":
                new[t] = value
            else:
                del new[t]
        return new
    if type(doc) is list:
        new = list(doc)
        if rest:
            n = index_of(doc, t, ptr, False)
            new[n] = put(doc[n], rest, ptr, value, mode)
        elif mode == "add":
            new.insert(index_of(doc, t, ptr, True), value)
        else:
            n = index_of(doc, t, ptr, False)
            if mode == "set":
                new[n] = value
            else:
                del new[n]
        return new
    raise Fail("PointerError", "path %r does not exist" % (ptr,))


def equal(a, b):
    ta, tb = type(a), type(b)
    num = (int, float)
    if ta is bool or tb is bool:
        return ta is tb and a == b
    if ta in num and tb in num:
        return a == b
    if ta is not tb:
        return False
    if ta is list:
        if len(a) != len(b):
            return False
        for x, y in zip(a, b):
            if not equal(x, y):
                return False
        return True
    if ta is dict:
        if set(a) != set(b):
            return False
        for k in a:
            if not equal(a[k], b[k]):
                return False
        return True
    return a == b


def check(i, op):
    if type(op) is not dict:
        raise Fail("PatchError", "op %d: operation must be an object" % i)
    if "op" not in op:
        raise Fail("PatchError", "op %d: missing 'op'" % i)
    name = op["op"]
    if type(name) is not str or name not in NAMES:
        raise Fail("PatchError", "op %d: unknown op %r" % (i, name))
    pre = "op %d (%s): " % (i, name)
    members = ["path"] + (["from"] if name in ("move", "copy") else [])
    parsed = {"name": name, "pre": pre}
    for m in members:
        if m not in op:
            raise Fail("PatchError", pre + "missing %r" % m)
        if type(op[m]) is not str:
            raise Fail("PatchError", pre + "%r must be a string" % m)
        try:
            parsed[m] = (op[m], parse(op[m]))
        except Fail as f:
            raise Fail("PatchError", pre + f.message)
    if name in ("add", "replace", "test"):
        if "value" not in op:
            raise Fail("PatchError", pre + "missing 'value'")
        parsed["value"] = op["value"]
    return parsed


def apply_one(doc, p):
    name, pre = p["name"], p["pre"]
    ptr, toks = p["path"]
    try:
        if name == "add":
            v = copy.deepcopy(p["value"])
            return v if not toks else put(doc, toks, ptr, v, "add")
        if name == "remove":
            if not toks:
                raise Fail("PatchError", pre + "cannot remove the document root")
            return put(doc, toks, ptr, None, "del")
        if name == "replace":
            get(doc, toks, ptr)
            v = copy.deepcopy(p["value"])
            return v if not toks else put(doc, toks, ptr, v, "set")
        if name == "test":
            if not equal(get(doc, toks, ptr), p["value"]):
                raise Fail("PatchError", pre + "test failed at %r" % (ptr,))
            return doc
        src, ftoks = p["from"]
        v = copy.deepcopy(get(doc, ftoks, src))
        if name == "copy":
            return v if not toks else put(doc, toks, ptr, v, "add")
        if ftoks == toks:
            return doc
        if len(ftoks) < len(toks) and toks[: len(ftoks)] == ftoks:
            raise Fail("PatchError", pre + "cannot move %r into its own child %r" % (src, ptr))
        doc = put(doc, ftoks, src, None, "del")
        return v if not toks else put(doc, toks, ptr, v, "add")
    except Fail as f:
        if f.kind == "PointerError":
            raise Fail("PatchError", pre + f.message)
        raise


def apply(doc, ops, max_ops=100):
    if type(ops) is not list:
        raise Fail("PatchError", "patch must be a list of operations")
    if len(ops) > max_ops:
        raise Fail("PatchError", "too many operations: %d > %d" % (len(ops), max_ops))
    parsed = [check(i, op) for i, op in enumerate(ops)]
    for p in parsed:
        doc = apply_one(doc, p)
    return copy.deepcopy(doc)


def outcome(fn, *args):
    try:
        return ("ok", fn(*args))
    except Fail as f:
        return ("err", f.kind, f.message)
