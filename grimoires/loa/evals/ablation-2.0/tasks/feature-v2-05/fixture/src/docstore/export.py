"""Bundles: every document of a store in one JSON text.

A bundle is ``{"format": "docstore-bundle/1", "docs": [{"id", "rev", "doc"}, ...]}``
with the documents in id order. Import refuses a bundle whose ids collide with
existing documents unless ``replace`` is set.
"""
from .canon import canonical, parse_json
from .errors import ExportError
from .ids import is_valid_id

FORMAT = "docstore-bundle/1"


def export_bundle(store):
    docs = [{"id": i, "rev": store.revision(i), "doc": store.get(i)} for i in store.ids()]
    return canonical({"format": FORMAT, "docs": docs})


def _entries(text):
    try:
        data = parse_json(text, "bundle")
    except Exception as exc:
        raise ExportError(str(exc)) from None
    if not isinstance(data, dict) or data.get("format") != FORMAT:
        raise ExportError(f"bundle: not a {FORMAT} bundle")
    docs = data.get("docs")
    if not isinstance(docs, list):
        raise ExportError("bundle: 'docs' must be a list")
    seen = set()
    for n, item in enumerate(docs):
        if not isinstance(item, dict) or set(item) != {"id", "rev", "doc"}:
            raise ExportError(f"bundle: entry {n} must have exactly id, rev and doc")
        if not is_valid_id(item["id"]):
            raise ExportError(f"bundle: entry {n} has an invalid id")
        rev = item["rev"]
        if isinstance(rev, bool) or not isinstance(rev, int) or rev < 1:
            raise ExportError(f"bundle: entry {n} has an invalid rev")
        if item["id"] in seen:
            raise ExportError(f"bundle: duplicate id {item['id']!r}")
        seen.add(item["id"])
    return docs


def import_bundle(store, text, replace=False):
    """Load every bundle entry; returns the number of documents imported."""
    docs = _entries(text)
    if not replace:
        taken = [d["id"] for d in docs if store.exists(d["id"])]
        if taken:
            raise ExportError(f"bundle: ids already present: {', '.join(sorted(taken))}")
    for item in docs:
        store.load(item["id"], item["rev"], item["doc"], "bundle")
    return len(docs)
