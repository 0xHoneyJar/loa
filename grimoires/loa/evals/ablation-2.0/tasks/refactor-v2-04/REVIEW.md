# Fairness review — refactor-v2-04

**Reviewer:** fairness session R1 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer E2 · **Verdict:** PASS

## 1. No solution leak

PASS. `grep -ri hidden` over `TASK.md` and `fixture/` is empty, and neither names an arm id, a test or the overlay path. Every structural assertion traces to a brief sentence:

- `test_status_is_an_enum_with_the_six_members_in_lifecycle_order` traces to "`Status`, an `enum.Enum` subclass with exactly these members, in this order … Each member's value is its name in lower case".
- `test_no_vocabulary_literal_outside_the_status_module` traces to "no string literal anywhere in the package outside `shipflow.status` equals one of the six words, in any letter case". The test compares the whole literal, so message text that merely contains a word stays legal.
- `test_module_imports_the_enum` (7 cases) traces to "Each of `model`, `transitions`, `billing`, `notify`, `report`, `storage` and `tracking` imports `Status` from `shipflow.status`". The test accepts `from .status import Status` and `from shipflow.status import Status`, which are the two readings of that sentence.
- `test_dispatch_names_every_member_and_has_no_fallback` (3 cases) traces to "Each one names all six members as `Status.<NAME>` in its own body, with no `else:` branch and no catch-all `case`". The test allows `elif`, and it treats a bare capture pattern as a catch-all, which it is.
- `test_a_value_that_is_not_a_member_is_a_type_error` traces to "When the status is not a `Status` member (`None`, or a string like `"pending"`), each raises `TypeError(f"not a Status: {status!r}")` … (for `charge_for` and `message_for`, the shipment's `status`)" and to "A plain string such as `"pending"` is not a status". It builds `Shipment("S1", 1.0, bad)` with the fixture's positional constructor. The brief's "the shipment's `status`" tells the implementer that a shipment can carry a non-member that reaches the dispatch function, so it should not coerce strings on construction.
- `test_shipments_hold_members_everywhere` traces to "A shipment's `status` always holds a `Status` member: a new shipment, after every event, and after loading from storage. `transitions.next_status` takes and returns members". The `from_dict` default of `PENDING` is the fixture's current behaviour.

No assertion depends on a choice the brief leaves open.

## 2. Red then green

Runner: host Python 3.13.5 and pytest 9, `PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`, a fresh `fixture/` copy per side, the manifest file at its `dest`, and the reference applied with `patch -p1` after a clean dry run, leaving no `.orig` or `.rej`.

```
[base] pytest -q tests --ignore=tests/structure => 23 passed in 0.03s
[base] pytest -q tests/structure                => 14 failed in 0.05s
  patching file src/shipflow/billing.py
  patching file src/shipflow/model.py
  patching file src/shipflow/notify.py
  patching file src/shipflow/report.py
  patching file src/shipflow/status.py
  patching file src/shipflow/storage.py
  patching file src/shipflow/tracking.py
  patching file src/shipflow/transitions.py
[ref]  pytest -q tests --ignore=tests/structure => 23 passed in 0.03s
[ref]  pytest -q tests/structure                => 14 passed in 0.03s
```

The counts match `success_criterion`. The structural check fails 14 of 14 at base and passes at the reference. The fixture suite has 23 cases and is green at both ends.

## 3. Criterion mechanical

PASS. `success_criterion` is one line naming the file, the overlay path, both counts and the suite condition. `criterion` is behavioural and names no path or test. `grader_protected` lists `tests/conftest.py` and `tests/test_shipflow.py`, and the fixture has no ini or pyproject. `bounds`, `suite_version: 2`, `source.kind: synthetic` with the date 2026-10-17, and churn of 8 files with +75/−44 all match the rules and the patch. The fixture is 60K and clean. `no-secrets.sh` exits 0.

## Notes

- **Hardness:** moderate and mostly mechanical. The words sit in about 25 places across seven modules, and the fixture suite pins the output text. Examples are `notify.subject`'s `status.upper()` and `report.counts` keyed by words. The traps are the `TypeError` on `"pending"`, which defeats a `str`-mixin compared with `==`, and the no-`else` rule on `notify.message_for`, which today falls through to "cancelled". A bare agent that greps for the six words probably passes.
