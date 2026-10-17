"""What a shipment has cost so far, in cents."""
import math

HANDLING = 150
RATE_PER_KG = 120


def postage(weight_kg):
    """Postage per started kilogram, at least one."""
    return RATE_PER_KG * max(1, math.ceil(weight_kg))


def charge_for(shipment):
    status = shipment.status
    if status == "pending":
        return 0
    if status == "cancelled":
        return HANDLING if "pack" in shipment.history else 0
    if status == "packed":
        return HANDLING
    if status in ("shipped", "delivered"):
        return HANDLING + postage(shipment.weight_kg)
    if status == "returned":
        return HANDLING + 2 * postage(shipment.weight_kg)
    return 0


def invoice_total(shipments):
    return sum(charge_for(s) for s in shipments)
