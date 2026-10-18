"""Ranges: parsing, normalising and matching."""
import re
import sys
from typing import List, Optional

from . import config
from .compat import ensure_str, is_wildcard
from .core import Version, parse, compare_versions, _fmt, InvalidVersion
from . import cache

_partial_re = re.compile(
    r"^[vV]?(0|[1-9][0-9]*|[xX*])(?:\.(0|[1-9][0-9]*|[xX*])(?:\.(0|[1-9][0-9]*|[xX*])"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?)?)?$"
)
_glue_re = re.compile(r"(>=|<=|~>|>|<|=|\^|~)\s+")
_hyphen_re = re.compile(r"^(\S+)\s+-\s+(\S+)$")


class InvalidRange(ValueError):
    pass


class comparator:
    def __init__(self, op, version):
        self.op = op
        self.version = version

    def __eq__(self, other):
        return isinstance(other, comparator) and (self.op, self.version) == (other.op, other.version)

    def __repr__(self):
        return "comparator(%r, %r)" % (self.op, self.version)


def _any():
    return comparator(">=", Version(0, 0, 0))


def _partial(text, token):
    m = _partial_re.match(text)
    if m is None:
        raise InvalidRange("invalid comparator: %r" % (token,))
    parts = []
    wild = False
    for g in m.groups()[:3]:
        if wild or g is None or is_wildcard(g):
            wild = True
            parts.append(None)
        else:
            parts.append(int(g))
    if parts[2] is None and (m.group(4) or m.group(5)):
        raise InvalidRange("invalid comparator: %r" % (token,))
    pre = []
    if m.group(4):
        for ident in m.group(4).split("."):
            if ident.isdigit() and len(ident) > 1 and ident[0] == "0":
                raise InvalidRange("invalid comparator: %r" % (token,))
            pre.append(int(ident) if ident.isdigit() else ident)
    return parts[0], parts[1], parts[2], tuple(pre)


def _ceil(major, minor, patch):
    return comparator("<", Version(major, minor, patch, (0,)))


def parse_range(rangeText):
    """Parse a range string into alternatives of comparators."""
    if not isinstance(rangeText, str):
        raise InvalidRange("not a string: %r" % (rangeText,))
    if len(rangeText) > config.get("max_range_length"):
        raise InvalidRange("range too long")
    result = []
    for piece in rangeText.split("||"):
        piece = piece.strip()
        group = []
        hm = _hyphen_re.match(piece)
        if hm:
            low, high = hm.group(1), hm.group(2)
            M, m, p, pre = _partial(low, low)
            if M is None:
                group.append(_any())
            else:
                group.append(comparator(">=", Version(M, m or 0, p or 0, pre)))
            M, m, p, pre = _partial(high, high)
            if M is not None:
                if m is None:
                    group.append(_ceil(M + 1, 0, 0))
                elif p is None:
                    group.append(_ceil(M, m + 1, 0))
                else:
                    group.append(comparator("<=", Version(M, m, p, pre)))
            result.append(group)
            continue
        tokens = _glue_re.sub(r"\1", piece).split()
        if not tokens:
            result.append([_any()])
            continue
        for token in tokens:
            op = ""
            for candidate in config.OPERATORS:
                if token.startswith(candidate):
                    op = candidate
                    break
            M, m, p, pre = _partial(token[len(op):], token)
            floor = Version(M or 0, m or 0, p or 0, pre)
            if op == "~>":
                op = "~"
            if M is None:
                if op in (">", "<"):
                    group.append(comparator("<", Version(0, 0, 0, (0,))))
                else:
                    group.append(_any())
            elif op in ("", "="):
                if m is None:
                    group += [comparator(">=", floor), _ceil(M + 1, 0, 0)]
                elif p is None:
                    group += [comparator(">=", floor), _ceil(M, m + 1, 0)]
                else:
                    group.append(comparator("=", floor))
            elif op == "^":
                if m is None or M > 0:
                    group += [comparator(">=", floor), _ceil(M + 1, 0, 0)]
                elif p is None or m > 0:
                    group += [comparator(">=", floor), _ceil(0, m + 1, 0)]
                else:
                    group += [comparator(">=", floor), _ceil(0, 0, p + 1)]
            elif op == "~":
                if m is None:
                    group += [comparator(">=", floor), _ceil(M + 1, 0, 0)]
                else:
                    group += [comparator(">=", floor), _ceil(M, m + 1, 0)]
            elif op == ">":
                if m is None:
                    group.append(comparator(">=", Version(M + 1, 0, 0)))
                elif p is None:
                    group.append(comparator(">=", Version(M, m + 1, 0)))
                else:
                    group.append(comparator(">", floor))
            elif op == ">=":
                group.append(comparator(">=", floor))
            elif op == "<":
                if p is None:
                    group.append(_ceil(M, m or 0, 0))
                else:
                    group.append(comparator("<", floor))
            else:
                if m is None:
                    group.append(_ceil(M + 1, 0, 0))
                elif p is None:
                    group.append(_ceil(M, m + 1, 0))
                else:
                    group.append(comparator("<=", floor))
        result.append(group)
    return result


def normalize_range(rangeText):
    """Return the canonical form of a range string."""
    sets = cache.cached_range(rangeText, parse_range)
    out = []
    for group in sets:
        out.append(" ".join(("" if c.op == "=" else c.op) + _fmt(c.version) for c in group))
    return " || ".join(out)


def test_set(v, group, include_prerelease):
    for c in group:
        order = compare_versions(v, c.version)
        if c.op == "<" and not order < 0:
            return False
        if c.op == "<=" and not order <= 0:
            return False
        if c.op == ">" and not order > 0:
            return False
        if c.op == ">=" and not order >= 0:
            return False
        if c.op == "=" and order != 0:
            return False
    if v.prerelease and not include_prerelease:
        for c in group:
            if c.version.prerelease and (c.version.major, c.version.minor, c.version.patch) == (v.major, v.minor, v.patch):
                return True
        return False
    return True


def satisfies(version, rangeText, include_prerelease=False):
    """Tell whether a version string satisfies a range; bad ones never do."""
    from .core import satisfies_version
    sets = cache.cached_range(rangeText, parse_range)
    try:
        v = parse(version)
    except InvalidVersion:
        return False
    return satisfies_version(v, sets, include_prerelease)


def _best(versions: List[str], rangeText, include_prerelease, sign) -> Optional[str]:
    sets = cache.cached_range(rangeText, parse_range)
    best = None
    best_text = None
    for text in versions:
        try:
            v = parse(text)
        except InvalidVersion:
            if config.DEFAULTS.get("strict"):
                sys.stderr.write("skipping %r\n" % (text,))
            continue
        if not any(test_set(v, g, include_prerelease) for g in sets):
            continue
        if best is None or compare_versions(v, best) == sign:
            best, best_text = v, text
    return best_text


def max_satisfying(versions, rangeText, include_prerelease=False):
    """Return the highest satisfying version string, skipping bad ones."""
    return _best(versions, rangeText, include_prerelease, 1)


def min_satisfying(versions, rangeText, include_prerelease=False):
    """Return the lowest satisfying version string, skipping bad ones."""
    return _best(versions, rangeText, include_prerelease, -1)
