from datetime import datetime, timedelta, timezone

import pytest

from ticketdesk import Desk


class FakeClock:
    def __init__(self, start=datetime(2026, 10, 17, 9, 0, tzinfo=timezone.utc)):
        self.now = start

    def __call__(self):
        return self.now

    def advance(self, **kw):
        self.now += timedelta(**kw)


@pytest.fixture
def clock():
    return FakeClock()


def test_ids_count_from_one_and_titles_are_stripped(clock):
    desk = Desk(clock=clock)
    assert desk.open("  printer jam ") == 1
    assert desk.open("vpn down", "high") == 2
    t = desk.ticket(1)
    assert (t.id, t.title, t.priority, t.status, t.agent, t.opened_at) == (1, "printer jam", "normal", "open", None, clock.now)


@pytest.mark.parametrize("title", ["", "   ", None, 3])
def test_a_ticket_needs_a_title(clock, title):
    desk = Desk(clock=clock)
    with pytest.raises(ValueError, match="^a ticket needs a title$"):
        desk.open(title)


def test_unknown_priority_and_unknown_ticket(clock):
    desk = Desk(clock=clock)
    with pytest.raises(ValueError, match="^unknown priority: 'urgent'$"):
        desk.open("x", "urgent")
    with pytest.raises(KeyError, match="no ticket 9"):
        desk.ticket(9)
    assert desk.events() == []


def test_assign_resolve_reopen_cycle(clock):
    desk = Desk(clock=clock)
    tid = desk.open("disk full")
    with pytest.raises(ValueError, match="^ticket 1 is not assigned$"):
        desk.resolve(tid)
    desk.assign(tid, "ana")
    clock.advance(hours=2)
    desk.resolve(tid)
    assert desk.ticket(tid).status == "resolved" and desk.ticket(tid).resolved_at == clock.now
    with pytest.raises(ValueError, match="^ticket 1 is resolved$"):
        desk.assign(tid, "bo")
    desk.reopen(tid)
    assert desk.ticket(tid).status == "open" and desk.ticket(tid).resolved_at is None
    with pytest.raises(ValueError, match="^ticket 1 is open$"):
        desk.reopen(tid)


def test_open_ticket_limit_per_agent(clock):
    desk = Desk(clock=clock, max_open_per_agent=2)
    ids = [desk.open(f"t{i}") for i in range(4)]
    desk.assign(ids[0], "ana")
    desk.assign(ids[1], "ana")
    desk.assign(ids[1], "ana")
    with pytest.raises(ValueError, match="^ana already has 2 open tickets$"):
        desk.assign(ids[2], "ana")
    desk.resolve(ids[0])
    desk.assign(ids[2], "ana")
    assert desk.workload() == {"ana": 2}


def test_default_limit_is_three(clock):
    desk = Desk(clock=clock)
    for i in range(3):
        desk.assign(desk.open(f"t{i}"), "bo")
    with pytest.raises(ValueError, match="^bo already has 3 open tickets$"):
        desk.assign(desk.open("t4"), "bo")


@pytest.mark.parametrize("kwargs,message", [
    ({"sla_hours": {"urgent": 1}}, "unknown priority: 'urgent'"),
    ({"sla_hours": {"high": 0}}, "bad SLA for high: 0"),
    ({"sla_hours": {"low": True}}, "bad SLA for low: True"),
    ({"max_open_per_agent": 0}, "bad max_open_per_agent: 0"),
])
def test_bad_settings(kwargs, message):
    with pytest.raises(ValueError) as exc:
        Desk(**kwargs)
    assert str(exc.value) == message


def test_sla_defaults_and_overrides(clock):
    desk = Desk(clock=clock, sla_hours={"high": 1})
    high, normal, low = desk.open("a", "high"), desk.open("b"), desk.open("c", "low")
    assert [desk.due_at(i) - clock.now for i in (high, normal, low)] == [
        timedelta(hours=1), timedelta(hours=24), timedelta(hours=72)]


def test_overdue_orders_by_due_time_then_id(clock):
    desk = Desk(clock=clock, sla_hours={"high": 2, "normal": 4})
    a = desk.open("a")
    clock.advance(hours=1)
    b, c = desk.open("b", "high"), desk.open("c", "high")
    clock.advance(hours=2)
    assert desk.overdue() == []
    clock.advance(minutes=1)
    assert desk.overdue() == [b, c]
    clock.advance(hours=1)
    assert desk.overdue() == [b, c, a]
    desk.assign(b, "ana")
    desk.resolve(b)
    assert desk.overdue() == [c, a]


def test_history_lines(clock):
    desk = Desk(clock=clock)
    tid = desk.open("printer", "low")
    clock.advance(minutes=5)
    desk.assign(tid, "ana")
    clock.advance(minutes=5)
    desk.resolve(tid)
    assert desk.history(tid) == [
        "2026-10-17 09:00 opened priority=low",
        "2026-10-17 09:05 assigned agent=ana",
        "2026-10-17 09:10 resolved",
    ]
    assert [e["kind"] for e in desk.events()] == ["opened", "assigned", "resolved"]
    desk.events()[0]["kind"] = "changed"
    assert desk.events(tid)[0]["kind"] == "opened"


def test_clock_must_be_aware():
    desk = Desk(clock=lambda: datetime(2026, 10, 17, 9, 0))
    with pytest.raises(ValueError, match="^the clock must return an aware datetime$"):
        desk.open("x")


def test_system_clock_by_default():
    desk = Desk()
    before = datetime.now(timezone.utc)
    tid = desk.open("x")
    assert before <= desk.ticket(tid).opened_at <= datetime.now(timezone.utc)


def test_a_new_desk_starts_empty(clock):
    first = Desk(clock=clock)
    first.open("x")
    second = Desk(clock=clock)
    assert second.open("y") == 1
    assert [e["ticket"] for e in second.events()] == [1]
