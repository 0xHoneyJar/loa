"""The ready queue: jobs that may start now."""


class ReadyQueue:
    """Ready job names grouped by priority, highest priority first.

    Within one priority, names leave in the order they were pushed.
    """

    def __init__(self):
        self._buckets = {}

    def push(self, job):
        """Add ``job`` (or move it to its current priority)."""
        self.discard(job.name)
        self._buckets.setdefault(job.priority, []).append(job.name)

    def discard(self, name):
        """Remove ``name`` if it is queued; do nothing otherwise."""
        for bucket in self._buckets.values():
            if name in bucket:
                bucket.remove(name)
                return

    def __contains__(self, name):
        return any(name in bucket for bucket in self._buckets.values())

    def __len__(self):
        return sum(len(bucket) for bucket in self._buckets.values())

    def names(self):
        """Every queued name in leaving order."""
        out = []
        for priority in sorted(self._buckets, reverse=True):
            out.extend(self._buckets[priority])
        return out

    def peek(self):
        """The name that would leave next, or None."""
        names = self.names()
        return names[0] if names else None

    def pop(self):
        """Remove and return the next name, or None when empty."""
        name = self.peek()
        if name is not None:
            self.discard(name)
        return name
