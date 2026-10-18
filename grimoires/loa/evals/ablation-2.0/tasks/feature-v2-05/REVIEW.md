# Fairness review — feature-v2-05

**Reviewer:** fairness session R3 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer E3 (swap round 1) · **Verdict:** PASS

## 1. No solution leak

PASS. `grep -ri hidden TASK.md fixture/` is empty. A wider grep of TASK.md and the fixture for `zq`, `_oracle`, `acceptance` and the arm ids is also empty. TASK.md names no overlay path, no hidden test and no arm. It states 37 numbered rules with every message exact, and every hidden assertion traces to one of them. Both oracle modules were read in full and checked against the brief.

Hand-written cases in `test_zq_jpatch_accept.py`. Each `test_*` case groups helper checks.

- `test_pointers` (line 717): `_h_parse_pointer_tokens` (56) traces to rules 1–3, including `/~01` → `["~1"]` and `/~10` → `["/0"]`. `_h_parse_pointer_errors` (65) traces to rules 1 and 3. `/~/0` is a `~` at the end of a token. The `issubclass` checks trace to the "direct subclass ... not of `PointerError`" sentences. `_h_format_pointer` (74) traces to rule 4. `_h_resolve_object_members_take_any_token` (80) traces to rule 5's object bullet and to rule 6. `_h_resolve_array_index_rules` (90) traces to rule 5's array bullet word for word, including `'/a/'` giving an invalid index `''` and the full pointer in `/a/3/x`. `_h_resolve_through_scalars_and_identity` (101) traces to the scalar bullet and to "returns the value itself (no copy)".
- `test_patch_list_limit_shape_and_members` (726) traces to rules 7, 8 and 9.1–9.6. The same case checks the empty-patch copy rule, "shares no list or object". It also checks `unknown op 5` and `unknown op None` against the `repr` of the member, a `null` value counting as present, and other members being ignored.
- `test_patch_checks_first_atomicity_and_add` (734): `_h_every_operation_is_checked_before_any_is_applied` (153) traces to rule 9's "So a malformed operation 5 is reported even when operation 0 would fail". `_h_inputs_are_never_modified_and_failure_is_atomic` (249) traces to section 2's opening sentence and to rules 10 and 18. `_h_add_*` (162–184) traces to rules 11 and 12. `/a/-/x` traces to "`-` is accepted only as the last token of an `add` path". `/s/k` and `/o/p/q` trace to "A parent that is not an object or array" and to rule 11's walk.
- `test_patch_remove_replace_move_copy` (742) traces to rules 13–16. Moving `/a/0` to `/a/2` and to `/a/-` uses the document after the removal, as rule 15 says. `move` from `/q` to `/q` locates `from` before the same-path check. `''` to `/x` is the stated root case. `/a` to `/ab` is not a token prefix. Copying `/a/l` into `/a/l/0` is allowed because rule 15's child refusal is for `move` only.
- `test_patch_test_and_json_equal` (750) traces to rules 17 and 19. A missing target gives the pointer error, and the root test failure gives `test failed at ''`.
- `test_store_get_and_patch` (755) traces to rules 20 and 22. The history line follows the fixture's documented six-field format with the stated detail `ops=<n>`. The no-op bump and dry run trace to 22.4 and 22.5. `PatchResult` compares equal to a tuple because it is a named tuple.
- `test_store_patch_errors_validation_and_limits` (762) traces to rule 22.1–22.3. The `Conflict` text is `put`'s existing message. The three `result invalid:` messages are the fixture's own `validate_document` messages with the stated prefix. It also traces to rules 21 and 37. `max_ops = 0` gives `max_ops must be a positive integer`, which is what "settable like `max_depth`" yields from `parse_config`, and the test uses `match`, so the `config:1:` prefix is allowed.
- `test_cli_get_and_patch` (769) traces to rules 33, 34 and 36. Exit 3 for an unknown id, exit 4 for the stale `--rev` and exit 5 with `<file>: invalid JSON:` are the fixture's existing CLI behaviour ("as today for `put`").

Hand-written cases in `test_zq_jdiff_accept.py`:

- `test_strict_equal_and_equal_values` (60) traces to rules 23 and 25.
- `test_objects_kinds_escapes_and_copies` (72) traces to rule 26's sorted visit, rule 28's replace cases and the root `""`. It also traces to rule 24's `format_pointer` escaping, with `"/"` for the empty key and `/~0`, and to "every `value` is a deep copy taken from `b`".
- `test_array_kept_pair_has_the_smallest_indexes_into_a` (102), `..._then_has_the_smallest_indexes_into_b` (119) and `test_array_removes_descend_and_adds_ascend` (132) trace to rule 27's three tie levels and its emission order. I recomputed several cases by hand: `["x","x","y"]` → `["y","x","y","y"]` keeps I = (0, 2), J = (1, 2), and `["x"]` → `["x","x"]` keeps J = (0,).
- `test_array_elements_compare_strictly_and_whole` (148) traces to "whole elements are compared with `strict_equal`, and the walk never descends into array elements". `[{"a":1}]` → `[{"a":2}]` is a remove followed by an add, not a nested replace.
- `test_store_revisions_and_revert_errors` (164) traces to rules 30 and 31. A dry run writes no revision. `True`, `"1"`, `None` and `0` give `no revision <repr> of 'doc'`. Delete-then-create forgets the old revisions. A bundle import keeps only the imported revision, at the bundle's rev, which is what the fixture's `Store.load` does. `_revert_errors` (212) traces to rule 32's check order and to the 22.3 validation, with the fixture's `document is 7 bytes, limit 5`. That check builds a second `Store` over the same storage. This works only if the revisions live in the storage, which rule 30 states ("`FileStorage` keeps them ...; the memory storage keeps them in memory").
- `test_store_revert` (198) traces to rule 32. `max_ops=1` does not apply, the int/float type is restored, the detail is `to=<rev> ops=<n>`, and an empty diff still bumps the revision.
- `test_cli_diff_and_revert` (236) traces to rule 35, with the direction "turn revision REV into the current document", and to rule 36. The output is canonical JSON, and its key order `op, path, value` is the same sorted or unsorted.

Conformance cases. Twelve are in the jdiff file and four in the jpatch file, with groups of 2–4 checks each. They compare the implementation to the oracles over seeded inputs. I traced these oracle branches to the brief:

- `_oracle_zq_jpatch.parse` scans pointers character by character. Its rule that `~` must be followed by `0` or `1` matches rule 3's per-token rule, because a `~` before `/` or at the end of the text is "at the end of a token".
- `is_index` and `index_of` follow rule 5. `-` is out of range except for an append, digits must match `[1-9][0-9]*` or `0`, `00`, `-1`, ` 1` and `1.0` are invalid, and the limit is `len` for add and `len - 1` otherwise.
- `put` walks intermediate tokens with the non-add index rule, which is rule 11. A missing member at the last token is fine for add, which sets the member as rule 12 says, and is an error for remove and replace.
- `check` runs the checks in rule 9's order: object, `op`, name, path, from (move and copy only), value (add, replace and test only). The prefix appears only after the name is known.
- `apply_one` for move locates and copies `from`, then runs the equal-token check, then the proper-prefix check, then removes and adds. `copy` adds a deep copy and has no child check. Pointer errors are re-raised as `PatchError` with the prefix. All of this is in rules 15, 16 and the section 2 preamble.
- `equal` treats a bool as equal only to a bool and lets int and float compare by value. That is rule 19.
- `_oracle_zq_jdiff.kept` enumerates the largest k first and the I tuples in `itertools.combinations` order, which is lexicographic. For the first I that embeds, it takes the greedy leftmost J, which is the lexicographically smallest J for that I. That is rule 27's definition exactly.
- `walk` follows rules 25–28 and sorts the union of the names.

`_c_conformance_store_patch` maps an oracle success with a non-object root to `result invalid: document root must be an object`. That is rule 22.3's example. The generated documents stay within the default depth and size limits, and the reference passes deterministically.

The open-choice candidates I checked are all decided by the brief. Error class names are stated, the CLI REV must be an integer for any revision lookup to succeed, the history detail strings are stated, and the import revision follows the fixture's existing `load`. No assertion depends on an ordering, format or message the brief leaves open. TASK.md does not contradict the fixture tests.

## 2. Red then green

PASS. Each side ran on a fresh `fixture/` copy under `mktemp -d`. All four `hidden/manifest.json` entries were copied to their `dest` under `tests/acceptance/`. The runner was host Python 3: `timeout 300 env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`. `patch -p1 --batch --forward -s < hidden/reference.patch` exited 0 with no `.rej` or `.orig` files. The patch touches 10 source files and adds no test file. The copies were deleted afterwards.

```
[base] pytest -q tests                                  => 36 failed, 20 passed in 0.51s
[base] pytest -q tests --ignore=tests/acceptance        => 20 passed in 0.05s
[ref]  patch rc=0, no .rej
[ref]  pytest -q tests                                  => 56 passed in 1.65s
[ref]  pytest -q tests --ignore=tests/acceptance        => 20 passed in 0.06s
[ref]  tests/acceptance/test_zq_jpatch_accept.py        => 12 passed in 1.17s
[ref]  tests/acceptance/test_zq_jdiff_accept.py         => 24 passed in 0.61s
```

These match `success_criterion` exactly. At base, 36 failed and 20 passed. At the reference, 12 of 12, 24 of 24 and 56 of 56 passed. The regression command has 20 cases and is green at both ends. The in-image rerun by the lead is binding.

## 3. Criterion mechanical

PASS.

- `success_criterion` is one line. It names both files, the overlay path with the two oracle modules, the counts at both ends and the regression condition with its case count.
- `criterion` is behavioural and names no path or test.
- `grader_protected` is `[tests/conftest.py, tests/test_cli.py, tests/test_store.py]`. That is every test file in the fixture, which has no `pytest.ini`, `setup.cfg`, `tox.ini` or `pyproject.toml`.
- `bounds` are exactly `{max_turns: {IMPLEMENT: 80, BARE: 190}, timeout_min: {IMPLEMENT: 35, BARE: 80}}`.
- `suite_version` is 2. `source.kind` is `synthetic`, with `date: "2026-10-17"` and an origin line.
- `type` is `feature-build`. `structural_check` and `review_catch` are null. `regression_command` ignores `tests/acceptance`.
- Every manifest `dest` is under `tests/`.
- The fixture holds 14 modules and 3 test files. It has no `__pycache__` or `.pyc`, nothing named `hidden*`, and no `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/`, `.run/` or `.git/`.

## Notes

- **Hardness read:** the correct change touches about 10 files, with three new modules and edits to `store`, `storage`, `history`, `config`, `errors`, `cli` and `__init__`. Two thirds of the hidden cases sit on the declaratively defined diff, whose lex-smallest-I-then-J tie rule defeats a standard LCS backtrack. Rule 29's bound of at most 10 elements invites a brute-force search, and the jpatch conformance batteries punish any single message or check-order slip across a whole grouped case. A careful bare Opus 5.5 agent with 190 turns and 80 minutes can read rule 27 as a definition, brute-force it and self-check, so I expect it to exceed 0.5. The author's blind self-solve scored 36/36 in minutes, which agrees. The likely misses are a DP-backtrack tie variant (17–19 of 24 diff cases fail), keeping revisions in the `Store` instead of the storage (one case), or a `TypeError` on an unhashable `op` value inside the conformance checks.
- The fixture suite does not constrain shortcuts in the new surface. Only the hidden cases do, so the grade rests on the oracles, which I found faithful to the brief.
- This is a hardness concern for the lead's calibration smoke, not a fairness defect. The author's own report says the same for all three delivered tasks.
