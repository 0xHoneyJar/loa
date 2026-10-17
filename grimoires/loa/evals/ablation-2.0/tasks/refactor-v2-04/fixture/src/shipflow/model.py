"""The shipment record."""
from dataclasses import dataclass, field


@dataclass
class Shipment:
    id: str
    weight_kg: float
    status: str = "pending"
    history: list = field(default_factory=list)


def new_shipment(shipment_id, weight_kg):
    """A pending shipment with no history."""
    if not isinstance(shipment_id, str) or not shipment_id:
        raise ValueError("a shipment needs an id")
    if isinstance(weight_kg, bool) or not isinstance(weight_kg, (int, float)) or weight_kg <= 0:
        raise ValueError(f"bad weight: {weight_kg!r}")
    return Shipment(shipment_id, float(weight_kg))


def is_final(shipment):
    """No event can move a returned or cancelled shipment."""
    return shipment.status in ("returned", "cancelled")
