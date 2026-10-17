from collections import Counter

import pytest

from stockroom import DuplicateName, DuplicateSku, InvalidItem, Inventory, Item, UnknownSku


def stocked():
    inv = Inventory()
    inv.add(Item("A1", "Bolt", "hardware", 10, ("metal",)))
    inv.add(Item("B2", "Nut", "hardware", 4, ("metal", "small")))
    inv.add(Item("C3", "Glue", "supplies", 2))
    return inv


def agrees(inv):
    items = inv.items()
    assert inv.counts() == dict(sorted(Counter(i.category for i in items).items()))
    assert inv.total_qty() == sum(i.qty for i in items)
    for item in items:
        assert inv.find(item.name) == item
        for tag in item.tags:
            assert item.sku in inv.with_tag(tag)


def test_removed_item_is_gone_from_every_lookup():
    inv = stocked()
    inv.find("bolt")
    inv.remove("A1")
    assert inv.find("bolt") is None
    assert inv.with_tag("metal") == ["B2"]
    assert inv.counts() == {"hardware": 1, "supplies": 1}
    assert inv.total_qty() == 6
    agrees(inv)


def test_removed_name_and_sku_are_free_again():
    inv = stocked()
    inv.find("bolt")
    inv.remove("A1")
    inv.add(Item("A9", "BOLT", "fasteners", 1))
    assert inv.find("bolt").sku == "A9"
    inv.remove("C3")
    inv.add(Item("C3", "Tape", "supplies", 5))
    assert inv.find("tape").sku == "C3"
    assert inv.find("glue") is None
    agrees(inv)


def test_restore_brings_the_item_back():
    inv = stocked()
    inv.counts()
    inv.remove("A1")
    inv.counts()
    inv.restore("A1")
    assert inv.find("bolt").sku == "A1"
    assert inv.trash.skus() == []
    assert inv.counts() == {"hardware": 2, "supplies": 1}
    agrees(inv)


def test_restore_follows_the_add_rules():
    inv = stocked()
    inv.remove("A1")
    inv.add(Item("A7", "bolt", "hardware"))
    before = inv.revision
    with pytest.raises(DuplicateName):
        inv.restore("A1")
    assert inv.trash.skus() == ["A1"] and inv.revision == before
    inv.remove("A7")
    inv.add(Item("A1", "Rivet", "hardware"))
    with pytest.raises(DuplicateSku):
        inv.restore("A1")
    assert inv.trash.skus() == ["A1", "A7"] and inv.revision == before + 2
    with pytest.raises(UnknownSku):
        inv.restore("Q5")


def test_summary_follows_move_and_restock():
    inv = stocked()
    inv.counts()
    inv.move("C3", "hardware")
    assert inv.counts() == {"hardware": 3}
    inv.restock("A1", 5)
    assert inv.total_qty() == 21
    agrees(inv)


def test_summary_follows_a_remove_then_an_add():
    inv = stocked()
    assert inv.counts() == {"hardware": 2, "supplies": 1}
    inv.remove("C3")
    inv.add(Item("D4", "Saw", "tools", 1))
    assert inv.counts() == {"hardware": 2, "tools": 1}
    assert inv.total_qty() == 15
    agrees(inv)


def test_lookups_inside_a_batch_see_the_changes():
    inv = stocked()
    inv.find("bolt")
    inv.counts()
    start = inv.revision
    with inv.batch():
        inv.add(Item("D4", "Saw", "tools", 1, ("metal",)))
        assert inv.find("saw").sku == "D4"
        assert inv.with_tag("metal") == ["A1", "B2", "D4"]
        inv.remove("A1")
        assert inv.find("bolt") is None
        assert inv.counts() == {"hardware": 1, "supplies": 1, "tools": 1}
        inv.move("D4", "hardware")
        agrees(inv)
        assert inv.revision == start
    assert inv.revision == start + 1
    agrees(inv)


def test_revision_advances_once_per_change():
    inv = stocked()
    steps = [
        lambda: inv.add(Item("D4", "Saw", "tools")),
        lambda: inv.remove("D4"),
        lambda: inv.restore("D4"),
        lambda: inv.move("D4", "hardware"),
        lambda: inv.restock("D4", 3),
        lambda: inv.restock("D4", -1),
    ]
    for step in steps:
        before = inv.revision
        step()
        assert inv.revision == before + 1


def test_operations_that_change_nothing_keep_the_revision():
    inv = stocked()
    before = inv.revision
    inv.move("A1", "hardware")
    inv.restock("B2", 0)
    with pytest.raises(InvalidItem):
        inv.restock("B2", -10)
    with pytest.raises(InvalidItem):
        inv.move("B2", "")
    with pytest.raises(UnknownSku):
        inv.remove("Z9")
    with pytest.raises(DuplicateName):
        inv.add(Item("Z9", "nut", "x"))
    assert inv.revision == before
    with inv.batch():
        inv.move("A1", "hardware")
        inv.restock("A1", 0)
    assert inv.revision == before
    assert inv.store.get("A1").category == "hardware"
    assert inv.store.get("B2").qty == 4


def test_caches_rebuild_once_per_change_and_not_otherwise():
    inv = stocked()
    inv.find("bolt")
    inv.counts()
    for change in (lambda: inv.move("C3", "hardware"), lambda: inv.remove("B2"),
                   lambda: inv.restock("A1", 2)):
        built = (inv.index.rebuilds, inv.summary.rebuilds)
        change()
        inv.find("bolt"); inv.find("glue"); inv.with_tag("metal")
        inv.counts(); inv.total_qty()
        assert (inv.index.rebuilds, inv.summary.rebuilds) == (built[0] + 1, built[1] + 1)
    built = (inv.index.rebuilds, inv.summary.rebuilds)
    inv.move("A1", "hardware")
    inv.restock("A1", 0)
    inv.find("bolt"); inv.counts()
    assert (inv.index.rebuilds, inv.summary.rebuilds) == built


def test_an_inventory_that_becomes_empty():
    inv = Inventory()
    assert inv.counts() == {} and inv.total_qty() == 0 and inv.find("bolt") is None
    inv.add(Item("A1", "Bolt", "hardware", 3, ("metal",)))
    assert inv.find("bolt").sku == "A1" and inv.total_qty() == 3
    inv.remove("A1")
    assert inv.items() == []
    assert inv.find("bolt") is None
    assert inv.with_tag("metal") == []
    assert inv.counts() == {} and inv.total_qty() == 0
    assert inv.table() == ["(empty)"]
