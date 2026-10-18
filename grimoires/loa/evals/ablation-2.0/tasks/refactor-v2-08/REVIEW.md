# Fairness review — refactor-v2-08

**Reviewer:** fairness session R3 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer F3 (swap round 1) · **Verdict:** PASS

## 1. No solution leak

PASS. `grep -ril hidden TASK.md fixture/` is empty. The brief and the fixture name no arm id, no test name, no overlay path and no oracle. The only `structure` hit in `TASK.md` is the word "Restructure".

Every rule case traces to a numbered rule of the brief. I read each predicate against its rule:

- `test_module_set_is_exactly_the_stated_one` (240–242) traces to "`src/taskgraph/` holds exactly these modules and no subpackage". The fixture's `graph`, `parser`, `report`, `scheduler`, `util` and `config` must go, and no fixture test imports them. The tests import only `taskgraph` and `taskgraph.cli`.
- `test_init_only_reexports`, `test_imports_point_strictly_down_the_layers`, `test_package_imports_use_the_from_module_form`, `test_imports_only_at_module_top_level` and `test_no_private_name_imported_across_modules` trace to rules 5, 1, 2, 3 and 4. The `LAYERS` table (13–16) equals the brief's layer column.
- `test_module_length_limit`, `test_function_length_limit` and `test_parameter_count_limit` trace to rules 6, 7 and 10. `fn.lineno` is the `def` line, so decorators do not count, and a leading `self`/`cls` is dropped only for functions that sit directly in a class body.
- `_complexity` (85–94) traces to rule 8. It adds 1 per `If` (an `elif` is a nested `If`), `IfExp`, `For`, `While`, `ExceptHandler` and `match_case`, plus 1 per comprehension and 1 per comprehension `if`, plus operands − 1 per `BoolOp`. It skips nested defs and classes but walks into lambdas, as the brief says.
- `_max_depth` (102–127) traces to rule 9. An `elif` chain is unrolled to its `if`'s depth. The author notes that `else: if` reads as `elif` too, which is lenient and harms no solver.
- `_constant_value` (178–196) and `test_no_module_or_class_state` (335–347) trace to rule 11. It covers a leading minus on a constant only, dotted names, tuples, `frozenset()` and `frozenset(...)` of a set, list or tuple display of these, the `__all__` exception, module-level `AugAssign` as state, and `field(...)` in class bodies.
- `test_no_global_nonlocal_or_function_cache`, `test_every_function_is_fully_annotated` and `test_annotations_use_builtin_generics_and_union_syntax` trace to rules 12, 13 and 14. The string-literal check and the `__future__` ban are both stated.
- `test_dunder_all_lists_exactly_the_public_names_sorted` (394–408) traces to rule 15, including the `as` name in `__init__`. `test_public_docstrings_with_a_short_first_sentence` traces to rule 16.
- The three naming tests use the regexes on 425–428, and they trace to rule 17. Parameters are snake_case, `errors` classes end in `Error`, and module-level names are UPPER_CASE.
- `test_one_definition_per_top_level_name`, `test_classes_only_where_stated`, `test_every_raise_uses_a_package_error`, `test_errors_derive_from_one_base`, `test_no_broad_or_bare_except`, `test_output_only_from_the_cli_module` and `test_model_classes_are_frozen_slotted_dataclasses_or_enums` trace to rules 18 to 23. Rule 18 forces the facade functions to use names that differ from `ordering.levels` and `critical.critical_path`, with `as` names in `__init__`. That is a design consequence of stated rules, not a hidden requirement.
- `test_stated_public_signatures` (603–610) compares the six signatures under "Functions with a fixed signature" text for text. `cli.run` is stated but not checked, which is lenient.
- `_match_cases_cover` (548–562) traces to rule 24. It needs exactly one `match` on the subject text `unit` or `command`, value patterns `Unit.X`/`Command.X` or `|` of them, no guard, and each member exactly once.
- `test_no_recursion_direct_or_mutual` (657–677) traces to rule 25 in both of its parts. The first part is the top-level call graph over bare-name calls to same-module top-level functions or package imports, with nested functions and lambdas walked into their holder. The second part is a self-call by bare name within a function's own nodes. Edges to imported classes do not form nodes, so they cannot fake a cycle.
- `test_single_exit_functions` (680–687) traces to rule 26, with nested functions judged on their own. `test_no_in_place_mutation` (703–713) traces to rule 27: the thirteen method names, any `AugAssign`, and `Assign`/`AnnAssign`/`Delete` targets that are a subscript or attribute, or a tuple element that is one.

**The oracle encodes today's behaviour.** The eight conformance cases compare against `_oracle_graph.py`. I ran my own differential of the oracle's layer functions against the base package's internals. It used the test's own generators with a different seed and covered 20,000 manifests and 5,000 cyclic graphs. The functions compared were `parse_manifest`, `graph.check`, `graph.order`, `graph.levels`, `graph.critical_path`, `graph.slack` and `scheduler.simulate`, with worker counts including 0, 65 and `True`.

```
{'parse': 20000, 'check': 12800, 'cyc': 5000, 'valid': 11449} diffs 0
```

So every conformance assertion traces to "give the results and messages the package gives today, for every input" and to the corner-case list in "Unchanged behaviour". I spot-checked five oracle rules against the base code:

- `_added` reports a duplicate after its own line parses.
- `_unknown` runs before `find_cycle`.
- `rotate_cycle` starts at the smallest name and closes the cycle.
- `ready_key` is `(-priority, name)`.
- `simulate` checks the workers first, uses the lowest free worker and the `(start, worker, name)` sort.

`test_simulate_matches_the_package` compares `Slot` fields through `_plain`, which follows the stated `-> list[Slot]`.

## 2. Red then green

PASS. The runner was host Python 3.13 with `timeout 300 env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`. Each side used a fresh `fixture/` copy under `mktemp -d`, with both manifest entries at `tests/structure/`. The reference applied with `patch -p1 --batch --forward` (exit 0) and left no `.rej` or `.orig`. The copies were deleted afterwards.

```
[base] tests --ignore=tests/structure => 40 passed in 0.04s
[base] tests/structure                => 39 failed, 1 passed in 0.65s
  patching file src/taskgraph/{__init__,cli,config,critical,durations,errors,facade,graph,index,lines,
                               manifest,model,names,ordering,parser,render,report,scheduler,simulate,util,validate}.py
[ref]  tests --ignore=tests/structure => 40 passed in 0.04s
[ref]  tests/structure                => 40 passed in 1.22s
[ref]  tests (all)                    => 80 passed in 1.24s
```

The counts match `success_criterion`. The structural check is 39 failed and 1 passed at base. The one pass is `test_exported_functions_match_the_package`, which the base satisfies by construction. The check is 40 of 40 at the reference, and the 40-case fixture suite is green at both ends. `regression_command` is null, as it is for refactors.

## 3. Criterion mechanical

PASS. `success_criterion` is one line. It names the file, both overlay paths, 40 of 40, the base split with the identity of the one base pass, the reference patch and the suite condition. `criterion` is behavioural and names no path or test.

`grader_protected` lists `tests/conftest.py`, `tests/test_cli.py`, `tests/test_manifest.py` and `tests/test_plan.py`. That is every fixture test file, and the fixture has no ini, pyproject or setup.cfg. `bounds` are exactly `{max_turns: {IMPLEMENT: 80, BARE: 190}, timeout_min: {IMPLEMENT: 35, BARE: 80}}`. The file has `suite_version: 2`, `source.kind: synthetic` and `date: "2026-10-17"`. The churn of 21 files, +623/−406, matches `git apply --numstat` of the patch.

The fixture is 64K, with 418 source lines plus 211 test lines. It holds no cache, nothing named `hidden*`, no dot-entries, `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/`, `.run/` or `.git/`. Both overlay `dest`s are under `tests/`. `no-secrets.sh` is not at `.claude/scripts/`, so I did not run it. The author reports exit 0.

## Notes

- **Advisory: `ordering.levels` is pinned only implicitly.** `test_order_and_levels_match_the_package` (870) calls `levels(graph)` with one positional `Graph` and compares with `==` against a list of sorted lists. The brief fixes the signatures of `topological_order` and `critical_path` but not of `levels`. Its shape follows from "the new functions … give the results … the package gives today", since today's `graph.levels(graph)` returns a list of lists. A solver that returns tuples or adds a parameter would fail eight-hundred-odd assertions. The brief could close this by adding `ordering.levels(graph: Graph) -> list[list[str]]` to the fixed-signature list. This is not a FAIL, because the natural move keeps today's call and return shape, and the author's blind solver passed all eight behaviour classes.
- **Advisory: lenient spots, none of which can fail a correct solution.** `cli.run`'s signature is stated but not checked. `else: if` is read as `elif`. `from sys import stdout` would slip past rule 22. A `for` or `with` target that is an attribute slips past rule 27.
- **Hardness:** probably too easy for the a0_bare ≤ 0.5 bar. The correct change rewrites all 8 modules into 14 and touches 21 files. Rules 25–27 force iterative and functional rewrites of the DFS, Kahn's algorithm and the simulator. However, every rule is stated mechanically enough that an agent writes its own AST checker. The behaviour oracle is the base code in the tree, so it can differential-test as it goes. The fixture suite pins only the exports, not the layer functions. The author's blind Opus solver scored 39 of 40 in about four minutes, missing only nesting. A bare agent with 190 turns and 80 minutes very likely clears 0.5. Its likeliest misses are rule 9 or rule 8 under the match-plus-loop shapes, and the `levels` shape above.
