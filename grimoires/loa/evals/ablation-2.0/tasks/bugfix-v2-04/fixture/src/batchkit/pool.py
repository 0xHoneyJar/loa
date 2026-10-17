"""Named locks with owners."""
from contextlib import contextmanager

from .model import NotHeld, ResourceBusy


class ResourcePool:
    """A set of named locks.  Any name can be locked; each has at most one owner."""

    def __init__(self):
        self._holders = {}

    def acquire(self, name, owner):
        """Lock ``name`` for ``owner``; locking a name you already hold is a no-op."""
        holder = self._holders.get(name)
        if holder is not None and holder != owner:
            raise ResourceBusy(name, holder)
        self._holders[name] = owner

    def release(self, name, owner):
        """Unlock ``name``, which ``owner`` must hold."""
        if self._holders.get(name) != owner:
            raise NotHeld(name, owner)
        del self._holders[name]

    def holder(self, name):
        """The owner holding ``name``, or None."""
        return self._holders.get(name)

    def locked(self):
        """Every locked name, sorted."""
        return sorted(self._holders)

    @contextmanager
    def lease(self, names, owner):
        """Lock every distinct name in sorted order for the duration of the block."""
        taken = []
        for name in sorted(set(names)):
            self.acquire(name, owner)
            taken.append(name)
        try:
            yield taken
        finally:
            for name in reversed(taken):
                self.release(name, owner)
