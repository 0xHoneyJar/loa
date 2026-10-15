"""Structure: planner settings are an explicit, immutable dependency, never module state."""
import ast
import dataclasses
import pathlib

import pytest

PKG = pathlib.Path(__file__).resolve().parents[2] / "src" / "fetchq"
TAKES_CONFIG = {
    "core.py": ("build_url", "backoff_delays", "should_retry", "request_plan"),
    "jobs.py": ("plan_batch", "simulate"),
}
MUTABLE = (ast.Dict, ast.List, ast.Set, ast.DictComp, ast.ListComp, ast.SetComp)


def trees():
    return {p.name: ast.parse(p.read_text(encoding="utf-8")) for p in sorted(PKG.glob("*.py"))}


def test_no_module_level_mutable_state():
    found = []
    for name, tree in trees().items():
        for node in tree.body:
            value = getattr(node, "value", None) if isinstance(node, (ast.Assign, ast.AnnAssign)) else None
            if value is None:
                continue
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if all(isinstance(t, ast.Name) and t.id.startswith("__") and t.id.endswith("__") for t in targets):
                continue
            if isinstance(value, MUTABLE) or (isinstance(value, ast.Call) and isinstance(value.func, ast.Name) and value.func.id in ("dict", "list", "set")):
                found.append(f"{name}:{node.lineno}")
    assert found == []


def test_no_global_statement_no_configure_no_settings_name():
    for name, tree in trees().items():
        assert not [n for n in ast.walk(tree) if isinstance(n, (ast.Global, ast.Nonlocal))], name
        assert not [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == "configure"], name
        assert not [n for n in ast.walk(tree) if isinstance(n, ast.Name) and n.id == "SETTINGS"], name


@pytest.mark.parametrize("module,func", [(m, f) for m, fs in TAKES_CONFIG.items() for f in fs])
def test_function_takes_config_first(module, func):
    fn = next((n for n in trees()[module].body if isinstance(n, ast.FunctionDef) and n.name == func), None)
    assert fn is not None
    assert fn.args.args and fn.args.args[0].arg == "config"


def test_config_is_a_frozen_dataclass_with_the_settings():
    from fetchq import core

    assert dataclasses.is_dataclass(core.Config)
    assert core.Config.__dataclass_params__.frozen
    assert {f.name for f in dataclasses.fields(core.Config)} == {"base_url", "timeout", "retries", "backoff"}
    with pytest.raises(ValueError):
        core.Config(base_url="ftp://h")


def test_two_configs_are_independent():
    from fetchq import core, jobs

    a = core.Config(base_url="https://a", retries=1)
    b = core.Config(base_url="https://b", retries=3, backoff=1)
    assert core.request_plan(a, "x") == {"url": "https://a/x", "timeout": 10.0, "delays": [0.5]}
    assert core.request_plan(b, "x")["delays"] == [1, 2, 4]
    assert core.build_url(a, "y") == "https://a/y"
    assert [r["action"] for r in jobs.simulate(a, "x", [503, 503])] == ["retry in 0.5s", "give-up"]
