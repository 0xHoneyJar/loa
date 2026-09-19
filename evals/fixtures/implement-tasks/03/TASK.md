# Task: paginate skips the first item

**Bug (observed):** `paginate(list(range(10)), 1, 3)` returns `[1, 2, 3]`; `paginate(list(range(10)), 4, 3)` returns `[]`.
**Expected:** page 1 is the first `size` items (`[0, 1, 2]`); the last page returns the remainder (`[9]` for page 4); pages past the end return `[]`.

Files: `src/listkit/page.py` (the fix), `tests/test_page.py` (the regression test). Nothing else needs to change.
Run the suite with `python3 -m pytest -q tests`.
