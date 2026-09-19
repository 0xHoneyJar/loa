import re


def slugify(text: str) -> str:
    """Lowercase the text, turn every non-alphanumeric character into '-', strip edge hyphens."""
    s = text.lower()
    s = re.sub(r"[^a-z0-9]", "-", s)
    return s.strip("-")
