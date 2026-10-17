# Fairness review — refactor-v2-01

**Reviewer:** fairness session R1 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer E2 · **Verdict:** PASS

## 1. No solution leak

PASS. `grep -ri hidden` over `TASK.md` and `fixture/` is empty, and neither names an arm id, a test or the overlay path. TASK.md states the target structure, not the patch. Every structural assertion traces to a brief sentence:

- `test_validation_constants_and_signature` (lines 26–33) traces to "defines the module-level constants `MAX_QTY = 999` and `MAX_BULK_QTY = 9999` and the one function `validate_line(sku, qty, *, normalise=False, max_qty=MAX_QTY)`; `normalise` and `max_qty` are keyword-only".
- `test_validate_line_behaviour` (lines 36–54) traces to "returns `(sku, qty)`, with the cleaned SKU when `normalise` is true; cleaning only applies to a string" and to the two message forms. The case `(5, 1)` with `normalise=True` giving `invalid sku: 5` follows from "cleaning only applies to a string". `True` and `2.0` follow from "A quantity is an `int` (a `bool` is not a quantity)". The plain SKU in `invalid quantity for ABC-0001: 0` follows from `<sku>` set against `<repr of the sku>`, and the fixture's seven copies show the same form.
- `test_validate_line_is_defined_once` traces to "`validate_line` is defined exactly once in the package".
- `test_validation_imports_nothing_from_the_package` traces to "`orderdesk.validation` imports nothing from the rest of the package".
- `test_operation_calls_validate_line_directly` (8 cases) traces to the list of eight functions and "in its own body, not through a helper of its module". That sentence also rules out keeping `quotes._line_ok`.
- `test_no_pattern_matching_outside_validation` traces to "no module calls `re.compile`, `re.match` or `re.fullmatch` (or the `match`/`fullmatch` method of a compiled pattern)". The test bans any `.compile`, `.match` or `.fullmatch` attribute call, but the only other `re` use in the fixture is `report.py`'s `re.sub`, which stays legal.
- `test_no_bool_and_no_limit_numbers_outside_validation` traces to "refers to the built-in `bool`, contains the number 999 or 9999" and "A module that needs a limit imports the constant". `quotes.DISCOUNT_STEPS` holds 1000, which is not banned.
- `test_check_messages_are_built_only_in_validation` traces to "or builds the `invalid sku` / `invalid quantity for` messages".

No assertion depends on a choice the brief leaves open.

## 2. Red then green

Runner: host Python 3.13.5 and pytest 9, `PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`, on a fresh `fixture/` copy per side under `mktemp -d`. The manifest file was copied to its `dest`. The reference patch passed a clean `--dry-run` and then applied with `patch -p1 --batch --forward --no-backup-if-mismatch`, exiting 0 and leaving no `.orig` or `.rej` file.

```
[base] pytest -q tests --ignore=tests/structure => 26 passed in 0.02s
[base] pytest -q tests/structure                => 15 failed in 0.06s
  patching file src/orderdesk/orders.py
  patching file src/orderdesk/quotes.py
  patching file src/orderdesk/returns.py
  patching file src/orderdesk/transfers.py
  patching file src/orderdesk/validation.py
[ref]  pytest -q tests --ignore=tests/structure => 26 passed in 0.02s
[ref]  pytest -q tests/structure                => 15 passed in 0.03s
```

The counts match `success_criterion`. The structural check fails 15 of 15 at base and passes at the reference. The fixture suite has 26 cases and is green at both ends.

## 3. Criterion mechanical

PASS. `success_criterion` is one line naming the file, the overlay path, both counts and the suite condition. `criterion` is behavioural and names no path or test. `grader_protected` lists `tests/conftest.py` and `tests/test_orderdesk.py`, which are the fixture's only test files, and the fixture has no ini or pyproject. `bounds` are `{max_turns: {IMPLEMENT: 80}, timeout_min: {IMPLEMENT: 35}}`. `suite_version` is 2, matching the suite file. `source.kind` is `synthetic`, with the authoring date 2026-10-17. The recorded churn, 5 files with +29/−63, matches the reference patch. The fixture is 56K and holds no cache, nothing named `hidden*`, and no `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/`, `.run/` or `.git/`. `no-secrets.sh` exits 0.

## Notes

- **Hardness:** probably easy for a bare agent. The change touches five files with a short mechanical edit, and the fixture suite pins both drifts, so a wrong consolidation shows up red at once. The likely slips are leaving `quotes._line_ok` as a wrapper or keeping a local 999 constant, and the brief names both.
