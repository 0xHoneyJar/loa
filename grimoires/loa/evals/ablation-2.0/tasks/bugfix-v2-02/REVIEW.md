# Fairness review — bugfix-v2-02

**Reviewer:** fairness session R2 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer D2 · **Verdict:** PASS

## 1. No solution leak

PASS. `grep -ri hidden` over `TASK.md` and `fixture/` is empty. The only hits in the task directory outside `hidden/` are in `task.yaml`, which is grader-side. TASK.md and the fixture name no overlay path, no hidden test, no defect id and no arm id. The fixture's own test `test_round_trip_of_plain_values` shares a word with the overlay file name, but it is a fixture test that names nothing hidden. The reader's comment "keys are matched case-insensitively, so they are stored in one case" describes the bug as it stands, which a bug-fix task allows. TASK.md describes symptoms and the expected contract, not the patch. Every hidden assertion traces to a brief sentence:

- `test_whitespace_quotes_and_comment_characters_survive` (lines 18–21) traces to "`loads(dumps(config)) == config` for every config ... whatever its values contain (printable characters, spaces, ... quotes, backslashes, `#`, `;`, an empty value)". It also traces to the bug bullet "A value with a trailing space comes back without it, and a value such as `red # blue` comes back as `red`". Only the round trip is asserted. Whether `#first` or `x#y` is quoted is left to the implementer and not checked.
- `test_backslashes_and_control_characters_survive` (lines 24–27) traces to the same "for every config" sentence and to the bullet "The path `C:\new\temp` comes back with a newline and a tab in it". The cases `back\\slash`, `tab\there\t` and `end\` need a one-pass decoder, which follows from "a quoted value is written in double quotes, with the escapes `\\`, `\"`, `\n`, `\t` and `\r`".
- `test_files_round_trip` (lines 30–38) traces to "and `load` after `save` likewise". The byte equality of the second save follows because `load` returns an equal config and `dumps` depends only on the config. The CR value traces to "carriage returns" in the list.
- `test_plain_values_stay_bare` (lines 41–44) traces to "A value that needs none of this is still written bare: `name = alice smith`". The layout matches the fixture's existing `dumps` form. The URL holds none of the listed characters. This case is green at base, as a guard.
- `test_spelling_of_names_survives` (lines 47–54) traces to "with the spelling of every section and key kept" and "compared case-insensitively ... by `keys`". It also traces to the bug bullet "`DisplayName = Al` loads back with the key `displayname`".
- `test_set_matches_names_case_insensitively` (lines 57–65) traces to "`set` on an existing name replaces the value in place and keeps the existing spelling and position; a new key is appended to its section". The `add_section("USER")` check traces to "compared case-insensitively everywhere ... by ... `add_section`".
- `test_bad_escape_is_refused` (lines 68–74) traces to "a backslash followed by anything other than the five escape letters is a `ParseError` with the message `line <n>: bad escape: \<c>`". Both the text and the line number are stated.
- `test_merge_matches_names_case_insensitively` (lines 77–85) traces word for word to the `merge` bullet. Inputs stay unchanged, base keys keep base order and spelling with overlay values, overlay-only keys follow in overlay order, and overlay-only sections come last in overlay spelling.
- `test_merged_config_survives_a_round_trip` (lines 88–96) traces to the bug bullet "saving the result and loading it back fails with `ParseError`". It also traces to the `merge` bullet and to the case-insensitive `get`. The inline comment after `b` is part of the stated file format.
- `test_round_trip_is_stable_for_many_values` (lines 99–106) traces to "for every config". The `dumps(loads(text)) == text` check follows from that equality and from `dumps` depending only on the config.
- `test_merge_of_empty_configs` (lines 109–114) traces to the `merge` bullet. Sections only `overlay` has come last, in `overlay` spelling, and every section of `base` is returned. This case is green at base.

No assertion depends on a format detail, an ordering or an error text the brief leaves open. The brief does not contradict any fixture test. The fixture's parse-error messages are unchanged in the reference, which matches "The existing error messages are unchanged".

## 2. Red then green

Runner: host Python 3, pytest from the user site, `timeout 120 env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`. Each side ran on a fresh `fixture/` copy under `mktemp -d`, with the manifest entry copied to its `dest`. The reference applied with `patch -p1 --batch --forward` and exited 0. The copies were deleted afterwards. The image Python was not run here, so the lead's in-image rerun is binding.

```
[base] pytest -q tests                           => 9 failed, 29 passed in 0.05s
[base] pytest -q tests --ignore=tests/acceptance => 27 passed in 0.03s
  patching file src/kvconf/escape.py
  patching file src/kvconf/model.py
  patching file src/kvconf/reader.py
  patching file src/kvconf/writer.py
  patching file tests/test_regressions.py
[ref]  pytest -q tests                           => 42 passed in 0.04s
[ref]  pytest -q tests --ignore=tests/acceptance => 31 passed in 0.03s
```

The base side matches `success_criterion` exactly: 9 failed and 29 passed, with 27 fixture cases green. All 9 base failures are assertion or `pytest.raises` failures, and there are no collection errors. The reference side shows 42 and 31, not 38 and 27. The difference is exactly the four cases in `tests/test_regressions.py`, which the reference patch adds because TASK.md asks for regression tests. Without that file the reference has 38 passing with the overlay, the 11 hidden cases pass, and the 27 fixture cases pass. The README grading rule counts the hidden file's cases and newly failing fixture cases, so the extra four cases do not change any grade. I read the parenthetical totals as "overlay plus fixture suite" and judge the counts as agreeing. bugfix-v2-01 has the same shape.

## 3. Criterion mechanical

PASS. `success_criterion` is one line. It names the file, the overlay path, the hidden count, the base counts, the reference condition and the regression condition with its case count. `criterion` is behavioural and names no path or test. `grader_protected` lists `tests/conftest.py`, `tests/test_reader.py` and `tests/test_writer_model.py`. Those are every test file in the fixture, and the fixture has no `pytest.ini`, `setup.cfg` or `pyproject.toml`. `bounds` are `{max_turns: {IMPLEMENT: 80, BARE: 190}, timeout_min: {IMPLEMENT: 35, BARE: 80}}`, which are the values the lead stated as correct for suite v2 under DEC-0580. `suite_version` is 2. `source.kind` is `synthetic`, with date 2026-10-17 and an origin line. `type` is `bug-fix`, `structural_check` and `review_catch` are null, and `regression_command` ignores `tests/acceptance` as the README requires. The fixture is 56K across 10 files. It holds no cache, nothing named `hidden*`, and no `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/`, `.run/` or `.git/`. No `no-secrets.sh` was found in the tree, so that scan was not run. The fixture holds only small Python sources with no credentials.

## Notes

- Hardness read: the correct change touches four modules. A local fix leaves a visible hidden case red, for example keeping key spelling in the reader without making `set` and `add_section` case-insensitive, or quoting more values without replacing the chained-replace decoder. Each of the four symptom bullets maps almost one-to-one to a module, and the brief states the merge order and the error text exactly. A bare Opus 5.5 agent with 190 turns will probably pass, so I expect this task to sit near or above the 0.5 calibration line. The likely misses are leaving `add_section` exact-match, or a decoder that mishandles a trailing backslash or `\\n`.
- The reference adds four regression cases of its own. If the lead wants the totals in `success_criterion` to equal the literal reference tail, the totals should read 42 and 31 at the reference, or the parenthetical should say that it excludes the agent's own tests. The grade is the same either way.
- `merge.py` needs no change once the model compares names case-insensitively. That is a real-code shape: the symptom shows in `merge`, but the cause is in the model.
