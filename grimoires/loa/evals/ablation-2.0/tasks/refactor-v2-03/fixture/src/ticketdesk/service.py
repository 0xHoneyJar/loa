"""Ticket operations: open, assign, resolve, reopen."""
from . import audit, clock, config, store


def open_ticket(title, priority="normal"):
    title = title.strip() if isinstance(title, str) else ""
    if not title:
        raise ValueError("a ticket needs a title")
    config.sla_hours_for(priority)
    at = clock.now()
    ticket = store.add(title, priority, at)
    audit.record("opened", ticket.id, at, priority=priority)
    return ticket.id


def assign(ticket_id, agent):
    ticket = store.get(ticket_id)
    if ticket.status != "open":
        raise ValueError(f"ticket {ticket_id} is {ticket.status}")
    load = sum(1 for t in store.all_tickets() if t.agent == agent and t.status == "open" and t.id != ticket_id)
    if load >= config.max_open():
        raise ValueError(f"{agent} already has {load} open tickets")
    ticket.agent = agent
    audit.record("assigned", ticket_id, clock.now(), agent=agent)


def resolve(ticket_id):
    ticket = store.get(ticket_id)
    if ticket.status != "open":
        raise ValueError(f"ticket {ticket_id} is {ticket.status}")
    if ticket.agent is None:
        raise ValueError(f"ticket {ticket_id} is not assigned")
    at = clock.now()
    ticket.status, ticket.resolved_at = "resolved", at
    audit.record("resolved", ticket_id, at)


def reopen(ticket_id):
    ticket = store.get(ticket_id)
    if ticket.status != "resolved":
        raise ValueError(f"ticket {ticket_id} is {ticket.status}")
    ticket.status, ticket.resolved_at = "open", None
    audit.record("reopened", ticket_id, clock.now())
