import gc
import weakref

from layercfg import Store, get, lookup_stats


def make():
    s = Store({"db": {"host": "localhost", "port": 5432}, "debug": False})
    s.load({"db": {"port": 6543}})
    return s


def test_reload_is_seen_after_a_read():
    s = make()
    assert get(s, "db.port") == 6543
    s.load({"db": {"port": 7000}})
    assert get(s, "db.port") == 7000
    s.load({})
    assert get(s, "db.port") == 5432


def test_unset_is_seen_after_a_read():
    s = make()
    s.set("debug", True)
    assert get(s, "debug") is True
    s.unset("debug")
    assert get(s, "debug") is False


def test_default_is_per_call():
    s = make()
    assert get(s, "db.user", "alice") == "alice"
    assert get(s, "db.user", "bob") == "bob"
    assert get(s, "db.user") is None


def test_unhashable_default():
    s = make()
    assert get(s, "tags", []) == []
    assert get(s, "tags", ["a"]) == ["a"]


def test_override_after_read_still_works():
    s = make()
    assert get(s, "db.host") == "localhost"
    s.set("db", {"host": "db.internal"})
    assert get(s, "db.host") == "db.internal"
    assert get(s, "db.port") == 6543


def test_stores_are_independent():
    a, b = make(), make()
    b.load({"db": {"port": 1}})
    assert get(a, "db.port") == 6543
    assert get(b, "db.port") == 1


def test_memo_still_hits_when_nothing_changed():
    s = make()
    get(s, "db.port")
    s.load({"db": {"port": 7000}})
    before = lookup_stats()
    for _ in range(3):
        assert get(s, "db.port") == 7000
    after = lookup_stats()
    assert after["misses"] - before["misses"] == 1
    assert after["hits"] - before["hits"] == 2


def test_a_new_store_never_sees_a_discarded_one():
    # Each store is read once and dropped; a store the weakref shows as freed leaves
    # its address free, and CPython hands that address to a later Store within a few
    # allocations. A store that lands on a freed address must read its own value.
    # An implementation that keeps every store alive never frees one: nothing to check.
    freed, reused = set(), 0
    for i in range(500):
        s = Store({"k": i})
        if id(s) in freed:
            reused += 1
        assert get(s, "k") == i
        ref, addr = weakref.ref(s), id(s)
        del s
        gc.collect()
        if ref() is None:
            freed.add(addr)
        if reused >= 3:
            break
