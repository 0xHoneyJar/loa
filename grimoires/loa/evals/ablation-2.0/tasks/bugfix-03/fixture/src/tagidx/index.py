"""A counting index of tags."""
from .keys import display, tag_key
from .parse import parse_tags


class TagIndex:
    """Counts tags by key; the label shown for a tag is the first spelling seen."""

    def __init__(self):
        self._entries = {}

    def add(self, tag: str, n: int = 1) -> None:
        key = tag_key(tag)
        if not key:
            return
        entry = self._entries.setdefault(key, {"label": display(tag), "count": 0})
        entry["count"] += n

    def add_text(self, text: str) -> None:
        """Add every tag of a free-text tag field."""
        for t in parse_tags(text):
            self.add(t)

    def count(self, tag: str) -> int:
        entry = self._entries.get(tag_key(tag))
        return entry["count"] if entry else 0

    def remove(self, tag: str) -> bool:
        """Forget ``tag`` entirely; True when it was present."""
        key = tag.strip().lower()
        return self._entries.pop(key, None) is not None

    def merge(self, other: "TagIndex") -> None:
        """Add every count of ``other`` into this index."""
        for entry in other._entries.values():
            self.add(entry["label"], entry["count"])

    def labels(self) -> list:
        """``(label, count)`` pairs, most frequent first, ties by key."""
        items = sorted(self._entries.items(), key=lambda kv: (-kv[1]["count"], kv[0]))
        return [(e["label"], e["count"]) for _, e in items]

    def __len__(self) -> int:
        return len(self._entries)
