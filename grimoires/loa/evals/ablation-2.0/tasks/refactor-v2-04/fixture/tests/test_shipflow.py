import json

import pytest

from shipflow import billing, model, notify, report, storage, tracking, transitions


def ship(events, sid="S1", kg=2.5):
    return transitions.replay(sid, kg, events)


def status_of(shipment):
    return storage.to_dict(shipment)["status"]


def test_new_shipment_is_pending():
    s = model.new_shipment("S1", 3)
    assert storage.to_dict(s) == {"id": "S1", "weight_kg": 3.0, "status": "pending", "history": []}
    assert not model.is_final(s)


@pytest.mark.parametrize("sid,kg,message", [("", 1, "a shipment needs an id"), ("S", 0, "bad weight: 0"), ("S", True, "bad weight: True")])
def test_new_shipment_checks(sid, kg, message):
    with pytest.raises(ValueError) as exc:
        model.new_shipment(sid, kg)
    assert str(exc.value) == message


@pytest.mark.parametrize("events,final", [
    (["pack", "ship", "deliver"], "delivered"),
    (["pack", "ship", "return"], "returned"),
    (["pack", "ship", "deliver", "return"], "returned"),
    (["cancel"], "cancelled"),
    (["pack", "cancel"], "cancelled"),
])
def test_lifecycle(events, final):
    s = ship(events)
    assert status_of(s) == final and s.history == events


@pytest.mark.parametrize("events,message", [
    (["ship"], "cannot ship a pending shipment"),
    (["pack", "pack"], "cannot pack a packed shipment"),
    (["pack", "ship", "cancel"], "cannot cancel a shipped shipment"),
    (["cancel", "pack"], "cannot pack a cancelled shipment"),
    (["pack", "ship", "return", "deliver"], "cannot deliver a returned shipment"),
    (["lose"], "unknown event: 'lose'"),
])
def test_disallowed_events(events, message):
    with pytest.raises(ValueError) as exc:
        ship(events)
    assert str(exc.value) == message


def test_final_statuses():
    assert model.is_final(ship(["cancel"])) and model.is_final(ship(["pack", "ship", "return"]))
    assert not model.is_final(ship(["pack", "ship", "deliver"]))


def test_charges():
    assert [billing.charge_for(ship(e, kg=2.5)) for e in ([], ["pack"], ["pack", "ship"], ["pack", "ship", "deliver"])] == [0, 150, 510, 510]
    assert billing.charge_for(ship(["pack", "ship", "return"], kg=0.2)) == 150 + 240
    assert billing.charge_for(ship(["cancel"])) == 0
    assert billing.charge_for(ship(["pack", "cancel"])) == 150
    assert billing.invoice_total([ship(["pack"]), ship(["pack", "ship"], kg=1)]) == 150 + 270


def test_messages_and_subjects():
    assert notify.message_for(ship([])) == "Shipment S1 is waiting to be packed."
    assert notify.message_for(ship(["pack", "ship"], sid="X9")) == "Shipment X9 is on its way."
    assert notify.message_for(ship(["pack", "ship", "return"])) == "Shipment S1 came back to us; a refund follows."
    assert notify.message_for(ship(["cancel"])) == "Shipment S1 was cancelled."
    assert notify.subject(ship(["pack", "ship", "deliver"])) == "[DELIVERED] shipment S1"


def test_should_notify():
    s = model.new_shipment("S1", 1)
    old = s.status
    transitions.advance(s, "pack")
    assert notify.should_notify(old, s) is False
    old = s.status
    transitions.advance(s, "ship")
    assert notify.should_notify(old, s) is True
    assert notify.should_notify(s.status, s) is False


def test_reports():
    shipments = [ship([], "A"), ship(["pack", "ship", "deliver"], "B"), ship(["pack"], "C"), ship([], "D"),
                 ship(["pack", "ship", "return"], "E"), ship(["cancel"], "F")]
    assert report.counts(shipments) == {"pending": 2, "packed": 1, "delivered": 1, "returned": 1, "cancelled": 1}
    assert list(report.counts(shipments)) == ["pending", "packed", "delivered", "returned", "cancelled"]
    assert report.summary_line(shipments) == "pending=2 packed=1 delivered=1 returned=1 cancelled=1"
    assert report.summary_line([]) == "no shipments"
    assert report.open_ids(shipments) == ["A", "C", "D"]
    assert report.return_rate(shipments) == 0.5
    assert report.return_rate(shipments[:1]) is None


def test_tracking():
    assert [tracking.eta_days(ship(e)) for e in ([], ["pack"], ["pack", "ship"], ["pack", "ship", "deliver"], ["cancel"])] == [3, 2, 1, None, None]
    assert tracking.timeline(ship(["pack", "ship", "deliver", "return"])) == "pending > packed > shipped > delivered > returned"
    assert tracking.is_late(ship(["pack", "ship"]), 3) and not tracking.is_late(ship(["pack", "ship"]), 2)
    assert not tracking.is_late(ship(["pack"]), 9)


def test_storage_round_trip():
    shipments = [ship(["pack", "ship"], "A", 1.5), ship(["cancel"], "B", 4)]
    text = storage.dumps(shipments)
    assert json.loads(text)[0] == {"history": ["pack", "ship"], "id": "A", "status": "shipped", "weight_kg": 1.5}
    back = storage.loads(text)
    assert [storage.to_dict(s) for s in back] == [storage.to_dict(s) for s in shipments]
    assert billing.charge_for(back[0]) == 150 + 240 and notify.message_for(back[1]) == "Shipment B was cancelled."
    transitions.advance(back[0], "deliver")
    assert status_of(back[0]) == "delivered"


def test_storage_defaults_and_errors():
    assert status_of(storage.from_dict({"id": "A", "weight_kg": "2"})) == "pending"
    with pytest.raises(ValueError) as exc:
        storage.from_dict({"id": "A", "weight_kg": 1, "status": "lost"})
    assert str(exc.value) == "unknown status: 'lost'"
    with pytest.raises(ValueError) as exc:
        storage.from_dict({"id": "A", "weight_kg": 1, "status": "Shipped"})
    assert str(exc.value) == "unknown status: 'Shipped'"
