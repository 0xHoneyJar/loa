"""The block tree."""


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
        self.last_line_blank = False   # the last line this block saw was blank

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
        return self.kind == other.kind and self.delimiter == other.delimiter
