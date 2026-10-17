"""Name and tag lookups over a store, rebuilt lazily."""


class Index:
    """Maps case-folded names to items and tags to skus.

    The maps are rebuilt on the first lookup after the store's revision
    moves; ``rebuilds`` counts the rebuilds.
    """

    def __init__(self, store):
        self._store = store
        self._seen = None
        self._by_name = {}
        self._by_tag = {}
        self.rebuilds = 0

    def _fresh(self):
        if self._seen == self._store.revision:
            return
        by_name, by_tag = {}, {}
        for item in self._store.items():
            by_name[item.key] = item
            for tag in item.tags:
                by_tag.setdefault(tag, []).append(item.sku)
        self._by_name = by_name
        self._by_tag = {tag: sorted(skus) for tag, skus in by_tag.items()}
        self._seen = self._store.revision
        self.rebuilds += 1

    def find(self, name):
        self._fresh()
        return self._by_name.get(name.strip().casefold())

    def with_tag(self, tag):
        self._fresh()
        return list(self._by_tag.get(tag.casefold(), ()))
