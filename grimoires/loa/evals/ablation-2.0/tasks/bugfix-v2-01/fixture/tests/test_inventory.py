import pytest

from stockroom import DuplicateName, DuplicateSku, InvalidItem, Inventory, Item, UnknownSku


@pytest.fixture
def inv():
    inv = Inventory()
    inv.add(Item("A1", "Bolt", "hardware", 10, ("metal",)))
    inv.add(Item("B2", "Nut", "hardware", 4, ("metal", "small")))
    inv.add(Item("C3", "Glue", "supplies", 2))
    return inv


def test_find_is_case_insensitive(inv):
    assert inv.find("bolt").sku == "A1"
    assert inv.find("  GLUE ").sku == "C3"
    assert inv.find("washer") is None


def test_duplicates_are_refused(inv):
    with pytest.raises(DuplicateSku):
        inv.add(Item("A1", "Washer", "hardware"))
    with pytest.raises(DuplicateName) as err:
        inv.add(Item("D4", "BOLT", "hardware"))
    assert str(err.value) == "duplicate name: BOLT"
    assert inv.revision == 3


def test_with_tag_is_sorted(inv):
    assert inv.with_tag("METAL") == ["A1", "B2"]
    assert inv.with_tag("small") == ["B2"]
    assert inv.with_tag("none") == []


def test_counts_and_table(inv):
    assert inv.counts() == {"hardware": 2, "supplies": 1}
    assert inv.total_qty() == 16
    assert inv.table() == ["category  items", "hardware      2", "supplies      1"]


def test_listing(inv):
    assert inv.listing() == [
        "A1  Bolt  [hardware]  x10",
        "B2  Nut  [hardware]  x4",
        "C3  Glue  [supplies]  x2",
    ]
    assert Inventory().table() == ["(empty)"]


def test_lookups_are_cached(inv):
    inv.find("bolt")
    inv.counts()
    built = (inv.index.rebuilds, inv.summary.rebuilds)
    inv.find("nut")
    inv.with_tag("metal")
    inv.counts()
    inv.total_qty()
    assert (inv.index.rebuilds, inv.summary.rebuilds) == built


def test_restock_below_zero_is_refused(inv):
    with pytest.raises(InvalidItem) as err:
        inv.restock("B2", -5)
    assert str(err.value) == "qty below zero: B2"
    assert inv.store.get("B2").qty == 4


def test_unknown_skus(inv):
    with pytest.raises(UnknownSku):
        inv.remove("Z9")
    with pytest.raises(UnknownSku):
        inv.move("Z9", "x")
    with pytest.raises(UnknownSku):
        inv.restore("A1")


def test_remove_puts_item_in_trash(inv):
    removed = inv.remove("C3")
    assert removed.name == "Glue"
    assert inv.trash.skus() == ["C3"]
    assert [i.sku for i in inv.items()] == ["A1", "B2"]
