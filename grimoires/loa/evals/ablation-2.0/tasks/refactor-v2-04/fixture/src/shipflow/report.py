"""Counts and ratios over many shipments."""
ORDER = ["pending", "packed", "shipped", "delivered", "returned", "cancelled"]
OPEN = {"pending", "packed", "shipped"}


def counts(shipments):
    """Shipments per status, in lifecycle order, statuses with none left out."""
    result = {}
    for status in ORDER:
        n = sum(1 for s in shipments if s.status == status)
        if n:
            result[status] = n
    return result


def summary_line(shipments):
    return " ".join(f"{status}={n}" for status, n in counts(shipments).items()) or "no shipments"


def open_ids(shipments):
    return sorted(s.id for s in shipments if s.status in OPEN)


def return_rate(shipments):
    """Returned shipments as a share of those that reached the customer, or None."""
    reached = [s for s in shipments if s.status == "delivered" or s.status == "returned"]
    if not reached:
        return None
    return sum(1 for s in reached if s.status == "returned") / len(reached)
