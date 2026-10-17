import pytest

from batchkit import (
    Item, Journal, Ledger, NotHeld, Overdraft, ResourceBusy, ResourcePool,
    UnknownAccount, apply_item,
)


def test_acquire_release_and_holder():
    pool = ResourcePool()
    pool.acquire("b", "x")
    pool.acquire("a", "x")
    pool.acquire("a", "x")
    assert pool.locked() == ["a", "b"]
    assert pool.holder("a") == "x" and pool.holder("c") is None
    pool.release("a", "x")
    assert pool.locked() == ["b"]


def test_lock_errors():
    pool = ResourcePool()
    pool.acquire("a", "x")
    with pytest.raises(ResourceBusy, match="resource a is locked by x"):
        pool.acquire("a", "y")
    with pytest.raises(NotHeld, match="resource a is not locked by y"):
        pool.release("a", "y")
    with pytest.raises(NotHeld, match="resource b is not locked by x"):
        pool.release("b", "x")


def test_lease_locks_sorted_distinct_names_and_releases():
    pool = ResourcePool()
    with pool.lease(["c", "a", "c", "b"], "x") as taken:
        assert taken == ["a", "b", "c"]
        assert pool.locked() == ["a", "b", "c"]
    assert pool.locked() == []


def test_lease_releases_when_the_block_raises():
    pool = ResourcePool()
    with pytest.raises(RuntimeError):
        with pool.lease(["a", "b"], "x"):
            raise RuntimeError("boom")
    assert pool.locked() == []


def test_ledger_apply_and_errors():
    ledger = Ledger({"a": 10, "b": 0})
    assert ledger.apply("a", -4) == 6
    assert ledger.balance("a") == 6
    with pytest.raises(Overdraft, match="overdraft on b: balance 0, change -1"):
        ledger.apply("b", -1)
    with pytest.raises(UnknownAccount, match="unknown account: zz"):
        ledger.apply("zz", 1)
    assert ledger.balances() == {"a": 6, "b": 0}
    assert ledger.accounts() == ["a", "b"]


def test_journal_records_once_in_order():
    journal = Journal(["i2"])
    journal.record("i1")
    journal.record("i2")
    assert journal.ids() == ["i2", "i1"]
    assert journal.seen("i1") and not journal.seen("i3")
    assert len(journal) == 2


def test_apply_item_skips_a_recorded_id():
    ledger = Ledger({"a": 1})
    journal = Journal(["done"])
    assert apply_item(ledger, journal, Item("done", "a", 5)) == "skipped"
    assert ledger.balance("a") == 1
    assert apply_item(ledger, journal, Item("new", "a", 5)) == "applied"
    assert ledger.balance("a") == 6


def test_item_validation():
    with pytest.raises(ValueError, match="item id must be a non-empty string"):
        Item("", "a", 1)
    with pytest.raises(TypeError, match="item amount must be an int"):
        Item("i", "a", 1.5)
