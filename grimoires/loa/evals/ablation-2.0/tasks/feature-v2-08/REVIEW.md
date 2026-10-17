# Fairness review — feature-v2-08

**Reviewer:** fairness session R3 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer E3 (swap round 1) · **Verdict:** PASS

## 1. No solution leak

PASS. `grep -ri hidden TASK.md fixture/` is empty. TASK.md and the fixture name no overlay path, no test name, no oracle module and no arm id. A grep for `zq_`, `acceptance`, `oracle` and the arm ids over TASK.md and the fixture is also empty. The brief states the public API it requires: module names, class and function signatures, the `Rule` attributes and `Decision` fields, the three error classes as `SnapError` subclasses, and every error message verbatim. Every hidden assertion traces to a brief sentence.

**Hand-written cases** (`test_zq_snapx_accept.py`, 39 cases):

- `test_star_question_dots_and_escapes` (98) and `test_trailing_backslashes_and_slash_splitting` (111) trace to G1–G5. The cases include `a[/]b` as two segments, the odd-backslash error with `repr` of the whole pattern, and `\a` as a literal `a`.
- `test_globstar_segments` (122) traces to G7. `**/**` matching `a` follows from "zero or more" for the first `**` and "one or more" for the last one. `a**b`, `**x` and `\*\*` are ordinary stars or literals.
- `test_bracket_members_negation_and_close_first` (135), `test_unterminated_brackets_dashes_and_code_points` (146) and `test_classes_and_class_tokens` (161) trace to B1–B6. `[a\]` is a literal because no unescaped `]` exists (B1, B2). `[--0]` is a range (B4). `[a-\z]` takes an escaped character token as a range end (B2, B4). `[[:alp]` reads as single-character members (B2). `[[:]` is covered by B1 and B2.
- `test_bracket_errors_and_their_order` (178) traces to B4, B5 and B7. Line 183 holds `[[:Alpha:]]`, which is not a class token because B2 requires lowercase letters. Its first `]` closes, and a literal `]` follows. Line 189 holds `[[:foo:]`: the class token consumes the only `]`, so the outer `[` is literal and no class is checked. B1, B2 and B7 ("only an expression that has a closing `]` is checked") make both results derivable. They are precise, not hidden.
- `test_casefold` (192) traces to G6 with its stated examples, `[Z-a]` against `z` included. Non-ASCII characters are never folded.
- `test_rule_lines` (204) and `test_rule_line_errors` (230) trace to R1–R8. The cases cover one `\r` removed per line, so `c\r\r` gives `c\r`. The R2 backslash-parity rule is tested at one, two and three backslashes. `!#w` is negated and not a comment (R3 tests the first character before R4). `!!v` gives pattern `!v`. `a//` is dir_only and unanchored (R5, R7). A pattern stripped by R7 appears in the error `repr` (R8 "for the pattern").
- `test_dir_only_anchoring_and_bases` (240) traces to R7 and R9, including base-prefix matching.
- `test_last_match_and_excluded_ancestors` (262) and `test_file_depth_config_entries_and_case` (283) trace to E1–E5. The cases cover depth order regardless of `add_file` order, a config entry that outranks every rule, a duplicate entry where the first counts, the config rule's fields (E2), no re-inclusion under an excluded ancestor (E4), and exact `fixed` entries under folding (E5).
- `test_snapshot_and_du_apply_rules_files` (307) traces to C2 and C3. A rules file that is itself excluded is still read. The rules file of an excluded directory is never read, so `build/.snapignore` with `[z-a]` and `skip/.snapignore` with `!` raise nothing. The first bad file met in walk order is raised. The output formats are the fixture's own.
- `test_config_keys` (346) traces to C1 and C2, with all four error messages verbatim. Line 365 reads `ok.ignore_file` and `ok.ignore_case == True`. The brief does not name the `Config` attributes. The fixture's `Config` stores every key as a typed attribute of the same name, and C2's `casefold=<ignore_case>` makes the value a bool, so this is the evident convention, not an open choice.
- `test_check_ignore_lines_status_and_directories` (370) and `test_check_ignore_ancestors_config_and_errors` (400) trace to C4 and C5. A trailing `/` or an existing directory makes a path a directory. The output line shape is stated, including `config:<n>:<entry>` and `::\t<path>`. The exit status is 0 or 1. Rules files are read only down to the first excluded ancestor. Line 415 expects the `a` line to stay on stdout before the `sub/.snapignore` error. This follows from C4's per-path reading of rules files and C5's "the lines already printed for earlier paths stay". The `'..' not allowed` message is the fixture's `normalize` text.
- The 15 group cases (434–526) trace to X1–X8. The cases cover `a!(b)c` against `abc`, `!(foo)*` against `foo` and empty alternatives, all quoted in X2 and X5. `@(a[)` is a literal `[` because no `]` follows in the segment (X2 "against the rest of the segment", B1). `@(**)` follows X6. The error order follows B7's examples verbatim. The rules-file `!` handling follows X8.
- The 6 brace cases (539–608) trace to BR1–BR8 and R4a. `{1..010}` gives width 3 and `{-01..1}` gives `-01 000 001` (BR4). `{1...3}`, `{a..b..c}`, `{ab..c}`, `{a,{b}` and the escape forms stay literal (BR1, BR3, BR5, section 3a "never removes a backslash"). `{a,a}`×9 is counted before de-duplication (BR8). R4a gives the line's shared `text` and `negated` and the first bad string in expansion order. `test_match_command` traces to C6: validation precedes printing, and the PATH error after printed lines follows C5.

**Conformance cases** (`test_zq_snapgen_accept.py`, 21 cases) compare the implementation with `_oracle_zq_snap.py` on fixed-seed samples, exact error messages included. Nine oracle rules sampled against the brief:

1. `_bracket_tokens` (43): the first member `]` is kept, a class token needs lowercase letters, an escape is a character token, and a missing `]` returns literal. This matches B1–B3.
2. `_members` (75): a range is a character token, an unescaped `-`, then a character token, and is consumed left to right. Escaped ends are allowed. Errors are raised in token order. This matches B4, B5 and B7.
3. `_char_ok` (106): it tests the character and its ASCII other-case form against a literal or any member, and negation applies after folding. This matches G6 and B6, including "`[!a]` matches neither".
4. `_in_item` and `_in_plus` (211, 201): these implement the X4 sets. `!` is the complement of *U*. `+` is concatenations of one or more. `*` and `?` add the empty string. `_in_seq` (185) enumerates every cut, matching X5.
5. `glob_match` (229, line 237): `**` takes at least one segment only as the last segment of a multi-segment pattern. This matches G7.
6. `compile_glob` (170): it checks every segment for a trailing backslash before parsing, and treats `**` as special only when it is the whole segment. This matches G4, B7 and X6.
7. `_sequence` (291): the integer and letter forms, a zero step stays literal, `abs(S)`, and padding to the signed width. This matches BR3–BR5.
8. `_expand_raw` and `expand` (332, 359): a non-forming `{` rescans from the next character, the leftmost braces vary slowest, the limit is counted on the raw list, and duplicates are removed at the end. This matches BR5–BR8.
9. `parse_rules` (370) and `check` (428): the R2 parity loop, the R3 and R4 order, per-string R5–R8 after expansion, depth order, `fixed` first, and ancestors judged as directories shallowest first. This matches R1–R8 and E1–E4.

`_model_walk` loads the root and each entered directory's rules file before judging its children, and never loads the file of an excluded directory. This matches C2. Two points are worth noting, but neither is open. R9 compares the base prefix exactly even under folding, and the oracle does the same. Rules files are read with universal newlines, but no walker sample has a lone `\r`, so that choice is not tested.

## 2. Red then green

PASS. Fresh `mktemp -d` copies of `fixture/` with the three manifest files overlaid under `tests/acceptance/`. `patch -p1 --batch --forward -s < hidden/reference.patch` exits 0, with no `.rej` or `.orig`. The reference touches `braces.py`, `glob.py`, `ignore.py`, `rules.py` (all new), `cli.py`, `config.py`, `errors.py`, `walker.py` and `__init__.py`.

```
base full        60 failed, 27 passed in 1.02s
base regression  27 passed in 0.03s
ref full         87 passed in 0.88s
ref regression   27 passed in 0.04s
ref acceptance   60 passed in 0.86s
```

These counts equal `success_criterion`: 39 + 21 = 60 hidden cases, red 60/27 at base, 87/87 with the reference, and the 27-case regression green at both ends. The copies were removed with `find -mindepth 1 -delete`.

## 3. Criterion mechanical

PASS.

- `success_criterion` is one line. It names both overlay files and the oracle, the overlay directory, the counts at both ends (60/60, 87/87, base 60 failed and 27 passed) and the regression condition.
- `criterion` is behavioural and names no path or test.
- `grader_protected` is `[tests/conftest.py, tests/test_snapkit.py]`. These are the only fixture test files, and the fixture has no ini, `pyproject.toml` or `setup.cfg`.
- `bounds` is `{max_turns: {IMPLEMENT: 80, BARE: 190}, timeout_min: {IMPLEMENT: 35, BARE: 80}}`.
- `suite_version: 2`, `source.kind: synthetic` and `date: "2026-10-17"` are set.
- The fixture holds no `__pycache__`, `.pyc`, `.pytest_cache`, nothing named `hidden*`, no `.claude/`, no `CLAUDE.md`, no `.loa.config.yaml`, no `grimoires/`, no `.run/` and no `.git/`.
- Every manifest `dest` is under `tests/acceptance/`.

## Notes — hardness read (decides nothing)

The correct change spans four new modules and five edited ones, about 730 reference lines. The conformance cases cover many edge classes exactly, error text and error order included: first-member `]`, class-token consumption, escaped range ends, fold-then-negate, complement groups over every cut with empty pieces, brackets inside groups, brace rescans, padding and the pre-dedup limit, and the R2 parity rule. The fixture suite constrains nothing new, so it blocks no shortcut. Even so, every rule is stated mechanically with worked examples, and a brute-force cut matcher is a natural thing to write. The author's blind Opus solve scored 60/60 in minutes, so I expect a bare agent with 190 turns and 80 minutes to pass well above 0.5. The calibration smoke decides.
