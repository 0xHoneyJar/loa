# Task: slugify must collapse runs of separators

**Bug (observed):** `slugify("Hello   World")` returns `hello---world`; `slugify("a & b")` returns `a---b`.
**Expected:** any run of separator characters becomes a single hyphen: `hello-world`, `a-b`.

Files: `src/textkit/slug.py` (the fix), `tests/test_slug.py` (the regression test). Nothing else needs to change.
Run the suite with `python3 -m pytest -q tests`.
