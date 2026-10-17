"""The parser's position within the current line (no tab handling: input has no tabs)."""

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
