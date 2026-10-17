# Fairness review — refactor-v2-07

**Reviewer:** fairness session R3 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer F3 (swap round 1) · **Verdict:** PASS

## 1. No solution leak

PASS. `grep -ri hidden TASK.md fixture/` is empty. A wider grep for `oracle`, `structure`, `layout_test` and the arm ids also finds nothing in TASK.md or the fixture. The single `arm` substring match is the word "atomically". TASK.md names no overlay path, no test name and no arm id. The fixture's tests use only `patchwork.*` exports and `patchwork.cli.main`, and the brief keeps all of them.

**Rule cases.** There are 35 rule cases, and each one maps to a numbered rule or to the layout table.

- `test_module_set_is_exactly_the_stated_one` traces to "holds exactly these modules and no subpackage". `__pycache__` is excluded.
- `test_init_only_reexports` traces to rule 5. `test_imports_point_strictly_down_the_layers` traces to rule 1 and the layer column. `test_package_imports_use_the_from_module_form` traces to rule 2, and `from patchwork import X` fails both, as stated. `test_imports_only_at_module_top_level` traces to rule 3, and `test_no_private_name_imported_across_modules` traces to rule 4.
- `test_module_length_limit` traces to rule 6 (110 lines). `test_function_length_limit` traces to rule 7: it measures `fn.lineno` to `end_lineno`, so decorators are excluded and the docstring counts, as stated.
- `test_branch_complexity_limit` traces to rule 8 term by term. It counts if/elif, IfExp, for, while, except handlers and match_case. It adds 1 plus the `ifs` per comprehension generator and operands − 1 per BoolOp. Nested defs are skipped and lambdas are counted in the enclosing function. A six-case `match` scores exactly 7, so `apply_operation` with one case per member must have no other branch. That follows arithmetically from rules 8 and 24, and `|` alternatives are an allowed way out.
- `test_nesting_depth_limit` traces to rule 9. The function body is depth 0, a statement sits at its block's depth + 1, and elif chains and `else: if` stay at the `if`'s depth. The second of these is more lenient than the brief, never stricter.
- `test_parameter_count_limit` traces to rule 10. Posonly, kwonly, `*args` and `**kwargs` are counted, and a leading self/cls is dropped.
- `test_no_module_or_class_state` traces to rule 11. I checked six branches of `_constant_value`. A Constant (adjacent literals are one Constant) is accepted. A JoinedStr (f-string) is rejected. USub of a Constant is accepted. A dotted name and a tuple of these are accepted. `frozenset()` and `frozenset` of a list, set or tuple display are accepted, and any other Call is rejected. AugAssign is rejected at module level. In class bodies, `field(...)` and `dataclasses.field(...)` are accepted.
- `test_no_global_nonlocal_or_function_cache` traces to rule 12. `test_every_function_is_fully_annotated` traces to rule 13, with lambdas exempt because only FunctionDef is walked. `test_annotations_use_builtin_generics_and_union_syntax` traces to rule 14, including the banned typing names, string constants inside annotations, `typing` imports and `from __future__`.
- `test_dunder_all_lists_exactly_the_public_names_sorted` traces to rule 15. For `__init__` it compares against the `as` names, as stated.
- `test_public_docstrings_with_a_short_first_sentence` traces to rule 16. Dunder methods start with `_` and are exempt.
- `test_function_and_parameter_names_are_snake_case`, `test_class_names_are_capwords_and_exceptions_end_in_error` and `test_module_level_names_are_upper_case_constants` trace to rule 17.
- `test_one_definition_per_top_level_name` traces to rule 18, and `test_classes_only_where_stated` traces to rule 19.
- `test_every_raise_uses_a_package_error` and `test_errors_derive_from_one_base` trace to rule 20. The first needs the bare name imported from `patchwork.errors`, as stated.
- `test_no_broad_or_bare_except` traces to rule 21, and `test_output_only_from_the_cli_module` traces to rule 22.
- `test_model_classes_are_frozen_slotted_dataclasses_or_enums` traces to rule 23. Both decorator spellings are accepted.
- `test_stated_public_signatures` has five cases, and each compares `ast.unparse` text with the brief's "Functions with a fixed signature" bullets character for character. Examples are `(text: str) -> tuple[str, ...]` and `(a: object, b: object, tokens: tuple[str, ...] = ()) -> list[dict[str, object]]`.
- `test_exhaustive_match_over_the_enum` has three cases and traces to rule 24. The subjects `kind` and `op.kind` are named in the rule. Guards, wildcards, captures and non-`OpKind.X` values fail. Members are read from `model.OpKind`.

**Conformance cases.** There are 5 conformance cases. They compare against `_oracle_patch.py` on outcome tuples: the value repr, or the error class name plus message.

- `test_pointer_parsing_matches_the_package` traces to "`pointer.parse_pointer` … as `patchwork.parse_pointer` does today, as a tuple" and to "Every error keeps today's message", with `PointerError` for pointer syntax. That includes non-str input, which raises "pointer must be a string" in the base.
- `test_parse_operation_matches_the_package` traces to "validates one raw operation as the package does today, errors and their order included" and to the `Operation` field definitions. Those definitions fix `source` as `""` when there is no `from`, `value` as the member or `None`, and `index` as the position. I traced the oracle order against the base `_validate` and they agree: not an object, missing op, unknown op, then path (missing, not a string, pointer syntax), then value or from.
- `test_apply_matches_the_package_and_never_mutates_the_input` traces to "Unchanged behaviour" and the error-class mapping. A test failure is `TestFailedError` by class name, which the brief states ("`TestFailed` is `TestFailedError` exported under the old name"). The no-mutation assertion traces to "the copy the input document and every inserted value get".
- `test_diff_matches_the_package` traces to the `diffing.diff` bullet and "the diff's operation order". It compares `repr`, so dict key order inside each op matters. Today's key order is op, path, value, so "returns the raw operations `patchwork.diff` returns today" fixes it.
- `test_exported_functions_match_the_package` traces to the Exports paragraph.

**Independent oracle check.** I ran the fixture's base package against the oracle over 20,000 generated triples using the test's own generators. Each triple covered `apply_patch`, `diff` and `parse_pointer`, with `TestFailed` renamed to `TestFailedError`. The result was 0 mismatches. Seven hand cases also agreed:
- a move inside one array;
- a move onto itself;
- a `true` tested against `1`;
- a `01` index;
- a move into its own child;
- a root move from `""` to `""`;
- the removal of the root.

The oracle therefore encodes today's behaviour plus only the brief's stated class changes. One of those is `not a JSON value` becoming a `PathError`, which the generated JSON documents never reach.

**Rule 18 and the exports.** The brief requires `apply.apply_patch` and `pointer.parse_pointer`, which return a tuple, alongside exports of the same names with different behaviour. Rule 18 then forbids a second top-level definition with those names. This is a puzzle with stated pieces and several solutions. One is facade functions under other names, re-exported with `as` in `__init__` as the reference does. Another is giving `apply.apply_patch` the raw-patch behaviour directly. `apply.apply_patch` is not signature-checked, so the brief leaves the agent free and no hidden choice is graded.

**Minor observation, not a FAIL.** Rule 15 accepts only a plain `__all__ = [...]`. An annotated `__all__: list[str] = [...]` would count as missing. The brief's wording "assigns `__all__` once, to a list literal" makes the plain form the natural reading. Rule 11 separately says "(plain or annotated)", so a literal-minded agent could in principle annotate it. I judge this too remote to fail the task. The author may want "a plain assignment" in rule 15.

No assertion depends on a format detail, ordering or error text the brief leaves open. The brief does not contradict the fixture tests.

## 2. Red then green

Runner: host Python 3, pytest from the user site, with `timeout 300 env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`. Each side ran on a fresh `fixture/` copy under `mktemp -d`. Both manifest entries were copied to `tests/structure/`. The reference applied with `patch -p1 --batch --forward -s` and exited 0, leaving no `.rej` or `.orig`. The copies were deleted afterwards. The image Python was not run here.

```
[base] pytest -q tests --ignore=tests/structure => 49 passed in 0.05s
[base] pytest -q tests/structure                => 39 failed, 1 passed in 0.63s
       (the one pass: test_exported_functions_match_the_package)
patch rc=0
[ref]  pytest -q tests --ignore=tests/structure => 49 passed in 0.05s
[ref]  pytest -q tests/structure                => 40 passed in 0.41s
```

The counts match `success_criterion` exactly: 40 cases (35 rule, 5 conformance), 39 failed and 1 passed at base with the stated base pass, 40 of 40 at reference, and a fixture suite of 49 cases green at both ends. `regression_command` is null, as the refactor type requires. The reference keeps every module at 74 lines or fewer, against a limit of 110.

## 3. Criterion mechanical

PASS.
- **`success_criterion`.** It is one line naming the check file, both overlay dests, the command, the 35/5 split and the counts at both ends (39 failed and 1 passed naming the base-pass case, then 40 of 40). It also names the fixture suite (49) green at both ends.
- **`criterion`.** It is behavioural and names no path or test.
- **`grader_protected`.** It lists `tests/conftest.py`, `tests/test_cli.py`, `tests/test_patch.py` and `tests/test_pointer.py`. That is every fixture test file. The fixture has no ini, pyproject or setup.cfg.
- **`bounds`.** They are exactly `{max_turns: {IMPLEMENT: 80, BARE: 190}, timeout_min: {IMPLEMENT: 35, BARE: 80}}`.
- **Other fields.** `suite_version: 2` is set. `source.kind` is `synthetic` with `date: "2026-10-17"`. `test_command` is the fixture suite with `--ignore=tests/structure`, and `structural_check` names the hidden file.
- **Fixture contents.** A `find` of the fixture finds no cache, no `.pyc`, no dotfile, nothing named `hidden*`, and no `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/`, `.run/` or `.git/`.
- **Overlay dests.** Both are under `tests/`.

## Notes — hardness read (decides nothing)

A bare Opus 5.5 agent with 190 turns and 80 minutes will very likely pass above 0.5. All 24 rules are stated precisely enough to be machine-checked locally, and the behaviour oracle is the old package sitting in the tree, so it can differential-test or simply move code. The author's blind self-solve scored 0.975 in about 3 minutes. The correct change still touches every file, rewriting 9 modules into 14, and the tightest traps are three. The first is the complexity-7 ceiling, which a six-case match fills exactly. The second is rule 18 colliding with the tuple-versus-list `parse_pointer` and the two `apply_patch` shapes. The third is rule 20's bare-name raise, which the self-solver missed. The fixture suite of 49 cases pins the exports and the CLI but does not constrain shortcuts in the layer functions. The generated conformance inputs do cover validation order, `-` and leading-zero indexes, root operations, in-array moves, self-moves and bool-versus-number tests.
