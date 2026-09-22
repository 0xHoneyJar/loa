from .store import MemoryStore


def register(email: str, store: MemoryStore) -> dict:
    """Create an active account for `email` and persist it."""
    record = {"email": email, "active": True}
    store.add(email, record)
    return record
