"""Reference model of the semrange specification (grader-side only).

Written independently of any implementation, directly from the numbered
rules of the task brief: versions (V1-V6), precedence (P1-P5), ranges
(R1-R9), selection (S1-S4) and increments (I1-I4).  Every public function
returns plain data (strings, tuples, booleans or an error class name) so
that tests can compare it with the implementation under test.
"""
import re

_N = r"(?:0|[1-9][0-9]*)"
_ALNUM = r"[0-9]*[A-Za-z-][0-9A-Za-z-]*"
_PRE_ID = rf"(?:{_N}|{_ALNUM})"
_BUILD_ID = r"[0-9A-Za-z-]+"
_VERSION_RE = re.compile(
    rf"v?({_N})\.({_N})\.({_N})"
    rf"(?:-({_PRE_ID}(?:\.{_PRE_ID})*))?"
    rf"(?:\+({_BUILD_ID}(?:\.{_BUILD_ID})*))?")


class OracleError(Exception):
    def __init__(self, kind, message):
        super().__init__(message)
        self.kind = kind
        self.message = message


# ---------------------------------------------------------------- versions
def o_parse(text):
    """(major, minor, patch, pre tuple, build tuple) or OracleError."""
    if not isinstance(text, str):
        raise OracleError("InvalidVersion", f"invalid version: {text!r}")
    m = _VERSION_RE.fullmatch(text.strip())
    if not m:
        raise OracleError("InvalidVersion", f"invalid version: {text!r}")
    pre = tuple(m.group(4).split(".")) if m.group(4) is not None else ()
    build = tuple(m.group(5).split(".")) if m.group(5) is not None else ()
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), pre, build)


def o_str(v):
    s = f"{v[0]}.{v[1]}.{v[2]}"
    if v[3]:
        s += "-" + ".".join(v[3])
    if v[4]:
        s += "+" + ".".join(v[4])
    return s


def o_valid(text):
    try:
        return o_str(o_parse(text))
    except OracleError:
        return None


def _ident_key(i):
    return (0, int(i), "") if i.isdigit() and i.isascii() else (1, 0, i)


def o_key(v):
    """A sort key that orders versions by precedence (build ignored)."""
    pre = v[3]
    pre_key = (1,) if not pre else (0, tuple(_ident_key(i) for i in pre))
    return (v[0], v[1], v[2], pre_key)


def o_compare(a, b):
    ka, kb = o_key(o_parse(a)), o_key(o_parse(b))
    return (ka > kb) - (ka < kb)


def o_sort(texts, reverse=False):
    """Canonical strings in precedence order; equal precedence keeps input
    order in both directions."""
    vs = [o_parse(t) for t in texts]
    if reverse:
        idx = sorted(range(len(vs)), key=lambda i: (o_key(vs[i]), -i),
                     reverse=True)
    else:
        idx = sorted(range(len(vs)), key=lambda i: (o_key(vs[i]), i))
    return [o_str(vs[i]) for i in idx]


# ------------------------------------------------------------------ ranges
_WILD = ("x", "X", "*")


def _partial(tok, whole):
    """(nums list of int|None len 3, pre tuple) or OracleError."""
    bad = OracleError("InvalidRange", f"invalid range: {whole!r}")
    s = tok[1:] if tok.startswith("v") else tok
    m = re.fullmatch(
        rf"([^.+-]+)(?:\.([^.+-]+))?(?:\.([^.+-]+))?"
        rf"(?:-({_PRE_ID}(?:\.{_PRE_ID})*))?"
        rf"(?:\+({_BUILD_ID}(?:\.{_BUILD_ID})*))?", s)
    if not m:
        raise bad
    comps = [m.group(1), m.group(2), m.group(3)]
    nums = []
    seen_wild = False
    for c in comps:
        if c is None or c in _WILD:
            seen_wild = True
            nums.append(None)
        elif seen_wild or not re.fullmatch(_N, c):
            raise bad
        else:
            nums.append(int(c))
    pre = tuple(m.group(4).split(".")) if m.group(4) else ()
    if (m.group(4) is not None or m.group(5) is not None) and nums[2] is None:
        raise bad
    return nums, pre


def _cmp(op, M, m, p, pre=()):
    return (op, (M, m, p, tuple(pre), ()))


ZERO = ("0",)


def _expand(op, nums, pre):
    M, m, p = nums
    if op in ("", "="):
        op = "="
    if op == "~":
        if M is None:
            return [_cmp(">=", 0, 0, 0)]
        if m is None:
            return [_cmp(">=", M, 0, 0), _cmp("<", M + 1, 0, 0, ZERO)]
        return [_cmp(">=", M, m, p or 0, pre), _cmp("<", M, m + 1, 0, ZERO)]
    if op == "^":
        if M is None:
            return [_cmp(">=", 0, 0, 0)]
        lo = _cmp(">=", M, m or 0, p or 0, pre)
        if M > 0 or m is None:
            hi = _cmp("<", M + 1, 0, 0, ZERO)
        elif m > 0 or p is None:
            hi = _cmp("<", 0, m + 1, 0, ZERO)
        else:
            hi = _cmp("<", 0, 0, p + 1, ZERO)
        return [lo, hi]
    # primitive operators
    if M is None:
        return [_cmp("<", 0, 0, 0, ZERO)] if op in ("<", ">") \
            else [_cmp(">=", 0, 0, 0)]
    if p is not None:
        return [_cmp(op, M, m, p, pre)]
    if m is None:
        lo, nxt = (M, 0, 0), (M + 1, 0, 0)
    else:
        lo, nxt = (M, m, 0), (M, m + 1, 0)
    return {
        "=": [_cmp(">=", *lo), _cmp("<", *nxt, ZERO)],
        ">": [_cmp(">=", *nxt)],
        ">=": [_cmp(">=", *lo)],
        "<": [_cmp("<", *lo, ZERO)],
        "<=": [_cmp("<", *nxt, ZERO)],
    }[op]


def _hyphen(a, b):
    (aM, am, ap), apre = a
    (bM, bm, bp), bpre = b
    out = [_cmp(">=", 0, 0, 0)] if aM is None else \
        [_cmp(">=", aM, am or 0, ap or 0, apre)]
    if bM is None:
        return out
    if bp is not None:
        out.append(_cmp("<=", bM, bm, bp, bpre))
    elif bm is None:
        out.append(_cmp("<", bM + 1, 0, 0, ZERO))
    else:
        out.append(_cmp("<", bM, bm + 1, 0, ZERO))
    return out


_OP_RE = re.compile(r"(<=|>=|<|>|=|~|\^)?(.*)", re.DOTALL)


def o_range(text):
    """List of comparator sets, each a list of (op, version tuple)."""
    if not isinstance(text, str):
        raise OracleError("InvalidRange", f"invalid range: {text!r}")
    bad = OracleError("InvalidRange", f"invalid range: {text!r}")
    sets = []
    for chunk in text.split("||"):
        toks = chunk.split()
        if not toks:
            sets.append([_cmp(">=", 0, 0, 0)])
            continue
        if "-" in toks:
            if len(toks) != 3 or toks[1] != "-":
                raise bad
            sets.append(_hyphen(_partial(toks[0], text), _partial(toks[2], text)))
            continue
        comps = []
        i = 0
        while i < len(toks):
            op, rest = _OP_RE.fullmatch(toks[i]).groups()
            op = op or ""
            if op and rest == "":
                i += 1
                if i == len(toks) or toks[i][0] in "<>=~^":
                    raise bad
                rest = toks[i]
            nums, pre = _partial(rest, text)
            comps.extend(_expand(op, nums, pre))
            i += 1
        sets.append(comps)
    return sets


def o_range_str(text):
    return " || ".join(
        " ".join(("" if op == "=" else op) + o_str(v) for op, v in s)
        for s in o_range(text))


_OPS = {"<": lambda c: c < 0, "<=": lambda c: c <= 0, ">": lambda c: c > 0,
        ">=": lambda c: c >= 0, "=": lambda c: c == 0}


def _test_set(s, v):
    kv = o_key(v)
    for op, bound in s:
        kb = o_key(bound)
        if not _OPS[op]((kv > kb) - (kv < kb)):
            return False
    if v[3]:
        return any(bound[3] and bound[:3] == v[:3] for _, bound in s)
    return True


def o_satisfies(version, range_text):
    v = o_parse(version)
    sets = o_range(range_text)
    return any(_test_set(s, v) for s in sets)


def _valid_items(items):
    out = []
    for i, t in enumerate(items):
        try:
            out.append((i, t, o_parse(t)))
        except OracleError:
            pass
    return out


def o_filter(items, range_text):
    sets = o_range(range_text)
    return [t for _, t, v in _valid_items(items)
            if any(_test_set(s, v) for s in sets)]


def o_max(items, range_text):
    sets = o_range(range_text)
    hits = [(o_key(v), -i, t) for i, t, v in _valid_items(items)
            if any(_test_set(s, v) for s in sets)]
    return max(hits)[2] if hits else None


def o_min(items, range_text):
    sets = o_range(range_text)
    hits = [(o_key(v), i, t) for i, t, v in _valid_items(items)
            if any(_test_set(s, v) for s in sets)]
    return min(hits)[2] if hits else None


# -------------------------------------------------------------- increments
KINDS = ("major", "minor", "patch", "premajor", "preminor", "prepatch",
         "prerelease")


def o_inc(version, kind, preid=None):
    M, m, p, pre, _ = o_parse(version)
    if kind not in KINDS:
        raise OracleError("InvalidIncrement", f"unknown increment: {kind!r}")
    if preid is not None and not (isinstance(preid, str)
                                  and re.fullmatch(r"[0-9A-Za-z-]+", preid)
                                  and not re.fullmatch(r"[0-9]+", preid)):
        raise OracleError("InvalidIncrement", f"invalid preid: {preid!r}")
    first = (preid, "0") if preid is not None else ("0",)
    if kind == "major":
        r = (M, 0, 0, ()) if (pre and m == 0 and p == 0) else (M + 1, 0, 0, ())
    elif kind == "minor":
        r = (M, m, 0, ()) if (pre and p == 0) else (M, m + 1, 0, ())
    elif kind == "patch":
        r = (M, m, p, ()) if pre else (M, m, p + 1, ())
    elif kind == "premajor":
        r = (M + 1, 0, 0, first)
    elif kind == "preminor":
        r = (M, m + 1, 0, first)
    elif kind == "prepatch":
        r = (M, m, p + 1, first)
    elif not pre:
        r = (M, m, p + 1, first)
    elif preid is not None and pre[0] != preid:
        r = (M, m, p, (preid, "0"))
    else:
        ids = list(pre)
        nums = [i for i, x in enumerate(ids) if re.fullmatch(r"[0-9]+", x)]
        if nums:
            ids[nums[-1]] = str(int(ids[nums[-1]]) + 1)
        else:
            ids.append("0")
        r = (M, m, p, tuple(ids))
    return o_str(r + ((),))


def outcome(fn, *args, **kw):
    """('ok', value) or ('err', kind, message): comparable across models."""
    try:
        return ("ok", fn(*args, **kw))
    except OracleError as e:
        return ("err", e.kind, e.message)


# -------------------------------------------------------------- generators
# Deterministic input generators for the conformance cases.  Each draws
# from the whole input space of one operation, including the edge classes
# the rules name, so a single deviation from a rule shows up in a sample.
_NUMS = ["0", "1", "2", "3", "10", "11"]
_BAD_NUMS = ["01", "00", "-1", "", "1a", "+1"]
_PRE_OK = ["0", "1", "2", "9", "10", "11", "100", "alpha", "beta", "rc",
           "Alpha", "BETA", "a1", "1a", "0a", "00a", "-", "x-y", "b", "Z9"]
_PRE_BAD = ["01", "007", "", "a_b", "a b", "é", "a+b"]
_BUILD_OK = ["001", "0", "sha", "exp-1", "20261017", "B", "x"]
_BUILD_BAD = ["", "a_b", "é"]


def gen_pre_ids(rng, bad=False):
    n = rng.choice([1, 1, 2, 2, 3, 4])
    ids = [rng.choice(_PRE_OK) for _ in range(n)]
    if bad:
        ids[rng.randrange(n)] = rng.choice(_PRE_BAD)
    return ids


def gen_version_text(rng):
    """A version-like string; roughly half are invalid."""
    bad = rng.random() < 0.5
    nums = [rng.choice(_NUMS) for _ in range(3)]
    where = rng.randrange(6) if bad else -1
    if where in (0, 1, 2):
        nums[where] = rng.choice(_BAD_NUMS)
    if where == 3:
        nums = nums[:rng.choice([1, 2])] if rng.random() < 0.5 \
            else nums + [rng.choice(_NUMS)]
    text = ".".join(nums)
    if rng.random() < 0.55 or where == 4:
        text += "-" + ".".join(gen_pre_ids(rng, bad=(where == 4)))
    if rng.random() < 0.35 or where == 5:
        ids = [rng.choice(_BUILD_OK) for _ in range(rng.choice([1, 2, 3]))]
        if where == 5:
            ids[rng.randrange(len(ids))] = rng.choice(_BUILD_BAD)
        text += "+" + ".".join(ids)
    r = rng.random()
    if r < 0.08:
        text = "v" + text
    elif r < 0.10:
        text = rng.choice(["vv", "V", "=", "v "]) + text
    if rng.random() < 0.06:
        text = rng.choice([" ", "\t", "  "]) + text + rng.choice([" ", "\n", ""])
    return text


_CORE = [0, 1, 2, 3]
_PRE_NEAR = [(), (), (), ("0",), ("1",), ("2",), ("10",), ("alpha",),
             ("alpha", "1"), ("alpha", "10"), ("alpha", "2"), ("beta",),
             ("rc", "1"), ("alpha", "beta"), ("0a",)]


def gen_near_version(rng, with_build=True):
    """A valid version close to the bounds the range generators produce."""
    core = [rng.choice(_CORE) for _ in range(3)]
    pre = rng.choice(_PRE_NEAR)
    text = ".".join(map(str, core))
    if pre:
        text += "-" + ".".join(pre)
    if with_build and rng.random() < 0.15:
        text += "+" + rng.choice(["b1", "001", "sha.5"])
    if rng.random() < 0.05:
        text = "v" + text
    return text


def gen_partial(rng, bad=False):
    if bad:
        return rng.choice(["1.x.3", "01.2", "1.2-beta", "1.2.3.4", "1.x-rc",
                           "a.b", "1..2", "x.1", "1.2.3-", "1.2.3+", "vv1",
                           "1.02.3", "1.2.3-01", "*.1"])
    form = rng.randrange(10)
    n = [rng.choice(_CORE) for _ in range(3)]
    w = rng.choice(["x", "X", "*"])
    if form == 0:
        text = w
    elif form == 1:
        text = f"{n[0]}"
    elif form == 2:
        text = f"{n[0]}.{n[1]}"
    elif form == 3:
        text = f"{n[0]}.{w}" + rng.choice(["", f".{w}"])
    elif form == 4:
        text = f"{n[0]}.{n[1]}.{w}"
    elif form in (5, 6, 7):
        text = f"{n[0]}.{n[1]}.{n[2]}"
    else:
        pre = rng.choice(_PRE_NEAR[3:])
        text = f"{n[0]}.{n[1]}.{n[2]}-" + ".".join(pre)
    if form >= 5 and rng.random() < 0.1:
        text += "+b7"
    if rng.random() < 0.07:
        text = "v" + text
    return text


_TERM_OPS = ["", "", "=", "<", "<=", ">", ">=", "~", "~", "^", "^", "^"]


def gen_term(rng, bad=False):
    op = rng.choice(_TERM_OPS)
    gap = rng.choice([" ", "  ", "\t"]) if op and rng.random() < 0.2 else ""
    return op + gap + gen_partial(rng, bad=bad)


def _ws(rng):
    return rng.choice([" ", " ", " ", "  ", "\t", " \t "])


def gen_set(rng, bad=False):
    r = rng.random()
    if r < 0.04:
        return rng.choice(["", " ", "\t"])
    if r < 0.24:
        a = gen_partial(rng)
        b = gen_partial(rng)
        return f"{a}{_ws(rng)}-{_ws(rng)}{b}"
    terms = [gen_term(rng) for _ in range(rng.choice([1, 1, 2, 2, 3]))]
    if bad:
        terms[rng.randrange(len(terms))] = rng.choice([
            gen_term(rng, bad=True), ">=", "- 1", "1 - 2 - 3", "~>1",
            "1.2.3 -2", ">= <1", "|", "=="])
    return _ws(rng).join(terms)


def gen_range(rng, bad=False, sets=None):
    n = sets or rng.choice([1, 1, 2, 2, 3])
    parts = [gen_set(rng) for _ in range(n)]
    if bad:
        parts[rng.randrange(n)] = gen_set(rng, bad=True)
    seps = ["||", " || ", "  ||\t", " ||", "|| "]
    out = parts[0]
    for p in parts[1:]:
        out += rng.choice(seps) + p
    return out


def gen_version_list(rng):
    """A list with build-only duplicates and a few invalid entries."""
    items = []
    for _ in range(rng.randint(0, 14)):
        r = rng.random()
        if r < 0.12:
            items.append(rng.choice(["junk", "1.2", "01.0.0", "", "1.0.0-01"]))
        elif r < 0.3 and items:
            base = rng.choice(items).split("+")[0]
            items.append(base + "+" + rng.choice(["a", "b", "c1", "007"]))
        else:
            items.append(gen_near_version(rng, with_build=True))
    return items


def gen_inc_args(rng):
    version = gen_near_version(rng) if rng.random() < 0.9 \
        else rng.choice(["1.2", "x", "1.0.0-01"])
    kind = rng.choice(list(KINDS) * 4 + ["minorr", "", "Major", "release"])
    preid = rng.choice([None, None, None, "alpha", "beta", "rc", "0a",
                        "", "1", "a.b", "a_b"])
    return version, kind, preid


def gen_version_for(rng, range_text):
    """A valid version drawn near the bounds of ``range_text`` (valid)."""
    bounds = [v for s in o_range(range_text) for _, v in s]
    if not bounds or rng.random() < 0.2:
        return gen_near_version(rng)
    M, m, p, pre, _ = rng.choice(bounds)
    r = rng.random()
    if r < 0.15:
        p += 1
    elif r < 0.25 and p > 0:
        p -= 1
    elif r < 0.3:
        m += 1
    r = rng.random()
    if pre and r < 0.35:
        ids = list(pre)
        tweak = rng.randrange(3)
        if tweak == 0:
            ids.append(rng.choice(["1", "alpha"]))
        elif tweak == 1 and ids[-1].isdigit():
            ids[-1] = str(int(ids[-1]) + rng.choice([1, 9]))
        else:
            ids[-1] = rng.choice(["0", "beta", "rc", "10"])
        pre = tuple(ids)
    elif r < 0.6:
        pre = rng.choice(_PRE_NEAR[3:])
    elif r < 0.75:
        pre = ()
    text = f"{M}.{m}.{p}" + ("-" + ".".join(pre) if pre else "")
    if rng.random() < 0.1:
        text += "+b" + str(rng.randrange(3))
    return text


# ----------------------------------------------------- the system as a whole
def o_report(requirements, available):
    """The resolution report: one line per name, sorted, as the brief's
    format_report documents (``name range -> version|unresolved``)."""
    lines = []
    for name in sorted(requirements):
        pick = o_max(available.get(name, ()), requirements[name])
        lines.append(f"{name} {requirements[name]} -> "
                     f"{pick if pick is not None else 'unresolved'}")
    return "\n".join(lines) + ("\n" if lines else "")


def o_check_lock(requirements, lock):
    out = []
    for name in sorted(requirements):
        if name not in lock:
            out.append(f"{name}: not locked")
        elif not o_satisfies(lock[name], requirements[name]):
            out.append(f"{name}: {lock[name]} is outside {requirements[name]}")
    for name in sorted(set(lock) - set(requirements)):
        out.append(f"{name}: not required")
    return out


_NAMES = ["alpha", "beta", "gamma", "delta", "eps", "zeta", "eta"]


def gen_project(rng):
    """(requirements, available, lock) over a handful of package names."""
    names = rng.sample(_NAMES, rng.randint(1, 5))
    reqs, avail, lock = {}, {}, {}
    for n in names:
        r = gen_range(rng, sets=rng.choice([1, 1, 2]))
        reqs[n] = r
        items = gen_version_list(rng)
        items += [gen_version_for(rng, r) for _ in range(rng.randint(0, 5))]
        rng.shuffle(items)
        avail[n] = items
        if rng.random() < 0.85:
            lock[n] = gen_version_for(rng, r)
    if rng.random() < 0.3:
        lock[rng.choice([x for x in _NAMES if x not in names] or ["omega"])] \
            = gen_near_version(rng)
    return reqs, avail, lock


# ------------------------------------------------------------ index inputs
def o_bounds(range_text):
    """The canonical comparator versions of a valid range."""
    return [o_str(v) for s in o_range(range_text) for _, v in s]


def collapse(text):
    """The text with all whitespace removed (often a different range)."""
    return "".join(text.split())


def respace(rng, text):
    """The same range with its whitespace changed but not removed."""
    out = []
    for ch in text:
        if ch in " \t":
            out.append(rng.choice([" ", "  ", "\t", " \t"]))
        else:
            out.append(ch)
    return "".join(out)


_TIGHT = ["1.2.3", "<1.2.3", ">1.2.3", "<=1.2.3", ">=1.2.3", "1.2.3 <1.2.3",
          ">=1.2.3 >1.2.3", "<=1.2.3 <1.2.3", ">1.2.3 >=1.2.3", "<1.2.3 <=1.2.3",
          ">1.0.0 <2.0.0", ">=1.0.0-0 <1.0.0", "<2.0.0-0", ">2.0.0-0",
          "1.2.3 - 2", "1.2.3-2", "1 2", "12", "1.2.3 - 2.0.0-0", "^1 || ^0.1",
          ">=1.2.3-alpha <1.2.3 || >=1.0.0", "~1.2.3-beta || 1.2.x"]


def gen_query_texts(rng):
    """Range texts to ask one index: generated ranges, their respaced and
    collapsed forms, and tight bounds."""
    out = []
    for _ in range(rng.randint(3, 9)):
        r = gen_range(rng)
        out.append(r)
        if rng.random() < 0.4:
            out.append(respace(rng, r))
        if rng.random() < 0.4:
            out.append(collapse(r))
    out += rng.sample(_TIGHT, rng.randint(1, 4))
    rng.shuffle(out)
    return out


def gen_index_case(rng):
    """(items, queries): a list holding the queries' own bounds (some with
    build-only duplicates) next to near versions and invalid entries."""
    queries = gen_query_texts(rng)
    items = gen_version_list(rng)
    for q in queries:
        try:
            bounds = o_bounds(q)
        except OracleError:
            continue
        for b in rng.sample(bounds, min(len(bounds), rng.randint(0, 2))):
            items.append(b)
            if rng.random() < 0.4:
                items.append(b + "+" + rng.choice(["x", "y", "007"]))
        items += [gen_version_for(rng, q) for _ in range(rng.randint(0, 2))]
    rng.shuffle(items)
    return items, queries


def gen_perf_case(rng, n=50000, q=500):
    """A big list and narrow ranges (each matches few or none of its entries)."""
    items = []
    for _ in range(n):
        text = f"{rng.randrange(30)}.{rng.randrange(30)}.{rng.randrange(30)}"
        if rng.random() < 0.15:
            text += "-rc." + str(rng.randrange(4))
        items.append(text)
    ranges = []
    for _ in range(q):
        a, b, c = rng.randrange(30), rng.randrange(30), rng.randrange(30)
        ranges.append(rng.choice([f"~{a}.{b}", f"{a}.{b}.{c} - {a}.{b}.{c + 2}",
                                  f"^{a}.{b}.{c}-rc.1 <{a}.{b}.{c + 1}",
                                  "^99", "<0.0.0-0", f">{a}.{b}.{c} <{a}.{b}.{c + 1}"]))
    return items, ranges
