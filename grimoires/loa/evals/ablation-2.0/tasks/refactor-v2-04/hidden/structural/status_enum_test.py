"""Structure: one Status enum; the vocabulary's words appear nowhere else; dispatch is exhaustive."""
import ast
import enum
import pathlib

import pytest

PKG = pathlib.Path(__file__).resolve().parents[2] / "src" / "shipflow"
MEMBERS = ("PENDING", "PACKED", "SHIPPED", "DELIVERED", "RETURNED", "CANCELLED")
WORDS = {m.lower() for m in MEMBERS}
USERS = ("billing", "model", "notify", "report", "storage", "tracking", "transitions")
DISPATCH = {"transitions": "next_status", "billing": "charge_for", "notify": "message_for"}


def trees():
    return {p.stem: ast.parse(p.read_text(encoding="utf-8")) for p in sorted(PKG.glob("*.py"))}


def test_status_is_an_enum_with_the_six_members_in_lifecycle_order():
    from shipflow.status import Status

    assert issubclass(Status, enum.Enum)
    assert [m.name for m in Status] == list(MEMBERS)
    assert [m.value for m in Status] == [m.lower() for m in MEMBERS]


def test_no_vocabulary_literal_outside_the_status_module():
    found = []
    for name, tree in trees().items():
        if name == "status":
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Constant) and isinstance(node.value, str) and node.value.lower() in WORDS:
                found.append(f"{name}:{node.lineno}:{node.value}")
    assert found == []


@pytest.mark.parametrize("module", USERS)
def test_module_imports_the_enum(module):
    imported = [
        a.name
        for n in ast.walk(trees()[module])
        if isinstance(n, ast.ImportFrom)
        and ((n.level == 1 and n.module == "status") or n.module == "shipflow.status")
        for a in n.names
    ]
    assert "Status" in imported


@pytest.mark.parametrize("module,func", sorted(DISPATCH.items()))
def test_dispatch_names_every_member_and_has_no_fallback(module, func):
    fn = next(n for n in trees()[module].body if isinstance(n, ast.FunctionDef) and n.name == func)
    named = {
        n.attr for n in ast.walk(fn)
        if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name) and n.value.id == "Status"
    }
    assert set(MEMBERS) <= named, set(MEMBERS) - named
    for n in ast.walk(fn):
        if isinstance(n, ast.If):
            assert not n.orelse or (len(n.orelse) == 1 and isinstance(n.orelse[0], ast.If)), f"else at line {n.lineno}"
        if isinstance(n, ast.match_case):
            assert not (isinstance(n.pattern, ast.MatchAs) and n.pattern.pattern is None), f"wildcard at line {n.pattern.lineno}"


def test_a_value_that_is_not_a_member_is_a_type_error():
    from shipflow import billing, notify, transitions
    from shipflow.model import Shipment

    for bad in (None, "pending", "shipped"):
        with pytest.raises(TypeError) as exc:
            transitions.next_status(bad, "pack")
        assert str(exc.value) == f"not a Status: {bad!r}"
        for fn in (billing.charge_for, notify.message_for):
            with pytest.raises(TypeError) as exc:
                fn(Shipment("S1", 1.0, bad))
            assert str(exc.value) == f"not a Status: {bad!r}"


def test_shipments_hold_members_everywhere():
    from shipflow import model, storage, transitions
    from shipflow.status import Status

    s = model.new_shipment("S1", 1)
    assert s.status is Status.PENDING
    transitions.advance(s, "pack")
    assert s.status is Status.PACKED
    assert transitions.next_status(Status.PACKED, "ship") is Status.SHIPPED
    assert transitions.replay("S2", 1, ["cancel"]).status is Status.CANCELLED
    back = storage.loads(storage.dumps([s]))
    assert back[0].status is Status.PACKED
    assert storage.from_dict({"id": "A", "weight_kg": 1}).status is Status.PENDING
