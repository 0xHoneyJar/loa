"""JSON storage of shipments."""
import json

from .model import Shipment

STATUSES = ("pending", "packed", "shipped", "delivered", "returned", "cancelled")


def to_dict(shipment):
    return {"id": shipment.id, "weight_kg": shipment.weight_kg, "status": shipment.status, "history": list(shipment.history)}


def from_dict(data):
    status = data.get("status", "pending")
    if status not in STATUSES:
        raise ValueError(f"unknown status: {status!r}")
    return Shipment(data["id"], float(data["weight_kg"]), status, list(data.get("history", [])))


def dumps(shipments):
    return json.dumps([to_dict(s) for s in shipments], sort_keys=True)


def loads(text):
    return [from_dict(d) for d in json.loads(text)]
