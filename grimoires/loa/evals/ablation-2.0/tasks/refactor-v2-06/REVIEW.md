# Fairness review — refactor-v2-06

**Reviewer:** fairness session R3 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer F3 (swap round 1) · **Verdict:** PASS

## 1. No solution leak

PASS. `grep -ri hidden TASK.md fixture/` is empty, with exit 1. Neither the brief nor the fixture names an arm id, a test name, the overlay path or the oracle. The reference's helper names, such as `fires_text` and `month_grid`, appear only in the patch and the oracle.

**Every rule case traces to a numbered rule.** I read each of the 35 rule cases against the brief:

- `test_module_set_is_exactly_the_stated_one` (line 241) traces to the layout table and to "exactly these modules and no subpackage". The fixture suite imports only `cronplan` and `cronplan.cli.main`, so deleting the old modules does not break it.
- The four import cases (lines 256–291) trace to rules 1–4. A top-level `if TYPE_CHECKING:` import fails, which matches rule 3's "never inside … `if`". `from cronplan import X` fails, which matches rule 2.
- `test_init_only_reexports` (line 246) traces to rule 5.
- The module-size case traces to rule 6. The function-size case measures `def` line to `end_lineno`, which excludes decorators, so it traces to rule 7.
- `_complexity` (line 86) traces to rule 8. It skips nested defs and classes, walks into lambdas and adds `len(values) - 1` per `BoolOp`. The limit is binding. `special_matches` has six cases, which already score 7, so any `and` in a case body must move into a helper. Rule 8 states the arithmetic, so this follows from the brief.
- `_max_depth` (line 103) traces to rule 9. A match counts one deeper, its case bodies are blocks inside it, an elif keeps its if's depth, and `else: if` is treated as an elif, which is lenient.
- `_param_count` (line 131) traces to rule 10.
- `test_no_module_or_class_state` with `_constant_value` (line 179) traces to rule 11. It allows dotted names, unary minus on a constant, tuples and `frozenset` of set, list or tuple displays, or `frozenset()`, and `field(...)` in class bodies. It rejects calls, dicts and augmented assignment.
- The global/nonlocal/cache case traces to rule 12, and the two annotation cases trace to rules 13 and 14. The `typing` name list and the `__future__` ban are the brief's exact list.
- `test_dunder_all_lists_exactly_the_public_names_sorted` (line 395) traces to rule 15. In `__init__` it reads the `as` name.
- The docstring case traces to rule 16. The three naming cases (lines 432–464) trace to rule 17, including snake_case parameters and UPPER_CASE module names.
- The one-definition, class-location, raise, error-base, except and output cases (lines 467–533) trace to rules 18–22. The raise case needs the bare imported name, which matches "by its bare name".
- `test_model_classes_are_frozen_slotted_dataclasses_or_enums` (line 536) traces to rule 23.
- `test_stated_public_signatures`, with 5 cases (line 604), compares `ast.unparse` text with the five signatures written in the brief. The brief says "exactly as shown" and "`datetime` is imported as a module".
- `test_exhaustive_match_over_the_enum`, with 3 cases (line 612), traces to rule 24. The subject text must be `kind` or `special.kind`, the patterns must be `Enum.MEMBER` value patterns, there are no guards, and the sorted coverage must equal the member list.

**The conformance cases trace to the data model and to the unchanged-behaviour paragraph.**
- `_plain` (line 632) compares fields by `kind.value`, sorted `values`, `specials` order and `starred`. It compares special days by `kind.value`, `number` and `nth`. Every one of these is stated in the "Data model" bullets: the enum values, the weekday 7 stored as 0, the member-then-number-then-ordinal order without repeats, and `starred` meaning the text starts with `*` or `?`.
- `_outcome` compares the error class name and message. This traces to "Every error keeps today's class and message" and the class mapping.
- The exported case passes a string to `cronplan.next_fire`, `fires` and `matches`. `search.next_fire` takes a `Schedule`, and rule 18 forbids a second top-level `next_fire`, so `__init__` must re-export a facade function under an `as` name. Rule 15 names that form, so this is discoverable and not hidden.

**The oracle matches the base.** I checked `_oracle_cron.py` against the fixture's own internals, independently of the author. I compared 20,000 generated fields through `parser.parse_field` and 5,000 generated expressions through `parser.parse`. For each valid expression I also checked 20 days through `schedule.day_ok` and one moment through `schedule._next`. The generators were the hidden test's own. There were 0 diffs, covering values, the special order, `starred`, error classes, messages, error order, the AND/OR day rule and the horizon. The exported-behaviour case passing at base covers `normalize`, `fires`, `matches`, `month_report` and the naive and aware `next_fire` probes. The branches I sampled were the `L-n` offset limit, `nW` range, `#` ordinal before value, `?` outside day fields, and step-from-single-value. Each matches the base code and a phrase of the "Unchanged behaviour" paragraph.

## 2. Red then green

PASS. The runner was host Python 3.13.5 with `timeout 300 env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`. Each side used a fresh `fixture/` copy under `mktemp -d`, with both manifest files at `tests/structure/`. `patch -p1 --batch --forward` exited 0 on 21 files and left no `.rej` or `.orig`. The copies were deleted afterwards.

```
[base] tests --ignore=tests/structure => 39 passed in 0.04s
[base] tests/structure                => 39 failed, 1 passed in 0.60s
[ref]  tests --ignore=tests/structure => 39 passed in 0.04s
[ref]  tests/structure                => 40 passed in 0.68s
[ref]  tests (both together)          => 79 passed in 0.62s
```

The counts match `success_criterion`. The one base pass is `test_exported_functions_match_the_package`, as stated. `regression_command` is null, as it should be for a refactor.

## 3. Criterion mechanical

PASS.
- `success_criterion` is one line. It names the file, both overlay paths, 40/40, 35 rule cases and 5 conformance cases, the base count of 39 failed and 1 passed with the reason, and the 39-case suite green at both ends.
- `criterion` is behavioural and names no path or test.
- `grader_protected` lists `tests/conftest.py`, `tests/test_cli.py`, `tests/test_fire.py` and `tests/test_parse.py`. Those are every fixture test file, and the fixture has no ini, pyproject or setup.cfg.
- `bounds` are `{max_turns: {IMPLEMENT: 80, BARE: 190}, timeout_min: {IMPLEMENT: 35, BARE: 80}}`.
- `suite_version: 2`, `source.kind: synthetic` and `date: "2026-10-17"` are as the rules say.
- The churn of 21 files, +643 and −454 matches the patch.
- The fixture is 76K. It holds no cache, nothing named `hidden*`, no `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/`, `.run/` or `.git/`.
- Both overlay `dest`s are under `tests/`.

## Notes

- **Advisory: export aliasing.** The string forms of `next_fire`, `fires` and `matches` must come from the facade under other names and be re-exported with `as`. This follows from rules 15 and 18 and the `search` signature, but no sentence says it outright. A careless agent that defines `facade.next_fire` fails only rule 18, the one-definition case. This is not a FAIL.
- **Advisory: the raise rule is strict.** `from cronplan.errors import ArgumentError as AE` with `raise AE(...)` fails the raise case. This matches "by its bare name".
- **Hardness:** likely easy for a bare agent. Every rule is stated mechanically, so an agent can write its own AST checker. The old code in the tree is a complete behaviour oracle for differential testing. The author's blind self-solve scored 40/40 in 3.6 minutes. The correct change touches 21 files, and the likely misses are rules checked only by reading, such as the binding complexity limit of 7 on the six-case match or the nesting limit. A pass rate above 0.5 over 190 turns and 80 minutes is the expected outcome, so this task probably fails the a0_bare ≤ 0.5 hardness bar.
