from batchkit import Item, Journal, Ledger, ResourcePool, run_batch


def _world(**balances):
    return ResourcePool(), Ledger(balances), Journal()


def test_a_clean_batch_commits():
    pool, ledger, journal = _world(a=10, b=0)
    items = [Item("i1", "a", -3), Item("i2", "b", 3), Item("i3", "a", 1)]
    report = run_batch(pool, ledger, journal, items, owner="nightly")
    assert report.status == "committed"
    assert report.applied == ["i1", "i2", "i3"]
    assert report.skipped == [] and report.failed is None and report.error is None
    assert report.summary() == "committed: 3 applied, 0 skipped"
    assert ledger.balances() == {"a": 8, "b": 3}
    assert journal.ids() == ["i1", "i2", "i3"]
    assert pool.locked() == []


def test_items_recorded_by_an_earlier_batch_are_skipped():
    pool, ledger, journal = _world(a=0)
    run_batch(pool, ledger, journal, [Item("i1", "a", 5)])
    report = run_batch(pool, ledger, journal, [Item("i1", "a", 5), Item("i2", "a", 1)])
    assert report.applied == ["i2"] and report.skipped == ["i1"]
    assert report.summary() == "committed: 1 applied, 1 skipped"
    assert ledger.balance("a") == 6


def test_batches_by_different_owners_run_one_after_another():
    pool, ledger, journal = _world(a=0, b=0)
    run_batch(pool, ledger, journal, [Item("x1", "a", 1)], owner="x")
    run_batch(pool, ledger, journal, [Item("y1", "a", 1), Item("y2", "b", 2)], owner="y")
    assert ledger.balances() == {"a": 2, "b": 2}
    assert pool.locked() == []
