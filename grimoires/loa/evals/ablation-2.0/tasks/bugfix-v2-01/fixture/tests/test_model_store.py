import pytest

from stockroom import InvalidItem, Item, Store, UnknownSku


def test_item_folds_tags():
    item = Item("A1", "Bolt", "hardware", 3, ("Metal", "SMALL"))
    assert item.tags == frozenset({"metal", "small"})
    assert item.key == "bolt"


@pytest.mark.parametrize("kwargs", [
    {"sku": "", "name": "x", "category": "c"},
    {"sku": "A 1", "name": "x", "category": "c"},
    {"sku": "A1", "name": "  ", "category": "c"},
    {"sku": "A1", "name": "x", "category": ""},
    {"sku": "A1", "name": "x", "category": "c", "qty": -1},
    {"sku": "A1", "name": "x", "category": "c", "tags": "metal"},
])
def test_invalid_items_are_refused(kwargs):
    with pytest.raises(InvalidItem):
        Item(**kwargs)


def test_store_put_get_and_order():
    store = Store()
    store.put(Item("B2", "Nut", "hardware"))
    store.put(Item("A1", "Bolt", "hardware"))
    assert [i.sku for i in store.items()] == ["A1", "B2"]
    assert store.get("A1").name == "Bolt"
    assert len(store) == 2 and "B2" in store
    assert store.revision == 2


def test_unknown_sku_message():
    with pytest.raises(UnknownSku) as err:
        Store().get("Z9")
    assert str(err.value) == "unknown sku: Z9"
    assert isinstance(err.value, KeyError)


def test_batch_groups_changes():
    store = Store()
    with store.batch():
        store.put(Item("A1", "Bolt", "hardware"))
        with store.batch():
            store.put(Item("B2", "Nut", "hardware"))
        assert store.revision == 0
    assert store.revision == 1
    with store.batch():
        pass
    assert store.revision == 1
