"""Structure: one shared record validator, every reader delegates to it."""
import ast
import pathlib

import pytest

PKG = pathlib.Path(__file__).resolve().parents[2] / "src" / "ledgerio"
CALLERS = ("csv_import.py", "json_import.py", "api.py")
RULE_TEXT = (
    "record must be a mapping",
    "missing field",
    "id must be a non-empty string",
    "amount must be a non-negative number",
    "currency must be a three-letter ISO code",
    "date must be an ISO date",
)


def trees():
    return {p.name: ast.parse(p.read_text(encoding="utf-8")) for p in sorted(PKG.glob("*.py"))}


def strings(tree):
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            yield node.value


def test_exactly_one_validate_record_at_module_level_of_validation():
    found = []
    for name, tree in trees().items():
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == "validate_record":
                found.append((name, node in tree.body))
    assert found == [("validation.py", True)]


@pytest.mark.parametrize("caller", CALLERS)
def test_caller_imports_and_calls_the_shared_validator(caller):
    tree = trees()[caller]
    imported = any(
        (isinstance(n, ast.ImportFrom) and (n.module or "").split(".")[-1] == "validation"
         and any(a.name == "validate_record" for a in n.names))
        or (isinstance(n, ast.ImportFrom) and any(a.name == "validation" for a in n.names))
        or (isinstance(n, ast.Import) and any(a.name.split(".")[-1] == "validation" for a in n.names))
        for n in ast.walk(tree)
    )
    called = any(
        isinstance(n, ast.Call) and (
            (isinstance(n.func, ast.Name) and n.func.id == "validate_record")
            or (isinstance(n.func, ast.Attribute) and n.func.attr == "validate_record")
        )
        for n in ast.walk(tree)
    )
    assert imported and called


@pytest.mark.parametrize("caller", CALLERS)
def test_caller_keeps_no_copy_of_the_rules(caller):
    tree = trees()[caller]
    leftover = sorted({r for s in strings(tree) for r in RULE_TEXT if r in s})
    assert leftover == []
    dates = [n for n in ast.walk(tree) if isinstance(n, ast.Attribute) and n.attr in ("fromisoformat", "strptime")]
    assert dates == []
    funcs = [n.name for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]
    assert not any(f in ("_check", "_validate_row") for f in funcs)


def test_shared_validator_behaves():
    from ledgerio.errors import RecordError
    from ledgerio.validation import validate_record

    assert validate_record({"id": "a", "amount": 0, "currency": "EUR", "date": "2026-10-01"}) is None
    with pytest.raises(RecordError, match="^currency must be a three-letter ISO code$"):
        validate_record({"id": "a", "amount": 0, "currency": "EUR\n", "date": "2026-10-01"})
