"""Structure: the order-line check is defined once and every operation calls it directly."""
import ast
import inspect
import pathlib

import pytest

PKG = pathlib.Path(__file__).resolve().parents[2] / "src" / "orderdesk"
CALLERS = {
    "orders.py": ("place_order", "order_total"),
    "returns.py": ("return_items", "exchange"),
    "transfers.py": ("plan_transfer", "split_transfer"),
    "quotes.py": ("quote", "bulk_quote"),
}
MESSAGES = ("invalid sku: ", "invalid quantity for ")


def trees():
    return {p.name: ast.parse(p.read_text(encoding="utf-8")) for p in sorted(PKG.glob("*.py"))}


def outside_validation():
    return [(name, tree) for name, tree in trees().items() if name != "validation.py"]


def test_validation_constants_and_signature():
    from orderdesk import validation

    assert validation.MAX_QTY == 999 and validation.MAX_BULK_QTY == 9999
    params = inspect.signature(validation.validate_line).parameters
    assert list(params) == ["sku", "qty", "normalise", "max_qty"]
    assert params["normalise"].kind is inspect.Parameter.KEYWORD_ONLY and params["normalise"].default is False
    assert params["max_qty"].kind is inspect.Parameter.KEYWORD_ONLY and params["max_qty"].default == 999


def test_validate_line_behaviour():
    from orderdesk.validation import validate_line

    assert validate_line("ABC-0001", 999) == ("ABC-0001", 999)
    assert validate_line(" abc-0001 ", 2, normalise=True) == ("ABC-0001", 2)
    assert validate_line("XYZ-9000", 9999, max_qty=9999) == ("XYZ-9000", 9999)
    cases = [
        ((" abc-0001 ", 2), {}, "invalid sku: ' abc-0001 '"),
        ((" abc-0001", 0), {"normalise": True}, "invalid quantity for ABC-0001: 0"),
        (("ABC-0001", True), {}, "invalid quantity for ABC-0001: True"),
        (("ABC-0001", 1000), {}, "invalid quantity for ABC-0001: 1000"),
        (("ABC-0001", 2.0), {"max_qty": 9999}, "invalid quantity for ABC-0001: 2.0"),
        (("bad", 0), {}, "invalid sku: 'bad'"),
        ((5, 1), {"normalise": True}, "invalid sku: 5"),
    ]
    for args, kwargs, message in cases:
        with pytest.raises(ValueError) as exc:
            validate_line(*args, **kwargs)
        assert str(exc.value) == message


def test_validate_line_is_defined_once():
    found = [
        name
        for name, tree in trees().items()
        for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == "validate_line"
    ]
    assert found == ["validation.py"]


def test_validation_imports_nothing_from_the_package():
    tree = trees()["validation.py"]
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom):
            assert node.level == 0 and not (node.module or "").startswith("orderdesk")
        if isinstance(node, ast.Import):
            assert not [a for a in node.names if a.name.startswith("orderdesk")]


@pytest.mark.parametrize("module,func", [(m, f) for m, fs in CALLERS.items() for f in fs])
def test_operation_calls_validate_line_directly(module, func):
    tree = trees()[module]
    fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == func)
    calls = [
        n
        for n in ast.walk(fn)
        if isinstance(n, ast.Call)
        and ((isinstance(n.func, ast.Name) and n.func.id == "validate_line")
             or (isinstance(n.func, ast.Attribute) and n.func.attr == "validate_line"))
    ]
    assert calls, f"{module}:{func} does not call validate_line"


def test_no_pattern_matching_outside_validation():
    for name, tree in outside_validation():
        bad = [
            n.lineno
            for n in ast.walk(tree)
            if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr in ("compile", "match", "fullmatch")
        ]
        assert bad == [], name


def test_no_bool_and_no_limit_numbers_outside_validation():
    for name, tree in outside_validation():
        assert not [n for n in ast.walk(tree) if isinstance(n, ast.Name) and n.id == "bool"], name
        assert not [
            n for n in ast.walk(tree)
            if isinstance(n, ast.Constant) and type(n.value) is int and n.value in (999, 9999)
        ], name


def test_check_messages_are_built_only_in_validation():
    for name, tree in outside_validation():
        texts = [n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, str)]
        assert not [t for t in texts if t.startswith(MESSAGES)], name
