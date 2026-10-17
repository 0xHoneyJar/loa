"""Read-only views over the desk."""
from datetime import timedelta

from . import audit, clock, config, store


def due_at(ticket):
    """When ``ticket`` breaches its SLA (counted from when it was opened)."""
    return ticket.opened_at + timedelta(hours=config.sla_hours_for(ticket.priority))


def overdue():
    """Ids of open tickets past their SLA, earliest due first (ties by id)."""
    current = clock.now()
    late = [t for t in store.all_tickets() if t.status == "open" and due_at(t) < current]
    return [t.id for t in sorted(late, key=lambda t: (due_at(t), t.id))]


def workload():
    """Open assigned tickets per agent, agents in name order."""
    counts = {}
    for t in store.all_tickets():
        if t.status == "open" and t.agent is not None:
            counts[t.agent] = counts.get(t.agent, 0) + 1
    return dict(sorted(counts.items()))


def history(ticket_id):
    """One line per event of ``ticket_id``: time, kind and its details."""
    store.get(ticket_id)
    lines = []
    for e in audit.events(ticket_id):
        extra = "".join(f" {k}={e[k]}" for k in sorted(e) if k not in ("kind", "ticket", "at"))
        lines.append(f"{e['at']:%Y-%m-%d %H:%M} {e['kind']}{extra}")
    return lines
