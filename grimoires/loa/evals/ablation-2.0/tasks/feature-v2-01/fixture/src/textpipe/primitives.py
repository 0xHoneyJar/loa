"""The built-in filters: name -> (function, description)."""

import re

_SPACE_RUN = re.compile(r"\s+")


def _squeeze(line):
    return _SPACE_RUN.sub(" ", line)


def _reverse(line):
    return line[::-1]


PRIMITIVES = {
    "lower": (str.lower, "lowercase the line"),
    "rev": (_reverse, "reverse the characters of the line"),
    "squeeze": (_squeeze, "collapse each run of whitespace to one space"),
    "strip": (str.strip, "remove leading and trailing whitespace"),
    "upper": (str.upper, "uppercase the line"),
}
