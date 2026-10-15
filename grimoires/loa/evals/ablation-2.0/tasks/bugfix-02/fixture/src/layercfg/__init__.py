"""layercfg: layered settings (defaults < loaded file < overrides) with dotted-key lookup."""
from .lookup import get, lookup_stats
from .store import Store

__all__ = ["Store", "get", "lookup_stats"]
