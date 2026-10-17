"""mdblocks: the block structure of CommonMark documents, rendered to HTML."""

from .node import Node
from .parser import parse
from .render import render_tree


def render(text):
    """The HTML of a document."""
    return render_tree(parse(text))


__all__ = ["Node", "parse", "render"]
