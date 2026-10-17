# Task: rebuild semverkit on a strict layered layout

`semverkit` (under `src/semverkit/`) parses semantic versions, compares, sorts and bumps them, parses npm-style ranges (`^`, `~`, `~>`, comparators, x-ranges, hyphen ranges, `||`), matches versions against ranges, renders a yes/no table and has a command line (`semverkit.cli.main`). The code works but is tangled: a god module, a cycle between `core` and `ranges` broken by imports inside functions, string-typed operators compared everywhere, module-level caches, settings dicts and compiled regexes, no annotations. Restructure it into the layout below. Every rule is checked across the whole package, so one module that breaks a rule breaks it for the package.

## Target layout

`src/semverkit/` holds exactly these modules and no subpackage:

| Layer | Module | Holds |
|---|---|---|
| 0 | `errors` | `SemverError(ValueError)` and its subclasses `InvalidVersionError`, `InvalidRangeError`, `InvalidBumpError` |
| 1 | `model` | the dataclasses `Version`, `Partial`, `Comparator` and the enums `Op`, `Prefix`, `Part` |
| 2 | `versions` | `parse_version`, `format_version` |
| 3 | `precedence` | `compare`, `sort_versions` |
| 4 | `bumping` | `bump` |
| 4 | `desugar` | `expand`, `expand_hyphen` |
| 5 | `ranges` | `parse_range`, `format_range` |
| 6 | `matching` | `test_op`, `satisfies`, `filter_satisfying`, `max_satisfying`, `min_satisfying` |
| 7 | `facade` | the string-in, string-out functions the package exports |
| 8 | `report` | `render_table` |
| 9 | `cli` | `main` |
| top | `__init__` | re-exports only |

**Data model** (`model`):
- `Version(major: int, minor: int, patch: int, prerelease: tuple[int | str, ...] = (), build: tuple[str, ...] = ())`. A numeric prerelease identifier is an `int`.
- `Partial(major: int | None, minor: int | None, patch: int | None, prerelease: tuple[int | str, ...] = ())`: a version as written inside a range. A wildcard (`x`, `X`, `*`) or missing part is `None`, and so is every part after it.
- `Comparator(op: Op, version: Version)`.
- `Op`: `LT = "<"`, `LE = "<="`, `GT = ">"`, `GE = ">="`, `EQ = "="`.
- `Prefix` (the operator written before a partial version): `NONE = ""`, `EQ = "="`, `LT = "<"`, `LE = "<="`, `GT = ">"`, `GE = ">="`, `CARET = "^"`, `TILDE = "~"`. `~>` is read as `TILDE`.
- `Part`: `MAJOR = "major"`, `MINOR = "minor"`, `PATCH = "patch"`, `PRERELEASE = "prerelease"`, `RELEASE = "release"`.

**Functions with a fixed signature.** Write these exactly as shown: parameter names, annotations and defaults.
- `versions.parse_version(text: str) -> Version` parses as `semverkit.parse` does today. `versions.format_version(version: Version) -> str` gives the canonical text.
- `precedence.compare(a: Version, b: Version) -> int` returns -1, 0 or 1 by precedence, as `semverkit.compare` does for the two strings today.
- `bumping.bump(version: Version, part: Part, ident: str | None = None) -> Version` is today's bump on parsed values.
- `desugar.expand(prefix: Prefix, partial: Partial) -> tuple[Comparator, ...]` and `desugar.expand_hyphen(low: Partial, high: Partial) -> tuple[Comparator, ...]` give the primitive comparators one written comparator or one hyphen range stands for.
- `ranges.parse_range(text: str) -> tuple[tuple[Comparator, ...], ...]` returns one tuple per `||` alternative, holding the comparators that alternative's normalised form lists today, in that order. `ranges.format_range(comparator_sets: tuple[tuple[Comparator, ...], ...]) -> str` renders them as `semverkit.normalize_range` does.
- `matching.satisfies(version: Version, comparator_sets: tuple[tuple[Comparator, ...], ...], include_prerelease: bool = False) -> bool` and `matching.test_op(op: Op, order: int) -> bool` (whether a `compare` result passes an operator).

**Errors.** Every error the package raises is one of the `errors` classes, with today's message text. A bad version string (`not a string: …`, `version too long`, `invalid version: …`) raises `InvalidVersionError`. A bad range (`not a string: …`, `range too long`, `invalid comparator: …`) raises `InvalidRangeError`. A bump that cannot apply (`unknown part: …`, `identifier only applies to prerelease`, `invalid identifier: …`, `already a release: …`) raises `InvalidBumpError`.

**Exports.** `semverkit` exports these names, with today's behaviour: `InvalidRange`, `InvalidVersion`, `Version`, `bump`, `compare`, `max_satisfying`, `min_satisfying`, `normalize_range`, `parse`, `render_table`, `satisfies`, `sort` and `valid`. It adds `SemverError` and `InvalidBumpError`. `semverkit.InvalidVersion` and `semverkit.InvalidRange` are `InvalidVersionError` and `InvalidRangeError` exported under the old names. Other names that `__init__` happens to import today need not stay.

## Rules

1. **Layers.** A module imports another package module only when that module's layer is strictly lower than its own. `__init__` may import from any module.
2. **Import form.** Package modules are imported only as `from semverkit.<module> import <names>`. There is no `import semverkit…`, no relative import and no `*` import.
3. **Imports at the top.** Every `import` statement is a top-level statement of its module, never inside a function, class, `if` or `try`.
4. **No private imports.** No module imports a name that starts with `_` from another package module.
5. **`__init__`.** It holds only its docstring, `from semverkit.<module> import …` statements and `__all__`.
6. **Module size.** A module has at most 150 lines.
7. **Function size.** A function or method spans at most 25 lines, from its `def` line to its last line. The docstring counts and decorators do not.
8. **Branch complexity.** A function scores 1, plus 1 for each `if` and `elif`, conditional expression, `for`, `while`, `except` clause and `case` clause, plus 1 for each `for` and each `if` inside a comprehension, plus (operands − 1) for each `and`/`or` chain. Nested functions and classes are scored on their own, not in the enclosing function, and a lambda counts in the function that holds it. No function scores more than 8.
9. **Nesting.** A function's body is depth 0. An `if`, `for`, `while`, `with`, `try` or `match` statement sits one deeper than the block that holds it, and an `elif` is at its `if`'s depth. No such statement is deeper than 2.
10. **Parameters.** A function or method has at most 4 parameters, not counting a method's leading `self` or `cls`. `*args` and `**kwargs` count one each.
11. **No module or class state.** A module-level assignment (plain or annotated) binds only a number (a leading minus is allowed), a string literal (adjacent literals count as one; an f-string does not), `None`/`True`/`False`, a bare or dotted name, a tuple of these, or `frozenset(...)` of a tuple, list or set display of these (or `frozenset()`). `__all__` is the one exception, and there is no augmented assignment (`+=` and the like) at module level. A compiled regex, a dict, list or set, a call or an object instance at module level is state. The same rules hold in a class body, where a `dataclasses.field(...)` call is also allowed.
12. **No implicit mutation.** No `global` or `nonlocal` statement, and no function decorated with `functools.cache`, `functools.lru_cache` or `functools.cached_property`.
13. **Annotations everywhere.** Every function and method, private and nested ones included, annotates every parameter except a method's leading `self`/`cls`, and its return (`-> None` included). Lambdas are exempt.
14. **Annotation form.** Annotations use builtin generics and `|` unions (`list[str]`, `tuple[int, ...]`, `str | None`). No annotation uses `Optional`, `Union`, `List`, `Dict`, `Set`, `FrozenSet`, `Tuple`, `Type` or `Any`, no module imports those names from `typing`, no annotation is or contains a string literal, and no module has `from __future__ import annotations`.
15. **`__all__`.** Every module, `__init__` included, assigns `__all__` once, to a list literal of strings. It equals the sorted (Python `sorted`, capitals first) names the module defines at top level with `def`, `class` or assignment that do not start with `_`. In `__init__` it equals the sorted names it imports, using the `as` name where there is one.
16. **Docstrings.** Every module, every top-level function and class whose name does not start with `_`, and every such method of such a class has a docstring. Its first line is at most 72 characters and ends with a period.
17. **Names.** Function, method and parameter names are snake_case: lowercase letters and digits, words joined by single underscores, an optional leading underscore. Dunder methods are allowed. Class names are CapWords with an optional leading underscore, and every class in `errors` ends in `Error`. Names assigned at module level, `__all__` aside, are UPPER_CASE with an optional leading underscore.
18. **One definition.** No two modules define a top-level function or class with the same name, private names included.
19. **Classes only in `errors` and `model`.** No other module defines a class.
20. **Raising.** Every `raise` that names an exception raises an `errors` class by its bare name, imported with `from semverkit.errors import …`, either the class or a call of it (`raise InvalidRangeError(msg) from None` is fine). A bare `raise` is allowed. `SemverError`'s only base is `ValueError`, and every other `errors` class has exactly one base, another `errors` class.
21. **Catching.** There is no bare `except:` and no `except Exception` or `except BaseException`, alone or in a tuple.
22. **Output.** Only `cli` calls `print` or uses `sys.stdout`, `sys.stderr`, `sys.stdin`, `sys.argv` or `sys.exit`.
23. **Model classes.** An enum in `model` has `enum.Enum` (or `Enum`) as its only base. Every other `model` class has no base and is decorated with `@dataclass(frozen=True, slots=True)` (the same call spelled `dataclasses.dataclass(...)` also counts).
24. **Exhaustive dispatch.** `bumping.bump` (on `part`), `desugar.expand` (on `prefix`) and `matching.test_op` (on `op`) each hold exactly one `match` statement on that parameter. Its cases are value patterns written `Part.MAJOR`, `Prefix.CARET`, `Op.LT` and so on, or `|` alternatives of them. There is no guard, no wildcard and no capture pattern, and the cases name every member of the enum exactly once.

## Unchanged behaviour

Every exported function, `semverkit.cli.main` and the new functions above give the results and messages the package gives today, for every input. That covers the corner cases the current code handles: `=` and `v` prefixes, parts after a wildcard, prerelease matching, sort and max/min ties, skipped bad versions, and error order. The existing suite must stay green without edits. Run it with `python3 -m pytest -q tests`.
