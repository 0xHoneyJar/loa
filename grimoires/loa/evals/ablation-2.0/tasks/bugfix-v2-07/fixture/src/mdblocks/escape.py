"""HTML escaping."""

_ESCAPES = {"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"}


def escape_html(text):
    """Escape ``&``, ``<``, ``>`` and ``"``."""
    return "".join(_ESCAPES.get(ch, ch) for ch in text)
