# Task: reject invalid emails in register()

**Bug (observed):** `register("not-an-email", store)` succeeds and stores the record.
**Expected:** `register` raises `ValueError` and stores nothing when the address is invalid. Valid means: exactly one `@`, a non-empty local part, a domain containing at least one `.`, and no whitespace anywhere. `"ann@example.com"` stays valid.

Files: `src/accounts/service.py` (the fix), `tests/test_service.py` (the regression tests). `src/accounts/store.py` is out of scope — do not modify it.
Run the suite with `python3 -m pytest -q tests`.
