"""The journal of applied item ids (what makes a retry safe)."""


class Journal:
    """Item ids in the order they were recorded."""

    def __init__(self, ids=()):
        self._ids = []
        for item_id in ids:
            self.record(item_id)

    def seen(self, item_id):
        return item_id in self._ids

    def record(self, item_id):
        """Record ``item_id``; recording an id twice is a no-op."""
        if item_id not in self._ids:
            self._ids.append(item_id)

    def ids(self):
        return list(self._ids)

    def __len__(self):
        return len(self._ids)
