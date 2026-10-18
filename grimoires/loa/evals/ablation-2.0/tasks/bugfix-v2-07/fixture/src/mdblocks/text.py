"""The text of paragraphs and headings (no inline syntax is interpreted)."""


def paragraph_text(content):
    """Lines without their surrounding spaces, joined by newlines, the whole trimmed."""
    lines = content.strip(" \n").split("\n")
    return "\n".join(line.strip(" ") for line in lines)


def heading_text(content):
    """A heading's text: one line (ATX) or the lines of a paragraph (setext), as for paragraphs."""
    return paragraph_text(content)
