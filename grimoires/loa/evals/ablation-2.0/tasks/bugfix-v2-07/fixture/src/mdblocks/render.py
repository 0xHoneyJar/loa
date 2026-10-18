"""Rendering the block tree to HTML, in markdown-it's layout."""

from .escape import escape_html
from .text import heading_text, paragraph_text


def _code(node):
    cls = f' class="language-{escape_html(node.info)}"' if node.fenced and node.info else ""
    return f"<pre><code{cls}>" + escape_html(node.literal) + "</code></pre>\n"


def _item(item, tight, out):
    if not item.children:
        out.append("<li></li>\n")
        return
    first = item.children[0]
    out.append("<li>" if tight and first.kind == "paragraph" else "<li>\n")
    for i, child in enumerate(item.children):
        if tight and child.kind == "paragraph":
            # a tight paragraph is written without tags; the next block starts on a new line
            out.append(escape_html(paragraph_text(child.content)))
            if i + 1 < len(item.children):
                out.append("\n")
        else:
            _block(child, out)
    out.append("</li>\n")


def _list(node, out):
    data = node.list_data
    if data.kind == "bullet":
        out.append("<ul>\n")
    else:
        out.append(f'<ol start="{data.start}">\n' if data.start > 1 else "<ol>\n")
    for item in node.children:
        _item(item, data.tight, out)
    out.append("</ul>\n" if data.kind == "bullet" else "</ol>\n")


def _block(node, out):
    kind = node.kind
    if kind == "paragraph":
        out.append("<p>" + escape_html(paragraph_text(node.content)) + "</p>\n")
    elif kind == "heading":
        out.append(f"<h{node.level}>" + escape_html(heading_text(node.content)) + f"</h{node.level}>\n")
    elif kind == "thematic_break":
        out.append("<hr>\n")
    elif kind == "code_block":
        out.append(_code(node))
    elif kind == "block_quote":
        out.append("<blockquote>\n")
        for child in node.children:
            _block(child, out)
        out.append("</blockquote>\n")
    elif kind == "list":
        _list(node, out)
    else:
        raise ValueError(f"unknown block kind: {kind}")


def render_tree(doc):
    out = []
    for child in doc.children:
        _block(child, out)
    return "".join(out)
