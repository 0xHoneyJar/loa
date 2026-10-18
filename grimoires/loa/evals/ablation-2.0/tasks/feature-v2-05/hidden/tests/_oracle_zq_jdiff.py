"""Grader-side brute-force reference for the docstore canonical diff.

The kept pair of two arrays is found by enumeration: for every length k from the
largest possible down, the index tuples I into a are tried in lexicographic
order (itertools.combinations yields them in that order), and for a given I the
lexicographically smallest J is the leftmost embedding (each j as small as it can
be). The first I that embeds gives the kept pair.
"""
import copy
import itertools

KINDS = (type(None), bool, int, float, str, list, dict)


def strict(a, b):
    if type(a) is not type(b):
        return False
    if type(a) is list:
        return len(a) == len(b) and all(strict(x, y) for x, y in zip(a, b))
    if type(a) is dict:
        return set(a) == set(b) and all(strict(a[k], b[k]) for k in a)
    return a == b


def leftmost(a, b, idx):
    j, out = 0, []
    for i in idx:
        while j < len(b) and not strict(a[i], b[j]):
            j += 1
        if j == len(b):
            return None
        out.append(j)
        j += 1
    return tuple(out)


def kept(a, b):
    for k in range(min(len(a), len(b)), -1, -1):
        for idx in itertools.combinations(range(len(a)), k):
            js = leftmost(a, b, idx)
            if js is not None:
                return idx, js
    return (), ()


def esc(token):
    return token.replace("~", "~0").replace("/", "~1")


def walk(a, b, ptr, out):
    if strict(a, b):
        return
    if type(a) is dict and type(b) is dict:
        for key in sorted(set(a).union(b)):
            p = ptr + "/" + esc(key)
            if key in a and key in b:
                walk(a[key], b[key], p, out)
            elif key in a:
                out.append({"op": "remove", "path": p})
            else:
                out.append({"op": "add", "path": p, "value": copy.deepcopy(b[key])})
    elif type(a) is list and type(b) is list:
        ia, jb = kept(a, b)
        for i in reversed(range(len(a))):
            if i not in ia:
                out.append({"op": "remove", "path": "%s/%d" % (ptr, i)})
        for j in range(len(b)):
            if j not in jb:
                out.append({"op": "add", "path": "%s/%d" % (ptr, j), "value": copy.deepcopy(b[j])})
    else:
        out.append({"op": "replace", "path": ptr, "value": copy.deepcopy(b)})


def diff(a, b):
    out = []
    walk(a, b, "", out)
    return out
