# Task: rebuild patchwork on a strict layered layout

`patchwork` (under `src/patchwork/`) implements RFC 6901 JSON pointers and RFC 6902 JSON patches. It resolves pointers, validates a whole patch before applying any operation, applies `add`, `remove`, `replace`, `move`, `copy` and `test` atomically to a copy, diffs two documents into a patch, explains a patch line by line, lists a document's pointers, counts its value types and has a command line (`patchwork.cli.main`). The code works but is tangled. One long function validates and another applies every operation through string comparisons. `move` repeats the logic of `remove` and `add`, `explain` and `cli` reach back into private helpers and the package, a registry dict and a copy counter sit at module level, and nothing is annotated. Restructure it into the layout below. Every rule is checked across the whole package, so one module that breaks a rule breaks it for the package.

## Target layout

`src/patchwork/` holds exactly these modules and no subpackage:

| Layer | Module | Holds |
|---|---|---|
| 0 | `errors` | `PatchError(ValueError)` and its subclasses `PointerError`, `PathError`, `OperationError`, `TestFailedError`, `InputError` |
| 1 | `model` | the dataclasses `Operation`, `Target` and the enums `OpKind`, `JsonType` |
| 2 | `pointer` | `parse_pointer`, `format_pointer` |
| 2 | `equality` | `json_equal` |
| 3 | `navigate` | `where`, `array_index`, `insert_index`, `get_at` |
| 3 | `operations` | `required_members`, `parse_operation`, `parse_patch` |
| 3 | `survey` | `list_pointers`, `json_type`, `type_counts` |
| 4 | `mutate` | `add_at`, `remove_at`, `replace_at` |
| 4 | `diffing` | `diff` |
| 4 | `explain` | `explain_operation`, `explain_patch` |
| 5 | `apply` | `apply_operation`, `apply_patch` |
| 6 | `facade` | the functions the package exports |
| 7 | `cli` | `main` |
| top | `__init__` | re-exports only |

**Data model** (`model`):
- `OpKind`: `ADD = "add"`, `REMOVE = "remove"`, `REPLACE = "replace"`, `MOVE = "move"`, `COPY = "copy"`, `TEST = "test"`.
- `JsonType`, in the order `type_counts` reports: `OBJECT = "object"`, `ARRAY = "array"`, `STRING = "string"`, `NUMBER = "number"`, `BOOLEAN = "boolean"`, `NULL = "null"`.
- `Operation(kind: OpKind, path: str, value: object = None, source: str = "", index: int = 0)`: one validated operation. `source` is the `from` pointer of `move` and `copy` and `""` otherwise, `value` is the `value` member (or `None` when the operation has none), and `index` is the operation's position in its patch, counted from 0.
- `Target(tokens: tuple[str, ...], pointer: str, index: int = -1)`: a parsed pointer with its text and the index of the operation it belongs to, or -1 outside a patch. Errors about a target start with `operation <index>: ` when the index is 0 or more, as they do today.

**Functions with a fixed signature.** Write these exactly as shown: parameter names, annotations and defaults.
- `pointer.parse_pointer(text: str) -> tuple[str, ...]` splits and unescapes a pointer as `patchwork.parse_pointer` does today, as a tuple.
- `navigate.get_at(document: object, tokens: tuple[str, ...], target: Target) -> object` walks `tokens` from the root, with error messages naming `target`.
- `operations.parse_operation(raw: object, index: int) -> Operation` validates one raw operation as the package does today, errors and their order included.
- `apply.apply_operation(document: object, op: Operation) -> object` applies one validated operation in place where it can and returns the new root.
- `diffing.diff(a: object, b: object, tokens: tuple[str, ...] = ()) -> list[dict[str, object]]` returns the raw operations `patchwork.diff` returns today, with every path under the pointer that `tokens` spell.

**Errors.** Every error keeps today's message. Every class lives in `errors`: `PointerError` for pointer syntax, `PathError` for locations (`path not found`, the array-index messages, `cannot descend into a scalar`, `cannot add to a scalar`, `cannot remove the root`, `not a JSON value`), `OperationError` for patch shape (`patch must be a list`, `not an object`, `missing …`, `unknown op`, `… must be a string`, `cannot move a value into itself`), `TestFailedError` for `test failed at …`, and `InputError` for the command line's `cannot read …` and `bad json in …`.

**Exports.** `patchwork` exports these names, with today's behaviour: `OperationError`, `PatchError`, `PathError`, `PointerError`, `TestFailed`, `apply_patch`, `diff`, `explain`, `format_pointer`, `json_equal`, `list_pointers`, `parse_pointer`, `resolve` and `type_counts`. `patchwork.TestFailed` is `TestFailedError` exported under the old name, and `patchwork.parse_pointer` keeps returning a list. Other names that `__init__` happens to import today need not stay.

## Rules

1. **Layers.** A module imports another package module only when that module's layer is strictly lower than its own. `__init__` may import from any module.
2. **Import form.** Package modules are imported only as `from patchwork.<module> import <names>`. There is no `import patchwork…`, no relative import and no `*` import.
3. **Imports at the top.** Every `import` statement is a top-level statement of its module, never inside a function, class, `if` or `try`.
4. **No private imports.** No module imports a name that starts with `_` from another package module.
5. **`__init__`.** It holds only its docstring, `from patchwork.<module> import …` statements and `__all__`.
6. **Module size.** A module has at most 110 lines.
7. **Function size.** A function or method spans at most 22 lines, from its `def` line to its last line. The docstring counts and decorators do not.
8. **Branch complexity.** A function scores 1, plus 1 for each `if` and `elif`, conditional expression, `for`, `while`, `except` clause and `case` clause, plus 1 for each `for` and each `if` inside a comprehension, plus (operands − 1) for each `and`/`or` chain. Nested functions and classes are scored on their own, not in the enclosing function, and a lambda counts in the function that holds it. No function scores more than 7.
9. **Nesting.** A function's body is depth 0. An `if`, `for`, `while`, `with`, `try` or `match` statement sits one deeper than the block that holds it, and an `elif` is at its `if`'s depth. No such statement is deeper than 2.
10. **Parameters.** A function or method has at most 3 parameters, not counting a method's leading `self` or `cls`. `*args` and `**kwargs` count one each.
11. **No module or class state.** A module-level assignment (plain or annotated) binds only a number (a leading minus is allowed), a string literal (adjacent literals count as one; an f-string does not), `None`/`True`/`False`, a bare or dotted name, a tuple of these, or `frozenset(...)` of a tuple, list or set display of these (or `frozenset()`). `__all__` is the one exception, and there is no augmented assignment (`+=` and the like) at module level. A compiled regex, a dict, list or set, a call or an object instance at module level is state. The same rules hold in a class body, where a `dataclasses.field(...)` call is also allowed.
12. **No implicit mutation.** No `global` or `nonlocal` statement, and no function decorated with `functools.cache`, `functools.lru_cache` or `functools.cached_property`.
13. **Annotations everywhere.** Every function and method, private and nested ones included, annotates every parameter except a method's leading `self`/`cls`, and its return (`-> None` included). Lambdas are exempt.
14. **Annotation form.** Annotations use builtin generics and `|` unions (`list[str]`, `tuple[int, ...]`, `str | None`). No annotation uses `Optional`, `Union`, `List`, `Dict`, `Set`, `FrozenSet`, `Tuple`, `Type` or `Any`, no module imports those names from `typing`, no annotation is or contains a string literal, and no module has `from __future__ import annotations`.
15. **`__all__`.** Every module, `__init__` included, assigns `__all__` once, to a list literal of strings. It equals the sorted (Python `sorted`, capitals first) names the module defines at top level with `def`, `class` or assignment that do not start with `_`. In `__init__` it equals the sorted names it imports, using the `as` name where there is one.
16. **Docstrings.** Every module, every top-level function and class whose name does not start with `_`, and every such method of such a class has a docstring. Its first line is at most 72 characters and ends with a period.
17. **Names.** Function, method and parameter names are snake_case: lowercase letters and digits, words joined by single underscores, an optional leading underscore. Dunder methods are allowed. Class names are CapWords with an optional leading underscore, and every class in `errors` ends in `Error`. Names assigned at module level, `__all__` aside, are UPPER_CASE with an optional leading underscore.
18. **One definition.** No two modules define a top-level function or class with the same name, private names included.
19. **Classes only in `errors` and `model`.** No other module defines a class.
20. **Raising.** Every `raise` that names an exception raises an `errors` class by its bare name, imported with `from patchwork.errors import …`, either the class or a call of it (`raise InputError(msg) from None` is fine). A bare `raise` is allowed. `PatchError`'s only base is `ValueError`, and every other `errors` class has exactly one base, another `errors` class.
21. **Catching.** There is no bare `except:` and no `except Exception` or `except BaseException`, alone or in a tuple.
22. **Output.** Only `cli` calls `print` or uses `sys.stdout`, `sys.stderr`, `sys.stdin`, `sys.argv` or `sys.exit`.
23. **Model classes.** An enum in `model` has `enum.Enum` (or `Enum`) as its only base. Every other `model` class has no base and is decorated with `@dataclass(frozen=True, slots=True)` (the same call spelled `dataclasses.dataclass(...)` also counts).
24. **Exhaustive dispatch.** `operations.required_members` holds exactly one `match` statement on `kind`, and `apply.apply_operation` and `explain.explain_operation` each hold exactly one `match` statement on `op.kind`. Its cases are value patterns written `OpKind.ADD` and so on, or `|` alternatives of them. There is no guard, no wildcard and no capture pattern, and the cases name every member of `OpKind` exactly once.

## Unchanged behaviour

Every exported function, `patchwork.cli.main` and the new functions above give the results and messages the package gives today, for every input. That covers the corner cases the current code handles: the order of validation, `-` and leading zeros in array indexes, whole-document operations, moves inside one array, `move` onto itself, numbers against booleans in `test`, the copy the input document and every inserted value get, the diff's operation order and document order in the pointer list. The existing suite must stay green without edits. Run it with `python3 -m pytest -q tests`.
