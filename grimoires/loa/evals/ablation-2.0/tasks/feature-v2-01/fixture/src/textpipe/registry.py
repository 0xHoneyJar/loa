"""The filter registry."""

from .errors import RegistryError
from .model import Filter
from .primitives import PRIMITIVES


class Registry:
    """Filters by name."""

    def __init__(self):
        self._filters = {}

    @classmethod
    def with_builtins(cls):
        registry = cls()
        for name, (func, description) in PRIMITIVES.items():
            registry._filters[name] = Filter(name, (func,), description)
        return registry

    def __contains__(self, name):
        return name in self._filters

    def get(self, name):
        try:
            return self._filters[name]
        except KeyError:
            raise RegistryError(f"unknown filter: {name}") from None

    def names(self):
        return sorted(self._filters)

    def entries(self):
        return [self._filters[name] for name in self.names()]
