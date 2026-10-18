"""Document id rules.

An id is 1 to 40 characters from ``a-z 0-9 _ -`` and starts with a letter or a
digit.
"""
import re

from .errors import InvalidId

_ID = re.compile(r"[a-z0-9][a-z0-9_-]{0,39}")


def check_id(doc_id):
    """Return ``doc_id`` unchanged, or raise InvalidId."""
    if not isinstance(doc_id, str) or not _ID.fullmatch(doc_id):
        raise InvalidId(f"invalid document id: {doc_id!r}")
    return doc_id


def is_valid_id(doc_id):
    try:
        check_id(doc_id)
    except InvalidId:
        return False
    return True
