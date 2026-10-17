"""Whether an open block continues on the current line.

Each function returns ``MATCHED`` (the block continues and the cursor has
moved past its prefix), ``UNMATCHED`` (the block does not continue on this
line) or ``CONSUMED`` (the line is used up: a closing code fence).
"""

from .cursor import CODE_INDENT
from .markers import CLOSING_FENCE

MATCHED, UNMATCHED, CONSUMED = 0, 1, 2


def _document(parser, cur, node):
    return MATCHED


def _list(parser, cur, node):
    return MATCHED


def _block_quote(parser, cur, node):
    if not cur.indented and cur.peek(cur.next_nonspace) == ">":
        cur.advance_to_next_nonspace()
        cur.offset += 1
        if cur.peek() == " ":
            cur.offset += 1
        return MATCHED
    return UNMATCHED


def _item(parser, cur, node):
    data = node.list_data
    if cur.blank:
        cur.advance_to_next_nonspace()
    elif cur.indent >= data.padding:
        cur.offset += data.padding
    else:
        return UNMATCHED
    return MATCHED


def _code_block(parser, cur, node):
    if node.fenced:
        m = None
        if cur.indent <= 3 and cur.peek(cur.next_nonspace) == node.fence_char:
            m = CLOSING_FENCE.match(cur.rest(cur.next_nonspace))
        if m:
            parser.finalize(node, parser.line_number)
            return CONSUMED
        skip = node.fence_offset
        while skip > 0 and cur.peek() == " ":
            cur.offset += 1
            skip -= 1
        return MATCHED
    if cur.indent >= CODE_INDENT:
        cur.offset += CODE_INDENT
    elif cur.blank:
        cur.advance_to_next_nonspace()
    else:
        return UNMATCHED
    return MATCHED


def _paragraph(parser, cur, node):
    return UNMATCHED if cur.blank else MATCHED


def _single_line(parser, cur, node):
    return UNMATCHED


CONTINUE = {
    "document": _document,
    "list": _list,
    "block_quote": _block_quote,
    "item": _item,
    "code_block": _code_block,
    "paragraph": _paragraph,
    "heading": _single_line,
    "thematic_break": _single_line,
}

ACCEPTS_LINES = {"paragraph", "code_block"}


def can_contain(parent_kind, child_kind):
    """Which blocks may hold which."""
    if parent_kind == "list":
        return child_kind == "item"
    if parent_kind in ("document", "block_quote", "item"):
        return child_kind != "item"
    return False
