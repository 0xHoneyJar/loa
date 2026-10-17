import pytest

from batchkit import Item, Journal, Ledger, ResourceBusy, ResourcePool, run_batch

OVERDRAFT = "overdraft on a: balance 5, change -20"


def _world(**balances):
    return ResourcePool(), Ledger(balances), Journal()


def _failing():
    return [Item("i1", "a", -5), Item("i2", "b", 3), Item("i3", "a", -20)]


def test_failed_batch_releases_its_locks():
    pool, ledger, journal = _world(a=10, b=0)
    run_batch(pool, ledger, journal, _failing(), owner="nightly")
    assert pool.locked() == []
    assert pool.holder("a") is None and pool.holder("b") is None


def test_next_batch_after_a_failure_runs():
    pool, ledger, journal = _world(a=10, b=0)
    run_batch(pool, ledger, journal, _failing(), owner="nightly")
    report = run_batch(pool, ledger, journal, [Item("j1", "b", 1)], owner="manual")
    assert report.status == "committed"
    assert ledger.balances() == {"a": 10, "b": 1}


def test_failed_batch_undoes_its_changes():
    pool, ledger, journal = _world(a=10, b=0)
    run_batch(pool, ledger, journal, _failing())
    assert ledger.balances() == {"a": 10, "b": 0}
    assert journal.ids() == []


def test_failed_batch_report():
    pool, ledger, journal = _world(a=10, b=0)
    report = run_batch(pool, ledger, journal, _failing())
    assert report.status == "rolled back"
    assert report.applied == []
    assert report.skipped == []
    assert report.failed == "i3"
    assert report.error == OVERDRAFT
    assert report.summary() == "rolled back at i3: " + OVERDRAFT


def test_retry_after_the_cause_is_fixed_applies_each_item_once():
    pool, ledger, journal = _world(a=10, b=0)
    run_batch(pool, ledger, journal, _failing())
    ledger.apply("a", 20)
    report = run_batch(pool, ledger, journal, _failing())
    assert report.status == "committed"
    assert report.applied == ["i1", "i2", "i3"]
    assert ledger.balances() == {"a": 5, "b": 3}
    assert journal.ids() == ["i1", "i2", "i3"]


def test_repeated_id_in_one_batch_is_applied_once():
    pool, ledger, journal = _world(a=10)
    items = [Item("i1", "a", 5), Item("i2", "a", 1), Item("i1", "a", 5)]
    report = run_batch(pool, ledger, journal, items)
    assert ledger.balance("a") == 16
    assert report.applied == ["i1", "i2"]
    assert report.skipped == ["i1"]
    assert report.summary() == "committed: 2 applied, 1 skipped"


def test_rollback_keeps_ids_of_earlier_batches():
    pool, ledger, journal = _world(a=10, b=0)
    run_batch(pool, ledger, journal, [Item("i0", "b", 2)])
    items = [Item("i0", "b", 2), Item("i1", "a", -1), Item("bad", "zz", 1)]
    report = run_batch(pool, ledger, journal, items)
    assert report.status == "rolled back"
    assert report.skipped == ["i0"] and report.applied == []
    assert report.summary() == "rolled back at bad: unknown account: zz"
    assert journal.ids() == ["i0"]
    assert ledger.balances() == {"a": 10, "b": 2}
    assert pool.locked() == []


def test_failure_on_the_first_item():
    pool, ledger, journal = _world(a=0)
    report = run_batch(pool, ledger, journal, [Item("i1", "a", -1), Item("i2", "a", 4)])
    assert report.failed == "i1" and report.applied == []
    assert report.summary() == "rolled back at i1: overdraft on a: balance 0, change -1"
    assert ledger.balance("a") == 0 and pool.locked() == []


def test_refused_batch_changes_nothing_and_leaves_no_lock():
    pool, ledger, journal = _world(a=10, b=0, c=0)
    pool.acquire("b", "other")
    items = [Item("i1", "a", 1), Item("i2", "b", 1), Item("i3", "c", 1)]
    with pytest.raises(ResourceBusy, match="resource b is locked by other"):
        run_batch(pool, ledger, journal, items, owner="nightly")
    assert pool.locked() == ["b"]
    assert pool.holder("a") is None
    assert ledger.balances() == {"a": 10, "b": 0, "c": 0}
    assert journal.ids() == []


def test_lease_that_cannot_lock_a_name_releases_the_rest():
    pool = ResourcePool()
    pool.acquire("b", "y")
    with pytest.raises(ResourceBusy, match="resource b is locked by y"):
        with pool.lease(["c", "a", "b"], "x"):
            pass
    assert pool.locked() == ["b"]
    assert pool.holder("b") == "y"


def test_empty_batch_commits():
    pool, ledger, journal = _world(a=1)
    report = run_batch(pool, ledger, journal, [])
    assert report.status == "committed"
    assert report.summary() == "committed: 0 applied, 0 skipped"
    assert report.failed is None and report.error is None
    assert pool.locked() == []
