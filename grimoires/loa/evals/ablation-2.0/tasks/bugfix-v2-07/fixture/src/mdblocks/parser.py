"""The block phase: lines into a tree of open and closed blocks.

Every line is processed in three steps.  First the open containers are
matched from the outside in, each consuming its prefix of the line.  Then
new block starts are looked for at the first non-space character.  What is
left is added as text: to the open paragraph as a lazy continuation, to a
leaf that takes lines, or as the first line of a new paragraph.
"""

from .continuation import ACCEPTS_LINES, CONSUMED, CONTINUE, UNMATCHED, can_contain
from .cursor import Cursor
from .finalize import finalize_block
from .lines import split_lines
from .node import Node
from .starts import CONTAINER_START, LEAF_START, MAYBE_SPECIAL, STARTS


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

        if cur.blank and container.last_child is not None:
            container.last_child.last_line_blank = True
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


def parse(text):
    """The block tree of a document."""
    return BlockParser().parse(text)
