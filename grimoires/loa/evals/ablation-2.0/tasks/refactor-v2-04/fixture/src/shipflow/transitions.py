"""The lifecycle: which event moves a shipment from which status to which."""
EVENTS = {"pack": "packed", "ship": "shipped", "deliver": "delivered", "return": "returned", "cancel": "cancelled"}


def next_status(status, event):
    """The status after ``event`` from ``status``; ValueError when the event is not allowed there."""
    if event not in EVENTS:
        raise ValueError(f"unknown event: {event!r}")
    target = EVENTS[event]
    if status == "pending":
        allowed = ("packed", "cancelled")
    elif status == "packed":
        allowed = ("shipped", "cancelled")
    elif status == "shipped":
        allowed = ("delivered", "returned")
    elif status == "delivered":
        allowed = ("returned",)
    else:
        allowed = ()
    if target not in allowed:
        raise ValueError(f"cannot {event} a {status} shipment")
    return target


def advance(shipment, event):
    """Apply ``event`` to ``shipment`` and record it in its history."""
    shipment.status = next_status(shipment.status, event)
    shipment.history.append(event)
    return shipment


def replay(shipment_id, weight_kg, events):
    """A new shipment with ``events`` applied in order."""
    from .model import new_shipment

    shipment = new_shipment(shipment_id, weight_kg)
    for event in events:
        advance(shipment, event)
    return shipment
