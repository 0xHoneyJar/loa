# Fairness review — refactor-v2-02

**Reviewer:** fairness session R1 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer E2 · **Verdict:** PASS

## 1. No solution leak

PASS. `grep -ri hidden` over `TASK.md` and `fixture/` is empty, and neither names an arm id, a test or the overlay path. The brief names the two upward dependencies as facts about today's code. It does not say how to break them. Every structural assertion traces to a brief sentence:

- `test_new_module_defines_its_names` (2 cases) and `test_each_name_is_defined_in_exactly_one_module` trace to the three name lists and "Each name in these three lists is defined (a `def`, a `class` or an assignment at module level) in exactly one module of the package: the one it is listed under".
- `test_pricing_reexports_parsing_names_but_not_rendering_names` traces to "`invoicer.pricing` keeps re-exporting the six parsing names by importing them, so … gives the very same object … It does not provide any rendering name".
- `test_layer_imports_only_lower_layers` (3 cases) traces to "`parsing` imports nothing from the package. `pricing` imports from `parsing` and from no other package module. `rendering` imports only from `parsing` and `pricing`". The rule that `pricing` must import `parsing` follows from the re-export sentence.
- `test_callers_take_each_name_from_its_defining_module` traces to "`api`, `batch` and `cli` get every name from the module that defines it. Nothing they import from `invoicer.pricing`, or read as `pricing.<name>`, is a parsing or rendering name".
- `test_no_function_has_more_than_the_statement_limit` (3 cases) traces to "No function … has more than 15 statements. Count every statement inside the function at any depth …".
- `test_errors_still_come_from_their_layers` traces to "An unknown tax class is still a `ParseError` that names its line. A discount above the subtotal is still a `PricingError` with the same message". Both strings are the fixture's current messages.

No assertion depends on a choice the brief leaves open.

## 2. Red then green

Runner: same as the other reviews in this batch. Host Python 3.13.5 and pytest 9, `PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`, a fresh `fixture/` copy per side, the manifest file at its `dest`, and the reference applied with `patch -p1` after a clean dry run, leaving no `.orig` or `.rej`.

```
[base] pytest -q tests --ignore=tests/structure => 21 passed in 0.02s
[base] pytest -q tests/structure                => 12 failed in 0.11s
  patching file src/invoicer/api.py
  patching file src/invoicer/batch.py
  patching file src/invoicer/cli.py
  patching file src/invoicer/parsing.py
  patching file src/invoicer/pricing.py
  patching file src/invoicer/rendering.py
[ref]  pytest -q tests --ignore=tests/structure => 21 passed in 0.02s
[ref]  pytest -q tests/structure                => 12 passed in 0.03s
```

The counts match `success_criterion`. The structural check fails 12 of 12 at base and passes at the reference. The fixture suite has 21 cases and is green at both ends.

## 3. Criterion mechanical

PASS. `success_criterion` is one line naming the file, the overlay path, both counts and the suite condition. `criterion` is behavioural and names no path or test. `grader_protected` lists `tests/conftest.py` and `tests/test_invoicer.py`, and the fixture has no ini or pyproject. `bounds`, `suite_version: 2`, `source.kind: synthetic` with the date 2026-10-17, and churn of 6 files with +190/−151 all match the rules and the patch. The fixture is 52K and clean. `no-secrets.sh` exits 0.

## Notes

- **Advisory: statement counting.** The test counts every `ast.stmt` node under the function. That includes a docstring, which is an expression statement, and an `elif`, which is a nested `if`. The brief's "count every statement … at any depth" covers both in Python's grammar, but a reader counting by eye may skip the docstring. That matters only for a function at exactly 15. The reference's largest functions sit at 14 and 15: `parsing._field` has 15 with no docstring, and `parse_invoice` has 14 including its docstring. Adding "a docstring counts as one statement" would remove the doubt. This is not a FAIL, because the sentence is literally correct.
- **Hardness:** moderate. The change touches six files and is mostly moved code. The traps are the two upward dependencies: parsing needs the tax-class names without `TAX_RATES`, and pricing must format money without `format_money`. There are also the caller rewrites (`cli` imports `format_money` from `pricing`, and `batch` reads `pricing.parse_invoice`) and splitting `parse_invoice`, which has 47 statements, and `invoice_totals`, which has 22. A bare agent probably finishes but can miss one caller attribute or one count near the limit.
