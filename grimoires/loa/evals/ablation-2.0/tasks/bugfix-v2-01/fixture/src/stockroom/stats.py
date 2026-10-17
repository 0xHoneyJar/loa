"""Per-category counts and the total quantity, computed lazily."""


class Summary:
    """Item counts per category and the total quantity of a store.

    The figures only change when items come or go, so they are recomputed
    on the first lookup after the store's size changes; ``rebuilds`` counts
    the recomputations.
    """

    def __init__(self, store):
        self._store = store
        self._seen = None
        self._counts = {}
        self._qty = 0
        self.rebuilds = 0

    def _fresh(self):
        size = len(self._store)
        if self._seen == size:
            return
        counts, qty = {}, 0
        for item in self._store.items():
            counts[item.category] = counts.get(item.category, 0) + 1
            qty += item.qty
        self._counts = {cat: counts[cat] for cat in sorted(counts)}
        self._qty = qty
        self._seen = size
        self.rebuilds += 1

    def counts(self):
        self._fresh()
        return dict(self._counts)

    def total_qty(self):
        self._fresh()
        return self._qty
