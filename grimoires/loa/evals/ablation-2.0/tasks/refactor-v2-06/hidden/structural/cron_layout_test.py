"""Structure: the cron package follows the layered layout and rules of the brief."""
import ast
import datetime
import importlib.util
import pathlib
import random
import re

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[2]
PKG_NAME = "cronplan"
PKG = ROOT / "src" / PKG_NAME
LAYERS = {
    "errors": 0, "model": 1, "limits": 2, "names": 2, "dates": 2, "items": 3, "render": 3, "days": 3,
    "fields": 4, "expressions": 5, "search": 6, "report": 7, "facade": 8, "cli": 9,
}
MODULE_MAX_LINES = 120
FUNCTION_MAX_LINES = 20
COMPLEXITY_MAX = 7
NESTING_MAX = 2
PARAMS_MAX = 3
DOC_FIRST_LINE_MAX = 72
ERRORS_MODULE = "errors"
ERROR_BASE = "CronError"
ERROR_BASE_PARENT = "ValueError"
MODEL_MODULE = "model"
CLI_MODULE = "cli"
CLASS_MODULES = ("errors", "model")
ENUM_BASES = ("enum.Enum", "Enum")
SIGNATURES = {
    "fields:parse_field": "(text: str, kind: FieldKind) -> Field",
    "expressions:parse_expression": "(text: str) -> Schedule",
    "days:day_matches": "(schedule: Schedule, day: datetime.date) -> bool",
    "search:next_fire": "(schedule: Schedule, after: datetime.datetime) -> datetime.datetime",
    "render:format_schedule": "(schedule: Schedule) -> str",
}
EXHAUSTIVE = {
    "limits:limits": ("kind", "FieldKind"),
    "days:special_matches": ("special.kind", "Special"),
    "render:format_special": ("special.kind", "Special"),
}


# ---- common rules (each one a rule of the brief's Refactor section) ----

def _source(stem):
    return (PKG / f"{stem}.py").read_text(encoding="utf-8")


def _trees():
    return {p.stem: ast.parse(p.read_text(encoding="utf-8")) for p in sorted(PKG.glob("*.py"))}


def _functions(tree):
    return [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]


def _classes(tree):
    return [n for n in ast.walk(tree) if isinstance(n, ast.ClassDef)]


def _methods_of(tree):
    owned = {}
    for cls in _classes(tree):
        for n in cls.body:
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
                owned[id(n)] = cls
    return owned


def _own_nodes(fn):
    """Walk a function's body without entering nested functions, classes or lambdas' defs."""
    stack = list(fn.body) + list(fn.args.defaults) + list(fn.args.kw_defaults or [])
    while stack:
        node = stack.pop()
        if node is None:
            continue
        yield node
        for child in ast.iter_child_nodes(node):
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                continue
            stack.append(child)


def _complexity(fn):
    score = 1
    for node in _own_nodes(fn):
        if isinstance(node, (ast.If, ast.IfExp, ast.For, ast.AsyncFor, ast.While, ast.ExceptHandler, ast.match_case)):
            score += 1
        elif isinstance(node, ast.comprehension):
            score += 1 + len(node.ifs)
        elif isinstance(node, ast.BoolOp):
            score += len(node.values) - 1
    return score


COMPOUND = (ast.If, ast.For, ast.AsyncFor, ast.While, ast.With, ast.AsyncWith, ast.Try, ast.Match)
if hasattr(ast, "TryStar"):
    COMPOUND = COMPOUND + (ast.TryStar,)


def _max_depth(stmts, depth=0):
    best = depth
    for st in stmts:
        if isinstance(st, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            continue
        if isinstance(st, COMPOUND):
            here = depth + 1
            best = max(best, here)
            blocks = []
            if isinstance(st, ast.If):
                blocks.append(st.body)
                orelse = st.orelse
                while len(orelse) == 1 and isinstance(orelse[0], ast.If):
                    blocks.append(orelse[0].body)
                    orelse = orelse[0].orelse
                blocks.append(orelse)
            elif isinstance(st, ast.Match):
                blocks.extend(c.body for c in st.cases)
            elif isinstance(st, (ast.Try,) + ((ast.TryStar,) if hasattr(ast, "TryStar") else ())):
                blocks.extend([st.body, st.orelse, st.finalbody])
                blocks.extend(h.body for h in st.handlers)
            else:
                blocks.extend([st.body, getattr(st, "orelse", [])])
            for block in blocks:
                best = max(best, _max_depth(block, here))
    return best


def _param_count(fn, is_method):
    a = fn.args
    names = [x.arg for x in a.posonlyargs + a.args + a.kwonlyargs]
    if a.vararg:
        names.append(a.vararg.arg)
    if a.kwarg:
        names.append(a.kwarg.arg)
    if is_method and names and names[0] in ("self", "cls"):
        names = names[1:]
    return len(names)


def _pkg_imports(tree):
    """(node, target module stem or None for the package itself, imported names) for every package import."""
    found = []
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom):
            if node.level:
                found.append((node, "<relative>", [a.name for a in node.names]))
            elif node.module == PKG_NAME:
                found.append((node, None, [a.name for a in node.names]))
            elif node.module and node.module.startswith(PKG_NAME + "."):
                found.append((node, node.module[len(PKG_NAME) + 1:], [a.name for a in node.names]))
        elif isinstance(node, ast.Import):
            for a in node.names:
                if a.name == PKG_NAME or a.name.startswith(PKG_NAME + "."):
                    found.append((node, "<import>", [a.name]))
    return found


def _top_defs(tree):
    names = []
    for n in tree.body:
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            names.append(n.name)
        elif isinstance(n, ast.Assign):
            names.extend(t.id for t in n.targets if isinstance(t, ast.Name))
        elif isinstance(n, ast.AnnAssign) and isinstance(n.target, ast.Name):
            names.append(n.target.id)
    return names


def _dotted_name(node):
    while isinstance(node, ast.Attribute):
        node = node.value
    return isinstance(node, ast.Name)


def _constant_value(node):
    if isinstance(node, (ast.Constant, ast.Name)):
        return True
    if isinstance(node, ast.Attribute):
        return _dotted_name(node)
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
        return isinstance(node.operand, ast.Constant)
    if isinstance(node, ast.Tuple):
        return all(_constant_value(e) for e in node.elts)
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "frozenset":
        if node.keywords or len(node.args) > 1:
            return False
        if not node.args:
            return True
        arg = node.args[0]
        if isinstance(arg, (ast.Set, ast.List, ast.Tuple)):
            return all(_constant_value(e) for e in arg.elts)
        return False
    return False


def _assignments(body):
    for node in body:
        if isinstance(node, ast.Assign):
            yield node.targets, node.value, node.lineno
        elif isinstance(node, ast.AnnAssign) and node.value is not None:
            yield [node.target], node.value, node.lineno
        elif isinstance(node, ast.AugAssign):
            yield [node.target], None, node.lineno


def _is_field_call(node):
    return isinstance(node, ast.Call) and (
        (isinstance(node.func, ast.Name) and node.func.id == "field")
        or (isinstance(node.func, ast.Attribute) and node.func.attr == "field")
    )


def _docstring_ok(node):
    doc = ast.get_docstring(node, clean=True)
    if not doc:
        return False
    first = doc.splitlines()[0]
    return len(first) <= DOC_FIRST_LINE_MAX and first.endswith(".")


BANNED_TYPING = frozenset({"Optional", "Union", "List", "Dict", "Set", "FrozenSet", "Tuple", "Any", "Type"})


def _annotation_nodes(tree):
    for fn in _functions(tree):
        a = fn.args
        for arg in a.posonlyargs + a.args + a.kwonlyargs + [x for x in (a.vararg, a.kwarg) if x]:
            if arg.annotation is not None:
                yield arg.annotation
        if fn.returns is not None:
            yield fn.returns
    for node in ast.walk(tree):
        if isinstance(node, ast.AnnAssign):
            yield node.annotation


def test_module_set_is_exactly_the_stated_one():
    assert sorted(p.stem for p in PKG.glob("*.py")) == sorted(list(LAYERS) + ["__init__"])
    assert not [p for p in PKG.iterdir() if p.is_dir() and p.name != "__pycache__"]


def test_init_only_reexports():
    tree = _trees()["__init__"]
    body = tree.body[1:] if ast.get_docstring(tree) else tree.body
    for node in body:
        if isinstance(node, ast.ImportFrom):
            assert node.level == 0 and node.module and node.module.startswith(PKG_NAME + "."), ast.unparse(node)
            continue
        assert isinstance(node, ast.Assign) and [getattr(t, "id", None) for t in node.targets] == ["__all__"], ast.unparse(node)


def test_imports_point_strictly_down_the_layers():
    bad = []
    for stem, tree in _trees().items():
        if stem == "__init__":
            continue
        for node, target, _ in _pkg_imports(tree):
            if target not in LAYERS or LAYERS[target] >= LAYERS.get(stem, -1):
                bad.append(f"{stem}:{node.lineno} -> {target}")
    assert bad == []


def test_package_imports_use_the_from_module_form():
    bad = []
    for stem, tree in _trees().items():
        for node, target, names in _pkg_imports(tree):
            if target in ("<relative>", "<import>") or target is None or "*" in names:
                bad.append(f"{stem}:{node.lineno}")
    assert bad == []


def test_imports_only_at_module_top_level():
    bad = []
    for stem, tree in _trees().items():
        top = {id(n) for n in tree.body}
        for node in ast.walk(tree):
            if isinstance(node, (ast.Import, ast.ImportFrom)) and id(node) not in top:
                bad.append(f"{stem}:{node.lineno}")
    assert bad == []


def test_no_private_name_imported_across_modules():
    bad = []
    for stem, tree in _trees().items():
        for node, _, names in _pkg_imports(tree):
            bad.extend(f"{stem}:{node.lineno}:{n}" for n in names if n.startswith("_"))
    assert bad == []


def test_module_length_limit():
    bad = [p.stem for p in PKG.glob("*.py") if len(p.read_text(encoding="utf-8").splitlines()) > MODULE_MAX_LINES]
    assert bad == []


def test_function_length_limit():
    bad = []
    for stem, tree in _trees().items():
        for fn in _functions(tree):
            if fn.end_lineno - fn.lineno + 1 > FUNCTION_MAX_LINES:
                bad.append(f"{stem}.{fn.name}")
    assert bad == []


def test_branch_complexity_limit():
    bad = []
    for stem, tree in _trees().items():
        for fn in _functions(tree):
            if _complexity(fn) > COMPLEXITY_MAX:
                bad.append(f"{stem}.{fn.name}={_complexity(fn)}")
    assert bad == []


def test_nesting_depth_limit():
    bad = []
    for stem, tree in _trees().items():
        for fn in _functions(tree):
            if _max_depth(fn.body) > NESTING_MAX:
                bad.append(f"{stem}.{fn.name}")
    assert bad == []


def test_parameter_count_limit():
    bad = []
    for stem, tree in _trees().items():
        owned = _methods_of(tree)
        for fn in _functions(tree):
            if _param_count(fn, id(fn) in owned) > PARAMS_MAX:
                bad.append(f"{stem}.{fn.name}")
    assert bad == []


def test_no_module_or_class_state():
    bad = []
    for stem, tree in _trees().items():
        for targets, value, line in _assignments(tree.body):
            if all(isinstance(t, ast.Name) and t.id == "__all__" for t in targets) and value is not None:
                continue
            if value is None or not _constant_value(value):
                bad.append(f"{stem}:{line}")
        for cls in _classes(tree):
            for _, value, line in _assignments(cls.body):
                if value is None or not (_constant_value(value) or _is_field_call(value)):
                    bad.append(f"{stem}:{line}")
    assert bad == []


def test_no_global_nonlocal_or_function_cache():
    bad = []
    for stem, tree in _trees().items():
        bad.extend(f"{stem}:{n.lineno}" for n in ast.walk(tree) if isinstance(n, (ast.Global, ast.Nonlocal)))
        for fn in _functions(tree):
            for dec in fn.decorator_list:
                target = dec.func if isinstance(dec, ast.Call) else dec
                if (getattr(target, "id", None) or getattr(target, "attr", None)) in ("cache", "lru_cache", "cached_property"):
                    bad.append(f"{stem}.{fn.name}")
    assert bad == []


def test_every_function_is_fully_annotated():
    bad = []
    for stem, tree in _trees().items():
        owned = _methods_of(tree)
        for fn in _functions(tree):
            a = fn.args
            args = a.posonlyargs + a.args + a.kwonlyargs + [x for x in (a.vararg, a.kwarg) if x]
            if id(fn) in owned and args and args[0].arg in ("self", "cls"):
                args = args[1:]
            if fn.returns is None or any(x.annotation is None for x in args):
                bad.append(f"{stem}.{fn.name}")
    assert bad == []


def test_annotations_use_builtin_generics_and_union_syntax():
    bad = []
    for stem, tree in _trees().items():
        for ann in _annotation_nodes(tree):
            for node in ast.walk(ann):
                if isinstance(node, ast.Constant) and isinstance(node.value, str):
                    bad.append(f"{stem}:{ann.lineno}:string")
                name = getattr(node, "id", None) if isinstance(node, ast.Name) else (node.attr if isinstance(node, ast.Attribute) else None)
                if name in BANNED_TYPING:
                    bad.append(f"{stem}:{ann.lineno}:{name}")
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom) and node.module == "typing":
                bad.extend(f"{stem}:{node.lineno}:{a.name}" for a in node.names if a.name in BANNED_TYPING)
            if isinstance(node, ast.ImportFrom) and node.module == "__future__":
                bad.append(f"{stem}:{node.lineno}:__future__")
    assert bad == []


def test_dunder_all_lists_exactly_the_public_names_sorted():
    bad = []
    for stem, tree in _trees().items():
        decl = [n for n in tree.body if isinstance(n, ast.Assign) and [getattr(t, "id", None) for t in n.targets] == ["__all__"]]
        if len(decl) != 1 or not isinstance(decl[0].value, ast.List):
            bad.append(f"{stem}:missing")
            continue
        listed = [e.value if isinstance(e, ast.Constant) else None for e in decl[0].value.elts]
        if stem == "__init__":
            public = [a.asname or a.name for n in tree.body if isinstance(n, ast.ImportFrom) for a in n.names]
        else:
            public = [n for n in _top_defs(tree) if not n.startswith("_")]
        if listed != sorted(set(public)):
            bad.append(stem)
    assert bad == []


def test_public_docstrings_with_a_short_first_sentence():
    bad = []
    for stem, tree in _trees().items():
        if not _docstring_ok(tree):
            bad.append(f"{stem}:module")
        public_classes = [n for n in tree.body if isinstance(n, ast.ClassDef) and not n.name.startswith("_")]
        nodes = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and not n.name.startswith("_")]
        for cls in public_classes:
            nodes.append(cls)
            nodes.extend(m for m in cls.body if isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef)) and not m.name.startswith("_"))
        bad.extend(f"{stem}.{n.name}" for n in nodes if not _docstring_ok(n))
    assert bad == []


SNAKE = re.compile(r"^_?[a-z][a-z0-9]*(_[a-z0-9]+)*$")
DUNDER = re.compile(r"^__[a-z][a-z0-9_]*__$")
CAPWORDS = re.compile(r"^_?[A-Z][a-zA-Z0-9]*$")
UPPER = re.compile(r"^_?[A-Z][A-Z0-9]*(_[A-Z0-9]+)*$")


def test_function_and_parameter_names_are_snake_case():
    bad = []
    for stem, tree in _trees().items():
        for fn in _functions(tree):
            if not (SNAKE.match(fn.name) or DUNDER.match(fn.name)):
                bad.append(f"{stem}.{fn.name}")
            a = fn.args
            for arg in a.posonlyargs + a.args + a.kwonlyargs + [x for x in (a.vararg, a.kwarg) if x]:
                if not SNAKE.match(arg.arg):
                    bad.append(f"{stem}.{fn.name}({arg.arg})")
    assert bad == []


def test_class_names_are_capwords_and_exceptions_end_in_error():
    bad = []
    for stem, tree in _trees().items():
        for cls in _classes(tree):
            if not CAPWORDS.match(cls.name):
                bad.append(cls.name)
        if stem == ERRORS_MODULE:
            bad.extend(c.name for c in _classes(tree) if not c.name.endswith("Error"))
    assert bad == []


def test_module_level_names_are_upper_case_constants():
    bad = []
    for stem, tree in _trees().items():
        for targets, _, line in _assignments(tree.body):
            for t in targets:
                for n in ast.walk(t):
                    if isinstance(n, ast.Name) and n.id != "__all__" and not UPPER.match(n.id):
                        bad.append(f"{stem}:{line}:{n.id}")
    assert bad == []


def test_one_definition_per_top_level_name():
    seen = {}
    for stem, tree in _trees().items():
        for n in tree.body:
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                seen.setdefault(n.name, []).append(stem)
    assert {k: v for k, v in seen.items() if len(v) > 1} == {}


def test_classes_only_where_stated():
    bad = []
    for stem, tree in _trees().items():
        if stem not in CLASS_MODULES:
            bad.extend(f"{stem}.{c.name}" for c in _classes(tree))
    assert bad == []


def test_every_raise_uses_a_package_error():
    trees = _trees()
    error_names = {c.name for c in _classes(trees[ERRORS_MODULE])}
    bad = []
    for stem, tree in trees.items():
        imported = {a.asname or a.name for node, target, _ in _pkg_imports(tree) if target == ERRORS_MODULE for a in node.names}
        known = error_names if stem == ERRORS_MODULE else imported & error_names
        for node in ast.walk(tree):
            if isinstance(node, ast.Raise) and node.exc is not None:
                exc = node.exc.func if isinstance(node.exc, ast.Call) else node.exc
                if not (isinstance(exc, ast.Name) and exc.id in known):
                    bad.append(f"{stem}:{node.lineno}")
    assert bad == []


def test_errors_derive_from_one_base():
    tree = _trees()[ERRORS_MODULE]
    classes = {c.name: c for c in tree.body if isinstance(c, ast.ClassDef)}
    assert ERROR_BASE in classes
    assert [ast.unparse(b) for b in classes[ERROR_BASE].bases] == [ERROR_BASE_PARENT]
    bad = []
    for name, cls in classes.items():
        if name == ERROR_BASE:
            continue
        if len(cls.bases) != 1 or ast.unparse(cls.bases[0]) not in classes:
            bad.append(name)
    assert bad == []


def test_no_broad_or_bare_except():
    bad = []
    for stem, tree in _trees().items():
        for h in [n for n in ast.walk(tree) if isinstance(n, ast.ExceptHandler)]:
            types = h.type.elts if isinstance(h.type, ast.Tuple) else [h.type]
            if h.type is None or any(getattr(t, "id", None) in ("Exception", "BaseException") for t in types):
                bad.append(f"{stem}:{h.lineno}")
    assert bad == []


def test_output_only_from_the_cli_module():
    bad = []
    for stem, tree in _trees().items():
        if stem == CLI_MODULE:
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Call) and getattr(node.func, "id", None) == "print":
                bad.append(f"{stem}:{node.lineno}")
            if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name) and node.value.id == "sys" and node.attr in ("stdout", "stderr", "stdin", "argv", "exit"):
                bad.append(f"{stem}:{node.lineno}")
    assert bad == []


def test_model_classes_are_frozen_slotted_dataclasses_or_enums():
    bad = []
    for cls in [n for n in _trees()[MODEL_MODULE].body if isinstance(n, ast.ClassDef)]:
        bases = [ast.unparse(b) for b in cls.bases]
        if bases and all(b in ENUM_BASES for b in bases):
            continue
        decs = [d for d in cls.decorator_list if isinstance(d, ast.Call) and getattr(d.func, "id", getattr(d.func, "attr", None)) == "dataclass"]
        kw = {k.arg: getattr(k.value, "value", None) for d in decs for k in d.keywords}
        if bases or len(decs) != 1 or kw.get("frozen") is not True or kw.get("slots") is not True:
            bad.append(cls.name)
    assert bad == []


def _match_cases_cover(fn, subject, enum_name, members):
    matches = [n for n in _own_nodes(fn) if isinstance(n, ast.Match) and ast.unparse(n.subject) == subject]
    if len(matches) != 1:
        return False
    covered = []
    for case in matches[0].cases:
        pats = case.pattern.patterns if isinstance(case.pattern, ast.MatchOr) else [case.pattern]
        if case.guard is not None:
            return False
        for p in pats:
            if not (isinstance(p, ast.MatchValue) and isinstance(p.value, ast.Attribute)
                    and isinstance(p.value.value, ast.Name) and p.value.value.id == enum_name):
                return False
            covered.append(p.value.attr)
    return sorted(covered) == sorted(members)


def _enum_members(enum_name):
    for cls in [n for n in _trees()[MODEL_MODULE].body if isinstance(n, ast.ClassDef) and n.name == enum_name]:
        return [t.id for targets, _, _ in _assignments(cls.body) for t in targets if isinstance(t, ast.Name)]
    return []


def _find_function(stem, name):
    for n in _trees()[stem].body:
        if isinstance(n, ast.FunctionDef) and n.name == name:
            return n
    return None


def _signature_text(fn):
    a = fn.args
    parts = []
    defaults = [None] * (len(a.args) - len(a.defaults)) + list(a.defaults)
    for arg, d in zip(a.args, defaults):
        parts.append(_param_text(arg, d))
    if a.vararg:
        parts.append("*" + _param_text(a.vararg, None))
    elif a.kwonlyargs:
        parts.append("*")
    for arg, d in zip(a.kwonlyargs, a.kw_defaults):
        parts.append(_param_text(arg, d))
    if a.kwarg:
        parts.append("**" + _param_text(a.kwarg, None))
    ret = ast.unparse(fn.returns) if fn.returns is not None else "?"
    return f"({', '.join(parts)}) -> {ret}"


def _param_text(arg, default):
    text = arg.arg + (": " + ast.unparse(arg.annotation) if arg.annotation is not None else "")
    if default is not None:
        text += " = " + ast.unparse(default)
    return text


@pytest.mark.parametrize("where", sorted(SIGNATURES))
def test_stated_public_signatures(where):
    stem, name = where.split(":")
    fn = _find_function(stem, name)
    assert fn is not None, where
    assert _signature_text(fn) == SIGNATURES[where]


@pytest.mark.parametrize("where", sorted(EXHAUSTIVE))
def test_exhaustive_match_over_the_enum(where):
    stem, name = where.split(":")
    param, enum_name = EXHAUSTIVE[where]
    fn = _find_function(stem, name)
    members = _enum_members(enum_name)
    assert fn is not None and members, where
    assert _match_cases_cover(fn, param, enum_name, members)


# ---- conformance: the new functions behave exactly as the package did ----

def _oracle():
    path = pathlib.Path(__file__).with_name("_oracle_cron.py")
    spec = importlib.util.spec_from_file_location("_oracle_cron", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _plain(x):
    if hasattr(x, "minute") and hasattr(x, "weekday") and hasattr(x, "day") and not isinstance(x, datetime.datetime):
        return ("S",) + tuple(_plain(getattr(x, n)) for n in ("minute", "hour", "day", "month", "weekday"))
    if hasattr(x, "values") and hasattr(x, "specials"):
        return ("F", x.kind.value, tuple(sorted(x.values)), tuple(_plain(s) for s in x.specials), bool(x.starred))
    if hasattr(x, "nth") and hasattr(x, "number"):
        return ("D", x.kind.value, x.number, x.nth)
    if isinstance(x, (list, tuple)):
        return tuple(_plain(e) for e in x)
    return x


def _outcome(fn, *args):
    try:
        return ("ok", _plain(fn(*args)))
    except ValueError as exc:
        return ("err", type(exc).__name__, str(exc))


NUMS = {"minute": ["0", "5", "15", "30", "59", "07", "45"], "hour": ["0", "6", "12", "23", "9", "18"],
        "day-of-month": ["1", "2", "15", "28", "29", "30", "31", "10"], "month": ["1", "2", "6", "12", "JAN", "feb", "Dec", "3"],
        "day-of-week": ["0", "1", "5", "6", "7", "MON", "fri", "Sun", "3"]}
BAD_NUMS = {"minute": ["60", "-1"], "hour": ["24"], "day-of-month": ["0", "32", "JAN"], "month": ["0", "13", "FOO", "MON"],
            "day-of-week": ["8", "XYZ", "JAN"]}
SPECIAL_DAY = ["L", "LW", "L-0", "L-2", "L-30", "1W", "15W", "30W", "31W", "L", "LW", "29W"]
BAD_SPECIAL_DAY = ["L-31", "0W", "W", "L-", "32W"]
SPECIAL_WEEKDAY = ["5L", "0L", "7L", "FRIL", "1#1", "1#5", "MON#2", "6#4", "sat#3"]
BAD_SPECIAL_WEEKDAY = ["0#6", "8#1", "#1", "L", "1#0"]
KINDS = ["minute", "hour", "day-of-month", "month", "day-of-week"]
MACROS = ["@yearly", "@ANNUALLY", "@monthly", "@weekly", "@daily", "@midnight", "@hourly", "@reboot", "@Daily"]


def _num(rng, kind):
    return rng.choice(BAD_NUMS[kind]) if rng.random() < 0.03 else rng.choice(NUMS[kind])


def _item(rng, kind):
    roll = rng.random()
    if kind == "day-of-month" and roll < 0.25:
        return rng.choice(BAD_SPECIAL_DAY) if rng.random() < 0.08 else rng.choice(SPECIAL_DAY)
    if kind == "day-of-week" and roll < 0.25:
        return rng.choice(BAD_SPECIAL_WEEKDAY) if rng.random() < 0.08 else rng.choice(SPECIAL_WEEKDAY)
    if roll < 0.45:
        star = "?" if kind in ("day-of-month", "day-of-week") and rng.random() < 0.3 else "*"
        if rng.random() < 0.02:
            star = "?"
        return star + rng.choice(["", "", "", "/2", "/5", "/13", "/0" if rng.random() < 0.1 else ""])
    if roll < 0.62:
        low, high = _num(rng, kind), _num(rng, kind)
        if rng.random() < 0.85 and low.isdigit() and high.isdigit() and int(low) > int(high):
            low, high = high, low
        return f"{low}-{high}" + rng.choice(["", "", "/2", "/3"])
    if roll < 0.67:
        return _num(rng, kind) + rng.choice(["/4", "/10"])
    if roll < 0.69:
        return rng.choice(["", "1-", "-1", "a", "*/", "1--2", "+1"])
    return _num(rng, kind)


def _field(rng, kind):
    return ",".join(_item(rng, kind) for _ in range(rng.choice([1, 1, 1, 2, 3])))


def _expression(rng, valid_only=False):
    if rng.random() < 0.05:
        return rng.choice(MACROS)
    fields = [_field(rng, k) for k in KINDS]
    if rng.random() < 0.03:
        fields = fields[: rng.choice([3, 4])] + (["*", "*"] if rng.random() < 0.3 else [])
    return rng.choice(["", " ", "\t"]) + " ".join(fields) + rng.choice(["", " "])


def _valid_expressions(oracle, rng, n):
    out = []
    while len(out) < n:
        text = _expression(rng)
        if _outcome(oracle.parse_expression, text)[0] == "ok":
            out.append(text)
    return out


def _moment(rng):
    return datetime.datetime(rng.randint(1999, 2031), rng.randint(1, 12), rng.randint(1, 28),
                             rng.randint(0, 23), rng.randint(0, 59), rng.choice([0, 0, 30]))


def test_parse_expression_matches_the_package():
    from cronplan.expressions import parse_expression

    oracle, rng = _oracle(), random.Random(26101711)
    for _ in range(2000):
        text = _expression(rng)
        assert _outcome(parse_expression, text) == _outcome(oracle.parse_expression, text), text


def test_parse_field_and_format_schedule_match_the_package():
    from cronplan.expressions import parse_expression
    from cronplan.fields import parse_field
    from cronplan.model import FieldKind
    from cronplan.render import format_schedule

    oracle, rng = _oracle(), random.Random(26101712)
    for _ in range(1500):
        kind = rng.choice(KINDS)
        text = _field(rng, kind)
        assert _outcome(parse_field, text, FieldKind(kind)) == _outcome(oracle.parse_field, text, oracle.FieldKind(kind)), (kind, text)
    for text in _valid_expressions(oracle, rng, 1000):
        assert format_schedule(parse_expression(text)) == oracle.format_schedule(oracle.parse_expression(text)), text


def test_day_matches_the_package():
    from cronplan.days import day_matches
    from cronplan.expressions import parse_expression

    oracle, rng = _oracle(), random.Random(26101713)
    for text in _valid_expressions(oracle, rng, 150):
        mine, theirs = parse_expression(text), oracle.parse_expression(text)
        start = datetime.date(rng.randint(1999, 2031), rng.randint(1, 12), 1)
        for offset in range(0, 70):
            day = start + datetime.timedelta(days=offset)
            assert day_matches(mine, day) == oracle.day_matches(theirs, day), (text, day)


def test_next_fire_matches_the_package():
    from cronplan.expressions import parse_expression
    from cronplan.search import next_fire

    oracle, rng = _oracle(), random.Random(26101714)
    for text in _valid_expressions(oracle, rng, 400):
        when = _moment(rng)
        mine = _outcome(next_fire, parse_expression(text), when)
        assert mine == _outcome(oracle.next_fire, oracle.parse_expression(text), when), (text, when)


def test_exported_functions_match_the_package():
    import cronplan

    oracle, rng = _oracle(), random.Random(26101715)
    for _ in range(300):
        text, when = _expression(rng), _moment(rng)
        count = rng.choice([1, 3, 0, 1001, 2])
        assert _outcome(cronplan.normalize, text) == _outcome(oracle.normalize, text), text
        assert _outcome(cronplan.fires, text, when, count) == _outcome(oracle.fires_text, text, when, count), (text, when, count)
        exact = when.replace(second=0)
        assert _outcome(cronplan.matches, text, exact) == _outcome(oracle.matches_text, text, exact), (text, exact)
        year, month = rng.choice([(2024, 2), (2025, 2), (2026, 10), (2026, 13), (2031, 12)])
        assert _outcome(cronplan.month_report, text, year, month) == _outcome(oracle.month_report, text, year, month), text
    aware = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
    assert _outcome(cronplan.next_fire, "* * * * *", aware) == _outcome(oracle.next_fire_text, "* * * * *", aware)
    assert _outcome(cronplan.next_fire, "0 0 30 2 *", aware.replace(tzinfo=None)) == _outcome(oracle.next_fire_text, "0 0 30 2 *", aware.replace(tzinfo=None))
