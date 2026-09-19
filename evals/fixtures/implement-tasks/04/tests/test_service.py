from accounts.service import register
from accounts.store import MemoryStore


def test_register_persists():
    store = MemoryStore()
    rec = register("ann@example.com", store)
    assert rec["active"] is True
    assert store.get("ann@example.com") is rec
    assert len(store) == 1
