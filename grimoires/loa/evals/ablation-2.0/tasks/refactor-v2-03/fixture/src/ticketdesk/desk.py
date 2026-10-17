"""The public face of the package: one ``Desk`` per support desk."""
from . import audit, config, reports, service, store
from . import clock as _clock


class Desk:
    """A support desk with its own settings, tickets, audit log and clock."""

    def __init__(self, *, sla_hours=None, max_open_per_agent=3, clock=None):
        config.configure(sla_hours=sla_hours, max_open_per_agent=max_open_per_agent)
        store.reset()
        audit.reset()
        _clock.set_clock(clock)

    def open(self, title, priority="normal"):
        return service.open_ticket(title, priority)

    def assign(self, ticket_id, agent):
        service.assign(ticket_id, agent)

    def resolve(self, ticket_id):
        service.resolve(ticket_id)

    def reopen(self, ticket_id):
        service.reopen(ticket_id)

    def ticket(self, ticket_id):
        return store.get(ticket_id)

    def due_at(self, ticket_id):
        return reports.due_at(store.get(ticket_id))

    def overdue(self):
        return reports.overdue()

    def workload(self):
        return reports.workload()

    def history(self, ticket_id):
        return reports.history(ticket_id)

    def events(self, ticket_id=None):
        return audit.events(ticket_id)
