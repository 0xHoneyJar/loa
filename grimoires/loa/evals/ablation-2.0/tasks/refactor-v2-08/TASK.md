# Task: rebuild taskgraph on a strict layered layout

`taskgraph` (under `src/taskgraph/`) reads task manifests. Each line is `name: duration [needs a, b] [priority n]`, durations are written `90`, `45m` or `2h`, and `#` starts a comment. The package checks for unknown dependencies and cycles, orders tasks topologically with priority and name tie-breaking, groups them by level, finds the critical path and every task's slack, simulates a fixed number of workers, renders a report and a Graphviz graph and has a command line (`taskgraph.cli.main`). The code works but is tangled. One long function parses the manifest, the graph algorithms share one module with nested closures, `Graph` caches a name dict, a settings dict and a call counter sit at module level, `cli` imports the package back, and nothing is annotated. Restructure it into the layout below. Every rule is checked across the whole package, so one module that breaks a rule breaks it for the package.

## Target layout

`src/taskgraph/` holds exactly these modules and no subpackage:

| Layer | Module | Holds |
|---|---|---|
| 0 | `errors` | `PlanError(ValueError)` and its subclasses `ParseError`, `GraphError`, `CycleError` (a `GraphError`), `ArgumentError` |
| 1 | `model` | the dataclasses `Task`, `Graph`, `Slot` and the enums `Unit`, `Command` |
| 2 | `names` | task-name checking |
| 2 | `durations` | `unit_minutes`, `parse_duration`, `format_duration` |
| 2 | `index` | lookups over a graph: tasks by name, the tasks that need a task |
| 3 | `lines` | `parse_line` and the `needs` and `priority` clauses |
| 3 | `validate` | `check_graph` and the cycle search |
| 3 | `ordering` | `topological_order`, `levels` |
| 4 | `manifest` | `parse_manifest` |
| 4 | `critical` | earliest finish times, `critical_path`, slack |
| 4 | `simulate` | `simulate` |
| 5 | `render` | the schedule lines, the summary, the dot graph |
| 6 | `facade` | the manifest-string functions the package exports |
| 7 | `cli` | `main`, `run` |
| top | `__init__` | re-exports only |

**Data model** (`model`):
- `Task(name: str, duration: int, needs: tuple[str, ...] = (), priority: int = 0, line: int = 0)`. The duration is in minutes and `line` is the task's line number in its manifest, counted from 1.
- `Graph(tasks: tuple[Task, ...])`, the tasks in definition order.
- `Slot(name: str, start: int, end: int, worker: int)`, one task placed on a worker. Workers are numbered from 1.
- `Unit`: `MINUTES = "m"`, `HOURS = "h"`. A bare number is minutes.
- `Command`, one member per command-line action: `ORDER = "order"`, `LEVELS = "levels"`, `CRITICAL = "critical"`, `SCHEDULE = "schedule"`, `CHECK = "check"`, `SLACK = "slack"`, `DOT = "dot"`.

**Functions with a fixed signature.** Write these exactly as shown: parameter names, annotations and defaults.
- `lines.parse_line(text: str, line: int) -> Task` parses one comment-free, non-blank line as the package does today, errors and their order included.
- `manifest.parse_manifest(text: str) -> Graph` parses a whole manifest without checking dependencies.
- `validate.check_graph(graph: Graph) -> Graph` rejects unknown dependencies, then cycles, with today's messages, and returns the graph.
- `ordering.topological_order(graph: Graph) -> list[str]` and `critical.critical_path(graph: Graph) -> tuple[int, list[str]]` work on a checked graph and give today's results.
- `simulate.simulate(graph: Graph, workers: int) -> list[Slot]` gives today's schedule, sorted as it is today, and checks the worker count first.
- `cli.run(command: Command, text: str, workers: int) -> str` returns the output of one command for a manifest's text.

**Errors.** Every error keeps today's class and message. Every class lives in `errors`: `ParseError` for manifest syntax, `GraphError` for an unknown dependency, `CycleError` for a cycle, and `ArgumentError` for a worker count and the command line's `cannot read …`.

**Exports.** `taskgraph` exports these names, with today's behaviour: `ArgumentError`, `CycleError`, `GraphError`, `ParseError`, `PlanError`, `critical_path`, `format_duration`, `levels`, `order`, `parse`, `report`, `schedule`, `slack` and `to_dot`. `taskgraph.parse` returns a checked `Graph`, and `taskgraph.schedule` keeps returning `(name, start, end, worker)` tuples. Other names that `__init__` happens to import today need not stay.

## Rules

1. **Layers.** A module imports another package module only when that module's layer is strictly lower than its own. `__init__` may import from any module.
2. **Import form.** Package modules are imported only as `from taskgraph.<module> import <names>`. There is no `import taskgraph…`, no relative import and no `*` import.
3. **Imports at the top.** Every `import` statement is a top-level statement of its module, never inside a function, class, `if` or `try`.
4. **No private imports.** No module imports a name that starts with `_` from another package module.
5. **`__init__`.** It holds only its docstring, `from taskgraph.<module> import …` statements and `__all__`.
6. **Module size.** A module has at most 100 lines.
7. **Function size.** A function or method spans at most 18 lines, from its `def` line to its last line. The docstring counts and decorators do not.
8. **Branch complexity.** A function scores 1, plus 1 for each `if` and `elif`, conditional expression, `for`, `while`, `except` clause and `case` clause, plus 1 for each `for` and each `if` inside a comprehension, plus (operands − 1) for each `and`/`or` chain. Nested functions and classes are scored on their own, not in the enclosing function, and a lambda counts in the function that holds it. No function scores more than 8.
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
20. **Raising.** Every `raise` that names an exception raises an `errors` class by its bare name, imported with `from taskgraph.errors import …`, either the class or a call of it (`raise ArgumentError(msg) from None` is fine). A bare `raise` is allowed. `PlanError`'s only base is `ValueError`, and every other `errors` class has exactly one base, another `errors` class (`CycleError` derives from `GraphError`).
21. **Catching.** There is no bare `except:` and no `except Exception` or `except BaseException`, alone or in a tuple.
22. **Output.** Only `cli` calls `print` or uses `sys.stdout`, `sys.stderr`, `sys.stdin`, `sys.argv` or `sys.exit`.
23. **Model classes.** An enum in `model` has `enum.Enum` (or `Enum`) as its only base. Every other `model` class has no base and is decorated with `@dataclass(frozen=True, slots=True)` (the same call spelled `dataclasses.dataclass(...)` also counts).
24. **Exhaustive dispatch.** `durations.unit_minutes` holds exactly one `match` statement on `unit`, and `cli.run` holds exactly one `match` statement on `command`. Its cases are value patterns written `Unit.HOURS`, `Command.ORDER` and so on, or `|` alternatives of them. There is no guard, no wildcard and no capture pattern, and the cases name every member of the enum exactly once.

25. **No recursion.** No function, nested ones included, calls itself by its bare name. No top-level function calls itself through other package functions either: for that, a call counts when it calls, by bare name, a function defined at the top level of the same module or imported from a package module, and calls inside a nested function or a lambda count as calls of the top-level function that holds them.
26. **Single exit.** A function or method has at most one `return` statement of its own, and when it has one, that statement is the last statement of its body. A nested function is judged on its own.
27. **No in-place mutation.** No module calls a method named `append`, `extend`, `insert`, `pop`, `popitem`, `remove`, `clear`, `update`, `setdefault`, `add`, `discard`, `sort` or `reverse`. No module has an augmented assignment (`+=` and the like) or an assignment or `del` whose target, or one element of whose target tuple, is a subscript or an attribute. Build new values instead (`x = x + [y]`, `{**d, k: v}`, comprehensions).

## Unchanged behaviour

Every exported function, `taskgraph.cli.main` and the new functions above give the results and messages the package gives today, for every input. That covers the corner cases the current code handles: the order of the parse checks, a duplicate task reported after its own line parses, unknown dependencies reported before cycles, the cycle the search meets first and how it is rotated, priority and name ties, critical-path ties, zero-length tasks, which worker a task gets, and the report's column widths. The existing suite must stay green without edits. Run it with `python3 -m pytest -q tests`.
