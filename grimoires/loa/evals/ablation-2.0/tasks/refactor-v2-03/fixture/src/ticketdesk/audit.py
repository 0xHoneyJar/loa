"""An append-only log of what happened to each ticket."""
_EVENTS = []


def reset():
    _EVENTS.clear()


def record(kind, ticket_id, at, **data):
    _EVENTS.append({"kind": kind, "ticket": ticket_id, "at": at, **data})


def events(ticket_id=None):
    """Copies of the events, oldest first; only ``ticket_id``'s when given."""
    return [dict(e) for e in _EVENTS if ticket_id is None or e["ticket"] == ticket_id]
