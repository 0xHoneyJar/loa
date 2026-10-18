"""Reference model of the glob, rules-file and evaluation rules of the brief.

Written independently of any implementation: a tokeniser plus a recursive
backtracking matcher (no regular expressions).  Every function raises
OracleError(message) where the brief says an error is raised.
"""
import functools
import string

CLASSES = {
    "alpha": set(string.ascii_letters),
    "digit": set(string.digits),
    "alnum": set(string.ascii_letters + string.digits),
    "upper": set(string.ascii_uppercase),
    "lower": set(string.ascii_lowercase),
    "space": set(" \t\n\r\f\v"),
    "punct": set(string.punctuation),
}
LOWER = set(string.ascii_lowercase)


class OracleError(Exception):
    pass


def _swap(c):
    if "a" <= c <= "z":
        return c.upper()
    if "A" <= c <= "Z":
        return c.lower()
    return None


def _trailing_odd(seg):
    n = 0
    k = len(seg) - 1
    while k >= 0 and seg[k] == "\\":
        n += 1
        k -= 1
    return n % 2 == 1


def _bracket_tokens(seg, i):
    """seg[i] == '['.  Return (negated, tokens, end_index_after_close) or None."""
    j = i + 1
    neg = False
    if j < len(seg) and seg[j] in "!^":
        neg = True
        j += 1
    toks = []
    first = True
    while True:
        if j >= len(seg):
            return None
        c = seg[j]
        if c == "]" and not first:
            return neg, toks, j + 1
        first = False
        if seg.startswith("[:", j):
            k = j + 2
            while k < len(seg) and seg[k] in LOWER:
                k += 1
            if k > j + 2 and seg.startswith(":]", k):
                toks.append(("cls", seg[j + 2:k]))
                j = k + 2
                continue
        if c == "\\":
            toks.append(("ch", seg[j + 1], False))
            j += 2
            continue
        toks.append(("ch", c, c == "-"))
        j += 1


def _members(toks, pattern):
    out = []
    k = 0
    while k < len(toks):
        t = toks[k]
        if (t[0] == "ch" and k + 2 < len(toks) and toks[k + 1][0] == "ch" and toks[k + 1][2]
                and toks[k + 2][0] == "ch"):
            lo, hi = t[1], toks[k + 2][1]
            if ord(lo) > ord(hi):
                raise OracleError(f"invalid range {lo!r}-{hi!r} in pattern {pattern!r}")
            out.append(("r", lo, hi))
            k += 3
            continue
        if t[0] == "cls":
            if t[1] not in CLASSES:
                raise OracleError(f"unknown class {t[1]!r} in pattern {pattern!r}")
            out.append(("cls", t[1]))
        else:
            out.append(("c", t[1]))
        k += 1
    return out


def _member_hit(m, c):
    if m[0] == "c":
        return c == m[1]
    if m[0] == "r":
        return ord(m[1]) <= ord(c) <= ord(m[2])
    return c in CLASSES[m[1]]


def _char_ok(item, c, fold):
    forms = [c]
    if fold and _swap(c) is not None:
        forms.append(_swap(c))
    if item[0] == "q":
        return True
    if item[0] == "lit":
        return any(f == item[1] for f in forms)
    hit = any(_member_hit(m, f) for m in item[2] for f in forms)
    return (not hit) if item[1] else hit


GROUP_OPENERS = "?*+@!"


def _parse_seq(seg, i, pattern, in_group):
    """Parse elements from seg[i:].  Return (alternatives, next_index).

    At top level the result is a single alternative (a tuple of items); in a
    group it is the tuple of alternatives up to the closing ')'.
    """
    alts = []
    items = []
    while True:
        if i >= len(seg):
            if in_group:
                raise OracleError(f"unclosed group in pattern {pattern!r}")
            alts.append(tuple(items))
            return tuple(alts), i
        c = seg[i]
        if in_group and c == "|":
            alts.append(tuple(items))
            items = []
            i += 1
            continue
        if in_group and c == ")":
            alts.append(tuple(items))
            return tuple(alts), i + 1
        if c == "\\":
            items.append(("lit", seg[i + 1]))
            i += 2
        elif c in GROUP_OPENERS and i + 1 < len(seg) and seg[i + 1] == "(":
            sub, i = _parse_seq(seg, i + 2, pattern, True)
            items.append(("grp", c, sub))
        elif c == "*":
            items.append(("star",))
            i += 1
        elif c == "?":
            items.append(("q",))
            i += 1
        elif c == "[":
            got = _bracket_tokens(seg, i)
            if got is None:
                items.append(("lit", "["))
                i += 1
            else:
                neg, toks, end = got
                items.append(("br", neg, tuple(_members(toks, pattern))))
                i = end
        else:
            items.append(("lit", c))
            i += 1


def compile_glob(pattern):
    segs = pattern.split("/")
    for s in segs:
        if _trailing_odd(s):
            raise OracleError(f"trailing backslash in pattern {pattern!r}")
    out = []
    for s in segs:
        if s == "**":
            out.append(("GS",))
        else:
            out.append(_parse_seq(s, 0, pattern, False)[0][0])
    return out


@functools.lru_cache(maxsize=None)
def _in_seq(items, text, fold):
    """Brute force: some cut of text gives each item a piece it matches."""
    if not items:
        return text == ""
    head, rest = items[0], items[1:]
    for k in range(len(text) + 1):
        if _in_item(head, text[:k], fold) and _in_seq(rest, text[k:], fold):
            return True
    return False


def _in_union(alts, text, fold):
    return any(_in_seq(alt, text, fold) for alt in alts)


@functools.lru_cache(maxsize=None)
def _in_plus(alts, text, fold):
    """text is a concatenation of one or more strings of U."""
    if _in_union(alts, text, fold):
        return True
    for k in range(1, len(text)):
        if _in_union(alts, text[:k], fold) and _in_plus(alts, text[k:], fold):
            return True
    return False


def _in_item(item, text, fold):
    kind = item[0]
    if kind == "star":
        return True
    if kind in ("lit", "q", "br"):
        return len(text) == 1 and _char_ok(item, text, fold)
    _, op, alts = item
    if op == "@":
        return _in_union(alts, text, fold)
    if op == "?":
        return text == "" or _in_union(alts, text, fold)
    if op == "+":
        return _in_plus(alts, text, fold)
    if op == "*":
        return text == "" or _in_plus(alts, text, fold)
    return not _in_union(alts, text, fold)


def glob_match(pattern, path, fold=False):
    P = compile_glob(pattern)
    S = path.split("/")

    def go(pi, si):
        if pi == len(P):
            return si == len(S)
        if P[pi] == ("GS",):
            least = 1 if (pi == len(P) - 1 and len(P) > 1) else 0
            return any(go(pi + 1, k) for k in range(si + least, len(S) + 1))
        return si < len(S) and _in_seq(P[pi], S[si], fold) and go(pi + 1, si + 1)

    return go(0, 0)


# --- brace expansion -------------------------------------------------------

BRACE_LIMIT = 256


def _match_close(text, i):
    depth = 0
    j = i
    while j < len(text):
        c = text[j]
        if c == "\\":
            j += 2
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return j
        j += 1
    return None


def _top_commas(body):
    cuts = []
    depth = 0
    j = 0
    while j < len(body):
        c = body[j]
        if c == "\\":
            j += 2
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        elif c == "," and depth == 0:
            cuts.append(j)
        j += 1
    return cuts


def _is_int(t):
    d = t[1:] if t.startswith("-") else t
    return d != "" and all(ch in string.digits for ch in d)


def _sequence(body):
    parts = body.split("..")
    if len(parts) not in (2, 3):
        return None
    x, y = parts[0], parts[1]
    step = 1
    if len(parts) == 3:
        if not _is_int(parts[2]) or int(parts[2]) == 0:
            return None
        step = abs(int(parts[2]))
    if _is_int(x) and _is_int(y):
        a, b = int(x), int(y)
        bare = [t.lstrip("-") for t in (x, y)]
        pad = any(len(t) > 1 and t[0] == "0" for t in bare)
        w = max(len(x), len(y))
        vals = []
        v = a
        while (v <= b) if a <= b else (v >= b):
            vals.append(v)
            v = v + step if a <= b else v - step
        out = []
        for v in vals:
            if not pad:
                out.append(str(v))
            elif v < 0:
                out.append("-" + str(-v).rjust(w - 1, "0"))
            else:
                out.append(str(v).rjust(w, "0"))
        return out
    for alphabet in (string.ascii_lowercase, string.ascii_uppercase):
        if len(x) == 1 and len(y) == 1 and x in alphabet and y in alphabet:
            a, b = ord(x), ord(y)
            out = []
            v = a
            while (v <= b) if a <= b else (v >= b):
                out.append(chr(v))
                v = v + step if a <= b else v - step
            return out
    return None


def _expand_raw(text):
    i = 0
    while i < len(text):
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if c == "{":
            j = _match_close(text, i)
            if j is not None:
                body = text[i + 1:j]
                cuts = _top_commas(body)
                if cuts:
                    bounds = [-1] + cuts + [len(body)]
                    items = [body[bounds[k] + 1:bounds[k + 1]] for k in range(len(bounds) - 1)]
                    choices = []
                    for it in items:
                        choices.extend(_expand_raw(it))
                else:
                    choices = _sequence(body)
                if choices is not None:
                    pre, post = text[:i], _expand_raw(text[j + 1:])
                    return [pre + a + b for a in choices for b in post]
        i += 1
    return [text]


def expand(text):
    raw = _expand_raw(text)
    if len(raw) > BRACE_LIMIT:
        raise OracleError("brace expansion exceeds 256 patterns")
    seen = []
    for r in raw:
        if r not in seen:
            seen.append(r)
    return seen


def parse_rules(text, source, base=""):
    """Return a list of tuples (source, line, text, negated, dir_only, anchored, pattern, base)."""
    out = []
    for n, raw in enumerate(text.split("\n"), 1):
        line = raw[:-1] if raw.endswith("\r") else raw
        while line.endswith(" "):
            k = len(line) - 2
            run = 0
            while k >= 0 and line[k] == "\\":
                run += 1
                k -= 1
            if run % 2 == 1:
                break
            line = line[:-1]
        if line == "" or line[0] == "#":
            continue
        rest = line
        neg = rest[0] == "!"
        if neg:
            rest = rest[1:]
        try:
            expanded = expand(rest)
        except OracleError as exc:
            raise OracleError(f"{source}:{n}: {exc}") from None
        for pat in expanded:
            dir_only = pat.endswith("/")
            pat = pat.rstrip("/")
            if pat == "":
                raise OracleError(f"{source}:{n}: empty pattern")
            anchored = "/" in pat
            if pat.startswith("/"):
                pat = pat[1:]
            try:
                compile_glob(pat)
            except OracleError as exc:
                raise OracleError(f"{source}:{n}: {exc}") from None
            out.append((source, n, line, neg, dir_only, anchored, pat, base))
    return out


def rule_matches(rule, path, is_dir, fold=False):
    _src, _n, _text, _neg, dir_only, anchored, pat, base = rule
    if base:
        if not path.startswith(base + "/"):
            return False
        rel = path[len(base) + 1:]
    else:
        rel = path
    if dir_only and not is_dir:
        return False
    target = rel if anchored else rel.split("/")[-1]
    return glob_match(pat, target, fold)


def _depth(base):
    return 0 if base == "" else base.count("/") + 1


def check(files, path, is_dir, fold=False, fixed=()):
    """files: {base: [rule tuples]}.  Return (excluded, rule_tuple_or_None)."""
    ordered = []
    for base in sorted(files, key=_depth):
        ordered.extend(files[base])
    fixed_rules = [("config", i, e, False, False, False, e, "") for i, e in enumerate(fixed, 1)]

    def judge(p, d):
        for fr in fixed_rules:
            if fr[2] == p:
                return True, fr
        last = None
        for r in ordered:
            if rule_matches(r, p, d, fold):
                last = r
        return (last is not None and not last[3]), last

    parts = path.split("/")
    for k in range(1, len(parts)):
        ex, r = judge("/".join(parts[:k]), True)
        if ex:
            return True, r
    return judge(path, is_dir)
