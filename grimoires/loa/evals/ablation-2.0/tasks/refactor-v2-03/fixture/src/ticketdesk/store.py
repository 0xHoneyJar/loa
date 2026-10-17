"""Ticket storage; ids count up from 1."""
from dataclasses import dataclass

_TICKETS = {}
_NEXT_ID = 1


@dataclass
class Ticket:
    id: int
    title: str
    priority: str
    opened_at: object
    agent: object = None
    status: str = "open"
    resolved_at: object = None


def reset():
    global _NEXT_ID
    _TICKETS.clear()
    _NEXT_ID = 1


def add(title, priority, opened_at):
    global _NEXT_ID
    ticket = Ticket(_NEXT_ID, title, priority, opened_at)
    _TICKETS[ticket.id] = ticket
    _NEXT_ID += 1
    return ticket


def get(ticket_id):
    try:
        return _TICKETS[ticket_id]
    except KeyError:
        raise KeyError(f"no ticket {ticket_id}") from None


def all_tickets():
    return [_TICKETS[i] for i in sorted(_TICKETS)]
