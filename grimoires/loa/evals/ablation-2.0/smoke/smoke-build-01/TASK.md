# Task: slugify must collapse runs of separators

**Bug (observed):** `slugify("Hello   World")` returns `hello---world`; `slugify("a & b")` returns `a---b`.
**Expected:** any run of separator characters becomes a single hyphen: `hello-world`, `a-b`. The result stays lowercase and still has no leading or trailing hyphen.

The package lives under `src/textkit/`. Fix the bug in place and add a regression test of your own. Run the suite with `python3 -m pytest -q tests`.
