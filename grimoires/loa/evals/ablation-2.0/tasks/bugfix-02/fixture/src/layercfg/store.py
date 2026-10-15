"""A settings store made of three layers.

Later layers win: the defaults given at construction, then the mapping passed
to ``load()`` (typically a parsed config file; each ``load()`` replaces the
previous file layer), then single-key overrides from ``set()``. Nested
mappings are merged key by key.

``generation`` counts the changes made to the store's content; readers that
cache derived values (see ``layercfg.lookup``) use it to tell whether a cached
value is still current.
"""
import copy


def _deep_merge(base: dict, top: dict) -> dict:
    out = dict(base)
    for k, v in top.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = v
    return out


class Store:
    def __init__(self, defaults=None):
        self._defaults = copy.deepcopy(dict(defaults or {}))
        self._file = {}
        self._overrides = {}
        self._merged = None
        self.generation = 0

    def load(self, mapping: dict) -> None:
        """Replace the file layer with ``mapping``."""
        self._file = copy.deepcopy(dict(mapping))
        self._merged = None

    def set(self, key: str, value) -> None:
        """Override one top-level key."""
        self._overrides[key] = copy.deepcopy(value)
        self._merged = None
        self.generation += 1

    def unset(self, key: str) -> None:
        """Drop the override for ``key`` (the file layer and defaults show again)."""
        self._overrides.pop(key, None)
        self._merged = None

    def merged(self) -> dict:
        """The effective settings as one nested dict (a fresh copy each call)."""
        if self._merged is None:
            m = _deep_merge(self._defaults, self._file)
            self._merged = _deep_merge(m, self._overrides)
        return copy.deepcopy(self._merged)
