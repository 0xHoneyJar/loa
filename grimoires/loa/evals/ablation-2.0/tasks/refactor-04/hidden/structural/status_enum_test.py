"""Structure: one Status enum; no module compares or spells raw status strings."""
import ast
import enum
import pathlib

import pytest

PKG = pathlib.Path(__file__).resolve().parents[2] / "src" / "jobboard"
RAW = {"pending", "running", "done", "failed"}
USERS = ("board.py", "policy.py", "report.py")


def trees():
    return {p.name: ast.parse(p.read_text(encoding="utf-8")) for p in sorted(PKG.glob("*.py"))}


def test_status_enum_has_the_four_members():
    from jobboard.status import Status

    assert issubclass(Status, enum.Enum)
    assert {m.name: m.value for m in Status} == {"PENDING": "pending", "RUNNING": "running", "DONE": "done", "FAILED": "failed"}


def test_status_is_defined_once():
    where = [name for name, tree in trees().items() for n in ast.walk(tree) if isinstance(n, ast.ClassDef) and n.name == "Status"]
    assert where == ["status.py"]


@pytest.mark.parametrize("module", USERS)
def test_no_raw_status_strings_outside_the_enum(module):
    raw = [(n.lineno, n.value) for n in ast.walk(trees()[module]) if isinstance(n, ast.Constant) and isinstance(n.value, str) and n.value in RAW]
    assert raw == []


@pytest.mark.parametrize("module", USERS)
def test_module_uses_the_enum(module):
    tree = trees()[module]
    imported = any(
        (isinstance(n, ast.ImportFrom) and (n.module or "").split(".")[-1] == "status" and any(a.name == "Status" for a in n.names))
        or (isinstance(n, ast.ImportFrom) and any(a.name == "status" for a in n.names))
        or (isinstance(n, ast.Import) and any(a.name.split(".")[-1] == "status" for a in n.names))
        for n in ast.walk(tree)
    )
    used = any(
        isinstance(n, ast.Attribute) and (
            (isinstance(n.value, ast.Name) and n.value.id == "Status")
            or (isinstance(n.value, ast.Attribute) and n.value.attr == "Status"))
        for n in ast.walk(tree)
    )
    assert imported and used


def test_jobs_carry_enum_members():
    from jobboard import Board
    from jobboard.status import Status

    b = Board()
    job = b.submit("x")
    assert job["status"] is Status.PENDING
    b.start_next()
    assert job["status"] is Status.RUNNING
    assert b.finish(job["id"], True)["status"] is Status.DONE
