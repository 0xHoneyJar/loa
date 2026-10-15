"""fetchq: plan HTTP fetches (URLs, timeouts, retry back-off) without sending anything."""
from .api import plan, replay

__all__ = ["plan", "replay"]
