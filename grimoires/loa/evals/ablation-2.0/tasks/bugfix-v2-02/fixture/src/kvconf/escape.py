"""Quoting of values: the escapes and the scanner for a quoted value."""
from .model import ParseError

ESCAPES = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\t": "\\t", "\r": "\\r"}


def quote(value):
    """``value`` in double quotes, with the five escapes applied."""
    return '"' + "".join(ESCAPES.get(ch, ch) for ch in value) + '"'


def scan_quoted(text, line):
    """Split ``text`` (starting with a quote) into the quoted body and the rest.

    The body is returned still escaped; ``unquote`` decodes it.
    """
    i = 1
    while i < len(text):
        ch = text[i]
        if ch == "\\":
            i += 2
            continue
        if ch == '"':
            return text[1:i], text[i + 1:]
        i += 1
    raise ParseError(line, "unterminated quote")


def unquote(body, line):
    """Decode the escapes of a quoted body."""
    return (body.replace("\\n", "\n").replace("\\t", "\t").replace("\\r", "\r")
            .replace('\\"', '"').replace("\\\\", "\\"))
