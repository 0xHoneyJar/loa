"""Dotted-path selection and simple equality search.

A dotted path is ``key.key.0``: each part names an object member, or, on a list,
a decimal index. The empty path selects the whole document.
"""
from .errors import NotFound

_MISSING = object()


def select(doc, path):
    """Return the value at a dotted path, or raise NotFound."""
    value = doc
    if path == "":
        return value
    for part in path.split("."):
        if isinstance(value, dict) and part in value:
            value = value[part]
        elif isinstance(value, list) and part.isdigit() and int(part) < len(value):
            value = value[int(part)]
        else:
            raise NotFound(f"no value at {path!r}")
    return value


def try_select(doc, path):
    try:
        return select(doc, path)
    except NotFound:
        return _MISSING


def find(store, path, value):
    """Return the sorted ids of documents whose value at ``path`` equals ``value``."""
    hits = []
    for doc_id in store.ids():
        found = try_select(store.get(doc_id), path)
        if found is not _MISSING and type(found) is type(value) and found == value:
            hits.append(doc_id)
    return hits
