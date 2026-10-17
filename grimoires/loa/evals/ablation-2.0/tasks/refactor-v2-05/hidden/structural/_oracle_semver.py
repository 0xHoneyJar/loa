"""Reference behaviour of the package, flattened into one module (grader side)."""

import enum
from dataclasses import dataclass
import re
import functools


# ---- errors ----

class SemverError(ValueError):
    """Base class of every error the package raises."""


class InvalidVersionError(SemverError):
    """A version string does not follow the grammar."""


class InvalidRangeError(SemverError):
    """A range string does not follow the grammar."""


class InvalidBumpError(SemverError):
    """A bump request cannot be applied."""


# ---- model ----

class Op(enum.Enum):
    """A comparator operator."""

    LT = "<"
    LE = "<="
    GT = ">"
    GE = ">="
    EQ = "="


class Prefix(enum.Enum):
    """The operator written before a partial version in a range."""

    NONE = ""
    EQ = "="
    LT = "<"
    LE = "<="
    GT = ">"
    GE = ">="
    CARET = "^"
    TILDE = "~"


class Part(enum.Enum):
    """A part of a version that a bump changes."""

    MAJOR = "major"
    MINOR = "minor"
    PATCH = "patch"
    PRERELEASE = "prerelease"
    RELEASE = "release"


@dataclass(frozen=True, slots=True)
class Version:
    """A parsed semantic version."""

    major: int
    minor: int
    patch: int
    prerelease: tuple[int | str, ...] = ()
    build: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class Comparator:
    """One operator applied to one version."""

    op: Op
    version: Version


@dataclass(frozen=True, slots=True)
class Partial:
    """A version in a range whose missing or wildcard parts are None."""

    major: int | None
    minor: int | None
    patch: int | None
    prerelease: tuple[int | str, ...] = ()


# ---- versions ----

MAX_LENGTH = 256


_PATTERN = (
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)


def _strip_prefix(text: str) -> str:
    body = text.strip()
    if body.startswith("="):
        body = body[1:]
    if body[:1] in ("v", "V"):
        body = body[1:]
    return body


def parse_identifiers(text: str, original: str) -> tuple[int | str, ...]:
    """Split a dotted prerelease into numbers and words."""
    out: list[int | str] = []
    for ident in text.split("."):
        if not ident.isascii() or not ident.isdigit():
            out.append(ident)
        elif len(ident) > 1 and ident[0] == "0":
            raise InvalidVersionError(f"invalid version: {original!r}")
        else:
            out.append(int(ident))
    return tuple(out)


def parse_version(text: str) -> Version:
    """Parse one version string, accepting a leading = and v."""
    if not isinstance(text, str):
        raise InvalidVersionError(f"not a string: {text!r}")
    if len(text) > MAX_LENGTH:
        raise InvalidVersionError("version too long")
    match = re.match(_PATTERN, _strip_prefix(text))
    if match is None:
        raise InvalidVersionError(f"invalid version: {text!r}")
    major, minor, patch, pre, build = match.groups()
    prerelease = parse_identifiers(pre, text) if pre else ()
    return Version(int(major), int(minor), int(patch), prerelease, tuple(build.split(".")) if build else ())


def format_version(version: Version) -> str:
    """Render a version in its canonical form."""
    text = f"{version.major}.{version.minor}.{version.patch}"
    if version.prerelease:
        text += "-" + ".".join(str(i) for i in version.prerelease)
    if version.build:
        text += "+" + ".".join(version.build)
    return text


# ---- precedence ----

def _sign(a: int | str, b: int | str) -> int:
    return (a > b) - (a < b)


def compare_identifier(a: int | str, b: int | str) -> int:
    """Order two prerelease identifiers: numbers before words."""
    if isinstance(a, int) and isinstance(b, int):
        return _sign(a, b)
    if isinstance(a, int):
        return -1
    if isinstance(b, int):
        return 1
    return _sign(a, b)


def _compare_prerelease(a: tuple[int | str, ...], b: tuple[int | str, ...]) -> int:
    if not a or not b:
        return _sign(len(b), len(a))
    for left, right in zip(a, b):
        order = compare_identifier(left, right)
        if order:
            return order
    return _sign(len(a), len(b))


def compare(a: Version, b: Version) -> int:
    """Return -1, 0 or 1 by precedence; build metadata is ignored."""
    for left, right in ((a.major, b.major), (a.minor, b.minor), (a.patch, b.patch)):
        if left != right:
            return _sign(left, right)
    return _compare_prerelease(a.prerelease, b.prerelease)


def _total(a: Version, b: Version) -> int:
    return compare(a, b) or _sign(format_version(a), format_version(b))


def sort_versions(versions: list[Version]) -> list[Version]:
    """Sort ascending by precedence; equal ones by canonical text."""
    return sorted(versions, key=functools.cmp_to_key(_total))


# ---- bumping ----

def _word(ident: str) -> bool:
    chars = all(c.isascii() and (c.isalnum() or c == "-") for c in ident)
    return bool(ident) and chars and not ident.isdigit()


def check_identifier(part: Part, ident: str | None) -> None:
    """Reject an identifier that a bump cannot use."""
    if ident is None:
        return
    if part is not Part.PRERELEASE:
        raise InvalidBumpError("identifier only applies to prerelease")
    if not _word(ident):
        raise InvalidBumpError(f"invalid identifier: {ident!r}")


def _major(v: Version) -> Version:
    keep = bool(v.prerelease) and v.minor == 0 and v.patch == 0
    return Version(v.major if keep else v.major + 1, 0, 0)


def _minor(v: Version) -> Version:
    keep = bool(v.prerelease) and v.patch == 0
    return Version(v.major, v.minor if keep else v.minor + 1, 0)


def _patch(v: Version) -> Version:
    return Version(v.major, v.minor, v.patch if v.prerelease else v.patch + 1)


def _next_prerelease(v: Version, ident: str | None) -> tuple[int | str, ...]:
    pre = v.prerelease
    if ident is not None and pre[0] != ident:
        return (ident, 0)
    if isinstance(pre[-1], int):
        return pre[:-1] + (pre[-1] + 1,)
    return pre + (0,)


def _prerelease(v: Version, ident: str | None) -> Version:
    if not v.prerelease:
        start: tuple[int | str, ...] = (ident, 0) if ident is not None else (0,)
        return Version(v.major, v.minor, v.patch + 1, start)
    return Version(v.major, v.minor, v.patch, _next_prerelease(v, ident))


def _release(v: Version) -> Version:
    if not v.prerelease:
        raise InvalidBumpError(f"already a release: {format_version(v)!r}")
    return Version(v.major, v.minor, v.patch)


def bump(version: Version, part: Part, ident: str | None = None) -> Version:
    """Return the version after bumping one part; build metadata is dropped."""
    check_identifier(part, ident)
    match part:
        case Part.MAJOR:
            return _major(version)
        case Part.MINOR:
            return _minor(version)
        case Part.PATCH:
            return _patch(version)
        case Part.PRERELEASE:
            return _prerelease(version, ident)
        case Part.RELEASE:
            return _release(version)


# ---- desugar ----

def any_version() -> Comparator:
    """Return the comparator every release satisfies."""
    return Comparator(Op.GE, Version(0, 0, 0))


def no_version() -> Comparator:
    """Return the comparator no version satisfies."""
    return Comparator(Op.LT, Version(0, 0, 0, (0,)))


def _floor(p: Partial) -> Version:
    return Version(p.major or 0, p.minor or 0, p.patch or 0, p.prerelease)


def _ceiling(major: int, minor: int, patch: int) -> Comparator:
    return Comparator(Op.LT, Version(major, minor, patch, (0,)))


def _next_major_or_minor(p: Partial) -> Comparator:
    if p.minor is None:
        return _ceiling(p.major + 1, 0, 0)
    return _ceiling(p.major, p.minor + 1, 0)


def _plain(p: Partial) -> tuple[Comparator, ...]:
    if p.major is None:
        return (any_version(),)
    if p.patch is None:
        return (Comparator(Op.GE, _floor(p)), _next_major_or_minor(p))
    return (Comparator(Op.EQ, _floor(p)),)


def _caret(p: Partial) -> tuple[Comparator, ...]:
    if p.major is None:
        return (any_version(),)
    low = Comparator(Op.GE, _floor(p))
    if p.minor is None or p.major > 0:
        return (low, _ceiling(p.major + 1, 0, 0))
    if p.patch is None or p.minor > 0:
        return (low, _ceiling(0, p.minor + 1, 0))
    return (low, _ceiling(0, 0, p.patch + 1))


def _tilde(p: Partial) -> tuple[Comparator, ...]:
    if p.major is None:
        return (any_version(),)
    return (Comparator(Op.GE, _floor(p)), _next_major_or_minor(p))


def _greater(p: Partial) -> tuple[Comparator, ...]:
    if p.major is None:
        return (no_version(),)
    if p.minor is None:
        return (Comparator(Op.GE, Version(p.major + 1, 0, 0)),)
    if p.patch is None:
        return (Comparator(Op.GE, Version(p.major, p.minor + 1, 0)),)
    return (Comparator(Op.GT, _floor(p)),)


def _at_least(p: Partial) -> tuple[Comparator, ...]:
    return (any_version(),) if p.major is None else (Comparator(Op.GE, _floor(p)),)


def _less(p: Partial) -> tuple[Comparator, ...]:
    if p.major is None:
        return (no_version(),)
    if p.patch is None:
        return (_ceiling(p.major, p.minor or 0, 0),)
    return (Comparator(Op.LT, _floor(p)),)


def _at_most(p: Partial) -> tuple[Comparator, ...]:
    if p.major is None:
        return (any_version(),)
    if p.patch is None:
        return (_next_major_or_minor(p),)
    return (Comparator(Op.LE, _floor(p)),)


def expand(prefix: Prefix, partial: Partial) -> tuple[Comparator, ...]:
    """Expand one prefixed partial version into primitive comparators."""
    match prefix:
        case Prefix.NONE | Prefix.EQ:
            return _plain(partial)
        case Prefix.CARET:
            return _caret(partial)
        case Prefix.TILDE:
            return _tilde(partial)
        case Prefix.GT:
            return _greater(partial)
        case Prefix.GE:
            return _at_least(partial)
        case Prefix.LT:
            return _less(partial)
        case Prefix.LE:
            return _at_most(partial)


def expand_hyphen(low: Partial, high: Partial) -> tuple[Comparator, ...]:
    """Expand an inclusive hyphen range into primitive comparators."""
    lower = _at_least(low)
    if high.major is None:
        return lower
    return lower + _at_most(high)


# ---- ranges ----

MAX_RANGE_LENGTH = 1024


_PARTIAL = (
    r"^[vV]?(0|[1-9][0-9]*|[xX*])(?:\.(0|[1-9][0-9]*|[xX*])(?:\.(0|[1-9][0-9]*|[xX*])"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?)?)?$"
)


_TOKEN = r"^(>=|<=|~>|>|<|=|\^|~)?(.*)$"


_GLUE = r"(>=|<=|~>|>|<|=|\^|~)\s+"


_HYPHEN = r"^(\S+)\s+-\s+(\S+)$"


def _number(text: str | None) -> int | None:
    if text is None or text in ("x", "X", "*"):
        return None
    return int(text)


def _partial_prerelease(text: str | None, token: str) -> tuple[int | str, ...]:
    if text is None:
        return ()
    out: list[int | str] = []
    for ident in text.split("."):
        if ident.isdigit() and len(ident) > 1 and ident[0] == "0":
            raise InvalidRangeError(f"invalid comparator: {token!r}")
        out.append(int(ident) if ident.isdigit() else ident)
    return tuple(out)


def _wildcarded(parts: list[int | None]) -> list[int | None]:
    for i, part in enumerate(parts):
        if part is None:
            return parts[:i] + [None] * (3 - i)
    return parts


def parse_partial(text: str, token: str) -> Partial:
    """Parse a possibly partial or wildcard version written in a range."""
    match = re.match(_PARTIAL, text, re.DOTALL)
    if match is None:
        raise InvalidRangeError(f"invalid comparator: {token!r}")
    major, minor, patch = _wildcarded([_number(g) for g in match.groups()[:3]])
    if patch is None and (match.group(4) or match.group(5)):
        raise InvalidRangeError(f"invalid comparator: {token!r}")
    return Partial(major, minor, patch, _partial_prerelease(match.group(4), token))


def _prefix(text: str | None) -> Prefix:
    if text is None:
        return Prefix.NONE
    return Prefix.TILDE if text == "~>" else Prefix(text)


def _parse_token(token: str) -> tuple[Comparator, ...]:
    match = re.match(_TOKEN, token, re.DOTALL)
    return expand(_prefix(match.group(1)), parse_partial(match.group(2), token))


def _parse_piece(piece: str) -> tuple[Comparator, ...]:
    hyphen = re.match(_HYPHEN, piece)
    if hyphen is not None:
        low, high = hyphen.groups()
        return expand_hyphen(parse_partial(low, low), parse_partial(high, high))
    tokens = re.sub(_GLUE, r"\1", piece).split()
    if not tokens:
        return (any_version(),)
    return tuple(c for token in tokens for c in _parse_token(token))


def parse_range(text: str) -> tuple[tuple[Comparator, ...], ...]:
    """Parse a range into alternatives of comparators that must all hold."""
    if not isinstance(text, str):
        raise InvalidRangeError(f"not a string: {text!r}")
    if len(text) > MAX_RANGE_LENGTH:
        raise InvalidRangeError("range too long")
    return tuple(_parse_piece(piece.strip()) for piece in text.split("||"))


def _format_comparator(comparator: Comparator) -> str:
    op = "" if comparator.op is Op.EQ else comparator.op.value
    return op + format_version(comparator.version)


def format_range(comparator_sets: tuple[tuple[Comparator, ...], ...]) -> str:
    """Render parsed alternatives in the canonical form."""
    return " || ".join(" ".join(_format_comparator(c) for c in group) for group in comparator_sets)


# ---- matching ----

def test_op(op: Op, order: int) -> bool:
    """Tell whether a comparison result passes an operator."""
    match op:
        case Op.LT:
            return order < 0
        case Op.LE:
            return order <= 0
        case Op.GT:
            return order > 0
        case Op.GE:
            return order >= 0
        case Op.EQ:
            return order == 0


def _same_core(a: Version, b: Version) -> bool:
    return (a.major, a.minor, a.patch) == (b.major, b.minor, b.patch)


def _prerelease_allowed(version: Version, group: tuple[Comparator, ...]) -> bool:
    return any(c.version.prerelease and _same_core(c.version, version) for c in group)


def _test_group(version: Version, group: tuple[Comparator, ...], include_prerelease: bool) -> bool:
    if not all(test_op(c.op, compare(version, c.version)) for c in group):
        return False
    return include_prerelease or not version.prerelease or _prerelease_allowed(version, group)


def satisfies(version: Version, comparator_sets: tuple[tuple[Comparator, ...], ...], include_prerelease: bool = False) -> bool:
    """Tell whether a version satisfies any alternative of a parsed range."""
    return any(_test_group(version, group, include_prerelease) for group in comparator_sets)


def filter_satisfying(versions: list[Version], comparator_sets: tuple[tuple[Comparator, ...], ...], include_prerelease: bool = False) -> list[Version]:
    """Keep the versions that satisfy a parsed range, in input order."""
    return [v for v in versions if satisfies(v, comparator_sets, include_prerelease)]


def _extreme(versions: list[Version], sign: int) -> Version | None:
    best: Version | None = None
    for version in versions:
        if best is None or compare(version, best) == sign:
            best = version
    return best


def max_satisfying(versions: list[Version], comparator_sets: tuple[tuple[Comparator, ...], ...], include_prerelease: bool = False) -> Version | None:
    """Return the highest satisfying version; the first one wins a tie."""
    return _extreme(filter_satisfying(versions, comparator_sets, include_prerelease), 1)


def min_satisfying(versions: list[Version], comparator_sets: tuple[tuple[Comparator, ...], ...], include_prerelease: bool = False) -> Version | None:
    """Return the lowest satisfying version; the first one wins a tie."""
    return _extreme(filter_satisfying(versions, comparator_sets, include_prerelease), -1)


# ---- facade ----

def parse(text: str) -> Version:
    """Parse a version string."""
    return parse_version(text)


def valid(text: object) -> str | None:
    """Return the canonical form of a version string, or None."""
    try:
        return format_version(parse_version(text))
    except InvalidVersionError:
        return None


def compare_text(a: str, b: str) -> int:
    """Compare two version strings by precedence."""
    return compare(parse_version(a), parse_version(b))


def _by_precedence(a: tuple[Version, str], b: tuple[Version, str]) -> int:
    order = compare(a[0], b[0])
    if order:
        return order
    left, right = format_version(a[0]), format_version(b[0])
    return (left > right) - (left < right)


def sort_text(texts: list[str]) -> list[str]:
    """Sort version strings by precedence, keeping their spelling."""
    pairs = [(parse_version(t), t) for t in texts]
    return [t for _, t in sorted(pairs, key=functools.cmp_to_key(_by_precedence))]


def bump_text(text: str, part: str, ident: str | None = None) -> str:
    """Bump one part of a version string."""
    try:
        which = Part(part)
    except ValueError:
        raise InvalidBumpError(f"unknown part: {part!r}") from None
    return format_version(bump(parse_version(text), which, ident))


def satisfies_text(version: str, range_text: str, include_prerelease: bool = False) -> bool:
    """Tell whether a version string satisfies a range; bad ones never do."""
    sets = parse_range(range_text)
    try:
        parsed = parse_version(version)
    except InvalidVersionError:
        return False
    return satisfies(parsed, sets, include_prerelease)


def _parsed_pairs(texts: list[str]) -> tuple[list[Version], list[str]]:
    versions, kept = [], []
    for text in texts:
        try:
            versions.append(parse_version(text))
        except InvalidVersionError:
            continue
        kept.append(text)
    return versions, kept


def max_satisfying_text(texts: list[str], range_text: str, include_prerelease: bool = False) -> str | None:
    """Return the highest satisfying version string, skipping bad ones."""
    sets = parse_range(range_text)
    versions, kept = _parsed_pairs(texts)
    best = max_satisfying(versions, sets, include_prerelease)
    return None if best is None else kept[versions.index(best)]


def min_satisfying_text(texts: list[str], range_text: str, include_prerelease: bool = False) -> str | None:
    """Return the lowest satisfying version string, skipping bad ones."""
    sets = parse_range(range_text)
    versions, kept = _parsed_pairs(texts)
    best = min_satisfying(versions, sets, include_prerelease)
    return None if best is None else kept[versions.index(best)]


def normalize_range(text: str) -> str:
    """Return the canonical form of a range string."""
    return format_range(parse_range(text))


# ---- report ----

def _split_valid(texts: list[str]) -> tuple[list[str], list[str]]:
    good, bad = [], []
    for text in texts:
        try:
            parse_version(text)
        except InvalidVersionError:
            bad.append(text)
            continue
        good.append(text)
    return good, bad


def _line(cells: list[str], widths: list[int]) -> str:
    return "  ".join(cell.ljust(width) for cell, width in zip(cells, widths)).rstrip()


def _row(text: str, parsed: list[tuple[tuple[Comparator, ...], ...]]) -> list[str]:
    version = parse_version(text)
    return [text] + ["yes" if satisfies(version, p) else "no" for p in parsed]


def render_table(texts: list[str], ranges: list[str]) -> str:
    """Render one row per valid version and one column per range."""
    parsed = [parse_range(r) for r in ranges]
    good, bad = _split_valid(texts)
    rows = [["version"] + list(ranges)]
    rows.extend(_row(text, parsed) for text in sort_text(good))
    widths = [max(len(row[i]) for row in rows) for i in range(len(rows[0]))]
    lines = [_line(rows[0], widths), _line(["-" * w for w in widths], widths)]
    lines.extend(_line(row, widths) for row in rows[1:])
    lines.extend(f"invalid: {text}" for text in bad)
    return "\n".join(lines)

