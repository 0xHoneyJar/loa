"""Reference model of the block-structure specification (grader-side only).

One module holding the reference parser and renderer. Its outputs were
cross-checked against markdown-it 14.1.0 on the generated input space; the
documents where markdown-it departs from CommonMark are listed in EXCLUDED
(sha256 prefixes) and skipped by the conformance cases.
"""

import re
from dataclasses import dataclass, field
from typing import List, Tuple


# ---- lines.py ----------------------------------------------------
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


# ---- node.py -----------------------------------------------------
class Node:
    """One block of the document.

    ``kind`` is one of ``document``, ``block_quote``, ``list``, ``item``,
    ``paragraph``, ``heading``, ``thematic_break``, ``code_block``.
    ``start_line`` and ``end_line`` are 1-based line numbers.
    """

    CONTAINERS = ("document", "block_quote", "list", "item")

    def __init__(self, kind, start_line=0):
        self.kind = kind
        self.parent = None
        self.children = []
        self.open = True
        self.start_line = start_line
        self.end_line = start_line
        self.content = ""          # raw lines of a leaf, each ending in "\n"
        self.level = 0             # heading level
        self.fenced = False
        self.fence_char = ""
        self.fence_length = 0
        self.fence_offset = 0
        self.info = ""
        self.literal = ""
        self.list_data = None

    @property
    def last_child(self):
        return self.children[-1] if self.children else None

    @property
    def next_sibling(self):
        if self.parent is None:
            return None
        sibs = self.parent.children
        i = sibs.index(self)
        return sibs[i + 1] if i + 1 < len(sibs) else None

    def append(self, child):
        child.parent = self
        self.children.append(child)
        return child

    def replace_with(self, other):
        """Put ``other`` in this node's place among its siblings."""
        sibs = self.parent.children
        sibs[sibs.index(self)] = other
        other.parent = self.parent
        self.parent = None

    def walk(self):
        yield self
        for child in self.children:
            yield from child.walk()

    def __repr__(self):
        return f"Node({self.kind!r}, lines {self.start_line}-{self.end_line})"


class ListData:
    """What a list marker says about its list and item."""

    def __init__(self, kind, marker_offset):
        self.kind = kind            # "bullet" or "ordered"
        self.bullet_char = None
        self.start = None
        self.delimiter = None
        self.marker_offset = marker_offset
        self.padding = 0
        self.tight = True

    def matches(self, other):
        """True when an item with ``other`` continues a list with this data."""
        return (self.kind == other.kind and self.delimiter == other.delimiter
                and self.bullet_char == other.bullet_char)


# ---- cursor.py ---------------------------------------------------
CODE_INDENT = 4


class Cursor:
    """Offset, next non-space position and indentation of the current line."""

    def __init__(self, line):
        self.line = line
        self.offset = 0
        self.next_nonspace = 0
        self.indent = 0
        self.indented = False
        self.blank = False

    def find_next_nonspace(self):
        i = self.offset
        while i < len(self.line) and self.line[i] == " ":
            i += 1
        self.next_nonspace = i
        self.indent = i - self.offset
        self.indented = self.indent >= CODE_INDENT
        self.blank = i >= len(self.line)

    def advance(self, count):
        self.offset = min(self.offset + count, len(self.line)) if count >= 0 else self.offset

    def advance_to_next_nonspace(self):
        self.offset = self.next_nonspace

    def peek(self, pos=None):
        pos = self.offset if pos is None else pos
        return self.line[pos] if pos < len(self.line) else ""

    def rest(self, pos=None):
        return self.line[self.offset if pos is None else pos:]


# ---- markers.py --------------------------------------------------
THEMATIC_BREAK = re.compile(r"^(?:\*[ ]*){3,}$|^(?:_[ ]*){3,}$|^(?:-[ ]*){3,}$")
ATX_OPEN = re.compile(r"^#{1,6}(?:[ ]+|$)")
CODE_FENCE = re.compile(r"^`{3,}(?!.*`)|^~{3,}")
CLOSING_FENCE = re.compile(r"^(?:`{3,}|~{3,})(?=[ ]*$)")
SETEXT_LINE = re.compile(r"^(?:=+|-+)[ ]*$")
BULLET = re.compile(r"^[*+-]")
ORDERED = re.compile(r"^(\d{1,9})([.)])")


def atx_content(rest):
    """The content of an ATX heading line after its opening sequence."""
    rest = re.sub(r"^[ ]*#+[ ]*$", "", rest)
    return re.sub(r"[ ]+#+[ ]*$", "", rest)


def parse_list_marker(cur, container_kind):
    """Read a list marker at the cursor; ``None`` when there is none.

    On success the cursor is advanced past the marker and the spaces that
    belong to it, and the returned data carries the item's padding.
    """
    if cur.indent >= 4:
        return None
    rest = cur.rest(cur.next_nonspace)
    m = BULLET.match(rest)
    if m:
        data = ListData("bullet", cur.indent)
        data.bullet_char = m.group(0)
    else:
        m = ORDERED.match(rest)
        if not m or (container_kind == "paragraph" and int(m.group(1)) != 1):
            return None
        data = ListData("ordered", cur.indent)
        data.start = int(m.group(1))
        data.delimiter = m.group(2)
    marker = m.group(0)
    after = cur.next_nonspace + len(marker)
    nextc = cur.peek(after)
    if nextc not in ("", " "):
        return None
    if container_kind == "paragraph" and cur.line[after:].strip(" ") == "":
        return None
    cur.advance_to_next_nonspace()
    cur.offset += len(marker)
    spaces_start = cur.offset
    spaces = 0
    while spaces < 5 and cur.peek(spaces_start + spaces) == " ":
        spaces += 1
    blank_item = spaces_start + spaces >= len(cur.line)
    if spaces >= 5 or spaces < 1 or blank_item:
        data.padding = len(marker) + 1
        if cur.peek() == " ":
            cur.offset += 1
    else:
        data.padding = len(marker) + spaces
        cur.offset += spaces
    return data


# ---- continuation.py ---------------------------------------------
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
        if not node.children:
            return UNMATCHED      # a blank line after an empty item ends it
        cur.advance_to_next_nonspace()
    elif cur.indent >= data.marker_offset + data.padding:
        cur.offset += data.marker_offset + data.padding
    else:
        return UNMATCHED
    return MATCHED


def _code_block(parser, cur, node):
    if node.fenced:
        m = None
        if cur.indent <= 3 and cur.peek(cur.next_nonspace) == node.fence_char:
            m = CLOSING_FENCE.match(cur.rest(cur.next_nonspace))
        if m and len(m.group(0)) >= node.fence_length:
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


# ---- starts.py ---------------------------------------------------
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
    node.content = atx_content(cur.rest())
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
    if cur.indented or container.kind != "paragraph":
        return NO_START
    m = SETEXT_LINE.match(cur.rest(cur.next_nonspace))
    if not m:
        return NO_START
    parser.close_unmatched()
    heading = Node("heading", container.start_line)
    heading.level = 1 if m.group(0)[0] == "=" else 2
    heading.content = container.content
    container.replace_with(heading)
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
    if cur.indented and parser.tip.kind != "paragraph" and not cur.blank:
        cur.offset += CODE_INDENT
        parser.close_unmatched()
        parser.add_child("code_block")
        return LEAF_START
    return NO_START


STARTS = (block_quote, atx_heading, fenced_code, setext_heading, thematic_break,
          list_item, indented_code)

MAYBE_SPECIAL = set("#`~*+_=<>0123456789-")


# ---- finalize.py -------------------------------------------------
def _ends_with_blank_line(node):
    """True when a blank line separates ``node`` from the block after it."""
    nxt = node.next_sibling
    return nxt is not None and node.end_line != nxt.start_line - 1


def _finalize_code_block(node):
    if node.fenced:
        first, _, rest = node.content.partition("\n")
        node.info = first.strip(" ")
        node.literal = rest
    else:
        lines = node.content.split("\n")
        while lines and lines[-1].strip(" ") == "":
            lines.pop()
        node.literal = "\n".join(lines) + "\n"
        node.end_line = node.start_line + len(lines) - 1   # trailing blank lines are not part of it
    node.content = ""


def _finalize_item(node):
    if node.children:
        node.end_line = node.children[-1].end_line
    else:
        node.end_line = node.start_line


def _finalize_list(node):
    data = node.list_data
    node.end_line = node.children[-1].end_line
    for item in node.children:
        if item.next_sibling is not None and _ends_with_blank_line(item):
            data.tight = False
            return
        for sub in item.children:
            if sub.next_sibling is not None and _ends_with_blank_line(sub):
                data.tight = False
                return


def _nothing(node):
    pass


FINALIZE = {
    "code_block": _finalize_code_block,
    "item": _finalize_item,
    "list": _finalize_list,
}


def finalize_block(node):
    FINALIZE.get(node.kind, _nothing)(node)


# ---- parser.py ---------------------------------------------------
class BlockParser:
    def __init__(self):
        self.doc = Node("document", 1)
        self.tip = self.doc
        self.old_tip = self.doc
        self.line_number = 0
        self.all_closed = True
        self.last_matched = self.doc
        self.cur = None

    # -- tree operations ---------------------------------------------------
    def add_child(self, kind):
        while not can_contain(self.tip.kind, kind):
            self.finalize(self.tip, self.line_number - 1)
        node = self.tip.append(Node(kind, self.line_number))
        self.tip = node
        return node

    def finalize(self, node, line_number):
        above = node.parent
        node.open = False
        node.end_line = line_number
        finalize_block(node)
        self.tip = above

    def close_unmatched(self):
        if not self.all_closed:
            while self.old_tip is not self.last_matched:
                parent = self.old_tip.parent
                self.finalize(self.old_tip, self.line_number - 1)
                self.old_tip = parent
            self.all_closed = True

    def add_line(self):
        self.tip.content += self.cur.rest() + "\n"

    # -- one line ------------------------------------------------------------
    def incorporate(self, line):
        cur = self.cur = Cursor(line)
        self.line_number += 1
        self.old_tip = self.tip
        container = self.doc
        while container.last_child is not None and container.last_child.open:
            container = container.last_child
            cur.find_next_nonspace()
            res = CONTINUE[container.kind](self, cur, container)
            if res == UNMATCHED:
                container = container.parent
                break
            if res == CONSUMED:
                return
        self.all_closed = container is self.old_tip
        self.last_matched = container

        matched_leaf = container.kind != "paragraph" and container.kind in ACCEPTS_LINES
        while not matched_leaf:
            cur.find_next_nonspace()
            if not cur.indented and cur.peek(cur.next_nonspace) not in MAYBE_SPECIAL:
                cur.advance_to_next_nonspace()
                break
            for start in STARTS:
                res = start(self, cur, container)
                if res == CONTAINER_START:
                    container = self.tip
                    break
                if res == LEAF_START:
                    container = self.tip
                    matched_leaf = True
                    break
            else:
                cur.advance_to_next_nonspace()
                break

        if not self.all_closed and not cur.blank and self.tip.kind == "paragraph":
            self.add_line()          # lazy paragraph continuation
            return
        self.close_unmatched()
        if container.kind in ACCEPTS_LINES:
            self.add_line()
        elif cur.offset < len(line) and not cur.blank:
            self.add_child("paragraph")
            cur.advance_to_next_nonspace()
            self.add_line()

    def parse(self, text):
        lines = split_lines(text)
        for line in lines:
            self.incorporate(line)
        while self.tip is not None:
            self.finalize(self.tip, len(lines))
        return self.doc




# ---- escape.py ---------------------------------------------------
_ESCAPES = {"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"}


def escape_html(text):
    """Escape ``&``, ``<``, ``>`` and ``"``."""
    return "".join(_ESCAPES.get(ch, ch) for ch in text)


# ---- text.py -----------------------------------------------------
def paragraph_text(content):
    """Lines without their surrounding spaces, joined by newlines, the whole trimmed."""
    lines = content.strip(" \n").split("\n")
    return "\n".join(line.strip(" ") for line in lines)


def heading_text(content):
    """A heading's text: one line (ATX) or the lines of a paragraph (setext), as for paragraphs."""
    return paragraph_text(content)


# ---- tokens.py ---------------------------------------------------
@dataclass
class Token:
    type: str                      # e.g. "paragraph_open", "inline", "fence"
    tag: str
    nesting: int                   # 1 opening, -1 closing, 0 self-contained
    block: bool = True
    hidden: bool = False
    content: str = ""
    info: str = ""
    attrs: List[Tuple[str, str]] = field(default_factory=list)


def _emit(node, out, tight):
    kind = node.kind
    if kind == "paragraph":
        out.append(Token("paragraph_open", "p", 1, hidden=tight))
        out.append(Token("inline", "", 0, block=False, content=paragraph_text(node.content)))
        out.append(Token("paragraph_close", "p", -1, hidden=tight))
    elif kind == "heading":
        tag = f"h{node.level}"
        out.append(Token("heading_open", tag, 1))
        out.append(Token("inline", "", 0, block=False, content=heading_text(node.content)))
        out.append(Token("heading_close", tag, -1))
    elif kind == "thematic_break":
        out.append(Token("hr", "hr", 0))
    elif kind == "code_block":
        if node.fenced:
            out.append(Token("fence", "code", 0, content=node.literal, info=node.info))
        else:
            out.append(Token("code_block", "code", 0, content=node.literal))
    elif kind == "block_quote":
        out.append(Token("blockquote_open", "blockquote", 1))
        for child in node.children:
            _emit(child, out, False)
        out.append(Token("blockquote_close", "blockquote", -1))
    elif kind == "list":
        data = node.list_data
        if data.kind == "bullet":
            out.append(Token("bullet_list_open", "ul", 1))
        else:
            attrs = [] if data.start == 1 else [("start", str(data.start))]
            out.append(Token("ordered_list_open", "ol", 1, attrs=attrs))
        for item in node.children:
            out.append(Token("list_item_open", "li", 1))
            for child in item.children:
                _emit(child, out, data.tight)
            out.append(Token("list_item_close", "li", -1))
        out.append(Token("bullet_list_close" if data.kind == "bullet" else "ordered_list_close",
                         "ul" if data.kind == "bullet" else "ol", -1))
    else:
        raise ValueError(f"unknown block kind: {kind}")


def to_tokens(doc):
    out = []
    for child in doc.children:
        _emit(child, out, False)
    return out


# ---- render.py ---------------------------------------------------
def _attrs(token):
    return "".join(f' {name}="{escape_html(value)}"' for name, value in token.attrs)


def _render_code_block(tokens, i):
    return "<pre><code>" + escape_html(tokens[i].content) + "</code></pre>\n"


def _fence(tokens, i):
    token = tokens[i]
    info = token.info.strip()
    lang = info.split()[0] if info else ""
    cls = f' class="language-{escape_html(lang)}"' if lang else ""
    return f"<pre><code{cls}>" + escape_html(token.content) + "</code></pre>\n"


RULES = {"code_block": _render_code_block, "fence": _fence}


def render_token(tokens, i):
    token = tokens[i]
    if token.hidden:
        return ""
    out = ""
    if token.block and token.nesting != -1 and i and tokens[i - 1].hidden:
        out += "\n"
    out += ("</" if token.nesting == -1 else "<") + token.tag + _attrs(token)
    need_lf = token.block
    if token.block and token.nesting == 1 and i + 1 < len(tokens):
        nxt = tokens[i + 1]
        if nxt.type == "inline" or nxt.hidden:
            need_lf = False
        elif nxt.nesting == -1 and nxt.tag == token.tag:
            need_lf = False
    return out + (">\n" if need_lf else ">")


def render_tokens(tokens):
    out = []
    for i, token in enumerate(tokens):
        if token.type == "inline":
            out.append(escape_html(token.content))
        elif token.type in RULES:
            out.append(RULES[token.type](tokens, i))
        else:
            out.append(render_token(tokens, i))
    return "".join(out)



def parse(text):
    return BlockParser().parse(text)


def render(text):
    return render_tokens(to_tokens(parse(text)))


EXCLUDED = frozenset({
    "00fa38889954f38c",
    "04c182e1967ab20d",
    "05ed21163854efa9",
    "072f2912be013f11",
    "0910f1213c260f44",
    "0993a9a8cbf5a40d",
    "0a1ccefcf64669c9",
    "0acc12d0b85977e7",
    "0b76e134d4ff658a",
    "0ba0c0b969152345",
    "0cf119d1a25e3836",
    "0d5fe4c17b39bfdc",
    "10c17c778ea53206",
    "117bd98bb35e6432",
    "13fc7d171153f60b",
    "145320818766686e",
    "14db343c8a351c95",
    "18ba9f89b49bc63f",
    "18efd356759fa783",
    "18f5fdd7cacf3785",
    "1b2376a5474d05b6",
    "1b3e443fd53cb7cd",
    "1cac92e56aa10465",
    "2011caab03153269",
    "208970d76a448adb",
    "2403c6f9233359e0",
    "26e0db685b37ccbb",
    "284f946a5a1b4b5a",
    "29134f52fe5e2e89",
    "2a24d5e14641c713",
    "2c09260f67d46a9d",
    "2cc154dc8f132616",
    "2cdaa1a69fe83de7",
    "2d5fe127d1c4e1b2",
    "2fd5497cdf7ebc85",
    "32f51918a39dd3da",
    "33bca3e4bbf2c81b",
    "33dbbbf36fe887a7",
    "359ee0e7998b446c",
    "39487f242ce64223",
    "39d1b2f49bbf15cf",
    "3ddb4efe6cf3b05c",
    "3e5292fda45e9f19",
    "3e903bacea0dc479",
    "3fcc8809c96f6d96",
    "3fd1e5abc8dd6e11",
    "40a835c8ea56cfce",
    "418fe5c482ea9e87",
    "436c12f41433d651",
    "46ad2e5f4a014f3d",
    "4781edf00054a14f",
    "481b2202690731f5",
    "482c9e1b5e3a5b2c",
    "495db9871f904192",
    "4c42893cea7c36f4",
    "4d98b52a57d39d00",
    "4eae0864364af4d3",
    "51d902a9464e10b6",
    "51f563b69eba0704",
    "523a7986d394fa23",
    "565aefb7604b071d",
    "56e4415b462b0c4e",
    "57842f80ef65d515",
    "58135b9bb5ea3521",
    "59872b5be344d2f3",
    "5a9028e515693d57",
    "5b64a9535e1e34dc",
    "5b6e098b25b4cbb1",
    "5c543654afb933ba",
    "5cb2d3b97372563b",
    "5d1d9dba4e695940",
    "5d99b2cc77b8f3b2",
    "600e3e8420f30877",
    "60250942d27d4d1c",
    "602ac376347d2ec9",
    "60cd63323d087acb",
    "64a8eb9f64d88d27",
    "660a1d1e210cad86",
    "672d16b99ed62865",
    "6eaf17dae33de761",
    "6eec1396b02bbbf6",
    "6f0e82f846369991",
    "716346b4a129bb43",
    "7188482bbf4272b2",
    "725e19b0445700c2",
    "74db8949a06077ef",
    "7503766120b49b14",
    "77d4559c42580577",
    "7846ed7279aa3875",
    "784fb6d1053d1429",
    "78697efd5e2443a3",
    "7cdad39f0818d96c",
    "7f89fcaf5acbd10b",
    "80ab94e028e56872",
    "82321fc985775cf4",
    "8257a21c6d59ba06",
    "84d392b56f976e4c",
    "86da5f60a45bc8c0",
    "872ab8fa8dfedf78",
    "8a24851c5666cca2",
    "8a95d94b8fa6f699",
    "8b8615231a8361dd",
    "8b8ef683e8591646",
    "8cc78467b6295ba3",
    "8f16b62c139b97a2",
    "909e8cb37a71e7b4",
    "91c23f106a33dd7c",
    "928eaa48dfa5dd07",
    "93905962715882e6",
    "950e74cc9cc5c7fe",
    "9954061755777c7d",
    "9b74f3a919eed716",
    "9c6347e95530f192",
    "9ca16ea4b79cdee9",
    "9cebe4004388ff02",
    "9d215e936584289d",
    "9e37dc1db8e9b5dc",
    "9e8dad53648da1ea",
    "9f87a58145833cc2",
    "a0ff71e9f766a6e6",
    "a35c2860cfc4aa09",
    "a544c240e1a0656f",
    "a587567ab8e2bffd",
    "a80c9693ebacc676",
    "a89793a0fd0425dc",
    "abcf1d70d8a81ac2",
    "ad8e4e8c61e3416c",
    "ae8a6e2e3c01a339",
    "b2215c55d7c2750d",
    "b221d9742676e9de",
    "b268a0404be5784c",
    "b28842d27fabe3fc",
    "b3e8ebfa9eac9bd4",
    "b6571c31d59467db",
    "ba36a44a714bf54c",
    "c03eb8dfac8cc3df",
    "c05a3a02eff6a10b",
    "c127f09a11ee3e83",
    "c22b23c3a2f7c852",
    "c259159db6fbb9ee",
    "c6096356e5e74139",
    "c8062f26f96f347c",
    "c93aa3c535977360",
    "c960aac6a5c47aac",
    "c9bc511102442545",
    "cc463e9559407164",
    "cd2eaec6c8b30212",
    "ce4e4e22582da390",
    "ced551ad607a6129",
    "cf2c4da50f129ca5",
    "cf664245cc6b6dc4",
    "d145d5a2a4c6c4b9",
    "d260d51a61591c62",
    "d2ad032f44822b78",
    "d2e415cc0ad556f3",
    "d2e5b304ed55e47a",
    "d3979c74abaac197",
    "d489068fc8546d02",
    "d516074db0ee97b5",
    "d747826508703d37",
    "d7ff0be93cc3959f",
    "d989472231f1f50f",
    "da78afa4f6502449",
    "de6c979699d6db48",
    "e003cb510a283182",
    "e167ee785aaa3038",
    "e19dbfae51e06aff",
    "e4c4db96dbdd441f",
    "e4e7331f100b4015",
    "e5568e932e4eb9af",
    "e671f607c145228a",
    "e8360f4ae1e76c51",
    "eac3c74b89db0110",
    "ec868a66a2408d0a",
    "ed817546f28431e0",
    "f02e04a7e87fd6bd",
    "f0404f4047cbe5e4",
    "f1813bf3f2ff69e6",
    "f4f68d6ac7324391",
    "f6395e59747549ce",
    "f6d3d2bfb30775d9",
    "f8505c40f7c8543b",
    "f914213c06db441a",
    "fa39bb89082bad80",
    "fa9a444881f2373c",
    "fb781a493ec3e71c",
    "ff9b4cf507d3996d"
})
