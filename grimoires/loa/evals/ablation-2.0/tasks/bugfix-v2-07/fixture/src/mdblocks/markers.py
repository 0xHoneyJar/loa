"""Recognising block markers."""

import re

from .node import ListData

THEMATIC_BREAK = re.compile(r"^(?:\*[ ]*){3,}$|^(?:_[ ]*){3,}$|^(?:-[ ]*){3,}$")
ATX_OPEN = re.compile(r"^#{1,6}(?:[ ]+|$)")
CODE_FENCE = re.compile(r"^`{3,}(?!.*`)|^~{3,}")
CLOSING_FENCE = re.compile(r"^(?:`{3,}|~{3,})(?=[ ]*$)")
SETEXT_LINE = re.compile(r"^(?:=+|-+)[ ]*$")
LIST_MARKER = re.compile(r"([*+-]|(\d+)([.)]))(?= |$)( *)")


def heading_text(rest):
    """The content of an ATX heading line after its opening sequence."""
    rest = re.sub(r"^[ ]*#+[ ]*$", "", rest)
    return re.sub(r"[ ]*#+[ ]*$", "", rest)


def parse_list_marker(cur, container_kind):
    """Read a list marker at the cursor; ``None`` when there is none.

    On success the cursor is advanced past the marker and the spaces that
    belong to it, and the returned data carries the item's padding.
    """
    if cur.indent >= 4:
        return None
    m = LIST_MARKER.match(cur.line, cur.next_nonspace)
    if not m:
        return None
    marker, number, delimiter, spaces = m.group(1), m.group(2), m.group(3), m.group(4)
    if number is None:
        data = ListData("bullet", cur.indent)
        data.bullet_char = marker
    else:
        data = ListData("ordered", cur.indent)
        data.start = int(number)
        data.delimiter = delimiter
    rest_blank = cur.line[m.end():].strip(" ") == ""
    if container_kind == "paragraph" and rest_blank:
        return None
    cur.offset = cur.next_nonspace + len(marker)
    if not spaces or rest_blank:
        data.padding = len(marker) + 1
        if cur.peek() == " ":
            cur.offset += 1
    else:
        data.padding = len(marker) + len(spaces)
        cur.offset += len(spaces)
    return data
