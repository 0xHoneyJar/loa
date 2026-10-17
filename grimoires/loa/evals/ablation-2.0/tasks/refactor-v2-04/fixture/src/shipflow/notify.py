"""Customer notifications."""


def message_for(shipment):
    status = shipment.status
    if status == "pending":
        return f"Shipment {shipment.id} is waiting to be packed."
    elif status == "packed":
        return f"Shipment {shipment.id} is packed and will leave soon."
    elif status == "shipped":
        return f"Shipment {shipment.id} is on its way."
    elif status == "delivered":
        return f"Shipment {shipment.id} was delivered."
    elif status == "returned":
        return f"Shipment {shipment.id} came back to us; a refund follows."
    else:
        return f"Shipment {shipment.id} was cancelled."


def subject(shipment):
    return f"[{shipment.status.upper()}] shipment {shipment.id}"


def should_notify(old_status, shipment):
    """Customers hear about every change except packing."""
    return shipment.status != old_status and shipment.status != "packed"
