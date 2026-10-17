"""Splitting the input into lines."""

import re

_LINE_END = re.compile(r"\r\n|\n|\r")


def split_lines(text):
    """The lines of ``text``; a final line ending does not start another line."""
    lines = _LINE_END.split(text)
    if lines and lines[-1] == "":
        lines.pop()
    return lines


def is_blank(text):
    """True for a line (or the rest of one) that holds only spaces."""
    return text.strip(" ") == ""
