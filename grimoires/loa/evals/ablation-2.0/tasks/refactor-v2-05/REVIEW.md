# Fairness review — refactor-v2-05

**Reviewer:** fairness session R3 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer F3 (swap round 1) · **Verdict:** PASS

## 1. No solution leak

PASS. `grep -ri hidden TASK.md fixture/` is empty. TASK.md and the fixture name no overlay path, no test name, no oracle file and no arm id. The only near-hit for a wider grep is the word "Restructure" in the brief's opening paragraph. The brief describes the target layout, data model, signatures, error mapping, exports and 24 rules. It does not describe the reference's private helpers.

Every rule case traces to a numbered rule of the brief:

- `test_module_set_is_exactly_the_stated_one` (line 240) traces to "`src/semverkit/` holds exactly these modules and no subpackage" and the layout table.
- `test_init_only_reexports` (245) traces to rule 5. `test_imports_point_strictly_down_the_layers` (255) traces to rule 1 and the layer column. `test_package_imports_use_the_from_module_form` (266) traces to rule 2. `test_imports_only_at_module_top_level` (275) traces to rule 3. `test_no_private_name_imported_across_modules` (285) traces to rule 4.
- `test_module_length_limit` (293) and `test_function_length_limit` (298) trace to rules 6 and 7. The function span is `def` line to `end_lineno`, so decorators are excluded and the docstring counts, as stated.
- `test_branch_complexity_limit` (307) traces to rule 8. `_complexity` (85) counts `If`, `IfExp`, `For`, `While`, `ExceptHandler`, `match_case`, `1 + len(ifs)` per comprehension and `len(values) - 1` per `BoolOp`. `_own_nodes` (71) skips nested defs and classes but walks into lambdas, which is the stated lambda rule.
- `test_nesting_depth_limit` (316) traces to rule 9. `_max_depth` (102) puts a body statement at depth 1 and an `elif` chain at its `if`'s depth. It also reads `else: if` as `elif`, which is more lenient than the brief and so cannot fail a brief-conforming solution.
- `test_parameter_count_limit` (325) traces to rule 10, including `*args`/`**kwargs` counting one each and the leading `self`/`cls` exemption.
- `test_no_module_or_class_state` (335) traces to rule 11. `_constant_value` (178) accepts exactly the stated forms: constants, names, dotted names, a negated constant, tuples of these, and `frozenset` of a display or empty. The class-body branch also accepts a `field(...)` call. Augmented assignment is rejected.
- `test_no_global_nonlocal_or_function_cache` (350) traces to rule 12. `test_every_function_is_fully_annotated` (362) traces to rule 13. `test_annotations_use_builtin_generics_and_union_syntax` (376) traces to rule 14, with the same banned-name list, string-literal ban and `__future__` ban.
- `test_dunder_all_lists_exactly_the_public_names_sorted` (394) traces to rule 15, including the `as` name in `__init__` and assignment-defined names.
- `test_public_docstrings_with_a_short_first_sentence` (411) traces to rule 16: every module, public top-level function and class, and public method, first line at most 72 characters ending with a period.
- `test_function_and_parameter_names_are_snake_case` (431), `test_class_names_are_capwords_and_exceptions_end_in_error` (444) and `test_module_level_names_are_upper_case_constants` (455) trace to rule 17. Parameters being snake_case is stated in the rule.
- `test_one_definition_per_top_level_name` (466) traces to rule 18. `test_classes_only_where_stated` (475) traces to rule 19.
- `test_every_raise_uses_a_package_error` (483) and `test_errors_derive_from_one_base` (498) trace to rule 20. The bare-name requirement means `raise errors.X` fails, which the rule states ("by its bare name").
- `test_no_broad_or_bare_except` (512) traces to rule 21. `test_output_only_from_the_cli_module` (522) traces to rule 22.
- `test_model_classes_are_frozen_slotted_dataclasses_or_enums` (535) traces to rule 23. Both `dataclass(...)` and `dataclasses.dataclass(...)` are accepted, as stated.
- `test_stated_public_signatures` (603, five cases) checks `parse_version`, `compare`, `bump`, `parse_range` and `satisfies` by `ast.unparse` text. Each string equals the brief's "Functions with a fixed signature" text, which says "Write these exactly as shown".
- `test_exhaustive_match_over_the_enum` (611, three cases) traces to rule 24. The subject must be the parameter name, cases must be `Enum.MEMBER` value patterns or `|` alternatives, no guard, and the covered list must equal the members exactly once. The `Prefix` enum has eight members and the complexity limit is 8. The brief's permission to use `|` alternatives makes this satisfiable, and the reference does it by grouping `NONE | EQ`.

The five conformance cases compare against the oracle, which is the reference flattened. Its fidelity to today's package is what matters for a refactor. I ran a differential check of the oracle against the base package through the public API. It covered `valid`, `sort`, `normalize_range`, `satisfies`, `max_satisfying`, `min_satisfying`, `render_table`, `compare` and `bump`. I used the test file's own input generators with a different seed and mapped the base error classes to the brief's new names.

```
checks 174219 diffs 0
```

I also checked five oracle branches by hand against the base code:
- `bump_text` raises "unknown part" before parsing. The base does this at `core.py` lines 119–121.
- `bump` checks the identifier first, then the part. This matches base lines 122–126 before the part branches.
- Release on a non-prerelease raises "already a release". This matches base lines 158–159.
- `satisfies_text` parses the range first, then returns False for a bad version. This matches `ranges.py` lines 190–194.
- `_parsed_pairs` skips bad versions. This matches the `continue` in `_best`.

Each conformance case traces to the brief:

- `test_parse_version_and_compare_match_the_package` (687) traces to "`versions.parse_version` … parses as `semverkit.parse` does today", "`format_version` … gives the canonical text" and "`precedence.compare` … as `semverkit.compare` does". The data model fixes the tuple shapes and int prerelease identifiers that `_plain` compares. The error class names and messages trace to the **Errors** paragraph.
- `test_bump_matches_the_package` (703) traces to "`bumping.bump` … is today's bump on parsed values" and the stated `Part` values. The test builds its argument with `Part(part.value)`.
- `test_parse_range_matches_the_package` (721) compares `format_range(parse_range(t))` text and errors. It traces to the `parse_range`/`format_range` sentences and to the `InvalidRangeError` messages. This is looser than the brief's comparator-order sentence.
- `test_satisfies_matches_the_package` (731) traces to the `matching.satisfies` signature and "Unchanged behaviour", including prerelease matching.
- `test_exported_string_functions_match_the_package` (748) traces to the **Exports** paragraph and "Unchanged behaviour". It compares `type(exc).__name__`. The brief states that `semverkit.InvalidVersion`/`InvalidRange` are the `…Error` classes under the old names. The brief also states that bump errors become `InvalidBumpError`, where the base raises a plain `ValueError`.

No assertion depends on a choice the brief leaves open.

## 2. Red then green

PASS. The proof ran on a fresh `mktemp -d` copy of the fixture with both manifest entries overlaid at `tests/structure/`. The reference applied with `patch -p1 --batch --forward -s`, exit 0, with no `.rej` or `.orig` files. The host had Python 3.13.5 and pytest 9.0.2, and each run used `timeout 300 env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`.

```
[base] tests --ignore=tests/structure  64 passed in 0.05s
[base] tests/structure                 40 failed in 0.49s
[base] tests                           40 failed, 64 passed in 0.55s
[ref]  tests --ignore=tests/structure  64 passed in 0.05s
[ref]  tests/structure                 40 passed in 0.60s
[ref]  tests                           104 passed in 0.56s
```

These counts match `success_criterion` exactly. The structural check is 40 failed at base and 40 passed at the reference, with 35 rule cases and 5 conformance cases. The fixture suite is 64 green at both ends. All five conformance cases fail at base. Four fail because the layer modules do not exist, and the exported-functions case fails because the brief renames the error classes. `regression_command` is null, as a refactor task expects. The reference leaves 12 modules totalling 784 lines.

## 3. Criterion mechanical

PASS.
- **`success_criterion`.** It is one line. It names the check file, both overlay destinations, the command, the 40/40 count split 35/5, red at base with 40 failed, green with the reference, and the 64-case fixture suite green at both ends.
- **`criterion`.** It is behavioural and names no path or test.
- **`grader_protected`.** It lists `tests/conftest.py`, `tests/test_cli.py`, `tests/test_ranges.py` and `tests/test_versions.py`. Those are every fixture test file. The fixture has no `pytest.ini`, `setup.cfg`, `tox.ini` or `pyproject.toml`.
- **`bounds`.** They are `{max_turns: {IMPLEMENT: 80, BARE: 190}, timeout_min: {IMPLEMENT: 35, BARE: 80}}`.
- **Other fields.** `suite_version` is 2. `source.kind` is `synthetic` with date `"2026-10-17"`, an origin line and churn. `type` is `refactor` and `structural_check` names the check file. `regression_command` and `review_catch` are null.
- **Fixture contents.** The fixture holds only `src/semverkit/` with nine modules and `tests/` with four files. It has no cache, nothing named `hidden*`, and no `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/`, `.run/` or `.git/`.
- **Overlay destinations.** Both overlay `dest` values are under `tests/`.

## Notes

- **Hardness read.** A bare Opus 5.5 agent with 190 turns and 80 minutes will very likely pass above 0.5. Every structural rule is stated precisely enough to self-check with a short AST script. The behaviour oracle is the old code in the tree, so the agent can differential-test its rebuild against it. The correct change touches every module: nine are deleted or rewritten into twelve. The fixture suite constrains only the exported behaviour, not the layout. The likely misses are rules checked only by reading: complexity 8 against the 8-member `Prefix` match, rule 15's sorted `__all__` including constants, rule 20's bare-name raise, and rule 9 nesting. The author's blind self-solve scored 40/40 in about four minutes, which agrees with this read.
- **Leniency.** The checker is lenient in two places, and neither can fail a conforming solution. It reads `else: if` as `elif`. It does not check `from sys import stdout` under rule 22.
