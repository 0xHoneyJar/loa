# Task: rebuild cronplan on a strict layered layout

`cronplan` (under `src/cronplan/`) parses five-field cron expressions: lists, ranges, steps, month and weekday names, `?`, the macros `@yearly` … `@hourly`, and the day items `L`, `LW`, `L-n`, `nW`, `dL` and `d#n`. It finds fire times, checks a moment, normalises an expression, counts fires per day of a month and has a command line (`cronplan.cli.main`). The code works but is tangled. Parsing lives in one long function, `cli` and `cache` import back into the package, the day items are tuples tagged with strings, settings and name tables sit in module-level dicts, an `lru_cache` holds parsed schedules, and nothing is annotated. Restructure it into the layout below. Every rule is checked across the whole package, so one module that breaks a rule breaks it for the package.

## Target layout

`src/cronplan/` holds exactly these modules and no subpackage:

| Layer | Module | Holds |
|---|---|---|
| 0 | `errors` | `CronError(ValueError)` and its subclasses `ParseError`, `RangeError`, `SearchError`, `ArgumentError` |
| 1 | `model` | the dataclasses `SpecialDay`, `Field`, `Schedule` and the enums `FieldKind`, `Special` |
| 2 | `limits` | `limits`, `label`, `full_values` |
| 2 | `names` | the month and weekday name tables and their lookups |
| 2 | `dates` | calendar arithmetic: the Sunday-is-0 weekday, the last day, the last weekday, the nearest weekday |
| 3 | `items` | parsing one comma-separated item |
| 3 | `render` | `format_special`, `format_field`, `format_schedule` |
| 3 | `days` | `special_matches`, `day_matches` |
| 4 | `fields` | `parse_field` |
| 5 | `expressions` | `parse_expression` and the macros |
| 6 | `search` | `next_fire`, `fires`, `matches` |
| 7 | `report` | the per-day count of one month |
| 8 | `facade` | the expression-string functions the package exports |
| 9 | `cli` | `main` |
| top | `__init__` | re-exports only |

**Data model** (`model`):
- `FieldKind`, in field order: `MINUTE = "minute"`, `HOUR = "hour"`, `DAY = "day-of-month"`, `MONTH = "month"`, `WEEKDAY = "day-of-week"`. The value is the field's name in messages.
- `Special`, in this order: `MONTH_END = "L"`, `MONTH_END_WEEKDAY = "LW"`, `MONTH_END_OFFSET = "L-"`, `NEAREST_WEEKDAY = "W"`, `LAST_WEEKDAY = "dL"`, `NTH_WEEKDAY = "#"`. A normalised field lists its special items in this member order, then by number, then by ordinal, as it does today.
- `SpecialDay(kind: Special, number: int, nth: int = 0)`. `number` is the `n` of `L-n` and `nW` or the Sunday-is-0 weekday of `dL` and `d#n`, it is 0 for `L` and `LW`, and `nth` is the `n` of `d#n`.
- `Field(kind: FieldKind, values: frozenset[int], specials: tuple[SpecialDay, ...] = (), starred: bool = False)`. `values` are the plain numbers (weekday 7 stored as 0), `specials` the special items in the normalised order without repeats, and `starred` is today's "the field's text starts with `*` or `?`".
- `Schedule(minute: Field, hour: Field, day: Field, month: Field, weekday: Field)`.

**Functions with a fixed signature.** Write these exactly as shown: parameter names, annotations and defaults. `datetime` is imported as a module (`import datetime`).
- `fields.parse_field(text: str, kind: FieldKind) -> Field` parses one field as the package does today, errors included.
- `expressions.parse_expression(text: str) -> Schedule` parses as `cronplan.parse` does today.
- `days.day_matches(schedule: Schedule, day: datetime.date) -> bool` tells whether a day passes the month field and the two day fields.
- `search.next_fire(schedule: Schedule, after: datetime.datetime) -> datetime.datetime` is today's next fire time on a parsed schedule.
- `render.format_schedule(schedule: Schedule) -> str` gives the text `cronplan.normalize` gives today.

**Errors.** Every error keeps today's class and message. Every class lives in `errors`: `ParseError` for the grammar (`not a string`, `unknown macro`, `expected 5 fields`, `bad item`, `bad value`, `step 0`, `is reversed`), `RangeError` for out-of-range values, offsets and ordinals, `SearchError` for `no fire time within 5 years`, and `ArgumentError` for datetimes, counts, years, months and the command line's `bad datetime` and `bad month`.

**Exports.** `cronplan` exports these names, with today's behaviour: `ArgumentError`, `CronError`, `ParseError`, `RangeError`, `Schedule`, `SearchError`, `fires`, `matches`, `month_report`, `next_fire`, `normalize` and `parse`. Other names that `__init__` happens to import today need not stay.

## Rules

1. **Layers.** A module imports another package module only when that module's layer is strictly lower than its own. `__init__` may import from any module.
2. **Import form.** Package modules are imported only as `from cronplan.<module> import <names>`. There is no `import cronplan…`, no relative import and no `*` import.
3. **Imports at the top.** Every `import` statement is a top-level statement of its module, never inside a function, class, `if` or `try`.
4. **No private imports.** No module imports a name that starts with `_` from another package module.
5. **`__init__`.** It holds only its docstring, `from cronplan.<module> import …` statements and `__all__`.
6. **Module size.** A module has at most 120 lines.
7. **Function size.** A function or method spans at most 20 lines, from its `def` line to its last line. The docstring counts and decorators do not.
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
20. **Raising.** Every `raise` that names an exception raises an `errors` class by its bare name, imported with `from cronplan.errors import …`, either the class or a call of it (`raise ArgumentError(msg) from None` is fine). A bare `raise` is allowed. `CronError`'s only base is `ValueError`, and every other `errors` class has exactly one base, another `errors` class.
21. **Catching.** There is no bare `except:` and no `except Exception` or `except BaseException`, alone or in a tuple.
22. **Output.** Only `cli` calls `print` or uses `sys.stdout`, `sys.stderr`, `sys.stdin`, `sys.argv` or `sys.exit`.
23. **Model classes.** An enum in `model` has `enum.Enum` (or `Enum`) as its only base. Every other `model` class has no base and is decorated with `@dataclass(frozen=True, slots=True)` (the same call spelled `dataclasses.dataclass(...)` also counts).
24. **Exhaustive dispatch.** `limits.limits` holds exactly one `match` statement on `kind`, and `days.special_matches` and `render.format_special` each hold exactly one `match` statement on `special.kind`. Its cases are value patterns written `FieldKind.MINUTE`, `Special.MONTH_END` and so on, or `|` alternatives of them. There is no guard, no wildcard and no capture pattern, and the cases name every member of the enum exactly once.

## Unchanged behaviour

Every exported function, `cronplan.cli.main` and the new functions above give the results and messages the package gives today, for every input. That covers the corner cases the current code handles: the order in which errors are found, `?` outside the day fields, names in ranges, weekday 7, steps from a single value, the AND rule when a day field is starred, the nearest-weekday and last-weekday rules, the five-year search horizon and the run folding of normalised fields. The existing suite must stay green without edits. Run it with `python3 -m pytest -q tests`.
