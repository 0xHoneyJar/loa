"""Delivery estimates and the customer-facing timeline."""
from .transitions import EVENTS

DAYS_LEFT = {"pending": 3, "packed": 2, "shipped": 1}


def eta_days(shipment):
    """Days until delivery, or None once the shipment is delivered, returned or cancelled."""
    return DAYS_LEFT.get(shipment.status)


def timeline(shipment):
    """The statuses the shipment went through, starting from pending."""
    steps = ["pending"]
    for event in shipment.history:
        steps.append(EVENTS[event])
    return " > ".join(steps)


def is_late(shipment, days_since_shipped):
    return shipment.status == "shipped" and days_since_shipped > DAYS_LEFT["shipped"] + 1
