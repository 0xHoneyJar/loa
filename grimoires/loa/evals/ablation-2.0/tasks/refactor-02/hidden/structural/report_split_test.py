"""Structure: the report builder is split along its three concerns."""
import ast
import pathlib

import pytest

SRC = pathlib.Path(__file__).resolve().parents[2] / "src" / "salesreport" / "report.py"
NAMES = ("parse_lines", "aggregate", "render_report", "build_report")
LIMIT = 40

SAMPLE = """date,region,product,qty,unit_price
2026-10-06,North,Widget,10,2.50
2026-10-07,South,Gadget,3,19.99
2026-10-09,East,Widget,4,2.50
2026-10-10,South,Widget,-2,2.50
2026-10-10,East,Doohickey,1,99.00
2026-10-11,West,Gadget,2,19.99
"""


def tree():
    return ast.parse(SRC.read_text(encoding="utf-8"))


def functions(t):
    return [n for n in ast.walk(t) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]


def own_statements(fn):
    """Statements inside ``fn``, not counting the bodies of nested functions or classes."""
    count, todo = 0, list(fn.body)
    while todo:
        node = todo.pop()
        count += 1
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            continue
        for field in ("body", "orelse", "finalbody", "handlers", "cases"):
            for child in getattr(node, field, []) or []:
                if isinstance(child, ast.stmt):
                    todo.append(child)
                elif isinstance(child, (ast.ExceptHandler, ast.match_case)):
                    todo.extend(child.body)
    return count


def calls(fn):
    return {n.func.id for n in ast.walk(fn) if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)}


def test_the_four_functions_are_module_level():
    top = {n.name for n in tree().body if isinstance(n, ast.FunctionDef)}
    assert set(NAMES) <= top


def test_no_function_is_longer_than_the_limit():
    sizes = {f.name: own_statements(f) for f in functions(tree())}
    assert sizes and max(sizes.values()) <= LIMIT, sizes


def test_build_report_only_composes():
    fn = next(f for f in tree().body if isinstance(f, ast.FunctionDef) and f.name == "build_report")
    assert {"parse_lines", "aggregate", "render_report"} <= calls(fn)
    assert own_statements(fn) <= 8


def test_concerns_do_not_leak():
    fns = {f.name: f for f in tree().body if isinstance(f, ast.FunctionDef)}
    assert not ({"aggregate", "render_report"} & calls(fns["parse_lines"]))
    assert not ({"parse_lines", "render_report"} & calls(fns["aggregate"]))
    assert not ({"parse_lines", "aggregate"} & calls(fns["render_report"]))
    text_made = [n for n in ast.walk(fns["aggregate"]) if isinstance(n, ast.JoinedStr)
                 or (isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr in ("join", "format", "ljust", "rjust"))]
    assert text_made == []
    parsing = [n for n in ast.walk(fns["render_report"]) if isinstance(n, ast.Attribute) and n.attr in ("splitlines", "split", "fromisoformat")]
    assert parsing == []


@pytest.mark.parametrize("currency,top", [("EUR", 3), ("USD", 1), ("GBP", 10)])
def test_the_parts_compose_to_the_report(currency, top):
    from salesreport import report

    sales = report.parse_lines(SAMPLE)
    assert len(sales) == 6
    summary = report.aggregate(sales, top=top)
    assert report.render_report(summary, currency=currency) == report.build_report(SAMPLE, currency=currency, top=top)


def test_empty_input_composes():
    from salesreport import report

    assert report.parse_lines("# none\n") == []
    assert report.render_report(report.aggregate([], top=3), currency="EUR") == report.build_report("# none\n")
