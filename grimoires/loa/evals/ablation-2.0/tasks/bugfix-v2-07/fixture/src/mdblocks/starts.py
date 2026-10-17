"""Block starts, tried in order at the first non-space character of a line.

Each function returns ``NO_START``, ``CONTAINER_START`` (a container was
opened and the rest of the line is examined for more starts) or
``LEAF_START`` (a leaf was opened and the rest of the line is its content).
"""

from .cursor import CODE_INDENT
from .markers import (ATX_OPEN, CODE_FENCE, SETEXT_LINE, THEMATIC_BREAK,
                      heading_text, parse_list_marker)
from .node import Node

NO_START, CONTAINER_START, LEAF_START = 0, 1, 2


def block_quote(parser, cur, container):
    if not cur.indented and cur.peek(cur.next_nonspace) == ">":
        cur.advance_to_next_nonspace()
        cur.offset += 1
        if cur.peek() == " ":
            cur.offset += 1
        parser.close_unmatched()
        parser.add_child("block_quote")
        return CONTAINER_START
    return NO_START


def atx_heading(parser, cur, container):
    if cur.indented:
        return NO_START
    m = ATX_OPEN.match(cur.rest(cur.next_nonspace))
    if not m:
        return NO_START
    cur.advance_to_next_nonspace()
    cur.offset += len(m.group(0))
    parser.close_unmatched()
    node = parser.add_child("heading")
    node.level = len(m.group(0).strip())
    node.content = heading_text(cur.rest())
    cur.offset = len(cur.line)
    return LEAF_START


def fenced_code(parser, cur, container):
    if cur.indented:
        return NO_START
    m = CODE_FENCE.match(cur.rest(cur.next_nonspace))
    if not m:
        return NO_START
    parser.close_unmatched()
    node = parser.add_child("code_block")
    node.fenced = True
    node.fence_length = len(m.group(0))
    node.fence_char = m.group(0)[0]
    node.fence_offset = cur.indent
    cur.advance_to_next_nonspace()
    cur.offset += len(m.group(0))
    return LEAF_START


def setext_heading(parser, cur, container):
    para = parser.tip
    if cur.indented or para.kind != "paragraph":
        return NO_START
    m = SETEXT_LINE.match(cur.rest(cur.next_nonspace))
    if not m:
        return NO_START
    parser.close_unmatched()
    heading = Node("heading", para.start_line)
    heading.level = 1 if m.group(0)[0] == "=" else 2
    heading.content = para.content
    para.replace_with(heading)
    parser.tip = heading
    cur.offset = len(cur.line)
    return LEAF_START


def thematic_break(parser, cur, container):
    if cur.indented or not THEMATIC_BREAK.match(cur.rest(cur.next_nonspace)):
        return NO_START
    parser.close_unmatched()
    parser.add_child("thematic_break")
    cur.offset = len(cur.line)
    return LEAF_START


def list_item(parser, cur, container):
    if cur.indented and container.kind != "list":
        return NO_START
    data = parse_list_marker(cur, container.kind)
    if data is None:
        return NO_START
    parser.close_unmatched()
    if parser.tip.kind != "list" or not parser.tip.list_data.matches(data):
        lst = parser.add_child("list")
        lst.list_data = data
    item = parser.add_child("item")
    item.list_data = data
    return CONTAINER_START


def indented_code(parser, cur, container):
    if cur.indented and container.kind != "paragraph" and not cur.blank:
        cur.offset += CODE_INDENT
        parser.close_unmatched()
        parser.add_child("code_block")
        return LEAF_START
    return NO_START


STARTS = (block_quote, atx_heading, fenced_code, setext_heading, list_item,
          thematic_break, indented_code)

MAYBE_SPECIAL = set("#`~*+_=<>0123456789-")
