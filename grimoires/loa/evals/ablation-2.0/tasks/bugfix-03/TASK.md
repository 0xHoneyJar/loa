# Task: the same tag is counted under several spellings

`tagidx` (under `src/tagidx/`) counts free-text tags. The module docstring of `tagidx.keys` defines when two tags are the same tag.

**Bug (observed):**
- `"Café"` typed with a precomposed `é` and `"Café"` typed as `e` plus a combining acute accent are counted as two tags.
- `"Straße"` and `"STRASSE"` are two tags, and so are the full-width `"ＡＢＣ"` and `"abc"`.
- After `add("New  York")` (two spaces), `remove("new york")` returns `False` and the tag stays in the index.

**Expected:** two tags are one tag when they are equal after Unicode compatibility normalisation, full case folding and collapsing every run of whitespace (any Unicode whitespace) to a single space, as the docstring says. Every operation that compares tags (adding, counting, merging, removing) uses that same rule. Keys are stable: the key of a key is itself, and a key is in NFKC form. The label shown for a tag is still the first spelling seen.

Fix the bug in place and add regression tests of your own. Run the suite with `python3 -m pytest -q tests`.
