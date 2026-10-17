"""Structure: parsing, pricing and rendering are separate layers with a one-way import direction."""
import ast
import pathlib

import pytest

PKG = pathlib.Path(__file__).resolve().parents[2] / "src" / "invoicer"
OWNED = {
    "parsing": ("ParseError", "Item", "Discount", "Invoice", "parse_amount", "parse_invoice"),
    "pricing": ("TAX_RATES", "PricingError", "Totals", "line_total", "invoice_totals"),
    "rendering": ("format_money", "render_invoice", "render_summary"),
}
ALLOWED = {"parsing": set(), "pricing": {"parsing"}, "rendering": {"parsing", "pricing"}}
REQUIRED = {"pricing": {"parsing"}}
CALLERS = ("api", "batch", "cli")
MAX_STATEMENTS = 15


def tree(module):
    return ast.parse((PKG / f"{module}.py").read_text(encoding="utf-8"))


def all_modules():
    return sorted(p.stem for p in PKG.glob("*.py"))


def defined(module):
    """Names a module defines at top level (def, class or assignment; imports excluded)."""
    names = set()
    for node in tree(module).body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            names.add(node.name)
        elif isinstance(node, ast.Assign):
            names.update(t.id for t in node.targets if isinstance(t, ast.Name))
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            names.add(node.target.id)
    return names


def package_imports(module):
    """The package modules ``module`` imports (relative or absolute)."""
    found = set()
    for node in ast.walk(tree(module)):
        if isinstance(node, ast.ImportFrom):
            if node.level >= 1:
                if node.module:
                    found.add(node.module.split(".")[0])
                else:
                    found.update(a.name for a in node.names)
            elif node.module and node.module.split(".")[0] == "invoicer":
                rest = node.module.split(".")[1:]
                found.update(rest[:1] or [a.name for a in node.names])
        elif isinstance(node, ast.Import):
            for a in node.names:
                parts = a.name.split(".")
                if parts[0] == "invoicer":
                    found.add(parts[1] if len(parts) > 1 else "__init__")
    return found


@pytest.mark.parametrize("module", ["parsing", "rendering"])
def test_new_module_defines_its_names(module):
    assert set(OWNED[module]) <= defined(module)


def test_each_name_is_defined_in_exactly_one_module():
    for module, names in OWNED.items():
        for name in names:
            owners = [m for m in all_modules() if name in defined(m)]
            assert owners == [module], (name, owners)


def test_pricing_reexports_parsing_names_but_not_rendering_names():
    from invoicer import parsing, pricing

    for name in OWNED["parsing"]:
        assert getattr(pricing, name) is getattr(parsing, name), name
    for name in OWNED["rendering"]:
        assert not hasattr(pricing, name), name


@pytest.mark.parametrize("module", sorted(ALLOWED))
def test_layer_imports_only_lower_layers(module):
    found = package_imports(module)
    assert REQUIRED.get(module, set()) <= found <= ALLOWED[module], found


def test_callers_take_each_name_from_its_defining_module():
    pricing_names = defined("pricing") - set(OWNED["parsing"]) - set(OWNED["rendering"])
    for module in CALLERS:
        for node in ast.walk(tree(module)):
            if isinstance(node, ast.ImportFrom) and (
                (node.level == 1 and node.module == "pricing") or node.module == "invoicer.pricing"
            ):
                assert {a.name for a in node.names} <= pricing_names, module
            if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name) and node.value.id == "pricing":
                assert node.attr in pricing_names, (module, node.attr)


@pytest.mark.parametrize("module", sorted(OWNED))
def test_no_function_has_more_than_the_statement_limit(module):
    for node in ast.walk(tree(module)):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            count = sum(isinstance(n, ast.stmt) for n in ast.walk(node)) - 1
            assert count <= MAX_STATEMENTS, (module, node.name, count)


def test_errors_still_come_from_their_layers():
    from invoicer import parsing, pricing

    with pytest.raises(parsing.ParseError) as exc:
        parsing.parse_invoice("customer: A\ncurrency: EUR\nitem: x | 1 | 1.00 | luxury\n")
    assert str(exc.value) == "line 3: unknown tax class 'luxury'"
    invoice = parsing.parse_invoice("customer: A\ncurrency: GBP\nitem: x | 2 | 1.00 | std\ndiscount: 50\n")
    with pytest.raises(pricing.PricingError) as exc:
        pricing.invoice_totals(invoice)
    assert str(exc.value) == "discount GBP 50.00 exceeds subtotal GBP 2.00"
