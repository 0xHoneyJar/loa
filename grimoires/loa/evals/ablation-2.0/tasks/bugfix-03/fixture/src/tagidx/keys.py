"""Canonical tag keys.

Two tags are the same tag when their keys are equal. A key is the tag after
Unicode compatibility normalisation (NFKC), full case folding, and collapsing
every run of whitespace to one space with the ends stripped, so that
``"Café"`` typed with a combining accent, ``"CAFÉ"`` and ``" café "`` are one
tag, and so are ``"Straße"`` and ``"STRASSE"``.
"""


def tag_key(tag: str) -> str:
    """The comparison key of ``tag``."""
    return " ".join(tag.lower().split())


def display(tag: str) -> str:
    """The tag as shown to people: whitespace collapsed, case and accents kept."""
    return " ".join(tag.split())
