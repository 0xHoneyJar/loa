"""Tokenising range expressions into terms over partial versions.

A range is a list of comparator sets separated by ``||``.  A set is either a
hyphen range ``A - B`` or a run of whitespace-separated terms, each an
optional operator followed by a partial version.  The parser only checks the
syntax; ``desugar`` turns the terms into primitive comparators.
"""
import re

from .errors import InvalidRange
from .identifiers import (split_identifiers, valid_build_identifier,
                          valid_prerelease_identifier)

WILDCARDS = frozenset({"x", "X", "*"})
# longest first, so that "<=" is not read as "<" followed by "=1.2.3"
TERM_OPERATORS = ("<=", ">=", "<", ">", "=", "~", "^")
_NUMBER = re.compile(r"0|[1-9][0-9]*")


class Partial:
    """A version whose trailing components may be wildcards (``None``)."""

    __slots__ = ("major", "minor", "patch", "prerelease")

    def __init__(self, major, minor, patch, prerelease=()):
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = tuple(prerelease)

    @property
    def is_full(self):
        return self.patch is not None

    def __repr__(self):
        parts = ["x" if p is None else str(p)
                 for p in (self.major, self.minor, self.patch)]
        text = ".".join(parts)
        if self.prerelease:
            text += "-" + ".".join(self.prerelease)
        return f"Partial({text!r})"


STAR = Partial(None, None, None)


class Term:
    """``op`` is one of ``TERM_OPERATORS``; ``partial`` a ``Partial``."""

    __slots__ = ("op", "partial")

    def __init__(self, op, partial):
        self.op = op
        self.partial = partial


class HyphenTerm:
    """``A - B``: an inclusive span between two partial versions."""

    __slots__ = ("low", "high")

    def __init__(self, low, high):
        self.low = low
        self.high = high


def parse_partial(text, whole):
    """Parse one partial version; ``whole`` is the range text for errors."""
    body = text
    if body.startswith("v"):
        body = body[1:]
    pre, build = (), ()
    if "+" in body:
        body, build_text = body.split("+", 1)
        build = split_identifiers(build_text, valid_build_identifier)
        if build is None:
            raise InvalidRange(whole)
    if "-" in body:
        body, pre_text = body.split("-", 1)
        pre = split_identifiers(pre_text, valid_prerelease_identifier)
        if pre is None:
            raise InvalidRange(whole)
    parts = body.split(".")
    if len(parts) > 3:
        raise InvalidRange(whole)
    numbers = []
    wild = False
    for part in parts:
        if part in WILDCARDS:
            wild = True
            numbers.append(None)
        elif not wild and _NUMBER.fullmatch(part):
            numbers.append(int(part))
        else:
            raise InvalidRange(whole)
    while len(numbers) < 3:
        numbers.append(None)
    if (pre or build) and numbers[2] is None:
        raise InvalidRange(whole)
    return Partial(numbers[0], numbers[1], numbers[2], pre)


def _split_operator(token):
    for op in TERM_OPERATORS:
        if token.startswith(op):
            return op, token[len(op):]
    return "", token


def parse_set(text, whole):
    """Parse one comparator set into a list of terms."""
    tokens = text.split()
    if not tokens:
        raise InvalidRange(whole)
    if "-" in tokens:
        if len(tokens) != 3 or tokens[1] != "-":
            raise InvalidRange(whole)
        return [HyphenTerm(parse_partial(tokens[0], whole),
                           parse_partial(tokens[2], whole))]
    terms = []
    for token in tokens:
        op, rest = _split_operator(token)
        if not rest:
            raise InvalidRange(whole)
        terms.append(Term(op or "=", parse_partial(rest, whole)))
    return terms


def parse_range_text(text):
    """Split a range on ``||`` and parse every set; returns a list of lists."""
    if not isinstance(text, str):
        raise InvalidRange(text)
    return [parse_set(part, text) for part in text.split("||")]
