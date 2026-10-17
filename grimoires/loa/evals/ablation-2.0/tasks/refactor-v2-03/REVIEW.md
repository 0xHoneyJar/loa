# Fairness review — refactor-v2-03

**Reviewer:** fairness session R1 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer E2 · **Verdict:** PASS

This is the second review, after the author's fix. The first review failed check 1. Its `constant_value` rejected `frozenset({...})` and `frozenset([...])`, while `TASK.md` allows "`frozenset(...)` of these". The author changed only `hidden/structural/explicit_context_test.py`. `constant_value` now accepts a `frozenset(...)` call with no keywords and at most one positional argument. That argument may be an `ast.Set`, `ast.List` or `ast.Tuple` whose elements are constants or names, checked recursively, or a single constant or name. An empty `frozenset()` is also accepted. `TASK.md`, the fixture and the reference patch are unchanged. `task.yaml` now carries the lead's `BARE` bounds.

## 1. No solution leak

PASS. `grep -ril hidden` over `TASK.md` and `fixture/` is empty. The only hits in the task directory are `task.yaml` and this file, and both are grader-side. Neither the brief nor the fixture names an arm id, a test or the overlay path.

**The frozenset contradiction is resolved.** I repeated the first reviewer's probe on a fresh copy of the reference tree. I changed only `config.PRIORITIES` from the tuple to each frozenset spelling. Every spelling keeps both the structural check and the suite green:

```
[frozenset({"high", "normal", "low"})]   suite: 19 passed | structure: 14 passed
[frozenset(["high", "normal", "low"])]   suite: 19 passed | structure: 14 passed
[frozenset(("high", "normal", "low"))]   suite: 19 passed | structure: 14 passed
```

**The relaxation does not admit state.** I ran `test_no_mutable_module_or_class_state` alone for each form, because some probes change behaviour and break the functional tests:

```
{"high", "normal", "low"}        1 failed   (a bare set display stays state)
["high"]                         1 failed
frozenset([{"a": 1}])            1 failed   (a dict element is rejected)
frozenset({"high"}, {"low"})     1 failed   (two arguments)
frozenset(iterable=("a",))       1 failed   (keyword)
frozenset(x for x in "ab")       1 failed   (generator)
frozenset(set())                 1 failed
frozenset([("a", 1)])            1 passed   (tuples of constants)
frozenset()                      1 passed
```

The rejection of `frozenset(set())` is consistent with the brief. A call is not one of "these". No plausible solution spells an empty frozenset that way.

Every assertion traces to a brief sentence:

- `test_no_mutable_module_or_class_state` (lines 57–69) traces to the module-level rule. Its constants are "numbers, strings, `None`/`True`/`False`, names, and tuples or `frozenset(...)` of these, apart from `__all__`". It also traces to "A dict, list or set at module level is state, even when it is never mutated", which covers `DEFAULT_SLA_HOURS`. The class-body branch traces to "The same rule holds for assignments in a class body, where a `dataclasses.field(...)` call is also allowed". `ast.Attribute` values such as `enum.Enum` members fall under "names".
- `test_no_global_or_nonlocal_statement`, `test_no_configure_set_clock_or_reset` and `test_no_function_cache` trace to "No module uses `global` or `nonlocal`, decorates a function with `functools.cache` or `functools.lru_cache`, or defines a function named `configure`, `set_clock` or `reset`".
- `test_public_functions_take_ctx_first`, with 6 cases, traces to "Every public function … in `config`, `clock`, `store`, `audit`, `service` and `reports` takes the context as its first positional parameter, named `ctx`". Its `assert public, module` line also requires each of the six modules to keep a public function. See the advisory below.
- `test_context_checks_the_settings` traces to the `Context(*, sla_hours=None, max_open_per_agent=3, clock=None)` sentence and to "raising `ValueError` with the existing messages". Both messages are the fixture's current `config.configure` messages.
- `test_functions_work_on_an_explicit_context` traces to the `service.open_ticket(ctx, title, priority="normal")` and `reports.workload(ctx)` examples and to "keeps its other parameters in their current order". The history line format is the fixture's current output.
- `test_two_desks_do_not_share_tickets_events_or_limits` and `test_each_desk_keeps_its_own_settings_and_clock` trace to "Two desks never share tickets, ids, events, settings or clocks" and to the unchanged `Desk` behaviour.

## 2. Red then green

PASS. The runner was host Python 3.13.5 with pytest 9.0.2, using `PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`. Each side used a fresh `fixture/` copy under `mktemp -d`, with the manifest file at its `dest`. The reference applied with `patch -p1` after a clean dry run and left no `.orig` or `.rej`. The copies were deleted afterwards.

```
[base] pytest -q tests --ignore=tests/structure => 19 passed in 0.02s
[base] pytest -q tests/structure                => 14 failed in 0.06s
  patching file src/ticketdesk/audit.py
  patching file src/ticketdesk/clock.py
  patching file src/ticketdesk/config.py
  patching file src/ticketdesk/context.py
  patching file src/ticketdesk/desk.py
  patching file src/ticketdesk/reports.py
  patching file src/ticketdesk/service.py
  patching file src/ticketdesk/store.py
[ref]  pytest -q tests --ignore=tests/structure => 19 passed in 0.02s
[ref]  pytest -q tests/structure                => 14 passed in 0.03s
```

The counts match `success_criterion`. The structural check fails 14 of 14 at base and passes 14 of 14 at the reference. The fixture suite has 19 cases and is green at both ends. The fix did not change any count from the first review.

## 3. Criterion mechanical

PASS. `success_criterion` is one line. It names the file, the overlay path, both counts and the suite condition. `criterion` is behavioural and names no path or test. The function names it mentions, `configure`, `set_clock` and `reset`, are part of the target structure. `grader_protected` lists `tests/conftest.py` and `tests/test_desk.py`, and the fixture has no ini or pyproject. `bounds` are `{max_turns: {IMPLEMENT: 80, BARE: 190}, timeout_min: {IMPLEMENT: 35, BARE: 80}}`. The `IMPLEMENT` values match the brief, and the lead's dispatch states that the `BARE` addition is correct (DEC-0580). `suite_version: 2`, `source.kind: synthetic` with the date 2026-10-17, and churn of 8 files with +84/−107 all match the rules and the patch. The fixture is 60K and holds no cache, nothing named `hidden*`, no dot-entries, `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/`, `.run/` or `.git/`. `no-secrets.sh` exits 0.

## Notes

- **Advisory, carried over: modules must keep a public function.** `test_public_functions_take_ctx_first` fails when one of the six modules has no public function. It raises `KeyError` when a module is deleted. The brief implies the modules survive, since their public functions "keep [their] other parameters in their current order", but it never says so outright. An agent could fold `clock.now` into a `Context` method and delete `clock.py`. The fix did not address this, and the first review did not make it a FAIL. One sentence in the brief, "each of the six modules keeps its public functions", would close it.
- **Hardness:** moderate. The change touches eight files, and the state takes five forms. The never-mutated `DEFAULT_SLA_HOURS` dict and the class-body rule are the likely misses. A bare agent that reads the end-state paragraph closely probably passes. One that keeps a module-level default dict, or removes a module's last public function, does not.
