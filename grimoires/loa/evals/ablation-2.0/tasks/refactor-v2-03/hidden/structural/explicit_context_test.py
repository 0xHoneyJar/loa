"""Structure: a desk's state lives in an explicit context passed as ``ctx``, never in module state."""
import ast
import pathlib
from datetime import datetime, timedelta, timezone

import pytest

PKG = pathlib.Path(__file__).resolve().parents[2] / "src" / "ticketdesk"
TAKES_CTX = ("audit", "clock", "config", "reports", "service", "store")
T0 = datetime(2026, 10, 17, 9, 0, tzinfo=timezone.utc)


def trees():
    return {p.stem: ast.parse(p.read_text(encoding="utf-8")) for p in sorted(PKG.glob("*.py"))}


def constant_value(node):
    if isinstance(node, (ast.Constant, ast.Name, ast.Attribute)):
        return True
    if isinstance(node, ast.Tuple):
        return all(constant_value(e) for e in node.elts)
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "frozenset":
        if node.keywords or len(node.args) > 1:
            return False
        if not node.args:
            return True
        arg = node.args[0]
        if isinstance(arg, (ast.Set, ast.List, ast.Tuple)):
            return all(constant_value(e) for e in arg.elts)
        return constant_value(arg)
    return False


def is_field_call(node):
    return isinstance(node, ast.Call) and (
        (isinstance(node.func, ast.Name) and node.func.id == "field")
        or (isinstance(node.func, ast.Attribute) and node.func.attr == "field")
    )


def assignments(body):
    for node in body:
        if isinstance(node, ast.Assign):
            yield node.targets, node.value, node.lineno
        elif isinstance(node, ast.AnnAssign) and node.value is not None:
            yield [node.target], node.value, node.lineno


class FakeClock:
    def __init__(self, start):
        self.now = start

    def __call__(self):
        return self.now


def test_no_mutable_module_or_class_state():
    found = []
    for name, tree in trees().items():
        for targets, value, line in assignments(tree.body):
            if all(isinstance(t, ast.Name) and t.id == "__all__" for t in targets):
                continue
            if not constant_value(value):
                found.append(f"{name}:{line}")
        for cls in [n for n in ast.walk(tree) if isinstance(n, ast.ClassDef)]:
            for _, value, line in assignments(cls.body):
                if not (constant_value(value) or is_field_call(value)):
                    found.append(f"{name}:{line}")
    assert found == []


def test_no_global_or_nonlocal_statement():
    for name, tree in trees().items():
        assert not [n for n in ast.walk(tree) if isinstance(n, (ast.Global, ast.Nonlocal))], name


def test_no_configure_set_clock_or_reset():
    for name, tree in trees().items():
        defs = {n.name for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
        assert not defs & {"configure", "set_clock", "reset"}, name


def test_no_function_cache():
    def cache_name(dec):
        target = dec.func if isinstance(dec, ast.Call) else dec
        return getattr(target, "id", None) or getattr(target, "attr", None)

    for name, tree in trees().items():
        for fn in [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]:
            assert not [d for d in fn.decorator_list if cache_name(d) in ("cache", "lru_cache")], (name, fn.name)


@pytest.mark.parametrize("module", TAKES_CTX)
def test_public_functions_take_ctx_first(module):
    public = [n for n in trees()[module].body if isinstance(n, ast.FunctionDef) and not n.name.startswith("_")]
    assert public, module
    for fn in public:
        assert fn.args.args and fn.args.args[0].arg == "ctx", (module, fn.name)


def test_context_checks_the_settings():
    from ticketdesk.context import Context

    Context()
    Context(sla_hours={"high": 1}, max_open_per_agent=5, clock=None)
    with pytest.raises(ValueError, match="^unknown priority: 'urgent'$"):
        Context(sla_hours={"urgent": 1})
    with pytest.raises(ValueError, match="^bad max_open_per_agent: 0$"):
        Context(max_open_per_agent=0)


def test_functions_work_on_an_explicit_context():
    from ticketdesk import reports, service
    from ticketdesk.context import Context

    ctx, other = Context(clock=FakeClock(T0)), Context(clock=FakeClock(T0))
    assert service.open_ticket(ctx, "x", "high") == 1
    assert service.open_ticket(other, "y") == 1
    service.assign(ctx, 1, "ana")
    assert reports.workload(ctx) == {"ana": 1} and reports.workload(other) == {}
    assert reports.history(ctx, 1) == ["2026-10-17 09:00 opened priority=high", "2026-10-17 09:00 assigned agent=ana"]


def test_two_desks_do_not_share_tickets_events_or_limits():
    from ticketdesk import Desk

    a = Desk(clock=FakeClock(T0), max_open_per_agent=1)
    a.open("a1")
    b = Desk(clock=FakeClock(T0))
    assert b.open("b1") == 1
    assert a.open("a2") == 2
    assert a.ticket(1).title == "a1" and b.ticket(1).title == "b1"
    assert [e["ticket"] for e in a.events()] == [1, 2]
    assert [e["ticket"] for e in b.events()] == [1]
    a.assign(1, "ana")
    b.assign(1, "ana")
    with pytest.raises(ValueError, match="^ana already has 1 open tickets$"):
        a.assign(2, "ana")
    assert a.workload() == {"ana": 1} and b.workload() == {"ana": 1}


def test_each_desk_keeps_its_own_settings_and_clock():
    from ticketdesk import Desk

    clock_a, clock_b = FakeClock(T0), FakeClock(T0 + timedelta(hours=10))
    a = Desk(clock=clock_a, sla_hours={"normal": 1})
    b = Desk(clock=clock_b, sla_hours={"normal": 48})
    ta, tb = a.open("x"), b.open("y")
    assert a.due_at(ta) == T0 + timedelta(hours=1)
    assert b.due_at(tb) == T0 + timedelta(hours=58)
    clock_a.now += timedelta(hours=2)
    assert a.overdue() == [ta] and b.overdue() == []
    assert b.ticket(tb).opened_at == T0 + timedelta(hours=10)
