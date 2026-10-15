"""Split a free-text tag field into tags."""
import re

_SEP = re.compile(r"[,;\n]")


def parse_tags(text: str) -> list:
    """Tags in ``text``, split on commas, semicolons and newlines; a leading ``#`` is dropped; empty tags are skipped."""
    out = []
    for raw in _SEP.split(text):
        t = raw.strip()
        if t.startswith("#"):
            t = t[1:].strip()
        if t:
            out.append(t)
    return out
