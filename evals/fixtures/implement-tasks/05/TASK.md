# Task: dedupe keeps the wrong record

**Bug (observed):** `dedupe([{"id": 1, "v": "a"}, {"id": 1, "v": "b"}], key=lambda r: r["id"])` returns `[{"id": 1, "v": "b"}]`.
**Expected:** the FIRST occurrence wins: `[{"id": 1, "v": "a"}]`. Order of first occurrence is preserved (already the case).

Files: `src/datakit/dedupe.py` (the fix), `tests/test_dedupe.py` (the regression test). Nothing else needs to change.
Run the suite with `python3 -m pytest -q tests`.
